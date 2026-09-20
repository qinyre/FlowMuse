// validate.go：§3.6 双端校验清单的入站（请求侧，400 口径）与出站
// sanitize（模型输出侧，502 invalidProviderResponse 口径）。
package layoutrecognitionv3

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	// imageDecodeFits 走 image.DecodeConfig，依赖解码器注册；
	// 不在此显式注册 PNG 解码器时，所有 PNG 都报 unknown format
	// 被误判"超解码上限"（包内测试文件导入 image/png 会在测试二进制
	// 全局注册解码器，令测试全绿而生产全挂，见 cmd 侧回归测试）。
	_ "image/png"
	"math"
	"strings"
	"unicode/utf8"
)

var (
	validStages = map[string]bool{StageRead: true, StageVerify: true, StageStructure: true}
	// 模型侧 status 越枚举按 502；请求侧不含该字段。
	validStatuses       = map[string]bool{"recognized": true, "uncertain": true, "unreadable": true, "nonText": true}
	validUnitKinds      = map[string]bool{"typed": true, "ink": true, "figure": true, "preserved": true}
	validStructureRoles = map[string]bool{"title": true, "body": true, "caption": true, "listItem": true, "other": true}
	validRoleHints      = map[string]bool{"title": true, "body": true, "caption": true, "listItem": true}
	validListTypes      = map[string]bool{"ordered": true, "unordered": true}
	validVerifyReasons  = map[string]bool{"lowConfidence": true, "suspectedMiss": true, "maybeNonText": true, "brokenNumbering": true, "shapeMismatch": true}
)

// ValidateRequest 是入站校验（请求侧 400 口径，客户端发送前自检同一套
// 规则）。limit 参数为已 normalize 的限额。
func ValidateRequest(req *RecognitionRequest, limits Limits) *WireError {
	if req.SchemaVersion != SchemaVersion {
		return wireErr(CodeInvalidSchema, "schemaVersion 必须为 "+SchemaVersion)
	}
	if !validStages[req.Stage] {
		return wireErr(CodeInvalidSchema, "未知 stage 枚举: "+req.Stage)
	}
	if strings.TrimSpace(req.OperationID) == "" || utf8.RuneCountInString(req.OperationID) > 64 {
		return wireErr(CodeInvalidSchema, "operationId 必须非空且 ≤64 字符")
	}
	if strings.TrimSpace(req.RequestID) == "" || utf8.RuneCountInString(req.RequestID) > 128 {
		return wireErr(CodeInvalidSchema, "requestId 必须非空且 ≤128 字符")
	}
	if strings.TrimSpace(req.PageID) == "" || utf8.RuneCountInString(req.PageID) > 128 {
		return wireErr(CodeInvalidSchema, "pageId 必须非空且 ≤128 字符")
	}
	if req.SceneRevision.Epoch < 0 || req.SceneRevision.Revision < 0 {
		return wireErr(CodeInvalidSchema, "sceneRevision.epoch/revision 必须非负")
	}
	fp := req.SceneRevision.Fingerprint
	if fp == "" || utf8.RuneCountInString(fp) > 64 {
		return wireErr(CodeInvalidSchema, "sceneRevision.fingerprint 必须非空且 ≤64 字符")
	}
	if req.ContentFingerprint == "" || utf8.RuneCountInString(req.ContentFingerprint) > 64 {
		return wireErr(CodeInvalidSchema, "contentFingerprint 必须非空且 ≤64 字符")
	}
	if req.Generation < 0 {
		return wireErr(CodeInvalidSchema, "generation 必须非负")
	}

	switch req.Stage {
	case StageRead, StageVerify:
		return validateRegionBatch(req, limits)
	case StageStructure:
		return validateStructureRequest(req, limits)
	}
	return wireErr(CodeInvalidSchema, "未知 stage")
}

