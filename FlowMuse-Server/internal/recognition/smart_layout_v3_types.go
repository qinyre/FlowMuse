package recognition

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"unicode/utf8"
)

// 智能排版 v3 分析协议类型（schema 冻结见
// docs/研发记录/specs/smart-layout-v3/protocol/protocol.md）。
//
// Dart 侧镜像：FlowMuse-App/lib/features/whiteboard/smart_layout/protocol/。
// 双端消费同一组 fixtures（正例无损 round-trip，负例同类拒绝）。
// typed text 只存在于请求 ExactTexts——服务端不得从图片重建打字文本。

// 错误码（与 Dart SmartLayoutV3ErrorCode 同名 snake_case）。
const (
	V3ErrInvalidRequest     = "invalid_request"
	V3ErrUnknownField       = "unknown_field"
	V3ErrUnknownEnum        = "unknown_enum"
	V3ErrDanglingReference  = "dangling_reference"
	V3ErrDuplicateReference = "duplicate_reference"
	V3ErrReferenceCycle     = "reference_cycle"
	V3ErrLimitExceeded      = "limit_exceeded"
)

// SmartLayoutV3Error 是 v3 协议错误 envelope。
type SmartLayoutV3Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Field   string `json:"field,omitempty"`
}

func (e *SmartLayoutV3Error) Error() string {
	if e.Field == "" {
		return fmt.Sprintf("smart-layout-v3: %s: %s", e.Code, e.Message)
	}
	return fmt.Sprintf("smart-layout-v3: %s: %s (field: %s)", e.Code, e.Message, e.Field)
}

func v3err(code, field, format string, args ...any) *SmartLayoutV3Error {
	return &SmartLayoutV3Error{Code: code, Field: field, Message: fmt.Sprintf(format, args...)}
}

var v3FingerprintPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

// ---- 请求 ----

type SmartLayoutV3SceneRevision struct {
	Epoch       *int   `json:"epoch"`
	Revision    *int   `json:"revision"`
	Fingerprint string `json:"fingerprint"`
}

type SmartLayoutV3AssetRef struct {
	Key         string `json:"key"`
	Kind        string `json:"kind"`
	Fingerprint string `json:"fingerprint"`
}

type SmartLayoutV3Mark struct {
	MarkID   string `json:"markId"`
	Label    string `json:"label"`
	AssetKey string `json:"assetKey"`
	SourceID string `json:"sourceId"`
}

type SmartLayoutV3ExactText struct {
	SourceID string `json:"sourceId"`
	Text     string `json:"text"`
}

type SmartLayoutV3Request struct {
	ProtocolVersion *int                        `json:"protocolVersion"`
	PageID          string                      `json:"pageId"`
	SceneRevision   *SmartLayoutV3SceneRevision `json:"sceneRevision"`
	Assets          []SmartLayoutV3AssetRef     `json:"assets"`
	Marks           []SmartLayoutV3Mark         `json:"marks"`
	ExactTexts      []SmartLayoutV3ExactText    `json:"exactTexts"`
	SourceRefs      []string                    `json:"sourceRefs"`
}

var v3AssetKinds = map[string]bool{"clean": true, "annotated": true, "crop": true}

