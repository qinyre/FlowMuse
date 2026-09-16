package layoutrecognitionv3

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/png"
	"testing"
)

// tinyPngBase64 是真实可解码的 1×1 PNG（fixtures 同源字节）。
const tinyPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

func TestDefaultLimits(t *testing.T) {
	limits := DefaultLimits()
	if limits.MaxBodyBytes != 16<<20 {
		t.Fatalf("16MiB body 上限: %d", limits.MaxBodyBytes)
	}
	if limits.MaxRegionsPerBatch != 8 || limits.MaxUnits != 128 {
		t.Fatalf("批/units 上限: %d/%d", limits.MaxRegionsPerBatch, limits.MaxUnits)
	}
	if limits.MaxImageBase64Bytes != 3<<20 {
		t.Fatalf("单图 base64 上限: %d", limits.MaxImageBase64Bytes)
	}
	if limits.MaxImagePixels != 2*1024*1024 || limits.MaxImageEdge != 2048 {
		t.Fatalf("解码上限: %d/%d", limits.MaxImagePixels, limits.MaxImageEdge)
	}
	if limits.MaxTextRunes != 2000 {
		t.Fatalf("正文上限: %d", limits.MaxTextRunes)
	}
	if limits.MaxInFlight != 4 {
		t.Fatalf("并发上限: %d", limits.MaxInFlight)
	}
}

func TestImageDecodeFits(t *testing.T) {
	limits := DefaultLimits()
	if !imageDecodeFits(tinyPngBase64, limits) {
		t.Fatal("1×1 真实 PNG 必须通过解码尺寸校验")
	}
	if imageDecodeFits("!!!not-base64!!!", limits) {
		t.Fatal("非法 base64 必须拒绝")
	}
	if imageDecodeFits(base64.StdEncoding.EncodeToString([]byte("not a png")), limits) {
		t.Fatal("非 PNG 字节必须拒绝")
	}
	// 真实 2049×1 PNG：长边超限。
	if imageDecodeFits(pngOf(t, 2049, 1), limits) {
		t.Fatal("长边 2049 必须拒绝")
	}
	// 真实 2048×1024 PNG：恰在限内（2,097,152 px = 2MP）。
	if !imageDecodeFits(pngOf(t, 2048, 1024), limits) {
		t.Fatal("2048×1024（恰 2MP）必须通过")
	}
	// 真实 1500×1500 PNG：2.25MP 超像素上限。
	if imageDecodeFits(pngOf(t, 1500, 1500), limits) {
		t.Fatal("2.25MP 必须拒绝")
	}
}

func TestBodySizeLimit(t *testing.T) {
	// 16MiB 上限由 handler 的 MaxBytesReader 执行（见 handler_stage_test
	// 的 body 上限用例）；此处校验 normalize 行为。
	limits := Limits{MaxBodyBytes: -1}.normalized()
	if limits.MaxBodyBytes != 16<<20 {
		t.Fatalf("非正上限必须回落默认: %d", limits.MaxBodyBytes)
	}
	zero := Limits{}.normalized()
	if zero.MaxInFlight != 4 || zero.MaxRegionsPerBatch != 8 {
		t.Fatal("零值必须全部回落默认")
	}
}

func pngOf(t *testing.T, width, height int) string {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	img.Set(0, 0, color.RGBA{R: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}
