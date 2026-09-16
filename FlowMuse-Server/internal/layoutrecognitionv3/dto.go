// dto.go：recognize/v3 wire 结构体与常量（spec §3）。与 Dart 侧
// recognition_models.dart 同源；fixtures 双端同类拒绝。
package layoutrecognitionv3

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
)

// SchemaVersion 是协议版本（唯一合法值）。
const SchemaVersion = "recognition-v3/1"

// EndpointPath 是路由路径。
const EndpointPath = "/api/ink/smart-layout/recognize/v3"

// Stage 枚举。
const (
	StageRead      = "read"
	StageVerify    = "verify"
	StageStructure = "structure"
)

// 错误码（spec §3.5；camelCase，与 Dart 端 RecognitionExceptionCode 同名）。
const (
	CodeInvalidSchema       = "invalidSchema"
	CodeDuplicateID         = "duplicateId"
	CodeLimitExceeded       = "limitExceeded"
	CodeTextTooLong         = "textTooLong"
	CodeBadGeometry         = "badGeometry"
	CodeAuth                = "auth"
	CodeBusy                = "busy"
	CodeUnconfigured        = "unconfigured"
	CodeProviderTimeout     = "providerTimeout"
	CodeProviderError       = "providerError"
	CodeInvalidProviderResp = "invalidProviderResponse"
	CodeInternal            = "internal"
)

// retryableByCode 是 §3.5 表的 retryable 列。
var retryableByCode = map[string]bool{
	CodeInvalidSchema:       false,
	CodeDuplicateID:         false,
	CodeLimitExceeded:       false,
	CodeTextTooLong:         false,
	CodeBadGeometry:         false,
	CodeAuth:                false,
	CodeBusy:                true,
	CodeUnconfigured:        false,
	CodeProviderTimeout:     true,
	CodeProviderError:       true,
	CodeInvalidProviderResp: false,
	CodeInternal:            false,
}

// WireError 是统一错误 envelope：{"error":{"code","message","retryable"}}。
type WireError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

func wireErr(code, message string) *WireError {
	return &WireError{
		Code:      code,
		Message:   message,
		Retryable: retryableByCode[code],
	}
}

// SceneRevision 表达 Scene 版本三元组。
type SceneRevision struct {
	Epoch       int    `json:"epoch"`
	Revision    int    `json:"revision"`
	Fingerprint string `json:"fingerprint"`
}

// RegionImageInput 是 read/verify 请求的单区域输入（verify 追加
// original*/reason；read 禁止携带这些字段——stage 字段隔离在
// ValidateRequest 校验）。
type RegionImageInput struct {
	RegionID           string   `json:"regionId"`
	ImagePngBase64     string   `json:"imagePngBase64"`
	ImageScale         float64  `json:"imageScale"`
	ContextBefore      *string  `json:"contextBefore,omitempty"`
	ContextAfter       *string  `json:"contextAfter,omitempty"`
	OriginalText       *string  `json:"originalText,omitempty"`
	OriginalConfidence *float64 `json:"originalConfidence,omitempty"`
	Reason             string   `json:"reason,omitempty"`
}

// UnitInput 是 structure 请求的单 unit 输入。
type UnitInput struct {
	UnitID         string     `json:"unitId"`
	Kind           string     `json:"kind"` // typed|ink|figure|preserved
	Text           *string    `json:"text,omitempty"`
	Bounds         UnitBounds `json:"bounds"`
	LineHintHeight *float64   `json:"lineHintHeight,omitempty"`
	RoleHint       *string    `json:"roleHint,omitempty"`
}