// ParseSmartLayoutV3Request 严格解析+校验；失败返回 *SmartLayoutV3Error。
func ParseSmartLayoutV3Request(data []byte) (*SmartLayoutV3Request, *SmartLayoutV3Error) {
	var req SmartLayoutV3Request
	if err := decodeStrict(data, &req); err != nil {
		return nil, err
	}
	root, keyErr := rawObjectOf(data)
	if keyErr != nil {
		return nil, keyErr
	}
	if err := requireRequestKeys(root); err != nil {
		return nil, err
	}
	if req.ProtocolVersion == nil || *req.ProtocolVersion != 3 {
		return nil, v3err(V3ErrInvalidRequest, "protocolVersion", "必须为 3")
	}
	if req.PageID == "" {
		return nil, v3err(V3ErrInvalidRequest, "pageId", "必须非空")
	}
	if utf8.RuneCountInString(req.PageID) > 128 {
		return nil, v3err(V3ErrLimitExceeded, "pageId", "超过 128 字符")
	}
	if req.SceneRevision == nil {
		return nil, v3err(V3ErrInvalidRequest, "sceneRevision", "缺少必填字段")
	}
	if req.SceneRevision.Epoch == nil || *req.SceneRevision.Epoch < 0 {
		return nil, v3err(V3ErrInvalidRequest, "sceneRevision.epoch", "必须是非负整数")
	}
	if req.SceneRevision.Revision == nil || *req.SceneRevision.Revision < 0 {
		return nil, v3err(V3ErrInvalidRequest, "sceneRevision.revision", "必须是非负整数")
	}
	if !v3FingerprintPattern.MatchString(req.SceneRevision.Fingerprint) {
		return nil, v3err(V3ErrInvalidRequest, "sceneRevision.fingerprint", "必须是 16 位小写 hex")
	}
	if len(req.Assets) > 64 {
		return nil, v3err(V3ErrLimitExceeded, "assets", "超过上限 64")
	}
	assetKeys := map[string]bool{}
	for i, asset := range req.Assets {
		field := fmt.Sprintf("assets[%d]", i)
		if asset.Key == "" {
			return nil, v3err(V3ErrInvalidRequest, field+".key", "必须非空")
		}
		if assetKeys[asset.Key] {
			return nil, v3err(V3ErrDuplicateReference, field+".key", "key 重复: %s", asset.Key)
		}
		assetKeys[asset.Key] = true
		if !v3AssetKinds[asset.Kind] {
			return nil, v3err(V3ErrUnknownEnum, field+".kind", "未知 asset kind 枚举: %s", asset.Kind)
		}
		if !v3FingerprintPattern.MatchString(asset.Fingerprint) {
			return nil, v3err(V3ErrInvalidRequest, field+".fingerprint", "必须是 16 位小写 hex")
		}
	}
	if len(req.SourceRefs) > 2048 {
		return nil, v3err(V3ErrLimitExceeded, "sourceRefs", "超过上限 2048")
	}
	sourceRefs := map[string]bool{}
	for i, ref := range req.SourceRefs {
		if ref == "" {
			return nil, v3err(V3ErrInvalidRequest, fmt.Sprintf("sourceRefs[%d]", i), "必须是非空字符串")
		}
		if sourceRefs[ref] {
			return nil, v3err(V3ErrDuplicateReference, "sourceRefs", "sourceRef 重复: %s", ref)
		}
		sourceRefs[ref] = true
	}
	if len(req.Marks) > 512 {
		return nil, v3err(V3ErrLimitExceeded, "marks", "超过上限 512")
	}
	markIDs := map[string]bool{}
	for i, mark := range req.Marks {
		field := fmt.Sprintf("marks[%d]", i)
		if mark.MarkID == "" {
			return nil, v3err(V3ErrInvalidRequest, field+".markId", "必须非空")
		}
		if markIDs[mark.MarkID] {
			return nil, v3err(V3ErrDuplicateReference, field+".markId", "markId 重复: %s", mark.MarkID)
		}
		markIDs[mark.MarkID] = true
		if mark.Label == "" {
			return nil, v3err(V3ErrInvalidRequest, field+".label", "必须非空")
		}
		if !assetKeys[mark.AssetKey] {
			return nil, v3err(V3ErrDanglingReference, field+".assetKey", "mark 引用了未声明的 asset: %s", mark.AssetKey)
		}
		if !sourceRefs[mark.SourceID] {
			return nil, v3err(V3ErrDanglingReference, field+".sourceId", "mark 引用了未声明的 sourceRef: %s", mark.SourceID)
		}
	}
	seenExact := map[string]bool{}
	for i, text := range req.ExactTexts {
		field := fmt.Sprintf("exactTexts[%d]", i)
		if text.SourceID == "" {
			return nil, v3err(V3ErrInvalidRequest, field+".sourceId", "必须非空")
		}
		if seenExact[text.SourceID] {
			return nil, v3err(V3ErrDuplicateReference, field+".sourceId", "sourceId 重复: %s", text.SourceID)
		}
		seenExact[text.SourceID] = true
		if utf8.RuneCountInString(text.Text) > 10000 {
			return nil, v3err(V3ErrLimitExceeded, field+".text", "text 超过 10000 字符")
		}
		if !sourceRefs[text.SourceID] {
			return nil, v3err(V3ErrDanglingReference, field+".sourceId", "exactText 引用了未声明的 sourceRef: %s", text.SourceID)
		}
	}
	return &req, nil
}

