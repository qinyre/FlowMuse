package recognition

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"sync"
	"time"
)

// 智能排版 v3 分析器与路由（V3-201A，合并原 201A～B）。
//
// 职责边界：schema/错误码冻结在 smart_layout_v3_types.go（V3-200A）；
// 本文件做 provider 编排 + 跨消息 sanitize（引用/基数/order/typed text
// 回填/preserved）+ 限流与路由。v2 与 v3 通道独立注册、互不影响。
//
// 核心安全性质：provider 超时/失败/恶意/残缺输出只能产生
// 「完整已校验文档」或「稳定结构化错误」，绝不部分信任——
// 所有校验通过后才构造 V3AnalysisDocument。

// V3ErrInternal 是传输层内部错误码（protocol.md：500，不在冻结七码内）。
const V3ErrInternal = "internal"

// V3RequestLimits 是 v3 请求域限额（body/并发/超时）。
type V3RequestLimits struct {
	MaxBodyBytes    int64
	MaxConcurrent   int
	RequestTimeout  time.Duration
	ProviderTimeout time.Duration
}

// DefaultV3RequestLimits 返回默认限额：2MiB body、8 并发、
// 请求 60s、provider 调用 55s。
func DefaultV3RequestLimits() V3RequestLimits {
	return V3RequestLimits{
		MaxBodyBytes:    2 << 20,
		MaxConcurrent:   8,
		RequestTimeout:  60 * time.Second,
		ProviderTimeout: 55 * time.Second,
	}
}

func (l V3RequestLimits) normalized() V3RequestLimits {
	if l.MaxBodyBytes <= 0 {
		l.MaxBodyBytes = 2 << 20
	}
	if l.MaxConcurrent <= 0 {
		l.MaxConcurrent = 8
	}
	if l.RequestTimeout <= 0 {
		l.RequestTimeout = 60 * time.Second
	}
	if l.ProviderTimeout <= 0 || l.ProviderTimeout > l.RequestTimeout {
		l.ProviderTimeout = l.RequestTimeout
	}
	return l
}

// V3ProviderFunc 是上游模型 seam：输入已校验请求，输出原始模型响应字节。
// 真实视觉/OCR provider 后续接入；测试注入确定性 fake。
type V3ProviderFunc func(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error)

// V3AnalysisDocument 是完全校验后的分析产物（绝不部分构造）。
type V3AnalysisDocument struct {
	Response            *SmartLayoutV3Response
	RegionTexts         map[string]string // regionID → 回填的 typed text（请求 exactTexts 拼接）
	PreservedSourceRefs []string          // 未被任何 region 认领的 sourceRef（原位保留，排序）
}

// V3Analyzer 编排 provider 调用与 strict sanitize。
type V3Analyzer struct {
	provider V3ProviderFunc
	limits   V3RequestLimits
	sem      chan struct{}
	mu       sync.Mutex
	inFlight int
}

// NewV3Analyzer 构造分析器；provider 为 nil 时返回 nil（v3 通道关闭）。
func NewV3Analyzer(provider V3ProviderFunc, limits V3RequestLimits) *V3Analyzer {
	if provider == nil {
		return nil
	}
	limits = limits.normalized()
	return &V3Analyzer{
		provider: provider,
		limits:   limits,
		sem:      make(chan struct{}, limits.MaxConcurrent),
	}
}

// InFlight 返回当前并发分析数（限流观测）。
func (a *V3Analyzer) InFlight() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.inFlight
}

func (a *V3Analyzer) acquire(ctx context.Context) *SmartLayoutV3Error {
	select {
	case a.sem <- struct{}{}:
		a.mu.Lock()
		a.inFlight++
		a.mu.Unlock()
		return nil
	case <-ctx.Done():
		return v3err(V3ErrInternal, "", "并发额度等待超时")
	}
}

func (a *V3Analyzer) release() {
	a.mu.Lock()
	a.inFlight--
	a.mu.Unlock()
	<-a.sem
}

// Analyze 执行一次分析：provider → strict decode → 跨消息 sanitize。
// 成功返回完整文档；失败返回稳定结构化错误，文档为 nil。
func (a *V3Analyzer) Analyze(ctx context.Context, req *SmartLayoutV3Request) (*V3AnalysisDocument, *SmartLayoutV3Error) {
	if a == nil || a.provider == nil {
		return nil, v3err(V3ErrInternal, "", "v3 分析器未配置")
	}
	if err := a.acquire(ctx); err != nil {
		return nil, err
	}
	defer a.release()

	providerCtx, cancel := context.WithTimeout(ctx, a.limits.ProviderTimeout)
	defer cancel()
	raw, pErr := a.provider(providerCtx, req)
	if pErr != nil {
		if errors.Is(pErr, context.DeadlineExceeded) {
			return nil, v3err(V3ErrInternal, "", "provider 超时")
		}
		if errors.Is(pErr, context.Canceled) {
			return nil, v3err(V3ErrInternal, "", "客户端取消请求")
		}
		return nil, v3err(V3ErrInternal, "", "provider 失败: %v", pErr)
	}
	// 严格 decode（schema/未知字段/枚举/上限/环/悬空 targetRegion 全在此）。
	response, sErr := ParseSmartLayoutV3Response(raw)
	if sErr != nil {
		return nil, v3err(V3ErrInternal, "provider.output", "模型响应未通过严格校验: %s: %s", sErr.Code, sErr.Message)
	}
	doc, err := sanitizeV3Analysis(req, response)
	if err != nil {
		return nil, err
	}
	return doc, nil
}

