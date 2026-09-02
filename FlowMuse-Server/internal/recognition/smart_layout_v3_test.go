package recognition

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// 请求构造（V3-200A conformance fixture p2 的等价负载）。
func v3TestRequest() *SmartLayoutV3Request {
	epoch, revision := 2, 17
	version := 3
	return &SmartLayoutV3Request{
		ProtocolVersion: &version,
		PageID:          "page-42",
		SceneRevision: &SmartLayoutV3SceneRevision{
			Epoch:       &epoch,
			Revision:    &revision,
			Fingerprint: "0123456789abcdef",
		},
		Assets: []SmartLayoutV3AssetRef{
			{Key: "clean|page", Kind: "clean", Fingerprint: "0123456789abcdef"},
			{Key: "annotated|page", Kind: "annotated", Fingerprint: "0123456789abcdef"},
			{Key: "crop|r1", Kind: "crop", Fingerprint: "0123456789abcdef"},
		},
		Marks: []SmartLayoutV3Mark{
			{MarkID: "m1", Label: "m1", AssetKey: "annotated|page", SourceID: "r1"},
		},
		ExactTexts: []SmartLayoutV3ExactText{
			{SourceID: "text-1", Text: "标题：会议纪要"},
			{SourceID: "text-2", Text: "第二行"},
		},
		SourceRefs: []string{"r1", "r2", "text-1", "text-2", "ink-3"},
	}
}

// 与 p3-response fixture 等价的合法响应字节（引用均落在请求 sourceRefs 内）。
func v3ValidResponseJSON() []byte {
	return []byte(`{
	  "protocolVersion": 3,
	  "requestId": "req-1",
	  "regions": [
	    {"id": "g1", "role": "title", "sourceIds": ["text-1"], "readingOrder": 0, "confidence": 0.9, "relations": []},
	    {"id": "g2", "role": "figure", "sourceIds": ["r2"], "readingOrder": 1, "confidence": 0.8,
	     "relations": []},
	    {"id": "g3", "role": "caption", "sourceIds": ["r1", "ink-3"], "readingOrder": 2, "confidence": 0.7,
	     "relations": [{"type": "captionOf", "targetRegionId": "g2"}]}
	  ],
	  "warnings": ["低置信区域 1 个"]
	}`)
}

