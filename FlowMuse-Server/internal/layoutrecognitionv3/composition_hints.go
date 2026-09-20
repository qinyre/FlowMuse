package layoutrecognitionv3

import (
	"strings"
	"unicode/utf8"
)

// CompositionHints 只引用本轮 unit，不拥有正文、坐标或源账本。
type CompositionHints struct {
	Version        string           `json:"version"`
	PageIntent     string           `json:"pageIntent"`
	Sections       []SectionHint    `json:"sections"`
	MediaGroups    []MediaGroupHint `json:"mediaGroups"`
	SoftLineBreaks []SoftBreakHint  `json:"softLineBreaks"`
}

type SectionHint struct {
	SectionID     string   `json:"sectionId"`
	HeadingUnitID string   `json:"headingUnitId"`
	MemberUnitIDs []string `json:"memberUnitIds"`
}

type MediaGroupHint struct {
	GroupID       string   `json:"groupId"`
	FigureUnitIDs []string `json:"figureUnitIds"`
	TextUnitIDs   []string `json:"textUnitIds"`
	Confidence    *float64 `json:"confidence"`
}

type SoftBreakHint struct {
	UnitID         string   `json:"unitId"`
	NewlineIndexes []int    `json:"newlineIndexes"`
	Confidence     *float64 `json:"confidence"`
}

// 即便值为空串/null，结构输出也不得携带正文；只在新协商模式启用。
func containsStructureText(value any) bool {
	switch node := value.(type) {
	case map[string]any:
		for key, child := range node {
			if key == "text" || containsStructureText(child) {
				return true
			}
		}
	case []any:
		for _, child := range node {
			if containsStructureText(child) {
				return true
			}
		}
	}
	return false
}

func validateCompositionHints(req *RecognitionRequest, result *ModelStructureResult) *WireError {
	fail := func() *WireError {
		return wireErr(CodeInvalidProviderResp, "composition 提示的字段、角色、成员或连续性无效")
	}
	h := result.CompositionHints
	if h == nil || h.Version != "composition-hints/1" ||
		h.Sections == nil || h.MediaGroups == nil || h.SoftLineBreaks == nil ||
		result.ReadingOrder == nil || result.Roles == nil || result.ListGroups == nil || result.Captions == nil || result.Warnings == nil {
		return fail()
	}
	if h.PageIntent != "reading" && h.PageIntent != "comparison" && h.PageIntent != "mixed" && h.PageIntent != "unknown" {
		return fail()
	}
	if len(h.Sections) > len(req.Units) || len(h.MediaGroups) > len(req.Units) || len(h.SoftLineBreaks) > len(req.Units) {
		return fail()
	}
	units := map[string]UnitInput{}
	roles := map[string]string{}
	positions := map[string]int{}
	for _, u := range req.Units {
		units[u.UnitID] = u
	}
	for _, r := range result.Roles {
		if r.Text != nil {
			return fail()
		}
		roles[r.UnitID] = r.Role
	}
	for i, id := range result.ReadingOrder {
		positions[id] = i
	}
	validID := func(id string) bool { return strings.TrimSpace(id) != "" && utf8.RuneCountInString(id) <= 64 }
	// 每个列表完整子树是不可拆单元，而不是仅检查各级成员。
	subtrees := []map[string]bool{}
	for _, root := range result.ListGroups {
		if root.Text != nil {
			return fail()
		}
		set := map[string]bool{}
		for _, id := range root.Members {
			set[id] = true
		}
		for range result.ListGroups {
			for _, child := range result.ListGroups {
				if child.ParentUnitID != nil && set[*child.ParentUnitID] {
					for _, id := range child.Members {
						set[id] = true
					}
				}
			}
		}
		for id := range set {
			if roles[id] != "listItem" {
				return fail()
			}
		}
		subtrees = append(subtrees, set)
	}
	continuous := func(ids []string) bool {
		if len(ids) == 0 {
			return false
		}
		set, low, high := map[string]bool{}, len(positions), -1
		for _, id := range ids {
			p, ok := positions[id]
			if !ok || set[id] {
				return false
			}
			set[id] = true
			low, high = min(low, p), max(high, p)
		}
		if high-low+1 != len(set) {
			return false
		}
		for _, subtree := range subtrees {
			hits := 0
			for id := range subtree {
				if set[id] {
					hits++
				}
			}
			if hits != 0 && hits != len(subtree) {
				return false
			}
		}
		return true
	}
	sectionOf, sectionIDs := map[string]string{}, map[string]bool{}
	for _, s := range h.Sections {
		if !validID(s.SectionID) || sectionIDs[s.SectionID] || roles[s.HeadingUnitID] != "title" || len(s.MemberUnitIDs) == 0 {
			return fail()
		}
		sectionIDs[s.SectionID] = true
		ids := append([]string{s.HeadingUnitID}, s.MemberUnitIDs...)
		if !continuous(ids) {
			return fail()
		}
		last := positions[s.HeadingUnitID]
		for _, id := range s.MemberUnitIDs {
			if positions[id] <= last || roles[id] == "title" {
				return fail()
			}
			last = positions[id]
		}
		for _, id := range ids {
			if sectionOf[id] != "" {
				return fail()
			}
			sectionOf[id] = s.SectionID
		}
	}
	captionOf := map[string]string{}
	for _, c := range result.Captions {
		target, ok := units[c.TargetUnitID]
		if c.Text != nil || roles[c.CaptionUnitID] != "caption" || !ok ||
			(target.Kind != "figure" && target.Kind != "preserved") || captionOf[c.CaptionUnitID] != "" ||
			sectionOf[c.CaptionUnitID] != sectionOf[c.TargetUnitID] {
			return fail()
		}
		captionOf[c.CaptionUnitID] = c.TargetUnitID
	}
	for id, role := range roles {
		if role == "caption" && captionOf[id] == "" {
			return fail()
		}
	}
	owner, groupIDs := map[string]string{}, map[string]bool{}
	for _, g := range h.MediaGroups {
		if req.OverviewPngBase64 == "" || !validID(g.GroupID) || groupIDs[g.GroupID] || len(g.FigureUnitIDs) == 0 || len(g.TextUnitIDs) == 0 ||
			g.Confidence == nil || !(*g.Confidence >= 0 && *g.Confidence <= 1) {
			return fail()
		}
		groupIDs[g.GroupID] = true
		ids := append(append([]string{}, g.FigureUnitIDs...), g.TextUnitIDs...)
		figures := map[string]bool{}
		for _, id := range g.FigureUnitIDs {
			if units[id].Kind != "figure" {
				return fail()
			}
			figures[id] = true
		}
		for _, id := range g.TextUnitIDs {
			if roles[id] != "body" && roles[id] != "listItem" {
				return fail()
			}
		}
		for caption, target := range captionOf {
			if figures[target] {
				ids = append(ids, caption)
			}
		}
		if !continuous(ids) {
			return fail()
		}
		for _, id := range ids {
			if owner[id] != "" || sectionOf[id] != sectionOf[ids[0]] {
				return fail()
			}
			owner[id] = g.GroupID
		}
	}
	// 没有正文 mediaGroup 的单图+图注组件也必须连续。
	for _, c := range result.Captions {
		if owner[c.TargetUnitID] != "" {
			continue
		}
		ids := []string{c.TargetUnitID}
		for caption, target := range captionOf {
			if target == c.TargetUnitID {
				ids = append(ids, caption)
			}
		}
		if !continuous(ids) {
			return fail()
		}
	}
	seenBreaks := map[string]bool{}
	for _, b := range h.SoftLineBreaks {
		u, ok := units[b.UnitID]
		role := roles[b.UnitID]
		if !ok || u.Kind != "ink" || u.Text == nil || (role != "title" && role != "body" && role != "caption") ||
			seenBreaks[b.UnitID] || len(b.NewlineIndexes) == 0 || b.Confidence == nil || !(*b.Confidence >= 0 && *b.Confidence <= 1) {
			return fail()
		}
		seenBreaks[b.UnitID] = true
		lines := strings.Split(*u.Text, "\n")
		last := -1
		for _, index := range b.NewlineIndexes {
			if index <= last || index+1 >= len(lines) || strings.TrimSpace(lines[index]) == "" || strings.TrimSpace(lines[index+1]) == "" {
				return fail()
			}
			last = index
		}
	}
	return nil
}

