package recognition

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

const smartLayoutOCRConcurrency = 3

type SmartLayouter interface {
	Layout(context.Context, SmartLayoutRequest) (SmartLayoutResponse, error)
	RecognizeBlock(context.Context, SmartLayoutInkBlock) (SmartLayoutRecognizedBlock, error)
	Compose(context.Context, SmartLayoutComposeRequest) (SmartLayoutResponse, error)
}

type OpenAICompatibleConfig struct {
	BaseURL string
	APIKey  string
	Model   string
	Timeout time.Duration
}

type OpenAICompatibleSmartLayouter struct {
	config OpenAICompatibleConfig
	client *http.Client
}

func NewOpenAICompatibleSmartLayouter(config OpenAICompatibleConfig) *OpenAICompatibleSmartLayouter {
	timeout := config.Timeout
	if timeout <= 0 {
		timeout = 60 * time.Second
	}
	return &OpenAICompatibleSmartLayouter{
		config: config,
		client: &http.Client{Timeout: timeout},
	}
}

func (l *OpenAICompatibleSmartLayouter) Layout(ctx context.Context, request SmartLayoutRequest) (SmartLayoutResponse, error) {
	if strings.TrimSpace(l.config.BaseURL) == "" ||
		strings.TrimSpace(l.config.APIKey) == "" ||
		strings.TrimSpace(l.config.Model) == "" {
		return SmartLayoutResponse{}, errors.New("AI smart layout is not configured")
	}
	recognized := l.recognizeBlocks(ctx, request.Blocks)
	return l.Compose(ctx, SmartLayoutComposeRequest{
		Pages:  request.Pages,
		Blocks: recognized,
	})
}

func (l *OpenAICompatibleSmartLayouter) RecognizeBlock(ctx context.Context, block SmartLayoutInkBlock) (SmartLayoutRecognizedBlock, error) {
	return l.recognizeBlock(ctx, block)
}

func (l *OpenAICompatibleSmartLayouter) Compose(ctx context.Context, request SmartLayoutComposeRequest) (SmartLayoutResponse, error) {
	pages := l.decidePages(ctx, request.Pages, request.Blocks)
	document := buildSmartLayoutDocument(request.Blocks, pages, request.Pages)
	return SmartLayoutResponse{Document: document, Blocks: request.Blocks, Pages: pages}, nil
}

func (l *OpenAICompatibleSmartLayouter) recognizeBlocks(ctx context.Context, blocks []SmartLayoutInkBlock) []SmartLayoutRecognizedBlock {
	results := make([]SmartLayoutRecognizedBlock, len(blocks))
	sem := make(chan struct{}, smartLayoutOCRConcurrency)
	var wg sync.WaitGroup
	for i, block := range blocks {
		i, block := i, block
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			result, err := l.recognizeBlock(ctx, block)
			if err != nil {
				result = SmartLayoutRecognizedBlock{
					ID:           block.ID,
					PageID:       block.PageID,
					Type:         "error",
					Bounds:       block.Bounds,
					StrokeBounds: block.StrokeBounds,
					StartedAt:    block.StartedAt,
					Error:        err.Error(),
				}
			}
			results[i] = result
		}()
	}
	wg.Wait()
	return results
}

