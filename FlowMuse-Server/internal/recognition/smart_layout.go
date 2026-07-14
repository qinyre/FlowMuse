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
	pages := l.decidePages(ctx, request.Pages, recognized)
	document := buildSmartLayoutDocument(recognized, pages)
	return SmartLayoutResponse{Document: document, Blocks: recognized, Pages: pages}, nil
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
					ID:        block.ID,
					PageID:    block.PageID,
					Type:      "error",
					Bounds:    block.Bounds,
					StartedAt: block.StartedAt,
					Error:     err.Error(),
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
			"text": "Recognize this handwritten ink block. Return strict JSON only: {\"type\":\"text|formula\",\"text\":\"...\",\"latex\":\"...\"}. Use formula only for mathematical expressions. For formula, put LaTeX in latex and a readable text in text.",
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
	if resultType == "text" && text == "" {
		return SmartLayoutRecognizedBlock{}, errors.New("AI OCR returned empty text")
	}
	if resultType == "formula" && latex == "" {
		return SmartLayoutRecognizedBlock{}, errors.New("AI OCR returned empty formula")
	}
	return SmartLayoutRecognizedBlock{
		ID:        block.ID,
		PageID:    block.PageID,
		Type:      resultType,
		Text:      text,
		LaTeX:     latex,
		Bounds:    block.Bounds,
		StartedAt: block.StartedAt,
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

func buildSmartLayoutDocument(blocks []SmartLayoutRecognizedBlock, pages []SmartLayoutPageDecision) SmartLayoutDocument {
	blockByID := map[string]SmartLayoutRecognizedBlock{}
	for _, block := range blocks {
		if block.Error == "" {
			blockByID[block.ID] = block
		}
	}
	docBlocks := []SmartLayoutBlock{}
	order := 0
	for _, page := range pages {
		for _, paragraph := range page.Paragraphs {
			parts := []string{}
			sourceIDs := []string{}
			var bounds *InkBounds
			blockType := "paragraph"
			latex := ""
			for _, id := range paragraph {
				block, ok := blockByID[id]
				if !ok {
					continue
				}
				sourceIDs = append(sourceIDs, id)
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
					parts = append(parts, latex)
				} else {
					parts = append(parts, strings.TrimSpace(block.Text))
				}
			}
			text := strings.TrimSpace(strings.Join(parts, "\n"))
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
				WritingMode: "horizontal",
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
