# Chama Ledger

A records-only ledger for Kenyan chamas. The platform holds no money: each chama connects
its own M-Pesa shortcode, members pay directly, and this system records what happened.

- **Backend:** Go, chi, pgx/v5, sqlc, golang-migrate (embedded), slog.
- **Web:** Svelte dashboard, built to `backend/internal/web/dist` and embedded in the binary.
  Public pages live at `/` (marketing), `/login` (sign-in), `/app` (dashboard) and `/join/{code}` (invites).
- **Mobile:** Flutter app (Phase 7).
- **Database:** PostgreSQL 15+; every status/type/role is a lookup table, no enums.

Design documents: `docs/DESIGN.md`, `docs/DATA-MODEL.md`, `docs/API.md`,
`docs/DESIGN-SYSTEM.md`, `docs/TENANCY-BILLING.md`, `docs/ROADMAP.md`.

## Change the app name

Edit one line in `branding.json`:

```json
{ "appName": "Chama Ledger" }
```

Then `make build` (or `make brand`). This regenerates the Go constants, and clients also read
`GET /api/v1/meta`, so the name can change without a new app release.

On Windows, the same step without `make`, from `backend/`:

```powershell
go run ./cmd/brandgen -file ../branding.json -out internal/platform/brand/brand.gen.go
```

## Local setup (Windows)

Every command below is a direct command, so nothing depends on `make`. Run them from the
repository root unless a step says otherwise. `192.168.100.11` is this machine's LAN address
(check with `ipconfig`); it is used so phones and other devices on the same Wi-Fi can reach the
backend. Change it in every command if your address changes.

Prerequisites: Go 1.26+, Node 20+, Flutter 3.x with the Android SDK, Docker Desktop.

### 1. Start Postgres

```powershell
docker compose up -d db
docker compose ps          # wait for STATUS "healthy"
```

Postgres 15 runs in the `chama-db` container on host port **5434**, with user, password and database
all `chama`. The non-standard port avoids colliding with a system Postgres.

Without Docker, point `DATABASE_URL` at any Postgres 15+ database instead.

### 2. Set the backend environment

The server reads configuration from process environment variables only — there is no `.env`
loader — so set these in the terminal that starts it. `.env.example` lists every variable with
safe development values.

```powershell
$env:APP_ENV         = "development"
$env:HTTP_ADDR       = ":8080"
$env:PUBLIC_BASE_URL = "http://192.168.100.11:8080"   # LAN origin: invites, callbacks, links
$env:DATABASE_URL    = "postgres://chama:chama@localhost:5434/chama?sslmode=disable"
$env:SMS_PROVIDER    = "console"                      # prints OTPs and returns dev_code
```

Leave `PAYMENTS_PROVIDER` unset: it defaults to `mock` in development and `daraja` otherwise.
`JWT_SECRET` and `ENCRYPTION_KEY` also have development defaults, and production refuses those
defaults, the console SMS provider and the mock payment provider.

### 3. Apply migrations and run the API

```powershell
cd backend
go mod download
go run ./cmd/migrate up       # needs DATABASE_URL in this shell; its built-in default uses another user
go run ./cmd/server           # http://192.168.100.11:8080
```

`go run ./cmd/migrate version` prints the applied version and `go run ./cmd/migrate down 1` rolls
one migration back.

Check it: `Invoke-RestMethod http://192.168.100.11:8080/healthz`. Windows Defender Firewall asks
once for `go.exe` — allow it on **both** Private and Public networks, otherwise a phone on the
Wi-Fi gets "We could not reach the server". To add the rule up front, in an elevated PowerShell:

```powershell
New-NetFirewallRule -DisplayName "chama-api 8080" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
```

### 4. Run the web dashboard

```powershell
cd web
npm install
npm run dev -- --host 0.0.0.0     # http://192.168.100.11:5173
```

The Vite dev server proxies `/api` to `http://localhost:8080`, so keep the API on port 8080 while
using it. There is no CORS middleware, which is why the dashboard goes through that proxy instead
of calling the API origin directly.

For the way production serves it, `npm run build` writes into `backend/internal/web/dist`, which
`go build` embeds, so the single binary serves the dashboard at
`http://192.168.100.11:8080/app`.

### 5. Run the mobile app

```powershell
cd mobile
flutter pub get
flutter devices              # confirm the phone is listed
flutter run --dart-define=API_BASE_URL=http://192.168.100.11:8080
```

