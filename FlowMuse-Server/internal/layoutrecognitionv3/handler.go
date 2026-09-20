// handler.go：recognize/v3 路由与编排（spec §4）。stage 分发 → 入站校验
// → 组提示词 → provider 调用（ctx 取消透传）→ 解析模型输出（容忍一次
// 围栏剥离；解析/结构校验失败=invalidProviderResponse，不重试）→
// sanitize → 响应。
package layoutrecognitionv3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// RecognitionHandler 是 recognize/v3 端点处理器。
type RecognitionHandler struct {
	provider RecognitionProvider
	limits   Limits
	sem      chan struct{}
	mu       sync.Mutex
	inFlight int
}

// NewRecognitionHandler 构造处理器；provider 为 nil 时仍构造
// （unconfigured → 503），便于路由注册形态与旧包一致。
func NewRecognitionHandler(provider RecognitionProvider, limits Limits) *RecognitionHandler {
	return &RecognitionHandler{
		provider: provider,
		limits:   limits.normalized(),
		sem:      make(chan struct{}, limits.normalized().MaxInFlight),
	}
}

// InFlight 返回当前并发数（限流观测）。
func (h *RecognitionHandler) InFlight() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.inFlight
}

// RegisterRecognitionV3 在 mux 上注册 /api/ink/smart-layout/recognize/v3。
// handler 为 nil 时不注册（旧路由不受影响）。
func RegisterRecognitionV3(mux *http.ServeMux, handler *RecognitionHandler) {
	if mux == nil || handler == nil {
		return
	}
	mux.HandleFunc(EndpointPath, func(w http.ResponseWriter, r *http.Request) {
		handler.serveHTTP(w, r)
	})
}

func (h *RecognitionHandler) serveHTTP(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeRecognitionError(w, http.StatusMethodNotAllowed,
			wireErr(CodeInvalidSchema, "method not allowed"))
		return
	}
	if h.provider == nil {
		writeRecognitionError(w, http.StatusServiceUnavailable,
			wireErr(CodeUnconfigured, "识别链路未配置（FLOWMUSE_LAYOUT_V3_*）"))
		return
	}
	// in-flight 信号量闸（容量 4）；满则 429 busy（retryable）。
	select {
	case h.sem <- struct{}{}:
		h.mu.Lock()
		h.inFlight++
		h.mu.Unlock()
		defer h.release()
	default:
		writeRecognitionError(w, http.StatusTooManyRequests,
			wireErr(CodeBusy, "识别并发已满"))
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, h.limits.MaxBodyBytes))
	if err != nil {
		writeRecognitionError(w, http.StatusBadRequest,
			wireErr(CodeLimitExceeded, fmt.Sprintf("请求体读取失败或超过上限 %d 字节", h.limits.MaxBodyBytes)))
		return
	}
	request, dErr := DecodeRecognitionRequest(body)
	if dErr != nil {
		writeRecognitionError(w, http.StatusBadRequest,
			wireErr(CodeInvalidSchema, "请求解析失败: "+dErr.Error()))
		return
	}
	if vErr := ValidateRequest(request, h.limits); vErr != nil {
		writeRecognitionError(w, http.StatusBadRequest, vErr)
		return
	}

	prepared := time.Since(started)
	recognitionStarted := time.Now()
	response, pErr := h.dispatch(r, request)
	// 只记阶段和规模，不打印请求正文、图片或模型原文。
	log.Printf("[recognition-v3] stage=%s regions=%d units=%d request_bytes=%d prepare_ms=%d recognition_ms=%d ok=%t",
		request.Stage, len(request.Regions), len(request.Units), len(body),
		prepared.Milliseconds(), time.Since(recognitionStarted).Milliseconds(), pErr == nil)
	if pErr != nil {
		status := http.StatusBadGateway
		switch pErr.Code {
		case CodeProviderTimeout:
			status = http.StatusGatewayTimeout
		case CodeInvalidProviderResp:
			status = http.StatusBadGateway
		case CodeInternal:
			status = http.StatusInternalServerError
		}
		writeRecognitionError(w, status, pErr)
		return
	}
	writeRecognitionJSON(w, http.StatusOK, response)
}

func (h *RecognitionHandler) release() {
	h.mu.Lock()
	h.inFlight--
	h.mu.Unlock()
	<-h.sem
}

func (h *RecognitionHandler) dispatch(r *http.Request, request *RecognitionRequest) (*RecognitionResponse, *WireError) {
	ctx, cancel := context.WithTimeout(r.Context(), h.limits.ProviderTimeout)
	defer cancel()
	_ = ctx
	switch request.Stage {
	case StageRead:
		return h.runTranscribe(ctx, request, false)
	case StageVerify:
		return h.runTranscribe(ctx, request, true)
	case StageStructure:
		return h.runStructure(ctx, request)
	}
	return nil, wireErr(CodeInvalidSchema, "未知 stage")
}

