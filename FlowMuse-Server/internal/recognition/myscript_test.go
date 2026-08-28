package recognition

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHMACSignatureSignsRequestBody(t *testing.T) {
	got := hmacSignature("app", "secret", []byte("hello"))
	const want = "01f9d74906d5ac3d38004370023c4f8ba9d5af16c20698242eb913f8b8f7a376c23de1328a1d7d3505eaa91a21a3347daccdc1c12831c600e827fae90fa3a2ae"
	if got != want {
		t.Fatalf("hmacSignature() = %s, want %s", got, want)
	}
}

// almostEqual 判断浮点数在 1e-6 容差内相等（JIIX 毫米×96/25.4 的小数乘法无法精确表示）。
func almostEqual(a float64, b float64) bool {
	diff := a - b
	if diff < 0 {
		diff = -diff
	}
	return diff < 1e-6
}

// rawElementsFromJSON 把 canned JSON 解析为 parseRawElements 的入参形状。
func rawElementsFromJSON(t *testing.T, input string) []any {
	t.Helper()
	var elements []any
	if err := json.Unmarshal([]byte(input), &elements); err != nil {
		t.Fatalf("invalid test fixture %q: %v", input, err)
	}
	return elements
}

// sampleJiixWords 复刻官方 JIIX Text 形状：根 type=Text、words 在根上、
// word 节点无 type 字段、键名 bounding-box、数值为合成毫米量级。
const sampleJiixWords = `{"type":"Text","bounding-box":{"x":0,"y":0,"width":60,"height":20},` +
	`"words":[{"label":"hello","bounding-box":{"x":20,"y":10,"width":20,"height":8}},` +
	`{"label":"world","bounding-box":{"x":40,"y":10,"width":20,"height":8}}]}`

// TestParseRawElementsShiftsJiixCoordinatesToAbsolute 验证假想 elements 路径
// （issue #15 验收夹具形状）把相对坐标统一加回 ink 原点，含 shape 的 points。
func TestParseRawElementsShiftsJiixCoordinatesToAbsolute(t *testing.T) {
	inkBounds := InkBounds{X: 120, Y: 80, Width: 200, Height: 100}
	cases := []struct {
		name    string
		element string
		check   func(t *testing.T, elements []RecognizedElement)
	}{
		{
			name:    "text 元素加回原点",
			element: `{"type":"text","text":"你好","bounds":{"x":10,"y":5,"width":80,"height":30}}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				got := elements[0]
				if got.Type != "text" || got.Text != "你好" {
					t.Fatalf("type/text = %s/%q", got.Type, got.Text)
				}
				if got.X != 130 || got.Y != 85 || got.Width != 80 || got.Height != 30 {
					t.Fatalf("bounds = %+v, want {130 85 80 30}", got)
				}
			},
		},
		{
			name:    "word 别名归一为 text",
			element: `{"type":"word","label":"hello","bounds":{"x":40,"y":60,"width":60,"height":25}}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				got := elements[0]
				if got.Type != "text" || got.Text != "hello" {
					t.Fatalf("type/text = %s/%q", got.Type, got.Text)
				}
				if got.X != 160 || got.Y != 140 || got.Width != 60 || got.Height != 25 {
					t.Fatalf("bounds = %+v, want {160 140 60 25}", got)
				}
			},
		},
		{
			name:    "math 元素加回原点",
			element: `{"type":"math","latex":"a+b","bounds":{"x":0,"y":10,"width":50,"height":20}}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				got := elements[0]
				if got.Type != "math" || got.LaTeX != "a+b" {
					t.Fatalf("type/latex = %s/%q", got.Type, got.LaTeX)
				}
				if got.X != 120 || got.Y != 90 || got.Width != 50 || got.Height != 20 {
					t.Fatalf("bounds = %+v, want {120 90 50 20}", got)
				}
			},
		},
		{
			name:    "line 元素 box 与 points 同时加回原点",
			element: `{"type":"line","bounds":{"x":1,"y":2,"width":3,"height":4},"points":[{"x":5,"y":5},{"x":25,"y":15}]}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				got := elements[0]
				if got.Type != "line" {
					t.Fatalf("type = %s, want line", got.Type)
				}
				if got.X != 121 || got.Y != 82 || got.Width != 3 || got.Height != 4 {
					t.Fatalf("bounds = %+v, want {121 82 3 4}", got)
				}
				if len(got.Points) != 2 {
					t.Fatalf("points 数量 = %d, want 2", len(got.Points))
				}
				if got.Points[0].X != 125 || got.Points[0].Y != 85 {
					t.Fatalf("points[0] = %+v, want {125 85}", got.Points[0])
				}
				if got.Points[1].X != 145 || got.Points[1].Y != 95 {
					t.Fatalf("points[1] = %+v, want {145 95}", got.Points[1])
				}
			},
		},
		{
			name:    "rectangle 的 points 一并偏移",
			element: `{"type":"rectangle","bounds":{"x":5,"y":5,"width":20,"height":10},"points":[{"x":5,"y":5},{"x":25,"y":15}]}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				got := elements[0]
				if got.X != 125 || got.Y != 85 || got.Width != 20 || got.Height != 10 {
					t.Fatalf("bounds = %+v, want {125 85 20 10}", got)
				}
				if got.Points[0].X != 125 || got.Points[0].Y != 85 {
					t.Fatalf("points[0] = %+v, want {125 85}", got.Points[0])
				}
			},
		},
		{
			name:    "无 points 的 shape 保持 Points 为空",
			element: `{"type":"line","bounds":{"x":1,"y":2,"width":3,"height":4}}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 1 {
					t.Fatalf("elements 数量 = %d, want 1", len(elements))
				}
				if elements[0].Points != nil {
					t.Fatalf("points = %+v, want nil（omitempty 语义）", elements[0].Points)
				}
			},
		},
		{
			name:    "未知 type 被丢弃",
			element: `{"type":"foo","text":"x","bounds":{"x":1,"y":2,"width":3,"height":4}}`,
			check: func(t *testing.T, elements []RecognizedElement) {
				if len(elements) != 0 {
					t.Fatalf("elements 数量 = %d, want 0", len(elements))
				}
			},
		},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			elements := parseRawElements(rawElementsFromJSON(t, "["+tt.element+"]"), inkBounds)
			tt.check(t, elements)
		})
	}
}

