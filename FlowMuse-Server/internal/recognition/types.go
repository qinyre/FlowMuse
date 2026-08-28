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

// VisionLayoutRequest 是视觉优先管线的请求：整页截图（含编号标记，Set-of-Mark）
// 与可选笔记标题，VLM 一次调用完成认字、结构理解、图文配对与风格判定。
type VisionLayoutRequest struct {
	PageID      string   `json:"pageId"`
	NoteTitle   string   `json:"noteTitle,omitempty"`
	ImageMime   string   `json:"imageMime,omitempty"`
	ImageBase64 string   `json:"imageBase64"`
	Marks       []string `json:"marks,omitempty"` // 截图上已画出的编号标记（m1、m2...），输出引用必须出自这里
}

// VisionLayoutElement 是 VLM 对页面内一项内容的描述。
// MarkIds 引用截图上的编号标记（客户端已确定性映射回场景对象），不做坐标回归。
// ID 由服务端按输出顺序分配（"e0"、"e1"...），供 mindmap 结构树引用。
type VisionLayoutElement struct {
	ID         string   `json:"id,omitempty"`
	Role       string   `json:"role"` // title | caption | body | figure
	Text       string   `json:"text,omitempty"`
	Vertical   bool     `json:"vertical,omitempty"`
	MarkIds    []string `json:"markIds,omitempty"`
	PairID     string   `json:"pairId,omitempty"`
	Confidence float64  `json:"confidence,omitempty"`
}

// VisionLayoutResponse 是视觉识别结果：只含认字与图文配对，不再判定版式；
// 版式由客户端模板卡片选择后确定性落位。客户端按 markIds 直查场景对象。
type VisionLayoutResponse struct {
	PageID   string                `json:"pageId,omitempty"`
	Elements []VisionLayoutElement `json:"elements"`
}

// TranscribeRequest 是低置信裁剪重问的请求：一块从整页截图裁出的局部图像，
// 无上下文单独转写。Hint 只允许笔记标题等中性提示，禁止传入原识别结果以免锚定。
type TranscribeRequest struct {
	Hint        string `json:"hint,omitempty"`
	ImageMime   string `json:"imageMime,omitempty"`
	ImageBase64 string `json:"imageBase64"`
}

// TranscribeResponse 是单块转写结果；text 为空表示无法辨认（confidence 恒为 0）。
type TranscribeResponse struct {
	Text       string  `json:"text"`
	Confidence float64 `json:"confidence"`
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
