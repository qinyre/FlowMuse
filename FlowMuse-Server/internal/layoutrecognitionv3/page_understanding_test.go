package layoutrecognitionv3

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestPageUnderstandingProtocolAndPrompt(t *testing.T) {
	text := strings.Repeat("正文不得截断。", 30) + "尾部说明红色图片。"
	request, err := DecodeRecognitionRequest([]byte(structureRequestBody()))
	if err != nil {
		t.Fatal(err)
	}
	request.Units[1].Text = &text
	request.OverviewPngBase64 = tinyPngBase64
	request.IncludeFigureTextLinks = true
	model := `{"readingOrder":["u-title","u-i1","u-i2","u-fig","u-cap"],
	"roles":[{"unitId":"u-title","role":"title"},{"unitId":"u-i1","role":"body"},{"unitId":"u-i2","role":"body"},{"unitId":"u-cap","role":"caption"}],
	"listGroups":[],"captions":[{"captionUnitId":"u-cap","targetUnitId":"u-fig"}],"warnings":[],
	"figureTextLinks":[{"textUnitId":"u-i1","figureUnitId":"u-fig","confidence":0.93}]}`
	for _, enabled := range []bool{true, false} {
		request.IncludeFigureTextLinks = enabled
		body, err := json.Marshal(request)
		if err != nil {
			t.Fatal(err)
		}
		provider := &fakeProvider{responses: []string{model}}
		rec, parsed := post(t, NewRecognitionHandler(provider, DefaultLimits()), string(body))
		if rec.Code != http.StatusOK {
			t.Fatalf("status=%d", rec.Code)
		}
		if provider.callCount() != 1 || len(provider.lastReq.Images) != 1 {
			t.Fatal("整页只需一次带图结构请求")
		}
		if !strings.Contains(provider.lastReq.PromptText, text) {
			t.Fatal("全文尤其80字后的尾部必须参与结构判断")
		}
		if !strings.Contains(provider.lastReq.PromptText, "[4] unitId=u-fig") {
			t.Fatal("概览编号必须对应units顺序")
		}
		_, hasLinks := parsed["figureTextLinks"]
		if hasLinks != enabled {
			t.Fatal("新字段不得发给未协商的旧客户端")
		}
		if enabled && !strings.Contains(provider.lastReq.PromptText, "不能把每段文字强行配给最近图片") {
			t.Fatal("必须要求实际图像语义证据")
		}
	}

	request.IncludeFigureTextLinks = true
	body, _ := json.Marshal(request)
	for name, badModel := range map[string]string{
		"missing target":     strings.Replace(model, `"figureUnitId":"u-fig"`, `"figureUnitId":"missing"`, 1),
		"text target":        strings.Replace(model, `"figureUnitId":"u-fig"`, `"figureUnitId":"u-i2"`, 1),
		"title source":       strings.Replace(model, `"textUnitId":"u-i1"`, `"textUnitId":"u-title"`, 1),
		"caption source":     strings.Replace(model, `"textUnitId":"u-i1"`, `"textUnitId":"u-cap"`, 1),
		"bad confidence":     strings.Replace(model, `"confidence":0.93`, `"confidence":1.2`, 1),
		"missing confidence": strings.Replace(model, `,"confidence":0.93`, ``, 1),
		"text injection":     strings.Replace(model, `"confidence":0.93`, `"confidence":0.93,"text":"禁止正文"`, 1),
		"duplicate":          strings.Replace(model, `"confidence":0.93}`, `"confidence":0.93},{"textUnitId":"u-i1","figureUnitId":"u-fig","confidence":0.9}`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			rec, parsed := post(t, NewRecognitionHandler(&fakeProvider{responses: []string{badModel}}, DefaultLimits()), string(body))
			if rec.Code != http.StatusBadGateway || errorOf(t, parsed)["code"] != CodeInvalidProviderResp {
				t.Fatal("无效关系必须拒绝")
			}
		})
	}
	request.OverviewPngBase64 = ""
	if ValidateRequest(request, DefaultLimits()) == nil {
		t.Fatal("不得无图请求图文匹配")
	}
}
