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
const maxSmartLayoutBodyBytes = 4 * 1024 * 1024

type Recognizer interface {
	Recognize(context.Context, RecognizeRequest) (RecognizeResponse, error)
}

type HTTPAPI struct {
	recognizer     Recognizer
	layouter       SmartLayouter
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

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/api/ink/recognize", api.recognize)
	mux.HandleFunc("/api/ink/smart-layout", api.smartLayout)
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
	if len(request.Ink) == 0 && len(request.Text) == 0 {
		return errors.New("ink or text is required")
	}
	if len(request.Ink) > 4096 || len(request.Text) > 4096 || len(request.Context) > 4096 {
		return errors.New("too many elements")
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
