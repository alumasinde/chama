# Delivery Plan

Seven phases. After each one I stop, list every file created/changed, and state the checks that
were actually run (with failures reported honestly). No phase starts until the previous one
compiles, migrates from empty, and its tests pass.

Phase 0 (this document set) is complete when you approve the design.

---

## Phase 1 — Scaffold, config, identity

**Files:** `branding.json`, `Makefile`, `docker-compose.yml`, `.golangci.yml`, `.github/workflows/ci.yml`,
`scripts/check-size.sh`, `backend/cmd/server/main.go`, `backend/cmd/brandgen/main.go`,
`backend/internal/config/config.go`, `platform/{db,logger,httpx,crypto,queue,money,brand}`,
`internal/{auth,users}/*`, `internal/routes/api.go`, `internal/web/{embed.go,spa.go}`,
`migrations/0001…0003`, `queries/auth.sql`, `queries/users.sql`, `sqlc.yaml`,
`docs/openapi.yaml` (auth slice).

**Delivers:** boot with validated env, slog + request IDs + redaction, migrations 0001–0003,
OTP request/verify (console SMS provider, `dev_code` in development only), register, login with
password, 4-digit PIN set/verify/step-up, refresh rotation with reuse detection, `/me`, `/meta`,
rate limits and lockouts, `httpx` error envelope + cursor pagination helpers, brand codegen.

**Acceptance:** fresh DB → migrate up → down → up clean; register → PIN → refresh → PIN verify
works end to end via `curl`; 5 wrong PINs locks; duplicate refresh use revokes family; `go test
-race` green; size guard green.

---

## Phase 2 — Groups, roles, RBAC, payment settings

**Files:** `internal/{groups,memberships,rbac,billing/catalog,billing/entitlements}/*`,
`migrations/0004…0005`, group queries, `docs/openapi.yaml` (groups slice), web scaffold
(`web/` SvelteKit + adapter-static + Tailwind tokens + login/OTP + shell + group switcher) with
build wired to `internal/web/dist`.

**Delivers:** create group (wizard payload), invite code + join + admin approval, member list,
role/status changes, per-group settings, loan settings, fine rules, RBAC middleware, payment
settings with AES-256-GCM at rest and a write-only API, `/meta` feature flags.

**Acceptance:** member of group A gets 404 on group B (no existence leak); forged role field
ignored; cross-tenant composite FK rejects a mis-parented child row; secrets never appear in
responses or logs (grep test); ciphertext round-trip fails across groups (AAD test); new group
gets a 30-day trial subscription; `requireFeature` blocks loans on the free plan with `402`;
web login renders and stores tokens.

---

## Phase 3 — Ledger, STK, callback, reconciliation, statements

**Files:** `internal/{contributions,payments}/*` (`provider.go`, `daraja.go`, `mock.go`,
`callback.go`, `reconcile.go`), `migrations/0006…0008`, ledger + payment queries,
`internal/platform/money/*`, contributions schema/schedule, statements, audit writer.

**Delivers:** contribution schedule and due/overdue derivation, append-only triggers, idempotency
store + middleware, `PaymentProvider` interface with Daraja and mock, STK endpoint, callback with
constant-time secret and single-transaction settle, reconciler job, manual entry (audited),
reversal, member/group statements, receipt reference codes.

**Acceptance:** duplicate callback → one completed row; callback for unknown checkout → 200 no
write; wrong secret → 403; STK replay with same key → identical response; `UPDATE` on completed
transaction raises; balance view equals hand-computed sum.

---

## Phase 4 — Fines and loans

**Files:** `internal/{fines,loans}/*` (`schedule.go`, `guarantors.go`, `approvals.go`,
`repayments.go`, `job.go`), `migrations/0009…0010`, loan/fine queries, nightly job registration.

**Delivers:** fine rules evaluation job (idempotent), custom fines, waive, manual pay; loan apply
→ guarantor invites/decisions → approval queue → manual disbursement → persisted schedule (flat +
reducing) → repayment allocation → default detection; guarantor cover check.

**Acceptance:** schedule sums exact for 12 fixture cases including rounding edges; guarantor
over-commit rejected; loan cannot be approved while guarantors pending; repayment spanning
installments allocates correctly; fine job run twice yields one row.

