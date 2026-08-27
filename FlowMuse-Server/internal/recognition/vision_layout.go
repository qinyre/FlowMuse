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

// visionLayoutPrompt 是 VLM 的核心指令（0-1000 归一化坐标惯例见计划 2026-08-26）。
const visionLayoutPrompt = `你是一个白板笔记智能排版引擎。给定一页白板的整页截图（可能附带笔记标题），请识别页面上的全部手写内容与图示，并给出版式结构。

工作方式：
1. 先逐区域扫描（上→中→下，左→右），把每一块连续的文字/图形都找出来，再统一输出。
2. 忠实转写认出的文字；看不清的字不要编造，尽力写下你最有把握的读法。
3. 禁止发明页面上不存在的内容。

坐标系：0-1000 归一化，左上角为原点。box=[x1,y1,x2,y2]，是该内容在截图中的外接框。

角色定义：
- title：页面大标题（字号最大或位于顶部），最多 1 个。
- caption：紧邻某个图示、说明该图的短文字。
- body：正文/段落/列表等其他文字。
- figure：图片、插图、几何图形、图表等非文字内容（text 留空）。

其他标注：
- vertical：竖排文字（从上往下书写）置 true。
- pairId：figure 与它的 caption 用相同的 pairId（如 "pair-1"）配对。
- confidence：你对这项认字把握的自评分（0 到 1 小数）；看不清、连笔潦草时如实给低分。

style 判定：
- ppt：图文并茂（存在图片/图示且有说明文字）。
- mindmap：头脑风暴/发散讨论/层级大纲，适合"根主题+分支树"的思维导图。
- article：连续有逻辑的文章段落。
- in_place：内容零散，看不出上述风格。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"style":"ppt|mindmap|article|in_place","confidence":0.0到1.0的小数,"elements":[{"role":"title|caption|body|figure","text":"...","vertical":false,"box":[x1,y1,x2,y2],"pairId":"...","confidence":0.0到1.0的小数}]}

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
	sanitizeVisionLayoutResponse(&response, request.PageID)
	return response, nil
}

// sanitizeVisionLayoutResponse 校验并规范化 VLM 输出：角色白名单、坐标钳制 [0,1000]、
// 文字角色必须有文字（幻觉过滤）、title 唯一、元素数上限；mindmap 结构树引用校验。
func sanitizeVisionLayoutResponse(response *VisionLayoutResponse, pageID string) {
	response.PageID = pageID
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
		box, ok := normalizeVisionBox(element.Box)
		if !ok {
			continue
		}
		element.Box = box
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

// normalizeVisionBox 钳制每个坐标到 [0,1000] 并保证 x2>x1、y2>y1；退化框返回 false。
func normalizeVisionBox(raw []float64) ([]float64, bool) {
	if len(raw) != 4 {
		return nil, false
	}
	clamped := make([]float64, 4)
	for i, value := range raw {
		if value < 0 {
			value = 0
		} else if value > 1000 {
			value = 1000
		}
		clamped[i] = value
	}
	if clamped[2]-clamped[0] < 1 || clamped[3]-clamped[1] < 1 {
		return nil, false
	}
	return clamped, true
}