`API_BASE_URL` matters on a real device: without it the app falls back to `localhost:8081`
(`10.0.2.2:8081` on the Android emulator). Debug builds allow plain HTTP, so the LAN address works
on a phone on the same Wi-Fi; keep both devices on that network.

Debug APK for a phone without a USB cable:

```powershell
flutter build apk --debug
# build\app\outputs\flutter-apk\app-debug.apk
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### 6. Checks

```powershell
cd backend ; gofmt -l . ; go vet ./... ; go test ./...
cd ..\mobile ; flutter analyze ; flutter test
cd ..\web ; npm run check ; npm run build
```

Integration tests start their own Postgres through testcontainers, so Docker must be running:

```powershell
cd backend
go test -tags integration ./internal/payments
```

Set `TEST_DATABASE_URL` to reuse an existing database instead; its name must end in `_test`.

`scripts/setup-windows.ps1` runs steps 1 to 4 for you: it checks the prerequisites, starts
Postgres, applies migrations and opens the API and dashboard in their own windows.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1
powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1 -CheckOnly   # plan only
```

## M-Pesa (Daraja) for each chama

The platform never holds chama money. Each chama connects **its own** Safaricom paybill or till
through its own Daraja app, so payments settle straight into that chama's own bank or M-Pesa
account. Go-live therefore happens per chama; the full checklist is `docs/DARAJA-GO-LIVE.md`.

What a chama needs before onboarding:

| Item | Detail |
| --- | --- |
| Shortcode | A paybill or Buy Goods (till) number registered to the chama |
| Lipa na M-Pesa Online | Enabled on that shortcode, otherwise STK Push is rejected |
| Daraja app | Created at developer.safaricom.co.ke with the Lipa na M-Pesa Online product added |
| Consumer key and secret | From that Daraja app, for the environment being used |
| Passkey | Emailed by Safaricom when the shortcode goes live; unique per shortcode |
| Org portal user | A Business Administrator on org.ke.m-pesa.com, needed to approve go-live |

A chama that still collects on a personal M-Pesa number cannot use STK Push and records receipts
manually instead.

### Onboarding in the app (manager or treasurer)

1. Open the chama, tap **M-Pesa**, and save the shortcode type (paybill or till), the shortcode,
   the environment (`sandbox` or `production`), the account reference template, and the consumer
   key, consumer secret and passkey. Secrets are encrypted at rest and never returned by the API;
   saving again clears the previous verification.
2. Copy the **callback URL** shown after saving, in this shape, and paste it into the Daraja app as
   the STK Push result URL:

   ```
   https://<PUBLIC_BASE_URL>/api/v1/payments/mpesa/callback/<group_id>/<callback_secret>
   ```

   It must be public HTTPS. A laptop on `192.168.100.11` cannot receive a live callback, so use the
   domain or tunnel you actually expose; on a LAN-only setup keep `PAYMENTS_PROVIDER=mock` and
   settle through the development callback instead. The per-chama secret in the path is what stops
   a forged callback from settling a ledger row.
3. Tap **Verify**. The server mints an OAuth token with the saved key pair for the chama's chosen
   environment, which proves Daraja accepts the credentials. Nothing can validate a passkey without
   moving money, so this is not the last check.
4. Tap **Send a KES 1 test**. It sends a real STK prompt from the chama's shortcode to the
   manager's own phone. Entering the M-Pesa PIN proves the shortcode, passkey and environment all
   agree. The KES 1 settles to the chama and **no ledger row is written**, so the test is safe to
   repeat. It needs a PIN step-up and `payment_settings.write`.
5. Once the KES 1 prompt arrives and settles, tell members to pay through the app.

### Payments received outside the app

Cash, a bank transfer, or a paybill payment entered on the handset without C2B URLs registered on
the shortcode never reach the API. The treasurer records those with **Record a payment**: it writes
a completed `mpesa_manual` ledger row for an active member and rejects an M-Pesa code already
recorded in that chama. It needs a PIN step-up and `payment.record`.

C2B confirmation URLs can only be registered once per live shortcode, and C2B and B2C cannot share
one Daraja app; see `docs/DARAJA-GO-LIVE.md` before registering them.

## Demo data and browser tests

The demo seed needs the API running with `APP_ENV=development`. It sets up Umoja Women's welfare
fund, records contributions, approves and pays a claim, then starts a rotation and records one
payout. The script is safe to rerun: existing contributions, claims and cycles are reused.

```powershell
$env:DEMO_PHONE = "0712991122"
$env:DEMO_PIN   = "4826"
$env:DEMO_API   = "http://192.168.100.11:8080/api/v1"   # the script defaults to :8081
node scripts/seed-demo.mjs
```

