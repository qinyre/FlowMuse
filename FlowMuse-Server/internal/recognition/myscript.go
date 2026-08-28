package recognition

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type MyScriptConfig struct {
	AppKey   string
	HMACKey  string
	Endpoint string
	Timeout  time.Duration
}

type MyScriptRecognizer struct {
	config MyScriptConfig
	client *http.Client
}

func NewMyScriptRecognizer(config MyScriptConfig) *MyScriptRecognizer {
	timeout := config.Timeout
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	return &MyScriptRecognizer{
		config: config,
		client: &http.Client{Timeout: timeout},
	}
}

func (r *MyScriptRecognizer) Recognize(ctx context.Context, request RecognizeRequest) (RecognizeResponse, error) {
	if strings.TrimSpace(r.config.AppKey) == "" || strings.TrimSpace(r.config.HMACKey) == "" {
		return RecognizeResponse{}, errors.New("MyScript recognition is not configured")
	}
	switch strings.TrimSpace(request.Hint) {
	case "math":
		return r.recognizeContent(ctx, request, "Math")
	default:
		return r.recognizeContent(ctx, request, "Text")
	}
}

func (r *MyScriptRecognizer) recognizeContent(ctx context.Context, request RecognizeRequest, contentType string) (RecognizeResponse, error) {
	body, err := json.Marshal(r.toMyScriptRequest(request, contentType))
	if err != nil {
		return RecognizeResponse{}, err
	}
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, r.config.Endpoint, bytes.NewReader(body))
	if err != nil {
		return RecognizeResponse{}, err
	}
	httpRequest.Header.Set("Content-Type", "application/json")
	if contentType == "Math" {
		httpRequest.Header.Set("Accept", "application/x-latex,application/mathml+xml,application/vnd.myscript.jiix,application/json,text/plain")
	} else {
		httpRequest.Header.Set("Accept", "application/json,text/plain,application/vnd.myscript.jiix")
	}
	httpRequest.Header.Set("applicationKey", r.config.AppKey)
	httpRequest.Header.Set("hmac", hmacSignature(r.config.AppKey, r.config.HMACKey, body))

	response, err := r.client.Do(httpRequest)
	if err != nil {
		return RecognizeResponse{}, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		return RecognizeResponse{}, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return RecognizeResponse{}, fmt.Errorf(
			"MyScript recognition failed: HTTP %d: %s",
			response.StatusCode,
			strings.TrimSpace(string(responseBody)),
		)
	}
	if text := strings.TrimSpace(string(responseBody)); text != "" && !json.Valid(responseBody) {
		if contentType == "Math" {
			return RecognizeResponse{Elements: []RecognizedElement{mathTextElement(text, request.Bounds)}}, nil
		}
		return RecognizeResponse{Elements: []RecognizedElement{textElement(text, request.Bounds)}}, nil
	}
	var raw map[string]any
	if err := json.Unmarshal(responseBody, &raw); err != nil {
		return RecognizeResponse{}, err
	}
	result := parseMyScriptResponse(raw, request.Bounds, contentType)
	if len(result.Elements) == 0 {
		return RecognizeResponse{}, errors.New("MyScript returned no recognized elements")
	}
	return result, nil
}

func (r *MyScriptRecognizer) toMyScriptRequest(request RecognizeRequest, contentType string) map[string]any {
	strokes := make([]map[string]any, 0, len(request.Strokes))
	for _, stroke := range request.Strokes {
		x := make([]float64, 0, len(stroke.Points))
		y := make([]float64, 0, len(stroke.Points))
		t := make([]int64, 0, len(stroke.Points))
		for i, point := range stroke.Points {
			x = append(x, point.X-request.Bounds.X)
			y = append(y, point.Y-request.Bounds.Y)
			if point.T > 0 {
				t = append(t, point.T)
			} else {
				t = append(t, int64(i*10))
			}
		}
		strokes = append(strokes, map[string]any{
			"id":          stroke.ID,
			"pointerType": "pen",
			"x":           x,
			"y":           y,
			"t":           t,
		})
	}
	configuration := map[string]any{}
	if contentType == "Math" {
		configuration["lang"] = "en_US"
		configuration["math"] = map[string]any{
			"mimeTypes": []string{"application/x-latex", "application/mathml+xml", "application/vnd.myscript.jiix"},
			"solver":    map[string]any{"enable": true},
			"margin":    map[string]any{"top": 0, "left": 0, "right": 0, "bottom": 0},
		}
		configuration["export"] = map[string]any{
			"jiix": map[string]any{"strokes": true, "bounding-box": true},
		}
	} else {
		configuration["lang"] = "zh_CN"
		configuration["text"] = map[string]any{
			"mimeTypes": []string{"text/plain", "application/vnd.myscript.jiix"},
		}
		// 导出增强选项：JIIX 携带逐词 bounds（bounding-box 在 3.x 默认 false，显式钉死跨版本行为）。
		configuration["export"] = map[string]any{
			"jiix": map[string]any{
				"bounding-box": true,
				"text":         map[string]any{"words": true},
			},
		}
	}
	return map[string]any{
		"configuration": configuration,
		"contentType":   contentType,
		"xDPI":          96,
		"yDPI":          96,
		"width":         request.Bounds.Width,
		"height":        request.Bounds.Height,
		"strokeGroups":  []map[string]any{{"strokes": strokes}},
	}
}

