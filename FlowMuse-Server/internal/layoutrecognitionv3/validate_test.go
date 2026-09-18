package layoutrecognitionv3

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// 双端 conformance：Dart 与 Go 消费同一 fixtures
// （docs/研发记录/specs/smart-layout-v3/recognition/fixtures）。
// 请求侧正负例全量；响应侧覆盖模型输出 sanitize 语义——
// n9/n19/n25 是客户端响应外壳语义（覆盖声明/回填比对），服务端不构造
// 该输入，跳过（Dart 端 dto_json_test 全量覆盖）。
var dartOnlyResponseFixtures = map[string]bool{
	"n9-coverage-mismatch.json":               true,
	"n19-echo-operation-mismatch.json":        true,
	"n25-text-fingerprint-echo-mismatch.json": true,
}

const fixturesDir = "../../../docs/研发记录/specs/smart-layout-v3/recognition/fixtures"

type fixtureEnvelope struct {
	Kind              string          `json:"kind"`
	Expect            string          `json:"expect"`
	ExpectedErrorCode string          `json:"expectedErrorCode"`
	Request           json.RawMessage `json:"request"`
	Payload           json.RawMessage `json:"payload"`
}

func TestFixtureConformanceRequests(t *testing.T) {
	entries, err := os.ReadDir(filepath.Join(fixturesDir, "positive"))
	if err != nil {
		t.Fatalf("fixtures 目录不可读: %v", err)
	}
	limits := DefaultLimits()
	positive := 0
	for _, entry := range entries {
		var envelope fixtureEnvelope
		loadFixture(t, filepath.Join(fixturesDir, "positive", entry.Name()), &envelope)
		if envelope.Kind != "request" {
			continue
		}
		positive++
		req, dErr := DecodeRecognitionRequest(envelope.Payload)
		if dErr != nil {
			t.Fatalf("%s: 正例请求解析失败: %v", entry.Name(), dErr)
		}
		if vErr := ValidateRequest(req, limits); vErr != nil {
			t.Fatalf("%s: 正例请求校验失败: %s: %s", entry.Name(), vErr.Code, vErr.Message)
		}
	}
	if positive < 4 {
		t.Fatalf("正例请求 fixture 不足: %d", positive)
	}
}

func TestFixtureConformanceNegative(t *testing.T) {
	entries, err := os.ReadDir(filepath.Join(fixturesDir, "negative"))
	if err != nil {
		t.Fatalf("fixtures 目录不可读: %v", err)
	}
	rejected := 0
	for _, entry := range entries {
		name := entry.Name()
		var envelope fixtureEnvelope
		loadFixture(t, filepath.Join(fixturesDir, "negative", name), &envelope)
		if envelope.Kind == "request" {
			wire := validateFixtureRequest(t, envelope)
			if wire.Code != envelope.ExpectedErrorCode {
				t.Fatalf("%s: 期望 %s，实际 %s（%s）", name, envelope.ExpectedErrorCode, wire.Code, wire.Message)
			}
			rejected++
			continue
		}
		if dartOnlyResponseFixtures[name] {
			continue
		}
		wire := validateFixtureResponse(t, envelope)
		if wire == nil {
			t.Fatalf("%s: 期望拒绝（%s），实际通过", name, envelope.ExpectedErrorCode)
		}
		if wire.Code != envelope.ExpectedErrorCode {
			t.Fatalf("%s: 期望 %s，实际 %s（%s）", name, envelope.ExpectedErrorCode, wire.Code, wire.Message)
		}
		rejected++
	}
	if rejected < 20 {
		t.Fatalf("负例覆盖不足: %d", rejected)
	}
}