// ---- 响应（无任何 text 字段：typed text 不从模型往返）----

type SmartLayoutV3Relation struct {
	Type           string `json:"type"`
	TargetRegionID string `json:"targetRegionId"`
}

type SmartLayoutV3Region struct {
	ID           string                  `json:"id"`
	Role         string                  `json:"role"`
	SourceIDs    []string                `json:"sourceIds"`
	ReadingOrder *int                    `json:"readingOrder"`
	Confidence   *float64                `json:"confidence"`
	Relations    []SmartLayoutV3Relation `json:"relations"`
}

type SmartLayoutV3Response struct {
	ProtocolVersion *int                  `json:"protocolVersion"`
	RequestID       *string               `json:"requestId,omitempty"`
	Regions         []SmartLayoutV3Region `json:"regions"`
	Warnings        []string              `json:"warnings"`
}

var v3Roles = map[string]bool{
	"title": true, "body": true, "caption": true, "figure": true,
	"formula": true, "list": true, "table": true, "unknown": true,
}

var v3RelationTypes = map[string]bool{"captionOf": true, "boundTo": true, "sameColumn": true}

// ParseSmartLayoutV3Response 严格解析+校验响应。
func ParseSmartLayoutV3Response(data []byte) (*SmartLayoutV3Response, *SmartLayoutV3Error) {
	var resp SmartLayoutV3Response
	if err := decodeStrict(data, &resp); err != nil {
		return nil, err
	}
	respRoot, keyErr := rawObjectOf(data)
	if keyErr != nil {
		return nil, keyErr
	}
	if err := requireResponseKeys(respRoot); err != nil {
		return nil, err
	}
	if resp.ProtocolVersion == nil || *resp.ProtocolVersion != 3 {
		return nil, v3err(V3ErrInvalidRequest, "protocolVersion", "必须为 3")
	}
	if resp.RequestID != nil {
		if *resp.RequestID == "" {
			return nil, v3err(V3ErrInvalidRequest, "requestId", "必须非空")
		}
		if utf8.RuneCountInString(*resp.RequestID) > 128 {
			return nil, v3err(V3ErrLimitExceeded, "requestId", "超过 128 字符")
		}
	}
	if len(resp.Regions) > 128 {
		return nil, v3err(V3ErrLimitExceeded, "regions", "超过上限 128")
	}
	regionIDs := map[string]bool{}
	for i, region := range resp.Regions {
		field := fmt.Sprintf("regions[%d]", i)
		if region.ID == "" {
			return nil, v3err(V3ErrInvalidRequest, field+".id", "必须非空")
		}
		if regionIDs[region.ID] {
			return nil, v3err(V3ErrDuplicateReference, field+".id", "region id 重复: %s", region.ID)
		}
		regionIDs[region.ID] = true
	}
	for i, region := range resp.Regions {
		field := fmt.Sprintf("regions[%d]", i)
		if !v3Roles[region.Role] {
			return nil, v3err(V3ErrUnknownEnum, field+".role", "未知 role 枚举: %s", region.Role)
		}
		if len(region.SourceIDs) == 0 {
			return nil, v3err(V3ErrInvalidRequest, field+".sourceIds", "必须是非空数组")
		}
		seen := map[string]bool{}
		for j, id := range region.SourceIDs {
			if id == "" {
				return nil, v3err(V3ErrInvalidRequest, fmt.Sprintf("%s.sourceIds[%d]", field, j), "必须是非空字符串")
			}
			if seen[id] {
				return nil, v3err(V3ErrDuplicateReference, field+".sourceIds", "sourceId 重复: %s", id)
			}
			seen[id] = true
		}
		if region.ReadingOrder == nil || *region.ReadingOrder < 0 {
			return nil, v3err(V3ErrInvalidRequest, field+".readingOrder", "必须是非负整数")
		}
		if region.Confidence == nil || *region.Confidence < 0 || *region.Confidence > 1 {
			return nil, v3err(V3ErrInvalidRequest, field+".confidence", "必须在 [0,1]")
		}
		for j, relation := range region.Relations {
			relField := fmt.Sprintf("%s.relations[%d]", field, j)
			if !v3RelationTypes[relation.Type] {
				return nil, v3err(V3ErrUnknownEnum, relField+".type", "未知 relation type 枚举: %s", relation.Type)
			}
			if !regionIDs[relation.TargetRegionID] {
				return nil, v3err(V3ErrDanglingReference, relField+".targetRegionId", "relation 引用了未声明 region: %s", relation.TargetRegionID)
			}
		}
	}
	if err := rejectRelationCycle(resp.Regions); err != nil {
		return nil, err
	}
	if len(resp.Warnings) > 16 {
		return nil, v3err(V3ErrLimitExceeded, "warnings", "超过上限 16")
	}
	for i, warning := range resp.Warnings {
		if utf8.RuneCountInString(warning) > 500 {
			return nil, v3err(V3ErrLimitExceeded, fmt.Sprintf("warnings[%d]", i), "warning 超过 500 字符")
		}
	}
	return &resp, nil
}

