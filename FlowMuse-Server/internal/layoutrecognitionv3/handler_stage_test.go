package layoutrecognitionv3

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeProvider 是确定性注入 seam：按序返回预设输出/错误，记录调用数。
type fakeProvider struct {
	mu        sync.Mutex
	responses []string
	errs      []error
	calls     int
	delay     time.Duration
	block     chan struct{}
	lastReq   ProviderRequest
}

func (f *fakeProvider) Complete(ctx context.Context, req ProviderRequest) (string, error) {
	f.mu.Lock()
	f.calls++
	index := f.calls - 1
	f.lastReq = req
	delay := f.delay
	block := f.block
	f.mu.Unlock()
	if block != nil {
		select {
		case <-block:
		case <-ctx.Done():
			return "", &ProviderTransportError{Err: ctx.Err()}
		}
	}
	if delay > 0 {
		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return "", &ProviderTransportError{Err: ctx.Err()}
		}
	}
	if index < len(f.errs) && f.errs[index] != nil {
		return "", f.errs[index]
	}
	if index < len(f.responses) {
		return f.responses[index], nil
	}
	return "{}", nil
}

func (f *fakeProvider) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

func readRequestBody(stage string) string {
	return `{
		"schemaVersion": "recognition-v3/1",
		"stage": "` + stage + `",
		"operationId": "op-1",
		"requestId": "req-1",
		"pageId": "page-1",
		"sceneRevision": {"epoch": 0, "revision": 5, "fingerprint": "0123456789abcdef"},
		"contentFingerprint": "fedcba9876543210",
		"generation": 0,
		"regions": [
			{"regionId": "r:a", "imagePngBase64": "` + tinyPngBase64 + `", "imageScale": 2.5},
			{"regionId": "r:b", "imagePngBase64": "` + tinyPngBase64 + `", "imageScale": 2.5}
		]
	}`
}

func structureRequestBody() string {
	return `{
		"schemaVersion": "recognition-v3/1",
		"stage": "structure",
		"operationId": "op-2",
		"requestId": "req-2",
		"pageId": "page-1",
		"sceneRevision": {"epoch": 0, "revision": 5, "fingerprint": "0123456789abcdef"},
		"contentFingerprint": "fedcba9876543210",
		"generation": 0,
		"units": [
			{"unitId": "u-title", "kind": "typed", "text": "标题", "bounds": {"left": 0, "top": 0, "width": 100, "height": 40}, "roleHint": "title"},
			{"unitId": "u-i1", "kind": "ink", "text": "1. 第一项", "bounds": {"left": 0, "top": 50, "width": 200, "height": 24}},
			{"unitId": "u-i2", "kind": "ink", "text": "2. 第二项", "bounds": {"left": 0, "top": 80, "width": 200, "height": 24}},
			{"unitId": "u-fig", "kind": "figure", "bounds": {"left": 300, "top": 50, "width": 150, "height": 150}},
			{"unitId": "u-cap", "kind": "ink", "text": "图1 示意", "bounds": {"left": 300, "top": 210, "width": 150, "height": 24}}
		],
		"textFingerprint": "txtfp-1"
	}`
}

func post(t *testing.T, handler *RecognitionHandler, body string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, EndpointPath, strings.NewReader(body))
	rec := httptest.NewRecorder()
	handler.serveHTTP(rec, req)
	var parsed map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &parsed); err != nil {
		t.Fatalf("响应不是 JSON: %v (%s)", err, rec.Body.String())
	}
	return rec, parsed
}

func errorOf(t *testing.T, parsed map[string]any) map[string]any {
	t.Helper()
	value, ok := parsed["error"].(map[string]any)
	if !ok {
		t.Fatalf("错误 envelope 缺失: %v", parsed)
	}
	return value
}

