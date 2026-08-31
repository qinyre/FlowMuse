package recognition

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

// V3-202A：总览/crop 分级复核与冲突保留合并。

func overviewResponseForConfidences(confidences map[string]float64) []byte {
	regions := ""
	id := 0
	for regionID, conf := range confidences {
		if regions != "" {
			regions += ","
		}
		regions += fmt.Sprintf(`{"id":%q,"role":"body","sourceIds":[%q],"readingOrder":%d,"confidence":%f,"relations":[]}`,
			regionID, sourceRefOf(regionID), id, conf)
		id++
	}
	return []byte(fmt.Sprintf(`{"protocolVersion":3,"regions":[%s],"warnings":[]}`, regions))
}

// region→sourceRef 一一对应（g1→r1, g2→r2, g3→r3, g4→text-1）。
func sourceRefOf(regionID string) string {
	switch regionID {
	case "g1":
		return "r1"
	case "g2":
		return "r2"
	case "g3":
		return "ink-3"
	case "g4":
		return "text-1"
	}
	return "r1"
}

func TestV3OverviewLowConfidenceTriage(t *testing.T) {
	analyzer := NewV3OverviewAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return overviewResponseForConfidences(map[string]float64{
			"g1": 0.9, "g2": 0.59, "g3": 0.6, "g4": 0.2,
		}), nil
	}, 0.6)
	outcome, v3Err := analyzer.Analyze(context.Background(), v3TestRequest())
	if v3Err != nil {
		t.Fatalf("总览失败: %+v", v3Err)
	}
	if len(outcome.Response.Regions) != 4 {
		t.Fatalf("区域数: %d", len(outcome.Response.Regions))
	}
	got := map[string]bool{}
	for _, id := range outcome.LowConfidenceRegionIDs {
		got[id] = true
	}
	// g2=0.59<0.6 升级；g3=0.6 恰在下限不升级；g4=0.2 升级。
	if len(got) != 2 || !got["g2"] || !got["g4"] {
		t.Fatalf("低置信分诊不准: %v", got)
	}
}

func TestV3OverviewRejectsMalformedProviderOutput(t *testing.T) {
	analyzer := NewV3OverviewAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return []byte(`{"regions":`), nil
	}, 0.6)
	if outcome, v3Err := analyzer.Analyze(context.Background(), v3TestRequest()); outcome != nil || v3Err == nil {
		t.Fatal("残缺总览输出必须稳定错误")
	}
	failing := NewV3OverviewAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return nil, errors.New("503")
	}, 0.6)
	if _, v3Err := failing.Analyze(context.Background(), v3TestRequest()); v3Err == nil || v3Err.Code != V3ErrInternal {
		t.Fatal("provider 失败必须 internal 稳定错误")
	}
}

func cropJSON(regionID, kind, content, role string, confidence float64) []byte {
	return []byte(fmt.Sprintf(`{"regionId":%q,"kind":%q,"content":%q,"role":%q,"confidence":%f}`,
		regionID, kind, content, role, confidence))
}

func TestV3CropStrictParse(t *testing.T) {
	if _, v3Err := parseV3CropResult(cropJSON("g1", "ocr", "手写内容", "body", 0.8), "g1"); v3Err != nil {
		t.Fatalf("合法 crop 被拒: %+v", v3Err)
	}
	bad := []struct {
		name string
		raw  []byte
		want string
	}{
		{"回显不符", cropJSON("other", "ocr", "x", "body", 0.8), V3ErrInternal},
		{"未知 kind", cropJSON("g1", "asr", "x", "body", 0.8), V3ErrUnknownEnum},
		{"未知 role", cropJSON("g1", "ocr", "x", "sidebar", 0.8), V3ErrUnknownEnum},
		{"缺 confidence", []byte(`{"regionId":"g1","kind":"ocr","content":"x","role":"body"}`), V3ErrInvalidRequest},
		// 未知字段与其它 schema 违例一样按 201A 惯例包为 internal（码入 message）
		{"未知字段", []byte(`{"regionId":"g1","kind":"ocr","content":"x","role":"body","confidence":0.5,"evil":1}`), V3ErrInternal},
	}
	for _, tc := range bad {
		t.Run(tc.name, func(t *testing.T) {
			if _, v3Err := parseV3CropResult(tc.raw, "g1"); v3Err == nil || v3Err.Code != tc.want {
				t.Fatalf("got %+v want %s", v3Err, tc.want)
			}
		})
	}
}

