package recognition

import (
	"context"
	"errors"
)

// 总览级分析（V3-202A）：只产 role/order/relation/evidence——
// 总览不做 OCR/formula 内容；低置信区域触发高清 crop 复核。
// typed exactText 永不被模型改写：总览输出 schema 无 text 字段。

// V3OverviewAnalyzer 编排总览 provider 调用与低置信分诊。
type V3OverviewAnalyzer struct {
	provider        V3ProviderFunc
	confidenceFloor float64
}

// DefaultV3ConfidenceFloor 是触发 crop 复核的置信下限。
const DefaultV3ConfidenceFloor = 0.6

// NewV3OverviewAnalyzer 构造总览分析器；floor 收敛到 [0,1]。
func NewV3OverviewAnalyzer(provider V3ProviderFunc, confidenceFloor float64) *V3OverviewAnalyzer {
	if provider == nil {
		return nil
	}
	if confidenceFloor < 0 || confidenceFloor > 1 {
		confidenceFloor = DefaultV3ConfidenceFloor
	}
	return &V3OverviewAnalyzer{provider: provider, confidenceFloor: confidenceFloor}
}

// ConfidenceFloor 返回生效的置信下限。
func (a *V3OverviewAnalyzer) ConfidenceFloor() float64 {
	if a == nil {
		return DefaultV3ConfidenceFloor
	}
	return a.confidenceFloor
}

// V3OverviewOutcome 是总览分析产物：已严格校验的响应 +
// 需要升级 crop 复核的低置信区域 id（按 region 声明序）。
type V3OverviewOutcome struct {
	Response               *SmartLayoutV3Response
	LowConfidenceRegionIDs []string
}

// Analyze 调用总览 provider 并做低置信分诊。
// provider 超时/失败/残缺输出 → 稳定错误（沿用 201A 映射）。
func (a *V3OverviewAnalyzer) Analyze(ctx context.Context, req *SmartLayoutV3Request) (*V3OverviewOutcome, *SmartLayoutV3Error) {
	if a == nil || a.provider == nil {
		return nil, v3err(V3ErrInternal, "", "总览分析器未配置")
	}
	raw, pErr := a.provider(ctx, req)
	if pErr != nil {
		if errors.Is(pErr, context.DeadlineExceeded) {
			return nil, v3err(V3ErrInternal, "", "provider 超时")
		}
		if errors.Is(pErr, context.Canceled) {
			return nil, v3err(V3ErrInternal, "", "客户端取消请求")
		}
		return nil, v3err(V3ErrInternal, "", "provider 失败: %v", pErr)
	}
	response, sErr := ParseSmartLayoutV3Response(raw)
	if sErr != nil {
		return nil, v3err(V3ErrInternal, "provider.output",
			"总览输出未通过严格校验: %s: %s", sErr.Code, sErr.Message)
	}
	var lowConfidence []string
	for _, region := range response.Regions {
		if *region.Confidence < a.confidenceFloor {
			lowConfidence = append(lowConfidence, region.ID)
		}
	}
	return &V3OverviewOutcome{Response: response, LowConfidenceRegionIDs: lowConfidence}, nil
}