func (l *OpenAICompatibleSmartLayouter) recognizeBlock(ctx context.Context, block SmartLayoutInkBlock) (SmartLayoutRecognizedBlock, error) {
	mime := strings.TrimSpace(block.ImageMime)
	if mime == "" {
		mime = "image/png"
	}
	content := []map[string]any{
		{
			"type": "text",
			"text": "Recognize this handwritten ink block. Return strict JSON only: {\"type\":\"text|formula\",\"text\":\"...\",\"latex\":\"...\"}. Use formula only for mathematical expressions. For formula, put the LaTeX source text in both text and latex.",
		},
		{
			"type": "image_url",
			"image_url": map[string]any{
				"url": "data:" + mime + ";base64," + block.ImageBase64,
			},
		},
	}
	body, err := l.chatBody(content, 0)
	if err != nil {
		return SmartLayoutRecognizedBlock{}, err
	}
	responseBody, err := l.postChat(ctx, body)
	if err != nil {
		return SmartLayoutRecognizedBlock{}, err
	}
	rawContent, err := openAIMessageContent(responseBody)
	if err != nil {
		return SmartLayoutRecognizedBlock{}, err
	}
	var raw struct {
		Type  string `json:"type"`
		Text  string `json:"text"`
		LaTeX string `json:"latex"`
	}
	if err := json.Unmarshal([]byte(smartLayoutJSONContent(rawContent)), &raw); err != nil {
		return SmartLayoutRecognizedBlock{}, err
	}
	resultType := normalizeOCRType(raw.Type)
	text := strings.TrimSpace(raw.Text)
	latex := strings.TrimSpace(raw.LaTeX)
	if resultType == "formula" && latex == "" {
		latex = text
	}
	if resultType == "formula" {
		text = latex
	}
	if resultType == "text" && text == "" {
		return SmartLayoutRecognizedBlock{}, errors.New("AI OCR returned empty text")
	}
	if resultType == "formula" && latex == "" {
		return SmartLayoutRecognizedBlock{}, errors.New("AI OCR returned empty formula")
	}
	return SmartLayoutRecognizedBlock{
		ID:           block.ID,
		PageID:       block.PageID,
		Type:         resultType,
		Text:         text,
		LaTeX:        latex,
		Bounds:       block.Bounds,
		StrokeBounds: block.StrokeBounds,
		StartedAt:    block.StartedAt,
	}, nil
}

func normalizeOCRType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "formula", "math", "latex":
		return "formula"
	default:
		return "text"
	}
}

func (l *OpenAICompatibleSmartLayouter) decidePages(ctx context.Context, pages []SmartLayoutPage, blocks []SmartLayoutRecognizedBlock) []SmartLayoutPageDecision {
	blocksByPage := map[string][]SmartLayoutRecognizedBlock{}
	for _, block := range blocks {
		if block.Error != "" {
			continue
		}
		blocksByPage[block.PageID] = append(blocksByPage[block.PageID], block)
	}
	decisions := make([]SmartLayoutPageDecision, 0, len(pages))
	for _, page := range pages {
		pageBlocks := blocksByPage[page.ID]
		sortRecognizedBlocks(pageBlocks)
		decision := SmartLayoutPageDecision{
			PageID:     page.ID,
			Mode:       "in_place",
			Paragraphs: singleBlockParagraphs(pageBlocks),
		}
		if len(pageBlocks) >= 2 {
			if aiDecision, err := l.decidePage(ctx, page, pageBlocks); err == nil {
				decision = sanitizePageDecision(page.ID, pageBlocks, aiDecision)
			}
		}
		decisions = append(decisions, decision)
	}
	return decisions
}

func (l *OpenAICompatibleSmartLayouter) decidePage(ctx context.Context, page SmartLayoutPage, blocks []SmartLayoutRecognizedBlock) (SmartLayoutPageDecision, error) {
	type decisionBlock struct {
		ID        string    `json:"id"`
		Type      string    `json:"type"`
		Text      string    `json:"text"`
		LaTeX     string    `json:"latex,omitempty"`
		Bounds    InkBounds `json:"bounds"`
		StartedAt int64     `json:"startedAt,omitempty"`
	}
	payload := struct {
		Page   SmartLayoutPage `json:"page"`
		Blocks []decisionBlock `json:"blocks"`
	}{Page: page}
	for _, block := range blocks {
		payload.Blocks = append(payload.Blocks, decisionBlock{
			ID:        block.ID,
			Type:      block.Type,
			Text:      block.Text,
			LaTeX:     block.LaTeX,
			Bounds:    block.Bounds,
			StartedAt: block.StartedAt,
		})
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return SmartLayoutPageDecision{}, err
	}
	content := []map[string]any{
		{
			"type": "text",
			"text": "Decide whether these recognized handwriting blocks form one continuous article. Return strict JSON only: {\"pageId\":\"...\",\"mode\":\"article|in_place\",\"paragraphs\":[[\"blockId\"]]}. Use article only when the blocks read as a continuous complete article. Group block ids into paragraphs. Do not invent ids or text.\nInput:\n" + string(payloadJSON),
		},
	}
	body, err := l.chatBody(content, 0)
	if err != nil {
		return SmartLayoutPageDecision{}, err
	}
	responseBody, err := l.postChat(ctx, body)
	if err != nil {
		return SmartLayoutPageDecision{}, err
	}
	rawContent, err := openAIMessageContent(responseBody)
	if err != nil {
		return SmartLayoutPageDecision{}, err
	}
	var decision SmartLayoutPageDecision
	if err := json.Unmarshal([]byte(smartLayoutJSONContent(rawContent)), &decision); err != nil {
		return SmartLayoutPageDecision{}, err
	}
	return decision, nil
}