func TestHandlerReadStageFullProtocol(t *testing.T) {
	provider := &fakeProvider{responses: []string{
		"```json\n[" +
			`{"regionId":"r:a","status":"recognized","text":"识别正文","confidence":0.9,"diagnostics":[]},` +
			`{"regionId":"r:b","status":"unreadable","diagnostics":[]}` +
			"]\n```",
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, readRequestBody(StageRead))

	if rec.Code != http.StatusOK {
		t.Fatalf("read 应 200: %d %s", rec.Code, rec.Body.String())
	}
	// 回填外壳（R-12 服务端侧）。
	if parsed["operationId"] != "op-1" || parsed["stage"] != "read" ||
		parsed["generation"] != float64(0) || parsed["contentFingerprint"] != "fedcba9876543210" {
		t.Fatalf("回填外壳错误: %v", parsed)
	}
	// 部分批次：模型漏答 r:b 的部分由 missingRegionIds 显式传递。
	if missing, _ := parsed["missingRegionIds"].([]any); len(missing) != 0 {
		t.Fatalf("模型已答全部区域，missing 应为空: %v", parsed["missingRegionIds"])
	}
	regions, _ := parsed["regions"].([]any)
	if len(regions) != 2 {
		t.Fatalf("regions 数错误: %v", regions)
	}
	if provider.callCount() != 1 {
		t.Fatalf("单批单次调用: %d", provider.callCount())
	}
	// 提示词与图像按区域顺序传入。
	if provider.lastReq.Stage != StageRead {
		t.Fatal("provider 日志阶段应为 read")
	}
	if len(provider.lastReq.Images) != 2 {
		t.Fatalf("附图数错误: %d", len(provider.lastReq.Images))
	}
	if !strings.Contains(provider.lastReq.PromptText, "r:a") ||
		!strings.Contains(provider.lastReq.PromptText, "忠实转写器") {
		t.Fatal("read 提示词未按口径构建")
	}
}

func TestHandlerReadPartialBatch(t *testing.T) {
	provider := &fakeProvider{responses: []string{
		`[{"regionId":"r:a","status":"recognized","text":"部分","confidence":0.8,"diagnostics":[]}]`,
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusOK {
		t.Fatalf("部分批次应 200: %d %s", rec.Code, rec.Body.String())
	}
	missing, _ := parsed["missingRegionIds"].([]any)
	if len(missing) != 1 || missing[0] != "r:b" {
		t.Fatalf("missing 求差错误: %v", missing)
	}
}

func verifyRequestBody() string {
	body := readRequestBody(StageVerify)
	return strings.Replace(body,
		`"imageScale": 2.5}`,
		`"imageScale": 2.5, "reason": "lowConfidence"}`, -1)
}

func TestHandlerVerifyStage(t *testing.T) {
	provider := &fakeProvider{responses: []string{
		`[{"regionId":"r:a","status":"recognized","text":"复核正文","confidence":0.88,"diagnostics":["初读漏字"]},` +
			`{"regionId":"r:b","status":"nonText","diagnostics":[]}]`,
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, verifyRequestBody())
	if rec.Code != http.StatusOK || parsed["stage"] != "verify" {
		t.Fatalf("verify 应 200: %d %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(provider.lastReq.PromptText, "复核转写器") {
		t.Fatal("verify 提示词未按口径构建")
	}
	if provider.lastReq.Stage != StageVerify {
		t.Fatal("provider 日志阶段应为 verify")
	}
}

func TestHandlerStructureStage(t *testing.T) {
	provider := &fakeProvider{responses: []string{
		`{"readingOrder":["u-title","u-i1","u-i2","u-fig","u-cap"],` +
			`"roles":[{"unitId":"u-title","role":"title"},{"unitId":"u-i1","role":"listItem"},{"unitId":"u-i2","role":"listItem"},{"unitId":"u-cap","role":"caption"}],` +
			`"listGroups":[{"groupId":"g1","members":["u-i1","u-i2"],"level":1,"listType":"ordered","startNumber":1}],` +
			`"captions":[{"captionUnitId":"u-cap","targetUnitId":"u-fig"}],` +
			`"warnings":["标题置信度一般"]}`,
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, structureRequestBody())
	if rec.Code != http.StatusOK {
		t.Fatalf("structure 应 200: %d %s", rec.Code, rec.Body.String())
	}
	if parsed["textFingerprint"] != "txtfp-1" {
		t.Fatalf("textFingerprint 回填错误: %v", parsed["textFingerprint"])
	}
	if !strings.Contains(provider.lastReq.PromptText, "结构恢复器") {
		t.Fatal("structure 提示词未按口径构建")
	}
	if strings.Contains(provider.lastReq.PromptText, "概览图") {
		t.Fatal("无概览图不得提及概览图")
	}
	if provider.lastReq.Stage != StageStructure {
		t.Fatal("provider 日志阶段应为 structure")
	}
}

func TestHandlerInvalidProviderResponseNoRetry(t *testing.T) {
	provider := &fakeProvider{responses: []string{"这不是 JSON"}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("解析失败应 502: %d", rec.Code)
	}
	wire := errorOf(t, parsed)
	if wire["code"] != CodeInvalidProviderResp {
		t.Fatalf("错误码错误: %v", wire)
	}
	if wire["retryable"] != false {
		t.Fatal("invalidProviderResponse 不可重试")
	}
	if provider.callCount() != 1 {
		t.Fatalf("解析失败不得重试（服务端单次调用）: %d", provider.callCount())
	}
}

func TestHandlerStructureViolationRejects(t *testing.T) {
	provider := &fakeProvider{responses: []string{
		`{"readingOrder":["u-title","u-i1","u-i2","u-fig","u-cap"],` +
			`"roles":[{"unitId":"u-title","role":"title"},{"unitId":"u-i1","role":"listItem"},{"unitId":"u-i2","role":"listItem"},{"unitId":"u-cap","role":"caption"},{"unitId":"u-fig","role":"caption"}],` +
			`"listGroups":[],"captions":[],"warnings":[]}`,
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, structureRequestBody())
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("roles 覆盖 figure 应 502: %d %s", rec.Code, rec.Body.String())
	}
	if errorOf(t, parsed)["code"] != CodeInvalidProviderResp {
		t.Fatal("结构校验失败归 invalidProviderResponse")
	}
}

func TestHandlerProviderTransportError(t *testing.T) {
	provider := &fakeProvider{errs: []error{
		&ProviderTransportError{Err: errors.New("connection refused")},
	}}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("传输层失败应 502: %d", rec.Code)
	}
	wire := errorOf(t, parsed)
	if wire["code"] != CodeProviderError || wire["retryable"] != true {
		t.Fatalf("providerError retryable: %v", wire)
	}
}

func TestHandlerProviderTimeout(t *testing.T) {
	provider := &fakeProvider{delay: 200 * time.Millisecond}
	handler := NewRecognitionHandler(provider, Limits{
		ProviderTimeout: 50 * time.Millisecond,
	})
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("超时应 504: %d %s", rec.Code, rec.Body.String())
	}
	wire := errorOf(t, parsed)
	if wire["code"] != CodeProviderTimeout || wire["retryable"] != true {
		t.Fatalf("providerTimeout retryable: %v", wire)
	}
}

func TestHandlerUnconfigured(t *testing.T) {
	handler := NewRecognitionHandler(nil, DefaultLimits())
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("未配置应 503: %d", rec.Code)
	}
	wire := errorOf(t, parsed)
	if wire["code"] != CodeUnconfigured || wire["retryable"] != false {
		t.Fatalf("unconfigured: %v", wire)
	}
}

func TestHandlerBusyWhenInFlightFull(t *testing.T) {
	block := make(chan struct{})
	provider := &fakeProvider{
		block:     block,
		responses: []string{`[]`},
	}
	handler := NewRecognitionHandler(provider, Limits{MaxInFlight: 1})
	done := make(chan struct{})
	go func() {
		defer close(done)
		req := httptest.NewRequest(http.MethodPost, EndpointPath,
			strings.NewReader(readRequestBody(StageRead)))
		rec := httptest.NewRecorder()
		handler.serveHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("首个请求应成功: %d", rec.Code)
		}
	}()
	// 等待首个请求占满并发。
	deadline := time.Now().Add(2 * time.Second)
	for handler.InFlight() < 1 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("并发满应 429: %d", rec.Code)
	}
	wire := errorOf(t, parsed)
	if wire["code"] != CodeBusy || wire["retryable"] != true {
		t.Fatalf("busy retryable: %v", wire)
	}
	close(block)
	<-done
	if handler.InFlight() != 0 {
		t.Fatalf("释放后并发应归零: %d", handler.InFlight())
	}
}

func TestHandlerBodyOverLimit(t *testing.T) {
	provider := &fakeProvider{}
	handler := NewRecognitionHandler(provider, Limits{MaxBodyBytes: 512})
	rec, parsed := post(t, handler, readRequestBody(StageRead))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("body 超限应 400 limitExceeded: %d", rec.Code)
	}
	if errorOf(t, parsed)["code"] != CodeLimitExceeded {
		t.Fatal("body 超限错误码")
	}
	if provider.callCount() != 0 {
		t.Fatal("超限请求不得触达 provider")
	}
}

func TestHandlerInvalidRequestSchema(t *testing.T) {
	provider := &fakeProvider{}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	req := httptest.NewRequest(http.MethodPost, EndpointPath,
		strings.NewReader(`{"schemaVersion":"wrong"}`))
	rec := httptest.NewRecorder()
	handler.serveHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("非法请求应 400: %d", rec.Code)
	}
	if errorOf(t, mustParse(t, rec))["code"] != CodeInvalidSchema {
		t.Fatal("schema 错误码")
	}
	if provider.callCount() != 0 {
		t.Fatal("非法请求不得触达 provider")
	}
}

func TestHandlerIgnoresTrailingBody(t *testing.T) {
	provider := &fakeProvider{}
	handler := NewRecognitionHandler(provider, DefaultLimits())
	body := readRequestBody(StageRead) + " 垃圾尾随"
	rec, _ := post(t, handler, body)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("尾随内容应 400: %d", rec.Code)
	}
}

func mustParse(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var parsed map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &parsed); err != nil {
		t.Fatal(err)
	}
	return parsed
}
