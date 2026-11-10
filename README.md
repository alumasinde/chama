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

## Local setup

```bash
docker compose up -d db          # Postgres 15 on host port 5434
cd backend
export $(grep -v '^#' ../.env.example | xargs)   # or set the same vars in your shell
make migrate                     # apply every embedded migration
make run                         # http://localhost:8080
```

Without Docker, point `DATABASE_URL` at any Postgres 15+ database and run `make migrate`.

The development SMS provider prints OTPs to the log and also returns `dev_code` from
`/api/v1/auth/otp/request` when `APP_ENV=development`. Production refuses the console provider.

## Demo data and browser tests

The demo seed needs the API running with `APP_ENV=development`. It sets up Umoja Women's welfare
fund, records contributions, approves and pays a claim, then starts a rotation and records one
payout. The script is safe to rerun: existing contributions, claims and cycles are reused.

```bash
DEMO_PHONE=0712991122 DEMO_PIN=4826 node scripts/seed-demo.mjs
```

Set `DEMO_GROUP_ID`, `DEMO_GROUP_NAME`, `DEMO_ACCESS_TOKEN` or `DEMO_API` only when overriding
the defaults. The script never prints access, refresh or step-up tokens.

Browser tests run against the single binary on port 8081. Locally they use the installed Chrome; CI installs Playwright's bundled Chromium:

```bash
cd web
npm run test:e2e
```

Run the seed before the suite so the welfare fund exists. It covers the marketing page and URL
split, session restoration, admin and member navigation, report downloads, audit before/after
detail, a committee claim approval plus PIN-protected payout, and the public invite landing with
a pending join request. The first run creates `web/.auth/admin.json` and
`web/.auth/member.json` from the development OTP flow; later runs refresh and rewrite those
sessions, so normal reruns do not request another OTP. If a saved token is invalid, setup falls back to OTP and can hit the development resend cooldown. Delete `web/.auth/` to force a
fresh OTP bootstrap.

Useful overrides:

```bash
E2E_ADMIN_PHONE=0712991122 E2E_MEMBER_PHONE=0712991144 E2E_PIN=4826 \
  E2E_BASE_URL=http://localhost:8081 npm run test:e2e
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

| Command | Effect |
|---|---|
| `make brand` | regenerate brand constants from `branding.json` |
| `make sqlc` | regenerate the `internal/store` package |
| `make migrate` / `make migrate-down` | apply or roll back migrations |
| `make test` | `go test ./...` |
| `make vet` / `make size` | vet, and the 300-line file-size guard |
| `make build` | static binary at `../bin/chama-server` |

## Status

The backend and Svelte dashboard are complete through Phase 6: auth, groups and RBAC, ledger
and M-Pesa, loans and fines, welfare/rotation/voting, notifications, reports/exports and the
audit trail. Phase 7 (Flutter) and Phase 8 (billing and platform console) remain and follow
`docs/ROADMAP.md`.
