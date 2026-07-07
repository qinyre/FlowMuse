package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Addr              string
	DatabaseURL       string
	S3Endpoint        string
	S3AccessKeyID     string
	S3SecretAccessKey string
	S3Bucket          string
	S3UseSSL          bool
	AllowedOrigins    []string
	RequestTimeout    time.Duration
}

func Load() (Config, error) {
	cfg := Config{
		Addr:           env("FLOWMUSE_ADDR", ":3000"),
		DatabaseURL:    os.Getenv("DATABASE_URL"),
		S3Endpoint:     os.Getenv("FLOWMUSE_S3_ENDPOINT"),
		S3Bucket:       os.Getenv("FLOWMUSE_S3_BUCKET"),
		S3UseSSL:       envBool("FLOWMUSE_S3_USE_SSL", true),
		AllowedOrigins: envList("FLOWMUSE_ALLOWED_ORIGINS", "*"),
		RequestTimeout: envDuration("FLOWMUSE_REQUEST_TIMEOUT", 10*time.Second),
	}
	cfg.S3AccessKeyID = os.Getenv("FLOWMUSE_S3_ACCESS_KEY_ID")
	cfg.S3SecretAccessKey = os.Getenv("FLOWMUSE_S3_SECRET_ACCESS_KEY")

	switch {
	case cfg.DatabaseURL == "":
		return cfg, errors.New("DATABASE_URL is required")
	case cfg.S3Endpoint == "":
		return cfg, errors.New("FLOWMUSE_S3_ENDPOINT is required")
	case cfg.S3Bucket == "":
		return cfg, errors.New("FLOWMUSE_S3_BUCKET is required")
	case cfg.S3AccessKeyID == "":
		return cfg, errors.New("FLOWMUSE_S3_ACCESS_KEY_ID is required")
	case cfg.S3SecretAccessKey == "":
		return cfg, errors.New("FLOWMUSE_S3_SECRET_ACCESS_KEY is required")
	}

	return cfg, nil
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envDuration(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envList(key, fallback string) []string {
	value := env(key, fallback)
	parts := strings.Split(value, ",")
	items := make([]string, 0, len(parts))
	for _, part := range parts {
		item := strings.TrimSpace(part)
		if item != "" {
			items = append(items, item)
		}
	}
	return items
}