func TestV3AnalysisMergerPreservesConflicts(t *testing.T) {
	req := v3TestRequest() // exactTexts: text-1, text-2; refs: r1 r2 text-1 text-2 ink-3
	overviewRaw := overviewResponseForConfidences(map[string]float64{
		"g1": 0.9, // 手写，role=body
		"g2": 0.5, // 手写，低置信
		"g3": 0.9, // 手写
		"g4": 0.9, // typed（text-1）
	})
	overview, sErr := ParseSmartLayoutV3Response(overviewRaw)
	if sErr != nil {
		t.Fatal(sErr)
	}
	crops := []V3CropResult{
		{RegionID: "g1", Kind: "ocr", Content: "g1 手写识别", Role: "body", Confidence: 0.9},         // 一致 → 采纳内容
		{RegionID: "g2", Kind: "ocr", Content: "g2 手写识别", Role: "list", Confidence: 0.85},        // role 分歧 → 冲突
		{RegionID: "g4", Kind: "ocr", Content: "试图改写 typed text", Role: "body", Confidence: 0.9}, // 越权改写 → 冲突+丢弃
	}
	failures := []V3CropError{
		{RegionID: "g3", Err: v3err(V3ErrInternal, "", "crop provider 失败: timeout")},
	}
	doc, mErr := NewV3AnalysisMerger().Merge(req, overview, crops, failures)
	if mErr != nil {
		t.Fatalf("合并失败: %+v", mErr)
	}
	// typed text 未被改写。
	if doc.Analysis.RegionTexts["g4"] != "标题：会议纪要" {
		t.Fatalf("typed exactText 被改写: %q", doc.Analysis.RegionTexts["g4"])
	}
	if _, leaked := doc.CropContents["g4"]; leaked {
		t.Fatal("越权 crop 内容必须丢弃")
	}
	// 一致的 crop 内容保留。
	if doc.CropContents["g1"] != "g1 手写识别" {
		t.Fatalf("一致 crop 内容丢失: %v", doc.CropContents)
	}
	// 三类冲突全部留档，不静默择一。
	byKind := map[string]bool{}
	for _, conflict := range doc.Conflicts {
		byKind[conflict.Kind] = true
	}
	for _, kind := range []string{"role-disagreement", "typed-text-overwrite-attempt", "crop-failed"} {
		if !byKind[kind] {
			t.Fatalf("冲突 %s 未留档: %+v", kind, doc.Conflicts)
		}
	}
	// role 分歧保留总览结论（保守）。
	for _, region := range doc.Analysis.Response.Regions {
		if region.ID == "g2" && region.Role != "body" {
			t.Fatalf("role 分歧被静默择一为 crop 结论: %s", region.Role)
		}
	}
}

func TestRunV3AnalysisFullPipeline(t *testing.T) {
	var escalated []string
	overviewAnalyzer := NewV3OverviewAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return overviewResponseForConfidences(map[string]float64{
			"g1": 0.9, "g2": 0.3, "g3": 0.8, "g4": 0.5,
		}), nil
	}, 0.6)
	cropAnalyzer := NewV3CropAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request, regionID string) ([]byte, error) {
		escalated = append(escalated, regionID)
		return cropJSON(regionID, "ocr", regionID+" 内容", "body", 0.9), nil
	})
	doc, v3Err := RunV3Analysis(context.Background(), v3TestRequest(), overviewAnalyzer, cropAnalyzer)
	if v3Err != nil {
		t.Fatalf("全链失败: %+v", v3Err)
	}
	if len(escalated) != 2 {
		t.Fatalf("升级数不符: %v", escalated)
	}
	// g4 是 typed 区域，crop 触碰 → 冲突留档且 text 不变。
	if doc.Analysis.RegionTexts["g4"] != "标题：会议纪要" {
		t.Fatal("typed text 被改写")
	}
	foundOverwrite := false
	for _, conflict := range doc.Conflicts {
		if conflict.Kind == "typed-text-overwrite-attempt" {
			foundOverwrite = true
		}
	}
	if !foundOverwrite {
		t.Fatal("typed 改写企图未留档")
	}
	// g2 手写低置信 → crop 内容入文档。
	if doc.CropContents["g2"] != "g2 内容" {
		t.Fatalf("低置信 crop 内容丢失: %v", doc.CropContents)
	}
}

func TestRunV3AnalysisCropUnconfiguredRecordsConflict(t *testing.T) {
	overviewAnalyzer := NewV3OverviewAnalyzer(func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
		return overviewResponseForConfidences(map[string]float64{"g2": 0.1}), nil
	}, 0.6)
	doc, v3Err := RunV3Analysis(context.Background(), v3TestRequest(), overviewAnalyzer, nil)
	if v3Err != nil {
		t.Fatalf("crop 未配置不应失败全链: %+v", v3Err)
	}
	if len(doc.Conflicts) != 1 || doc.Conflicts[0].Kind != "crop-failed" {
		t.Fatalf("升级失败未留档: %+v", doc.Conflicts)
	}
}