func TestFixtureConformanceResponsesPositive(t *testing.T) {
	for _, name := range []string{
		"p5-read-response-partial.json",
		"p6-read-response-all-missing.json",
		"p7-structure-response.json",
		"p8-verify-response.json",
	} {
		var envelope fixtureEnvelope
		loadFixture(t, filepath.Join(fixturesDir, "positive", name), &envelope)
		if wire := validateFixtureResponse(t, envelope); wire != nil {
			t.Fatalf("%s: 正例响应校验失败: %s: %s", name, wire.Code, wire.Message)
		}
	}
	// p5/p6 的 missingRegionIds 语义：服务端从请求集合求差生成。
	var partial fixtureEnvelope
	loadFixture(t, filepath.Join(fixturesDir, "positive", "p5-read-response-partial.json"), &partial)
	var payload struct {
		MissingRegionIDs []string `json:"missingRegionIds"`
	}
	if err := json.Unmarshal(partial.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	var request RecognitionRequest
	if err := json.Unmarshal(partial.Request, &request); err != nil {
		t.Fatal(err)
	}
	requested := make([]string, 0, len(request.Regions))
	for _, region := range request.Regions {
		requested = append(requested, region.RegionID)
	}
	var model []ModelRegionResult
	if err := json.Unmarshal(modelRegionsOf(t, partial.Payload), &model); err != nil {
		t.Fatal(err)
	}
	regions, missing, wire := SanitizeRegionResults(requested, model)
	if wire != nil {
		t.Fatalf("p5 sanitize 失败: %s", wire.Message)
	}
	if len(regions) != 2 || len(missing) != 1 || missing[0] != "r:b" {
		t.Fatalf("p5 部分批次语义错误: regions=%d missing=%v", len(regions), missing)
	}
	if len(missing) != len(payload.MissingRegionIDs) {
		t.Fatalf("服务端求差生成的 missing 与 fixture 声明不一致: %v vs %v", missing, payload.MissingRegionIDs)
	}
}

func validateFixtureRequest(t *testing.T, envelope fixtureEnvelope) *WireError {
	t.Helper()
	req, dErr := DecodeRecognitionRequest(envelope.Payload)
	if dErr != nil {
		return wireErr(CodeInvalidSchema, dErr.Error())
	}
	return ValidateRequest(req, DefaultLimits())
}

// validateFixtureResponse 把响应 fixture 的模型输出部分喂给服务端
// sanitize（服务端不构造响应外壳，客户端语义见 Dart 端测试）。
func validateFixtureResponse(t *testing.T, envelope fixtureEnvelope) *WireError {
	t.Helper()
	var request RecognitionRequest
	if err := json.Unmarshal(envelope.Request, &request); err != nil {
		t.Fatalf("配对请求解析失败: %v", err)
	}
	if request.Stage == StageStructure {
		var payload struct {
			ReadingOrder []string         `json:"readingOrder"`
			Roles        []ModelRoleEntry `json:"roles"`
			ListGroups   []ModelListGroup `json:"listGroups"`
			Captions     []ModelCaption   `json:"captions"`
			Warnings     []string         `json:"warnings"`
		}
		if err := json.Unmarshal(envelope.Payload, &payload); err != nil {
			t.Fatalf("结构响应解析失败: %v", err)
		}
		_, wire := SanitizeStructureResult(request.Units, &ModelStructureResult{
			ReadingOrder: payload.ReadingOrder,
			Roles:        payload.Roles,
			ListGroups:   payload.ListGroups,
			Captions:     payload.Captions,
			Warnings:     payload.Warnings,
		})
		return wire
	}
	var model []ModelRegionResult
	if err := json.Unmarshal(modelRegionsOf(t, envelope.Payload), &model); err != nil {
		t.Fatalf("区域响应解析失败: %v", err)
	}
	requested := make([]string, 0, len(request.Regions))
	for _, region := range request.Regions {
		requested = append(requested, region.RegionID)
	}
	_, _, wire := SanitizeRegionResults(requested, model)
	return wire
}

func modelRegionsOf(t *testing.T, payload json.RawMessage) json.RawMessage {
	t.Helper()
	var parsed struct {
		Regions []json.RawMessage `json:"regions"`
	}
	if err := json.Unmarshal(payload, &parsed); err != nil {
		t.Fatal(err)
	}
	out, err := json.Marshal(parsed.Regions)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func loadFixture(t *testing.T, path string, target any) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("fixture 读取失败 %s: %v", path, err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		t.Fatalf("fixture 解析失败 %s: %v", path, err)
	}
}

func TestSanitizeRegionResultsPartialSemantics(t *testing.T) {
	// 全部漏答是合法结果（regions 空 + missing=全集）。
	regions, missing, wire := SanitizeRegionResults(
		[]string{"r:a", "r:b"}, nil)
	if wire != nil {
		t.Fatalf("全漏答应合法: %s", wire.Message)
	}
	if len(regions) != 0 || len(missing) != 2 {
		t.Fatalf("全漏答语义错误: %v %v", regions, missing)
	}
	// 数组内部重复拒绝。
	dup := "x"
	_, _, wire = SanitizeRegionResults([]string{"r:a"}, []ModelRegionResult{
		{RegionID: "r:a", Status: "recognized", Text: &dup},
		{RegionID: "r:a", Status: "recognized", Text: &dup},
	})
	if wire == nil || wire.Code != CodeInvalidProviderResp {
		t.Fatalf("重复 regionId 应整批拒绝: %v", wire)
	}
}

// transparentPngBase64 是 1×1 全透明 PNG——零长度笔画渲染产物的事故
// 样本形态（2026-09-18 真机：831×831 同性质空图致 provider 无限挂起）。
const transparentPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg=="

func TestValidateRequestRejectsFullyTransparentImage(t *testing.T) {
	read := RecognitionRequest{
		SchemaVersion:      SchemaVersion,
		Stage:              StageRead,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Fingerprint: "sfp"},
		ContentFingerprint: "fp",
		Regions:            []RegionImageInput{validRegion("r:a")},
	}
	read.Regions[0].ImagePngBase64 = transparentPngBase64
	wire := ValidateRequest(&read, DefaultLimits())
	if wire == nil || wire.Code != CodeInvalidSchema {
		t.Fatalf("全透明区域图应 400 拒绝: %v", wire)
	}

	structure := RecognitionRequest{
		SchemaVersion:      SchemaVersion,
		Stage:              StageStructure,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Fingerprint: "sfp"},
		ContentFingerprint: "fp",
		Units:              []UnitInput{validUnit("ink:r:x")},
		TextFingerprint:    "tfp",
	}
	structure.OverviewPngBase64 = transparentPngBase64
	wire = ValidateRequest(&structure, DefaultLimits())
	if wire == nil || wire.Code != CodeInvalidSchema {
		t.Fatalf("全透明概览图应 400 拒绝: %v", wire)
	}
}

