# Chama Ledger — System Design

**Status:** design for approval · **Phase:** 0 (no code yet) · **Date:** 2026-11-09

The product name is configurable. Everywhere below, "Chama" stands for the value in
`branding.json → appName`. See §13.

---

## 1. What this is, and what it is not

**Is:** a multi-tenant ledger for Kenyan chamas. It records contributions, fines, loans,
welfare and merry-go-round payouts, and triggers M-Pesa STK Push against **each chama's own
shortcode**. Money moves member → chama account directly; the platform is never a party to
the payment.

**Is not:** a wallet, a custodian, a sacco core-banking system, a USSD service. There is no
balance that the platform can spend. No USSD tables, handlers, menus or simulators exist in
this repo, by policy.

Two hard consequences that shape everything below:

1. **The ledger is the source of truth, and it is append-only.** No stored counters. Balances
   are `SELECT` over `transactions` (`v_member_balances`). Corrections are new rows
   (`reversal`, `adjustment`), never edits.
2. **Every mutation is attributable.** Actor, request ID, IP and before/after snapshots land in
   `audit_logs` for all admin/treasurer actions.

---

## 2. System shape

```
┌──────────────────────┐        ┌───────────────────────┐
│ Flutter (members)    │        │ Svelte SPA (admins)   │
│ Riverpod · dio       │        │ SvelteKit static      │
│ Drift offline cache  │        │ embedded via go:embed │
└──────────┬───────────┘        └──────────┬────────────┘
           │ HTTPS /api/v1 (JSON)          │ HTTPS /api/v1 + static
           └───────────────┬───────────────┘
                           ▼
        ┌──────────────────────────────────────────┐
        │  chama-server  (single Go binary)        │
        │  chi router → middleware → module routes │
        │  handlers → services → repositories      │
        │  in-process workers (Postgres queue)     │
        └───────┬───────────────────────┬──────────┘
                │ pgx/v5 pool           │ https
                ▼                       ▼
        ┌───────────────┐      ┌──────────────────────┐
        │ PostgreSQL 15 │      │ Daraja (per-chama    │
        │ ledger + jobs │      │ creds, STK + status) │
        └───────────────┘      └──────────────────────┘
```

One binary. One database. No Redis, no broker: the job queue is a Postgres table with
`FOR UPDATE SKIP LOCKED`. Advisory locks stop duplicate workers across replicas.

---

## 3. Module map (files I will create)

```
chama/
  branding.json                     single line app name + brand tokens
  Makefile  docker-compose.yml  Dockerfile  .golangci.yml  .github/workflows/ci.yml
  backend/
    cmd/server/main.go              ~80 lines: config, db, modules, http server, workers
    cmd/brandgen/main.go            branding.json → generated constants (Go/TS/Dart)
    internal/config/config.go       env parsing + validation, one struct
    internal/platform/
      db/        db.go tx.go        pool, WithTx helper, error mapping
      logger/    logger.go redact.go slog JSON + phone/secret redaction
      httpx/     respond.go errors.go pagination.go decode.go middleware.go requestid.go
      crypto/    aesgcm.go hash.go random.go id.go
      queue/     queue.go worker.go jobs.go registry
      money/     money.go split.go parse.go    Cents type, allocation, fmt
      brand/     brand.gen.go
    internal/auth/          handler.go service.go repository.go tokens.go otp.go pin.go models.go routes.go
    internal/users/         handler.go service.go repository.go models.go routes.go
    internal/groups/        handler.go service.go repository.go models.go routes.go settings.go
    internal/memberships/   handler.go service.go repository.go models.go routes.go
    internal/contributions/ handler.go service.go repository.go models.go routes.go schedule.go
    internal/payments/      handler.go service.go repository.go models.go routes.go
                            provider.go daraja.go mock.go reconcile.go callback.go
    internal/loans/         handler.go service.go repository.go models.go routes.go
                            guarantors.go approvals.go schedule.go repayments.go
    internal/welfare/       handler.go service.go repository.go models.go routes.go
    internal/rotation/      handler.go service.go repository.go models.go routes.go
                            voting.go
    internal/fines/         handler.go service.go repository.go models.go routes.go job.go
    internal/reports/       handler.go service.go repository.go models.go routes.go
                            queries.go export_csv.go export_pdf.go job.go
    internal/notifications/ handler.go service.go repository.go models.go routes.go
                            push.go push_fcm.go push_console.go
    internal/audit/         handler.go service.go repository.go models.go routes.go
    internal/billing/       handler.go service.go repository.go models.go routes.go
                            catalog.go invoices.go entitlements.go dunning.go provider.go mock.go
    internal/platformauth/  handler.go service.go repository.go models.go routes.go
    internal/rbac/          permissions.go middleware.go
    internal/web/           embed.go spa.go
    internal/routes/api.go  mounts every module + SPA fallback
    migrations/             0001_lookups … 0018_queue (each with .down.sql)
    queries/                one .sql per module (sqlc input)
    sqlc.yaml
  web/        SvelteKit app → builds into backend/internal/web/dist
  mobile/     Flutter app
  docs/       DESIGN.md DATA-MODEL.md API.md DESIGN-SYSTEM.md ROADMAP.md openapi.yaml
  scripts/    check-size.sh  dev-web.sh
```