// TestParseRawElementsFallbackUsesInkOrigin 验证缺 bounds 字段的兜底走相对系
// （x/y 兜 0 再加原点），不会双重偏移。
func TestParseRawElementsFallbackUsesInkOrigin(t *testing.T) {
	inkBounds := InkBounds{X: 120, Y: 80, Width: 200, Height: 100}
	cases := []struct {
		name    string
		element string
		want    InkBounds
	}{
		{
			name:    "整块缺 bounds 兜 ink 原点与整体尺寸",
			element: `{"type":"text","text":"x"}`,
			want:    InkBounds{X: 120, Y: 80, Width: 200, Height: 100},
		},
		{
			name:    "bounds 只有 x",
			element: `{"type":"text","text":"x","bounds":{"x":10}}`,
			want:    InkBounds{X: 130, Y: 80, Width: 200, Height: 100},
		},
		{
			name:    "bounds 只有 width",
			element: `{"type":"text","text":"x","bounds":{"width":60}}`,
			want:    InkBounds{X: 120, Y: 80, Width: 60, Height: 100},
		},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			elements := parseRawElements(rawElementsFromJSON(t, "["+tt.element+"]"), inkBounds)
			if len(elements) != 1 {
				t.Fatalf("elements 数量 = %d, want 1", len(elements))
			}
			got := elements[0]
			if got.X != tt.want.X || got.Y != tt.want.Y || got.Width != tt.want.Width || got.Height != tt.want.Height {
				t.Fatalf("bounds = {%f %f %f %f}, want %+v", got.X, got.Y, got.Width, got.Height, tt.want)
			}
		})
	}
}