func validateRegionBatch(req *RecognitionRequest, limits Limits) *WireError {
	// stage 字段隔离：read/verify 禁止携带结构字段。
	if len(req.Units) > 0 || req.OverviewPngBase64 != "" || req.TextFingerprint != "" || req.IncludeFigureTextLinks {
		return wireErr(CodeInvalidSchema, "read/verify 请求禁止携带结构字段（units/overviewPngBase64/textFingerprint）")
	}
	if len(req.Regions) == 0 {
		return wireErr(CodeInvalidSchema, "regions 必须是非空数组")
	}
	if len(req.Regions) > limits.MaxRegionsPerBatch {
		return wireErr(CodeLimitExceeded, fmt.Sprintf("regions 超过上限 %d", limits.MaxRegionsPerBatch))
	}
	seen := map[string]bool{}
	for i, region := range req.Regions {
		if region.RegionID == "" || utf8.RuneCountInString(region.RegionID) > 64 {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d].regionId 必须非空且 ≤64 字符", i))
		}
		if seen[region.RegionID] {
			return wireErr(CodeDuplicateID, fmt.Sprintf("regionId 重复: %s", region.RegionID))
		}
		seen[region.RegionID] = true
		if region.ImagePngBase64 == "" {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d].imagePngBase64 必须非空", i))
		}
		if int64(len(region.ImagePngBase64)) > limits.MaxImageBase64Bytes {
			return wireErr(CodeLimitExceeded, fmt.Sprintf("regions[%d].imagePngBase64 超过 3MiB", i))
		}
		if !(region.ImageScale > 0) || isInf(region.ImageScale) {
			return wireErr(CodeBadGeometry, fmt.Sprintf("regions[%d].imageScale 必须是有限正数", i))
		}
		for _, pair := range []struct {
			value *string
			field string
		}{{region.ContextBefore, "contextBefore"}, {region.ContextAfter, "contextAfter"}} {
			if pair.value != nil && utf8.RuneCountInString(*pair.value) > 200 {
				return wireErr(CodeTextTooLong, fmt.Sprintf("regions[%d].%s 超过 200 字符", i, pair.field))
			}
		}
		if region.OriginalText != nil && utf8.RuneCountInString(*region.OriginalText) > limits.MaxTextRunes {
			return wireErr(CodeTextTooLong, fmt.Sprintf("regions[%d].originalText 超过 %d 字符", i, limits.MaxTextRunes))
		}
		if region.OriginalConfidence != nil &&
			!(*region.OriginalConfidence >= 0 && *region.OriginalConfidence <= 1) {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d].originalConfidence 必须在 [0,1]", i))
		}
		if req.Stage == StageVerify {
			if !validVerifyReasons[region.Reason] {
				return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d].reason 枚举非法: %s", i, region.Reason))
			}
		} else if region.Reason != "" || region.OriginalText != nil || region.OriginalConfidence != nil {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d] read 请求禁止携带复核字段（original*/reason）", i))
		}
		// 解码尺寸是另一层独立安全上限，放在字段校验之后（对齐 Dart 端
		// 自检顺序；Dart 不做解码校验）。
		if !imageDecodeFits(region.ImagePngBase64, limits) {
			return wireErr(CodeLimitExceeded, fmt.Sprintf("regions[%d] 解码尺寸超上限（≤2MP、长边 ≤2048）", i))
		}
		if !imageHasVisibleInk(region.ImagePngBase64) {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("regions[%d] 图片无任何可见像素（全透明空图，疑似零长度笔画）", i))
		}
	}
	return nil
}

