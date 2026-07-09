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

type Recognizer interface {
	Recognize(context.Context, RecognizeRequest) (RecognizeResponse, error)
}

type HTTPAPI struct {
	recognizer     Recognizer
	requestTimeout time.Duration
}

func NewHTTPAPI(recognizer Recognizer, requestTimeout time.Duration) *HTTPAPI {
	return &HTTPAPI{
		recognizer:     recognizer,
		requestTimeout: requestTimeout,
	}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/api/ink/recognize", api.recognize)
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
	if hint != "" && hint != "auto" {
		return errors.New("hint must be auto")
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
