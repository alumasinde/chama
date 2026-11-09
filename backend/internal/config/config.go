// Package config loads and validates environment configuration once at boot.
package config

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	AppEnv          string
	HTTPAddr        string
	PublicBaseURL   string
	DatabaseURL     string
	LogLevel        string
	TrustProxy      bool
	ShutdownTimeout time.Duration

	JWTSecret       string
	AccessTTL       time.Duration
	StepUpTTL       time.Duration
	RegistrationTTL time.Duration
	RefreshTTL      time.Duration

	EncryptionKey  []byte
	OTPHashKey     []byte
	OTPTTL         time.Duration
	OTPMaxAttempts int32

	PINMaxAttempts  int32
	PINLockDuration time.Duration

	SMSProvider      string
	PaymentsProvider string
	DarajaBaseURL    string
}

// Load reads env vars, applies development defaults, and refuses unsafe production settings.
func Load() (*Config, error) {
	env := getenv("APP_ENV", "development")
	if env != "development" && env != "test" && env != "production" {
		return nil, fmt.Errorf("APP_ENV must be development, test or production")
	}
	dev := env != "production"

	cfg := &Config{
		AppEnv:          env,
		HTTPAddr:        getenv("HTTP_ADDR", ":8080"),
		PublicBaseURL:   getenv("PUBLIC_BASE_URL", "http://localhost:8080"),
		DatabaseURL:     getenv("DATABASE_URL", "postgres://chama:chama@localhost:5434/chama?sslmode=disable"),
		LogLevel:        getenv("LOG_LEVEL", "info"),
		TrustProxy:      getbool("TRUST_PROXY", false),
		ShutdownTimeout: getduration("SHUTDOWN_TIMEOUT", 15*time.Second),
		JWTSecret:       getenv("JWT_SECRET", ""),
		SMSProvider:     getenv("SMS_PROVIDER", "console"),
		DarajaBaseURL:   getenv("DARAJA_BASE_URL", "https://sandbox.safaricom.co.ke"),
	}

	cfg.PaymentsProvider = getenv("PAYMENTS_PROVIDER", "")
	if cfg.PaymentsProvider == "" {
		cfg.PaymentsProvider = "daraja"
		if dev {
			cfg.PaymentsProvider = "mock"
		}
	}

	var errs []error
	var err error
	if cfg.AccessTTL, err = getdurationErr("ACCESS_TTL", 15*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if cfg.StepUpTTL, err = getdurationErr("STEP_UP_TTL", 5*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if cfg.RegistrationTTL, err = getdurationErr("REGISTRATION_TTL", 15*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if cfg.RefreshTTL, err = getdurationErr("REFRESH_TTL", 30*24*time.Hour); err != nil {
		errs = append(errs, err)
	}
	if cfg.OTPTTL, err = getdurationErr("OTP_TTL", 10*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if cfg.PINLockDuration, err = getdurationErr("PIN_LOCK_DURATION", 15*time.Minute); err != nil {
		errs = append(errs, err)
	}
	cfg.OTPMaxAttempts = getint32("OTP_MAX_ATTEMPTS", 5)
	cfg.PINMaxAttempts = getint32("PIN_MAX_ATTEMPTS", 5)

	if cfg.JWTSecret == "" {
		if !dev {
			errs = append(errs, errors.New("JWT_SECRET is required in production"))
		}
		cfg.JWTSecret = "dev-only-jwt-secret-change-me-0123456789abcdef"
	}
	if len(cfg.JWTSecret) < 32 {
		errs = append(errs, errors.New("JWT_SECRET must be at least 32 characters"))
	}
	if cfg.EncryptionKey, err = getkey("ENCRYPTION_KEY", dev); err != nil {
		errs = append(errs, err)
	}
	if len(cfg.OTPHashKey) == 0 {
		cfg.OTPHashKey = []byte(getenv("OTP_HASH_KEY", "dev-only-otp-hash-key-change-me"))
	}
	if !dev && cfg.SMSProvider == "console" {
		errs = append(errs, errors.New("SMS_PROVIDER=console is not allowed in production"))
	}
	if cfg.SMSProvider != "console" && cfg.SMSProvider != "mock" {
		errs = append(errs, fmt.Errorf("SMS_PROVIDER %q is not supported yet", cfg.SMSProvider))
	}
	if cfg.PaymentsProvider != "daraja" && cfg.PaymentsProvider != "mock" {
		errs = append(errs, fmt.Errorf("PAYMENTS_PROVIDER must be daraja or mock"))
	}
	if !dev && cfg.PaymentsProvider == "mock" {
		errs = append(errs, errors.New("PAYMENTS_PROVIDER=mock is not allowed in production"))
	}
	if cfg.OTPMaxAttempts < 1 || cfg.PINMaxAttempts < 1 {
		errs = append(errs, errors.New("OTP_MAX_ATTEMPTS and PIN_MAX_ATTEMPTS must be positive"))
	}
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	return cfg, nil
}

func (c *Config) IsDevelopment() bool { return c.AppEnv == "development" }

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

// getint32 scans straight into int32 so out-of-range values fall back safely.
func getint32(key string, fallback int32) int32 {
	raw := getenv(key, "")
	if raw == "" {
		return fallback
	}
	var n int32
	if _, err := fmt.Sscanf(raw, "%d", &n); err != nil {
		return fallback
	}
	return n
}

func getbool(key string, fallback bool) bool {
	raw := getenv(key, "")
	if raw == "" {
		return fallback
	}
	b, err := strconv.ParseBool(raw)
	if err != nil {
		return fallback
	}
	return b
}

func getduration(key string, fallback time.Duration) time.Duration {
	d, err := getdurationErr(key, fallback)
	if err != nil {
		return fallback
	}
	return d
}

func getdurationErr(key string, fallback time.Duration) (time.Duration, error) {
	raw := getenv(key, "")
	if raw == "" {
		return fallback, nil
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be a duration such as 15m: %w", key, err)
	}
	return d, nil
}

// getkey decodes a base64 AES-256 key; development falls back to a fixed key.
func getkey(key string, dev bool) ([]byte, error) {
	raw := getenv(key, "")
	if raw == "" {
		if !dev {
			return nil, fmt.Errorf("%s is required in production (base64, 32 bytes)", key)
		}
		raw = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
	}
	b, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return nil, fmt.Errorf("%s must be valid base64: %w", key, err)
	}
	if len(b) != 32 {
		return nil, fmt.Errorf("%s must decode to exactly 32 bytes, got %d", key, len(b))
	}
	return b, nil
}
