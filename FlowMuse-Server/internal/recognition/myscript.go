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
	body, err := json.Marshal(r.toMyScriptRequest(request))
	if err != nil {
		return RecognizeResponse{}, err
	}
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, r.config.Endpoint, bytes.NewReader(body))
	if err != nil {
		return RecognizeResponse{}, err
	}
	httpRequest.Header.Set("Content-Type", "application/json")
	httpRequest.Header.Set("applicationKey", r.config.AppKey)
	httpRequest.Header.Set("hmac", hmacSignature(r.config.HMACKey, body))

	response, err := r.client.Do(httpRequest)
	if err != nil {
		return RecognizeResponse{}, err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return RecognizeResponse{}, fmt.Errorf("MyScript recognition failed: HTTP %d", response.StatusCode)
	}
	var raw map[string]any
	if err := json.NewDecoder(response.Body).Decode(&raw); err != nil {
		return RecognizeResponse{}, err
	}
	result := parseMyScriptResponse(raw, request.Bounds)
	if len(result.Elements) == 0 {
		return RecognizeResponse{}, errors.New("MyScript returned no recognized elements")
	}
	return result, nil
}

func (r *MyScriptRecognizer) toMyScriptRequest(request RecognizeRequest) map[string]any {
	strokes := make([]map[string]any, 0, len(request.Strokes))
	for _, stroke := range request.Strokes {
		x := make([]float64, 0, len(stroke.Points))
		y := make([]float64, 0, len(stroke.Points))
		t := make([]int64, 0, len(stroke.Points))
		for _, point := range stroke.Points {
			x = append(x, point.X-request.Bounds.X)
			y = append(y, point.Y-request.Bounds.Y)
			t = append(t, point.T)
		}
		strokes = append(strokes, map[string]any{
			"id": stroke.ID,
			"x":  x,
			"y":  y,
			"t":  t,
		})
	}
	return map[string]any{
		"configuration": map[string]any{
			"lang":         "zh_CN",
			"contentTypes": []string{"Text", "Math", "Diagram"},
		},
		"content": map[string]any{
			"type":    "Raw Content",
			"strokes": strokes,
			"bounds": map[string]any{
				"x":      request.Bounds.X,
				"y":      request.Bounds.Y,
				"width":  request.Bounds.Width,
				"height": request.Bounds.Height,
			},
		},
	}
}

func hmacSignature(key string, body []byte) string {
	mac := hmac.New(sha512.New, []byte(key))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

func parseMyScriptResponse(raw map[string]any, bounds InkBounds) RecognizeResponse {
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

func parseRawElements(rawElements []any, fallback InkBounds) []RecognizedElement {
	elements := make([]RecognizedElement, 0, len(rawElements))
	for _, item := range rawElements {
		raw, ok := item.(map[string]any)
		if !ok {
			continue
		}
		elementType := normalizeType(stringValue(raw["type"]))
		box := boundsFromRaw(raw, fallback)
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
				Points: pointsFromRaw(raw),
			})
		}
	}
	return elements
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
