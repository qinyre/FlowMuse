// png_decoder_registration_test.go：守护 layoutrecognitionv3 的 PNG
// 解码器注册。该包的 imageDecodeFits 依赖 image.DecodeConfig，而其
// 测试文件（limits_test.go 等）导入 image/png 会在测试二进制里全局
// 注册解码器，掩盖"生产文件漏注册"的缺陷——2026-09-16 平板真实请求
// 全部被误判"解码尺寸超上限"400 即由此而来。本测试必须放在 cmd
// 包：它只链接生产文件，解码器注册唯一来源就是 validate.go 的
// `_ "image/png"` 空导入；PNG 字面量硬编码（不得在本文件导入
// image/png 生成，否则同样会掩盖缺陷）。
package main

import (
	"testing"

	"flowmuse/server/internal/layoutrecognitionv3"
)

// 8×8 白底 PNG 的 base64（PIL 生成，独立可复现）。
const tinyPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAFUlEQVR4nGP8//8/AzbAhFV00EoAAFbUAw037MyjAAAAAElFTkSuQmCC"

func TestPngDecoderRegisteredForValidation(t *testing.T) {
	request := &layoutrecognitionv3.RecognitionRequest{
		SchemaVersion:      layoutrecognitionv3.SchemaVersion,
		Stage:              layoutrecognitionv3.StageRead,
		OperationID:        "op-1",
		RequestID:          "req-1",
		PageID:             "page-1",
		SceneRevision:      layoutrecognitionv3.SceneRevision{Fingerprint: "fp-1"},
		ContentFingerprint: "fp-1",
		Generation:         1,
		Regions: []layoutrecognitionv3.RegionImageInput{{
			RegionID:       "r-1",
			ImagePngBase64: tinyPngBase64,
			ImageScale:     1,
		}},
	}
	if vErr := layoutrecognitionv3.ValidateRequest(request, layoutrecognitionv3.DefaultLimits()); vErr != nil {
		t.Fatalf("合法小 PNG 不应被校验拒绝: code=%s message=%s", vErr.Code, vErr.Message)
	}
}
