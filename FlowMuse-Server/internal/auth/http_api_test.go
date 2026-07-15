package auth

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDecodeJSONRejectsOversizedBody(t *testing.T) {
	body := "{\"email\":\"" + strings.Repeat("a", maxJSONBodyBytes) + "\"}"
	request := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(body))
	response := httptest.NewRecorder()

	if decodeJSON(response, request, &map[string]any{}) {
		t.Fatal("decodeJSON() accepted oversized body")
	}
	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusRequestEntityTooLarge)
	}
}
