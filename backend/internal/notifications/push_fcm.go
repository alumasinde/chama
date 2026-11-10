package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const fcmEndpoint = "https://fcm.googleapis.com/fcm/send"

type fcmPusher struct {
	key    string
	client *http.Client
}

func defaultHTTPClient() *http.Client { return &http.Client{Timeout: 10 * time.Second} }

func (p *fcmPusher) Name() string { return "fcm" }

type fcmPayload struct {
	To           string            `json:"to"`
	Notification map[string]string `json:"notification"`
	Data         map[string]string `json:"data,omitempty"`
}

// Push sends one request per device token and fails on the first non-2xx response.
func (p *fcmPusher) Push(ctx context.Context, tokens []string, message Message) error {
	for _, token := range tokens {
		body, err := json.Marshal(fcmPayload{
			To: token,
			Notification: map[string]string{
				"title": message.Title,
				"body":  message.Body,
			},
			Data: message.Data,
		})
		if err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, fcmEndpoint, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "key="+p.key)
		resp, err := p.client.Do(req)
		if err != nil {
			return err
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return fmt.Errorf("fcm returned %d", resp.StatusCode)
		}
	}
	return nil
}