const compositionHintPrompt = `
本次启用整页内容组织，在同一 JSON 增加 compositionHints，禁止返回 figureTextLinks：
"compositionHints":{"version":"composition-hints/1","pageIntent":"reading|comparison|mixed|unknown","sections":[{"sectionId":"s1","headingUnitId":"标题ID","memberUnitIds":["有序成员ID"]}],"mediaGroups":[{"groupId":"m1","figureUnitIds":["图片ID"],"textUnitIds":["正文ID"],"confidence":0.95}],"softLineBreaks":[{"unitId":"OCR单元ID","newlineIndexes":[0],"confidence":0.95}]}
- 所有数组必须存在，无证据用 []，不用 null；只返回引用/编号/置信度，不得夹带正文或坐标。
- pageIntent 表示阅读、同级比较或混合。sections 仅一层章节，heading 必须 title，成员不含自己的 heading，章节连续且不交叉；页总标题可在章节之外。
- 根据概览中图片的实际对象及全文语义判断图文对应，不按最近距离硬配。mediaGroup 至少一图和一段 body/listItem；可以多图共用一段说明，该文字只出现一次；一单元最多属于一组。不确定不配。
- 短图注保留 caption 角色及 captions 关系，不列入 mediaGroups.textUnitIds；长解释仍为 body/listItem。每个 caption 必须挂靠 figure/preserved。组的图片、正文及其图注在 readingOrder 中连续，不夹无关单元，不跨章节、不拆完整列表子树；不要重写正文来满足约束。
- softLineBreaks 只标记 ink 中因手写行宽产生的物理换行（从第一个 \n 编号 0 开始，递增且不重复）。明确为普通正文、标题或短图注，且合并后语义仍为同一句时才给高置信。原生 typed、空行分段、列表、代码、公式、诗歌、未知内容不得合并；不改拼写/标点/连字符，不返回改写文本。
- 不确定的换行或关联留空。原 readingOrder/roles/listGroups/captions/warnings 仍必须完整返回。`
