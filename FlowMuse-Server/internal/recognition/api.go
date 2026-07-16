package recognition

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

const maxInkBodyBytes = 512 * 1024
const maxSmartLayoutBodyBytes = 32 * 1024 * 1024
const maxAIAgentBodyBytes = 64 * 1024

type Recognizer interface {
	Recognize(context.Context, RecognizeRequest) (RecognizeResponse, error)
}

type HTTPAPI struct {
	recognizer     Recognizer
	layouter       SmartLayouter
	agent          AIAgentRunner
	authorizeAgent func(*http.Request) bool
	requestTimeout time.Duration
}

func NewHTTPAPI(recognizer Recognizer, requestTimeout time.Duration, layouter ...SmartLayouter) *HTTPAPI {
	var smartLayouter SmartLayouter
	if len(layouter) > 0 {
		smartLayouter = layouter[0]
	}
	return &HTTPAPI{
		recognizer:     recognizer,
		layouter:       smartLayouter,
		requestTimeout: requestTimeout,
	}
}

func (api *HTTPAPI) WithAIAgent(agent AIAgentRunner, authorize func(*http.Request) bool) *HTTPAPI {
	api.agent = agent
	api.authorizeAgent = authorize
	return api
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/api/ink/recognize", api.recognize)
	mux.HandleFunc("/api/ink/smart-layout", api.smartLayout)
	mux.HandleFunc("/api/ink/smart-layout/block", api.smartLayoutBlock)
	mux.HandleFunc("/api/ink/smart-layout/compose", api.smartLayoutCompose)
	if api.agent != nil {
		mux.HandleFunc("/api/ai/agent", api.aiAgent)
	}
}

func (api *HTTPAPI) aiAgent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	if api.authorizeAgent == nil || !api.authorizeAgent(r) {
		http.Error(w, "authentication required", http.StatusUnauthorized)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request AIAgentRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxAIAgentBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateAIAgentRequest(request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := api.agent.RunAgent(ctx, request)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func (api *HTTPAPI) recognize(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request RecognizeRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxInkBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateRequest(request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := api.recognizer.Recognize(ctx, request)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func (api *HTTPAPI) smartLayout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	if api.layouter == nil {
		http.Error(w, "AI smart layout is not configured", http.StatusBadGateway)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request SmartLayoutRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxSmartLayoutBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateSmartLayoutRequest(request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := api.layouter.Layout(ctx, request)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func (api *HTTPAPI) smartLayoutBlock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	if api.layouter == nil {
		http.Error(w, "AI smart layout is not configured", http.StatusBadGateway)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request SmartLayoutBlockRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxSmartLayoutBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateSmartLayoutInkBlock(request.Block); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := api.layouter.RecognizeBlock(ctx, request.Block)
	if err != nil {
		response = SmartLayoutRecognizedBlock{
			ID:           request.Block.ID,
			PageID:       request.Block.PageID,
			Type:         "error",
			Bounds:       request.Block.Bounds,
			StrokeBounds: request.Block.StrokeBounds,
			StartedAt:    request.Block.StartedAt,
			Error:        err.Error(),
		}
	}
	writeJSON(w, http.StatusOK, response)
}

func (api *HTTPAPI) smartLayoutCompose(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	if api.layouter == nil {
		http.Error(w, "AI smart layout is not configured", http.StatusBadGateway)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request SmartLayoutComposeRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxSmartLayoutBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateSmartLayoutComposeRequest(request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := api.layouter.Compose(ctx, request)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func validateRequest(request RecognizeRequest) error {
	if len(request.Strokes) == 0 {
		return errors.New("strokes are required")
	}
	if len(request.Strokes) > 64 {
		return errors.New("too many strokes")
	}
	for _, stroke := range request.Strokes {
		if len(stroke.Points) < 2 {
			return errors.New("each stroke requires at least two points")
		}
		if len(stroke.Points) > 2048 {
			return errors.New("stroke has too many points")
		}
	}
	hint := strings.TrimSpace(request.Hint)
	if hint != "" && hint != "auto" && hint != "text" && hint != "math" {
		return errors.New("hint must be auto, text, or math")
	}
	return nil
}

func validateSmartLayoutRequest(request SmartLayoutRequest) error {
	if len(request.Pages) == 0 {
		return errors.New("pages are required")
	}
	if len(request.Pages) > 256 {
		return errors.New("too many pages")
	}
	if len(request.Blocks) == 0 {
		return errors.New("blocks are required")
	}
	if len(request.Blocks) > 512 {
		return errors.New("too many blocks")
	}
	for _, block := range request.Blocks {
		if err := validateSmartLayoutInkBlock(block); err != nil {
			return err
		}
	}
	return nil
}

func validateSmartLayoutInkBlock(block SmartLayoutInkBlock) error {
	if strings.TrimSpace(block.ID) == "" {
		return errors.New("block id is required")
	}
	if strings.TrimSpace(block.ImageBase64) == "" {
		return errors.New("block image is required")
	}
	return nil
}

func validateSmartLayoutComposeRequest(request SmartLayoutComposeRequest) error {
	if len(request.Pages) == 0 {
		return errors.New("pages are required")
	}
	if len(request.Pages) > 256 {
		return errors.New("too many pages")
	}
	if len(request.Blocks) == 0 {
		return errors.New("blocks are required")
	}
	if len(request.Blocks) > 512 {
		return errors.New("too many blocks")
	}
	for _, block := range request.Blocks {
		if strings.TrimSpace(block.ID) == "" {
			return errors.New("block id is required")
		}
	}
	return nil
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func contextWithTimeout(r *http.Request, timeout time.Duration) (context.Context, context.CancelFunc) {
	if timeout <= 0 {
		return context.WithCancel(r.Context())
	}
	return context.WithTimeout(r.Context(), timeout)
}