// TestParseMyScriptResponseExportsPathUnchanged 验证 exports 主路径优先级与整盒语义不变，
// 特别是 text/plain 与 jiix 字符串双键并存（export.jiix.text.words 配置生效后的真实常态）
// 时必须仍走主路径单元素。
func TestParseMyScriptResponseExportsPathUnchanged(t *testing.T) {
	bounds := InkBounds{X: 100, Y: 200, Width: 300, Height: 150}

	t.Run("text/plain 单键返回整盒单元素", func(t *testing.T) {
		raw := map[string]any{"exports": map[string]any{"text/plain": "你好"}}
		elements := parseMyScriptResponse(raw, bounds, "Text").Elements
		if len(elements) != 1 || elements[0].Type != "text" || elements[0].Text != "你好" {
			t.Fatalf("elements = %+v", elements)
		}
		if elements[0].X != 100 || elements[0].Y != 200 || elements[0].Width != 300 || elements[0].Height != 150 {
			t.Fatalf("bounds = %+v, want 整盒 {100 200 300 150}", elements[0])
		}
	})

	t.Run("x-latex 单键返回整盒 math", func(t *testing.T) {
		raw := map[string]any{"exports": map[string]any{"application/x-latex": "a+b"}}
		elements := parseMyScriptResponse(raw, bounds, "Math").Elements
		if len(elements) != 1 || elements[0].Type != "math" || elements[0].LaTeX != "a+b" {
			t.Fatalf("elements = %+v", elements)
		}
		if elements[0].X != 100 || elements[0].Width != 300 {
			t.Fatalf("bounds = %+v, want 整盒", elements[0])
		}
	})

	t.Run("双键并存必须仍走 text/plain 主路径", func(t *testing.T) {
		raw := map[string]any{"exports": map[string]any{
			"text/plain":                     "你好",
			"application/vnd.myscript.jiix": sampleJiixWords,
		}}
		elements := parseMyScriptResponse(raw, bounds, "Text").Elements
		if len(elements) != 1 || elements[0].Text != "你好" {
			t.Fatalf("elements = %+v, want 单个 text 元素（不得翻转为逐词多元素）", elements)
		}
		if elements[0].Width != 300 {
			t.Fatalf("width = %f, want 整盒 300", elements[0].Width)
		}
	})
}

