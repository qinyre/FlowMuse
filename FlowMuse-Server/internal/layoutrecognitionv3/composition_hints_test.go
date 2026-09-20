package layoutrecognitionv3

import (
	"encoding/json"
	"math"
	"net/http"
	"strings"
	"testing"
)

func compositionRequest(t *testing.T) *RecognitionRequest {
	t.Helper()
	r, err := DecodeRecognitionRequest([]byte(structureRequestBody()))
	if err != nil {
		t.Fatal(err)
	}
	r.IncludeCompositionHints = true
	r.OverviewPngBase64 = tinyPngBase64
	r.Units[1].Kind = "ink"
	text := "完整\n说明"
	r.Units[1].Text = &text
	return r
}

const compositionModel = `{"readingOrder":["u-title","u-i1","u-i2","u-fig","u-cap"],"roles":[{"unitId":"u-title","role":"title"},{"unitId":"u-i1","role":"body"},{"unitId":"u-i2","role":"body"},{"unitId":"u-cap","role":"caption"}],"listGroups":[],"captions":[{"captionUnitId":"u-cap","targetUnitId":"u-fig"}],"warnings":[],"compositionHints":{"version":"composition-hints/1","pageIntent":"reading","sections":[{"sectionId":"s1","headingUnitId":"u-title","memberUnitIds":["u-i1","u-i2","u-fig","u-cap"]}],"mediaGroups":[{"groupId":"m1","figureUnitIds":["u-fig"],"textUnitIds":["u-i1","u-i2"],"confidence":0.95}],"softLineBreaks":[{"unitId":"u-i1","newlineIndexes":[0],"confidence":0.95}]}}`

func TestCompositionNegotiationAndStrictBoundary(t *testing.T) {
	r := compositionRequest(t)
	for _, enabled := range []bool{true, false} {
		r.IncludeCompositionHints = enabled
		body, _ := json.Marshal(r)
		p := &fakeProvider{responses: []string{compositionModel}}
		rec, parsed := post(t, NewRecognitionHandler(p, DefaultLimits()), string(body))
		if rec.Code != http.StatusOK {
			t.Fatalf("status=%d", rec.Code)
		}
		_, hasHints := parsed["compositionHints"]
		if hasHints != enabled || parsed["figureTextLinks"] != nil || p.callCount() != 1 {
			t.Fatal("协商键集或调用数错误")
		}
		if enabled && (!strings.Contains(p.lastReq.PromptText, "softLineBreaks") || !strings.Contains(p.lastReq.PromptText, "多图共用")) {
			t.Fatal("未接入同轮提示")
		}
	}
	r.IncludeCompositionHints = true
	body, _ := json.Marshal(r)
	for name, raw := range map[string]string{
		"null hints":        strings.Replace(compositionModel, `"sections":[`, `"unexpected":null,"sections":[`, 1),
		"null array":        strings.Replace(compositionModel, `"warnings":[]`, `"warnings":null`, 1),
		"unknown field":     strings.Replace(compositionModel, `"pageIntent":"reading"`, `"pageIntent":"reading","body":"no"`, 1),
		"null text":         strings.Replace(compositionModel, `"role":"body"`, `"role":"body","text":null`, 1),
		"old authority":     strings.Replace(compositionModel, `"warnings":[]`, `"warnings":[],"figureTextLinks":[]`, 1),
		"duplicate member":  strings.Replace(compositionModel, `"textUnitIds":["u-i1","u-i2"]`, `"textUnitIds":["u-i1","u-i1"]`, 1),
		"interleaved":       strings.Replace(compositionModel, `"textUnitIds":["u-i1","u-i2"]`, `"textUnitIds":["u-i1"]`, 1),
		"caption as body":   strings.Replace(compositionModel, `"textUnitIds":["u-i1","u-i2"]`, `"textUnitIds":["u-cap"]`, 1),
		"missing unit":      strings.Replace(compositionModel, `"figureUnitIds":["u-fig"]`, `"figureUnitIds":["missing"]`, 1),
		"bad confidence":    strings.Replace(compositionModel, `"confidence":0.95`, `"confidence":1.01`, 1),
		"null confidence":   strings.Replace(compositionModel, `"confidence":0.95`, `"confidence":null`, 1),
		"section order":     strings.Replace(compositionModel, `"memberUnitIds":["u-i1","u-i2","u-fig","u-cap"]`, `"memberUnitIds":["u-i2","u-i1","u-fig","u-cap"]`, 1),
		"newline index":     strings.Replace(compositionModel, `"newlineIndexes":[0]`, `"newlineIndexes":[1]`, 1),
		"newline duplicate": strings.Replace(compositionModel, `"newlineIndexes":[0]`, `"newlineIndexes":[0,0]`, 1),
		"trailing":          compositionModel + " garbage",
	} {
		t.Run(name, func(t *testing.T) {
			rec, parsed := post(t, NewRecognitionHandler(&fakeProvider{responses: []string{raw}}, DefaultLimits()), string(body))
			if rec.Code != http.StatusBadGateway || errorOf(t, parsed)["code"] != CodeInvalidProviderResp {
				t.Fatal("非法结构未拒绝")
			}
		})
	}
	r.IncludeFigureTextLinks = true
	if ValidateRequest(r, DefaultLimits()) == nil {
		t.Fatal("互斥能力未拒绝")
	}
	if _, err := DecodeRecognitionRequest([]byte(strings.Replace(string(body), `"includeCompositionHints":true`, `"includeCompositionHints":null`, 1))); err == nil {
		t.Fatal("null能力未拒绝")
	}
}

func TestCompositionSharedTextAndSoftBreakSafety(t *testing.T) {
	r := compositionRequest(t)
	var m ModelStructureResult
	if err := decodeStrict([]byte(compositionModel), &m); err != nil {
		t.Fatal(err)
	}
	// 一段正文共两张图，输出中没有第二份正文。
	r.Units = append(r.Units, UnitInput{UnitID: "f2", Kind: "figure"})
	m.ReadingOrder = append(m.ReadingOrder, "f2")
	m.CompositionHints.Sections[0].MemberUnitIDs = append(m.CompositionHints.Sections[0].MemberUnitIDs, "f2")
	m.CompositionHints.MediaGroups[0].FigureUnitIDs = append(m.CompositionHints.MediaGroups[0].FigureUnitIDs, "f2")
	if err := validateCompositionHints(r, &m); err != nil {
		t.Fatal(err)
	}
	for _, value := range []float64{math.NaN(), math.Inf(1), -0.1} {
		m.CompositionHints.MediaGroups[0].Confidence = &value
		if validateCompositionHints(r, &m) == nil {
			t.Fatal("非法浮点未拒绝")
		}
	}
	m.CompositionHints.MediaGroups[0].Confidence = float64Ptr(0.95)
	r.OverviewPngBase64 = ""
	if validateCompositionHints(r, &m) == nil {
		t.Fatal("无图不可配图文")
	}
	m.CompositionHints.MediaGroups = []MediaGroupHint{}
	if err := validateCompositionHints(r, &m); err != nil {
		t.Fatal("无图文字结构应可用")
	}
	r.Units[1].Kind = "typed"
	if validateCompositionHints(r, &m) == nil {
		t.Fatal("原生硬换行未保护")
	}
	r.Units[1].Kind = "ink"
	text := "第一段\n\n第二段"
	r.Units[1].Text = &text
	if validateCompositionHints(r, &m) == nil {
		t.Fatal("空行段落未保护")
	}
}
