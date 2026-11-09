// Package users owns platform-global identities (never full_name columns).
package users

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID              int64
	PublicID        uuid.UUID
	PhoneNumber     string
	FirstName       string
	LastName        string
	Email           *string
	PasswordHash    *string
	IsActive        bool
	PINSet          bool
	NationalIDSet   bool
	PhoneVerifiedAt *time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// DisplayName is built in the API layer; there is no stored full name.
func (u User) DisplayName() string {
	return u.FirstName + " " + u.LastName
}

type View struct {
	ID            string    `json:"id"`
	PhoneNumber   string    `json:"phone_number"`
	FirstName     string    `json:"first_name"`
	LastName      string    `json:"last_name"`
	DisplayName   string    `json:"display_name"`
	Email         *string   `json:"email"`
	IsActive      bool      `json:"is_active"`
	PINSet        bool      `json:"pin_set"`
	HasPassword   bool      `json:"has_password"`
	NationalIDSet bool      `json:"national_id_set"`
	PhoneVerified bool      `json:"phone_verified"`
	CreatedAt     time.Time `json:"created_at"`
}

func (u User) View() View {
	return View{
		ID:            u.PublicID.String(),
		PhoneNumber:   u.PhoneNumber,
		FirstName:     u.FirstName,
		LastName:      u.LastName,
		DisplayName:   u.DisplayName(),
		Email:         u.Email,
		IsActive:      u.IsActive,
		PINSet:        u.PINSet,
		HasPassword:   u.PasswordHash != nil && *u.PasswordHash != "",
		NationalIDSet: u.NationalIDSet,
		PhoneVerified: u.PhoneVerifiedAt != nil,
		CreatedAt:     u.CreatedAt,
	}
}

type UpdateProfileInput struct {
	FirstName  string  `json:"first_name"`
	LastName   string  `json:"last_name"`
	Email      *string `json:"email"`
	NationalID *string `json:"national_id"`
}