// TestParseJiixExportConvertsMillimetresToAbsolutePixels 验证真实 JIIX 入口的
// 毫米→像素换算与官方形状解析（word 无 type、bounding-box 键名、expressions 不平铺）。
func TestParseJiixExportConvertsMillimetresToAbsolutePixels(t *testing.T) {
	inkBounds := InkBounds{X: 100, Y: 200, Width: 300, Height: 150}
	s := jiixMmToPx

	t.Run("words 逐词换算为绝对坐标", func(t *testing.T) {
		elements := parseJiixExport(sampleJiixWords, inkBounds)
		if len(elements) != 2 {
			t.Fatalf("elements 数量 = %d, want 2", len(elements))
		}
		first := elements[0]
		if first.Type != "text" || first.Text != "hello" {
			t.Fatalf("第一个元素 type/text = %s/%q（word 无 type，应默认按 text）", first.Type, first.Text)
		}
		if !almostEqual(first.X, 100+20*s) || !almostEqual(first.Y, 200+10*s) ||
			!almostEqual(first.Width, 20*s) || !almostEqual(first.Height, 8*s) {
			t.Fatalf("第一个元素 bounds = {%f %f %f %f}", first.X, first.Y, first.Width, first.Height)
		}
		// 字面量锚点：96/25.4 是官方换算契约，防止 jiixMmToPx 常量被误改而断言自引用放行。
		if !almostEqual(first.X, 175.5905511811) || !almostEqual(first.Width, 75.5905511811) {
			t.Fatalf("第一个元素 = {%f %f}, want 字面量 {175.5905511811 75.5905511811}", first.X, first.Width)
		}
		second := elements[1]
		if second.Text != "world" || !almostEqual(second.X, 100+40*s) {
			t.Fatalf("第二个元素 = %+v", second)
		}
	})

	t.Run("Math 根节点单元素", func(t *testing.T) {
		jiix := `{"type":"Math","label":"a+b","bounding-box":{"x":87.9,"y":55.09,"width":10.2,"height":7.3}}`
		elements := parseJiixExport(jiix, inkBounds)
		if len(elements) != 1 {
			t.Fatalf("elements 数量 = %d, want 1", len(elements))
		}
		got := elements[0]
		if got.Type != "math" || got.LaTeX != "a+b" {
			t.Fatalf("type/latex = %s/%q", got.Type, got.LaTeX)
		}
		if !almostEqual(got.X, 100+87.9*s) || !almostEqual(got.Y, 200+55.09*s) ||
			!almostEqual(got.Width, 10.2*s) || !almostEqual(got.Height, 7.3*s) {
			t.Fatalf("bounds = {%f %f %f %f}", got.X, got.Y, got.Width, got.Height)
		}
	})

	t.Run("words 空数组回落根节点单元素", func(t *testing.T) {
		jiix := `{"type":"Text","label":"你好","bounding-box":{"x":0,"y":0,"width":60,"height":20},"words":[]}`
		elements := parseJiixExport(jiix, inkBounds)
		if len(elements) != 1 || elements[0].Text != "你好" {
			t.Fatalf("elements = %+v, want 根节点单 text", elements)
		}
		if !almostEqual(elements[0].Width, 60*s) || !almostEqual(elements[0].Height, 20*s) {
			t.Fatalf("bounds = {%f %f}", elements[0].Width, elements[0].Height)
		}
	})

	t.Run("expressions 不平铺回落根节点", func(t *testing.T) {
		jiix := `{"type":"Text","label":"你好","bounding-box":{"x":0,"y":0,"width":60,"height":20},` +
			`"expressions":[{"type":"=","label":"x"}]}`
		elements := parseJiixExport(jiix, inkBounds)
		if len(elements) != 1 || elements[0].Text != "你好" {
			t.Fatalf("elements = %+v, want 忽略 expressions 后的根节点单 text", elements)
		}
	})

	t.Run("words 与 expressions 双非空时 words 胜出", func(t *testing.T) {
		jiix := `{"type":"Text","words":[{"label":"hello","bounding-box":{"x":20,"y":10,"width":20,"height":8}},` +
			`{"label":"world","bounding-box":{"x":40,"y":10,"width":20,"height":8}}],` +
			`"expressions":[{"type":"="}]}`
		if elements := parseJiixExport(jiix, inkBounds); len(elements) != 2 {
			t.Fatalf("elements 数量 = %d, want 2（words 优先）", len(elements))
		}
	})

	t.Run("空白词与缺 bounding-box 的词被跳过", func(t *testing.T) {
		jiix := `{"type":"Text","words":[{"label":"hello","bounding-box":{"x":20,"y":10,"width":20,"height":8}},` +
			`{"label":" ","bounding-box":{"x":1,"y":1,"width":2,"height":2}},` +
			`{"label":"nobbox"},{"label":"half","bounding-box":{"x":20}}]}`
		elements := parseJiixExport(jiix, inkBounds)
		if len(elements) != 1 || elements[0].Text != "hello" {
			t.Fatalf("elements = %+v, want 仅 hello（空白词带 bbox 也须跳过；bbox 字段残缺须跳过）", elements)
		}
	})

	t.Run("非法 JSON 返回 nil", func(t *testing.T) {
		if elements := parseJiixExport(`{"type":`, inkBounds); elements != nil {
			t.Fatalf("elements = %+v, want nil", elements)
		}
	})

	t.Run("Document 根未知类型返回 nil", func(t *testing.T) {
		jiix := `{"type":"Document","label":"x","bounding-box":{"x":0,"y":0,"width":10,"height":10}}`
		if elements := parseJiixExport(jiix, inkBounds); elements != nil {
			t.Fatalf("elements = %+v, want nil", elements)
		}
	})
}

