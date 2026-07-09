package collab

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
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
var ownerKeyHashPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type HTTPAPI struct {
	sceneStore     *storage.SceneStore
	fileStore      *storage.FileStore
	roomStore      *storage.RoomStore
	identitySource authIdentitySource
	requestTimeout time.Duration
}

type authIdentitySource interface {
	IdentityFromRequest(*http.Request) (auth.Identity, bool)
}

func NewHTTPAPI(
	sceneStore *storage.SceneStore,
	fileStore *storage.FileStore,
	roomStore *storage.RoomStore,
	identitySource authIdentitySource,
	requestTimeout time.Duration,
) *HTTPAPI {
	return &HTTPAPI{
		sceneStore:     sceneStore,
		fileStore:      fileStore,
		roomStore:      roomStore,
		identitySource: identitySource,
		requestTimeout: requestTimeout,
	}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/health", api.health)
	mux.HandleFunc("/api/rooms", api.roomsRoot)
	mux.HandleFunc("/api/rooms/", api.rooms)
}

func (api *HTTPAPI) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func hashOwnerKey(roomID, ownerKey string) string {
	if ownerKey == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(roomID + ":" + ownerKey))
	return hex.EncodeToString(sum[:])
}

func (api *HTTPAPI) roomsRoot(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		ctx, cancel := contextWithTimeout(r, api.requestTimeout)
		defer cancel()
		var request struct {
			RoomID       string `json:"roomId"`
			OwnerKeyHash string `json:"ownerKeyHash"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if !safeIDPattern.MatchString(request.RoomID) {
			http.Error(w, "invalid roomId", http.StatusBadRequest)
			return
		}
		if request.OwnerKeyHash != "" && !ownerKeyHashPattern.MatchString(request.OwnerKeyHash) {
			http.Error(w, "invalid ownerKeyHash", http.StatusBadRequest)
			return
		}
		identity, _ := api.identityFromRequest(r)
		ownerID := ""
		if !identity.IsGuest {
			ownerID = identity.UserID
		}
		metadata, err := api.roomStore.CreateRoom(ctx, request.RoomID, ownerID, request.OwnerKeyHash)
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
	var request struct {
		OwnerKey string `json:"ownerKey"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	identity, _ := api.identityFromRequest(r)
	ownerKeyHash := hashOwnerKey(roomID, request.OwnerKey)
	metadata, err := api.roomStore.EndRoom(ctx, roomID, identity.UserID, ownerKeyHash)
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
		if snapshot.OwnerKeyHash != "" && !ownerKeyHashPattern.MatchString(snapshot.OwnerKeyHash) {
			http.Error(w, "invalid ownerKeyHash", http.StatusBadRequest)
			return
		}
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
		if snapshot.OwnerKeyHash != "" && !ownerKeyHashPattern.MatchString(snapshot.OwnerKeyHash) {
			http.Error(w, "invalid ownerKeyHash", http.StatusBadRequest)
			return
		}
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
		if _, err := api.roomStore.CreateRoom(ctx, roomID, ownerID, snapshot.OwnerKeyHash); err != nil {
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
	return api.identitySource.IdentityFromRequest(r)
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