func validateStructureRequest(req *RecognitionRequest, limits Limits) *WireError {
	if req.IncludeFigureTextLinks && req.OverviewPngBase64 == "" {
		return wireErr(CodeInvalidSchema, "图文关联需要概览图")
	}
	if len(req.Regions) > 0 {
		return wireErr(CodeInvalidSchema, "structure 请求禁止携带 regions 字段")
	}
	if len(req.Units) == 0 {
		return wireErr(CodeInvalidSchema, "units 必须是非空数组")
	}
	if len(req.Units) > limits.MaxUnits {
		return wireErr(CodeLimitExceeded, fmt.Sprintf("units 超过上限 %d", limits.MaxUnits))
	}
	seen := map[string]bool{}
	for i, unit := range req.Units {
		if unit.UnitID == "" || utf8.RuneCountInString(unit.UnitID) > 64 {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("units[%d].unitId 必须非空且 ≤64 字符", i))
		}
		if seen[unit.UnitID] {
			return wireErr(CodeDuplicateID, fmt.Sprintf("unitId 重复: %s", unit.UnitID))
		}
		seen[unit.UnitID] = true
		if !validUnitKinds[unit.Kind] {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("units[%d].kind 枚举非法: %s", i, unit.Kind))
		}
		if unit.Text != nil && utf8.RuneCountInString(*unit.Text) > limits.MaxTextRunes {
			return wireErr(CodeTextTooLong, fmt.Sprintf("units[%d].text 超过 %d 字符", i, limits.MaxTextRunes))
		}
		text := ""
		if unit.Text != nil {
			text = *unit.Text
		}
		if unit.IsTextUnit() {
			if text == "" {
				return wireErr(CodeInvalidSchema, fmt.Sprintf("units[%d].text：typed/ink 单元必须非空", i))
			}
		} else if text != "" {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("units[%d].text：figure/preserved 单元必须缺省或空", i))
		}
		b := unit.Bounds
		for _, v := range []float64{b.Left, b.Top, b.Width, b.Height} {
			if isInf(v) {
				return wireErr(CodeBadGeometry, fmt.Sprintf("units[%d].bounds 必须全有限数", i))
			}
		}
		if b.Width < 0 || b.Height < 0 {
			return wireErr(CodeBadGeometry, fmt.Sprintf("units[%d].bounds 宽高不得为负", i))
		}
		if unit.LineHintHeight != nil && !(*unit.LineHintHeight > 0) {
			return wireErr(CodeBadGeometry, fmt.Sprintf("units[%d].lineHintHeight 必须是有限正数", i))
		}
		if unit.RoleHint != nil && !validRoleHints[*unit.RoleHint] {
			return wireErr(CodeInvalidSchema, fmt.Sprintf("units[%d].roleHint 枚举非法: %s", i, *unit.RoleHint))
		}
	}
	if req.OverviewPngBase64 != "" {
		if int64(len(req.OverviewPngBase64)) > limits.MaxImageBase64Bytes {
			return wireErr(CodeLimitExceeded, "overviewPngBase64 超过 3MiB")
		}
		if !imageDecodeFits(req.OverviewPngBase64, limits) {
			return wireErr(CodeLimitExceeded, "overviewPngBase64 解码尺寸超上限")
		}
		if !imageHasVisibleInk(req.OverviewPngBase64) {
			return wireErr(CodeInvalidSchema, "overviewPngBase64 无任何可见像素（全透明空图）")
		}
	}
	if req.TextFingerprint == "" || utf8.RuneCountInString(req.TextFingerprint) > 64 {
		return wireErr(CodeInvalidSchema, "textFingerprint 必须非空且 ≤64 字符")
	}
	return nil
}

func isInf(v float64) bool {
	return math.IsInf(v, 0) || math.IsNaN(v)
}

// imageDecodeFits 用 header 级解码校验解码尺寸上限（≤2MP、长边 ≤2048）。
func imageDecodeFits(base64Image string, limits Limits) bool {
	decoded, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		return false
	}
	config, _, err := image.DecodeConfig(bytes.NewReader(decoded))
	if err != nil {
		return false
	}
	return limits.imageFitsLimits(config)
}

// imageHasVisibleInk 全解码扫描 alpha 通道：全透明空图（2026-09-18 真机
// 事故：零长度笔画渲染的 831×831 空图）会让上游视觉 API 无限挂起直至
// provider 超时，必须在入站拒绝。解码失败与 imageDecodeFits 同口径
// （false → 由调用方的尺寸/空图校验报 400）。
func imageHasVisibleInk(base64Image string) bool {
	decoded, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		return false
	}
	img, _, err := image.Decode(bytes.NewReader(decoded))
	if err != nil {
		return false
	}
	switch im := img.(type) {
	case *image.NRGBA:
		for i := 3; i < len(im.Pix); i += 4 {
			if im.Pix[i] != 0 {
				return true
			}
		}
		return false
	case *image.RGBA:
		for i := 3; i < len(im.Pix); i += 4 {
			if im.Pix[i] != 0 {
				return true
			}
		}
		return false
	}
	b := img.Bounds()
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if _, _, _, a := img.At(x, y).RGBA(); a != 0 {
				return true
			}
		}
	}
	return false
}