func TestOpenAICompatibleV3Provider(t *testing.T) {
	var model string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" || r.Header.Get("Authorization") != "Bearer test-key" {
			t.Fatalf("unexpected provider request: %s auth=%q", r.URL.Path, r.Header.Get("Authorization"))
		}
		var body struct {
			Model string `json:"model"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		model = body.Model
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{
				"message": map[string]any{"content": string(v3ValidResponseJSON())},
			}},
		})
	}))
	defer server.Close()

	layouter := NewOpenAICompatibleSmartLayouter(OpenAICompatibleConfig{
		BaseURL: server.URL,
		APIKey:  "test-key",
		Model:   "test-model",
	})
	analyzer := NewV3Analyzer(layouter.V3Provider(), DefaultV3RequestLimits())
	doc, v3Err := analyzer.Analyze(context.Background(), v3TestRequest())
	if v3Err != nil || doc == nil || len(doc.Response.Regions) != 3 {
		t.Fatalf("live provider chain failed: doc=%v err=%v", doc, v3Err)
	}
	if model != "test-model" {
		t.Fatalf("model = %q, want test-model", model)
	}
	if NewOpenAICompatibleSmartLayouter(OpenAICompatibleConfig{}).V3Provider() != nil {
		t.Fatal("unconfigured provider must stay disabled")
	}
}

func TestV3AnalyzerProducesValidatedDocument(t *testing.T) {
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return v3ValidResponseJSON(), nil
	}, DefaultV3RequestLimits())
	doc, v3Err := analyzer.Analyze(context.Background(), v3TestRequest())
	if v3Err != nil {
		t.Fatalf("合法分析被拒: %+v", v3Err)
	}
	if doc.Response == nil || len(doc.Response.Regions) != 3 {
		t.Fatalf("文档不完整")
	}
	if doc.RegionTexts["g1"] != "标题：会议纪要" {
		t.Fatalf("typed text 回填错误: %q", doc.RegionTexts["g1"])
	}
	if _, has := doc.RegionTexts["g2"]; has {
		t.Fatalf("手写区域不应回填文本")
	}
	want := []string{"text-2"}
	if len(doc.PreservedSourceRefs) != len(want) || doc.PreservedSourceRefs[0] != want[0] {
		t.Fatalf("preserved 集合错误: %v", doc.PreservedSourceRefs)
	}
}

func TestV3AnalyzerRejectsMaliciousProviderOutput(t *testing.T) {
	cases := []struct {
		name string
		raw  []byte
		code string
	}{
		{"残缺 JSON", []byte(`{"regions":`), V3ErrInternal},
		{"schema 未知字段", []byte(`{"protocolVersion":3,"regions":[],"warnings":[],"evil":1}`), V3ErrInternal},
		{"引用请求不存在的 sourceRef", []byte(`{"protocolVersion":3,"regions":[{"id":"g1","role":"body","sourceIds":["ghost"],"readingOrder":0,"confidence":0.5,"relations":[]}],"warnings":[]}`), V3ErrDanglingReference},
		{"区域重叠认领", []byte(`{"protocolVersion":3,"regions":[
			{"id":"g1","role":"body","sourceIds":["r1"],"readingOrder":0,"confidence":0.5,"relations":[]},
			{"id":"g2","role":"body","sourceIds":["r1"],"readingOrder":1,"confidence":0.5,"relations":[]}
		],"warnings":[]}`), V3ErrDuplicateReference},
		{"readingOrder 非排列(重复)", []byte(`{"protocolVersion":3,"regions":[
			{"id":"g1","role":"body","sourceIds":["r1"],"readingOrder":0,"confidence":0.5,"relations":[]},
			{"id":"g2","role":"body","sourceIds":["r2"],"readingOrder":0,"confidence":0.5,"relations":[]}
		],"warnings":[]}`), V3ErrInvalidRequest},
		{"readingOrder 非排列(越界)", []byte(`{"protocolVersion":3,"regions":[
			{"id":"g1","role":"body","sourceIds":["r1"],"readingOrder":7,"confidence":0.5,"relations":[]}
		],"warnings":[]}`), V3ErrInvalidRequest},
		{"关系成环", []byte(`{"protocolVersion":3,"regions":[
			{"id":"g1","role":"body","sourceIds":["r1"],"readingOrder":0,"confidence":0.5,"relations":[{"type":"boundTo","targetRegionId":"g2"}]},
			{"id":"g2","role":"body","sourceIds":["r2"],"readingOrder":1,"confidence":0.5,"relations":[{"type":"boundTo","targetRegionId":"g1"}]}
		],"warnings":[]}`), V3ErrInternal},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
				return tc.raw, nil
			}, DefaultV3RequestLimits())
			doc, v3Err := analyzer.Analyze(context.Background(), v3TestRequest())
			if doc != nil {
				t.Fatalf("恶意/残缺输出不得产生文档")
			}
			if v3Err == nil || v3Err.Code != tc.code {
				t.Fatalf("错误码不符: got %+v want %s", v3Err, tc.code)
			}
		})
	}
}

func TestV3AnalyzerProviderFailureAndTimeout(t *testing.T) {
	failing := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return nil, errors.New("upstream 503")
	}, DefaultV3RequestLimits())
	if doc, v3Err := failing.Analyze(context.Background(), v3TestRequest()); doc != nil || v3Err == nil || v3Err.Code != V3ErrInternal {
		t.Fatalf("provider 失败必须稳定错误: %+v", v3Err)
	}
	limits := V3RequestLimits{ProviderTimeout: 30 * time.Millisecond}
	slow := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
			return v3ValidResponseJSON(), nil
		}
	}, limits)
	if doc, v3Err := slow.Analyze(context.Background(), v3TestRequest()); doc != nil || v3Err == nil || !strings.Contains(v3Err.Message, "超时") {
		t.Fatalf("provider 超时必须稳定错误: %+v", v3Err)
	}
}

func TestV3AnalyzerConcurrencyLimit(t *testing.T) {
	limits := V3RequestLimits{MaxConcurrent: 1, ProviderTimeout: time.Second}
	var concurrent, peak int32
	var mu sync.Mutex
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		current := atomic.AddInt32(&concurrent, 1)
		mu.Lock()
		if current > peak {
			peak = current
		}
		mu.Unlock()
		time.Sleep(20 * time.Millisecond)
		atomic.AddInt32(&concurrent, -1)
		return v3ValidResponseJSON(), nil
	}, limits)
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, v3Err := analyzer.Analyze(context.Background(), v3TestRequest()); v3Err != nil {
				t.Errorf("受限并发分析不应失败: %+v", v3Err)
			}
		}()
	}
	wg.Wait()
	if peak > 1 {
		t.Fatalf("并发上限被突破: peak=%d", peak)
	}
	if analyzer.InFlight() != 0 {
		t.Fatalf("结束后 in-flight 必须归零: %d", analyzer.InFlight())
	}
}

func TestRegisterSmartLayoutV3HTTPEndpoint(t *testing.T) {
	mux := http.NewServeMux()
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return v3ValidResponseJSON(), nil
	}, DefaultV3RequestLimits())
	RegisterSmartLayoutV3(mux, analyzer)
	server := httptest.NewServer(mux)
	defer server.Close()
	endpoint := server.URL + "/api/ink/smart-layout/analyze/v3"

	// 正常链路：200 + 冻结响应 schema。
	requestBytes, _ := json.Marshal(map[string]any{
		"protocolVersion": 3,
		"pageId":          "page-42",
		"sceneRevision":   map[string]any{"epoch": 0, "revision": 1, "fingerprint": "0123456789abcdef"},
		"assets":          []map[string]any{{"key": "clean|page", "kind": "clean", "fingerprint": "0123456789abcdef"}},
		"marks":           []map[string]any{},
		"exactTexts":      []map[string]any{{"sourceId": "text-1", "text": "标题：会议纪要"}},
		"sourceRefs":      []string{"r1", "r2", "text-1", "text-2", "ink-3"},
	})
	resp, err := http.Post(endpoint, "application/json", bytes.NewReader(requestBytes))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("正常请求状态码 %d", resp.StatusCode)
	}
	var payload map[string]json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if _, ok := payload["regions"]; !ok {
		t.Fatalf("响应缺 regions")
	}
	if _, ok := payload["error"]; ok {
		t.Fatalf("成功响应不应带 error")
	}

	// 非法请求：400 + 冻结错误 envelope。
	bad, _ := json.Marshal(map[string]any{"protocolVersion": 3})
	resp2, err := http.Post(endpoint, "application/json", bytes.NewReader(bad))
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusBadRequest {
		t.Fatalf("非法请求状态码 %d", resp2.StatusCode)
	}
	var errPayload map[string]SmartLayoutV3Error
	if err := json.NewDecoder(resp2.Body).Decode(&errPayload); err != nil {
		t.Fatal(err)
	}
	if errPayload["error"].Code != V3ErrInvalidRequest {
		t.Fatalf("错误 envelope code: %+v", errPayload["error"])
	}

	// 方法错误：405。
	resp3, err := http.Get(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	defer resp3.Body.Close()
	if resp3.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("GET 状态码 %d", resp3.StatusCode)
	}

	// 超限请求体：413 + limit_exceeded。
	resp4, err := http.Post(endpoint, "application/json", bytes.NewReader(make([]byte, int(DefaultV3RequestLimits().MaxBodyBytes)+1024)))
	if err != nil {
		t.Fatal(err)
	}
	defer resp4.Body.Close()
	if resp4.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("超限状态码 %d", resp4.StatusCode)
	}

	// provider 失败：502 + internal。
	failMux := http.NewServeMux()
	RegisterSmartLayoutV3(failMux, NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return nil, errors.New("boom")
	}, DefaultV3RequestLimits()))
	failServer := httptest.NewServer(failMux)
	defer failServer.Close()
	resp5, err := http.Post(failServer.URL+"/api/ink/smart-layout/analyze/v3", "application/json", bytes.NewReader(requestBytes))
	if err != nil {
		t.Fatal(err)
	}
	defer resp5.Body.Close()
	if resp5.StatusCode != http.StatusBadGateway {
		t.Fatalf("provider 失败状态码 %d", resp5.StatusCode)
	}
}

func TestV3ChannelIndependentFromV2(t *testing.T) {
	// v3 未注入 → 路由不存在（404），v2 端点行为不变。
	mux := http.NewServeMux()
	api := NewHTTPAPI(nil, time.Second).WithV3Analyzer(nil)
	api.Register(mux)
	server := httptest.NewServer(mux)
	defer server.Close()
	resp, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("未启用的 v3 端点应 404，got %d", resp.StatusCode)
	}

	// v3 注入 → WithV3Analyzer 链式注册成功。
	mux2 := http.NewServeMux()
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return v3ValidResponseJSON(), nil
	}, DefaultV3RequestLimits())
	NewHTTPAPI(nil, time.Second).WithV3Analyzer(analyzer).Register(mux2)
	server2 := httptest.NewServer(mux2)
	defer server2.Close()
	requestBytes, _ := json.Marshal(map[string]any{
		"protocolVersion": 3,
		"pageId":          "p",
		"sceneRevision":   map[string]any{"epoch": 0, "revision": 1, "fingerprint": "0123456789abcdef"},
		"assets":          []map[string]any{},
		"marks":           []map[string]any{},
		"exactTexts":      []map[string]any{},
		"sourceRefs":      []string{"r1", "r2", "text-1", "text-2", "ink-3"},
	})
	resp2, err := http.Post(server2.URL+"/api/ink/smart-layout/analyze/v3", "application/json", bytes.NewReader(requestBytes))
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusOK {
		t.Fatalf("启用后 v3 端点应 200，got %d", resp2.StatusCode)
	}

	// RegisterSmartLayoutV3 nil 防御。
	RegisterSmartLayoutV3(nil, nil)
	RegisterSmartLayoutV3(http.NewServeMux(), nil)
}

func TestNewV3AnalyzerNilProvider(t *testing.T) {
	if NewV3Analyzer(nil, DefaultV3RequestLimits()) != nil {
		t.Fatal("nil provider 必须返回 nil analyzer（通道关闭）")
	}
}

// ---- V3-201B：传输健壮性与 live-route ----

func newV3TestServer(t *testing.T, analyzer *V3Analyzer) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	RegisterSmartLayoutV3(mux, analyzer)
	server := httptest.NewServer(mux)
	t.Cleanup(server.Close)
	return server
}

func v3FullRequestBytes(t *testing.T) []byte {
	t.Helper()
	requestBytes, err := json.Marshal(map[string]any{
		"protocolVersion": 3,
		"pageId":          "page-42",
		"sceneRevision":   map[string]any{"epoch": 2, "revision": 17, "fingerprint": "0123456789abcdef"},
		"assets": []map[string]any{
			{"key": "clean|page", "kind": "clean", "fingerprint": "0123456789abcdef"},
			{"key": "annotated|page", "kind": "annotated", "fingerprint": "0123456789abcdef"},
			{"key": "crop|r1", "kind": "crop", "fingerprint": "0123456789abcdef"},
		},
		"marks":      []map[string]any{{"markId": "m1", "label": "m1", "assetKey": "annotated|page", "sourceId": "r1"}},
		"exactTexts": []map[string]any{{"sourceId": "text-1", "text": "标题：会议纪要"}, {"sourceId": "text-2", "text": "第二行"}},
		"sourceRefs": []string{"r1", "r2", "text-1", "text-2", "ink-3"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return requestBytes
}

func TestV3LiveRouteSmoke(t *testing.T) {
	var seen *SmartLayoutV3Request
	var mu sync.Mutex
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		mu.Lock()
		seen = req
		mu.Unlock()
		return v3ValidResponseJSON(), nil
	}, DefaultV3RequestLimits())
	server := newV3TestServer(t, analyzer)

	resp, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3",
		"application/json", bytes.NewReader(v3FullRequestBytes(t)))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("live-route smoke 状态码 %d: %s", resp.StatusCode, body)
	}
	var payload struct {
		ProtocolVersion int `json:"protocolVersion"`
		Regions         []struct {
			ID           string   `json:"id"`
			Role         string   `json:"role"`
			SourceIDs    []string `json:"sourceIds"`
			ReadingOrder *int     `json:"readingOrder"`
			Confidence   *float64 `json:"confidence"`
		} `json:"regions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.ProtocolVersion != 3 || len(payload.Regions) != 3 {
		t.Fatalf("响应不完整: %+v", payload)
	}
	if payload.Regions[0].ReadingOrder == nil || payload.Regions[0].Confidence == nil {
		t.Fatal("必填字段缺失")
	}
	mu.Lock()
	defer mu.Unlock()
	if seen == nil || seen.PageID != "page-42" || len(seen.ExactTexts) != 2 {
		t.Fatalf("provider 未收到完整请求: %+v", seen)
	}
}

