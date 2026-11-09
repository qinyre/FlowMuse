package websearch

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"flowmuse/server/internal/auth"
)

const Endpoint = "/api/assistant/web-search"

type source struct {
	Title   string `json:"title"`
	URL     string `json:"url"`
	Snippet string `json:"snippet"`
}

func Handler(key string, authenticate func(*http.Request) (auth.Identity, error)) http.Handler {
	return handler(strings.TrimSpace(key), authenticate, &http.Client{
		Timeout:       8 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	})
}

func handler(key string, authenticate func(*http.Request) (auth.Identity, error), client *http.Client) http.Handler {
	var mu sync.Mutex
	var day string
	var count int
	var last time.Time
	var perUser map[string]int
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if key == "" {
			http.Error(w, "search unavailable", http.StatusServiceUnavailable)
			return
		}
		identity, err := authenticate(r)
		if err != nil && !errors.Is(err, auth.ErrInvalidToken) {
			http.Error(w, "authentication unavailable", http.StatusServiceUnavailable)
			return
		}
		if err != nil || identity.IsGuest || identity.UserID == "" {
			http.Error(w, "sign in required", http.StatusUnauthorized)
			return
		}
		var input struct {
			Query string `json:"query"`
		}
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048))
		decoder.DisallowUnknownFields()
		if decoder.Decode(&input) != nil || decoder.Decode(new(any)) != io.EOF {
			http.Error(w, "invalid search", http.StatusBadRequest)
			return
		}
		query := strings.TrimSpace(input.Query)
		if query == "" || utf8.RuneCountInString(query) > 200 {
			http.Error(w, "invalid search", http.StatusBadRequest)
			return
		}
		now := time.Now().UTC()
		mu.Lock()
		if today := now.Format(time.DateOnly); day != today {
			day, count = today, 0
			perUser = make(map[string]int)
		}
		allowed := count < 200 && perUser[identity.UserID] < 20 && now.Sub(last) >= time.Second
		if allowed {
			last = now
			count++
			perUser[identity.UserID]++
		}
		mu.Unlock()
		if !allowed {
			http.Error(w, "search limit reached", http.StatusTooManyRequests)
			return
		}

		params := url.Values{"q": {query}, "count": {"5"}, "safesearch": {"strict"}, "text_decorations": {"false"}}
		request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, "https://api.search.brave.com/res/v1/web/search?"+params.Encode(), nil)
		if err != nil {
			http.Error(w, "search unavailable", http.StatusBadGateway)
			return
		}
		request.Header.Set("Accept", "application/json")
		request.Header.Set("X-Subscription-Token", key)
		response, err := client.Do(request)
		if err != nil {
			http.Error(w, "search unavailable", http.StatusBadGateway)
			return
		}
		defer response.Body.Close()
		var payload struct {
			Web struct {
				Results []struct {
					Title       string
					URL         string
					Description string
				}
			}
		}
		if response.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(response.Body, 512<<10)).Decode(&payload) != nil {
			http.Error(w, "search unavailable", http.StatusBadGateway)
			return
		}
		results := make([]source, 0, 5)
		seen := map[string]bool{}
		for _, item := range payload.Web.Results {
			link, err := url.Parse(item.URL)
			if err != nil || (link.Scheme != "https" && link.Scheme != "http") ||
				link.Hostname() == "" || link.User != nil || len(item.URL) > 2048 || seen[item.URL] ||
				strings.TrimSpace(item.Title) == "" || strings.TrimSpace(item.Description) == "" {
				continue
			}
			seen[item.URL] = true
			results = append(results, source{truncate(item.Title, 180), item.URL, truncate(item.Description, 600)})
			if len(results) == 5 {
				break
			}
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(results)
	})
}

func truncate(value string, max int) string {
	value = strings.Join(strings.Fields(value), " ")
	for index := range value {
		if max == 0 {
			return value[:index]
		}
		max--
	}
	return value
}