**File-size law (enforced):** Go file ≤ 300 lines, Svelte component ≤ 220, Dart screen ≤ 260.
`scripts/check-size.sh` runs in CI and fails the build. When a file would exceed it, the module
splits by *use case* (as `loans/schedule.go`), never by "utils".

**Layering law:** handlers decode → call one service method → `httpx.Respond`. Handlers never
import `pgx`, never build SQL, never branch on status codes. Repositories are sqlc
`Queries` + mappers only. Services own validation, permissions, money math and transactions.

---

## 4. Request pipeline

```
Recover → RequestID → AccessLog → SecurityHeaders → RateLimit
  → Auth (JWT) → GroupScope (membership lookup) → RBAC (permission)
  → Idempotency (money POSTs) → Handler
```

- `request_id` (ULID) is returned in `X-Request-Id`, attached to `slog` and to every audit row.
- `GroupScope` loads `group_members` for `{groupId}` and puts `{userID, groupID, roleCode}` in
  context. Client-sent roles are never read — a forged `role` field is ignored.
- Errors are values: `httpx.Error{Code, Message, Fields, HTTPStatus}`. One renderer produces
  `{"error":{"code","message","fields"}}`. 5xx messages are generic; detail goes to logs only.
- Panics become `500 internal_error`, logged with stack, request ID returned to the client.

---

## 5. Identity: OTP, password, 4-digit PIN, biometrics

Three credentials, deliberately separate:

| Credential | Purpose | Storage | Where |
|---|---|---|---|
| OTP (6 digits) | prove phone ownership | `otp_codes.code_hash` (HMAC-SHA256) | server |
| Password (optional) | web login alternative | `users.password_hash` (argon2id) | server |
| **PIN (4 digits)** | **authorise money / loan actions** | `user_pins.pin_hash` (argon2id) | server |
| Biometric | unlock the app / approve | never leaves device | device keychain |

**Onboarding (mobile).** phone → OTP → name (first/last) → set 4-digit PIN → confirm PIN →
"Enable fingerprint unlock?" → optional password ("Use a password instead" is available at
login but not forced) → join or create a chama.

**PIN rules.** 4 digits exactly, weak-PIN blocklist (`0000,1111,…,1234,4321`), argon2id, 5
failures → 15-minute lock (`user_pins.locked_until`), reset only via OTP (`otp_purposes.pin_reset`).
The PIN is never sent to third parties, never logged, never cached.

**Step-up token.** Verifying the PIN (or an accepted biometric) mints a 5-minute JWT with
`scope=step_up` and `aud=payments`. Every money-moving POST (`/payments/stk`, manual entries,
loan disburse, welfare payout, rotation payout, reversals) requires it in
`X-Step-Up-Token`. Missing/expired → `403 step_up_required`, and the app re-prompts inline.
This is what stops a stolen access token from moving money without the PIN.

**Biometric.** `local_auth` gates a refresh token held in `flutter_secure_storage`
(`accessibility: first_unlock_this_device`). The server never sees a fingerprint; it sees a
normal refresh from a `device_id` the user marked biometric-enabled. Server-side kill switch:
`DELETE /devices/{id}` revokes the family.

