package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

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
	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:55124" {
		t.Fatalf("allow origin = %q", got)
	}
	if called {
		t.Fatal("preflight request reached API handler")
	}
}
