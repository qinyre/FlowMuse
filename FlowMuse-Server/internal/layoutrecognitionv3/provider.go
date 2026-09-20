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
	"log"
	"net/http"
	"net/http/httptrace"
	"strings"
	"sync"
	"time"
)

// ProviderImage 是提示词附图（PNG base64，无 data URL 前缀）。
type ProviderImage struct {
	Base64 string
}

// ProviderRequest 是一次模型调用：提示词文本 + 按序附图。
type ProviderRequest struct {
	Stage      string // 仅用于耗时日志，不发送给模型。
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
func (p *OpenAICompatProvider) Complete(ctx context.Context, req ProviderRequest) (output string, err error) {
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
	payload := map[string]any{
		"model":       p.model,
		"temperature": 0,
		"messages": []map[string]any{
			{
				"role":    "user",
				"content": content,
			},
		},
	}
	effort := "default"
	// 只对已实测支持 minimal 的部署型号启用，不向其他兼容模型强塞参数。
	if p.model == "doubao-seed-2-1-turbo-260628" {
		effort = "minimal"
		payload["reasoning_effort"] = effort
	}
	body, err := json.Marshal(payload)
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
	started := time.Now()
	var mu sync.Mutex // httptrace 回调可能并发，甚至在请求结束后到达。
	var connected, written, firstByte, bodyRead time.Time
	var reused bool
	var status, responseBytes int
	trace := &httptrace.ClientTrace{
		GotConn: func(info httptrace.GotConnInfo) {
			mu.Lock()
			defer mu.Unlock()
			if connected.IsZero() {
				connected, reused = time.Now(), info.Reused
			}
		},
		WroteRequest: func(info httptrace.WroteRequestInfo) {
			mu.Lock()
			defer mu.Unlock()
			if info.Err == nil && written.IsZero() {
				written = time.Now()
			}
		},
		GotFirstResponseByte: func() {
			mu.Lock()
			defer mu.Unlock()
			if firstByte.IsZero() {
				firstByte = time.Now()
			}
		},
	}
	httpReq = httpReq.WithContext(httptrace.WithClientTrace(ctx, trace))
	defer func() {
		ended := time.Now()
		mu.Lock()
		defer mu.Unlock()
		milliseconds := func(from, to time.Time) int64 {
			if from.IsZero() {
				return -1 // 尚未进入该阶段，不能误记为耗时零。
			}
			if to.IsZero() {
				to = ended
			}
			return max(0, to.Sub(from).Milliseconds())
		}
		phase := "connect"
		if !connected.IsZero() {
			phase = "send"
		}
		if !written.IsZero() {
			phase = "wait"
		}
		if !firstByte.IsZero() {
			phase = "receive"
		}
		if !bodyRead.IsZero() {
			phase = "parse"
		}
		if err == nil {
			phase = "done"
		}
		stage := req.Stage
		if stage != StageRead && stage != StageVerify && stage != StageStructure {
			stage = "unknown"
		}
		// 首字节等待包含网络、上游排队及生成；不等同于纯模型推理。
		// 仅记录固定标签和数值，不记录地址、密钥、提示词或模型正文。
		log.Printf("[recognition-v3] provider stage=%s effort=%s phase=%s http_status=%d reused=%t connect_ms=%d send_ms=%d wait_ms=%d receive_ms=%d total_ms=%d response_bytes=%d ok=%t timeout=%t canceled=%t",
			stage, effort, phase, status, reused,
			milliseconds(started, connected), milliseconds(connected, written),
			milliseconds(written, firstByte), milliseconds(firstByte, bodyRead),
			ended.Sub(started).Milliseconds(), responseBytes, err == nil,
			errors.Is(err, context.DeadlineExceeded), errors.Is(err, context.Canceled))
	}()
	resp, err := p.client.Do(httpReq)
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	defer resp.Body.Close()
	status = resp.StatusCode
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	responseBytes = len(respBody)
	if err != nil {
		return "", &ProviderTransportError{Err: err}
	}
	bodyRead = time.Now()
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
