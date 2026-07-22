package main

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

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
