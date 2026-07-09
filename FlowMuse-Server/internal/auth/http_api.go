package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path"
	"strings"
	"time"

	"flowmuse/server/internal/storage"

	"github.com/minio/minio-go/v7"
)

const (
	emailPurposeVerify = "verify_email"
	emailPurposeReset  = "password_reset"
	maxAvatarBytes     = 2 * 1024 * 1024
)

type HTTPAPI struct {
	userStore      *UserStore
	fileStore      *storage.FileStore
	tokenService   *TokenService
	mailer         *Mailer
	publicAppURL   string
	requestTimeout time.Duration
	verifyTTL      time.Duration
	resetTTL       time.Duration
}

func NewHTTPAPI(
	userStore *UserStore,
	fileStore *storage.FileStore,
	tokenService *TokenService,
	mailer *Mailer,
	publicAppURL string,
	requestTimeout time.Duration,
	verifyTTL time.Duration,
	resetTTL time.Duration,
) *HTTPAPI {
	return &HTTPAPI{
		userStore:      userStore,
		fileStore:      fileStore,
		tokenService:   tokenService,
		mailer:         mailer,
		publicAppURL:   strings.TrimRight(publicAppURL, "/"),
		requestTimeout: requestTimeout,
		verifyTTL:      verifyTTL,
		resetTTL:       resetTTL,
	}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/api/auth/", api.auth)
	mux.HandleFunc("/api/users/", api.users)
}

func (api *HTTPAPI) auth(w http.ResponseWriter, r *http.Request) {
	action := strings.TrimPrefix(r.URL.Path, "/api/auth/")
	switch action {
	case "register":
		api.register(w, r)
	case "verify-email":
		api.verifyEmail(w, r)
	case "resend-verification":
		api.resendVerification(w, r)
	case "login":
		api.login(w, r)
	case "me":
		api.me(w, r)
	case "me/avatar":
		api.uploadAvatar(w, r)
	case "change-password":
		api.changePassword(w, r)
	case "request-password-reset":
		api.requestPasswordReset(w, r)
	case "reset-password":
		api.resetPassword(w, r)
	case "logout":
		api.logout(w, r)
	default:
		http.NotFound(w, r)
	}
}

func (api *HTTPAPI) users(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/users/")
	userID, suffix := path.Split(rest)
	userID = strings.TrimSuffix(userID, "/")
	if userID == "" || suffix != "avatar" {
		http.NotFound(w, r)
		return
	}
	object, info, err := api.fileStore.GetAvatar(r.Context(), userID)
	if minio.ToErrorResponse(err).Code == "NoSuchKey" {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer object.Close()
	if info.ContentType != "" {
		w.Header().Set("Content-Type", info.ContentType)
	}
	w.Header().Set("Cache-Control", "public, max-age=3600")
	http.ServeContent(w, r, "avatar", info.LastModified, object)
}

func (api *HTTPAPI) register(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"displayName"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	user, err := api.userStore.Register(ctx, request.Email, request.Password, request.DisplayName)
	if err != nil {
		if errors.Is(err, ErrEmailAlreadyRegistered) {
			http.Error(w, "邮箱已注册", http.StatusConflict)
			return
		}
		if errors.Is(err, ErrInvalidRegistration) {
			http.Error(w, "邮箱、密码或昵称不符合要求", http.StatusBadRequest)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := api.sendAccountEmail(ctx, user, emailPurposeVerify); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"user":    user,
		"message": "验证邮件已发送，请验证后登录",
	})
}

func (api *HTTPAPI) verifyEmail(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Token string `json:"token"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	userID, err := api.userStore.ConsumeEmailToken(ctx, emailPurposeVerify, hashToken(request.Token))
	if errors.Is(err, ErrInvalidAccountToken) {
		http.Error(w, "验证链接无效或已过期", http.StatusBadRequest)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	user, err := api.userStore.MarkEmailVerified(ctx, userID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	api.writeAuthSession(w, http.StatusOK, user)
}

func (api *HTTPAPI) resendVerification(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	user, err := api.userStore.LoadByEmail(ctx, request.Email)
	if err != nil {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if user.EmailVerified {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if err := api.sendAccountEmail(ctx, user, emailPurposeVerify); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	user, err := api.userStore.Login(ctx, request.Email, request.Password)
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			http.Error(w, "邮箱或密码错误", http.StatusUnauthorized)
			return
		}
		if errors.Is(err, ErrEmailNotVerified) {
			http.Error(w, "邮箱尚未验证，请先打开验证邮件", http.StatusForbidden)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	api.writeAuthSession(w, http.StatusOK, user)
}

func (api *HTTPAPI) me(w http.ResponseWriter, r *http.Request) {
	identity, ok := api.IdentityFromRequest(r)
	if !ok || identity.IsGuest {
		http.Error(w, "未登录", http.StatusUnauthorized)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	switch r.Method {
	case http.MethodGet:
		user, err := api.userStore.Load(ctx, identity.UserID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"user": user})
	case http.MethodPatch:
		var request struct {
			DisplayName string `json:"displayName"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}
		user, err := api.userStore.UpdateProfile(ctx, identity.UserID, request.DisplayName)
		if errors.Is(err, ErrInvalidRegistration) {
			http.Error(w, "昵称不符合要求", http.StatusBadRequest)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"user": user})
	default:
		methodNotAllowed(w, "GET, PATCH")
	}
}

