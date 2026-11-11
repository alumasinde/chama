package groups

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
)

const defaultReferenceTemplate = "CHAMA-{member_short}-{period}"

var validShortcodeTypes = map[string]bool{"paybill": true, "till": true}
var validEnvironments = map[string]bool{"sandbox": true, "production": true}

// CredentialVerifier is the narrow seam to the payment provider for setup checks.
type CredentialVerifier interface {
	VerifyCredentials(ctx context.Context, environment, consumerKey, consumerSecret string) error
}

func (s *Service) PaymentSettings(ctx context.Context, scope Scope) (PaymentSettingsView, error) {
	settings, err := s.repo.PaymentSettings(ctx, scope.Group.ID)
	if errors.Is(err, ErrNotFound) {
		return PaymentSettingsView{Configured: false}, nil
	}
	if err != nil {
		return PaymentSettingsView{}, err
	}
	return s.paymentView(scope.Group.ID, settings, ""), nil
}

// PutPaymentSettings merges supplied fields, seals secrets, and returns the callback URL once.
func (s *Service) PutPaymentSettings(ctx context.Context, scope Scope, actorID int64, in PaymentSettingsInput) (PaymentSettingsView, error) {
	existing, err := s.repo.PaymentSettings(ctx, scope.Group.ID)
	if errors.Is(err, ErrNotFound) {
		existing = PaymentSettings{}
	} else if err != nil {
		return PaymentSettingsView{}, err
	}

	fields := map[string]string{}
	shortcodeType := firstNonEmpty(strings.TrimSpace(in.ShortcodeType), existing.ShortcodeType)
	if !validShortcodeTypes[shortcodeType] {
		fields["shortcode_type"] = "Choose paybill or till."
	}
	shortcode := firstNonEmpty(strings.TrimSpace(in.Shortcode), existing.Shortcode)
	if !digitsBetween(shortcode, 4, 9) {
		fields["shortcode"] = "Enter the 4 to 9 digit M-Pesa shortcode."
	}
	environment := firstNonEmpty(strings.TrimSpace(in.DarajaEnvironment), existing.DarajaEnvironment)
	if !validEnvironments[environment] {
		fields["daraja_environment"] = "Choose sandbox or production."
	}
	template := defaultReferenceTemplate
	if in.AccountReferenceTemplate != nil {
		template = strings.TrimSpace(*in.AccountReferenceTemplate)
	} else if existing.AccountReferenceTemplate != "" {
		template = existing.AccountReferenceTemplate
	}
	if template == "" || len(template) > 64 {
		fields["account_reference_template"] = "Use 1 to 64 characters."
	}

	keyEnc, keyErr := s.sealOrKeep(in.ConsumerKey, existing.ConsumerKeyEnc, scope.Group.ID, "consumer_key")
	if keyErr != nil {
		fields["consumer_key"] = "Enter the consumer key from the Daraja portal."
	}
	secretEnc, secretErr := s.sealOrKeep(in.ConsumerSecret, existing.ConsumerSecretEnc, scope.Group.ID, "consumer_secret")
	if secretErr != nil {
		fields["consumer_secret"] = "Enter the consumer secret from the Daraja portal."
	}
	passkeyEnc, passErr := s.sealOrKeep(in.Passkey, existing.PasskeyEnc, scope.Group.ID, "passkey")
	if passErr != nil {
		fields["passkey"] = "Enter the Lipa na M-Pesa passkey."
	}
	if len(fields) > 0 {
		return PaymentSettingsView{}, httpx.Validation(fields)
	}

	callbackSecretEnc := existing.CallbackSecretEnc
	callbackSecret := ""
	if len(callbackSecretEnc) == 0 {
		raw, tokenErr := crypto.Token(24)
		if tokenErr != nil {
			return PaymentSettingsView{}, tokenErr
		}
		callbackSecret = raw
		callbackSecretEnc, err = s.cipher.Seal([]byte(raw), aad(scope.Group.ID, "callback_secret"))
		if err != nil {
			return PaymentSettingsView{}, err
		}
	}

	if err := s.repo.UpsertPaymentSettings(ctx, store.UpsertPaymentSettingsParams{
		GroupID:                  scope.Group.ID,
		ShortcodeType:            shortcodeType,
		Shortcode:                shortcode,
		AccountReferenceTemplate: template,
		DarajaEnvironment:        environment,
		DarajaConsumerKeyEnc:     keyEnc,
		DarajaConsumerSecretEnc:  secretEnc,
		DarajaPasskeyEnc:         passkeyEnc,
		CallbackSecretEnc:        callbackSecretEnc,
		UpdatedBy:                &actorID,
	}); err != nil {
		return PaymentSettingsView{}, err
	}

	if callbackSecret == "" {
		callbackSecret = string(s.openSecret(existing.CallbackSecretEnc, scope.Group.ID, "callback_secret"))
	}
	settings := PaymentSettings{
		ShortcodeType:            shortcodeType,
		Shortcode:                shortcode,
		AccountReferenceTemplate: template,
		DarajaEnvironment:        environment,
		ConsumerKeyEnc:           keyEnc,
		ConsumerSecretEnc:        secretEnc,
		PasskeyEnc:               passkeyEnc,
		CallbackSecretEnc:        callbackSecretEnc,
		IsVerified:               false,
		UpdatedAt:                time.Now().UTC(),
	}
	return s.paymentView(scope.Group.ID, settings, s.callbackURL(scope.Group, callbackSecret)), nil
}

