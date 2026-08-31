package recognition

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"unicode/utf8"
)

// 高清 crop 复核与冲突保留合并（V3-202A）。
//
// 关键不变量：
//  - crop 只服务手写区域（OCR/formula）；typed exactText 区域被 crop
//    触碰 → 记冲突并丢弃内容，绝不改写；
//  - overview 与 crop 的分歧（role 不一致等）记录为冲突进入文档，
//    不静默择一（保守保留 overview 结论）；
//  - 低置信区域必须升级 crop；升级失败 → 冲突留档，区域维持总览结论。

// V3CropProviderFunc 是 crop 级 provider seam：针对单个区域的
// 高清复核，返回原始 JSON。
type V3CropProviderFunc func(ctx context.Context, req *SmartLayoutV3Request, regionID string) ([]byte, error)

// V3CropAnalyzer 编排 crop 复核。
type V3CropAnalyzer struct {
	provider V3CropProviderFunc
}

// NewV3CropAnalyzer 构造 crop 分析器（provider nil → nil，通道关闭）。
func NewV3CropAnalyzer(provider V3CropProviderFunc) *V3CropAnalyzer {
	if provider == nil {
		return nil
	}
	return &V3CropAnalyzer{provider: provider}
}

// V3CropResult 是一条已校验的 crop 复核结论。
type V3CropResult struct {
	RegionID   string
	Kind       string // "ocr" | "formula"
	Content    string
	Role       string // crop 侧 role 结论（可与总览不同 → 冲突）
	Confidence float64
}

var v3CropKinds = map[string]bool{"ocr": true, "formula": true}

// V3CropError 记录一个区域的 crop 失败（升级未完成）。
type V3CropError struct {
	RegionID string
	Err      *SmartLayoutV3Error
}

// AnalyzeCrops 对 escalated 区域逐一复核（按输入顺序，无并发——
// 区域数 ≤128 且 provider 侧已有全局限流）。
func (a *V3CropAnalyzer) AnalyzeCrops(
	ctx context.Context,
	req *SmartLayoutV3Request,
	regionIDs []string,
) ([]V3CropResult, []V3CropError) {
	if a == nil || a.provider == nil {
		errs := make([]V3CropError, 0, len(regionIDs))
		for _, id := range regionIDs {
			errs = append(errs, V3CropError{
				RegionID: id,
				Err:      v3err(V3ErrInternal, "", "crop 分析器未配置"),
			})
		}
		return nil, errs
	}
	var results []V3CropResult
	var failures []V3CropError
	for _, regionID := range regionIDs {
		raw, pErr := a.provider(ctx, req, regionID)
		if pErr != nil {
			failures = append(failures, V3CropError{RegionID: regionID, Err: cropProviderError(pErr)})
			continue
		}
		result, v3Err := parseV3CropResult(raw, regionID)
		if v3Err != nil {
			failures = append(failures, V3CropError{RegionID: regionID, Err: v3Err})
			continue
		}
		results = append(results, *result)
	}
	return results, failures
}

func cropProviderError(err error) *SmartLayoutV3Error {
	if errors.Is(err, context.DeadlineExceeded) {
		return v3err(V3ErrInternal, "", "crop provider 超时")
	}
	if errors.Is(err, context.Canceled) {
		return v3err(V3ErrInternal, "", "客户端取消请求")
	}
	return v3err(V3ErrInternal, "", "crop provider 失败: %v", err)
}

// parseV3CropResult 严格解析 crop 输出并核对回显 regionId。
func parseV3CropResult(raw []byte, requestedRegionID string) (*V3CropResult, *SmartLayoutV3Error) {
	var crop struct {
		RegionID   string   `json:"regionId"`
		Kind       string   `json:"kind"`
		Content    string   `json:"content"`
		Role       string   `json:"role"`
		Confidence *float64 `json:"confidence"`
	}
	if err := decodeStrict(raw, &crop); err != nil {
		return nil, v3err(V3ErrInternal, "crop.output", "crop 输出未通过严格校验: %s: %s", err.Code, err.Message)
	}
	if crop.RegionID != requestedRegionID {
		return nil, v3err(V3ErrInternal, "crop.output.regionId",
			"crop 回显 regionId 与请求不符: %s != %s", crop.RegionID, requestedRegionID)
	}
	if !v3CropKinds[crop.Kind] {
		return nil, v3err(V3ErrUnknownEnum, "crop.output.kind", "未知 crop kind: %s", crop.Kind)
	}
	if !v3Roles[crop.Role] {
		return nil, v3err(V3ErrUnknownEnum, "crop.output.role", "未知 crop role: %s", crop.Role)
	}
	if crop.Confidence == nil || *crop.Confidence < 0 || *crop.Confidence > 1 {
		return nil, v3err(V3ErrInvalidRequest, "crop.output.confidence", "必须在 [0,1]")
	}
	if utf8.RuneCountInString(crop.Content) > 10000 {
		return nil, v3err(V3ErrLimitExceeded, "crop.output.content", "content 超过 10000 字符")
	}
	return &V3CropResult{
		RegionID:   crop.RegionID,
		Kind:       crop.Kind,
		Content:    crop.Content,
		Role:       crop.Role,
		Confidence: *crop.Confidence,
	}, nil
}

