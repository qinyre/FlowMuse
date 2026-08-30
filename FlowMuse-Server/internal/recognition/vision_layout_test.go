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
	content := `{"elements":[` +
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
	if len(response.Elements) != 3 {
		t.Fatalf("elements = %d, want 3", len(response.Elements))
	}
	if !response.Elements[2].Vertical || response.Elements[2].PairID != "pair-1" {
		t.Fatalf("caption = %#v", response.Elements[2])
	}
}

func TestVisionLayoutMarkReferencesValidated(t *testing.T) {
	content := `{"elements":[` +
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
	content := `{"elements":[` +
		`{"role":"body","text":"未自报把握","markIds":["m1"]},` + // 缺省 → 存疑 0.5，客户端触发重问
		`{"role":"body","text":"潦草字","confidence":0.25,"markIds":["m2"]},` + // 透传
		`{"role":"body","text":"过分自信","confidence":2.5,"markIds":["m3"]}]}` // 越界 → 1
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), sampleVisionRequest())
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	want := []float64{0.5, 0.25, 1}
	for i, expected := range want {
		if got := response.Elements[i].Confidence; got != expected {
			t.Fatalf("elements[%d].confidence = %v, want %v", i, got, expected)
		}
	}
}

func TestVisionLayoutStripsMarkEcho(t *testing.T) {
	content := `{"elements":[` +
		`{"role":"body","text":"m6三月","confidence":0.95,"markIds":["m1"]},` + // 前缀回显 → "三月"+压 0.5
		`{"role":"body","text":"m9","markIds":["m2"]},` + // 纯回显（真实编号）→ 空文本、把握 0
		`{"role":"body","text":"m99","confidence":0.9,"markIds":["m3"]},` + // 纯回显（编造编号）→ 同上
		`{"role":"body","text":"m6 U盘","confidence":0.9,"markIds":["m6"]},` + // 分隔符前缀 → "U盘"
		`{"role":"body","text":"m3u8","confidence":0.9,"markIds":["m5"]},` + // 真实编号开头也剥离（重问可救回）
		`{"role":"body","text":"正文内容","confidence":0.9,"markIds":["m4"]}]}` // 无回显 → 原样
	request := sampleVisionRequest()
	request.Marks = []string{"m1", "m2", "m3", "m4", "m5", "m6"}
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.VisionLayout(context.Background(), request)
	if err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if len(response.Elements) != 6 {
		t.Fatalf("elements = %d, want 6（纯回显剥成空文本的元素要保留，交客户端重问救回）", len(response.Elements))
	}
	wantText := []string{"三月", "", "", "U盘", "u8", "正文内容"}
	wantConfidence := []float64{0.5, 0, 0, 0.5, 0.5, 0.9}
	for i := range wantText {
		if got := response.Elements[i].Text; got != wantText[i] {
			t.Fatalf("elements[%d].text = %q, want %q", i, got, wantText[i])
		}
		if got := response.Elements[i].Confidence; got != wantConfidence[i] {
			t.Fatalf("elements[%d].confidence = %v, want %v", i, got, wantConfidence[i])
		}
	}
}

func TestStripMarkEcho(t *testing.T) {
	valid := map[string]bool{"m1": true, "m6": true, "m10": true}
	cases := []struct {
		name    string
		in      string
		text    string
		changed bool
	}{
		{"纯单编号", "m6", "", true},
		{"纯多编号带分隔与空白", "  m9，m10 ", "", true},
		{"前缀紧接内容", "m6三月", "三月", true},
		{"前缀+分隔符+内容", "m10：先头小子", "先头小子", true},
		{"非本页编号前缀不动", "m3u8", "m3u8", false},
		{"无编号", "正文内容", "正文内容", false},
		{"空串（只去空白）", "   ", "", false},
	}
	for _, tc := range cases {
		text, changed := stripMarkEcho(tc.in, valid)
		if text != tc.text || changed != tc.changed {
			t.Fatalf("%s: stripMarkEcho(%q) = (%q, %v), want (%q, %v)",
				tc.name, tc.in, text, changed, tc.text, tc.changed)
		}
	}
}

func TestVisionPromptForbidsMarkEchoInText(t *testing.T) {
	if !strings.Contains(visionLayoutPrompt, "严禁出现在") {
		t.Fatal("vision prompt 应明确禁止编号标签进入 text 转写")
	}
	if !strings.Contains(transcribePrompt, "严禁转写进结果") {
		t.Fatal("transcribe prompt 应明确忽略系统标注")
	}
}

// 第七轮识别质量治理（真机走查：短语拆框成"冬"+"1"、竖排误读、标题漏标）。
func TestVisionPromptGuidesMergeTitleCaptionVertical(t *testing.T) {
	for prompt, phrase := range map[string]string{
		visionLayoutPrompt: "必须合并为一个项输出",
		transcribePrompt:   "不要只转写半句",
	} {
		if !strings.Contains(prompt, phrase) {
			t.Fatalf("prompt 缺少关键指引 %q", phrase)
		}
	}
	if !strings.Contains(visionLayoutPrompt, "严禁把同一短语按编号拆成多项") {
		t.Fatal("vision prompt 应禁止短语按编号拆项")
	}
	if !strings.Contains(visionLayoutPrompt, "按从上到下的顺序逐字转写") {
		t.Fatal("vision prompt 应给竖排读法指引")
	}
	if !strings.Contains(visionLayoutPrompt, "图1\"\"图2\"这类编号短标") {
		t.Fatal("vision prompt 应把图N 短标指到 caption")
	}
	if !strings.Contains(transcribePrompt, "按从上到下的顺序逐字转写") {
		t.Fatal("transcribe prompt 应给竖排读法指引")
	}
}