// TestParseMyScriptResponseJiixStringFallback 验证 jiix 字符串兜底入口与
// result.elements 嵌套路径的原点修复。
func TestParseMyScriptResponseJiixStringFallback(t *testing.T) {
	t.Run("exports 仅 jiix 字符串时走 parseJiixExport", func(t *testing.T) {
		raw := map[string]any{"exports": map[string]any{
			"application/vnd.myscript.jiix": sampleJiixWords,
		}}
		elements := parseMyScriptResponse(raw, InkBounds{X: 100, Y: 200, Width: 300, Height: 150}, "Text").Elements
		if len(elements) != 2 || elements[0].Text != "hello" {
			t.Fatalf("elements = %+v, want 逐词元素", elements)
		}
		if !almostEqual(elements[0].X, 100+20*jiixMmToPx) {
			t.Fatalf("X = %f, want %f", elements[0].X, 100+20*jiixMmToPx)
		}
	})

	t.Run("jiix 解析失败时 fallthrough 到 elements 路径", func(t *testing.T) {
		raw := map[string]any{
			"exports": map[string]any{"application/vnd.myscript.jiix": `{"type":`},
			"elements": []any{map[string]any{
				"type":   "text",
				"text":   "兜底",
				"bounds": map[string]any{"x": 10.0, "y": 5.0, "width": 80.0, "height": 30.0},
			}},
		}
		elements := parseMyScriptResponse(raw, InkBounds{X: 120, Y: 80, Width: 200, Height: 100}, "Text").Elements
		if len(elements) != 1 || elements[0].Text != "兜底" || elements[0].X != 130 {
			t.Fatalf("elements = %+v, want 走 elements 路径的 {兜底 X=130}", elements)
		}
	})

	t.Run("result.elements 嵌套路径加回原点", func(t *testing.T) {
		raw := map[string]any{"result": map[string]any{"elements": []any{
			map[string]any{
				"type":   "text",
				"text":   "嵌套",
				"bounds": map[string]any{"x": 10.0, "y": 5.0, "width": 80.0, "height": 30.0},
			},
		}}}
		elements := parseMyScriptResponse(raw, InkBounds{X: 120, Y: 80, Width: 200, Height: 100}, "Text").Elements
		if len(elements) != 1 {
			t.Fatalf("elements 数量 = %d, want 1", len(elements))
		}
		if elements[0].X != 130 || elements[0].Y != 85 {
			t.Fatalf("bounds = {%f %f}, want {130 85}", elements[0].X, elements[0].Y)
		}
	})
}

// TestToMyScriptRequestExportConfig 验证 Text/Math 请求的 jiix 导出配置。
func TestToMyScriptRequestExportConfig(t *testing.T) {
	recognizer := NewMyScriptRecognizer(MyScriptConfig{})
	request := RecognizeRequest{
		Strokes: []InkStroke{{Points: []InkPoint{{X: 20, Y: 30}, {X: 40, Y: 50}}}},
		Bounds: InkBounds{X: 10, Y: 20, Width: 100, Height: 50},
	}
	jiixOf := func(contentType string) map[string]any {
		body := recognizer.toMyScriptRequest(request, contentType)
		configuration, ok := body["configuration"].(map[string]any)
		if !ok {
			t.Fatalf("%s configuration 缺失", contentType)
		}
		export, ok := configuration["export"].(map[string]any)
		if !ok {
			t.Fatalf("%s export 缺失", contentType)
		}
		jiix, ok := export["jiix"].(map[string]any)
		if !ok {
			t.Fatalf("%s export.jiix 缺失", contentType)
		}
		return jiix
	}
	textJIIX := jiixOf("Text")
	if textJIIX["bounding-box"] != true {
		t.Fatalf("Text bounding-box = %v, want true", textJIIX["bounding-box"])
	}
	textConfig, ok := textJIIX["text"].(map[string]any)
	if !ok || textConfig["words"] != true {
		t.Fatalf("Text export.jiix.text.words 异常: %+v", textJIIX)
	}
	mathJIIX := jiixOf("Math")
	if mathJIIX["bounding-box"] != true || mathJIIX["strokes"] != true {
		t.Fatalf("Math export.jiix = %+v, want bounding-box 与 strokes 均 true", mathJIIX)
	}
}

