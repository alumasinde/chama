// Package audit stores an append-only, group-scoped trail of sensitive actions.
package audit

import (
	"time"

	"github.com/chama/chama/backend/internal/auditlog"
)

type Entry = auditlog.Entry

type Writer = auditlog.Writer

type Filter struct {
	Action     string
	EntityType string
	From       *time.Time
	To         *time.Time
	Limit      int32
}

type View struct {
	ID             string    `json:"id"`
	Actor          string    `json:"actor"`
	Action         string    `json:"action"`
	EntityType     string    `json:"entity_type"`
	EntityPublicID *string   `json:"entity_public_id,omitempty"`
	Before         any       `json:"before"`
	After          any       `json:"after"`
	CreatedAt      time.Time `json:"created_at"`
}
