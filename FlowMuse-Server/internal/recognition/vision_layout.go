package recognition

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"
)

const (
	maxVisionElements  = 50
	maxVisionTextRunes = 500
)

// VisionLayouter 是视觉优先识别通道：整页截图一次认字与图文配对，
// 外加低置信块的裁剪重问转写（v2 模板卡片制：AI 不判版式，见计划 2026-08-28）。
type VisionLayouter interface {
	VisionLayout(context.Context, VisionLayoutRequest) (VisionLayoutResponse, error)
	Transcribe(context.Context, TranscribeRequest) (TranscribeResponse, error)
}

// visionLayoutPrompt 是 VLM 的核心指令（Set-of-Mark：候选对象由客户端编号标出，
// 模型只引用编号、不做坐标回归）。v2 起不再输出 style/structure，
// 版式决策完全交给客户端模板。
const visionLayoutPrompt = `你是一个白板笔记智能排版引擎。给定一页白板的整页截图（可能附带笔记标题），请识别页面上的全部手写内容与图示。

截图上的候选对象（手写笔迹簇、图片、图形等）已用彩色外框标出，每个外框左上角有一个
编号标签（m1、m2、……）。你引用内容时只能使用这些编号，禁止编造截图上不存在的编号。

工作方式：
1. 先逐区域扫描（上→中→下，左→右），读懂每个编号对象的内容与角色，再统一输出。
2. 忠实转写认出的文字；看不清的字不要编造，尽力写下你最有把握的读法。
3. 禁止发明页面上不存在的内容。
4. 转写只能依据笔迹形状本身：禁止参考照片/插图内容来猜测文字（不要把图中人物、
   场景、品牌猜成人名或词句）；没有把握的字符宁可在 confidence 里如实给低分，
   也不要顺着画面联想。

角色定义：
- title：页面大标题（字号最大或位于顶部），最多 1 个。
- caption：紧邻某个图示、说明该图的短文字。
- body：正文/段落/列表等其他文字。
- figure：图片、插图、几何图形、图表等非文字内容（text 留空）。

其他标注：
- markIds：该项内容对应的编号列表。一句连续手写被外框拆成多个编号时，把这几个编号
  都放进 markIds；其余情况通常只有一个编号。每个编号全局只能被一个项引用。
- vertical：竖排文字（从上往下书写）置 true。
- pairId：figure 与它的 caption 用相同的 pairId（如 "pair-1"）配对。
- confidence：你对这项认字把握的自评分（0 到 1 小数）；看不清、连笔潦草时如实给低分。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"elements":[{"role":"title|caption|body|figure","text":"...","vertical":false,"markIds":["m1"],"pairId":"...","confidence":0.0到1.0的小数}]}`

// transcribePrompt 是低置信裁剪重问的指令：无上下文单块转写，靠上下文隔离降幻觉
// （KIE-HVQA, NeurIPS 2025）。
const transcribePrompt = `你是手写文字转写引擎。给定一块从白板截图上裁出的局部图像，里面是一段待转写的手写内容。

- 只转写图像中真实写出的文字，逐字忠实；禁止联想、补全，禁止根据常识推测"这里应该是什么词"。
- 看不清、连笔潦草的字，给出你最有把握的读法，并在 confidence 里如实给低分。
- 整块都无法辨认时 text 留空、confidence 给接近 0 的小数。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"text":"...","confidence":0.0到1.0的小数}`

// VisionLayout 调用 VLM 分析整页截图并返回校验后的认字与图文配对结果（不判版式）。
func (l *OpenAICompatibleSmartLayouter) VisionLayout(
	ctx context.Context, request VisionLayoutRequest,
) (VisionLayoutResponse, error) {
	if strings.TrimSpace(l.config.BaseURL) == "" ||
		strings.TrimSpace(l.config.APIKey) == "" ||
		strings.TrimSpace(l.config.Model) == "" {
		return VisionLayoutResponse{}, errors.New("AI smart layout is not configured")
	}
	mime := strings.TrimSpace(request.ImageMime)
	if mime == "" {
		mime = "image/png"
	}
	intro := visionLayoutPrompt
	if title := strings.TrimSpace(request.NoteTitle); title != "" {
		intro += "\n\n笔记标题：" + title
	}
	content := []map[string]any{
		{"type": "text", "text": intro},
		{
			"type": "image_url",
			"image_url": map[string]any{
				"url": "data:" + mime + ";base64," + request.ImageBase64,
			},
		},
	}
	body, err := l.chatBody(content, 0)
	if err != nil {
		return VisionLayoutResponse{}, err
	}
	responseBody, err := l.postChat(ctx, body)
	if err != nil {
		return VisionLayoutResponse{}, err
	}
	rawContent, err := openAIMessageContent(responseBody)
	if err != nil {
		return VisionLayoutResponse{}, err
	}
	var response VisionLayoutResponse
	if err := json.Unmarshal([]byte(smartLayoutJSONContent(rawContent)), &response); err != nil {
		log.Printf("[smart-layout] vision parse failed: %v", err)
		return VisionLayoutResponse{}, err
	}
	sanitizeVisionLayoutResponse(&response, request.PageID, request.Marks)
	return response, nil
}