func (l *OpenAICompatibleSmartLayouter) chatBody(content []map[string]any, temperature float64) ([]byte, error) {
	return json.Marshal(map[string]any{
		"model": l.config.Model,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": "You are a handwriting OCR assistant for a whiteboard app. Return strict JSON only.",
			},
			{
				"role":    "user",
				"content": content,
			},
		},
		"temperature":      temperature,
		"reasoning_effort": "minimal",
	})
}

func (l *OpenAICompatibleSmartLayouter) postChat(ctx context.Context, body []byte) ([]byte, error) {
	endpoint := strings.TrimRight(l.config.BaseURL, "/") + "/chat/completions"
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpRequest.Header.Set("Content-Type", "application/json")
	httpRequest.Header.Set("Authorization", "Bearer "+l.config.APIKey)
	response, err := l.client.Do(httpRequest)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf(
			"AI smart layout failed: HTTP %d: %s",
			response.StatusCode,
			strings.TrimSpace(string(responseBody)),
		)
	}
	return responseBody, nil
}

func sanitizePageDecision(pageID string, blocks []SmartLayoutRecognizedBlock, decision SmartLayoutPageDecision) SmartLayoutPageDecision {
	ids := map[string]bool{}
	for _, block := range blocks {
		ids[block.ID] = true
	}
	mode := strings.ToLower(strings.TrimSpace(decision.Mode))
	if mode != "article" {
		mode = "in_place"
	}
	seen := map[string]bool{}
	paragraphs := make([][]string, 0, len(decision.Paragraphs))
	for _, paragraph := range decision.Paragraphs {
		clean := []string{}
		for _, id := range paragraph {
			if ids[id] && !seen[id] {
				clean = append(clean, id)
				seen[id] = true
			}
		}
		if len(clean) > 0 {
			paragraphs = append(paragraphs, clean)
		}
	}
	for _, block := range blocks {
		if !seen[block.ID] {
			paragraphs = append(paragraphs, []string{block.ID})
		}
	}
	if mode == "in_place" {
		paragraphs = singleBlockParagraphs(blocks)
	}
	return SmartLayoutPageDecision{PageID: pageID, Mode: mode, Paragraphs: paragraphs}
}

func singleBlockParagraphs(blocks []SmartLayoutRecognizedBlock) [][]string {
	paragraphs := make([][]string, 0, len(blocks))
	for _, block := range blocks {
		if block.Error == "" {
			paragraphs = append(paragraphs, []string{block.ID})
		}
	}
	return paragraphs
}

func buildSmartLayoutDocument(blocks []SmartLayoutRecognizedBlock, pages []SmartLayoutPageDecision, pageRequests []SmartLayoutPage) SmartLayoutDocument {
	blockByID := map[string]SmartLayoutRecognizedBlock{}
	for _, block := range blocks {
		if block.Error == "" {
			blockByID[block.ID] = block
		}
	}
	writingModeByPage := map[string]string{}
	pageByID := map[string]SmartLayoutPage{}
	for _, page := range pageRequests {
		writingModeByPage[page.ID] = smartLayoutWritingModeForTemplate(page.Template)
		pageByID[page.ID] = page
	}
	docBlocks := []SmartLayoutBlock{}
	order := 0
	for _, page := range pages {
		for _, paragraph := range page.Paragraphs {
			sourceIDs := []string{}
			sourceBlocks := []SmartLayoutRecognizedBlock{}
			var bounds *InkBounds
			blockType := "paragraph"
			latex := ""
			writingMode := writingModeByPage[page.PageID]
			if writingMode == "" {
				writingMode = "horizontal"
			}
			for _, id := range paragraph {
				block, ok := blockByID[id]
				if !ok {
					continue
				}
				sourceIDs = append(sourceIDs, id)
				sourceBlocks = append(sourceBlocks, block)
				if bounds == nil {
					copyBounds := block.Bounds
					bounds = &copyBounds
				} else {
					merged := unionInkBounds(*bounds, block.Bounds)
					bounds = &merged
				}
				if block.Type == "formula" {
					blockType = "math"
					value := block.LaTeX
					if strings.TrimSpace(value) == "" {
						value = block.Text
					}
					latex = strings.TrimSpace(value)
				}
			}
			text := formatSmartLayoutParagraph(sourceBlocks, pageByID[page.PageID], writingMode)
			if text == "" {
				continue
			}
			docBlocks = append(docBlocks, SmartLayoutBlock{
				ID:          fmt.Sprintf("block-%d", order),
				Type:        blockType,
				Text:        text,
				LaTeX:       latex,
				PageID:      page.PageID,
				Bounds:      bounds,
				Order:       order,
				WritingMode: writingMode,
				SourceIDs:   sourceIDs,
			})
			order++
		}
	}
	return SmartLayoutDocument{
		Version:     1,
		GeneratedAt: time.Now().UnixMilli(),
		Blocks:      docBlocks,
	}
}

