package payments

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/users"
)

func TestDarajaRequestSTK(t *testing.T) {
	var captured map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/oauth/v1/generate":
			key, secret, ok := r.BasicAuth()
			if !ok || key != "key-1" || secret != "secret-1" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "token-1", "expires_in": "3599"})
		case "/mpesa/stkpush/v1/processrequest":
			if r.Header.Get("Authorization") != "Bearer token-1" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			_ = json.NewDecoder(r.Body).Decode(&captured)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"MerchantRequestID": "merchant-1",
				"CheckoutRequestID": "ws_CO_123",
				"ResponseCode":      "0",
				"CustomerMessage":   "Success",
			})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	daraja, err := NewDaraja(server.URL)
	if err != nil {
		t.Fatalf("NewDaraja: %v", err)
	}
	response, err := daraja.RequestSTK(context.Background(), STKRequest{
		ShortcodeType:    "paybill",
		Shortcode:        "247247",
		Passkey:          "passkey-1",
		ConsumerKey:      "key-1",
		ConsumerSecret:   "secret-1",
		Amount:           money.Cents(150000),
		PhoneNumber:      "+254712345678",
		CallbackURL:      "https://example.test/callback",
		AccountReference: "CHAMA-5678",
		Description:      "Chama contribution",
	})
	if err != nil {
		t.Fatalf("RequestSTK: %v", err)
	}
	if response.CheckoutRequestID != "ws_CO_123" || response.MerchantRequestID != "merchant-1" {
		t.Fatalf("unexpected response %+v", response)
	}
	if captured["Amount"] != float64(1500) {
		t.Fatalf("Amount = %v, want whole shillings", captured["Amount"])
	}
	if captured["PartyA"] != "254712345678" || captured["PhoneNumber"] != "254712345678" {
		t.Fatalf("phone not normalised: %v", captured)
	}
	if captured["TransactionType"] != "CustomerPayBillOnline" {
		t.Fatalf("TransactionType = %v", captured["TransactionType"])
	}
	password, _ := base64.StdEncoding.DecodeString(captured["Password"].(string))
	if !strings.HasPrefix(string(password), "247247passkey-1") {
		t.Fatalf("password is not shortcode+passkey+timestamp: %q", password)
	}
	stamp, _ := captured["Timestamp"].(string)
	if len(stamp) != 14 || !strings.HasPrefix(string(password), "247247passkey-1"+stamp) {
		t.Fatalf("timestamp mismatch: %q vs %q", stamp, password)
	}
}

func TestDarajaTillAndFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/oauth/v1/generate" {
			_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "token-1"})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ResponseCode": "1", "ResponseDescription": "Rejected",
		})
	}))
	defer server.Close()

	daraja, err := NewDaraja(server.URL)
	if err != nil {
		t.Fatalf("NewDaraja: %v", err)
	}
	_, err = daraja.RequestSTK(context.Background(), STKRequest{
		ShortcodeType: "till", Shortcode: "123456", Passkey: "p",
		ConsumerKey: "k", ConsumerSecret: "s", Amount: money.Cents(100),
		PhoneNumber: "+254700000000",
	})
	if err == nil || !strings.Contains(err.Error(), "Rejected") {
		t.Fatalf("expected provider rejection, got %v", err)
	}
}

func TestDarajaVerifyCredentials(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/oauth/v1/generate" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		calls++
		key, secret, ok := r.BasicAuth()
		if !ok || key != "good-key" || secret != "good-secret" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "token-1", "expires_in": "3599"})
	}))
	defer server.Close()

	daraja, err := NewDaraja(server.URL)
	if err != nil {
		t.Fatalf("NewDaraja: %v", err)
	}
	if err := daraja.VerifyCredentials(context.Background(), "sandbox", "good-key", "good-secret"); err != nil {
		t.Fatalf("VerifyCredentials: %v", err)
	}
	if err := daraja.VerifyCredentials(context.Background(), "sandbox", "bad-key", "bad-secret"); err == nil {
		t.Fatal("expected rejected keys to fail verification")
	}
	if err := daraja.VerifyCredentials(context.Background(), "sandbox", "", "good-secret"); err == nil {
		t.Fatal("expected a missing key to fail verification")
	}
	if calls != 2 {
		t.Fatalf("oauth calls = %d, want 2 (the good key is cached)", calls)
	}
}

func TestDarajaVerificationHosts(t *testing.T) {
	daraja, err := NewDaraja("https://sandbox.safaricom.co.ke")
	if err != nil {
		t.Fatalf("NewDaraja: %v", err)
	}
	if host := daraja.verificationBase("sandbox").Host; host != "sandbox.safaricom.co.ke" {
		t.Fatalf("sandbox host = %q", host)
	}
	if host := daraja.verificationBase("production").Host; host != "api.safaricom.co.ke" {
		t.Fatalf("production host = %q", host)
	}

	local, err := NewDaraja("http://127.0.0.1:9")
	if err != nil {
		t.Fatalf("NewDaraja loopback: %v", err)
	}
	if host := local.verificationBase("production").Host; host != "127.0.0.1:9" {
		t.Fatalf("loopback host = %q", host)
	}
}

func TestAccountReference(t *testing.T) {
	ref := accountReference("CHAMA-{member_short}", users.User{PhoneNumber: "+254712345678"}, time.Date(2026, 11, 9, 0, 0, 0, 0, time.UTC))
	if ref != "CHAMA-5678" {
		t.Fatalf("ref = %q", ref)
	}
}
