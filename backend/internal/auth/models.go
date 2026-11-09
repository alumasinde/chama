package auth

import (
	"time"

	"github.com/chama/chama/backend/internal/users"
)

const (
	PurposeLogin        = "login"
	PurposeRegistration = "registration"
	PurposePINReset     = "pin_reset"
)

type RequestOTPInput struct {
	PhoneNumber string `json:"phone_number"`
	Purpose     string `json:"purpose"`
}

type RequestOTPResult struct {
	ExpiresIn   int    `json:"expires_in"`
	ResendAfter int    `json:"resend_after"`
	DevCode     string `json:"dev_code,omitempty"`
}

type VerifyOTPInput struct {
	PhoneNumber string `json:"phone_number"`
	Code        string `json:"code"`
	Purpose     string `json:"purpose"`
}

type VerifyOTPResult struct {
	NewUser           bool     `json:"new_user"`
	RegistrationToken string   `json:"registration_token,omitempty"`
	ExpiresIn         int      `json:"expires_in,omitempty"`
	Session           *Session `json:"session,omitempty"`
}

type RegisterInput struct {
	FirstName  string  `json:"first_name"`
	LastName   string  `json:"last_name"`
	PIN        string  `json:"pin"`
	Email      *string `json:"email"`
	NationalID *string `json:"national_id"`
	Password   *string `json:"password"`
}

type LoginInput struct {
	PhoneNumber string `json:"phone_number"`
	Password    string `json:"password"`
}

type RefreshInput struct {
	RefreshToken string `json:"refresh_token"`
}

type PINVerifyInput struct {
	PIN string `json:"pin"`
}

type PINVerifyResult struct {
	StepUpToken string `json:"step_up_token"`
	ExpiresIn   int    `json:"expires_in"`
}

type ResetPINInput struct {
	PhoneNumber string `json:"phone_number"`
	Code        string `json:"code"`
	NewPIN      string `json:"new_pin"`
}

type ChangePINInput struct {
	CurrentPIN string `json:"current_pin"`
	NewPIN     string `json:"new_pin"`
}

type SetPasswordInput struct {
	PIN      string `json:"pin"`
	Password string `json:"password"`
}

type DeviceInput struct {
	Platform         string  `json:"platform"`
	DeviceToken      *string `json:"device_token"`
	DeviceName       *string `json:"device_name"`
	BiometricEnabled bool    `json:"biometric_enabled"`
}

type DeviceView struct {
	ID               string    `json:"id"`
	Platform         string    `json:"platform"`
	DeviceName       *string   `json:"device_name"`
	BiometricEnabled bool      `json:"biometric_enabled"`
	LastSeenAt       time.Time `json:"last_seen_at"`
}

// Session is the token pair returned by every successful sign-in.
type Session struct {
	AccessToken      string     `json:"access_token"`
	RefreshToken     string     `json:"refresh_token"`
	TokenType        string     `json:"token_type"`
	ExpiresIn        int        `json:"expires_in"`
	RefreshExpiresIn int        `json:"refresh_expires_in"`
	User             users.View `json:"user"`
}

type clientMeta struct {
	userAgent string
	ip        string
}
