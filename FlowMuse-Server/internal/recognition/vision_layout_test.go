package recognition

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeVisionServer 用固定内容响应 chat/completions（供 vision 测试复用）。
func fakeVisionServer(t *testing.T, content string, sawImage *bool) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := readAllBody(t, r)
		if !strings.Contains(body, "data:image/png;base64,dGVzdA==") {
			t.Fatalf("request should carry the page screenshot as data URL")
		}
		if sawImage != nil {
			*sawImage = true
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	return server
}

func readAllBody(t *testing.T, r *http.Request) string {
	t.Helper()
	body, err := io.ReadAll(r.Body)
	if err != nil {
		t.Fatalf("read request body: %v", err)
	}
	return string(body)
}

func sampleVisionRequest() VisionLayoutRequest {
	return VisionLayoutRequest{
		PageID:      "p-1",
		NoteTitle:   "我的笔记",
		ImageMime:   "image/png",
		ImageBase64: "dGVzdA==",
		Marks:       []string{"m1", "m2", "m3"},
	}
}

func TestVisionLayoutParsesAndMapsPageID(t *testing.T) {
	content := `{"style":"ppt","confidence":0.9,"elements":[` +
		`{"role":"title","text":"手工记账","markIds":["m1"]},` +
		`{"role":"figure","text":"","markIds":["m2"],"pairId":"pair-1"},` +
		`{"role":"caption","text":"小羊睡觉","vertical":true,"markIds":["m3"],"pairId":"pair-1"}]}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.PageID != "p-1" {
		t.Fatalf("pageId = %q", response.PageID)
	}
	if response.Style != layoutStylePPT {
		t.Fatalf("style = %q", response.Style)
	}
	if len(response.Elements) != 3 {
		t.Fatalf("elements = %d, want 3", len(response.Elements))
	}
	if !response.Elements[2].Vertical || response.Elements[2].PairID != "pair-1" {
		t.Fatalf("caption = %#v", response.Elements[2])
	}
}

func TestVisionLayoutMarkReferencesValidated(t *testing.T) {
	content := `{"style":"in_place","elements":[` +
		`{"role":"body","text":"未知编号","markIds":["m9"]},` + // 不在请求标记里 → 丢元素
		`{"role":"body","text":"多项合并","markIds":["m2","m1","m99"]},` + // 剔除未知，保留 m2,m1
		`{"role":"body","text":"重复引用","markIds":["m1"]},` + // m1 已被前项占用 → 剔空丢元素
		`{"role":"body","text":"无引用","markIds":[]},` + // 空 → 丢元素
		`{"role":"body","text":"正常单项","markIds":["m3"]}]}` // 透传
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if len(response.Elements) != 2 {
		t.Fatalf("elements = %d, want 2", len(response.Elements))
	}
	if got := strings.Join(response.Elements[0].MarkIds, ","); got != "m2,m1" {
		t.Fatalf("first element markIds = %q, want m2,m1", got)
	}
	if got := strings.Join(response.Elements[1].MarkIds, ","); got != "m3" {
		t.Fatalf("second element markIds = %q, want m3", got)
	}
}

func TestVisionLayoutElementConfidenceNormalized(t *testing.T) {
	content := `{"style":"in_place","elements":[` +
		`{"role":"body","text":"未自报把握","markIds":["m1"]},` + // 缺省 → 0.9
		`{"role":"body","text":"潦草字","confidence":0.25,"markIds":["m2"]},` + // 透传
		`{"role":"body","text":"过分自信","confidence":2.5,"markIds":["m3"]}]}` // 越界 → 1
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	want := []float64{0.9, 0.25, 1}
	for i, expected := range want {
		if got := response.Elements[i].Confidence; got != expected {
			t.Fatalf("elements[%d].confidence = %v, want %v", i, got, expected)
		}
	}
}

func TestVisionLayoutDropsHallucinatedTextAndNormalizesRoles(t *testing.T) {
	content := `{"style":"in_place","elements":[` +
		`{"role":"body","text":"","markIds":["m1"]},` + // 文字角色无文字 → 幻觉，丢弃
		`{"role":"unknown-role","text":"角色未知","markIds":["m1"]},` + // 归为 body 保留
		`{"role":"title","text":"标题一","markIds":["m2"]},` +
		`{"role":"title","text":"标题二","markIds":["m3"]}]}` // 第二个 title 降级 body
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	var roles []string
	for _, element := range response.Elements {
		roles = append(roles, element.Role)
	}
	joined := strings.Join(roles, ",")
	want := "body,title,body"
	if joined != want {
		t.Fatalf("roles = %q (%d), want %q", joined, len(roles), want)
	}
}

func TestVisionLayoutBadStyleFallsBackToInPlace(t *testing.T) {
	content := `{"style":"diagram","elements":[{"role":"body","text":"内容","markIds":["m1"]}]}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.Style != layoutStyleInPlace {
		t.Fatalf("style = %q, want in_place", response.Style)
	}
}

