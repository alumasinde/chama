package groups

import (
	"context"
	"fmt"

	"github.com/google/uuid"
)

// Credentials are decrypted only inside the payments path; they never reach a response.
type Credentials struct {
	ShortcodeType            string
	Shortcode                string
	AccountReferenceTemplate string
	Environment              string
	ConsumerKey              string
	ConsumerSecret           string
	Passkey                  string
	CallbackSecret           string
}

func (s *Service) Find(ctx context.Context, publicID uuid.UUID) (Group, error) {
	return s.repo.GetByPublicID(ctx, publicID)
}

func (s *Service) Credentials(ctx context.Context, groupID int64) (Credentials, error) {
	settings, err := s.repo.PaymentSettings(ctx, groupID)
	if err != nil {
		return Credentials{}, err
	}
	key, err := s.decryptRequired(settings.ConsumerKeyEnc, groupID, "consumer_key")
	if err != nil {
		return Credentials{}, err
	}
	secret, err := s.decryptRequired(settings.ConsumerSecretEnc, groupID, "consumer_secret")
	if err != nil {
		return Credentials{}, err
	}
	passkey, err := s.decryptRequired(settings.PasskeyEnc, groupID, "passkey")
	if err != nil {
		return Credentials{}, err
	}
	callback, err := s.decryptRequired(settings.CallbackSecretEnc, groupID, "callback_secret")
	if err != nil {
		return Credentials{}, err
	}
	return Credentials{
		ShortcodeType:            settings.ShortcodeType,
		Shortcode:                settings.Shortcode,
		AccountReferenceTemplate: settings.AccountReferenceTemplate,
		Environment:              settings.DarajaEnvironment,
		ConsumerKey:              key,
		ConsumerSecret:           secret,
		Passkey:                  passkey,
		CallbackSecret:           callback,
	}, nil
}

func (s *Service) CallbackSecret(ctx context.Context, groupID int64) (string, error) {
	settings, err := s.repo.PaymentSettings(ctx, groupID)
	if err != nil {
		return "", err
	}
	return s.decryptRequired(settings.CallbackSecretEnc, groupID, "callback_secret")
}

func (s *Service) decryptRequired(enc []byte, groupID int64, column string) (string, error) {
	plain, err := s.cipher.Open(enc, aad(groupID, column))
	if err != nil {
		return "", fmt.Errorf("decrypt %s for group %d: %w", column, groupID, err)
	}
	return string(plain), nil
}
