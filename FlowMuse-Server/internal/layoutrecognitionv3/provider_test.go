package layoutrecognitionv3

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"strconv"
	"strings"
	"testing"
	"testing/iotest"
	"time"
)

func TestOpenAICompatProviderReasoningEffort(t *testing.T) {
	for _, model := range []string{"doubao-seed-2-1-turbo-260628", "other-compatible-model", "ep-model-alias"} {
		t.Run(model, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost || r.URL.Path != "/chat/completions" ||
					r.Header.Get("Authorization") != "Bearer test-key" {
					t.Error("请求方法、路径或鉴权头错误")
				}
				var payload map[string]any
				if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
					t.Error("请求 JSON 无法解析")
					w.WriteHeader(http.StatusBadRequest)
					return
				}
				if payload["model"] != model || payload["temperature"] != float64(0) {
					t.Error("不得更换模型或温度")
				}
				effort, present := payload["reasoning_effort"]
				if model == "doubao-seed-2-1-turbo-260628" {
					if effort != "minimal" {
						t.Error("已验证的豆包型号应使用 minimal")
					}
				} else if present {
					t.Error("其他兼容模型不得收到未经验证的思考参数")
				}
				if _, present := payload["max_tokens"]; present {
					t.Error("本次优化不得新增输出截断上限")
				}
				messages, _ := payload["messages"].([]any)
				if len(messages) != 1 {
					t.Error("应保留单条多模态消息")
				} else {
					message, _ := messages[0].(map[string]any)
					content, _ := message["content"].([]any)
					if message["role"] != "user" || len(content) != 2 {
						t.Error("提示词与附图不得丢失")
					} else {
						text, _ := content[0].(map[string]any)
						image, _ := content[1].(map[string]any)
						imageURL, _ := image["image_url"].(map[string]any)
						if text["text"] != "synthetic-prompt" || imageURL["url"] != "data:image/png;base64,synthetic-image" {
							t.Error("多模态内容被改动")
						}
					}
				}
				if _, present := payload["stage"]; present {
					t.Error("日志阶段不得进入模型协议")
				}
				_, _ = io.WriteString(w, `{"choices":[{"message":{"content":"synthetic-result"}}]}`)
			}))
			defer server.Close()
			provider := NewOpenAICompatProvider(server.URL, "test-key", model)
			output, err := provider.Complete(context.Background(), ProviderRequest{
				Stage: StageRead, PromptText: "synthetic-prompt",
				Images: []ProviderImage{{Base64: "synthetic-image"}},
			})
			if err != nil || output != "synthetic-result" {
				t.Fatal("provider 未保留原有结果")
			}
		})
	}
}

type providerRoundTripFunc func(*http.Request) (*http.Response, error)

