package recognition

type InkPoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	T int64   `json:"t,omitempty"`
}

type InkStroke struct {
	ID     string     `json:"id,omitempty"`
	Points []InkPoint `json:"points"`
}

type InkBounds struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type RecognizeRequest struct {
	SessionID string      `json:"sessionId,omitempty"`
	Hint      string      `json:"hint,omitempty"`
	Strokes   []InkStroke `json:"strokes"`
	Bounds    InkBounds   `json:"bounds"`
}

type RecognizedElement struct {
	Type     string         `json:"type"`
	Text     string         `json:"text,omitempty"`
	LaTeX    string         `json:"latex,omitempty"`
	X        float64        `json:"x"`
	Y        float64        `json:"y"`
	Width    float64        `json:"width"`
	Height   float64        `json:"height"`
	Points   []InkPoint     `json:"points,omitempty"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

type RecognizeResponse struct {
	Elements []RecognizedElement `json:"elements"`
}
