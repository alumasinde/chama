// Package auditlog holds the dependency-neutral audit writer contract.
package auditlog

import (
	"context"

	"github.com/google/uuid"
)

// Entry is written by a module after a successful mutation.
type Entry struct {
	GroupID        int64
	ActorID        *int64
	Action         string
	EntityType     string
	EntityID       *int64
	EntityPublicID *uuid.UUID
	Before         any
	After          any
	IPAddress      string
	RequestID      string
}

// Writer is implemented by audit.Service and by test doubles.
type Writer interface {
	Record(ctx context.Context, entry Entry) error
}
