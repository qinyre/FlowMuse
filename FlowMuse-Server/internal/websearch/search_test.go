package websearch

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
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
		if r.Method != http.MethodPost || r.URL.String() != "https://api.tavily.com/search" ||
			r.Header.Get("Authorization") != "Bearer provider-test-key" ||
			r.Header.Get("Content-Type") != "application/json" {
			t.Fatal("unexpected search provider request")
		}
		var body map[string]any
		want := map[string]any{
			"query": "梯度消失", "search_depth": "basic", "auto_parameters": false,
			"max_results": float64(5), "safe_search": true,
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || !reflect.DeepEqual(body, want) {
			t.Fatal("unexpected search provider request body")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(
			`{"results":[{"title":"Gradient","url":"https://example.com/gradient","content":"A source"},{"title":"unsafe","url":"javascript:alert(1)","content":"ignored"}]}`,
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
		!strings.Contains(response.Body.String(), `"snippet":"A source"`) ||
		strings.Contains(response.Body.String(), "javascript:") {
		t.Fatalf("unexpected search result, status %d, calls %d", response.Code, called)
	}
	if code := request("Bearer session", `{"query":"梯度消失"}`).Code; code != http.StatusTooManyRequests {
		t.Fatalf("rate limit status = %d", code)
	}
}

func TestSearchReportsTavilyUsageLimit(t *testing.T) {
	client := &http.Client{Transport: testTransport(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 432, Body: http.NoBody}, nil
	})}
	endpoint := handler("provider-test-key", func(*http.Request) (auth.Identity, error) {
		return auth.Identity{UserID: "test"}, nil
	}, client)
	request := httptest.NewRequest(http.MethodPost, Endpoint, strings.NewReader(`{"query":"test"}`))
	response := httptest.NewRecorder()
	endpoint.ServeHTTP(response, request)
	if response.Code != http.StatusTooManyRequests {
		t.Fatalf("search quota status = %d", response.Code)
	}
}