// SanitizeRegionResults 校验模型 read/verify 输出（R-02/R-03 + 数组去重）
// 并生成 missingRegionIds（从请求集合与合法结果求差，不依赖模型声明）。
// 全部漏答是合法结果（regions 空 + missing=全集）。
func SanitizeRegionResults(requestedIDs []string, results []ModelRegionResult) ([]RegionResult, []string, *WireError) {
	requested := map[string]bool{}
	for _, id := range requestedIDs {
		requested[id] = true
	}
	seen := map[string]bool{}
	out := make([]RegionResult, 0, len(results))
	for i, result := range results {
		if !requested[result.RegionID] {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("模型输出引用了请求外的 regionId: %s", result.RegionID))
		}
		if seen[result.RegionID] {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("模型输出 regionId 重复: %s", result.RegionID))
		}
		seen[result.RegionID] = true
		if !validStatuses[result.Status] {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("regions[%d].status 枚举非法: %s", i, result.Status))
		}
		text := ""
		if result.Text != nil {
			text = *result.Text
			if utf8.RuneCountInString(text) > 2000 {
				return nil, nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("regions[%d].text 超过 2000 字符", i))
			}
		}
		requiresText := result.Status == "recognized" || result.Status == "uncertain"
		if requiresText && strings.TrimSpace(text) == "" {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("regions[%d]：status=%s 必须携带非空 text", i, result.Status))
		}
		if !requiresText && text != "" {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("regions[%d]：status=%s 必须缺省或空 text", i, result.Status))
		}
		if result.Confidence != nil &&
			!(*result.Confidence >= 0 && *result.Confidence <= 1) {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("regions[%d].confidence 必须在 [0,1]", i))
		}
		if len(result.Diagnostics) > 4 {
			return nil, nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("regions[%d].diagnostics 超过 4 条", i))
		}
		diagnostics := make([]string, 0, len(result.Diagnostics))
		for _, entry := range result.Diagnostics {
			if utf8.RuneCountInString(entry) > 32 {
				return nil, nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("regions[%d].diagnostics 条目超过 32 字符", i))
			}
			diagnostics = append(diagnostics, entry)
		}
		out = append(out, RegionResult{
			RegionID:    result.RegionID,
			Status:      result.Status,
			Text:        text,
			Confidence:  result.Confidence,
			Diagnostics: diagnostics,
		})
	}
	missing := make([]string, 0)
	for _, id := range requestedIDs {
		if !seen[id] {
			missing = append(missing, id)
		}
	}
	return out, missing, nil
}

