package notifications

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/google/uuid"
)

// fakeRepo embeds the real repository only to satisfy the unexercised methods.
type fakeRepo struct {
	*Repository
	seen      map[string]bool
	inserts   int
	pushed    int
	tokens    []string
	insertErr error
}

func (f *fakeRepo) Insert(_ context.Context, e Event) (uuid.UUID, bool, error) {
	if f.insertErr != nil {
		return uuid.Nil, false, f.insertErr
	}
	if f.seen == nil {
		f.seen = map[string]bool{}
	}
	if f.seen[e.DedupeKey] {
		return uuid.Nil, false, nil
	}
	f.seen[e.DedupeKey] = true
	f.inserts++
	return uuid.New(), true, nil
}

func (f *fakeRepo) Tokens(context.Context, int64) ([]string, error) { return f.tokens, nil }

func (f *fakeRepo) MarkPushed(context.Context, int64, uuid.UUID) error {
	f.pushed++
	return nil
}

type fakePusher struct {
	calls  int
	tokens []string
	msg    Message
	err    error
}

func (p *fakePusher) Name() string { return "fake" }

func (p *fakePusher) Push(_ context.Context, tokens []string, msg Message) error {
	p.calls++
	p.tokens = append([]string(nil), tokens...)
	p.msg = msg
	return p.err
}

func testService(repo *fakeRepo, push Pusher) *Service {
	return NewService(repo, push, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func rotationEvent() Event {
	return Event{
		UserID: 7, Type: "rotation_turn", Title: "Rotation order set",
		Body: "You are number 2.", Data: map[string]any{"position": 2},
		DedupeKey: "rotation:cycle:start:member",
	}
}

func TestNotifyPushesOncePerDedupeKey(t *testing.T) {
	repo := &fakeRepo{tokens: []string{"device-1", "device-2"}}
	push := &fakePusher{}
	svc := testService(repo, push)

	for i := 0; i < 2; i++ {
		if err := svc.Notify(context.Background(), rotationEvent()); err != nil {
			t.Fatalf("notify: %v", err)
		}
	}

	if repo.inserts != 1 {
		t.Fatalf("inserts = %d, want 1", repo.inserts)
	}
	if push.calls != 1 {
		t.Fatalf("push calls = %d, want 1", push.calls)
	}
	if len(push.tokens) != 2 || push.tokens[0] != "device-1" {
		t.Fatalf("pushed tokens = %v", push.tokens)
	}
	if push.msg.Title != "Rotation order set" || push.msg.Data["position"] != "2" {
		t.Fatalf("pushed message = %+v", push.msg)
	}
	if repo.pushed != 1 {
		t.Fatalf("mark pushed = %d, want 1", repo.pushed)
	}
}

func TestNotifySkipsPushWithoutDevices(t *testing.T) {
	repo := &fakeRepo{}
	push := &fakePusher{}
	svc := testService(repo, push)

	if err := svc.Notify(context.Background(), rotationEvent()); err != nil {
		t.Fatalf("notify: %v", err)
	}
	if push.calls != 0 {
		t.Fatalf("push calls = %d, want 0", push.calls)
	}
}

func TestNotifyPushFailureIsBestEffort(t *testing.T) {
	repo := &fakeRepo{tokens: []string{"device-1"}}
	push := &fakePusher{err: errors.New("provider down")}
	svc := testService(repo, push)

	if err := svc.Notify(context.Background(), rotationEvent()); err != nil {
		t.Fatalf("notify should swallow push failure, got %v", err)
	}
	if repo.pushed != 0 {
		t.Fatalf("mark pushed = %d, want 0 after provider failure", repo.pushed)
	}
}
