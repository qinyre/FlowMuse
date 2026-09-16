package layoutrecognitionv3

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRegisterRecognitionV3NoopOnNil(t *testing.T) {
	mux := http.NewServeMux()
	RegisterRecognitionV3(mux, nil)
	RegisterRecognitionV3(nil, NewRecognitionHandler(nil, DefaultLimits()))
	req := httptest.NewRequest(http.MethodPost, EndpointPath, nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("nil handler 不注册路由: %d", rec.Code)
	}
}

func TestRegisterRecognitionV3OldRoutesCoexist(t *testing.T) {
	mux := http.NewServeMux()
	legacyReached := false
	mux.HandleFunc("/api/ink/smart-layout/analyze/v3", func(w http.ResponseWriter, r *http.Request) {
		legacyReached = true
		w.WriteHeader(http.StatusOK)
	})
	RegisterRecognitionV3(mux, NewRecognitionHandler(nil, DefaultLimits()))

	legacyReq := httptest.NewRequest(http.MethodPost, "/api/ink/smart-layout/analyze/v3", nil)
	legacyRec := httptest.NewRecorder()
	mux.ServeHTTP(legacyRec, legacyReq)
	if !legacyReached || legacyRec.Code != http.StatusOK {
		t.Fatalf("旧路由必须不受影响: %d", legacyRec.Code)
	}

	// 新路由已注册（未配置 → 503 而非 404）。
	newReq := httptest.NewRequest(http.MethodPost, EndpointPath,
		strings.NewReader(readRequestBody(StageRead)))
	newRec := httptest.NewRecorder()
	mux.ServeHTTP(newRec, newReq)
	if newRec.Code != http.StatusServiceUnavailable {
		t.Fatalf("新路由应注册并 503 unconfigured: %d", newRec.Code)
	}
}

func TestMethodNotAllowed(t *testing.T) {
	handler := NewRecognitionHandler(nil, DefaultLimits())
	req := httptest.NewRequest(http.MethodGet, EndpointPath, nil)
	rec := httptest.NewRecorder()
	handler.serveHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET 应 405: %d", rec.Code)
	}
	if rec.Header().Get("Allow") != "POST" {
		t.Fatal("Allow 头")
	}
}
