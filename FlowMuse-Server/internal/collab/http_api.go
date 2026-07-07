package collab

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"flowmuse/server/internal/storage"

	"github.com/jackc/pgx/v5"
	"github.com/minio/minio-go/v7"
)

type HTTPAPI struct {
	sceneStore     *storage.SceneStore
	fileStore      *storage.FileStore
	requestTimeout time.Duration
}

func NewHTTPAPI(sceneStore *storage.SceneStore, fileStore *storage.FileStore, requestTimeout time.Duration) *HTTPAPI {
	return &HTTPAPI{
		sceneStore:     sceneStore,
		fileStore:      fileStore,
		requestTimeout: requestTimeout,
	}
}

func (api *HTTPAPI) Register(mux *http.ServeMux) {
	mux.HandleFunc("/health", api.health)
	mux.HandleFunc("/api/rooms/", api.rooms)
}

func (api *HTTPAPI) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (api *HTTPAPI) rooms(w http.ResponseWriter, r *http.Request) {
	roomID, suffix, ok := parseRoomPath(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	if suffix == "scene" {
		api.scene(w, r, roomID)
		return
	}
	if strings.HasPrefix(suffix, "files/") {
		fileID := strings.TrimPrefix(suffix, "files/")
		if fileID == "" || strings.Contains(fileID, "/") {
			http.NotFound(w, r)
			return
		}
		api.file(w, r, roomID, fileID)
		return
	}
	http.NotFound(w, r)
}

func (api *HTTPAPI) scene(w http.ResponseWriter, r *http.Request, roomID string) {
	ctx, cancel := contextWithTimeout(r, api.requestTimeout)
	defer cancel()

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
		if err := json.NewDecoder(r.Body).Decode(&snapshot); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		snapshot.RoomID = roomID
		if snapshot.EncryptedBuffer == nil || snapshot.IV == nil {
			http.Error(w, "encryptedBuffer and iv are required", http.StatusBadRequest)
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