**Sessions.** Access JWT HS256, 15 min, claims `sub, gid? , sid, scope, jti, exp`. Refresh:
32 random bytes, SHA-256 hashed at rest, 30 days, rotated on every use with `replaced_by`
chain; **reuse of a rotated token revokes the whole family** (theft detection). Logout revokes
the family. Web stores the access token in memory + refresh in an httpOnly-equivalent pattern
(same-origin cookie is unavailable to a static SPA, so: refresh token in `sessionStorage`,
access in memory, strict CSP, no third-party scripts).

**Abuse control.** Postgres-backed throttle (`auth_throttle`): OTP send 3/phone/10 min + 10/IP/hour;
OTP verify 5 attempts then invalidate; password login 10 failures/15 min; PIN 5 then 15 min lock.
Phone numbers are masked in logs (`+2547****1234`) and never appear in URLs.

---

## 6. Payments — ledger-only STK Push

```
Flutter "Contribute" → POST /groups/{id}/payments/stk  (Idempotency-Key, X-Step-Up-Token)
  └─ service: load settings → decrypt creds → Daraja OAuth (cached ~55m per group)
     → STK Push on the CHAMA's shortcode
     → tx: insert payment_requests(pending) + transactions(pending)
  └─ 202 {payment_request_id, checkout_request_id}

Daraja → POST /api/v1/payments/mpesa/callback/{groupPublicId}/{callbackSecret}
  └─ constant-time secret check → find by CheckoutRequestID
  └─ tx: if status still pending → set completed/failed, set reference_code, raw_callback,
         completed_at; link transaction. Already settled → 200 no-op (idempotent).

Reconciler (job, every 60s): pending > 3 min → Daraja STK Query → same settle() function.
Treasurer: POST /groups/{id}/payments/{requestId}/reconcile for on-demand check.
```

- `PaymentProvider` interface: `RequestSTK`, `QuerySTK`, `TestConnection`. Implementations:
  `daraja.go`, `mock.go` (`PAYMENTS_PROVIDER=mock` in dev: settles after 2s with a fixed
  result; never registered when `APP_ENV=production`).
- **Callback secrecy.** The URL secret is generated per group (32 bytes, base64url), stored
  AES-256-GCM encrypted (`callback_secret_enc`) because we need the plaintext to construct the
  URL we hand Daraja. Compared with `subtle.ConstantTimeCompare`.
- **Idempotency.** Header key + SHA-256 of canonical body, stored in `idempotency_keys` for 24h.
  Same key + same hash → replay stored response. Same key + different body → `409
  idempotency_conflict`. Key already in flight → `409 request_in_progress`. 5xx clears the row
  so a retry is legal.
- **Manual entry** (cash/bank/other): treasurer role, requires reference text, writes the ledger
  row **and** an audit row in the same transaction. `recorded_by` is set.
- **Reversal**: admin/treasurer creates a mirrored negative-effect `reversal` row with
  `narration` + reason; the original keeps its status. Enforced by trigger, not convention.
- **Credentials never leave the server.** No endpoint, log line, or admin page can read
  `*_enc`. The UI shows `••••last4` and `is_verified` only. `TestConnection` performs one
  OAuth call and one STK-query on a synthetic ID, then sets `is_verified`.

---

## 7. Money, loans, fines, welfare, rotation (summary)

- **Money representation.** DB `NUMERIC(15,2)`. Go `money.Cents int64` (`type Cents int64`),
  converted at the SQL boundary (`round(amount*100)::bigint` / `(x/100.0)::numeric(15,2)`).
  No float anywhere, including the Dart and TS clients (both use integer minor units).
- **Loan math** (in `internal/platform/money` + `loans/schedule.go`, unit-tested):
  flat → `total_interest = P × monthly_rate × n`, equal installments, remainder on the last row;
  reducing balance → `EMI = P·i / (1 − (1+i)^−n)`, interest recomputed per period on the
  opening balance. Rounding is half-up per installment; the final installment absorbs the delta
  so `Σ` exactly equals `total_payable`. Schedules are persisted (auditable), never recomputed
  on read.
