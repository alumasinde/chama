package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/chama/chama/backend/internal/auth"
	"github.com/chama/chama/backend/internal/config"
	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/db"
	"github.com/chama/chama/backend/internal/platform/logger"
	"github.com/chama/chama/backend/internal/routes"
	"github.com/chama/chama/backend/internal/users"
)

func main() {
	if err := run(); err != nil {
		slog.Error("startup failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}
	log := logger.New(cfg.LogLevel, cfg.AppEnv)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := db.Ping(ctx, pool); err != nil {
		return fmt.Errorf("database unreachable: %w", err)
	}

	cipher, err := crypto.NewCipher(cfg.EncryptionKey)
	if err != nil {
		return err
	}
	sms, err := auth.NewSMS(cfg.SMSProvider, log)
	if err != nil {
		return err
	}

	usersSvc := users.NewService(users.NewRepository(pool), cipher)
	authSvc, err := auth.NewService(auth.Options{
		JWTSecret:       cfg.JWTSecret,
		AccessTTL:       cfg.AccessTTL,
		StepUpTTL:       cfg.StepUpTTL,
		RegistrationTTL: cfg.RegistrationTTL,
		RefreshTTL:      cfg.RefreshTTL,
		OTPTTL:          cfg.OTPTTL,
		OTPMaxAttempts:  cfg.OTPMaxAttempts,
		PINMaxAttempts:  cfg.PINMaxAttempts,
		PINLock:         cfg.PINLockDuration,
		OTPHashKey:      cfg.OTPHashKey,
		DevMode:         cfg.IsDevelopment(),
	}, auth.NewRepository(pool), usersSvc, cipher, sms, log)
	if err != nil {
		return err
	}

	groupsSvc := groups.NewService(groups.NewRepository(pool), cipher, log,
		groups.Options{PublicBaseURL: cfg.PublicBaseURL})

	handler := routes.New(routes.Deps{
		Config:        cfg,
		Log:           log,
		Pool:          pool,
		Auth:          authSvc,
		AuthHandler:   auth.NewHandler(authSvc, cfg.TrustProxy),
		UsersHandler:  users.NewHandler(usersSvc),
		GroupsHandler: groups.NewHandler(groupsSvc),
	})

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       20 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() {
		log.Info("server listening", "addr", cfg.HTTPAddr, "env", cfg.AppEnv)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
		}
	}()

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	log.Info("shutting down")
	return srv.Shutdown(shutdownCtx)
}