func (f providerRoundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestOpenAICompatProviderTimingAndErrors(t *testing.T) {
	const sensitive = "test-secret-marker"
	const validResponse = `{"choices":[{"message":{"content":"` + sensitive + `"}}]}`
	for _, test := range []struct {
		name, phase string
		reached     int // 0=无连接，1=获连接，2=发完，3=首字节。
		status      int
		body        string
		failure     error
		readFailure bool
		writeFailed bool
	}{
		{name: "连接超时", phase: "connect", failure: context.DeadlineExceeded},
		{name: "发送失败", phase: "send", reached: 1, failure: io.ErrClosedPipe, writeFailed: true},
		{name: "首字节等待超时", phase: "wait", reached: 2, failure: context.DeadlineExceeded},
		{name: "等待时取消", phase: "wait", reached: 2, failure: context.Canceled},
		{name: "接收超时", phase: "receive", reached: 3, status: 200, failure: context.DeadlineExceeded, readFailure: true},
		{name: "上游错误状态", phase: "parse", reached: 3, status: 503, body: sensitive},
		{name: "无效JSON", phase: "parse", reached: 3, status: 200, body: sensitive},
		{name: "成功", phase: "done", reached: 3, status: 200, body: validResponse},
	} {
		t.Run(test.name, func(t *testing.T) {
			var logs bytes.Buffer
			previous := log.Writer()
			log.SetOutput(&logs)
			defer log.SetOutput(previous)
			provider := NewOpenAICompatProvider("http://example.invalid/"+sensitive, sensitive, "doubao-seed-2-1-turbo-260628")
			provider.client.Transport = providerRoundTripFunc(func(r *http.Request) (*http.Response, error) {
				trace := httptrace.ContextClientTrace(r.Context())
				if trace == nil {
					t.Fatal("真实 HTTP 请求缺少 trace")
				}
				if test.reached >= 1 {
					trace.GotConn(httptrace.GotConnInfo{Reused: true})
				}
				if test.writeFailed {
					trace.WroteRequest(httptrace.WroteRequestInfo{Err: test.failure})
				}
				if test.reached >= 2 {
					trace.WroteRequest(httptrace.WroteRequestInfo{})
				}
				if test.reached >= 3 {
					trace.GotFirstResponseByte()
				}
				if test.failure != nil && !test.readFailure {
					return nil, test.failure
				}
				var body io.Reader = strings.NewReader(test.body)
				if test.readFailure {
					body = iotest.ErrReader(test.failure)
				}
				return &http.Response{StatusCode: test.status, Body: io.NopCloser(body), Header: make(http.Header)}, nil
			})
			_, err := provider.Complete(context.Background(), ProviderRequest{
				Stage: sensitive, PromptText: sensitive, Images: []ProviderImage{{Base64: sensitive}},
			})
			if test.failure != nil && !errors.Is(err, test.failure) {
				t.Fatal("底层取消、超时或传输错误必须可追溯")
			}
			if (err == nil) != (test.phase == "done") {
				t.Fatal("成功/失败语义被改变")
			}
			if err != nil {
				var transport *ProviderTransportError
				if !errors.As(err, &transport) {
					t.Fatal("错误必须保持现有 provider 包装")
				}
			}
			line := logs.String()
			for _, expected := range []string{
				"[recognition-v3] provider stage=unknown effort=minimal phase=" + test.phase,
				"http_status=" + strconv.Itoa(test.status),
				"ok=" + strconv.FormatBool(err == nil),
				"timeout=" + strconv.FormatBool(errors.Is(test.failure, context.DeadlineExceeded)),
				"canceled=" + strconv.FormatBool(errors.Is(test.failure, context.Canceled)),
			} {
				if !strings.Contains(line, expected) {
					t.Errorf("日志缺少 %s", expected)
				}
			}
			if strings.Contains(line, sensitive) {
				t.Error("日志泄漏地址、密钥、阶段注入值、提示词或模型正文")
			}
			fields := make(map[string]string)
			for _, field := range strings.Fields(line) {
				if key, value, ok := strings.Cut(field, "="); ok {
					fields[key] = value
				}
			}
			for index, key := range []string{"connect_ms", "send_ms", "wait_ms", "receive_ms"} {
				value, parseErr := strconv.Atoi(fields[key])
				if parseErr != nil || (index > test.reached && value != -1) || (index <= test.reached && value < 0) {
					t.Errorf("%s 未正确区分已进入与未进入阶段", key)
				}
			}
		})
	}
}

func TestOpenAICompatProviderRealHTTPTimeout(t *testing.T) {
	for _, receive := range []bool{false, true} {
		t.Run(strconv.FormatBool(receive), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = io.Copy(io.Discard, r.Body)
				if receive {
					w.WriteHeader(http.StatusOK)
					w.(http.Flusher).Flush()
				}
				<-r.Context().Done()
			}))
			defer server.Close()
			provider := NewOpenAICompatProvider(server.URL, "test-key", "other-model")
			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()
			_, err := provider.Complete(ctx, ProviderRequest{Stage: StageRead, PromptText: "synthetic"})
			if !errors.Is(err, context.DeadlineExceeded) {
				t.Fatal("真实 HTTP 首字节/响应体等待未遵守 deadline")
			}
			if wire := providerWireError(err); wire.Code != CodeProviderTimeout {
				t.Fatal("对客户端的超时错误码被改变")
			}
		})
	}
}
