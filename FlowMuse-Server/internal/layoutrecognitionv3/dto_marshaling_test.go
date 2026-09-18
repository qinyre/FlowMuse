// 响应序列化键集契约测试：客户端严格读取器要求阶段相关数组键必须存在
// （空集也须为 []），跨阶段键一律拒绝（2026-09-18 真机事故回归）。
package layoutrecognitionv3

import (
	"encoding/json"
	"strings"
	"testing"
)

func shellOf(stage string) RecognitionResponse {
	return RecognitionResponse{
		SchemaVersion:      SchemaVersion,
		Stage:              stage,
		OperationID:        "op",
		RequestID:          "req",
		PageID:             "page",
		SceneRevision:      SceneRevision{Epoch: 0, Revision: 0, Fingerprint: "fp"},
		ContentFingerprint: "cfp",
		Generation:         1,
	}
}

func TestMarshalReadResponseAlwaysEmitsBatchArrays(t *testing.T) {
	// 全成功：regions 非空、missing 为空集 → missingRegionIds 必须出现为 []。
	response := shellOf(StageRead)
	response.Regions = []RegionResult{{
		RegionID:    "r:a",
		Status:      "recognized",
		Text:        "正文",
		Confidence:  float64Ptr(0.99),
		Diagnostics: []string{},
	}}
	encoded, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("序列化失败: %v", err)
	}
	body := string(encoded)
	if !strings.Contains(body, `"missingRegionIds":[]`) {
		t.Fatalf("空 missingRegionIds 必须输出为 []: %s", body)
	}
	if strings.Contains(body, "readingOrder") || strings.Contains(body, "textFingerprint") {
		t.Fatalf("read 响应不得携带结构键: %s", body)
	}

	// 全漏答（合法 200）：regions 空集 → 必须出现为 []。
	allMissing := shellOf(StageRead)
	allMissing.MissingRegionIDs = []string{"r:a"}
	encoded, err = json.Marshal(allMissing)
	if err != nil {
		t.Fatalf("序列化失败: %v", err)
	}
	body = string(encoded)
	if !strings.Contains(body, `"regions":[]`) {
		t.Fatalf("空 regions 必须输出为 []: %s", body)
	}
}

func TestMarshalStructureResponseAlwaysEmitsStructureArrays(t *testing.T) {
	response := shellOf(StageStructure)
	response.TextFingerprint = "tfp"
	// 分组/图注/警告均为空集：五个结构键都必须出现为 []。
	response.ReadingOrder = []string{"ink:r:a"}
	response.Roles = []RoleAssignment{{UnitID: "ink:r:a", Role: "body"}}
	encoded, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("序列化失败: %v", err)
	}
	body := string(encoded)
	for _, key := range []string{
		`"textFingerprint":"tfp"`,
		`"readingOrder"`,
		`"roles"`,
		`"listGroups":[]`,
		`"captions":[]`,
		`"warnings":[]`,
	} {
		if !strings.Contains(body, key) {
			t.Fatalf("structure 响应缺少 %s: %s", key, body)
		}
	}
	if strings.Contains(body, `"regions"`) || strings.Contains(body, `"missingRegionIds"`) {
		t.Fatalf("structure 响应不得携带区域键: %s", body)
	}
}

func float64Ptr(v float64) *float64 { return &v }