func TestV3ClientCancellationPropagates(t *testing.T) {
	providerSawCancel := make(chan struct{})
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		<-ctx.Done()
		close(providerSawCancel)
		return nil, ctx.Err()
	}, DefaultV3RequestLimits())
	server := newV3TestServer(t, analyzer)

	ctx, cancel := context.WithCancel(context.Background())
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost,
		server.URL+"/api/ink/smart-layout/analyze/v3",
		bytes.NewReader(v3FullRequestBytes(t)))
	client := &http.Client{}
	go func() {
		time.Sleep(30 * time.Millisecond)
		cancel()
	}()
	_, _ = client.Do(req) // 客户端主动取消，读取错误是预期行为
	select {
	case <-providerSawCancel:
	case <-time.After(2 * time.Second):
		t.Fatal("客户端取消未传播到 provider ctx")
	}
}

func TestV3RequestTimeoutAborts(t *testing.T) {
	limits := V3RequestLimits{RequestTimeout: 50 * time.Millisecond, ProviderTimeout: 40 * time.Millisecond}
	analyzer := NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(5 * time.Second):
			return v3ValidResponseJSON(), nil
		}
	}, limits)
	server := newV3TestServer(t, analyzer)

	start := time.Now()
	resp, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3",
		"application/json", bytes.NewReader(v3FullRequestBytes(t)))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	elapsed := time.Since(start)
	if resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("请求级超时应 502，got %d", resp.StatusCode)
	}
	if elapsed > 2*time.Second {
		t.Fatalf("超时未及时中断: %v", elapsed)
	}
}