Set `DEMO_GROUP_ID`, `DEMO_GROUP_NAME` or `DEMO_ACCESS_TOKEN` only when overriding the defaults.
The script never prints access, refresh or step-up tokens.

Browser tests run against a running API plus embedded dashboard and use the installed Chrome
locally; CI installs Playwright's bundled Chromium. Point them at the same origin:

```powershell
cd web
$env:E2E_BASE_URL = "http://192.168.100.11:8080"
npm run test:e2e
```

Run the seed before the suite so the welfare fund exists. It covers the marketing page and URL
split, session restoration, admin and member navigation, report downloads, audit before/after
detail, a committee claim approval plus PIN-protected payout, and the public invite landing with
a pending join request. The first run creates `web/.auth/admin.json` and `web/.auth/member.json`
from the development OTP flow; later runs refresh and rewrite those sessions, so normal reruns do
not request another OTP. If a saved token is invalid, setup falls back to OTP and can hit the development resend cooldown. Delete `web/.auth/` to force a
fresh OTP bootstrap.

Useful overrides:

```powershell
$env:E2E_ADMIN_PHONE  = "0712991122"
$env:E2E_MEMBER_PHONE = "0712991144"
$env:E2E_PIN          = "4826"
$env:E2E_BASE_URL     = "http://192.168.100.11:8080"
npm run test:e2e
```

`PLAYWRIGHT_CHANNEL=msedge` selects Edge instead of Chrome. `web/.auth/`, `test-results/` and
`playwright-report/` are ignored and must not be committed.

## Core endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/meta` | branding and capabilities |
| POST | `/api/v1/auth/otp/request` | send a 6-digit code |
| POST | `/api/v1/auth/otp/verify` | session or registration token |
| POST | `/api/v1/auth/register` | create account with a 4-digit PIN |
| POST | `/api/v1/auth/login` | password login |
| POST | `/api/v1/auth/token/refresh` | rotate refresh token |
| POST | `/api/v1/auth/logout` | revoke session family |
| POST | `/api/v1/auth/pin/verify` | 5-minute step-up token |
| POST | `/api/v1/auth/pin/reset` | reset PIN with an OTP |
| GET/PATCH | `/api/v1/me` | profile |
| POST | `/api/v1/me/pin` · `/me/password` | change PIN or password |
| GET/POST/DELETE | `/api/v1/me/devices` | push/biometric device records |
| GET | `/healthz` · `/readyz` | probes |

Full contract: `docs/openapi.yaml`.

## Security notes

- Access JWT is 15 minutes; refresh tokens are 32 random bytes, hashed at rest, rotated on use.
  Reusing a rotated token revokes the whole session family.
- 4-digit PINs are argon2id-hashed, reject predictable values, and lock for 15 minutes after
  5 failures. Money endpoints will require a 5-minute step-up token minted by `/auth/pin/verify`.
- Passwords are optional and argon2id-hashed; unknown phones are compared against a dummy hash
  so response timing does not reveal whether an account exists.
- Phone numbers are masked in logs; OTPs, PINs, tokens and encrypted columns are redacted.

## Development commands (from `backend/`)

Windows has no `make`; the right-hand column is the equivalent to run directly.

| Command | Effect | PowerShell (Windows) |
|---|---|---|
| `make brand` | regenerate brand constants from `branding.json` | `go run ./cmd/brandgen -file ../branding.json -out internal/platform/brand/brand.gen.go` |
| `make sqlc` | regenerate the `internal/store` package | `sqlc generate` |
| `make migrate` / `make migrate-down` | apply or roll back migrations | `go run ./cmd/migrate up` / `go run ./cmd/migrate down 1` |
| `make run` | boot the API on `:8080` | `go run ./cmd/server` |
| `make test` | `go test ./...` | `go test ./...` |
| `make vet` / `make size` | vet, and the 300-line file-size guard | `go vet ./...` / `bash ../scripts/check-size.sh` (needs Git Bash) |
| `make build` | static binary at `../bin/chama-server` | `$env:CGO_ENABLED = "0"` then `go build -trimpath -ldflags "-s -w" -o ../bin/chama-server.exe ./cmd/server` |

## Status

The backend and Svelte dashboard are complete through Phase 6: auth, groups and RBAC, ledger
and M-Pesa, loans and fines, welfare/rotation/voting, notifications, reports/exports and the
audit trail. Phase 7 (Flutter) and Phase 8 (billing and platform console) remain and follow
`docs/ROADMAP.md`.