type smartLayoutLine struct {
	Blocks []SmartLayoutRecognizedBlock
	Bounds InkBounds
}

func formatSmartLayoutParagraph(blocks []SmartLayoutRecognizedBlock, page SmartLayoutPage, writingMode string) string {
	if len(blocks) == 0 {
		return ""
	}
	sorted := append([]SmartLayoutRecognizedBlock(nil), blocks...)
	sortRecognizedBlocks(sorted)
	if writingMode != "vertical" {
		sorted = expandSmartLayoutInternalLines(sorted)
		sortRecognizedBlocks(sorted)
	}
	if writingMode == "vertical" {
		parts := make([]string, 0, len(sorted))
		for _, block := range sorted {
			if text := smartLayoutBlockText(block); text != "" {
				parts = append(parts, text)
			}
		}
		return strings.TrimSpace(strings.Join(parts, "\n"))
	}

	lines := groupSmartLayoutLines(sorted)
	if len(lines) == 0 {
		return ""
	}
	lineHeight := medianSmartLayoutLineHeight(lines)
	if lineHeight <= 0 {
		lineHeight = 32
	}
	charWidth := lineHeight * 0.45
	if charWidth < 8 {
		charWidth = 8
	}
	baseLeft := smartLayoutTextBaseLeft(page, lines)
	out := []string{}
	var previous *smartLayoutLine
	for i := range lines {
		line := lines[i]
		if previous != nil {
			gap := line.Bounds.Y - (previous.Bounds.Y + previous.Bounds.Height)
			blankLines := int(gap/lineHeight + 0.5)
			if blankLines > 1 {
				for b := 0; b < minInt(blankLines-1, 4); b++ {
					out = append(out, "")
				}
			}
		}
		text := formatSmartLayoutLine(line, baseLeft, charWidth)
		if text != "" {
			out = append(out, text)
		}
		previous = &line
	}
	return trimSmartLayoutDocumentText(strings.Join(out, "\n"))
}

func expandSmartLayoutInternalLines(blocks []SmartLayoutRecognizedBlock) []SmartLayoutRecognizedBlock {
	expanded := make([]SmartLayoutRecognizedBlock, 0, len(blocks))
	for _, block := range blocks {
		text := smartLayoutBlockText(block)
		textLines := smartLayoutTextLines(text)
		if len(textLines) <= 1 || len(block.StrokeBounds) <= 1 {
			expanded = append(expanded, block)
			continue
		}
		geometryLines := groupSmartLayoutStrokeBounds(block.StrokeBounds)
		if len(geometryLines) == 0 {
			expanded = append(expanded, block)
			continue
		}
		for i, lineText := range textLines {
			lineText = strings.TrimRight(lineText, " \t")
			if strings.TrimSpace(lineText) == "" {
				continue
			}
			lineBlock := block
			lineBlock.Text = lineText
			if block.Type == "formula" {
				lineBlock.LaTeX = lineText
			}
			lineBlock.Bounds = geometryLines[minInt(i, len(geometryLines)-1)].Bounds
			lineBlock.StrokeBounds = nil
			lineBlock.StartedAt = block.StartedAt + int64(i)
			expanded = append(expanded, lineBlock)
		}
	}
	return expanded
}

