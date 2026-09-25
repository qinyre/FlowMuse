package auth

import (
	"errors"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

func (api *HTTPAPI) huaweiLogin(w http.ResponseWriter, r *http.Request) {
	if !api.allowLinkRequest(w, r) {
		return
	}
	identity, ok := api.huaweiIdentity(w, r)
	if !ok {
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	user, err := api.userStore.LoginHuawei(ctx, identity.UnionID)
	if err != nil {
		writeLinkError(w, err)
		return
	}
	if identity.DisplayName != "" || identity.AvatarURL != "" {
		user, err = api.userStore.FillHuaweiProfile(ctx, user.ID, identity.DisplayName, identity.AvatarURL)
		if err != nil {
			writeLinkError(w, err)
			return
		}
	}
	api.writeAuthSession(w, http.StatusOK, user)
}

func (api *HTTPAPI) huaweiBind(w http.ResponseWriter, r *http.Request) {
	sessionIdentity, sessionID, ok := api.linkSession(w, r)
	if !ok {
		return
	}
	identity, ok := api.huaweiIdentity(w, r)
	if !ok {
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	user, err := api.userStore.BindHuawei(ctx, sessionIdentity.UserID, sessionID, identity.UnionID)
	if err != nil {
		writeLinkError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (api *HTTPAPI) huaweiIdentity(w http.ResponseWriter, r *http.Request) (HuaweiIdentity, bool) {
	if api.huawei == nil {
		http.Error(w, "华为登录暂未配置，请使用邮箱登录", http.StatusServiceUnavailable)
		return HuaweiIdentity{}, false
	}
	var request struct {
		Code string `json:"code"`
	}
	if !decodeJSON(w, r, &request) {
		return HuaweiIdentity{}, false
	}
	if strings.TrimSpace(request.Code) == "" || len(request.Code) > 8192 {
		http.Error(w, "华为授权码无效，请重新授权", http.StatusBadRequest)
		return HuaweiIdentity{}, false
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	identity, err := api.huawei.VerifyCode(ctx, request.Code)
	if err != nil {
		if errors.Is(err, ErrInvalidHuaweiCode) {
			http.Error(w, "华为授权已失效，请重新授权", http.StatusUnauthorized)
		} else {
			http.Error(w, "华为登录暂时不可用，请稍后重试", http.StatusBadGateway)
		}
		return HuaweiIdentity{}, false
	}
	return identity, true
}

func (api *HTTPAPI) requestEmailBinding(w http.ResponseWriter, r *http.Request) {
	identity, sessionID, ok := api.linkSession(w, r)
	if !ok {
		return
	}
	var request struct {
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	token, err := randomToken()
	if err != nil {
		writeLinkError(w, err)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	requestID := hashToken(token)
	email, err := api.userStore.CreateEmailBinding(ctx, identity.UserID, sessionID, request.Email, requestID, time.Now().Add(30*time.Minute))
	if err != nil {
		writeLinkError(w, err)
		return
	}
	link := api.publicAppURL + "/auth/verify-email?purpose=bind_email&token=" + token
	if err = api.mailer.SendEmailBinding(ctx, email, link); err != nil {
		http.Error(w, "绑定邮件发送失败，请稍后重试", http.StatusBadGateway)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"requestId": requestID, "email": email})
}

func (api *HTTPAPI) verifyEmailBinding(w http.ResponseWriter, r *http.Request) {
	if !api.allowLinkRequest(w, r) {
		return
	}
	var request struct {
		Token string `json:"token"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	if len(request.Token) != 43 {
		writeLinkError(w, ErrInvalidAccountToken)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	if err := api.userStore.VerifyEmailBinding(ctx, hashToken(request.Token)); err != nil {
		writeLinkError(w, err)
		return
	}
	// Email proof never issues a session or changes the browser's current user.
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) completeEmailBinding(w http.ResponseWriter, r *http.Request) {
	identity, sessionID, ok := api.linkSession(w, r)
	if !ok {
		return
	}
	var request struct {
		RequestID string `json:"requestId"`
		Password  string `json:"password"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	if len(request.RequestID) != 64 {
		writeLinkError(w, ErrInvalidAccountToken)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	user, err := api.userStore.CompleteEmailBinding(ctx, identity.UserID, sessionID, request.RequestID, request.Password)
	if err != nil {
		writeLinkError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (api *HTTPAPI) linkSession(w http.ResponseWriter, r *http.Request) (Identity, string, bool) {
	if !api.allowLinkRequest(w, r) {
		return Identity{}, "", false
	}
	identity, ok := api.IdentityFromRequest(r)
	if !ok {
		http.Error(w, "登录已失效，请重新登录", http.StatusUnauthorized)
		return Identity{}, "", false
	}
	_, sessionID, err := api.tokenService.Verify(BearerToken(r.Header.Get("Authorization")))
	return identity, sessionID, err == nil
}

func writeLinkError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrEmailAlreadyRegistered), errors.Is(err, ErrIdentityAlreadyLinked):
		http.Error(w, "该登录方式已绑定账号，请使用原账号登录；暂不支持合并或换绑", http.StatusConflict)
	case errors.Is(err, ErrInvalidCredentials):
		http.Error(w, "登录已失效，请重新登录", http.StatusUnauthorized)
	case errors.Is(err, ErrInvalidAccountToken):
		http.Error(w, "绑定申请无效或已过期，请在原应用重新发起绑定", http.StatusBadRequest)
	case errors.Is(err, ErrEmailBindingPending):
		http.Error(w, "请先打开邮件完成邮箱验证，再回到这里完成绑定", http.StatusBadRequest)
	case errors.Is(err, ErrInvalidRegistration):
		http.Error(w, "请检查邮箱格式与密码长度；密码至少 8 位，过长时请缩短", http.StatusBadRequest)
	case errors.Is(err, ErrEmailRateLimited):
		w.Header().Set("Retry-After", "60")
		http.Error(w, "请等待 60 秒后再发送绑定邮件", http.StatusTooManyRequests)
	default:
		http.Error(w, "账号操作失败，请稍后重试", http.StatusInternalServerError)
	}
}

type authRateWindow struct {
	until time.Time
	count int
}

type authRateLimiter struct {
	mu      sync.Mutex
	windows map[string]authRateWindow
}

func (l *authRateLimiter) allow(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.windows == nil {
		l.windows = make(map[string]authRateWindow)
	}
	window := l.windows[key]
	if !now.Before(window.until) {
		if len(l.windows) >= 4096 {
			for k, old := range l.windows {
				if !now.Before(old.until) {
					delete(l.windows, k)
				}
			}
			if len(l.windows) >= 4096 {
				return false
			}
		}
		window = authRateWindow{until: now.Add(time.Minute)}
	}
	if window.count >= 30 {
		return false
	}
	window.count++
	l.windows[key] = window
	return true
}

func (api *HTTPAPI) allowLinkRequest(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return false
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	// ponytail: per-process IP windows; a shared gateway limiter is needed for
	// multiple replicas. Forwarded headers are deliberately not trusted here.
	if !api.linkRate.allow(host, time.Now()) {
		w.Header().Set("Retry-After", "60")
		http.Error(w, "操作过于频繁，请稍后重试", http.StatusTooManyRequests)
		return false
	}
	w.Header().Set("Cache-Control", "no-store")
	return true
}
