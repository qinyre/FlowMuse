package layoutrecognitionv3

import (
	"strings"
	"testing"
)

func TestBuildReadPromptAnchors(t *testing.T) {
	context := "上一区域末行"
	prompt := BuildReadPrompt([]RegionImageInput{
		{RegionID: "r:ink-0007", ContextBefore: &context},
		{RegionID: "r:ink-0008"},
	})
	anchors := []string{
		"忠实转写器",
		"只输出图中可见文字",
		"保留原换行",
		"原样转写，不重排",
		"unreadable",
		"nonText",
		"每个区域独立判断",
		"r:ink-0007",
		"r:ink-0008",
		"上一区域末行",
		"严格 JSON 数组",
	}
	for _, anchor := range anchors {
		if !strings.Contains(prompt, anchor) {
			t.Fatalf("read 提示词缺少锚点: %s", anchor)
		}
	}
	if strings.Contains(prompt, "改写") && strings.Contains(prompt, "允许改写") {
		t.Fatal("提示词不得引入改写许可")
	}
}

func TestBuildVerifyPromptAnchors(t *testing.T) {
	original := "初读结果"
	confidence := 0.42
	prompt := BuildVerifyPrompt([]RegionImageInput{
		{
			RegionID:           "r:a",
			Reason:             "lowConfidence",
			OriginalText:       &original,
			OriginalConfidence: &confidence,
		},
	})
	anchors := []string{
		"复核转写器",
		"重新独立读图",
		"图中不可见的内容",
		"也不得保留",
		"r:a",
		"lowConfidence",
		"初读结果",
		"0.42",
	}
	for _, anchor := range anchors {
		if !strings.Contains(prompt, anchor) {
			t.Fatalf("verify 提示词缺少锚点: %s", anchor)
		}
	}
}

func TestBuildStructurePromptAnchors(t *testing.T) {
	text := "1. 第一项"
	hint := "listItem"
	lineHeight := 18.5
	prompt := BuildStructurePrompt([]UnitInput{
		{
			UnitID:         "ink:r:list-1",
			Kind:           "ink",
			Text:           &text,
			RoleHint:       &hint,
			LineHintHeight: &lineHeight,
			Bounds:         UnitBounds{Left: 10, Top: 60, Width: 280, Height: 24},
		},
		{UnitID: "native:img-3", Kind: "figure", Bounds: UnitBounds{Left: 350, Top: 60, Width: 150, Height: 150}},
	}, true)
	anchors := []string{
		"结构恢复器",
		"编号连续性",
		"缩进",
		"单项可以作为子列表",
		"parentUnitId",
		"不确定的角色",
		"other",
		"ink:r:list-1",
		"native:img-3",
		"概览图",
		"figure/preserved",
		"严格 JSON",
	}
	for _, anchor := range anchors {
		if !strings.Contains(prompt, anchor) {
			t.Fatalf("structure 提示词缺少锚点: %s", anchor)
		}
	}
	// 正文只以元数据出现且截断换行。
	if !strings.Contains(prompt, `1. 第一项`) {
		t.Fatal("structure 提示词应携带输入正文（只读输入）")
	}
}

func TestBuildStructurePromptNoOverview(t *testing.T) {
	prompt := BuildStructurePrompt([]UnitInput{validUnit("ink:r:x")}, false)
	if strings.Contains(prompt, "概览图") {
		t.Fatal("无概览图时不得提及概览图")
	}
}
