package social

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"flowmuse/server/internal/auth"
)

type HTTPAPI struct {
	store    *Store
	identity func(*http.Request) (auth.Identity, bool)
	enabled  bool
	timeout  time.Duration
	Notify   func(event, id string, users ...string)
	mu       sync.Mutex
	rates    map[string]requestRate
}

type requestRate struct {
	since time.Time
	count int
}

func NewHTTPAPI(store *Store, identity func(*http.Request) (auth.Identity, bool), enabled bool, timeout time.Duration) *HTTPAPI {
	return &HTTPAPI{store: store, identity: identity, enabled: enabled, timeout: timeout, rates: map[string]requestRate{}}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) { mux.HandleFunc("/api/social/", api.serve) }

func (api *HTTPAPI) serve(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if !api.enabled {
		fail(w, http.StatusServiceUnavailable, "disabled", "好友服务暂未开放")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), api.timeout)
	defer cancel()
	r = r.WithContext(ctx)
	identity, ok := api.identity(r)
	if !ok || identity.IsGuest || identity.UserID == "" {
		fail(w, 401, "unauthorized", "登录已失效，请重新登录")
		return
	}
	user := identity.UserID
	path := strings.TrimPrefix(r.URL.Path, "/api/social/")
	if !api.allow(user+":all", 300) || (path == "people/lookup" && !api.allow(user+":lookup", 30)) {
		respondError(w, ErrLimit)
		return
	}
	var result any
	var err error
	status := http.StatusOK
	switch {
	case path == "me" && r.Method == "GET":
		var person Person
		person, err = api.store.Me(ctx, user)
		if err == nil {
			var pending int
			err = api.store.db.QueryRow(ctx, `SELECT count(*) FROM social_relationships WHERE $1 IN(user_low_id,user_high_id) AND requester_id<>$1 AND state='pending'`, user).Scan(&pending)
			var unread int64
			if err == nil {
				unread, err = api.store.UnreadCount(ctx, user)
			}
			result = map[string]any{"person": person, "pendingRequestCount": pending, "unreadCount": unread, "capabilities": map[string]bool{"friends": true, "textMessages": true, "invitations": false}}
		}
	case path == "people/lookup" && r.Method == "POST":
		var body struct {
			FriendCode string `json:"friendCode"`
		}
		if !decode(w, r, &body) {
			return
		}
		result, err = api.store.Lookup(ctx, user, body.FriendCode)
	case path == "relationships" && r.Method == "GET":
		limit, cursor, valid := page(r, 20)
		if !valid {
			respondError(w, ErrInvalid)
			return
		}
		var items []Relationship
		items, err = api.store.Relationships(ctx, user, r.URL.Query().Get("state"), cursor, limit+1)
		next := ""
		if len(items) > limit {
			items = items[:limit]
			next = items[limit-1].ID
		}
		result = map[string]any{"items": items, "nextCursor": next}
	case path == "relationships" && r.Method == "POST":
		var body struct {
			FriendCode      string `json:"friendCode"`
			RequestMessage  string `json:"requestMessage"`
			ClientRequestID string `json:"clientRequestId"`
			ExpectedVersion *int64 `json:"expectedVersion,string"`
		}
		if !decode(w, r, &body) {
			return
		}
		if body.ExpectedVersion == nil {
			respondError(w, ErrInvalid)
			return
		}
		var relationship Relationship
		relationship, err = api.store.RequestFriend(ctx, user, body.FriendCode, body.RequestMessage, body.ClientRequestID, *body.ExpectedVersion)
		if err == nil {
			api.changed("relationship.changed", relationship.ID, user, relationship.Person.ID)
		}
		result = relationship
	case strings.HasPrefix(path, "relationships/") && r.Method == "POST":
		id, ok := actionID(path, "relationships", "actions")
		if !ok {
			respondError(w, ErrNotFound)
			return
		}
		var body struct {
			Action          string `json:"action"`
			ExpectedVersion *int64 `json:"expectedVersion,string"`
		}
		if !decode(w, r, &body) {
			return
		}
		if body.ExpectedVersion == nil {
			respondError(w, ErrInvalid)
			return
		}
		var relationship Relationship
		relationship, err = api.store.RelationshipAction(ctx, user, id, body.Action, *body.ExpectedVersion)
		if err == nil {
			api.changed("relationship.changed", relationship.ID, user, relationship.Person.ID)
		}
		result = relationship
	case path == "blocks" && r.Method == "GET":
		var items []Person
		items, err = api.store.Blocks(ctx, user)
		result = map[string]any{"items": items}
	case path == "blocks" && r.Method == "POST":
		var body struct {
			UserID string `json:"userId"`
		}
		if !decode(w, r, &body) {
			return
		}
		err = api.store.SetBlock(ctx, user, body.UserID, true)
		if err == nil {
			api.changed("relationship.changed", "", user, body.UserID)
		}
		status = 204
	case strings.HasPrefix(path, "blocks/") && r.Method == "POST":
		id, ok := actionID(path, "blocks", "remove")
		if !ok {
			respondError(w, ErrNotFound)
			return
		}
		err = api.store.SetBlock(ctx, user, id, false)
		if err == nil {
			api.changed("relationship.changed", "", user, id)
		}
		status = 204
	case path == "conversations" && r.Method == "GET":
		limit, cursor, valid := page(r, 20)
		if !valid {
			respondError(w, ErrInvalid)
			return
		}
		var items []Conversation
		items, err = api.store.Conversations(ctx, user, cursor, limit+1)
		next := ""
		if len(items) > limit {
			items = items[:limit]
			next = items[limit-1].ID
		}
		result = map[string]any{"items": items, "nextCursor": next}
	case strings.HasPrefix(path, "conversations/"):
		id, ok := actionID(path, "conversations", "messages")
		if ok && r.Method == "GET" {
			limit, _, valid := page(r, 50)
			q := r.URL.Query()
			before, be := parseSeq(q.Get("beforeSeq"))
			after, ae := parseSeq(q.Get("afterSeq"))
			if !valid || be != nil || ae != nil || (q.Has("beforeSeq") && q.Has("afterSeq")) {
				respondError(w, ErrInvalid)
				return
			}
			var items []Message
			items, err = api.store.Messages(ctx, user, id, before, after, limit+1)
			hasMore := len(items) > limit
			if hasMore {
				if after > 0 {
					items = items[:limit]
				} else {
					items = items[1:]
				}
			}
			result = map[string]any{"items": items, "hasMore": hasMore}
		} else if ok && r.Method == "POST" {
			var body struct {
				ClientMessageID string `json:"clientMessageId"`
				Text            string `json:"text"`
			}
			if !decode(w, r, &body) {
				return
			}
			var m Message
			var peer string
			m, peer, err = api.store.SendMessage(ctx, user, id, body.ClientMessageID, body.Text)
			result = m
			if err == nil {
				api.changed("conversation.changed", id, user, peer)
			}
		} else if id, ok := actionID(path, "conversations", "read"); ok && r.Method == "PUT" {
			var body struct {
				ThroughSeq *int64 `json:"throughSeq,string"`
			}
			if !decode(w, r, &body) {
				return
			}
			if body.ThroughSeq == nil {
				respondError(w, ErrInvalid)
				return
			}
			err = api.store.MarkRead(ctx, user, id, *body.ThroughSeq)
			status = 204
			if err == nil {
				api.changed("conversation.changed", id, user)
			}
		} else {
			respondError(w, ErrNotFound)
			return
		}
	default:
		respondError(w, ErrNotFound)
		return
	}
	if err != nil {
		respondError(w, err)
		return
	}
	if status == 204 {
		w.WriteHeader(status)
		return
	}
	writeJSON(w, status, result)
}

