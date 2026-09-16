// Package layoutrecognitionv3 实现独立识别链路端点
// POST /api/ink/smart-layout/recognize/v3（spec §4）。
//
// 本文件：请求上限（limits.go）。
package layoutrecognitionv3

import (
	"image"
	"time"
)

// Limits 是 recognize/v3 请求域限额（spec §4 limits.go 行）。
type Limits struct {
	// 编码后完整请求 JSON（UTF-8）的字节上限。
	MaxBodyBytes int64
	// 单批区域数上限（stage=read/verify）。
	MaxRegionsPerBatch int
	// 结构请求 unit 数上限。
	MaxUnits int
	// 单图 base64（编码后）字节上限。
	MaxImageBase64Bytes int64
	// 解码后图像尺寸独立安全上限：总像素与长边。
	MaxImagePixels int64
	MaxImageEdge   int
	// 正文（runes）上限。
	MaxTextRunes int
	// in-flight 信号量容量；满则 429 busy。
	MaxInFlight int
	// 服务端单次 provider 超时（FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS，
	// 整数秒；客户端 §6.2 的 45s/剩余时限约束不因此放宽）。
	ProviderTimeout time.Duration
}

// DefaultLimits 返回默认限额：16MiB body、批 8 区域、128 units、
// 单图 base64 3MiB、解码 ≤2MP/长边 2048、正文 2000 runes、并发 4。
func DefaultLimits() Limits {
	return Limits{
		MaxBodyBytes:        16 << 20,
		MaxRegionsPerBatch:  8,
		MaxUnits:            128,
		MaxImageBase64Bytes: 3 << 20,
		MaxImagePixels:      2 * 1024 * 1024,
		MaxImageEdge:        2048,
		MaxTextRunes:        2000,
		MaxInFlight:         4,
		ProviderTimeout:     60 * time.Second,
	}
}

func (l Limits) normalized() Limits {
	if l.MaxBodyBytes <= 0 {
		l.MaxBodyBytes = 16 << 20
	}
	if l.MaxRegionsPerBatch <= 0 {
		l.MaxRegionsPerBatch = 8
	}
	if l.MaxUnits <= 0 {
		l.MaxUnits = 128
	}
	if l.MaxImageBase64Bytes <= 0 {
		l.MaxImageBase64Bytes = 3 << 20
	}
	if l.MaxImagePixels <= 0 {
		l.MaxImagePixels = 2 * 1024 * 1024
	}
	if l.MaxImageEdge <= 0 {
		l.MaxImageEdge = 2048
	}
	if l.MaxTextRunes <= 0 {
		l.MaxTextRunes = 2000
	}
	if l.MaxInFlight <= 0 {
		l.MaxInFlight = 4
	}
	if l.ProviderTimeout <= 0 {
		l.ProviderTimeout = 60 * time.Second
	}
	return l
}

// imageFitsLimits 校验解码配置（尺寸）：总像素 ≤2MP 且长边 ≤2048。
// 这是独立于 base64 体积的另一层安全上限（spec §3.2）。
func (l Limits) imageFitsLimits(config image.Config) bool {
	if config.Width <= 0 || config.Height <= 0 {
		return false
	}
	edge := config.Width
	if config.Height > edge {
		edge = config.Height
	}
	pixels := int64(config.Width) * int64(config.Height)
	return edge <= l.MaxImageEdge && pixels <= l.MaxImagePixels
}