- **Guarantor cover.** `Σ amount_guaranteed` per guarantor across live loans may not exceed their
  savings balance; checked in the service inside the loan transaction.
- **Fines.** Nightly job (`0 2 * * *` Africa/Nairobi, implementd as a `jobs` row swept every
  minute) evaluates `fine_rules` against overdue contribution periods; idempotent by
  `UNIQUE(group_id, user_id, fine_rule_id, period_label)`. Waive/pay audited.
- **Welfare.** Fund per group, contributions link to ledger rows, claims follow
  pending → approved/rejected → paid (payout = manual ledger row).
- **Rotation with voting.** Ordering mode is a lookup: `random | manual | vote`.
  Voting flow: treasurer proposes an order (`rotation_proposal_slots`) → members vote
  for/against within `closes_at` → quorum `ceil(active_members × quorum_percent/100)` →
  passes when `for > against`; a passed proposal materialises `rotation_slots`. Ties fail
  (re-propose). `random` uses a crypto seed stored on the cycle so the draw is verifiable
  after the fact. Payouts are recorded manual ledger rows.

---

## 8. Background work

Postgres queue, one `jobs` table, workers started inside the binary unless
`WORKERS_ENABLED=false`:

| Job | Cadence | Idempotency |
|---|---|---|
| `payments.reconcile` | 60 s | per `payment_request_id` |
| `fines.nightly` | daily 02:00 EAT | unique fine key |
| `loans.detect_defaults` | daily 03:00 | per installment |
| `reports.render` | on submit | `report_jobs.status` |
| `notifications.send` | 10 s | `notifications.pushed_at` |
| `views.refresh` | hourly | `REFRESH MATERIALIZED VIEW CONCURRENTLY` |
| `auth.cleanup` | hourly | delete expired OTP/refresh/idempotency rows |

`pg_advisory_lock` per job kind prevents double execution across replicas; retries use
exponential backoff with `attempts` capped at 5 and `last_error` recorded.

---

## 9. Reporting

`report_jobs` is the only export path: POST a report code + params → 202 with job ID → worker
renders CSV (streaming) or PDF (gofpdf) into `REPORT_DIR` → `GET /reports/jobs/{id}/download`
streams with `Content-Disposition`. Every table in the web UI exports through this, so no
long query ever blocks a request.

Read models are SQL views (`v_member_balances`, `v_loan_book`, `v_defaulter_board`) plus one
materialised view for the daily cash-flow series. No counters, no triggers that increment.

---

## 10. Secrets, PII, logging

- All secrets from env, validated at boot; the server refuses to start in production with
  defaults (`JWT_SECRET` < 32 chars, missing `ENCRYPTION_KEY` → fatal).
- AES-256-GCM envelope: `nonce|ciphertext` in `bytea`, key = 32-byte base64 env
  (`ENCRYPTION_KEY`), AAD = column name + group ID so ciphertexts cannot be swapped between rows.
- Argon2id for passwords and PINs (64 MiB, t=3, p=2), OTP/pin never logged.
- `logger/redact.go` installs a `slog.Handler` wrapper that masks `phone_number`, `*_enc`,
  `password`, `pin`, `token`, `authorization`, `callback_secret` keys and E.164 patterns.
- PII at rest: `national_id_enc` encrypted; only the last 4 digits are surfaced.

---

## 11. Testing & CI

- Unit: loan schedule (flat + reducing, rounding edges), fine calculation, callback settle
  idempotency, PIN/step-up, cursor pagination, money allocation. Table-driven.
- Integration: `testcontainers-go` Postgres 15, real migrations, one test file per module
  behind `//go:build integration`. Includes the append-only trigger and concurrent-callback race.
- Contract: `docs/openapi.yaml` checked by a linter; handler tests assert envelope shape.
- CI: `go vet`, `golangci-lint run`, `go test -race ./...`, `npm ci && npm run check && npm run
  build`, `flutter analyze && flutter test`. Size guard runs first and is cheap.

---

## 12. Dev loop & build

```
docker compose up -d db          # postgres 15 on 5432
make migrate                     # golang-migrate up
make dev-api                     # go run ./cmd/server  → :8080
make dev-web                     # vite dev :5173 proxying /api → :8080
make build                       # brandgen → npm build → go build → ./bin/chama-server
```