var v3UnknownFieldPattern = regexp.MustCompile(`unknown field "([^"]*)"`)

// requireKeys：对象级必需键存在且非 null（缺失/null → invalid_request）。
func requireKeys(raw json.RawMessage, required []string, prefix string) *SmartLayoutV3Error {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(raw, &obj); err != nil {
		return v3err(V3ErrInvalidRequest, prefix, "必须是对象")
	}
	for _, key := range required {
		value, ok := obj[key]
		if !ok || string(value) == "null" {
			field := key
			if prefix != "" {
				field = prefix + "." + key
			}
			return v3err(V3ErrInvalidRequest, field, "缺少必填字段或为 null")
		}
	}
	return nil
}

func requireArrayElementKeys(raw json.RawMessage, required []string, prefix string) *SmartLayoutV3Error {
	var elements []json.RawMessage
	if err := json.Unmarshal(raw, &elements); err != nil {
		return v3err(V3ErrInvalidRequest, prefix, "必须是数组")
	}
	for i, element := range elements {
		if err := requireKeys(element, required, fmt.Sprintf("%s[%d]", prefix, i)); err != nil {
			return err
		}
	}
	return nil
}

func rawObjectOf(data []byte) (map[string]json.RawMessage, *SmartLayoutV3Error) {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(data, &obj); err != nil {
		return nil, v3err(V3ErrInvalidRequest, "", "根必须是对象")
	}
	return obj, nil
}

// requireRequestKeys：请求全层级必需键预检（与 Dart require() 等价）。
func requireRequestKeys(root map[string]json.RawMessage) *SmartLayoutV3Error {
	for _, key := range []string{"protocolVersion", "pageId", "sceneRevision", "assets", "marks", "exactTexts", "sourceRefs"} {
		if _, ok := root[key]; !ok {
			return v3err(V3ErrInvalidRequest, key, "缺少必填字段")
		}
		if string(root[key]) == "null" {
			return v3err(V3ErrInvalidRequest, key, "缺少必填字段或为 null")
		}
	}
	if err := requireKeys(root["sceneRevision"], []string{"epoch", "revision", "fingerprint"}, "sceneRevision"); err != nil {
		return err
	}
	if err := requireArrayElementKeys(root["assets"], []string{"key", "kind", "fingerprint"}, "assets"); err != nil {
		return err
	}
	if err := requireArrayElementKeys(root["marks"], []string{"markId", "label", "assetKey", "sourceId"}, "marks"); err != nil {
		return err
	}
	if err := requireArrayElementKeys(root["exactTexts"], []string{"sourceId", "text"}, "exactTexts"); err != nil {
		return err
	}
	return nil
}

