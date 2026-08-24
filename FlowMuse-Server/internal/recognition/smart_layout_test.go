package recognition

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeChatServer 用固定内容响应 chat/completions。
func fakeChatServer(t *testing.T, content string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/chat/completions") {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	return server
}

func jsonString(value string) string {
	// 简易 JSON 字符串转义（测试内容不含控制字符）。
	escaped := strings.ReplaceAll(value, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `"`, `\"`)
	escaped = strings.ReplaceAll(escaped, "\n", "\\n")
	return `"` + escaped + `"`
}

func newTestSmartLayouter(baseURL string) *OpenAICompatibleSmartLayouter {
	return NewOpenAICompatibleSmartLayouter(OpenAICompatibleConfig{
		BaseURL: baseURL,
		APIKey:  "fake-key",
		Model:   "fake-model",
	})
}

func sampleComposeRequest() SmartLayoutComposeRequest {
	return SmartLayoutComposeRequest{
		Pages: []SmartLayoutPage{{ID: "p-1", Index: 0}},
		Blocks: []SmartLayoutRecognizedBlock{
			{ID: "blk-1", PageID: "p-1", Type: "text", Text: "手工记账"},
			{ID: "blk-2", PageID: "p-1", Type: "text", Text: "流水线"},
			{ID: "blk-3", PageID: "p-1", Type: "text", Text: "无法识别的字", Error: "recognition failed"},
		},
		Elements: []SmartLayoutElementRef{
			{ID: "e-1", Type: "image", Bounds: InkBounds{X: 0, Y: 0, Width: 10, Height: 10}},
		},
	}
}

func TestDecideLayoutMindmap(t *testing.T) {
	server := fakeChatServer(t, `{"style":"mindmap","confidence":0.9,"structure":{"root":{"text":"主题","blockIds":["blk-1","blk-2"]}}}`)
	layouter := newTestSmartLayouter(server.URL)
	decision := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if decision == nil {
		t.Fatal("decideLayout returned nil")
	}
	if decision.Style != layoutStyleMindmap {
		t.Fatalf("style = %q, want mindmap", decision.Style)
	}
	root, ok := decision.Structure["root"].(map[string]any)
	if !ok {
		t.Fatalf("root missing: %#v", decision.Structure)
	}
	// blk-1/blk-2 均为成功块，节点文本优先使用块文本拼接
	if root["text"] != "手工记账\n流水线" {
		t.Fatalf("root text = %q", root["text"])
	}
}

func TestDecideLayoutMindmapDropsFailedBlockRefs(t *testing.T) {
	server := fakeChatServer(t, `{"style":"mindmap","confidence":0.8,"structure":{"root":{"text":"","blockIds":["blk-3"]}}}`)
	layouter := newTestSmartLayouter(server.URL)
	decision := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if decision == nil {
		t.Fatal("decideLayout returned nil")
	}
	// root 引用失败块(blk-3)且无 text → 整树无效 → 回落 in_place
	if decision.Style != layoutStyleInPlace {
		t.Fatalf("style = %q, want in_place", decision.Style)
	}
}

func TestDecideLayoutPptSanitizesRoles(t *testing.T) {
	server := fakeChatServer(t, `{"style":"ppt","confidence":0.7,"structure":{"groups":[{"role":"title","elementIds":["blk-1"]},{"role":"unknown-role","elementIds":["e-1","blk-9"]},{"role":"body","elementIds":[]}]}}`)
	layouter := newTestSmartLayouter(server.URL)
	decision := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if decision == nil {
		t.Fatal("decideLayout returned nil")
	}
	if decision.Style != layoutStylePPT {
		t.Fatalf("style = %q, want ppt", decision.Style)
	}
	groups, ok := decision.Structure["groups"].([]map[string]any)
	if !ok {
		t.Fatalf("groups missing: %#v", decision.Structure)
	}
	if len(groups) != 2 {
		t.Fatalf("groups len = %d, want 2 (非法role归为body、空组删除)", len(groups))
	}
	if groups[1]["role"] != "body" {
		t.Fatalf("role = %v, want body", groups[1]["role"])
	}
	ids, ok := groups[1]["elementIds"].([]string)
	if !ok || len(ids) != 1 || ids[0] != "e-1" {
		t.Fatalf("ids = %#v, want [e-1]（blk-9 失效引用删除）", groups[1]["elementIds"])
	}
}

