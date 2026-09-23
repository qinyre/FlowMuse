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
	"flowmuse/server/internal/layoutrecognitionv3"
	"flowmuse/server/internal/recognition"
	"flowmuse/server/internal/social"
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
	).WithHuawei(auth.NewHuaweiClient(cfg.HuaweiClientID, cfg.HuaweiClientSecret))

	socketOptions := socket.DefaultServerOptions()
	allowCredentials := !slices.Contains(cfg.AllowedOrigins, "*")
	socketOptions.SetCors(&types.Cors{
		Origin:      socketAllowedOrigins(cfg.AllowedOrigins),
		Credentials: allowCredentials,
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
	socialStore := social.NewStore(db)
	socialEnabled := cfg.SocialEnabled
	if socialEnabled {
		if err := socialStore.EnsureSchema(ctx); err != nil {
			log.Print("social schema unavailable; social endpoints disabled")
			socialEnabled = false
		}
	}
	socialHub := social.NewHub(io, userStore, tokenService, socialEnabled)
	defer socialHub.Close()
	socialAPI := social.NewHTTPAPI(socialStore, authAPI.IdentityFromRequest, socialEnabled, cfg.RequestTimeout)
	socialAPI.Notify = socialHub.Notify
	socialAPI.Register(mux)
	collab.NewHTTPAPI(sceneStore, fileStore, roomStore, authAPI, cfg.RequestTimeout).Register(mux)
	recognizer := recognition.NewMyScriptRecognizer(recognition.MyScriptConfig{
		AppKey:   cfg.MyScriptAppKey,
		HMACKey:  cfg.MyScriptHMACKey,
		Endpoint: cfg.MyScriptEndpoint,
		Timeout:  cfg.RecognitionTimeout,
	})
	recognition.NewHTTPAPI(
		recognizer,
		cfg.AITimeout+10*time.Second,
	).Register(mux)
	registerLayoutRecognitionV3(mux, cfg)

	log.Printf("FlowMuse collab server listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, withCORS(mux, cfg.AllowedOrigins)); err != nil {
		log.Fatal(err)
	}
}

func registerLayoutRecognitionV3(mux *http.ServeMux, cfg config.Config) {
	// 独立识别链路（recognize/v3）：配置缺失时 provider 为 nil，
	// 路由仍注册、返回 503 unconfigured；旧通道初始化与注册不动。
	layoutV3Provider := layoutrecognitionv3.NewOpenAICompatProvider(
		cfg.LayoutV3BaseURL,
		cfg.LayoutV3APIKey,
		cfg.LayoutV3Model,
	)
	limits := layoutrecognitionv3.DefaultLimits()
	limits.ProviderTimeout = cfg.LayoutV3Timeout
	layoutrecognitionv3.RegisterRecognitionV3(
		mux,
		layoutrecognitionv3.NewRecognitionHandler(
			layoutV3Provider,
			limits,
		),
	)
}

func socketAllowedOrigins(origins []string) any {
	if slices.Contains(origins, "*") {
		return "*"
	}
	allowed := make([]any, len(origins))
	for index, origin := range origins {
		allowed[index] = origin
	}
	return allowed
}

func withCORS(next http.Handler, allowedOrigins []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		allowAnyOrigin := slices.Contains(allowedOrigins, "*")
		if origin == "" || (!allowAnyOrigin && !slices.Contains(allowedOrigins, origin)) {
			next.ServeHTTP(w, r)
			return
		}

		if allowAnyOrigin {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		w.Header().Add("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Cache-Control")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