func TestValidateRequestStageIsolation(t *testing.T) {
	base := RecognitionRequest{
		SchemaVersion:      SchemaVersion,
		Stage:              StageRead,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Fingerprint: "sfp"},
		ContentFingerprint: "fp",
		Generation:         0,
		Regions:            []RegionImageInput{validRegion("r:a")},
	}
	if wire := ValidateRequest(&base, DefaultLimits()); wire != nil {
		t.Fatalf("基线请求应通过: %s", wire.Message)
	}
	withUnits := base
	withUnits.Units = []UnitInput{validUnit("ink:r:x")}
	if wire := ValidateRequest(&withUnits, DefaultLimits()); wire == nil || wire.Code != CodeInvalidSchema {
		t.Fatalf("read 携带 units 应拒绝: %v", wire)
	}
	structure := RecognitionRequest{
		SchemaVersion:      SchemaVersion,
		Stage:              StageStructure,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Fingerprint: "sfp"},
		ContentFingerprint: "fp",
		Generation:         0,
		Units:              []UnitInput{validUnit("ink:r:x")},
		TextFingerprint:    "tfp",
	}
	if wire := ValidateRequest(&structure, DefaultLimits()); wire != nil {
		t.Fatalf("structure 基线应通过: %s", wire.Message)
	}
	withRegions := structure
	withRegions.Regions = []RegionImageInput{validRegion("r:a")}
	if wire := ValidateRequest(&withRegions, DefaultLimits()); wire == nil {
		t.Fatal("structure 携带 regions 应拒绝")
	}
	verifyNoReason := RecognitionRequest{
		SchemaVersion:      SchemaVersion,
		Stage:              StageVerify,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Fingerprint: "sfp"},
		ContentFingerprint: "fp",
		Regions:            []RegionImageInput{validRegion("r:a")},
	}
	if wire := ValidateRequest(&verifyNoReason, DefaultLimits()); wire == nil || wire.Code != CodeInvalidSchema {
		t.Fatalf("verify 缺 reason 应拒绝: %v", wire)
	}
}

func validRegion(id string) RegionImageInput {
	return RegionImageInput{
		RegionID:       id,
		ImagePngBase64: tinyPngBase64,
		ImageScale:     1.5,
	}
}

func validUnit(id string) UnitInput {
	text := "手写正文"
	return UnitInput{
		UnitID: id,
		Kind:   "ink",
		Text:   &text,
		Bounds: UnitBounds{
			Left: 0, Top: 0, Width: 100, Height: 20,
		},
	}
}