func TestVisionLayoutInvalidJSONReturnsError(t *testing.T) {
	layouter := newTestSmartLayouter(fakeVisionServer(t, `这不是 JSON`, nil).URL)
	if _, err := layouter.VisionLayout(context.Background(), sampleVisionRequest()); err == nil {
		t.Fatal("invalid JSON should return an error so客户端回退经典管线")
	}
}

func TestVisionLayoutAssignsElementIDs(t *testing.T) {
	content := `{"style":"article","elements":[` +
		`{"role":"title","text":"标题","markIds":["m1"]},` +
		`{"role":"body","text":"正文","markIds":["m2"]}]}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.Elements[0].ID != "e0" || response.Elements[1].ID != "e1" {
		t.Fatalf("ids = %q,%q", response.Elements[0].ID, response.Elements[1].ID)
	}
}

func TestVisionLayoutMindmapStructureValidated(t *testing.T) {
	content := `{"style":"mindmap","confidence":0.9,"elements":[` +
		`{"role":"body","text":"主题","markIds":["m1"]},` +
		`{"role":"body","text":"分支一","markIds":["m2"]},` +
		`{"role":"figure","markIds":["m3"]}],` +
		`"structure":{"root":{"text":"","blockIds":["e0","e9"],"children":[` +
		`{"text":"分支","blockIds":["e1"]}]}}}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.Style != layoutStyleMindmap {
		t.Fatalf("style = %q", response.Style)
	}
	root, ok := response.Structure["root"].(map[string]any)
	if !ok {
		t.Fatalf("structure = %#v", response.Structure)
	}
	// e9 是悬空引用应被剔除；根节点 text 空+仅剩 e0 合法
	refs, _ := root["blockIds"].([]string)
	if len(refs) != 1 || refs[0] != "e0" {
		t.Fatalf("root refs = %#v", root["blockIds"])
	}
	children, _ := root["children"].([]map[string]any)
	if len(children) != 1 {
		t.Fatalf("children = %#v", root["children"])
	}
}

func TestVisionLayoutMindmapDanglingRefsFallBackInPlace(t *testing.T) {
	content := `{"style":"mindmap","elements":[` +
		`{"role":"body","text":"主题","markIds":["m1"]}],` +
		`"structure":{"root":{"text":"","blockIds":["e5"]}}}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.Style != layoutStyleInPlace || response.Structure != nil {
		t.Fatalf("style=%q structure=%v, want in_place/nil", response.Style, response.Structure)
	}
}

func TestVisionLayoutNonMindmapClearsStructure(t *testing.T) {
	content := `{"style":"ppt","elements":[{"role":"title","text":"T","markIds":["m1"]}],"structure":{"root":{}}}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if response.Structure != nil {
		t.Fatalf("non-mindmap should clear structure, got %#v", response.Structure)
	}
}

func TestVisionSendsNoteTitleInPrompt(t *testing.T) {
	sawTitle := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := readAllBody(t, r)
		if strings.Contains(body, "笔记标题：我的笔记") {
			sawTitle = true
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` +
			jsonString(`{"style":"article","elements":[]}`) + `}}]}`))
	}))
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if !sawTitle {
		t.Fatal("prompt should embed note title")
	}
	if response.Style != layoutStyleArticle {
		t.Fatalf("style = %q", response.Style)
	}
}

func TestVisionEndpointRejectsEmptyImage(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil).WithVisionLayouter(newTestSmartLayouter("http://unused"))
	mux := http.NewServeMux()
	api.Register(mux)
	request := httptest.NewRequest(http.MethodPost, "/api/ink/smart-layout/vision",
		strings.NewReader(`{"pageId":"p-1","imageBase64":""}`))
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", recorder.Code)
	}
}

func TestVisionEndpointRejectsNonPost(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil).WithVisionLayouter(newTestSmartLayouter("http://unused"))
	mux := http.NewServeMux()
	api.Register(mux)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/ink/smart-layout/vision", nil))
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", recorder.Code)
	}
}

func TestVisionEndpointWithoutLayouterFails(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil)
	mux := http.NewServeMux()
	api.Register(mux)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, httptest.NewRequest(http.MethodPost,
		"/api/ink/smart-layout/vision", strings.NewReader(sampleJSONVisionRequest())))
	if recorder.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", recorder.Code)
	}
}

func sampleJSONVisionRequest() string {
	return `{"pageId":"p-1","imageBase64":"dGVzdA=="}`
}