func (api *HTTPAPI) uploadAvatar(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	identity, ok := api.IdentityFromRequest(r)
	if !ok || identity.IsGuest {
		http.Error(w, "未登录", http.StatusUnauthorized)
		return
	}
	contentType := strings.ToLower(strings.Split(r.Header.Get("Content-Type"), ";")[0])
	if !allowedAvatarType(contentType) {
		http.Error(w, "头像只支持 PNG、JPEG、WebP 或 GIF", http.StatusBadRequest)
		return
	}
	if r.ContentLength < 0 {
		http.Error(w, "Content-Length is required", http.StatusLengthRequired)
		return
	}
	if r.ContentLength > maxAvatarBytes {
		http.Error(w, "头像不能超过 2MB", http.StatusRequestEntityTooLarge)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	r.Body = http.MaxBytesReader(w, r.Body, maxAvatarBytes)
	if err := api.fileStore.PutAvatar(ctx, identity.UserID, contentType, r.Body, r.ContentLength); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	avatarURL := fmt.Sprintf("/api/users/%s/avatar?v=%d", identity.UserID, time.Now().Unix())
	user, err := api.userStore.SetAvatarURL(ctx, identity.UserID, avatarURL)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (api *HTTPAPI) changePassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	identity, ok := api.IdentityFromRequest(r)
	if !ok || identity.IsGuest {
		http.Error(w, "未登录", http.StatusUnauthorized)
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		OldPassword string `json:"oldPassword"`
		NewPassword string `json:"newPassword"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	if err := api.userStore.ChangePassword(ctx, identity.UserID, request.OldPassword, request.NewPassword); err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			http.Error(w, "旧密码错误", http.StatusUnauthorized)
			return
		}
		if errors.Is(err, ErrInvalidRegistration) {
			http.Error(w, "新密码至少需要 8 位", http.StatusBadRequest)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := api.userStore.RevokeUserSessions(ctx, identity.UserID); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) requestPasswordReset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	user, err := api.userStore.LoadByEmail(ctx, request.Email)
	if err == nil && user.EmailVerified {
		if err := api.sendAccountEmail(ctx, user, emailPurposeReset); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) resetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	var request struct {
		Token       string `json:"token"`
		NewPassword string `json:"newPassword"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}
	if len(request.NewPassword) < 8 {
		http.Error(w, "新密码至少需要 8 位", http.StatusBadRequest)
		return
	}
	userID, err := api.userStore.ConsumeEmailToken(ctx, emailPurposeReset, hashToken(request.Token))
	if errors.Is(err, ErrInvalidAccountToken) {
		http.Error(w, "重置链接无效或已过期", http.StatusBadRequest)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := api.userStore.ResetPassword(ctx, userID, request.NewPassword); err != nil {
		if errors.Is(err, ErrInvalidRegistration) {
			http.Error(w, "新密码至少需要 8 位", http.StatusBadRequest)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := api.userStore.RevokeUserSessions(ctx, userID); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	token := BearerToken(r.Header.Get("Authorization"))
	userID, sessionID, err := api.tokenService.Verify(token)
	if err == nil {
		ctx, cancel := contextWithTimeout(r, api.requestTimeout)
		defer cancel()
		_ = api.userStore.RevokeSession(ctx, sessionID, userID)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (api *HTTPAPI) writeAuthSession(w http.ResponseWriter, status int, user User) {
	ctx, cancel := context.WithTimeout(context.Background(), api.requestTimeout)
	defer cancel()
	sessionID, err := api.userStore.CreateSession(ctx, user.ID, api.tokenService.ExpiresAt())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	token, err := api.tokenService.Issue(user, sessionID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, status, map[string]any{
		"token": token,
		"user":  user,
	})
}

func (api *HTTPAPI) IdentityFromRequest(r *http.Request) (Identity, bool) {
	token := BearerToken(r.Header.Get("Authorization"))
	if token == "" {
		return Identity{
			DisplayName: GuestName(r.RemoteAddr + r.UserAgent()),
			IsGuest:     true,
		}, false
	}
	userID, sessionID, err := api.tokenService.Verify(token)
	if err != nil {
		return Identity{DisplayName: "匿名用户", IsGuest: true}, false
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	if !api.userStore.SessionActive(ctx, sessionID, userID) {
		return Identity{DisplayName: "匿名用户", IsGuest: true}, false
	}
	user, err := api.userStore.Load(ctx, userID)
	if err != nil || !user.EmailVerified {
		return Identity{DisplayName: "匿名用户", IsGuest: true}, false
	}
	return Identity{
		UserID:      user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		AvatarURL:   user.AvatarURL,
		IsGuest:     false,
	}, true
}

func (api *HTTPAPI) sendAccountEmail(ctx context.Context, user User, purpose string) error {
	token, err := randomToken()
	if err != nil {
		return err
	}
	expiresAt := time.Now().Add(api.verifyTTL)
	linkPath := "/auth/verify-email"
	if purpose == emailPurposeReset {
		expiresAt = time.Now().Add(api.resetTTL)
		linkPath = "/auth/reset-password"
	}
	if err := api.userStore.CreateEmailToken(ctx, user.ID, purpose, hashToken(token), expiresAt); err != nil {
		return err
	}
	link := api.publicAppURL + linkPath + "?token=" + token
	if purpose == emailPurposeReset {
		return api.mailer.SendPasswordReset(ctx, user.Email, link)
	}
	return api.mailer.SendVerification(ctx, user.Email, link)
}

func randomToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(token)))
	return hex.EncodeToString(sum[:])
}

func allowedAvatarType(contentType string) bool {
	switch contentType {
	case "image/png", "image/jpeg", "image/webp", "image/gif":
		return true
	default:
		return false
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	if err := json.NewDecoder(r.Body).Decode(target); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func contextWithTimeout(r *http.Request, timeout time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(r.Context(), timeout)
}