// V3AnalysisConflict 是 overview/crop 分歧或升级失败的留档。
type V3AnalysisConflict struct {
	RegionID string
	Kind     string // role-disagreement | typed-text-overwrite-attempt | crop-failed
	Overview string
	Crop     string
}

// V3AnalysisMerger 把总览结论与 crop 复核合并为最终文档。
// 冲突进入文档（Conflicts），绝不静默择一。
type V3AnalysisMerger struct{}

// NewV3AnalysisMerger 构造合并器。
func NewV3AnalysisMerger() *V3AnalysisMerger { return &V3AnalysisMerger{} }

// V3FinalDocument 是总览+crop 的完整产物（含冲突留档与 crop 内容）。
type V3FinalDocument struct {
	Analysis  *V3AnalysisDocument
	Conflicts []V3AnalysisConflict

	// CropContents 保存手写区域的 crop 复核内容（regionID → content）。
	CropContents map[string]string
}

// Merge 执行合并。overview 先过跨消息 sanitize（201A sanitizeV3Analysis），
// crop 结论按以下规则应用：
//  1. typed text 区域被 crop 触碰 → 冲突 typed-text-overwrite-attempt，
//     内容丢弃；
//  2. crop role 与总览 role 不同 → 冲突 role-disagreement，保守保留
//     总览 role（不择一）；
//  3. 其余手写区域 → 记录 crop 内容与 kind（role 不变）。
func (m *V3AnalysisMerger) Merge(
	req *SmartLayoutV3Request,
	overview *SmartLayoutV3Response,
	crops []V3CropResult,
	cropFailures []V3CropError,
) (*V3FinalDocument, *SmartLayoutV3Error) {
	base, err := sanitizeV3Analysis(req, overview)
	if err != nil {
		return nil, err
	}
	// typed 区域 = 回填了 exactText 的区域（sanitize 已判定）。
	typedRegions := map[string]bool{}
	for regionID := range base.RegionTexts {
		typedRegions[regionID] = true
	}
	regionRole := map[string]string{}
	for _, region := range overview.Regions {
		regionRole[region.ID] = region.Role
	}
	cropByID := map[string]V3CropResult{}
	for _, crop := range crops {
		cropByID[crop.RegionID] = crop
	}
	var conflicts []V3AnalysisConflict
	cropContents := map[string]string{}
	for _, region := range overview.Regions {
		crop, ok := cropByID[region.ID]
		if !ok {
			continue
		}
		if typedRegions[region.ID] {
			conflicts = append(conflicts, V3AnalysisConflict{
				RegionID: region.ID,
				Kind:     "typed-text-overwrite-attempt",
				Overview: "typed exactText（不可改写）",
				Crop:     fmt.Sprintf("%s content=%q", crop.Kind, truncateForLog(crop.Content, 40)),
			})
			continue
		}
		if crop.Role != regionRole[region.ID] {
			conflicts = append(conflicts, V3AnalysisConflict{
				RegionID: region.ID,
				Kind:     "role-disagreement",
				Overview: fmt.Sprintf("role=%s conf=%.2f", region.Role, *region.Confidence),
				Crop:     fmt.Sprintf("role=%s conf=%.2f", crop.Role, crop.Confidence),
			})
		}
		cropContents[region.ID] = crop.Content
	}
	for _, failure := range cropFailures {
		conflicts = append(conflicts, V3AnalysisConflict{
			RegionID: failure.RegionID,
			Kind:     "crop-failed",
			Overview: "总览结论维持",
			Crop:     failure.Err.Error(),
		})
	}
	sort.SliceStable(conflicts, func(i, j int) bool {
		return conflicts[i].RegionID < conflicts[j].RegionID
	})
	return &V3FinalDocument{
		Analysis:     base,
		Conflicts:    conflicts,
		CropContents: cropContents,
	}, nil
}

// RunV3Analysis 是完整链：总览 → 低置信分诊 → crop 复核 → 合并。
func RunV3Analysis(
	ctx context.Context,
	req *SmartLayoutV3Request,
	overview *V3OverviewAnalyzer,
	crop *V3CropAnalyzer,
) (*V3FinalDocument, *SmartLayoutV3Error) {
	outcome, err := overview.Analyze(ctx, req)
	if err != nil {
		return nil, err
	}
	cropResults, cropFailures := []V3CropResult{}, []V3CropError{}
	if len(outcome.LowConfidenceRegionIDs) > 0 {
		if crop == nil {
			for _, id := range outcome.LowConfidenceRegionIDs {
				cropFailures = append(cropFailures, V3CropError{
					RegionID: id,
					Err:      v3err(V3ErrInternal, "", "crop 分析器未配置"),
				})
			}
		} else {
			cropResults, cropFailures = crop.AnalyzeCrops(ctx, req, outcome.LowConfidenceRegionIDs)
		}
	}
	return NewV3AnalysisMerger().Merge(req, outcome.Response, cropResults, cropFailures)
}

func truncateForLog(text string, max int) string {
	runes := []rune(text)
	if len(runes) <= max {
		return strings.TrimSpace(text)
	}
	return strings.TrimSpace(string(runes[:max])) + "…"
}
