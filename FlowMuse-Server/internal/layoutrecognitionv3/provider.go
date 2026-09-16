// provider.go：上游模型 seam（spec §4）。OpenAICompatProvider 用 std
// net/http 直连 chat/completions，多模态 image 内容（base64 data URL），
// 超时与取消走 ctx；不 import 旧包算法。
package layoutrecognitionv3

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// ProviderImage 是提示词附图（PNG base64，无 data URL 前缀）。
type ProviderImage struct {
	Base64 string
}

// ProviderRequest 是一次模型调用：提示词文本 + 按序附图。
type ProviderRequest struct {
	PromptText string
	Images     []ProviderImage
}

// RecognitionProvider 是上游模型 seam；测试注入确定性 fake。
type RecognitionProvider interface {
	Complete(ctx context.Context, req ProviderRequest) (string, error)
}

// ProviderTransportError 表示 provider 传输层/5xx 失败（retryable）；
// 与模型输出解析失败（invalidProviderResponse，不可重试）区分。
type ProviderTransportError struct {
	Err error
}

func (e *ProviderTransportError) Error() string {
	return "provider 传输失败: " + e.Err.Error()
}

func (e *ProviderTransportError) Unwrap() error { return e.Err }

// OpenAICompatProvider 直连 OpenAI 兼容 chat/completions。
type OpenAICompatProvider struct {
	baseURL string
	apiKey  string
	model   string
	client  *http.Client
}

// NewOpenAICompatProvider 构造 provider；三项配置缺一返回 nil
// （路由层据此返回 503 unconfigured）。http.Client 不设全局超时——
// 超时与取消全部由调用方 ctx 控制。
func NewOpenAICompatProvider(baseURL, apiKey, model string) *OpenAICompatProvider {
	if strings.TrimSpace(baseURL) == "" ||
		strings.TrimSpace(apiKey) == "" ||
		strings.TrimSpace(model) == "" {
		return nil
	}
	return &OpenAICompatProvider{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:  strings.TrimSpace(apiKey),
		model:   strings.TrimSpace(model),
		client:  &http.Client{},
	}
}

// Configured 报告 provider 是否可用（nil-safe）。
func (p *OpenAICompatProvider) Configured() bool {
	return p != nil
}

// Complete 执行一次 chat/completions 调用，返回首条 message.content。
func (p *OpenAICompatProvider) Complete(ctx context.Context, req ProviderRequest) (string, error) {
	content := make([]map[string]any, 0, len(req.Images)+1)
	content = append(content, map[string]any{
		"type": "text",
		"text": req.PromptText,
	})
	for _, image := range req.Images {
		content = append(content, map[string]any{
			"type": "image_url",
			"image_url": map[string]any{
				"url": "data:image/png;base64," + image.Base64,
			},
		})
	}
	body, err := json.Marshal(map[string]any{
		"model":       p.model,
		"temperature": 0,
		"messages": []map[string]any{
			{
				"role":    "user",
				"content": content,
			},
		},
	})
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	httpReq, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		p.baseURL+"/chat/completions",
		bytes.NewReader(body),
	)
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	resp, err := p.client.Do(httpReq)
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", &ProviderTransportError{Err: fmt.Errorf(
			"provider HTTP %d: %.200s", resp.StatusCode, string(respBody))}
	}
	content0, err := chatContentOf(respBody)
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	return content0, nil
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func chatContentOf(body []byte) (string, error) {
	var parsed chatCompletionResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", err
	}
	if len(parsed.Choices) == 0 {
		return "", errors.New("provider 响应缺少 choices")
	}
	return parsed.Choices[0].Message.Content, nil
}

// stripCodeFence 容忍 ```json 围栏：一次确定性剥离（spec §4 Handler 行）。
func stripCodeFence(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if !strings.HasPrefix(trimmed, "```") {
		return trimmed
	}
	// 剥离起始围栏行（```json / ```）与结尾围栏。
	firstNewline := strings.IndexByte(trimmed, '\n')
	if firstNewline < 0 {
		return trimmed
	}
	inner := trimmed[firstNewline+1:]
	if strings.HasSuffix(inner, "```") {
		inner = inner[:len(inner)-3]
	}
	return strings.TrimSpace(inner)
}

// 编译期保证默认实现满足 seam。
var _ RecognitionProvider = (*OpenAICompatProvider)(nil)
