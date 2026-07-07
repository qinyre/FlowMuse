package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"flowmuse/server/internal/collab"
	"flowmuse/server/internal/config"
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

	socketOptions := socket.DefaultServerOptions()
	socketOptions.SetCors(&types.Cors{
		Origin:      cfg.AllowedOrigins,
		Credentials: true,
	})
	socketOptions.SetPingInterval(25 * time.Second)
	socketOptions.SetPingTimeout(20 * time.Second)
	io := socket.NewServer(nil, socketOptions)
	defer io.Close(nil)

	hub := collab.NewHub(io, sceneStore)
	hub.Register()

	mux := http.NewServeMux()
	mux.Handle("/socket.io/", io.ServeHandler(nil))
	collab.NewHTTPAPI(sceneStore, fileStore, cfg.RequestTimeout).Register(mux)

	log.Printf("FlowMuse collab server listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, mux); err != nil {
		log.Fatal(err)
	}
}
