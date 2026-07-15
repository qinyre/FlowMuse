package collab

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRoomsRootRejectsOversizedMetadata(t *testing.T) {
	api := &HTTPAPI{}
	body := "{\"roomId\":\"" + strings.Repeat("a", maxMetadataBytes) + "\"}"
	request := httptest.NewRequest(http.MethodPost, "/api/rooms", strings.NewReader(body))
	response := httptest.NewRecorder()

	api.roomsRoot(response, request)

	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusRequestEntityTooLarge)
	}
}