func TestDecideLayoutBadStyleFallsBack(t *testing.T) {
	server := fakeChatServer(t, `{"style":"diagram","confidence":0.5,"structure":{}}`)
	layouter := newTestSmartLayouter(server.URL)
	decision := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if decision == nil {
		t.Fatal("decideLayout returned nil")
	}
	if decision.Style != layoutStyleInPlace {
		t.Fatalf("style = %q, want in_place", decision.Style)
	}
}

func TestDecideLayoutHonorsHint(t *testing.T) {
	server := fakeChatServer(t, `{"style":"ppt","confidence":0.9,"structure":{"groups":[{"role":"title","elementIds":["blk-1"]}]}}`)
	layouter := newTestSmartLayouter(server.URL)
	request := sampleComposeRequest()
	request.LayoutHint = layoutStylePPT
	decision := layouter.decideLayout(context.Background(), request)
	if decision == nil {
		t.Fatal("decideLayout returned nil")
	}
	if decision.Style != layoutStylePPT {
		t.Fatalf("style = %q, want ppt", decision.Style)
	}
}

func TestDecideLayoutEmptyContentSkipsAI(t *testing.T) {
	// 无成功块且无元素时不调 AI，直接返回 nil
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		_, _ = w.Write([]byte(`{}`))
	}))
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	request := SmartLayoutComposeRequest{
		Pages: []SmartLayoutPage{{ID: "p-1", Index: 0}},
		Blocks: []SmartLayoutRecognizedBlock{
			{ID: "blk-3", Type: "text", Error: "failed"},
		},
	}
	decision := layouter.decideLayout(context.Background(), request)
	if decision != nil {
		t.Fatalf("decision = %#v, want nil", decision)
	}
	if called {
		t.Fatal("AI should not be called when there is nothing to decide")
	}
}

func TestSanitizeLayoutDecisionConfidenceClamped(t *testing.T) {
	decision := &SmartLayoutLayoutDecision{Style: layoutStyleArticle, Confidence: 2.5}
	sanitizeLayoutDecision(decision, sampleComposeRequest())
	if decision.Confidence != 1 {
		t.Fatalf("confidence = %v, want 1", decision.Confidence)
	}
	negative := &SmartLayoutLayoutDecision{Style: layoutStyleArticle, Confidence: -0.5}
	sanitizeLayoutDecision(negative, sampleComposeRequest())
	if negative.Confidence != 0 {
		t.Fatalf("confidence = %v, want 0", negative.Confidence)
	}
}

func TestComposeMindmapStyleUsesInPlacePages(t *testing.T) {
	server := fakeChatServer(t, `{"style":"mindmap","confidence":0.9,"structure":{"root":{"text":"主题","blockIds":["blk-1"]}}}`)
	layouter := newTestSmartLayouter(server.URL)
	response, err := layouter.Compose(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("Compose error: %v", err)
	}
	if response.Layout == nil || response.Layout.Style != layoutStyleMindmap {
		t.Fatalf("layout = %#v, want mindmap", response.Layout)
	}
	for _, page := range response.Pages {
		if page.Mode != "in_place" {
			t.Fatalf("mindmap 风格下所有页面 mode 应为 in_place，实际 %q", page.Mode)
		}
	}
}

func TestComposeFallbackKeepsArticlePath(t *testing.T) {
	// 无 layoutHint、AI 判定 article 时走原 decidePages 路径（>=2 成功块触发段落决策，
	// 该测试的 fake server 会对第二次 AI 调用返回 article 段落结果）
	content := `{"style":"article","confidence":0.9,"structure":{}}`
	articleDecision := `{"pageId":"p-1","mode":"article","paragraphs":[["blk-1","blk-2"]]}`
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls == 1 {
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`))
			return
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(articleDecision) + `}}]}`))
	}))
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	response, err := layouter.Compose(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("Compose error: %v", err)
	}
	if response.Layout == nil || response.Layout.Style != layoutStyleArticle {
		t.Fatalf("layout = %#v, want article", response.Layout)
	}
	found := false
	for _, page := range response.Pages {
		if page.Mode == "article" {
			found = true
		}
	}
	if !found {
		t.Fatalf("article 风格应保留原文章段落决策路径，pages = %#v", response.Pages)
	}
}