func TestV3ErrorCodeToStatusMapping(t *testing.T) {
	cases := []struct {
		name     string
		provider []byte
		status   int
	}{
		{"残缺输出→502", []byte("{"), http.StatusBadGateway},
		{"悬空 sourceRef→400", []byte(`{"protocolVersion":3,"regions":[{"id":"g1","role":"body","sourceIds":["ghost"],"readingOrder":0,"confidence":0.5,"relations":[]}],"warnings":[]}`), http.StatusBadRequest},
		{"重叠认领→400", []byte(`{"protocolVersion":3,"regions":[{"id":"g1","role":"body","sourceIds":["r1"],"readingOrder":0,"confidence":0.5,"relations":[]},{"id":"g2","role":"body","sourceIds":["r1"],"readingOrder":1,"confidence":0.5,"relations":[]}],"warnings":[]}`), http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := newV3TestServer(t, NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
				return tc.provider, nil
			}, DefaultV3RequestLimits()))
			resp, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3",
				"application/json", bytes.NewReader(v3FullRequestBytes(t)))
			if err != nil {
				t.Fatal(err)
			}
			defer resp.Body.Close()
			if resp.StatusCode != tc.status {
				t.Fatalf("状态映射不符: got %d want %d", resp.StatusCode, tc.status)
			}
			var envelope map[string]SmartLayoutV3Error
			if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
				t.Fatal(err)
			}
			if envelope["error"].Code == "" {
				t.Fatal("错误 envelope 缺 code")
			}
		})
	}
}