// runTranscribe 处理 read/verify：组提示词 + 逐区域附图 → provider →
// 模型输出解析（数组）→ sanitize（含 missingRegionIds 求差）→ 回填外壳。
func (h *RecognitionHandler) runTranscribe(ctx context.Context, request *RecognitionRequest, verify bool) (*RecognitionResponse, *WireError) {
	prompt := BuildReadPrompt(request.Regions)
	if verify {
		prompt = BuildVerifyPrompt(request.Regions)
	}
	images := make([]ProviderImage, 0, len(request.Regions))
	for _, region := range request.Regions {
		images = append(images, ProviderImage{Base64: region.ImagePngBase64})
	}
	raw, err := h.provider.Complete(ctx, ProviderRequest{
		Stage:      request.Stage,
		PromptText: prompt,
		Images:     images,
	})
	if err != nil {
		return nil, providerWireError(err)
	}
	var model []ModelRegionResult
	if pErr := parseModelJSON(raw, &model); pErr != nil {
		return nil, pErr
	}
	requestedIDs := make([]string, 0, len(request.Regions))
	for _, region := range request.Regions {
		requestedIDs = append(requestedIDs, region.RegionID)
	}
	regions, missing, sErr := SanitizeRegionResults(requestedIDs, model)
	if sErr != nil {
		return nil, sErr
	}
	return fillShell(request, &RecognitionResponse{
		Regions:          regions,
		MissingRegionIDs: missing,
	}), nil
}

// runStructure 处理 structure：元数据 + 可选概览图 → provider → 模型输出
// 解析（对象）→ 结构校验（R-06..R-10 + 子树连续性）→ 回填外壳与指纹。
func (h *RecognitionHandler) runStructure(ctx context.Context, request *RecognitionRequest) (*RecognitionResponse, *WireError) {
	prompt := BuildStructurePrompt(request.Units, request.OverviewPngBase64 != "")
	images := make([]ProviderImage, 0, 1)
	if request.OverviewPngBase64 != "" {
		images = append(images, ProviderImage{Base64: request.OverviewPngBase64})
	}
	raw, err := h.provider.Complete(ctx, ProviderRequest{
		Stage:      request.Stage,
		PromptText: prompt,
		Images:     images,
	})
	if err != nil {
		return nil, providerWireError(err)
	}
	var model ModelStructureResult
	if pErr := parseModelJSON(raw, &model); pErr != nil {
		return nil, pErr
	}
	sanitized, sErr := SanitizeStructureResult(request.Units, &model)
	if sErr != nil {
		return nil, sErr
	}
	sanitized.TextFingerprint = request.TextFingerprint
	return fillShell(request, sanitized), nil
}

// parseModelJSON 解析模型输出：一次确定性围栏剥离；解析失败=
// invalidProviderResponse（不可重试，服务端不做第二次调用）。
func parseModelJSON(raw string, target any) *WireError {
	trimmed := stripCodeFence(raw)
	dec := json.NewDecoder(strings.NewReader(trimmed))
	if err := dec.Decode(target); err != nil {
		return wireErr(CodeInvalidProviderResp, "模型输出解析失败: "+err.Error())
	}
	if err := dec.Decode(new(json.RawMessage)); err == nil {
		return wireErr(CodeInvalidProviderResp, "模型输出含尾随内容")
	}
	return nil
}

// providerWireError 将 provider 失败映射为 §3.5：传输层/超时→
// providerTimeout/providerError（retryable）；解析类绝不在此分支。
func providerWireError(err error) *WireError {
	var transport *ProviderTransportError
	if errors.As(err, &transport) {
		if errors.Is(transport.Err, context.DeadlineExceeded) {
			return wireErr(CodeProviderTimeout, "provider 超时")
		}
		if errors.Is(transport.Err, context.Canceled) {
			return wireErr(CodeProviderTimeout, "provider 调用被取消")
		}
		return wireErr(CodeProviderError, "provider 失败")
	}
	return wireErr(CodeProviderError, "provider 失败")
}

// fillShell 从请求回填响应外壳（不依赖模型回显；R-12 由客户端比对兜底）。
func fillShell(request *RecognitionRequest, response *RecognitionResponse) *RecognitionResponse {
	response.SchemaVersion = SchemaVersion
	response.Stage = request.Stage
	response.OperationID = request.OperationID
	response.RequestID = request.RequestID
	response.PageID = request.PageID
	response.SceneRevision = request.SceneRevision
	response.ContentFingerprint = request.ContentFingerprint
	response.Generation = request.Generation
	return response
}

func writeRecognitionError(w http.ResponseWriter, status int, wireErrValue *WireError) {
	log.Printf("[recognition-v3] %d %s: %s", status, wireErrValue.Code, wireErrValue.Message)
	writeRecognitionJSON(w, status, map[string]*WireError{"error": wireErrValue})
}

func writeRecognitionJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