---

## Phase 5 — Welfare, rotation + voting, notifications

**Files:** `internal/{welfare,rotation,notifications}/*` (`voting.go`, `push.go`,
`push_fcm.go`), `migrations/0010…0012`, related queries.

**Delivers:** welfare fund, contributions, claims lifecycle with payouts; rotation cycles with
random (verifiable seed) / manual / vote ordering, proposals, one-vote-per-member with change,
quorum + tally, close job, payout recording, history; notifications list, read state, FCM push
behind an interface with console provider, event hooks (payment received, due reminder,
guarantor request, loan update, fine applied, rotation turn).

**Acceptance:** vote after close rejected; second vote updates rather than duplicates; tie fails;
cycle cannot start twice; push interface mocked in tests; notification created exactly once per
event.

---

## Phase 6 — Reports, exports, audit viewer, full Svelte dashboard

**Files:** `internal/reports/*` (`queries.go`, `export_csv.go`, `export_pdf.go`, `job.go`),
`internal/audit/*`, `migrations/0014…0016`, all remaining web pages/components,
`docs/openapi.yaml` complete.

**Delivers:** dashboard KPIs + charts from views, loan book, defaulter board, fines report,
cash-flow series, CSV/PDF jobs with download, audit log viewer with diff drawer, every dashboard
page, CSV/PDF buttons on every table, light/dark, role-aware nav, `make build` single binary with
embedded SPA.

**Acceptance:** one binary serves SPA + API; deep link reload works (index fallback) and
`/api/unknown` returns JSON 404; exports open in Excel with correct amounts; audit shows
before/after; no page loads > 1 MB JS; AA contrast verified on both themes.

---

## Phase 7 — Flutter app against the finished API

**Files:** `mobile/` full app: `lib/core/{api,router,storage,brand.gen,theme,i18n}`,
`lib/features/{onboarding,auth,home,money,loans,welfare,rotation,group,notifications,profile}/`,
Drift schema + DAOs, ARB files (en, sw), platform config for secure storage + biometrics.

**Delivers:** all screens from DESIGN-SYSTEM §2, secure token storage, biometric unlock, 4-digit
PIN + step-up, dio interceptors (auth refresh, idempotency key, request ID, offline detection),
Drift offline statements/balances with staleness bar, skeletons, confirmation sheets with
line-item breakdown, en/sw localization, deep links.

**Acceptance:** `flutter analyze` clean; widget tests for PIN pad, confirm sheet totals, offline
cache; manual run against local backend for onboarding → contribute (mock provider) → statement;
language switch verified; no product name hard-coded.

---

## Phase 8 — SaaS billing and platform console

Plans/trial/entitlement hooks already shipped in Phase 2; this phase adds the money path and the
operator console.

**Files:** `internal/billing/{invoices,provider,mock,dunning}.go`,
`internal/platformauth/*`, `migrations/0015…0017`, billing queries, `/platform` SPA bundle
(tenants, invoices, plans, revenue), tenant **Billing** pages, Flutter admin "Plan & billing"
screen, invoice PDF template.

**Delivers:** plan catalog (seeded), subscription lifecycle with seat snapshots, invoice
generation + VAT, STK collection on the platform's own shortcode with callback and idempotency,
manual/finance settlement, dunning ladder job (T-7 → T+90), proration on upgrade, credit lines,
entitlement enforcement with `402` + upgrade URL, platform auth with audience split, revenue
view, offboarding/export job.

**Acceptance:** invoice totals equal line items incl. VAT; paying an invoice extends the period
exactly once (duplicate callback is a no-op); expiry blocks admin writes but a member STK
contribution still succeeds; prorated upgrade never double-charges; platform token cannot call a
tenant endpoint and vice versa; no billing row ever appears in a chama's `transactions` or
balances; finance mark-paid requires a reference and writes an audit row.

---

## Cross-phase rules

- One phase = one reviewable diff set. No phase leaves TODO stubs in shipped paths.
- Any bug found while building is fixed in that phase, including earlier-phase code.
- Every phase ends with: migrations round-trip, `go vet`, `golangci-lint`, `go test -race`,
  size guard; plus the phase-specific checks above.
- I report what I actually ran, including checks that failed or could not run.
