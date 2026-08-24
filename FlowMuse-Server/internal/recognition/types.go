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

type SmartLayoutRequest struct {
	Pages  []SmartLayoutPage     `json:"pages"`
	Blocks []SmartLayoutInkBlock `json:"blocks"`
}

type SmartLayoutBlockRequest struct {
	Block SmartLayoutInkBlock `json:"block"`
}

type SmartLayoutComposeRequest struct {
	Pages      []SmartLayoutPage            `json:"pages"`
	Blocks     []SmartLayoutRecognizedBlock `json:"blocks"`
	Elements   []SmartLayoutElementRef      `json:"elements,omitempty"`
	LayoutHint string                        `json:"layoutHint,omitempty"`
}

// SmartLayoutElementRef 是 compose 请求中"非笔迹元素"的最小摘要，供 AI 判定整页布局。
type SmartLayoutElementRef struct {
	ID       string     `json:"id"`
	Type     string     `json:"type"`
	Bounds   InkBounds  `json:"bounds"`
	PageID   string     `json:"pageId,omitempty"`
	Locked   bool       `json:"locked,omitempty"`
	GroupIDs []string   `json:"groupIds,omitempty"`
}

// SmartLayoutLayoutDecision 是服务端对整页布局风格的判定结果（方案二：只判风格与结构，不给坐标）。
type SmartLayoutLayoutDecision struct {
	Style      string         `json:"style"` // ppt | mindmap | article | in_place
	Confidence float64        `json:"confidence"`
	Structure  map[string]any `json:"structure,omitempty"`
}

type SmartLayoutPage struct {
	ID       string           `json:"id"`
	Index    int              `json:"index"`
	Bounds   InkBounds        `json:"bounds"`
	Template string           `json:"template"`
	Anchors  []map[string]any `json:"anchors"`
}

type SmartLayoutElement struct {
	ID     string     `json:"id"`
	Type   string     `json:"type"`
	Bounds InkBounds  `json:"bounds"`
	Text   string     `json:"text,omitempty"`
	Points []InkPoint `json:"points,omitempty"`
}

type SmartLayoutInkBlock struct {
	ID           string      `json:"id"`
	PageID       string      `json:"pageId,omitempty"`
	Bounds       InkBounds   `json:"bounds"`
	StrokeBounds []InkBounds `json:"strokeBounds,omitempty"`
	StartedAt    int64       `json:"startedAt,omitempty"`
	ImageMime    string      `json:"imageMime"`
	ImageBase64  string      `json:"imageBase64"`
}

type SmartLayoutRecognizedBlock struct {
	ID           string      `json:"id"`
	PageID       string      `json:"pageId,omitempty"`
	Type         string      `json:"type"`
	Text         string      `json:"text,omitempty"`
	LaTeX        string      `json:"latex,omitempty"`
	Bounds       InkBounds   `json:"bounds"`
	StrokeBounds []InkBounds `json:"strokeBounds,omitempty"`
	StartedAt    int64       `json:"startedAt,omitempty"`
	Error        string      `json:"error,omitempty"`
}

type SmartLayoutPageDecision struct {
	PageID     string     `json:"pageId"`
	Mode       string     `json:"mode"`
	Paragraphs [][]string `json:"paragraphs,omitempty"`
}

type SmartLayoutBlock struct {
	ID          string     `json:"id"`
	Type        string     `json:"type"`
	Text        string     `json:"text"`
	LaTeX       string     `json:"latex,omitempty"`
	PageID      string     `json:"pageId,omitempty"`
	Bounds      *InkBounds `json:"bounds,omitempty"`
	Order       int        `json:"order"`
	WritingMode string     `json:"writingMode"`
	SourceIDs   []string   `json:"sourceIds,omitempty"`
}

type SmartLayoutDocument struct {
	Version     int                `json:"version"`
	GeneratedAt int64              `json:"generatedAt"`
	Blocks      []SmartLayoutBlock `json:"blocks"`
}

type SmartLayoutResponse struct {
	Document SmartLayoutDocument          `json:"document"`
	Blocks   []SmartLayoutRecognizedBlock `json:"blocks"`
	Pages    []SmartLayoutPageDecision    `json:"pages"`
	Layout   *SmartLayoutLayoutDecision   `json:"layout,omitempty"`
}
