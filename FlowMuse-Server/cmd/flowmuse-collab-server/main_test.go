package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"flowmuse/server/internal/config"
	"flowmuse/server/internal/layoutrecognitionv3"
)

func TestRecognitionV3RegistrationUsesConfiguredTimeout(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		<-r.Context().Done()
	}))
	defer upstream.Close()
	mux := http.NewServeMux()
	registerLayoutRecognitionV3(mux, config.Config{
		LayoutV3BaseURL: upstream.URL,
		LayoutV3APIKey:  "test-key",
		LayoutV3Model:   "test-model",
		LayoutV3Timeout: 50 * time.Millisecond,
	})
	body, err := json.Marshal(layoutrecognitionv3.RecognitionRequest{
		SchemaVersion: layoutrecognitionv3.SchemaVersion,
		Stage:         layoutrecognitionv3.StageStructure,
		OperationID:   "op-test", RequestID: "req-test", PageID: "page-test",
		SceneRevision:      layoutrecognitionv3.SceneRevision{Fingerprint: "scene-fp"},
		ContentFingerprint: "content-fp", TextFingerprint: "text-fp",
		Units: []layoutrecognitionv3.UnitInput{{
			UnitID: "native:test", Kind: "preserved",
			Bounds: layoutrecognitionv3.UnitBounds{Width: 10, Height: 10},
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	// 防回归时测试本身等待默认 120s；外层截止不应成为实际生效的超时。
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	request := httptest.NewRequest(http.MethodPost, layoutrecognitionv3.EndpointPath, bytes.NewReader(body)).WithContext(ctx)
	response := httptest.NewRecorder()
	started := time.Now()
	mux.ServeHTTP(response, request)
	if response.Code != http.StatusGatewayTimeout || time.Since(started) >= time.Second {
		t.Fatalf("配置的短超时没有作用于生产注册链：status=%d elapsed=%v", response.Code, time.Since(started))
	}
	var envelope struct {
		Error layoutrecognitionv3.WireError `json:"error"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.Error.Code != layoutrecognitionv3.CodeProviderTimeout {
		t.Fatalf("错误码 = %s", envelope.Error.Code)
	}
}

func TestSocketAllowedOriginsUsesTypesSupportedByEngineIO(t *testing.T) {
	if got := socketAllowedOrigins([]string{"*"}); got != "*" {
		t.Fatalf("wildcard origins = %#v", got)
	}
	want := []any{"https://qinyre.github.io", "http://localhost:3000"}
	if got := socketAllowedOrigins([]string{
		"https://qinyre.github.io",
		"http://localhost:3000",
	}); !reflect.DeepEqual(got, want) {
		t.Fatalf("explicit origins = %#v, want %#v", got, want)
	}
}

func TestWithCORSHandlesBrowserPreflight(t *testing.T) {
	called := false
	handler := withCORS(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		called = true
	}), []string{"*"})
	request := httptest.NewRequest(http.MethodOptions, "/api/rooms/room/scene", nil)
	request.Header.Set("Origin", "http://localhost:55124")
	request.Header.Set("Access-Control-Request-Method", http.MethodGet)
	request.Header.Set("Access-Control-Request-Headers", "content-type")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
	}
	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("allow origin = %q", got)
	}
	if got := response.Header().Get("Access-Control-Allow-Credentials"); got != "" {
		t.Fatalf("allow credentials = %q, want empty for wildcard origin", got)
	}
	if called {
		t.Fatal("preflight request reached API handler")
	}
}

func TestWithCORSAllowsCredentialsOnlyForExplicitOrigin(t *testing.T) {
	handler := withCORS(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}), []string{"https://app.flowmuse.example"})
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	request.Header.Set("Origin", "https://app.flowmuse.example")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "https://app.flowmuse.example" {
		t.Fatalf("allow origin = %q", got)
	}
	if got := response.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Fatalf("allow credentials = %q, want true", got)
	}
}