`make build` order matters: web build writes `backend/internal/web/dist` (vite `outDir`
configured there), then `go build` embeds it. `go:embed all:dist` with a committed
`.gitkeep` so `go build` never fails on a clean checkout.

SPA handler: static file if it exists, `/assets/*` immutable 1-year cache, otherwise
`index.html` for non-`/api` paths, `404 JSON` under `/api`. Health: `/healthz` (liveness),
`/readyz` (DB ping).

---

## 13. Branding: change one line

`branding.json` at repo root is the single source:

```json
{ "appName": "Chama Ledger", "primaryColor": "#0B6E4F", "accentColor": "#D9A227", "currency": "KES", "locale": "en", "supportEmail": "support@example.co.ke" }
```

Change `appName`, run `make build` (or `make brand`), and three artefacts regenerate:
`internal/platform/brand/brand.gen.go`, `web/src/lib/brand.gen.ts`,
`mobile/lib/core/brand.gen.dart` — plus the Android `strings.xml` label and the iOS
`CFBundleDisplayName`. No other file mentions the product name.

Runtime override: `GET /api/v1/meta` returns `{app_name, short_name, currency, primary_color,
support_email, features}` and both clients prefer it over the compile-time constant, so renaming
doesn't require a store release. `short_name` is the first word of `appName` (or `shortName` if
provided). Every user-facing string in Flutter and Svelte references `brand.appName`; a CI grep
fails on hard-coded product names.

---

## 14. Decisions worth flagging

| # | Decision | Why |
|---|---|---|
| 1 | Money = `int64` cents in Go, `NUMERIC` in PG | No float, no pgx codec hack, exact rounding, trivially testable |
| 2 | Step-up token for money actions | PIN/biometric must gate spend, not just login |
| 3 | Postgres job queue, in-process workers | One binary deploy as required; no Redis dependency |
| 4 | Schedules persisted, not derived | Lenders and treasurers need the agreed schedule to be immutable evidence |
| 5 | Rotation voting = approve-a-proposed-order | Simple, auditable, quorum-based; matches how chamas actually agree |
| 6 | `idempotency_keys` stores response body | Replay must be byte-identical, incl. the created transaction ID |
| 7 | Lookup shape fixed at 7 columns | Direction/capability live in Go constants + SQL CASE views, keeping the lookup contract uniform |
| 8 | Pooled tenancy, tenant = group, composite FKs + RLS | Per-DB tenants cost more than KES 1,000/mo revenue; schema-level FKs make leakage impossible, not just unlikely |
| 9 | Platform billing is a separate domain and table set | A platform invoice in `transactions` would corrupt member balances and chama cash-flow |
| 10 | Expiry never blocks member contributions | Punishing 50 members for a treasurer's missed invoice destroys ledger trust |

## 15. Assumptions (correct me now, cheaply)

1. One human can belong to many chamas; role is per group (never global).
2. Group currency is `KES` only in v1; `currency_code` exists but is validated to `KES`.
3. Treasurer/admin both approve loans; `guarantors_required` is enforced by count, not amount.
4. Payouts (loan disbursement, welfare, rotation) are **always** recorded manually — no B2C.
5. PDF export is per-report, server-rendered, no client-side PDF.
6. Platform staff exist only as a separate privileged plane (`platform_users`, audience `platform`), see `TENANCY-BILLING.md`.
7. Tenancy is pooled: one database, tenant = `group_id`, enforced by path + membership + composite FKs + RLS.
8. Billing is flat + seats in KES, paid by the chama's treasurer from the platform's own shortcode.

---

## 16. Tenancy and monetisation

Tenancy (pooled, five isolation layers, tenant lifecycle, support-access rules), URL design and
subscription billing are specified in **`docs/TENANCY-BILLING.md`**. Summary: tenant = `groups`
row; URLs are UUID-pathed on one origin (`/api/v1/groups/{groupUuid}/...`, `/join/{code}`); money
is collected for subscriptions on the **platform's** shortcode into `billing_*` tables, never into
a chama's ledger. Entitlement hooks land in Phase 2, the billing console in Phase 8.