// TestRecognizeEndToEndWithStubMyScript 以 httptest 伪 MyScript（官方形状响应：
// exports 含 jiix 字符串、无 text/plain）做端到端验证：请求侧对称契约（笔画已减原点、
// 书写区尺寸、jiix 导出配置、Accept 头）与响应侧绝对坐标。handler 只捕获请求，
// 断言全部在测试主体进行。
func TestRecognizeEndToEndWithStubMyScript(t *testing.T) {
	cases := []struct {
		hint     string
		wantText bool // true=Text 配置（export.jiix.text.words）；false=Math 配置（export.jiix.strokes）
	}{
		{hint: "", wantText: true},
		{hint: "math", wantText: false},
	}
	for _, tt := range cases {
		t.Run("hint="+tt.hint, func(t *testing.T) {
			type capturedRequest struct {
				body   []byte
				accept string
			}
			captured := make(chan capturedRequest, 1)
			stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, _ := io.ReadAll(r.Body)
				captured <- capturedRequest{body: body, accept: r.Header.Get("Accept")}
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`{"exports":{"application/vnd.myscript.jiix":` + jsonString(sampleJiixWords) + `}}`))
			}))
			t.Cleanup(stub.Close)

			recognizer := NewMyScriptRecognizer(MyScriptConfig{
				AppKey:   "app",
				HMACKey:  "secret",
				Endpoint: stub.URL,
			})
			request := RecognizeRequest{
				Hint:    tt.hint,
				Strokes: []InkStroke{{ID: "s1", Points: []InkPoint{{X: 110, Y: 210}, {X: 150, Y: 240}}}},
				Bounds:  InkBounds{X: 100, Y: 200, Width: 300, Height: 150},
			}
			response, err := recognizer.Recognize(context.Background(), request)
			if err != nil {
				t.Fatalf("Recognize() 失败: %v", err)
			}
			if len(response.Elements) != 2 {
				t.Fatalf("elements 数量 = %d, want 2", len(response.Elements))
			}
			first := response.Elements[0]
			if first.Text != "hello" || !almostEqual(first.X, 175.5905511811) || !almostEqual(first.Y, 237.7952755906) {
				t.Fatalf("第一个元素 = {%q %f %f}, want 绝对坐标 {hello 175.5905511811 237.7952755906}", first.Text, first.X, first.Y)
			}

			sent := <-captured
			if !strings.Contains(sent.accept, "application/vnd.myscript.jiix") {
				t.Fatalf("Accept = %q, want 含 jiix MIME", sent.accept)
			}
			var body map[string]any
			if err := json.Unmarshal(sent.body, &body); err != nil {
				t.Fatalf("发出的请求体不是合法 JSON: %v", err)
			}
			if body["contentType"] != map[bool]string{true: "Text", false: "Math"}[tt.wantText] {
				t.Fatalf("contentType = %v", body["contentType"])
			}
			if body["width"] != float64(300) || body["height"] != float64(150) {
				t.Fatalf("书写区 = %v/%v, want 300/150（inkBounds.W/H）", body["width"], body["height"])
			}
			groups, ok := body["strokeGroups"].([]any)
			if !ok || len(groups) != 1 {
				t.Fatalf("strokeGroups 异常: %+v", body["strokeGroups"])
			}
			strokes, ok := groups[0].(map[string]any)["strokes"].([]any)
			if !ok || len(strokes) != 1 {
				t.Fatalf("strokes 异常: %+v", groups[0])
			}
			stroke := strokes[0].(map[string]any)
			x, ok := stroke["x"].([]any)
			y, okY := stroke["y"].([]any)
			if !ok || !okY || len(x) != 2 || len(y) != 2 {
				t.Fatalf("笔画坐标异常: %+v", stroke)
			}
			if x[0] != float64(10) || y[0] != float64(10) {
				t.Fatalf("首个点 = (%v,%v), want (10,10)（绝对 110,210 减 ink 原点 100,200）", x[0], y[0])
			}
			if x[1] != float64(50) || y[1] != float64(40) {
				t.Fatalf("次个点 = (%v,%v), want (50,40)", x[1], y[1])
			}
			configuration, ok := body["configuration"].(map[string]any)
			if !ok {
				t.Fatalf("configuration 缺失")
			}
			export, ok := configuration["export"].(map[string]any)
			if !ok {
				t.Fatalf("export 缺失")
			}
			jiix, ok := export["jiix"].(map[string]any)
			if !ok || jiix["bounding-box"] != true {
				t.Fatalf("export.jiix.bounding-box 异常: %+v", jiix)
			}
			if tt.wantText {
				textConfig, ok := jiix["text"].(map[string]any)
				if !ok || textConfig["words"] != true {
					t.Fatalf("export.jiix.text.words 异常: %+v", jiix)
				}
			} else if jiix["strokes"] != true {
				t.Fatalf("export.jiix.strokes 异常: %+v", jiix)
			}
		})
	}
}