// 旧端点不串线：v2 请求打 v3 端点、v3 请求打 v2 端点都必须被各自
// 校验拒绝；两通道同时启用互不影响。
type stubV2Layouter struct{}

func (stubV2Layouter) Layout(ctx context.Context, request SmartLayoutRequest) (SmartLayoutResponse, error) {
	return SmartLayoutResponse{}, nil
}

func (stubV2Layouter) RecognizeBlock(ctx context.Context, block SmartLayoutInkBlock) (SmartLayoutRecognizedBlock, error) {
	return SmartLayoutRecognizedBlock{}, nil
}

func (stubV2Layouter) Compose(ctx context.Context, request SmartLayoutComposeRequest) (SmartLayoutResponse, error) {
	return SmartLayoutResponse{}, nil
}

func TestV2V3NoCrosstalk(t *testing.T) {
	v2Payload := []byte(`{"pages":[],"blocks":[]}`)
	layouter := stubV2Layouter{}
	api := NewHTTPAPI(nil, time.Second, layouter).
		WithV3Analyzer(NewV3Analyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
			return v3ValidResponseJSON(), nil
		}, DefaultV3RequestLimits()))
	mux := http.NewServeMux()
	api.Register(mux)
	server := httptest.NewServer(mux)
	defer server.Close()

	// v3 payload 打 v2 端点：v2 自身校验拒绝（不串线成 v3 语义）。
	respCross, err := http.Post(server.URL+"/api/ink/smart-layout", "application/json", bytes.NewReader(v3FullRequestBytes(t)))
	if err != nil {
		t.Fatal(err)
	}
	respCross.Body.Close()
	if respCross.StatusCode == http.StatusOK {
		t.Fatal("v3 payload 不得被 v2 端点当有效请求处理")
	}

	// v2 payload 打 v3 端点：v3 严格解析拒绝。
	respCross2, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3", "application/json", bytes.NewReader(v2Payload))
	if err != nil {
		t.Fatal(err)
	}
	defer respCross2.Body.Close()
	if respCross2.StatusCode != http.StatusBadRequest {
		t.Fatalf("v2 payload 打 v3 端点应 400，got %d", respCross2.StatusCode)
	}

	// v3 端点仍正常。
	respV3, err := http.Post(server.URL+"/api/ink/smart-layout/analyze/v3", "application/json", bytes.NewReader(v3FullRequestBytes(t)))
	if err != nil {
		t.Fatal(err)
	}
	defer respV3.Body.Close()
	if respV3.StatusCode != http.StatusOK {
		t.Fatalf("v3 端点被 v2 干扰: %d", respV3.StatusCode)
	}
}
