package websearch

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"flowmuse/server/internal/auth"
)

type testTransport func(*http.Request) (*http.Response, error)

func (f testTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

func TestSearchForwardsOnlyKeywordsAndReturnsSafeSources(t *testing.T) {
	called := 0
	client := &http.Client{Transport: testTransport(func(r *http.Request) (*http.Response, error) {
		called++
		if r.URL.Host != "api.search.brave.com" || r.URL.Query().Get("q") != "梯度消失" ||
			r.Header.Get("X-Subscription-Token") != "provider-test-key" || r.Header.Get("Authorization") != "" {
			t.Fatal("unexpected search provider request")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(
			`{"web":{"results":[{"title":"Gradient","url":"https://example.com/gradient","description":"A source"},{"title":"unsafe","url":"javascript:alert(1)","description":"ignored"}]}}`,
		))}, nil
	})}
	identify := func(r *http.Request) (auth.Identity, error) {
		if r.Header.Get("Authorization") != "Bearer session" {
			return auth.Identity{}, auth.ErrInvalidToken
		}
		return auth.Identity{UserID: "test"}, nil
	}
	endpoint := handler("provider-test-key", identify, client)
	request := func(token, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, Endpoint, strings.NewReader(body))
		r.Header.Set("Authorization", token)
		result := httptest.NewRecorder()
		endpoint.ServeHTTP(result, r)
		return result
	}
	if code := request("", `{"query":"梯度消失"}`).Code; code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d", code)
	}
	if code := request("Bearer session", `{"query":"梯度消失","notes":"private"}`).Code; code != http.StatusBadRequest {
		t.Fatalf("invalid payload status = %d", code)
	}
	response := request("Bearer session", `{"query":"梯度消失"}`)
	if response.Code != http.StatusOK || called != 1 ||
		!strings.Contains(response.Body.String(), "https://example.com/gradient") ||
		strings.Contains(response.Body.String(), "javascript:") {
		t.Fatalf("unexpected search result, status %d, calls %d", response.Code, called)
	}
	if code := request("Bearer session", `{"query":"梯度消失"}`).Code; code != http.StatusTooManyRequests {
		t.Fatalf("rate limit status = %d", code)
	}
}