// VerifyPaymentSettings proves the saved Daraja keys work and records the result.
func (s *Service) VerifyPaymentSettings(ctx context.Context, scope Scope, actorID int64) (PaymentSettingsView, error) {
	settings, err := s.repo.PaymentSettings(ctx, scope.Group.ID)
	if errors.Is(err, ErrNotFound) {
		return PaymentSettingsView{}, httpx.Unprocessable("payment_settings_missing",
			"Save the chama's M-Pesa details first.")
	}
	if err != nil {
		return PaymentSettingsView{}, err
	}
	if s.verifier == nil {
		return PaymentSettingsView{}, httpx.NewError(503, "verification_unavailable",
			"M-Pesa verification is not configured on this server.")
	}
	key := string(s.openSecret(settings.ConsumerKeyEnc, scope.Group.ID, "consumer_key"))
	secret := string(s.openSecret(settings.ConsumerSecretEnc, scope.Group.ID, "consumer_secret"))
	if key == "" || secret == "" {
		return PaymentSettingsView{}, httpx.NewError(500, "credentials_unreadable",
			"The saved M-Pesa keys could not be read. Save them again.")
	}
	if err := s.verifier.VerifyCredentials(ctx, settings.DarajaEnvironment, key, secret); err != nil {
		s.log.WarnContext(ctx, "daraja verification failed", "group_id", scope.Group.ID, "error", err)
		return PaymentSettingsView{}, httpx.Unprocessable("mpesa_verification_failed",
			"Daraja rejected these keys. Check that the environment, consumer key and secret come from the same Daraja app.")
	}
	if err := s.repo.MarkPaymentSettingsVerified(ctx, scope.Group.ID, actorID); err != nil {
		return PaymentSettingsView{}, err
	}
	verifiedAt := time.Now().UTC()
	settings.IsVerified = true
	settings.VerifiedAt = &verifiedAt
	callbackSecret := string(s.openSecret(settings.CallbackSecretEnc, scope.Group.ID, "callback_secret"))
	return s.paymentView(scope.Group.ID, settings, s.callbackURL(scope.Group, callbackSecret)), nil
}

func (s *Service) paymentView(groupID int64, settings PaymentSettings, callbackURL string) PaymentSettingsView {
	return PaymentSettingsView{
		Configured:               true,
		ShortcodeType:            settings.ShortcodeType,
		Shortcode:                settings.Shortcode,
		AccountReferenceTemplate: settings.AccountReferenceTemplate,
		DarajaEnvironment:        settings.DarajaEnvironment,
		ConsumerKeyMasked:        s.mask(settings.ConsumerKeyEnc, groupID, "consumer_key"),
		ConsumerSecretMasked:     s.mask(settings.ConsumerSecretEnc, groupID, "consumer_secret"),
		PasskeyMasked:            s.mask(settings.PasskeyEnc, groupID, "passkey"),
		IsVerified:               settings.IsVerified,
		VerifiedAt:               settings.VerifiedAt,
		UpdatedAt:                &settings.UpdatedAt,
		CallbackURL:              callbackURL,
	}
}

func (s *Service) callbackURL(group Group, secret string) string {
	if secret == "" {
		return ""
	}
	base := strings.TrimRight(s.opts.PublicBaseURL, "/")
	return fmt.Sprintf("%s/api/v1/payments/mpesa/callback/%s/%s", base, group.PublicID, secret)
}

func (s *Service) sealOrKeep(provided *string, existing []byte, groupID int64, column string) ([]byte, error) {
	if provided == nil || strings.TrimSpace(*provided) == "" {
		if len(existing) == 0 {
			return nil, errors.New("missing secret")
		}
		return existing, nil
	}
	value := strings.TrimSpace(*provided)
	if len(value) < 8 || len(value) > 512 {
		return nil, errors.New("secret length out of range")
	}
	return s.cipher.Seal([]byte(value), aad(groupID, column))
}

func (s *Service) mask(enc []byte, groupID int64, column string) string {
	if len(enc) == 0 {
		return ""
	}
	return maskSecret(string(s.openSecret(enc, groupID, column)))
}

func (s *Service) openSecret(enc []byte, groupID int64, column string) []byte {
	plain, err := s.cipher.Open(enc, aad(groupID, column))
	if err != nil {
		s.log.Error("payment settings decrypt failed", "group_id", groupID, "column", column)
		return nil
	}
	return plain
}

func maskSecret(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= 4 {
		return "••••"
	}
	return "••••" + value[len(value)-4:]
}

func aad(groupID int64, column string) []byte {
	return []byte(fmt.Sprintf("group_payment_settings:%d:%s", groupID, column))
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func digitsBetween(s string, min, max int) bool {
	if len(s) < min || len(s) > max {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
