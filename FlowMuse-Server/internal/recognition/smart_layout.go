package recognition

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

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
	payload, err := json.Marshal(request)
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	body, err := json.Marshal(map[string]any{
		"model": l.config.Model,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": "You convert whiteboard ink/text into a structured document. Return strict JSON only.",
			},
			{
				"role": "user",
				"content": []map[string]any{
					{
						"type": "text",
						"text": smartLayoutPrompt(string(payload)),
					},
				},
			},
		},
		"temperature":      0,
		"reasoning_effort": "minimal",
	})
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	endpoint := strings.TrimRight(l.config.BaseURL, "/") + "/chat/completions"
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	httpRequest.Header.Set("Content-Type", "application/json")
	httpRequest.Header.Set("Authorization", "Bearer "+l.config.APIKey)
	response, err := l.client.Do(httpRequest)
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return SmartLayoutResponse{}, fmt.Errorf(
			"AI smart layout failed: HTTP %d: %s",
			response.StatusCode,
			strings.TrimSpace(string(responseBody)),
		)
	}
	content, err := openAIMessageContent(responseBody)
	if err != nil {
		return SmartLayoutResponse{}, err
	}
	content = smartLayoutJSONContent(content)
	var result SmartLayoutResponse
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		var document SmartLayoutDocument
		if docErr := json.Unmarshal([]byte(content), &document); docErr != nil {
			return SmartLayoutResponse{}, err
		}
		result = SmartLayoutResponse{Document: document}
	}
	if result.Document.Version == 0 {
		result.Document.Version = 1
	}
	if result.Document.GeneratedAt == 0 {
		result.Document.GeneratedAt = time.Now().UnixMilli()
	}
	return result, nil
}

func smartLayoutPrompt(payload string) string {
	return `Input JSON contains page anchors, ink strokes, existing text, and retained context elements.
Return JSON shaped exactly as:
{"document":{"version":1,"generatedAt":0,"blocks":[{"id":"...","type":"paragraph|heading|math","text":"...","latex":"...","pageId":"...","bounds":{"x":0,"y":0,"width":100,"height":30},"order":0,"writingMode":"horizontal|vertical"}]}}
Use page anchors to choose bounds. Include existing text in reading order. Do not include highlighter/image/shape context as text unless it is necessary for ordering.
Input:
` + payload
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
