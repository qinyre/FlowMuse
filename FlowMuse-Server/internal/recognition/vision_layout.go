package recognition

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
)

const (
	maxVisionElements  = 50
	maxVisionTextRunes = 500

	// VLM 未自报把握时的默认值：视为存疑，客户端会触发裁剪重问复核。
	defaultVisionConfidence = 0.5
	// 编号回显剥离后的把握上限：该内容已被标签污染过，压低交重问复核。
	markEchoConfidenceCap = 0.5
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

截图上的候选对象（手写笔迹簇、图片、图形等）已用彩色外框标出，每个外框左上角外侧悬有
编号标签（m1、m2、……）。你引用内容时只能使用这些编号，禁止编造截图上不存在的编号。
彩色外框与编号标签是系统叠加的定位标注，不是页面内容：任何编号（如 m6）都严禁出现在
text 转写结果里，text 只包含笔迹实际写出的文字。

工作方式：
1. 先逐区域扫描（上→中→下，左→右），读懂每个编号对象的内容与角色，再统一输出。
2. 忠实转写认出的文字：先整体读短语，再逐字核对形近字，防止把整词认错；
   看不清的字不要编造，尽力写下你最有把握的读法。
3. 同一句短语/短句的手写若被外框拆成多个编号（例如"图"和"1"分开两框），
   必须合并为一个项输出，把这些编号都放进 markIds；严禁把同一短语按编号拆成多项。
4. 禁止发明页面上不存在的内容。
5. 转写只能依据笔迹形状本身：禁止参考照片/插图内容来猜测文字（不要把图中人物、
   场景、品牌猜成人名或词句）；没有把握的字符宁可在 confidence 里如实给低分，
   也不要顺着画面联想。

角色定义：
- title：页面大标题（通常位于页面顶部、独立于图示的完整短句），最多 1 个；
  页面顶部有明显标题就标出，不要因为字数少而漏标。
- caption：紧邻某个图示、说明该图的短文字（包括"图1""图2"这类编号短标），
  须与所指图示用 pairId 配对。
- body：正文/段落/列表等其他文字。
- figure：图片、插图、几何图形、图表等非文字内容（text 留空）。

其他标注：
- markIds：该项内容对应的编号列表。一句连续手写被外框拆成多个编号时，把这几个编号
  都放进 markIds（见工作方式 3）；其余情况通常只有一个编号。每个编号全局只能被一个项引用。
- vertical：竖排文字（从上往下书写）置 true；竖排内容按从上到下的顺序逐字转写。
- pairId：figure 与它的 caption 用相同的 pairId（如 "pair-1"）配对。
- confidence：你对这项认字把握的自评分（0 到 1 小数）；看不清、连笔潦草时如实给低分。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"elements":[{"role":"title|caption|body|figure","text":"...","vertical":false,"markIds":["m1"],"pairId":"...","confidence":0.0到1.0的小数}]}`

// transcribePrompt 是低置信裁剪重问的指令：无上下文单块转写，靠上下文隔离降幻觉
// （KIE-HVQA, NeurIPS 2025）。
const transcribePrompt = `你是手写文字转写引擎。给定一块从白板截图上裁出的局部图像，里面是一段待转写的手写内容。

- 只转写图像中真实写出的文字，逐字忠实：不要遗漏已写出的字，也不要只转写半句；
  禁止联想、补全，禁止根据常识推测"这里应该是什么词"。
- 竖排文字按从上到下的顺序逐字转写。
- 先整体读短语再逐字核对，注意形近字误读。
- 图中若出现彩色编号标签、外框等系统标注，一律忽略，严禁转写进结果。
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
// 编号回显剥离（标签被抄进 text 时剥掉，纯回显保留空文本交客户端重问救回）、
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
		markEchoStripped := false
		element.Text, markEchoStripped = stripMarkEcho(element.Text, validMarks)
		if element.Text != "" && len([]rune(element.Text)) > maxVisionTextRunes {
			element.Text = string([]rune(element.Text)[:maxVisionTextRunes])
		}
		if element.Text == "" && !markEchoStripped && element.Role != "figure" {
			// 幻觉过滤：文字角色没有可转写的文字则丢弃。编号回显剥离成空的
			// 除外——保留空文本，客户端按"无文本"走裁剪重问救回。
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
			// 未自报把握视为存疑，客户端会对低把握块做裁剪重问复核。
			element.Confidence = defaultVisionConfidence
		} else if element.Confidence > 1 {
			element.Confidence = 1
		}
		if markEchoStripped {
			// 被标签污染过的内容不可信：纯回显清零把握强制重问，其余压到上限。
			if element.Text == "" {
				element.Confidence = 0
			} else if element.Confidence > markEchoConfidenceCap {
				element.Confidence = markEchoConfidenceCap
			}
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

var (
	// markEchoToken 匹配文本开头的编号 token（m+数字）。
	markEchoToken = regexp.MustCompile(`^m[0-9]+`)
	// pureMarkEcho 匹配整条文本只由编号与分隔符构成的纯回显，如 "m9"、"m9，m10"；
	// 编号不必真实存在（模型可能编造截图上没有的编号）。
	pureMarkEcho = regexp.MustCompile(`^(?:m[0-9]+[\p{Zs}\t,，、;；:：]*)+$`)
)

// markEchoSeparators 是编号回显里编号之间（及之后）的常见分隔符。
const markEchoSeparators = " \t　,，、;；:："

// stripMarkEcho 剥离转写文本里的编号标签回显（SoM 标签被 VLM 抄进 text，
// 如 "m6三月"→"三月"、"m9"→""）。返回剥离后的文本与是否发生剥离：
//   - 整条文本全是编号与分隔符 → 空串（不校验编号存在性）；
//   - 否则从开头逐个剥离真实存在的编号 token 及其后分隔符；
//   - 开头不是本页真实编号时不剥离，避免误伤用户手写的普通文字。
func stripMarkEcho(text string, validMarks map[string]bool) (string, bool) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return trimmed, false
	}
	if pureMarkEcho.MatchString(trimmed) {
		return "", true
	}
	rest := trimmed
	changed := false
	for {
		loc := markEchoToken.FindStringIndex(rest)
		if loc == nil || !validMarks[rest[:loc[1]]] {
			break
		}
		rest = strings.TrimLeft(rest[loc[1]:], markEchoSeparators)
		changed = true
	}
	if !changed {
		return trimmed, false
	}
	return strings.TrimSpace(rest), true
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
// 空文本或纯编号回显（干净裁剪图里本不该有标签，出现即幻觉）视为未认出、
// 把握清零，客户端择优时自然保留原结果；未自报把握时按宽松默认处理
// （与整页识别的元素默认不同：单块干净图聚焦可信，重问结果才有资格覆盖原值）。
func sanitizeTranscribeResponse(response *TranscribeResponse) {
	response.Text = strings.TrimSpace(response.Text)
	if response.Text != "" && len([]rune(response.Text)) > maxVisionTextRunes {
		response.Text = string([]rune(response.Text)[:maxVisionTextRunes])
	}
	if response.Text == "" || pureMarkEcho.MatchString(response.Text) {
		response.Text = ""
		response.Confidence = 0
		return
	}
	if response.Confidence <= 0 {
		response.Confidence = 0.9
	} else if response.Confidence > 1 {
		response.Confidence = 1
	}
}
