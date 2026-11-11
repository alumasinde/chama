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

	"github.com/chama/chama/backend/internal/audit"
	"github.com/chama/chama/backend/internal/auth"
	"github.com/chama/chama/backend/internal/config"
	"github.com/chama/chama/backend/internal/fines"
	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/loans"
	"github.com/chama/chama/backend/internal/notifications"
	"github.com/chama/chama/backend/internal/payments"
	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/db"
	"github.com/chama/chama/backend/internal/platform/logger"
	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/platform/scheduler"
	"github.com/chama/chama/backend/internal/reports"
	"github.com/chama/chama/backend/internal/rotation"
	"github.com/chama/chama/backend/internal/routes"
	"github.com/chama/chama/backend/internal/users"
	"github.com/chama/chama/backend/internal/welfare"
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
	auditSvc := audit.NewService(audit.NewRepository(pool))
	groupsSvc.SetAuditor(auditSvc)

	var paymentProvider payments.Provider = &payments.Mock{}
	if cfg.PaymentsProvider == "daraja" {
		daraja, err := payments.NewDaraja(cfg.DarajaBaseURL)
		if err != nil {
			return fmt.Errorf("payments: %w", err)
		}
		paymentProvider = daraja
	}
	if verifier, ok := paymentProvider.(groups.CredentialVerifier); ok {
		groupsSvc.SetCredentialVerifier(verifier)
	}
	paymentsSvc := payments.NewService(payments.NewRepository(pool), groupsSvc, paymentProvider, cfg.PublicBaseURL, log)
	notificationSvc := notifications.NewService(notifications.NewRepository(pool),
		notifications.NewPusher(cfg.PushProvider, cfg.FCMServerKey, log), log)
	welfareSvc := welfare.NewService(welfare.NewRepository(pool), log)
	finesSvc := fines.NewService(fines.NewRepository(pool), log)
	loansSvc := loans.NewService(loans.NewRepository(pool), log)
	rotationSvc := rotation.NewService(rotation.NewRepository(pool), log)
	reportsSvc := reports.NewService(reports.NewRepository(pool), pool, auditSvc, log)
	finesSvc.SetNotifier(notificationSvc)
	loansSvc.SetNotifier(notificationSvc)
	rotationSvc.SetNotifier(notificationSvc)

	paymentsSvc.OnSettled(func(ctx context.Context, event payments.SettledEvent) {
		if event.Status != "completed" {
			return
		}
		if event.Purpose == "welfare_contribution" {
			if err := welfareSvc.RecordSettledPayment(ctx, event.GroupID, event.UserID,
				event.AmountCents, event.TransactionID); err != nil {
				log.WarnContext(ctx, "record welfare payment", "error", err)
			}
		}
		groupID := event.GroupID
		_ = notificationSvc.Notify(ctx, notifications.Event{
			UserID: event.UserID, GroupID: &groupID, Type: "payment_received",
			Title: "Payment received", Body: money.Cents(event.AmountCents).String() + " was recorded.",
			Data:      map[string]any{"transaction_id": event.TransactionPublicID.String(), "purpose": event.Purpose},
			DedupeKey: "payment:" + event.TransactionPublicID.String(),
		})
	})

	eat := time.FixedZone("EAT", 3*60*60)
	if loc, locErr := time.LoadLocation("Africa/Nairobi"); locErr == nil {
		eat = loc
	}
	scheduler.Daily(ctx, log, "fines.evaluate", 2, 0, eat, func(ctx context.Context) error {
		result, err := finesSvc.EvaluateAll(ctx)
		if err == nil {
			log.InfoContext(ctx, "fines evaluated", "groups", result.Groups, "created", result.Created)
		}
		return err
	})
	scheduler.Daily(ctx, log, "loans.defaults", 3, 0, eat, func(ctx context.Context) error {
		marked, err := loansSvc.DefaultsAll(ctx)
		if err == nil {
			log.InfoContext(ctx, "loan default scan", "marked", marked)
		}
		return err
	})
	scheduler.Daily(ctx, log, "rotation.close", 4, 0, eat, func(ctx context.Context) error {
		closed, err := rotationSvc.CloseExpired(ctx)
		if err == nil {
			log.InfoContext(ctx, "rotation proposals closed", "count", closed)
		}
		return err
	})
	scheduler.Daily(ctx, log, "notifications.due", 8, 0, eat, func(ctx context.Context) error {
		created, err := notificationSvc.DueReminders(ctx)
		if err == nil {
			log.InfoContext(ctx, "contribution reminders created", "count", created)
		}
		return err
	})

	handler := routes.New(routes.Deps{
		Config:               cfg,
		Log:                  log,
		Pool:                 pool,
		Auth:                 authSvc,
		AuthHandler:          auth.NewHandler(authSvc, cfg.TrustProxy),
		UsersHandler:         users.NewHandler(usersSvc),
		Groups:               groupsSvc,
		GroupsHandler:        groups.NewHandler(groupsSvc),
		PaymentsHandler:      payments.NewHandler(paymentsSvc),
		FinesHandler:         fines.NewHandler(finesSvc),
		LoansHandler:         loans.NewHandler(loansSvc),
		WelfareHandler:       welfare.NewHandler(welfareSvc),
		RotationHandler:      rotation.NewHandler(rotationSvc),
		NotificationsHandler: notifications.NewHandler(notificationSvc),
		ReportsHandler:       reports.NewHandler(reportsSvc),
		AuditHandler:         audit.NewHandler(auditSvc),
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