// sanitizeVisionLayoutResponse 校验并规范化 VLM 输出：角色白名单、markIds 引用校验
// （必须出自请求标记且全局不重复，剔空丢元素）、文字角色必须有文字（幻觉过滤）、
// title 唯一、文本限长、元素数上限。
func sanitizeVisionLayoutResponse(response *VisionLayoutResponse, pageID string, marks []string) {
	response.PageID = pageID
	validMarks := make(map[string]bool, len(marks))
	for _, mark := range marks {
		if id := strings.TrimSpace(mark); id != "" {
			validMarks[id] = true
		}
	}
	normalized := make([]VisionLayoutElement, 0, len(response.Elements))
	hasTitle := false
	usedMarks := make(map[string]bool, len(validMarks))
	for _, element := range response.Elements {
		element.Role = strings.ToLower(strings.TrimSpace(element.Role))
		switch element.Role {
		case "title":
			if hasTitle {
				// title 最多一个，后续降级为 body。
				element.Role = "body"
			}
			hasTitle = true
		case "caption", "body", "figure":
		default:
			element.Role = "body"
		}
		element.Text = strings.TrimSpace(element.Text)
		if element.Text != "" && len([]rune(element.Text)) > maxVisionTextRunes {
			element.Text = string([]rune(element.Text)[:maxVisionTextRunes])
		}
		if element.Text == "" && element.Role != "figure" {
			// 幻觉过滤：文字角色没有可转写的文字则丢弃。
			continue
		}
		markIds := make([]string, 0, len(element.MarkIds))
		for _, rawID := range element.MarkIds {
			id := strings.TrimSpace(rawID)
			if !validMarks[id] || usedMarks[id] {
				// 编造的、请求里没有的、或已被前项引用的编号一律剔除。
				continue
			}
			usedMarks[id] = true
			markIds = append(markIds, id)
		}
		if len(markIds) == 0 {
			// 无有效编号引用 = 无法绑定到场景对象，丢弃。
			continue
		}
		element.MarkIds = markIds
		if element.Confidence <= 0 {
			// 未自报把握时按宽松默认处理，避免老提示词输出被整体判为低置信。
			element.Confidence = 0.9
		} else if element.Confidence > 1 {
			element.Confidence = 1
		}
		normalized = append(normalized, element)
		if len(normalized) >= maxVisionElements {
			break
		}
	}
	response.Elements = normalized
	// 按输出顺序分配引用 id（"e0"...），供客户端校对与日志定位使用。
	for i := range response.Elements {
		response.Elements[i].ID = fmt.Sprintf("e%d", i)
	}
}

// Transcribe 对一块无上下文的局部截图做单块转写（低置信裁剪重问通道）。
func (l *OpenAICompatibleSmartLayouter) Transcribe(
	ctx context.Context, request TranscribeRequest,
) (TranscribeResponse, error) {
	if strings.TrimSpace(l.config.BaseURL) == "" ||
		strings.TrimSpace(l.config.APIKey) == "" ||
		strings.TrimSpace(l.config.Model) == "" {
		return TranscribeResponse{}, errors.New("AI smart layout is not configured")
	}
	mime := strings.TrimSpace(request.ImageMime)
	if mime == "" {
		mime = "image/png"
	}
	intro := transcribePrompt
	if hint := strings.TrimSpace(request.Hint); hint != "" {
		intro += "\n\n提示：" + hint
	}
	content := []map[string]any{
		{"type": "text", "text": intro},
		{
			"type": "image_url",
			"image_url": map[string]any{
				"url": "data:" + mime + ";base64," + request.ImageBase64,
			},
		},
	}
	body, err := l.chatBody(content, 0)
	if err != nil {
		return TranscribeResponse{}, err
	}
	responseBody, err := l.postChat(ctx, body)
	if err != nil {
		return TranscribeResponse{}, err
	}
	rawContent, err := openAIMessageContent(responseBody)
	if err != nil {
		return TranscribeResponse{}, err
	}
	var response TranscribeResponse
	if err := json.Unmarshal([]byte(smartLayoutJSONContent(rawContent)), &response); err != nil {
		log.Printf("[smart-layout] transcribe parse failed: %v", err)
		return TranscribeResponse{}, err
	}
	sanitizeTranscribeResponse(&response)
	return response, nil
}

// sanitizeTranscribeResponse 规范化单块转写：文本限长、把握钳制到 [0,1]；
// 空文本视为未认出、把握清零，客户端择优时自然保留原结果；未自报把握时按宽松
// 默认处理（与整页识别的元素默认一致）。
func sanitizeTranscribeResponse(response *TranscribeResponse) {
	response.Text = strings.TrimSpace(response.Text)
	if response.Text != "" && len([]rune(response.Text)) > maxVisionTextRunes {
		response.Text = string([]rune(response.Text)[:maxVisionTextRunes])
	}
	if response.Text == "" {
		response.Confidence = 0
		return
	}
	if response.Confidence <= 0 {
		response.Confidence = 0.9
	} else if response.Confidence > 1 {
		response.Confidence = 1
	}
}
