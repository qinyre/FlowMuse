// prompts.go：三阶段提示词构建（纯函数，单测锚定输出；spec §4 口径）。
package layoutrecognitionv3

import (
	"fmt"
	"strings"
)

// BuildReadPrompt 构建 stage=read 提示词。regions 顺序即图像顺序；
// contexts 携带邻区已定稿正文（邻区上下文唯一的传递通道之一）。
func BuildReadPrompt(regions []RegionImageInput) string {
	var b strings.Builder
	b.WriteString(readPromptIntro)
	b.WriteString("\n\n本次共 ")
	b.WriteString(fmt.Sprint(len(regions)))
	b.WriteString(" 个区域，按给出图像顺序依次对应：\n")
	for i, region := range regions {
		fmt.Fprintf(&b, "%d. regionId=%s", i+1, region.RegionID)
		if region.ContextBefore != nil && *region.ContextBefore != "" {
			fmt.Fprintf(&b, "，上文（相邻区域末行）：%s", *region.ContextBefore)
		}
		if region.ContextAfter != nil && *region.ContextAfter != "" {
			fmt.Fprintf(&b, "，下文（相邻区域首行）：%s", *region.ContextAfter)
		}
		b.WriteString("\n")
	}
	b.WriteString(readPromptOutput)
	return b.String()
}

const readPromptIntro = `你是白板手写忠实转写器。下面按顺序给出若干张区域截图，每张图只包含目标区域自身的笔迹（相邻区域内容不在图内）。

转写规则：
- 只输出图中可见文字；图中没有的内容一个字都不许出现。
- 保留原换行（用 \n 表示）与原有标点；不改写、不纠错、不补全、不润色。
- 编号（如 1. 2. 3.）原样转写，不重排、不补缺。
- 每个区域独立判断，不跨区域拼接语义。
- 无法辨认的区域输出 status:"unreadable"；确定不是文字（纯图形/涂鸦）输出 status:"nonText"。`

const readPromptOutput = `
输出规则（严格 JSON 数组，禁止任何额外文字或 Markdown 代码围栏）：
[{"regionId":"...","status":"recognized|uncertain|unreadable|nonText","text":"转写正文（仅 recognized/uncertain 非空）","confidence":0.0到1.0的小数,"diagnostics":["最多4条、每条不超过32字的备注"]}]`

// BuildVerifyPrompt 构建 stage=verify 提示词：附原图、初读结果与原因，
// 重新独立读图——图中不可见的内容即使原结果合理也不得保留。
func BuildVerifyPrompt(regions []RegionImageInput) string {
	var b strings.Builder
	b.WriteString(verifyPromptIntro)
	b.WriteString("\n\n本次共 ")
	b.WriteString(fmt.Sprint(len(regions)))
	b.WriteString(" 个待复核区域，按给出图像顺序依次对应：\n")
	for i, region := range regions {
		fmt.Fprintf(&b, "%d. regionId=%s，复核原因：%s", i+1, region.RegionID, region.Reason)
		if region.OriginalText != nil && *region.OriginalText != "" {
			fmt.Fprintf(&b, "，初读结果：%s", *region.OriginalText)
		}
		if region.OriginalConfidence != nil {
			fmt.Fprintf(&b, "，初读置信度：%.2f", *region.OriginalConfidence)
		}
		b.WriteString("\n")
	}
	b.WriteString(readPromptOutput)
	return b.String()
}

const verifyPromptIntro = `你是白板手写复核转写器。下面给出待复核区域的截图与初读结果。重新独立读图后输出你的最终判读。

复核规则：
- 重新独立读图：输出 text/confidence 必须由图中内容得出；图中不可见的内容，即使初读结果看起来合理，也不得保留。
- 只输出图中可见文字；保留原换行与标点；不改写、不纠错、不补全、不润色。
- 编号原样转写。
- 无法辨认输出 status:"unreadable"；确定非文字输出 status:"nonText"。`

// BuildStructurePrompt 构建 stage=structure 提示词：输入只含 unit 元数据
// （id/kind/text/几何摘要/roleHint）+ 可选概览图；模型只输出角色/顺序/
// 分组/层级/图注归属，禁止输出或修改正文。
func BuildStructurePrompt(units []UnitInput, hasOverview bool) string {
	var b strings.Builder
	b.WriteString(structurePromptIntro)
	if hasOverview {
		b.WriteString("\n\n附一张整页概览图（结构阶段理解整体关系用；图中文字仅供定位参照，转写一律以输入 text 为准）。")
	}
	fmt.Fprintf(&b, "\n\n本次共 %d 个单元：\n", len(units))
	for _, unit := range units {
		fmt.Fprintf(&b, "- unitId=%s kind=%s bounds=(left:%.1f,top:%.1f,w:%.1f,h:%.1f)",
			unit.UnitID, unit.Kind, unit.Bounds.Left, unit.Bounds.Top, unit.Bounds.Width, unit.Bounds.Height)
		if unit.IsTextUnit() && unit.Text != nil {
			fmt.Fprintf(&b, " text=%q", oneLine(*unit.Text))
		}
		if unit.LineHintHeight != nil {
			fmt.Fprintf(&b, " lineHintHeight=%.1f", *unit.LineHintHeight)
		}
		if unit.RoleHint != nil {
			fmt.Fprintf(&b, " roleHint=%s", *unit.RoleHint)
		}
		b.WriteString("\n")
	}
	b.WriteString(structurePromptOutput)
	return b.String()
}

const structurePromptIntro = `你是白板文档结构恢复器。输入是若干单元的元数据（编号/类别/正文/几何），请恢复阅读顺序、段落角色、列表分组与层级、图注归属。

判定规则：
- 列表按编号连续性与缩进（bounds 左缘）判断；单项可以作为子列表（parentUnitId 挂靠到上一级列表的某一项）。
- 标题、图注等不确定的角色一律用 "other"，不要猜。
- 图注（caption）挂到它说明的 figure/preserved 单元上。
- 只输出角色、阅读顺序、列表分组与层级（含父子挂靠）、图注归属。`

const structurePromptOutput = `
输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"readingOrder":["全部 unitId 恰好各出现一次，按阅读顺序"],"roles":[{"unitId":"仅文本单元","role":"title|body|caption|listItem|other"}],"listGroups":[{"groupId":"g1","members":["有序"],"level":1,"parentUnitId":"可选，必须属于另一组的成员","listType":"ordered|unordered","startNumber":1}],"captions":[{"captionUnitId":"...","targetUnitId":"允许 figure/preserved"}],"warnings":["最多8条、每条不超过200字"]}`

func oneLine(text string) string {
	replaced := strings.ReplaceAll(text, "\n", "\\n")
	runes := []rune(replaced)
	if len(runes) > 80 {
		return string(runes[:80]) + "…"
	}
	return replaced
}