// SanitizeStructureResult 校验模型 structure 输出（R-02/R-06..R-10 +
// 嵌套列表子树连续性），转换为响应结构。
func SanitizeStructureResult(units []UnitInput, result *ModelStructureResult) (*RecognitionResponse, *WireError) {
	unitIDs := map[string]bool{}
	textUnitIDs := map[string]bool{}
	for _, unit := range units {
		unitIDs[unit.UnitID] = true
		if unit.IsTextUnit() {
			textUnitIDs[unit.UnitID] = true
		}
	}

	// R-10：结构输出携带正文归 502。
	for i, role := range result.Roles {
		if role.Text != nil && *role.Text != "" {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("roles[%d] 携带正文字段", i))
		}
	}
	for i, group := range result.ListGroups {
		if group.Text != nil && *group.Text != "" {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("listGroups[%d] 携带正文字段", i))
		}
	}
	for i, caption := range result.Captions {
		if caption.Text != nil && *caption.Text != "" {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("captions[%d] 携带正文字段", i))
		}
	}

	// R-06：readingOrder 恰覆盖全部 units 各一次。
	if len(result.ReadingOrder) != len(unitIDs) {
		return nil, wireErr(CodeInvalidProviderResp, "readingOrder 必须恰覆盖全部 units 各一次")
	}
	seenOrder := map[string]bool{}
	for _, id := range result.ReadingOrder {
		if !unitIDs[id] || seenOrder[id] {
			return nil, wireErr(CodeInvalidProviderResp, "readingOrder 必须恰覆盖全部 units 各一次")
		}
		seenOrder[id] = true
	}

	// R-02/R-07：roles 恰覆盖文本单元、不含 figure/preserved。
	roles := make([]RoleAssignment, 0, len(result.Roles))
	if len(result.Roles) != len(textUnitIDs) {
		return nil, wireErr(CodeInvalidProviderResp,
			"roles 必须恰覆盖全部文本单元（typed/ink）")
	}
	seenRoles := map[string]bool{}
	for i, role := range result.Roles {
		if !unitIDs[role.UnitID] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("roles[%d] 引用了请求外的 unitId: %s", i, role.UnitID))
		}
		if seenRoles[role.UnitID] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("roles[%d] unitId 重复: %s", i, role.UnitID))
		}
		seenRoles[role.UnitID] = true
		if !textUnitIDs[role.UnitID] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("roles[%d] 不得包含 figure/preserved 单元: %s", i, role.UnitID))
		}
		if !validStructureRoles[role.Role] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("roles[%d].role 枚举非法: %s", i, role.Role))
		}
		roles = append(roles, RoleAssignment{UnitID: role.UnitID, Role: role.Role})
	}

	// R-08：listGroups 自洽（成员/层级/父子/跨组重复）。
	groups := make([]ListGroup, 0, len(result.ListGroups))
	memberOwner := map[string]string{}
	groupByID := map[string]*ModelListGroup{}
	for i := range result.ListGroups {
		group := &result.ListGroups[i]
		if group.GroupID == "" || utf8.RuneCountInString(group.GroupID) > 16 {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("listGroups[%d].groupId 必须非空且 ≤16 字符", i))
		}
		if _, dup := groupByID[group.GroupID]; dup {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("groupId 重复: %s", group.GroupID))
		}
		groupByID[group.GroupID] = group
		if len(group.Members) == 0 {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("listGroups[%d].members 必须非空", i))
		}
		if group.Level < 1 {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("listGroups[%d].level 必须 ≥1", i))
		}
		if !validListTypes[group.ListType] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("listGroups[%d].listType 枚举非法: %s", i, group.ListType))
		}
		seenMembers := map[string]bool{}
		for _, member := range group.Members {
			if member == "" || seenMembers[member] {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("listGroups[%d].members 含重复或空 id", i))
			}
			seenMembers[member] = true
			if !unitIDs[member] {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("listGroups[%d] 成员引用了请求外的 unitId: %s", i, member))
			}
			if owner, dup := memberOwner[member]; dup {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("成员跨组重复: %s（%s 与 %s）", member, owner, group.GroupID))
			}
			memberOwner[member] = group.GroupID
		}
		if group.ParentUnitID == nil {
			if len(group.Members) < 2 {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("顶层组 %s 成员必须 ≥2", group.GroupID))
			}
		} else {
			parentGroup, ok := memberOwner[*group.ParentUnitID]
			if !ok {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("parentUnitId 必须属于另一 listGroup 的成员: %s", *group.ParentUnitID))
			}
			if parentGroup == group.GroupID {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("parentUnitId 不得指向自身组的成员: %s", *group.ParentUnitID))
			}
		}
		groups = append(groups, ListGroup{
			GroupID:      group.GroupID,
			Members:      append([]string(nil), group.Members...),
			Level:        group.Level,
			ParentUnitID: group.ParentUnitID,
			ListType:     group.ListType,
			StartNumber:  group.StartNumber,
		})
	}
	// 成环检测：沿 parent 链走，超过组数即环。
	for _, group := range groupByID {
		cursor := group
		hops := 0
		for cursor.ParentUnitID != nil {
			hops++
			if hops > len(groupByID) {
				return nil, wireErr(CodeInvalidProviderResp,
					fmt.Sprintf("parentUnitId 链成环（涉及 %s）", group.GroupID))
			}
			parentGroupID, ok := memberOwner[*cursor.ParentUnitID]
			if !ok {
				break
			}
			cursor = groupByID[parentGroupID]
		}
	}

	// R-09：captions 悬空或自指。
	captions := make([]Caption, 0, len(result.Captions))
	for i, caption := range result.Captions {
		if !unitIDs[caption.CaptionUnitID] || !unitIDs[caption.TargetUnitID] {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("captions[%d] 引用了请求外的 unitId", i))
		}
		if caption.CaptionUnitID == caption.TargetUnitID {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("captions[%d] 不得自指", i))
		}
		captions = append(captions, Caption{
			CaptionUnitID: caption.CaptionUnitID,
			TargetUnitID:  caption.TargetUnitID,
		})
	}

	links := make([]FigureTextLink, 0, len(result.FigureTextLinks))
	kinds := map[string]string{}
	roleByID := map[string]string{}
	captionIDs := map[string]bool{}
	for _, unit := range units {
		kinds[unit.UnitID] = unit.Kind
	}
	for _, role := range roles {
		roleByID[role.UnitID] = role.Role
	}
	for _, caption := range captions {
		captionIDs[caption.CaptionUnitID] = true
	}
	seenLinks := map[string]bool{}
	for _, link := range result.FigureTextLinks {
		role := roleByID[link.TextUnitID]
		if !textUnitIDs[link.TextUnitID] || kinds[link.FigureUnitID] != "figure" ||
			(role != "body" && role != "listItem") || captionIDs[link.TextUnitID] ||
			seenLinks[link.TextUnitID] || link.Confidence == nil || link.Text != nil ||
			!(*link.Confidence >= 0 && *link.Confidence <= 1) {
			return nil, wireErr(CodeInvalidProviderResp, "图文关系端点、角色、唯一性或置信度无效")
		}
		seenLinks[link.TextUnitID] = true
		links = append(links, link.FigureTextLink)
	}
	if len(result.Warnings) > 8 {
		return nil, wireErr(CodeInvalidProviderResp, "warnings 超过 8 条")
	}
	for _, warning := range result.Warnings {
		if utf8.RuneCountInString(warning) > 200 {
			return nil, wireErr(CodeInvalidProviderResp, "warning 条目超过 200 字符")
		}
	}

	// §3.4 嵌套列表连续性：每个组的完整子树在 readingOrder 中连续。
	indexByUnit := make(map[string]int, len(result.ReadingOrder))
	for i, id := range result.ReadingOrder {
		indexByUnit[id] = i
	}
	childrenOfUnit := map[string][]*ModelListGroup{}
	for _, group := range groupByID {
		if group.ParentUnitID != nil {
			childrenOfUnit[*group.ParentUnitID] = append(childrenOfUnit[*group.ParentUnitID], group)
		}
	}
	var subtree func(group *ModelListGroup) map[string]bool
	subtree = func(group *ModelListGroup) map[string]bool {
		unitsSet := map[string]bool{}
		for _, member := range group.Members {
			unitsSet[member] = true
			for _, child := range childrenOfUnit[member] {
				for id := range subtree(child) {
					unitsSet[id] = true
				}
			}
		}
		return unitsSet
	}
	for _, group := range groupByID {
		indices := make([]int, 0, 4)
		for id := range subtree(group) {
			if idx, ok := indexByUnit[id]; ok {
				indices = append(indices, idx)
			}
		}
		if len(indices) == 0 {
			continue
		}
		min, max := indices[0], indices[0]
		for _, idx := range indices[1:] {
			if idx < min {
				min = idx
			}
			if idx > max {
				max = idx
			}
		}
		if max-min+1 != len(indices) {
			return nil, wireErr(CodeInvalidProviderResp,
				fmt.Sprintf("列表组 %s 的完整子树在 readingOrder 中不连续", group.GroupID))
		}
	}

	response := &RecognitionResponse{
		ReadingOrder:    append([]string(nil), result.ReadingOrder...),
		Roles:           roles,
		ListGroups:      groups,
		Captions:        captions,
		FigureTextLinks: links,
		Warnings:        append([]string(nil), result.Warnings...),
	}
	return response, nil
}
