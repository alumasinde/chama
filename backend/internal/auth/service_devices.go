package auth

import (
	"context"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

// RegisterDevice links a phone or web session to the user for push and biometrics.
func (s *Service) RegisterDevice(ctx context.Context, user users.User, in DeviceInput) (DeviceView, error) {
	switch in.Platform {
	case "android", "ios", "web":
	default:
		return DeviceView{}, httpx.Validation(map[string]string{"platform": "Choose android, ios or web."})
	}
	if in.DeviceToken != nil && len(*in.DeviceToken) > 512 {
		return DeviceView{}, httpx.Validation(map[string]string{"device_token": "Device token is too long."})
	}
	row, err := s.repo.q.CreateDevice(ctx, store.CreateDeviceParams{
		UserID:           user.ID,
		DeviceToken:      in.DeviceToken,
		Platform:         in.Platform,
		DeviceName:       in.DeviceName,
		BiometricEnabled: in.BiometricEnabled,
	})
	if err != nil {
		return DeviceView{}, err
	}
	return DeviceView{ID: row.PublicID.String(), Platform: in.Platform,
		DeviceName: in.DeviceName, BiometricEnabled: in.BiometricEnabled}, nil
}

func (s *Service) ListDevices(ctx context.Context, user users.User) ([]DeviceView, error) {
	rows, err := s.repo.q.ListDevices(ctx, user.ID)
	if err != nil {
		return nil, err
	}
	out := make([]DeviceView, 0, len(rows))
	for _, row := range rows {
		out = append(out, DeviceView{
			ID:               row.PublicID.String(),
			Platform:         row.Platform,
			DeviceName:       row.DeviceName,
			BiometricEnabled: row.BiometricEnabled,
			LastSeenAt:       row.LastSeenAt,
		})
	}
	return out, nil
}

func (s *Service) RevokeDevice(ctx context.Context, user users.User, deviceID string) error {
	publicID, err := uuid.Parse(deviceID)
	if err != nil {
		return httpx.NotFound("Device not found.")
	}
	removed, err := s.repo.q.DeleteDevice(ctx, store.DeleteDeviceParams{
		UserID: user.ID, PublicID: publicID,
	})
	if err != nil {
		return err
	}
	if removed == 0 {
		return httpx.NotFound("Device not found.")
	}
	return nil
}

// sessionStore carries the current session id for step-up tokens and logout.
type sessionKey struct{}

func withSession(ctx context.Context, id uuid.UUID) context.Context {
	return context.WithValue(ctx, sessionKey{}, id)
}

func SessionFrom(ctx context.Context) uuid.UUID {
	if id, ok := ctx.Value(sessionKey{}).(uuid.UUID); ok {
		return id
	}
	return uuid.Nil
}
