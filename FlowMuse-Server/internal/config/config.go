package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Addr               string
	DatabaseURL        string
	S3Endpoint         string
	S3AccessKeyID      string
	S3SecretAccessKey  string
	S3Bucket           string
	S3UseSSL           bool
	AllowedOrigins     []string
	RequestTimeout     time.Duration
	AuthSecret         string
	AuthTokenTTL       time.Duration
	PublicAppURL       string
	EmailVerifyTTL     time.Duration
	PasswordResetTTL   time.Duration
	SMTPHost           string
	SMTPPort           int
	SMTPUsername       string
	SMTPPassword       string
	SMTPFrom           string
	MyScriptAppKey     string
	MyScriptHMACKey    string
	MyScriptEndpoint   string
	RecognitionTimeout time.Duration
	AIBaseURL          string
	AIAPIKey           string
	AIModel            string
	AITimeout          time.Duration
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
		AuthSecret:     os.Getenv("FLOWMUSE_AUTH_SECRET"),
		AuthTokenTTL:   envDuration("FLOWMUSE_AUTH_TOKEN_TTL", 30*24*time.Hour),
		PublicAppURL:   env("FLOWMUSE_PUBLIC_APP_URL", "http://127.0.0.1:3000"),
		EmailVerifyTTL: envDuration("FLOWMUSE_EMAIL_VERIFY_TTL", 24*time.Hour),
		PasswordResetTTL: envDuration(
			"FLOWMUSE_PASSWORD_RESET_TTL",
			30*time.Minute,
		),
		SMTPHost:         os.Getenv("FLOWMUSE_SMTP_HOST"),
		SMTPPort:         envInt("FLOWMUSE_SMTP_PORT", 1025),
		SMTPUsername:     os.Getenv("FLOWMUSE_SMTP_USERNAME"),
		SMTPPassword:     os.Getenv("FLOWMUSE_SMTP_PASSWORD"),
		SMTPFrom:         env("FLOWMUSE_SMTP_FROM", "FlowMuse <noreply@flowmuse.local>"),
		MyScriptAppKey:   os.Getenv("FLOWMUSE_MYSCRIPT_APP_KEY"),
		MyScriptHMACKey:  os.Getenv("FLOWMUSE_MYSCRIPT_HMAC_KEY"),
		MyScriptEndpoint: env("FLOWMUSE_MYSCRIPT_ENDPOINT", "https://cloud.myscript.com/api/v4.0/iink/batch"),
		RecognitionTimeout: envDuration(
			"FLOWMUSE_RECOGNITION_TIMEOUT",
			20*time.Second,
		),
		AIBaseURL: env("FLOWMUSE_AI_BASE_URL", "https://ark.cn-beijing.volces.com/api/v3"),
		AIAPIKey:  envFirst("FLOWMUSE_AI_API_KEY", "ARK_API_KEY"),
		AIModel:   env("FLOWMUSE_AI_MODEL", "doubao-seed-2-1-turbo-260628"),
		AITimeout: envDuration("FLOWMUSE_AI_TIMEOUT", 60*time.Second),
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
	if cfg.AuthSecret == "" {
		cfg.AuthSecret = "flowmuse-dev-auth-secret:" + cfg.DatabaseURL
	}

	return cfg, nil
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envFirst(keys ...string) string {
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return ""
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

func envInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
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
