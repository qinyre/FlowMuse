package main

import (
	"context"
	"log"
	"net/http"
	"slices"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/collab"
	"flowmuse/server/internal/config"
	"flowmuse/server/internal/recognition"
	"flowmuse/server/internal/storage"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zishang520/engine.io/v2/types"
	"github.com/zishang520/socket.io/v2/socket"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), cfg.RequestTimeout)
	defer cancel()

	db, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	sceneStore := storage.NewSceneStore(db)
	if err := sceneStore.EnsureSchema(ctx); err != nil {
		log.Fatal(err)
	}
	userStore := auth.NewUserStore(db)
	if err := userStore.EnsureSchema(ctx); err != nil {
		log.Fatal(err)
	}
	roomStore := storage.NewRoomStore(db)
	if err := roomStore.EnsureSchema(ctx); err != nil {
		log.Fatal(err)
	}
	tokenService := auth.NewTokenService(cfg.AuthSecret, cfg.AuthTokenTTL)

	fileStore, err := storage.NewFileStore(
		cfg.S3Endpoint,
		cfg.S3AccessKeyID,
		cfg.S3SecretAccessKey,
		cfg.S3Bucket,
		cfg.S3UseSSL,
	)
	if err != nil {
		log.Fatal(err)
	}
	if err := fileStore.EnsureBucket(ctx); err != nil {
		log.Fatal(err)
	}
	mailer := auth.NewMailer(auth.MailConfig{
		Host:     cfg.SMTPHost,
		Port:     cfg.SMTPPort,
		Username: cfg.SMTPUsername,
		Password: cfg.SMTPPassword,
		From:     cfg.SMTPFrom,
	})
	authAPI := auth.NewHTTPAPI(
		userStore,
		fileStore,
		tokenService,
		mailer,
		cfg.PublicAppURL,
		cfg.RequestTimeout,
		cfg.EmailVerifyTTL,
		cfg.PasswordResetTTL,
	)

	socketOptions := socket.DefaultServerOptions()
	socketOptions.SetCors(&types.Cors{
		Origin:      cfg.AllowedOrigins,
		Credentials: true,
	})
	socketOptions.SetPingInterval(25 * time.Second)
	socketOptions.SetPingTimeout(20 * time.Second)
	io := socket.NewServer(nil, socketOptions)
	defer io.Close(nil)

	hub := collab.NewHub(io, sceneStore, roomStore, userStore, tokenService)
	hub.Register()

	mux := http.NewServeMux()
	mux.Handle("/socket.io/", io.ServeHandler(nil))
	authAPI.Register(mux)
	collab.NewHTTPAPI(sceneStore, fileStore, roomStore, authAPI, cfg.RequestTimeout).Register(mux)
	recognizer := recognition.NewMyScriptRecognizer(recognition.MyScriptConfig{
		AppKey:   cfg.MyScriptAppKey,
		HMACKey:  cfg.MyScriptHMACKey,
		Endpoint: cfg.MyScriptEndpoint,
		Timeout:  cfg.RecognitionTimeout,
	})
	smartLayouter := recognition.NewOpenAICompatibleSmartLayouter(
		recognition.OpenAICompatibleConfig{
			BaseURL: cfg.AIBaseURL,
			APIKey:  cfg.AIAPIKey,
			Model:   cfg.AIModel,
			Timeout: cfg.AITimeout,
		},
	)
	recognition.NewHTTPAPI(
		recognizer,
		cfg.AITimeout+10*time.Second,
		smartLayouter,
	).Register(mux)

	log.Printf("FlowMuse collab server listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, withCORS(mux, cfg.AllowedOrigins)); err != nil {
		log.Fatal(err)
	}
}

func withCORS(next http.Handler, allowedOrigins []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" || (!slices.Contains(allowedOrigins, "*") && !slices.Contains(allowedOrigins, origin)) {
			next.ServeHTTP(w, r)
			return
		}

		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Add("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Cache-Control")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