func parseSeq(s string) (int64, error) {
	if s == "" {
		return 0, nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n < 0 {
		return 0, ErrInvalid
	}
	return n, nil
}

func (api *HTTPAPI) changed(event, id string, users ...string) {
	if api.Notify != nil {
		api.Notify(event, id, users...)
	}
}

func (api *HTTPAPI) allow(key string, limit int) bool {
	api.mu.Lock()
	defer api.mu.Unlock()
	now := time.Now()
	if len(api.rates) >= 4096 {
		for k, v := range api.rates {
			if now.Sub(v.since) >= time.Minute {
				delete(api.rates, k)
			}
		}
	}
	r, exists := api.rates[key]
	if !exists && len(api.rates) >= 4096 {
		return false
	}
	if now.Sub(r.since) >= time.Minute {
		r = requestRate{since: now}
	}
	if r.count >= limit {
		return false
	}
	r.count++
	api.rates[key] = r
	return true
}

func actionID(path, prefix, action string) (string, bool) {
	parts := strings.Split(path, "/")
	if len(parts) != 3 || parts[0] != prefix || parts[2] != action || !safeID.MatchString(parts[1]) {
		return "", false
	}
	return parts[1], true
}

func page(r *http.Request, fallback int) (int, string, bool) {
	limit := fallback
	if value := r.URL.Query().Get("limit"); value != "" {
		var err error
		limit, err = strconv.Atoi(value)
		if err != nil || limit < 1 || limit > 100 {
			return 0, "", false
		}
	}
	cursor := r.URL.Query().Get("cursor")
	return limit, cursor, cursor == "" || safeID.MatchString(cursor)
}

func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64*1024)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	err := d.Decode(target)
	if err == nil {
		if e := d.Decode(new(any)); e != io.EOF {
			err = ErrInvalid
			if e != nil {
				err = e
			}
		}
	}
	if err != nil {
		var large *http.MaxBytesError
		if errors.As(err, &large) {
			fail(w, 413, "too_large", "请求内容过大")
		} else {
			respondError(w, ErrInvalid)
		}
		return false
	}
	return true
}

func respondError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalid):
		fail(w, 400, "invalid_input", "内容或参数不符合要求，请检查后重试")
	case errors.Is(err, ErrNotFound):
		fail(w, 404, "not_found", "未找到该用户或记录")
	case errors.Is(err, ErrForbidden):
		fail(w, 403, "interaction_forbidden", "当前关系不允许此操作")
	case errors.Is(err, ErrConflict):
		fail(w, 409, "conflict", "状态已更新，请刷新后重试")
	case errors.Is(err, ErrLimit):
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "limit_reached", "操作过于频繁或已达数量上限，请稍后重试")
	default:
		fail(w, 503, "unavailable", "好友服务暂不可用，请稍后重试")
	}
}

func fail(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"code": code, "message": message})
}
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