func TestVisionLayoutDropsHallucinatedTextAndNormalizesRoles(t *testing.T) {
	content := `{"elements":[` +
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

func TestVisionLayoutInvalidJSONReturnsError(t *testing.T) {
	layouter := newTestSmartLayouter(fakeVisionServer(t, `这不是 JSON`, nil).URL)
	if _, err := layouter.VisionLayout(context.Background(), sampleVisionRequest()); err == nil {
		t.Fatal("invalid JSON should return an error so客户端直接提示重试")
	}
}

func TestVisionLayoutAssignsElementIDs(t *testing.T) {
	content := `{"elements":[` +
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

func TestVisionSendsNoteTitleInPrompt(t *testing.T) {
	sawTitle := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := readAllBody(t, r)
		if strings.Contains(body, "笔记标题：我的笔记") {
			sawTitle = true
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` +
			jsonString(`{"elements":[]}`) + `}}]}`))
	}))
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	if _, err := layouter.VisionLayout(context.Background(), sampleVisionRequest()); err != nil {
		t.Fatalf("VisionLayout error: %v", err)
	}
	if !sawTitle {
		t.Fatal("prompt should embed note title")
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

func sampleTranscribeRequest() TranscribeRequest {
	return TranscribeRequest{
		Hint:        "我的笔记",
		ImageMime:   "image/png",
		ImageBase64: "dGVzdA==",
	}
}

func TestTranscribeParsesTextAndClampsConfidence(t *testing.T) {
	content := `{"text":" 先头小子 ","confidence":1.5}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.Transcribe(context.Background(), sampleTranscribeRequest())
	if err != nil {
		t.Fatalf("Transcribe error: %v", err)
	}
	if response.Text != "先头小子" {
		t.Fatalf("text = %q", response.Text)
	}
	if response.Confidence != 1 {
		t.Fatalf("confidence = %v, want 1", response.Confidence)
	}
}

func TestTranscribeEmptyTextClearsConfidence(t *testing.T) {
	content := `{"text":"   ","confidence":0.8}` // 整块无法辨认 → 空文本、把握清零
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.Transcribe(context.Background(), TranscribeRequest{ImageBase64: "dGVzdA=="})
	if err != nil {
		t.Fatalf("Transcribe error: %v", err)
	}
	if response.Text != "" || response.Confidence != 0 {
		t.Fatalf("response = %#v, want empty text / 0 confidence", response)
	}
}

func TestTranscribePureMarkEchoTreatedAsUnrecognized(t *testing.T) {
	// 干净裁剪图里不该有编号标签，纯编号回显即幻觉 → 视为未认出，
	// 客户端择优时自然保留原结果。
	content := `{"text":"m14","confidence":0.9}`
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.Transcribe(context.Background(), TranscribeRequest{ImageBase64: "dGVzdA=="})
	if err != nil {
		t.Fatalf("Transcribe error: %v", err)
	}
	if response.Text != "" || response.Confidence != 0 {
		t.Fatalf("response = %#v, want empty text / 0 confidence", response)
	}
}

func TestTranscribeMissingConfidenceDefaultsLenient(t *testing.T) {
	content := `{"text":"字"}` // 未自报把握 → 0.9，与整页识别元素默认一致
	layouter := newTestSmartLayouter(fakeVisionServer(t, content, nil).URL)
	response, err := layouter.Transcribe(context.Background(), sampleTranscribeRequest())
	if err != nil {
		t.Fatalf("Transcribe error: %v", err)
	}
	if response.Confidence != 0.9 {
		t.Fatalf("confidence = %v, want 0.9", response.Confidence)
	}
}

func TestTranscribeInvalidJSONReturnsError(t *testing.T) {
	layouter := newTestSmartLayouter(fakeVisionServer(t, `不是 JSON`, nil).URL)
	if _, err := layouter.Transcribe(context.Background(), sampleTranscribeRequest()); err == nil {
		t.Fatal("invalid JSON should return an error so客户端保留原识别结果")
	}
}

func TestTranscribeSendsHintInPrompt(t *testing.T) {
	sawHint := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := readAllBody(t, r)
		if strings.Contains(body, "提示：我的笔记") {
			sawHint = true
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` +
			jsonString(`{"text":"字","confidence":0.5}`) + `}}]}`))
	}))
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	if _, err := layouter.Transcribe(context.Background(), sampleTranscribeRequest()); err != nil {
		t.Fatalf("Transcribe error: %v", err)
	}
	if !sawHint {
		t.Fatal("prompt should embed the hint")
	}
}

func TestTranscribeEndpointRejectsEmptyImage(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil).WithVisionLayouter(newTestSmartLayouter("http://unused"))
	mux := http.NewServeMux()
	api.Register(mux)
	request := httptest.NewRequest(http.MethodPost, "/api/ink/smart-layout/transcribe",
		strings.NewReader(`{"imageBase64":""}`))
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", recorder.Code)
	}
}

func TestTranscribeEndpointRejectsNonPost(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil).WithVisionLayouter(newTestSmartLayouter("http://unused"))
	mux := http.NewServeMux()
	api.Register(mux)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/ink/smart-layout/transcribe", nil))
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", recorder.Code)
	}
}

func TestTranscribeEndpointWithoutLayouterFails(t *testing.T) {
	api := NewHTTPAPI(nil, 0, nil)
	mux := http.NewServeMux()
	api.Register(mux)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, httptest.NewRequest(http.MethodPost,
		"/api/ink/smart-layout/transcribe", strings.NewReader(`{"imageBase64":"dGVzdA=="}`)))
	if recorder.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", recorder.Code)
	}
}
