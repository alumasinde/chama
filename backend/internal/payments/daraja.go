package payments

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const darajaTimeout = 20 * time.Second

var eastAfrica = time.FixedZone("EAT", 3*60*60)

type cachedToken struct {
	value   string
	expires time.Time
}

// Daraja implements Provider against Safaricom's STK Push API.
type Daraja struct {
	base   *url.URL
	client *http.Client

	mu     sync.Mutex
	tokens map[string]cachedToken
}

// NewDaraja validates the operator-configured base URL once at startup.
func NewDaraja(rawURL string) (*Daraja, error) {
	base, err := url.Parse(strings.TrimRight(rawURL, "/") + "/")
	if err != nil {
		return nil, fmt.Errorf("daraja base url: %w", err)
	}
	if base.Host == "" {
		return nil, fmt.Errorf("daraja base url: missing host")
	}
	if base.Scheme != "https" && (base.Scheme != "http" || !isLoopbackHost(base.Hostname())) {
		return nil, fmt.Errorf("daraja base url: %s must use https", rawURL)
	}
	return &Daraja{
		base:   base,
		client: &http.Client{Timeout: darajaTimeout},
		tokens: make(map[string]cachedToken),
	}, nil
}

func isLoopbackHost(host string) bool {
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// endpoint joins a fixed path onto the validated base URL.
func (d *Daraja) endpoint(path string, query url.Values) string {
	u := *d.base
	u.Path = strings.TrimSuffix(u.Path, "/") + path
	if len(query) > 0 {
		u.RawQuery = query.Encode()
	}
	return u.String()
}

func (d *Daraja) Name() string { return "daraja" }

func (d *Daraja) RequestSTK(ctx context.Context, req STKRequest) (STKResponse, error) {
	token, err := d.accessToken(ctx, req.ConsumerKey, req.ConsumerSecret)
	if err != nil {
		return STKResponse{}, err
	}
	timestamp := time.Now().In(eastAfrica).Format("20060102150405")
	password := base64.StdEncoding.EncodeToString([]byte(req.Shortcode + req.Passkey + timestamp))

	transactionType := "CustomerPayBillOnline"
	if req.ShortcodeType == "till" {
		transactionType = "CustomerBuyGoodsOnline"
	}
	body := map[string]any{
		"BusinessShortCode": req.Shortcode,
		"Password":          password,
		"Timestamp":         timestamp,
		"TransactionType":   transactionType,
		"Amount":            int64(req.Amount) / 100,
		"PartyA":            strings.TrimPrefix(req.PhoneNumber, "+"),
		"PartyB":            req.Shortcode,
		"PhoneNumber":       strings.TrimPrefix(req.PhoneNumber, "+"),
		"CallBackURL":       req.CallbackURL,
		"AccountReference":  req.AccountReference,
		"TransactionDesc":   req.Description,
	}
	var out struct {
		MerchantRequestID   string `json:"MerchantRequestID"`
		CheckoutRequestID   string `json:"CheckoutRequestID"`
		ResponseCode        string `json:"ResponseCode"`
		ResponseDescription string `json:"ResponseDescription"`
		CustomerMessage     string `json:"CustomerMessage"`
		ErrorMessage        string `json:"errorMessage"`
	}
	if err := d.post(ctx, "/mpesa/stkpush/v1/processrequest", token, body, &out); err != nil {
		return STKResponse{}, err
	}
	if out.ResponseCode != "0" || out.CheckoutRequestID == "" {
		return STKResponse{}, fmt.Errorf("%w: %s", ErrProviderUnavailable, firstNonEmpty(out.ErrorMessage, out.ResponseDescription, "STK rejected"))
	}
	return STKResponse{
		MerchantRequestID: out.MerchantRequestID,
		CheckoutRequestID: out.CheckoutRequestID,
		CustomerMessage:   out.CustomerMessage,
	}, nil
}

// accessToken caches OAuth tokens per consumer key for 55 minutes.
func (d *Daraja) accessToken(ctx context.Context, key, secret string) (string, error) {
	cacheKey := key
	d.mu.Lock()
	if cached, ok := d.tokens[cacheKey]; ok && cached.expires.After(time.Now()) {
		d.mu.Unlock()
		return cached.value, nil
	}
	d.mu.Unlock()

	endpoint := d.endpoint("/oauth/v1/generate", url.Values{"grant_type": {"client_credentials"}})
	//nolint:gosec // the host is operator configuration, validated in NewDaraja; the path is fixed.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", err
	}
	req.SetBasicAuth(key, secret)
	//nolint:gosec // request URL is built from the validated base URL above.
	resp, err := d.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrProviderUnavailable, err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("%w: oauth status %d", ErrProviderUnavailable, resp.StatusCode)
	}
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   string `json:"expires_in"`
	}
	if err := json.Unmarshal(raw, &out); err != nil || out.AccessToken == "" {
		return "", fmt.Errorf("%w: oauth response unreadable", ErrProviderUnavailable)
	}
	d.mu.Lock()
	d.tokens[cacheKey] = cachedToken{value: out.AccessToken, expires: time.Now().Add(55 * time.Minute)}
	d.mu.Unlock()
	return out.AccessToken, nil
}

func (d *Daraja) post(ctx context.Context, path, token string, body, out any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	//nolint:gosec // the host is operator configuration, validated in NewDaraja; the path is fixed.
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.endpoint(path, nil), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	//nolint:gosec // request URL is built from the validated base URL above.
	resp, err := d.client.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrProviderUnavailable, err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("%w: stk status %d %s", ErrProviderUnavailable, resp.StatusCode, truncate(string(raw), 160))
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("%w: stk response unreadable", ErrProviderUnavailable)
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