func smartLayoutTextLines(text string) []string {
	normalized := strings.ReplaceAll(text, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	if !strings.Contains(normalized, "\n") {
		return []string{strings.TrimSpace(normalized)}
	}
	return strings.Split(normalized, "\n")
}

func groupSmartLayoutStrokeBounds(bounds []InkBounds) []smartLayoutLine {
	strokes := append([]InkBounds(nil), bounds...)
	sort.SliceStable(strokes, func(i, j int) bool {
		a, b := strokes[i], strokes[j]
		if a.Y != b.Y {
			return a.Y < b.Y
		}
		return a.X < b.X
	})
	lines := []smartLayoutLine{}
	for _, stroke := range strokes {
		if stroke.Width <= 0 || stroke.Height <= 0 {
			continue
		}
		centerY := stroke.Y + stroke.Height/2
		if len(lines) == 0 {
			lines = append(lines, smartLayoutLine{Bounds: stroke})
			continue
		}
		last := &lines[len(lines)-1]
		lastCenterY := last.Bounds.Y + last.Bounds.Height/2
		threshold := maxFloat(minFloat(last.Bounds.Height, stroke.Height)*0.7, 12)
		if absFloat(centerY-lastCenterY) <= threshold {
			last.Bounds = unionInkBounds(last.Bounds, stroke)
		} else {
			lines = append(lines, smartLayoutLine{Bounds: stroke})
		}
	}
	return lines
}

func groupSmartLayoutLines(blocks []SmartLayoutRecognizedBlock) []smartLayoutLine {
	lines := []smartLayoutLine{}
	for _, block := range blocks {
		if smartLayoutBlockText(block) == "" {
			continue
		}
		centerY := block.Bounds.Y + block.Bounds.Height/2
		if len(lines) == 0 {
			lines = append(lines, smartLayoutLine{Blocks: []SmartLayoutRecognizedBlock{block}, Bounds: block.Bounds})
			continue
		}
		last := &lines[len(lines)-1]
		lastCenterY := last.Bounds.Y + last.Bounds.Height/2
		threshold := maxFloat(minFloat(last.Bounds.Height, block.Bounds.Height)*0.7, 12)
		if absFloat(centerY-lastCenterY) <= threshold {
			last.Blocks = append(last.Blocks, block)
			last.Bounds = unionInkBounds(last.Bounds, block.Bounds)
			sortSmartLayoutLineBlocks(last.Blocks)
		} else {
			lines = append(lines, smartLayoutLine{Blocks: []SmartLayoutRecognizedBlock{block}, Bounds: block.Bounds})
		}
	}
	return lines
}

func medianSmartLayoutLineHeight(lines []smartLayoutLine) float64 {
	heights := make([]float64, 0, len(lines))
	for _, line := range lines {
		if line.Bounds.Height > 0 {
			heights = append(heights, line.Bounds.Height)
		}
	}
	if len(heights) == 0 {
		return 0
	}
	sort.Float64s(heights)
	return heights[len(heights)/2]
}

func smartLayoutTextBaseLeft(page SmartLayoutPage, lines []smartLayoutLine) float64 {
	if len(page.Anchors) > 0 {
		left := 0.0
		found := false
		for _, anchor := range page.Anchors {
			x, ok := smartLayoutNumber(anchor["x"])
			if !ok {
				continue
			}
			if !found || x < left {
				left = x
				found = true
			}
		}
		if found {
			return left
		}
	}
	left := lines[0].Bounds.X
	for _, line := range lines[1:] {
		if line.Bounds.X < left {
			left = line.Bounds.X
		}
	}
	return left
}

func formatSmartLayoutLine(line smartLayoutLine, baseLeft float64, charWidth float64) string {
	if len(line.Blocks) == 0 {
		return ""
	}
	sortSmartLayoutLineBlocks(line.Blocks)
	indent := int((line.Bounds.X-baseLeft)/charWidth + 0.5)
	indent = minInt(maxInt(indent, 0), 24)
	var builder strings.Builder
	builder.WriteString(strings.Repeat(" ", indent))
	prevRight := 0.0
	hasText := false
	for _, block := range line.Blocks {
		text := smartLayoutBlockText(block)
		if text == "" {
			continue
		}
		if hasText {
			gap := block.Bounds.X - prevRight
			spaces := 1
			if gap > charWidth {
				spaces = minInt(maxInt(int(gap/charWidth+0.5), 1), 12)
			}
			builder.WriteString(strings.Repeat(" ", spaces))
		}
		builder.WriteString(text)
		prevRight = block.Bounds.X + block.Bounds.Width
		hasText = true
	}
	if !hasText {
		return ""
	}
	return strings.TrimRight(builder.String(), " \t")
}

func sortSmartLayoutLineBlocks(blocks []SmartLayoutRecognizedBlock) {
	sort.SliceStable(blocks, func(i, j int) bool {
		a, b := blocks[i], blocks[j]
		if a.Bounds.X != b.Bounds.X {
			return a.Bounds.X < b.Bounds.X
		}
		return a.StartedAt < b.StartedAt
	})
}

func smartLayoutNumber(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case json.Number:
		parsed, err := typed.Float64()
		return parsed, err == nil
	default:
		return 0, false
	}
}