// sanitizeV3Analysis 跨消息校验与产物构造：
//  1. 引用：region.sourceIds 必须 ⊆ 请求 sourceRefs；
//  2. 基数：每个 sourceRef 至多属于一个 region（区域不相交）；
//  3. order：readingOrder 必须是 0..n-1 的排列；
//  4. typed text 回填：region 的 text sourceIds 按 sourceIds 顺序拼接；
//  5. preserved：未被认领的 sourceRefs 原位保留。
//
// 任一失败 → 稳定错误；全部通过才构造文档。
func sanitizeV3Analysis(req *SmartLayoutV3Request, resp *SmartLayoutV3Response) (*V3AnalysisDocument, *SmartLayoutV3Error) {
	sourceRefs := map[string]bool{}
	for _, ref := range req.SourceRefs {
		sourceRefs[ref] = true
	}
	exactTexts := map[string]string{}
	for _, text := range req.ExactTexts {
		exactTexts[text.SourceID] = text.Text
	}
	claimed := map[string]string{} // sourceRef → regionID
	for i, region := range resp.Regions {
		for _, sourceID := range region.SourceIDs {
			if !sourceRefs[sourceID] {
				return nil, v3err(V3ErrDanglingReference, regionField(i, "sourceIds"),
					"region 引用了请求不存在的 sourceRef: %s", sourceID)
			}
			if owner, dup := claimed[sourceID]; dup {
				return nil, v3err(V3ErrDuplicateReference, regionField(i, "sourceIds"),
					"sourceRef %s 同时被 %s 与 %s 认领", sourceID, owner, region.ID)
			}
			claimed[sourceID] = region.ID
		}
	}
	seenOrder := map[int]bool{}
	for i, region := range resp.Regions {
		order := *region.ReadingOrder
		if order >= len(resp.Regions) || seenOrder[order] {
			return nil, v3err(V3ErrInvalidRequest, regionField(i, "readingOrder"),
				"readingOrder 必须是 0..%d 的排列", len(resp.Regions)-1)
		}
		seenOrder[order] = true
	}
	regionTexts := map[string]string{}
	for _, region := range resp.Regions {
		var parts []string
		for _, sourceID := range region.SourceIDs {
			if text, ok := exactTexts[sourceID]; ok {
				parts = append(parts, text)
			}
		}
		if len(parts) > 0 {
			regionTexts[region.ID] = joinNonEmpty(parts)
		}
	}
	var preserved []string
	for _, ref := range req.SourceRefs {
		if _, ok := claimed[ref]; !ok {
			preserved = append(preserved, ref)
		}
	}
	sort.Strings(preserved)
	return &V3AnalysisDocument{
		Response:            resp,
		RegionTexts:         regionTexts,
		PreservedSourceRefs: preserved,
	}, nil
}

func regionField(index int, key string) string {
	return fmt.Sprintf("regions[%d].%s", index, key)
}

func joinNonEmpty(parts []string) string {
	result := ""
	for i, part := range parts {
		if part == "" {
			continue
		}
		if i > 0 && result != "" {
			result += "\n"
		}
		result += part
	}
	return result
}

// RegisterSmartLayoutV3 在 mux 上独立注册 v3 分析端点。
// analyzer 为 nil 时不注册（v2 通道不受影响——独立启停）。
func RegisterSmartLayoutV3(mux *http.ServeMux, analyzer *V3Analyzer) {
	if mux == nil || analyzer == nil {
		return
	}
	limits := analyzer.limits
	mux.HandleFunc("/api/ink/smart-layout/analyze/v3", func(w http.ResponseWriter, r *http.Request) {
		handleV3Analyze(w, r, analyzer, limits)
	})
}

func handleV3Analyze(w http.ResponseWriter, r *http.Request, analyzer *V3Analyzer, limits V3RequestLimits) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeV3Error(w, http.StatusMethodNotAllowed, v3err(V3ErrInvalidRequest, "", "method not allowed"))
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), limits.RequestTimeout)
	defer cancel()
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, limits.MaxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeV3Error(w, http.StatusRequestEntityTooLarge,
				v3err(V3ErrLimitExceeded, "", "请求体超过上限 %d 字节", limits.MaxBodyBytes))
			return
		}
		writeV3Error(w, http.StatusBadRequest, v3err(V3ErrInvalidRequest, "", "读取请求体失败"))
		return
	}
	request, pErr := ParseSmartLayoutV3Request(body)
	if pErr != nil {
		writeV3Error(w, http.StatusBadRequest, pErr)
		return
	}
	document, aErr := analyzer.Analyze(ctx, request)
	if aErr != nil {
		if aErr.Code == V3ErrInternal {
			writeV3Error(w, http.StatusBadGateway, aErr)
			return
		}
		writeV3Error(w, http.StatusBadRequest, aErr)
		return
	}
	writeJSON(w, http.StatusOK, document.Response)
}

func writeV3Error(w http.ResponseWriter, status int, v3Err *SmartLayoutV3Error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]*SmartLayoutV3Error{"error": v3Err})
}