// requireResponseKeys：响应全层级必需键预检。
func requireResponseKeys(root map[string]json.RawMessage) *SmartLayoutV3Error {
	for _, key := range []string{"protocolVersion", "regions", "warnings"} {
		if _, ok := root[key]; !ok || string(root[key]) == "null" {
			return v3err(V3ErrInvalidRequest, key, "缺少必填字段或为 null")
		}
	}
	var regions []json.RawMessage
	if err := json.Unmarshal(root["regions"], &regions); err != nil {
		return v3err(V3ErrInvalidRequest, "regions", "必须是数组")
	}
	for i, region := range regions {
		prefix := fmt.Sprintf("regions[%d]", i)
		if err := requireKeys(region, []string{"id", "role", "sourceIds", "readingOrder", "confidence", "relations"}, prefix); err != nil {
			return err
		}
		var regionObj map[string]json.RawMessage
		if err := json.Unmarshal(region, &regionObj); err != nil {
			return v3err(V3ErrInvalidRequest, prefix, "必须是对象")
		}
		if err := requireArrayElementKeys(regionObj["relations"], []string{"type", "targetRegionId"}, prefix+".relations"); err != nil {
			return err
		}
	}
	return nil
}

// decodeStrict：未知字段 unknown_field，类型/语法错误 invalid_request。
func decodeStrict(data []byte, v any) *SmartLayoutV3Error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		if typeErr, ok := err.(*json.UnmarshalTypeError); ok {
			field := typeErr.Field
			if field == "" {
				field = typeErr.Struct
			}
			return v3err(V3ErrInvalidRequest, field, "字段类型错误: %v", err)
		}
		if _, ok := err.(*json.SyntaxError); ok {
			return v3err(V3ErrInvalidRequest, "", "JSON 语法错误: %v", err)
		}
		if m := v3UnknownFieldPattern.FindStringSubmatch(err.Error()); m != nil {
			return v3err(V3ErrUnknownField, m[1], "未知字段")
		}
		return v3err(V3ErrInvalidRequest, "", "JSON 解析失败: %v", err)
	}
	if decoder.More() {
		return v3err(V3ErrInvalidRequest, "", "JSON 后有尾随内容")
	}
	return nil
}

// rejectRelationCycle：关系链 DFS 三色成环检测（与 Dart 同语义）。
func rejectRelationCycle(regions []SmartLayoutV3Region) *SmartLayoutV3Error {
	edges := map[string][]string{}
	for _, region := range regions {
		list := make([]string, 0, len(region.Relations))
		for _, relation := range region.Relations {
			list = append(list, relation.TargetRegionID)
		}
		edges[region.ID] = list
	}
	const (
		visiting = 1
		done     = 2
	)
	state := map[string]int{}
	var stack []string
	var dfs func(id string) *SmartLayoutV3Error
	dfs = func(id string) *SmartLayoutV3Error {
		switch state[id] {
		case done:
			return nil
		case visiting:
			return v3err(V3ErrReferenceCycle, "regions", "关系链成环: %v", append(stack, id))
		}
		state[id] = visiting
		stack = append(stack, id)
		for _, next := range edges[id] {
			if err := dfs(next); err != nil {
				return err
			}
		}
		stack = stack[:len(stack)-1]
		state[id] = done
		return nil
	}
	for id := range edges {
		if err := dfs(id); err != nil {
			return err
		}
	}
	return nil
}