func smartLayoutBlockText(block SmartLayoutRecognizedBlock) string {
	if block.Type == "formula" {
		value := strings.TrimSpace(block.LaTeX)
		if value == "" {
			value = strings.TrimSpace(block.Text)
		}
		return value
	}
	return strings.TrimSpace(block.Text)
}

func trimSmartLayoutDocumentText(text string) string {
	text = strings.TrimRight(text, " \t\r\n")
	for strings.HasPrefix(text, "\n") {
		text = strings.TrimPrefix(text, "\n")
	}
	return text
}

func smartLayoutWritingModeForTemplate(template string) string {
	switch strings.ToLower(strings.TrimSpace(template)) {
	case "narrowverticalline", "wideverticalline", "ancientbook":
		return "vertical"
	default:
		return "horizontal"
	}
}

func sortRecognizedBlocks(blocks []SmartLayoutRecognizedBlock) {
	sort.SliceStable(blocks, func(i, j int) bool {
		a, b := blocks[i], blocks[j]
		if a.Bounds.Y != b.Bounds.Y {
			return a.Bounds.Y < b.Bounds.Y
		}
		if a.Bounds.X != b.Bounds.X {
			return a.Bounds.X < b.Bounds.X
		}
		return a.StartedAt < b.StartedAt
	})
}

func unionInkBounds(a, b InkBounds) InkBounds {
	left := minFloat(a.X, b.X)
	top := minFloat(a.Y, b.Y)
	right := maxFloat(a.X+a.Width, b.X+b.Width)
	bottom := maxFloat(a.Y+a.Height, b.Y+b.Height)
	return InkBounds{X: left, Y: top, Width: right - left, Height: bottom - top}
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func absFloat(value float64) float64 {
	if value < 0 {
		return -value
	}
	return value
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func smartLayoutJSONContent(content string) string {
	content = strings.TrimSpace(content)
	if !strings.HasPrefix(content, "```") {
		return content
	}
	content = strings.TrimPrefix(content, "```")
	if newline := strings.IndexByte(content, '\n'); newline >= 0 {
		content = content[newline+1:]
	}
	content = strings.TrimSpace(content)
	content = strings.TrimSuffix(content, "```")
	return strings.TrimSpace(content)
}

func openAIMessageContent(body []byte) (string, error) {
	var raw struct {
		Choices []struct {
			Message struct {
				Content any `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return "", err
	}
	if len(raw.Choices) == 0 {
		return "", errors.New("AI smart layout returned no choices")
	}
	switch content := raw.Choices[0].Message.Content.(type) {
	case string:
		return strings.TrimSpace(content), nil
	case []any:
		var builder strings.Builder
		for _, item := range content {
			part, ok := item.(map[string]any)
			if !ok {
				continue
			}
			if text, ok := part["text"].(string); ok {
				builder.WriteString(text)
			}
		}
		text := strings.TrimSpace(builder.String())
		if text != "" {
			return text, nil
		}
	}
	return "", errors.New("AI smart layout returned empty content")
}
