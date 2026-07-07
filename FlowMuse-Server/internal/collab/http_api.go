package collab

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"

	"github.com/jackc/pgx/v5"
	"github.com/minio/minio-go/v7"
)

const (
	maxSceneBodyBytes = 8 * 1024 * 1024
	maxFileBodyBytes  = 10 * 1024 * 1024
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

type HTTPAPI struct {
	sceneStore     *storage.SceneStore
	fileStore      *storage.FileStore
	roomStore      *storage.RoomStore
	userStore      *auth.UserStore
	tokenService   *auth.TokenService
	requestTimeout time.Duration
}

func NewHTTPAPI(
	sceneStore *storage.SceneStore,
	fileStore *storage.FileStore,
	roomStore *storage.RoomStore,
	userStore *auth.UserStore,
	tokenService *auth.TokenService,
	requestTimeout time.Duration,
) *HTTPAPI {
	return &HTTPAPI{
		sceneStore:     sceneStore,
		fileStore:      fileStore,
		roomStore:      roomStore,
		userStore:      userStore,
		tokenService:   tokenService,
		requestTimeout: requestTimeout,
	}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/health", api.health)
	mux.HandleFunc("/api/auth/", api.auth)
	mux.HandleFunc("/api/rooms", api.roomsRoot)
	mux.HandleFunc("/api/rooms/", api.rooms)
}

func (api *HTTPAPI) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (api *HTTPAPI) auth(w http.ResponseWriter, r *http.Request) {
	action := strings.TrimPrefix(r.URL.Path, "/api/auth/")
	switch action {
	case "register":
		api.register(w, r)
	case "login":
		api.login(w, r)
	case "me":
		api.me(w, r)
	case "logout":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, "POST")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(w, r)
	}
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
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	user, err := api.userStore.Register(ctx, request.Email, request.Password, request.DisplayName)
	if err != nil {
		if errors.Is(err, auth.ErrEmailAlreadyRegistered) {
			http.Error(w, "邮箱已注册", http.StatusConflict)
			return
		}
		if errors.Is(err, auth.ErrInvalidRegistration) {
			http.Error(w, "邮箱、密码或昵称不符合要求", http.StatusBadRequest)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	api.writeAuthSession(w, http.StatusCreated, user)
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
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	user, err := api.userStore.Login(ctx, request.Email, request.Password)
	if err != nil {
		if errors.Is(err, auth.ErrInvalidCredentials) {
			http.Error(w, "邮箱或密码错误", http.StatusUnauthorized)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	api.writeAuthSession(w, http.StatusOK, user)
}

func (api *HTTPAPI) me(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	identity, ok := api.identityFromRequest(r)
	if !ok || identity.IsGuest {
		http.Error(w, "未登录", http.StatusUnauthorized)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": identity})
}

func (api *HTTPAPI) writeAuthSession(w http.ResponseWriter, status int, user auth.User) {
	token, err := api.tokenService.Issue(user)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, status, map[string]any{
		"token": token,
		"user":  user,
	})
}

func (api *HTTPAPI) roomsRoot(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		ctx, cancel := contextWithTimeout(r, api.requestTimeout)
		defer cancel()
		var request struct {
			RoomID string `json:"roomId"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if !safeIDPattern.MatchString(request.RoomID) {
			http.Error(w, "invalid roomId", http.StatusBadRequest)
			return
		}
		identity, _ := api.identityFromRequest(r)
		ownerID := ""
		if !identity.IsGuest {
			ownerID = identity.UserID
		}
		metadata, err := api.roomStore.CreateRoom(ctx, request.RoomID, ownerID)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, http.StatusCreated, metadata)
	default:
		methodNotAllowed(w, "POST")
	}
}

func (api *HTTPAPI) rooms(w http.ResponseWriter, r *http.Request) {
	roomID, suffix, ok := parseRoomPath(r.URL.Path)
	if !ok || !safeIDPattern.MatchString(roomID) {
		http.NotFound(w, r)
		return
	}
	if suffix == "scene" {
		api.scene(w, r, roomID)
		return
	}
	if suffix == "join" {
		api.joinRoom(w, r, roomID)
		return
	}
	if suffix == "end" {
		api.endRoom(w, r, roomID)
		return
	}
	if suffix == "access" {
		api.roomAccess(w, r, roomID)
		return
	}
	if strings.HasPrefix(suffix, "files/") {
		fileID := strings.TrimPrefix(suffix, "files/")
		if fileID == "" || strings.Contains(fileID, "/") || !safeIDPattern.MatchString(fileID) {
			http.NotFound(w, r)
			return
		}
		api.file(w, r, roomID, fileID)
		return
	}
	http.NotFound(w, r)
}

func (api *HTTPAPI) joinRoom(w http.ResponseWriter, r *http.Request, roomID string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	identity, _ := api.identityFromRequest(r)
	metadata, err := api.roomStore.LoadRoom(ctx, roomID, identity.UserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if metadata.Ended {
		http.Error(w, "协作房间已结束", http.StatusGone)
		return
	}
	if !identity.IsGuest {
		if err := api.roomStore.UpsertMember(ctx, roomID, identity.UserID, "editor"); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}
	metadata, err = api.roomStore.LoadRoom(ctx, roomID, identity.UserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, metadata)
}

func (api *HTTPAPI) roomAccess(w http.ResponseWriter, r *http.Request, roomID string) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, "GET")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	identity, _ := api.identityFromRequest(r)
	metadata, err := api.roomStore.LoadRoom(ctx, roomID, identity.UserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, metadata)
}

func (api *HTTPAPI) endRoom(w http.ResponseWriter, r *http.Request, roomID string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, "POST")
		return
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	identity, ok := api.identityFromRequest(r)
	if !ok || identity.IsGuest {
		http.Error(w, "未登录", http.StatusUnauthorized)
		return
	}
	metadata, err := api.roomStore.EndRoom(ctx, roomID, identity.UserID)
	if errors.Is(err, storage.ErrRoomAccessDenied) {
		http.Error(w, "只有房主可以结束协作", http.StatusForbidden)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, metadata)
}

func (api *HTTPAPI) scene(w http.ResponseWriter, r *http.Request, roomID string) {
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	identity, _ := api.identityFromRequest(r)
	metadata, err := api.roomStore.LoadRoom(ctx, roomID, identity.UserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if metadata.Ended {
		http.Error(w, "协作房间已结束", http.StatusGone)
		return
	}

	switch r.Method {
	case http.MethodGet:
		snapshot, err := api.sceneStore.Load(ctx, roomID)
		if errors.Is(err, pgx.ErrNoRows) {
			http.NotFound(w, r)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, http.StatusOK, snapshot)
	case http.MethodPut:
		var snapshot storage.SceneSnapshot
		r.Body = http.MaxBytesReader(w, r.Body, maxSceneBodyBytes)
		if err := json.NewDecoder(r.Body).Decode(&snapshot); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		snapshot.RoomID = roomID
		if snapshot.EncryptedBuffer == nil || snapshot.IV == nil {
			http.Error(w, "encryptedBuffer and iv are required", http.StatusBadRequest)
			return
		}
		if snapshot.BaseSceneHash == "" {
			http.Error(w, "baseSceneVersion and baseSceneHash are required", http.StatusBadRequest)
			return
		}
		if err := api.sceneStore.Save(ctx, snapshot); err != nil {
			if errors.Is(err, storage.ErrStaleSceneSnapshot) {
				http.Error(w, err.Error(), http.StatusConflict)
				return
			}
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	case http.MethodPost:
		var snapshot storage.SceneSnapshot
		r.Body = http.MaxBytesReader(w, r.Body, maxSceneBodyBytes)
		if err := json.NewDecoder(r.Body).Decode(&snapshot); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		snapshot.RoomID = roomID
		if snapshot.EncryptedBuffer == nil || snapshot.IV == nil {
			http.Error(w, "encryptedBuffer and iv are required", http.StatusBadRequest)
			return
		}
		if err := api.sceneStore.Create(ctx, snapshot); err != nil {
			if errors.Is(err, storage.ErrRoomAlreadyExists) {
				http.Error(w, err.Error(), http.StatusConflict)
				return
			}
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		identity, _ := api.identityFromRequest(r)
		ownerID := ""
		if !identity.IsGuest {
			ownerID = identity.UserID
		}
		if _, err := api.roomStore.CreateRoom(ctx, roomID, ownerID); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusCreated)
	default:
		w.Header().Set("Allow", "GET, PUT, POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (api *HTTPAPI) file(w http.ResponseWriter, r *http.Request, roomID, fileID string) {
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()

	switch r.Method {
	case http.MethodGet:
		object, info, err := api.fileStore.Get(ctx, roomID, fileID)
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
		w.Header().Set("Content-Length", strconv.FormatInt(info.Size, 10))
		http.ServeContent(w, r, fileID, info.LastModified, object)
	case http.MethodPut:
		if r.ContentLength < 0 {
			http.Error(w, "Content-Length is required", http.StatusLengthRequired)
			return
		}
		if r.ContentLength > maxFileBodyBytes {
			http.Error(w, "file is too large", http.StatusRequestEntityTooLarge)
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, maxFileBodyBytes)
		contentType := r.Header.Get("Content-Type")
		if contentType == "" {
			contentType = "application/octet-stream"
		}
		if err := api.fileStore.Put(ctx, roomID, fileID, contentType, r.Body, r.ContentLength); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (api *HTTPAPI) identityFromRequest(r *http.Request) (auth.Identity, bool) {
	token := auth.BearerToken(r.Header.Get("Authorization"))
	if token == "" {
		return auth.Identity{
			DisplayName: auth.GuestName(r.RemoteAddr + r.UserAgent()),
			IsGuest:     true,
		}, false
	}
	userID, err := api.tokenService.Verify(token)
	if err != nil {
		return auth.Identity{DisplayName: "匿名用户", IsGuest: true}, false
	}
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()
	user, err := api.userStore.Load(ctx, userID)
	if err != nil {
		return auth.Identity{DisplayName: "匿名用户", IsGuest: true}, false
	}
	return auth.Identity{
		UserID:      user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		AvatarURL:   user.AvatarURL,
		IsGuest:     false,
	}, true
}

func parseRoomPath(path string) (string, string, bool) {
	rest := strings.TrimPrefix(path, "/api/rooms/")
	if rest == path {
		return "", "", false
	}
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", false
	}
	return parts[0], parts[1], true
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
	if timeout <= 0 {
		return context.WithCancel(r.Context())
	}
	return context.WithTimeout(r.Context(), timeout)
}