func hmacSignature(appKey string, hmacKey string, body []byte) string {
	key := []byte(appKey + hmacKey)
	mac := hmac.New(sha512.New, key)
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

// parseMyScriptResponse 解析 MyScript 响应。bounds 参数在不同调用方语义不同：
// exports 主路径（text/plain/latex）把它整体作为单元素包围盒（绝对系）；
// elements 假想路径取其 X/Y 作加回原点、W/H 作尺寸兜底（见 parseRawElements）；
// jiix 字符串路径仅取 X/Y 作原点（见 parseJiixExport）。
func parseMyScriptResponse(raw map[string]any, bounds InkBounds, contentType string) RecognizeResponse {
	if exports, ok := raw["exports"].(map[string]any); ok {
		if latex := firstString(exports, "application/x-latex"); latex != "" {
			return RecognizeResponse{Elements: []RecognizedElement{mathTextElement(latex, bounds)}}
		}
		if text := firstString(exports, "text/plain"); text != "" {
			if contentType == "Math" {
				return RecognizeResponse{Elements: []RecognizedElement{mathTextElement(text, bounds)}}
			}
			return RecognizeResponse{Elements: []RecognizedElement{textElement(text, bounds)}}
		}
		// 官方 iink Batch API 以 exports["application/vnd.myscript.jiix"] 的 JSON 字符串
		// 交付 JIIX；仅在 text/plain 与 latex 均缺失时作为兜底解析（罕见路径加固）。
		if jiix := firstString(exports, "application/vnd.myscript.jiix"); jiix != "" {
			if elements := parseJiixExport(jiix, bounds); len(elements) > 0 {
				return RecognizeResponse{Elements: elements}
			}
		}
	}
	if elements, ok := raw["elements"].([]any); ok {
		return RecognizeResponse{Elements: parseRawElements(elements, bounds)}
	}
	if result, ok := raw["result"].(map[string]any); ok {
		if elements, ok := result["elements"].([]any); ok {
			return RecognizeResponse{Elements: parseRawElements(elements, bounds)}
		}
		if latex := stringValue(result["latex"]); latex != "" {
			return RecognizeResponse{Elements: []RecognizedElement{mathTextElement(latex, bounds)}}
		}
		if label := stringValue(result["text"]); label != "" {
			return RecognizeResponse{Elements: []RecognizedElement{textElement(label, bounds)}}
		}
	}
	if latex := stringValue(raw["latex"]); latex != "" {
		return RecognizeResponse{Elements: []RecognizedElement{mathTextElement(latex, bounds)}}
	}
	if label := stringValue(raw["text"]); label != "" {
		return RecognizeResponse{Elements: []RecognizedElement{textElement(label, bounds)}}
	}
	return RecognizeResponse{}
}

func looksLikeMath(latex string) bool {
	latex = strings.TrimSpace(latex)
	if latex == "" {
		return false
	}
	if strings.ContainsAny(latex, `=+\-*/^_{}\()[]<>∫√ΣΠ`) {
		return true
	}
	for _, token := range []string{`\frac`, `\sqrt`, `\int`, `\sum`, `\prod`, `\lim`, `\sin`, `\cos`, `\tan`, `\log`, `\ln`, `\alpha`, `\beta`, `\theta`} {
		if strings.Contains(latex, token) {
			return true
		}
	}
	return false
}

// parseRawElements 解析假想的顶层 elements 数组。该响应形状来自 issue #15 验收夹具
// （官方 iink Batch API 未见顶层 elements 数组，真实 JIIX 走 exports jiix 字符串，
// 见 parseJiixExport）。toMyScriptRequest 提交笔画前已减去 inkBounds.X/Y，此路径的
// 坐标因此以 ink 左上角为原点（px 相对系），解析后统一加回原点得画布绝对坐标；
// fallback 须用相对系（x/y 兜底 0），避免缺 bounds 的元素被双重偏移。
func parseRawElements(rawElements []any, inkBounds InkBounds) []RecognizedElement {
	relativeFallback := InkBounds{X: 0, Y: 0, Width: inkBounds.Width, Height: inkBounds.Height}
	elements := make([]RecognizedElement, 0, len(rawElements))
	for _, item := range rawElements {
		raw, ok := item.(map[string]any)
		if !ok {
			continue
		}
		elementType := normalizeType(stringValue(raw["type"]))
		box := boundsFromRaw(raw, relativeFallback)
		box.X += inkBounds.X
		box.Y += inkBounds.Y
		switch elementType {
		case "math":
			latex := firstString(raw, "latex", "label", "text")
			if latex != "" {
				elements = append(elements, mathTextElement(latex, box))
			}
		case "text":
			text := firstString(raw, "text", "label", "value")
			if text != "" {
				elements = append(elements, textElement(text, box))
			}
		case "rectangle", "ellipse", "diamond", "line", "arrow":
			elements = append(elements, RecognizedElement{
				Type:   elementType,
				X:      box.X,
				Y:      box.Y,
				Width:  box.Width,
				Height: box.Height,
				Points: shiftedPoints(pointsFromRaw(raw), inkBounds.X, inkBounds.Y),
			})
		}
	}
	return elements
}

// jiixMmToPx 把 JIIX 毫米坐标换算为像素（xDPI/yDPI=96），与官方 iinkJS 示例的
// mmToPixel(mm)=96*mm/25.4 一致。
const jiixMmToPx = 96.0 / 25.4

// parseJiixExport 解析 exports["application/vnd.myscript.jiix"] 交付的 JIIX JSON 字符串。
// JIIX 坐标为毫米、与提交笔画同帧（toMyScriptRequest 已把笔画归一到 ink 左上角原点），
// 按 px = mm × jiixMmToPx + inkBounds.X/Y 换算回画布绝对坐标。解析失败或无可用元素
// 返回 nil，由调用方 fallthrough 到既有入口。
//
// 官方形状（iinkTS 类型定义与论坛真实样本）：Text 根节点 type="Text"、words 数组在根上，
// word 节点没有 type 字段（一律按 text 处理）；Math 的 expressions 是 operands 递归细类树
// （"number"/"symbol" 等 23 种 type），逐节点平铺不适合，改用根节点自身做单 math 元素。
func parseJiixExport(jiix string, inkBounds InkBounds) []RecognizedElement {
	var root map[string]any
	if err := json.Unmarshal([]byte(jiix), &root); err != nil {
		return nil
	}
	if words, ok := nodeArray(root, "words"); ok {
		return jiixWordElements(words, inkBounds)
	}
	return jiixRootElement(root, inkBounds)
}

// nodeArray 返回 root[key] 的非空数组；空数组视为未命中（回落根分支）。
// 元素合法性由调用方逐节点校验，全非法时不回落根（与 jiixWordElements 的跳过语义一致）。
func nodeArray(root map[string]any, key string) ([]any, bool) {
	items, ok := root[key].([]any)
	if !ok || len(items) == 0 {
		return nil, false
	}
	return items, true
}

// jiixWordElements 把 JIIX words 数组（无 type 字段，一律 text）换算为绝对坐标元素。
// 空白词（label trim 后为空）与缺 bounding-box 的节点跳过——mm 系下兜 0 会把元素
// 拉到 ink 原点左侧形成负偏移，故不做静默兜底。
func jiixWordElements(words []any, inkBounds InkBounds) []RecognizedElement {
	elements := make([]RecognizedElement, 0, len(words))
	for _, item := range words {
		node, ok := item.(map[string]any)
		if !ok {
			continue
		}
		label := firstString(node, "label")
		if label == "" {
			continue
		}
		box, ok := jiixBounds(node)
		if !ok {
			continue
		}
		elements = append(elements, textElement(label, mmBoundsToAbsolute(box, inkBounds)))
	}
	return elements
}

// jiixRootElement 用根节点自身产出单元素（Math 根的 expressions 不平铺；Text 根在
// words 缺失/为空时回落到此）。仅接受 text/math 类型且 label 与 bounding-box 齐全的根，
// 其余（如 type="Document"）返回 nil。
func jiixRootElement(root map[string]any, inkBounds InkBounds) []RecognizedElement {
	label := firstString(root, "latex", "label", "text")
	if label == "" {
		return nil
	}
	box, ok := jiixBounds(root)
	if !ok {
		return nil
	}
	box = mmBoundsToAbsolute(box, inkBounds)
	switch normalizeType(stringValue(root["type"])) {
	case "math":
		return []RecognizedElement{mathTextElement(label, box)}
	case "text":
		return []RecognizedElement{textElement(label, box)}
	default:
		return nil
	}
}

// jiixBounds 严格读取 JIIX 节点的 bounding-box（官方唯一键名），返回原始毫米值；
// 缺键或 x/y/width/height 任一非数值时 ok=false。
func jiixBounds(node map[string]any) (InkBounds, bool) {
	box, ok := node["bounding-box"].(map[string]any)
	if !ok {
		return InkBounds{}, false
	}
	x, okX := box["x"].(float64)
	y, okY := box["y"].(float64)
	width, okWidth := box["width"].(float64)
	height, okHeight := box["height"].(float64)
	if !okX || !okY || !okWidth || !okHeight {
		return InkBounds{}, false
	}
	return InkBounds{X: x, Y: y, Width: width, Height: height}, true
}

// mmBoundsToAbsolute 把毫米 bounds 换算为画布绝对坐标（纯缩放+原点，与官方示例一致）。
func mmBoundsToAbsolute(box InkBounds, inkBounds InkBounds) InkBounds {
	return InkBounds{
		X:      box.X*jiixMmToPx + inkBounds.X,
		Y:      box.Y*jiixMmToPx + inkBounds.Y,
		Width:  box.Width * jiixMmToPx,
		Height: box.Height * jiixMmToPx,
	}
}

// shiftedPoints 把相对系 points 平移 dx/dy；nil 进 nil 出（保 omitempty 语义）。
func shiftedPoints(points []InkPoint, dx float64, dy float64) []InkPoint {
	if points == nil {
		return nil
	}
	for i := range points {
		points[i].X += dx
		points[i].Y += dy
	}
	return points
}

func normalizeType(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	switch value {
	case "math", "equation", "formula":
		return "math"
	case "text", "word":
		return "text"
	case "rectangle", "rect":
		return "rectangle"
	case "ellipse", "circle":
		return "ellipse"
	case "diamond":
		return "diamond"
	case "arrow":
		return "arrow"
	case "line", "connector", "stroke":
		return "line"
	default:
		return value
	}
}

func textElement(text string, bounds InkBounds) RecognizedElement {
	return RecognizedElement{
		Type:   "text",
		Text:   text,
		X:      bounds.X,
		Y:      bounds.Y,
		Width:  bounds.Width,
		Height: bounds.Height,
	}
}

func mathTextElement(latex string, bounds InkBounds) RecognizedElement {
	return RecognizedElement{
		Type:   "math",
		LaTeX:  latex,
		X:      bounds.X,
		Y:      bounds.Y,
		Width:  bounds.Width,
		Height: bounds.Height,
	}
}

func boundsFromRaw(raw map[string]any, fallback InkBounds) InkBounds {
	if box, ok := raw["bounds"].(map[string]any); ok {
		return InkBounds{
			X:      floatValue(box["x"], fallback.X),
			Y:      floatValue(box["y"], fallback.Y),
			Width:  floatValue(box["width"], fallback.Width),
			Height: floatValue(box["height"], fallback.Height),
		}
	}
	return InkBounds{
		X:      floatValue(raw["x"], fallback.X),
		Y:      floatValue(raw["y"], fallback.Y),
		Width:  floatValue(raw["width"], fallback.Width),
		Height: floatValue(raw["height"], fallback.Height),
	}
}

func pointsFromRaw(raw map[string]any) []InkPoint {
	items, ok := raw["points"].([]any)
	if !ok {
		return nil
	}
	points := make([]InkPoint, 0, len(items))
	for _, item := range items {
		point, ok := item.(map[string]any)
		if !ok {
			continue
		}
		points = append(points, InkPoint{
			X: floatValue(point["x"], 0),
			Y: floatValue(point["y"], 0),
		})
	}
	return points
}

func firstString(raw map[string]any, keys ...string) string {
	for _, key := range keys {
		if value := stringValue(raw[key]); value != "" {
			return value
		}
	}
	return ""
}

func stringValue(value any) string {
	text, ok := value.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(text)
}

func floatValue(value any, fallback float64) float64 {
	number, ok := value.(float64)
	if !ok {
		return fallback
	}
	return number
}
