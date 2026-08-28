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

// VisionLayouter 是视觉优先排版通道：整页截图一次判定风格、内容与粗位置。
type VisionLayouter interface {
	VisionLayout(context.Context, VisionLayoutRequest) (VisionLayoutResponse, error)
}

// visionLayoutPrompt 是 VLM 的核心指令（Set-of-Mark：候选对象由客户端编号标出，
// 模型只引用编号、不做坐标回归，见计划 2026-08-27 修订二）。
const visionLayoutPrompt = `你是一个白板笔记智能排版引擎。给定一页白板的整页截图（可能附带笔记标题），请识别页面上的全部手写内容与图示，并给出版式结构。

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

style 判定：
- ppt：图文并茂（存在图片/图示且有说明文字）。
- mindmap：头脑风暴/发散讨论/层级大纲，适合"根主题+分支树"的思维导图。
- article：连续有逻辑的文章段落。
- in_place：内容零散，看不出上述风格。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"style":"ppt|mindmap|article|in_place","confidence":0.0到1.0的小数,"elements":[{"role":"title|caption|body|figure","text":"...","vertical":false,"markIds":["m1"],"pairId":"...","confidence":0.0到1.0的小数}]}

structure（仅 style=mindmap 时输出，其他 style 省略或输出 {}）：
{"root":{"text":"节点文字","blockIds":["e0","e3"],"children":[...]}}
- elements 数组中第 i 项的引用名是 "e"+i（如第 0 项为 "e0"、第 3 项为 "e3"）。
- 节点文字必须是短标题（不超过 100 字）；树最多 4 层、最多 50 个节点。
- 同一个元素只能被一个节点引用；根节点是全页主题，分支依次展开。`

// VisionLayout 调用 VLM 分析整页截图并返回校验后的排版判定。
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
// title 唯一、元素数上限；mindmap 结构树引用校验。
func sanitizeVisionLayoutResponse(response *VisionLayoutResponse, pageID string, marks []string) {
	response.PageID = pageID
	validMarks := make(map[string]bool, len(marks))
	for _, mark := range marks {
		if id := strings.TrimSpace(mark); id != "" {
			validMarks[id] = true
		}
	}
	switch strings.ToLower(strings.TrimSpace(response.Style)) {
	case layoutStylePPT:
		response.Style = layoutStylePPT
	case layoutStyleMindmap:
		response.Style = layoutStyleMindmap
	case layoutStyleArticle:
		response.Style = layoutStyleArticle
	default:
		response.Style = layoutStyleInPlace
	}
	if response.Confidence < 0 {
		response.Confidence = 0
	} else if response.Confidence > 1 {
		response.Confidence = 1
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
	// 按输出顺序分配引用 id（"e0"...），供 mindmap 树与客户端使用。
	for i := range response.Elements {
		response.Elements[i].ID = fmt.Sprintf("e%d", i)
	}
	if response.Style != layoutStyleMindmap || len(response.Elements) == 0 {
		response.Structure = nil
		return
	}
	structure := sanitizeVisionMindmapStructure(response.Structure, response.Elements)
	if structure == nil {
		// 树不可用（缺 root/超层数/悬空引用）→ 与经典管线一致回落 in_place。
		log.Printf("[smart-layout] vision mindmap structure invalid, fallback in_place")
		response.Style = layoutStyleInPlace
		response.Structure = nil
		return
	}
	response.Structure = structure
}

// sanitizeVisionMindmapStructure 校验 mindmap 树：深 ≤4、节点 ≤50、节点文字 ≤100 字、
// blockIds 引用必须存在且全局唯一；无 text 且无有效引用的子树剔除，root 无效返回 nil。
func sanitizeVisionMindmapStructure(structure map[string]any, elements []VisionLayoutElement) map[string]any {
	if structure == nil {
		return nil
	}
	root, ok := structure["root"].(map[string]any)
	if !ok {
		return nil
	}
	validRefs := make(map[string]bool, len(elements))
	for _, element := range elements {
		validRefs[element.ID] = true
	}
	usedRefs := map[string]bool{}
	node, count := sanitizeVisionMindmapNode(root, validRefs, usedRefs, 1)
	if node == nil || count == 0 {
		return nil
	}
	return map[string]any{"root": node}
}

func sanitizeVisionMindmapNode(
	node map[string]any,
	validRefs map[string]bool,
	usedRefs map[string]bool,
	depth int,
) (map[string]any, int) {
	text := strings.TrimSpace(nodeText(node["text"]))
	if len([]rune(text)) > maxMindmapNodeText {
		text = string([]rune(text)[:maxMindmapNodeText])
	}
	refs := make([]string, 0, maxMindmapBlockRefs)
	if rawIDs, ok := node["blockIds"].([]any); ok {
		for _, rawID := range rawIDs {
			id, ok := rawID.(string)
			if !ok || !validRefs[id] || usedRefs[id] {
				continue
			}
			usedRefs[id] = true
			refs = append(refs, id)
			if len(refs) >= maxMindmapBlockRefs {
				break
			}
		}
	}
	if text == "" && len(refs) == 0 {
		return nil, 0
	}
	out := map[string]any{"text": text}
	if len(refs) > 0 {
		out["blockIds"] = refs
	}
	count := 1
	if depth < maxMindmapDepth {
		rawChildren, _ := node["children"].([]any)
		children := make([]map[string]any, 0, len(rawChildren))
		for _, rawChild := range rawChildren {
			child, ok := rawChild.(map[string]any)
			if !ok {
				continue
			}
			normalized, nextCount := sanitizeVisionMindmapNode(child, validRefs, usedRefs, depth+1)
			if normalized == nil {
				continue
			}
			count += nextCount
			children = append(children, normalized)
			if count >= maxMindmapNodes {
				break
			}
		}
		if len(children) > 0 {
			out["children"] = children
		}
	}
	if count >= maxMindmapNodes {
		return out, count
	}
	return out, count
}

// nodeText 容错读取 JSON 文本字段（VLM 可能输出非字符串）。
func nodeText(value any) string {
	s, _ := value.(string)
	return s
}