// UnitBounds 是页面坐标外框（全有限数、宽高非负）。
type UnitBounds struct {
	Left   float64 `json:"left"`
	Top    float64 `json:"top"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// IsTextUnit 报告该 unit 是否文本单元（typed/ink）。
func (u UnitInput) IsTextUnit() bool {
	return u.Kind == "typed" || u.Kind == "ink"
}

// RecognitionRequest 是三阶段共用的请求外壳；stage 决定有效字段集。
type RecognitionRequest struct {
	SchemaVersion      string             `json:"schemaVersion"`
	Stage              string             `json:"stage"`
	OperationID        string             `json:"operationId"`
	RequestID          string             `json:"requestId"`
	PageID             string             `json:"pageId"`
	SceneRevision      SceneRevision      `json:"sceneRevision"`
	ContentFingerprint string             `json:"contentFingerprint"`
	Generation         int                `json:"generation"`
	Regions            []RegionImageInput `json:"regions,omitempty"`
	Units              []UnitInput        `json:"units,omitempty"`
	OverviewPngBase64  string             `json:"overviewPngBase64,omitempty"`
	TextFingerprint    string             `json:"textFingerprint,omitempty"`
}

// RegionResult 是 read/verify 响应的单区域结果。
type RegionResult struct {
	RegionID    string   `json:"regionId"`
	Status      string   `json:"status"`
	Text        string   `json:"text,omitempty"`
	Confidence  *float64 `json:"confidence,omitempty"`
	Diagnostics []string `json:"diagnostics"`
}

// RoleAssignment 是 structure 响应的角色指派（仅文本单元）。
type RoleAssignment struct {
	UnitID string `json:"unitId"`
	Role   string `json:"role"` // title|body|caption|listItem|other
}

// ListGroup 是 structure 响应的列表分组（支持嵌套挂靠）。
type ListGroup struct {
	GroupID      string   `json:"groupId"`
	Members      []string `json:"members"`
	Level        int      `json:"level"`
	ParentUnitID *string  `json:"parentUnitId,omitempty"`
	ListType     string   `json:"listType"` // ordered|unordered
	StartNumber  *int     `json:"startNumber,omitempty"`
}

// Caption 是 structure 响应的图注归属。
type Caption struct {
	CaptionUnitID string `json:"captionUnitId"`
	TargetUnitID  string `json:"targetUnitId"`
}

// RecognitionResponse 是三阶段共用的响应外壳；服务端从请求回填，
// 不依赖模型回显（R-12 由客户端比对兜底）。
type RecognitionResponse struct {
	SchemaVersion      string           `json:"schemaVersion"`
	Stage              string           `json:"stage"`
	OperationID        string           `json:"operationId"`
	RequestID          string           `json:"requestId"`
	PageID             string           `json:"pageId"`
	SceneRevision      SceneRevision    `json:"sceneRevision"`
	ContentFingerprint string           `json:"contentFingerprint"`
	Generation         int              `json:"generation"`
	Regions            []RegionResult   `json:"regions,omitempty"`
	MissingRegionIDs   []string         `json:"missingRegionIds,omitempty"`
	TextFingerprint    string           `json:"textFingerprint,omitempty"`
	ReadingOrder       []string         `json:"readingOrder,omitempty"`
	Roles              []RoleAssignment `json:"roles,omitempty"`
	ListGroups         []ListGroup      `json:"listGroups,omitempty"`
	Captions           []Caption        `json:"captions,omitempty"`
	Warnings           []string         `json:"warnings,omitempty"`
}

// ModelRegionResult 是模型侧 read/verify 输出的单区域结果（无外壳）。
type ModelRegionResult struct {
	RegionID    string   `json:"regionId"`
	Status      string   `json:"status"`
	Text        *string  `json:"text,omitempty"`
	Confidence  *float64 `json:"confidence,omitempty"`
	Diagnostics []string `json:"diagnostics,omitempty"`
}

// ModelStructureResult 是模型侧 structure 输出（无外壳、无正文）。
type ModelStructureResult struct {
	ReadingOrder []string         `json:"readingOrder"`
	Roles        []ModelRoleEntry `json:"roles"`
	ListGroups   []ModelListGroup `json:"listGroups"`
	Captions     []ModelCaption   `json:"captions"`
	Warnings     []string         `json:"warnings,omitempty"`
}

// ModelRoleEntry 模型角色输出；Text 非空即 R-10 违规。
type ModelRoleEntry struct {
	UnitID string  `json:"unitId"`
	Role   string  `json:"role"`
	Text   *string `json:"text,omitempty"`
}

// ModelListGroup 模型分组输出。
type ModelListGroup struct {
	GroupID      string   `json:"groupId"`
	Members      []string `json:"members"`
	Level        int      `json:"level"`
	ParentUnitID *string  `json:"parentUnitId,omitempty"`
	ListType     string   `json:"listType"`
	StartNumber  *int     `json:"startNumber,omitempty"`
	Text         *string  `json:"text,omitempty"`
}

// ModelCaption 模型图注输出。
type ModelCaption struct {
	CaptionUnitID string  `json:"captionUnitId"`
	TargetUnitID  string  `json:"targetUnitId"`
	Text          *string `json:"text,omitempty"`
}

// decodeStrict 严格 JSON 解码：未知字段与尾随内容（含垃圾文本）拒绝。
func decodeStrict(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	if dec.More() {
		return errors.New("尾随内容拒绝")
	}
	if err := dec.Decode(new(json.RawMessage)); !errors.Is(err, io.EOF) {
		return errors.New("尾随内容拒绝")
	}
	return nil
}

// DecodeRecognitionRequest 严格解析请求 body（不含上限校验，见
// ValidateRequest）。
func DecodeRecognitionRequest(body []byte) (*RecognitionRequest, error) {
	var req RecognitionRequest
	if err := decodeStrict(body, &req); err != nil {
		return nil, err
	}
	return &req, nil
}
