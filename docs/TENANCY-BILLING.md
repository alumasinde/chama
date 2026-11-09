# Multi-Tenancy, URLs, and Monetisation

Answers three questions: is it multi-tenant, how are URLs built, and how the platform earns.
Read with `DESIGN.md` (architecture) and `DATA-MODEL.md` (tables).

---

## 1. Multi-tenancy: yes — pooled, single database

**Tenant = a chama (`groups` row).** One deployment, one Postgres database, one schema, tenant
rows discriminated by `group_id`. Identity (`users`) is platform-global because one human can be
in several chamas with a different role in each; **membership is the tenant boundary**, not the
user.

Why pooled and not database-per-tenant: pricing is KES 1,000–2,500/month per chama; per-tenant
databases would make migrations, backups and support cost more than the revenue. Pooled keeps
margins viable to thousands of tenants. Isolation is enforced in depth instead (§2).

```
users ──< group_members >── groups ──< everything else
          role_id, status_id     ^ tenant root
```

### 1.1 Isolation layers (all five, not one)

1. **Path, not header.** Group comes from the JWT-bound session plus `{groupUuid}` in the path.
   A client-sent `X-Group-Id`, `role`, or `group_id` body field is ignored — never read.
2. **Membership gate.** `GroupScope` middleware resolves `group_members` for the caller and
   returns **404** (not 403) when they are not an active member, so group existence never leaks.
3. **Repository contract.** Every tenant query takes `groupID` as its first parameter and filters
   on it. sqlc queries are written with `WHERE group_id = $1` unconditionally; a query without a
   tenant predicate fails review and a grep-based CI check flags `FROM transactions` without
   `group_id`.
4. **Composite FKs (schema-level proof).** Child tables carry `group_id` and reference their
   parent by `(parent_id, group_id)` against a `UNIQUE (id, group_id)` on the parent. A
   `loan_schedule_item` therefore *cannot* point at another tenant's loan, even with a service
   bug. This is the layer that makes cross-tenant corruption impossible rather than unlikely.
5. **RLS (deploy hardening, on by default in production).** Tenant tables get
   `ENABLE ROW LEVEL SECURITY` with `USING (group_id = current_setting('app.group_id')::bigint)`.
   The pool sets `SET LOCAL app.group_id` inside every transaction. If a future query forgets its
   predicate, Postgres returns nothing instead of another chama's ledger. Migrations run as owner
   (bypasses RLS); the app role does not.

### 1.2 Secrets are tenant-bound too

Payment credentials are AES-256-GCM with **AAD = `group_id || column`**, so ciphertext copied
from one tenant row into another fails to decrypt. `callback_secret` is per group; a callback URL
for one chama can never settle another chama's payment request (the secret is checked against
that group's setting *and* the request is looked up by that group's ID).

### 1.3 Noisy-neighbour and quota control

- Rate limits keyed per `(group_id, user_id)` and per `group_id` for money endpoints; platform
  limits only apply to OTP/registration.
- Queue fairness: a job per tenant (fine runs, report renders), with max 1 concurrent job per
  tenant per kind, so one 500-member chama cannot starve others.
- Plan quotas (members, groups per owner, report jobs/day, SMS allowance) are checked in the
  entitlement layer, never only in the UI.
- Per-tenant storage cap on generated exports (default 200 MB, oldest pruned).

### 1.4 Tenant lifecycle

| Stage | Trigger | Effect |
|---|---|---|
| `trialing` | group created | 30 days, all features, no card |
| `active` | invoice paid | normal |
| `past_due` | invoice overdue > 7 days | admin writes blocked (no new loans/invites/cycles); **member contributions and STK still accepted** |
| `expired` | overdue > 21 days | tenant read-only, exports still available |
| `cancelled` | admin cancels / finance voids | runs to period end, then read-only |
| `offboarded` | 90 days after expiry with no payment | export link emailed, then deletion job (ledger data only; audit retained 7 years) |

The deliberate choice: **expiry never blocks members' money.** A treasurer forgetting to pay must
not stop 50 people from contributing — that would destroy trust in the ledger and generate support
work. We restrict admin growth actions instead, which is where the pressure belongs.

### 1.5 Platform staff access (the new privileged plane)

`platform_users` with `platform_roles` (`owner`, `support`, `finance`), separate JWT audience
`platform`, separate session, no cross-use with tenant tokens. Platform staff see tenant
*metadata* (name, plan, status, usage, invoices) and **never decrypted payment credentials** —
there is no endpoint that returns them, for anyone. Reading a tenant's ledger requires a
time-boxed support grant the tenant admin issues; it is audited and shows as "Support view" in
the tenant's audit log.

### 1.6 Scale-out path (documented, not built)

All tenant access funnels through repositories with an explicit `groupID`, so a future
"dedicated database for large tenants" move is a connection-routing change plus a data copy, not
a rewrite. Trigger for revisiting: a single tenant above ~50 GB or a contractual isolation
requirement (sacco/bank partner). Not needed for v1.

---

## 2. URL design

One origin, path-based tenancy. No subdomains in v1.

| Purpose | URL |
|---|---|
| Web app (SPA) | `https://app.<domain>/` |
| API | `https://app.<domain>/api/v1/...` (same origin → no CORS, no preflight) |
| Tenant resource | `/api/v1/groups/{groupUuid}/contributions` |
| Tenant deep link | `/groups/{groupUuid}/contributions?period=2026-11` |
| Invite (public landing) | `/join/{inviteCode}` |
| Mobile deep link / app link | `https://app.<domain>/join/{inviteCode}` , scheme `chama://join/{code}` |
| M-Pesa callback (per chama) | `/api/v1/payments/mpesa/callback/{groupUuid}/{callbackSecret}` |
| Platform billing callback | `/api/v1/billing/mpesa/callback/{billingSecret}` |
| Platform console | `/platform` + `/api/v1/platform/...` (audience `platform`) |
| Meta / health | `/api/v1/meta`, `/healthz`, `/readyz` |
| Assets | `/assets/{hash}.{ext}` (immutable, 1 year) |

**Rules.**
- **UUIDs only in URLs.** `groupUuid` is the group `public_id`; sequential IDs, phone numbers and
  member numbers never appear in a path. Invoice URLs use `invoice.public_id`, not
  `INV-2026-000123` (that number is a document label, shown in the PDF only).
- **Tenant is never inferred from the host** and never from a header. `GroupScope` is
  membership-verified per request.
- **Invite links carry only the rotating code**, so forwarding a link exposes a join request, not
  the ledger. `/join/{code}` is the one public page: it explains the chama name and admin first
  name, asks the visitor to log in, then submits the join request. Wrong code → generic "This
  invite is no longer valid" (no existence probe).
- **Callback URLs contain an unguessable secret path segment** (32 bytes base64url), returned
  `403` on mismatch, always `200` on valid-shape unknown IDs. `PUBLIC_BASE_URL` env builds these;
  it must be a public HTTPS origin (a tunnel in dev), never derived from the request Host.
- **Unknown paths:** under `/api` → JSON 404 (never HTML). Elsewhere → SPA `index.html` (deep
  link reload works). Real static file wins, then fallback.
- **Versioning:** `/api/v1` forever-additive; breaking change ships as `/api/v2` with
  `Sunset` headers on the old one for 90 days.
- **Why no `umoja.app.<domain>`:** wildcard DNS + wildcard TLS + per-tenant cookies and CORS
  complexity, for zero user benefit — the dashboard is auth-gated, there is nothing to index, and
  the group switcher is one click. The upgrade path exists: add `groups.slug` (unique), then the
  same tenant middleware resolves host → group; no API change.

**Platform console separation.** `/platform` serves a separate SPA bundle and `/api/v1/platform/*`
requires `aud=platform` tokens; CSP is stricter and the tenant session cookie is irrelevant
(tokens are header-based). This means a stolen chama-admin token cannot call a platform endpoint
even if routing were misconfigured — the audience check fails first. v1 keeps it on one host for
deploy simplicity; `admin.<domain>` is a config change, not a redesign.

---

## 3. Monetisation

### 3.1 Principles

1. **The chama pays, never the member.** A member's payment screen shows no platform fee — the
   full amount lands on the chama's shortcode. Charging members would look like the platform is
   taking chama money, which contradicts the entire product.
2. **Billing is a separate domain.** Invoices, plans and billing payments live in platform tables.
   A platform invoice is **never** a row in `transactions`; putting it there would corrupt
   `v_member_balances` and each chama's cash-flow report.
3. **Flat + seats, no percentage of contributions.** A chama's savings are not our revenue base;
   a % cut would make us a party to the money flows and invite regulatory attention.
4. **No per-transaction fee.** STK is triggered on the chama's account; charging per payment
   would create an incentive to inflate payment volume against the treasurer's interest.

### 3.2 Plans (seed data, editable in the plan table / platform console)

| Plan | Price | Members | Includes |
|---|---|---|---|
| **Mwanzo** (free) | KES 0 | 15 | 1 group, contributions, fines, statements (CSV), 30-day trial of everything |
| **Chama** | KES 1,000/mo · KES 10,000/yr | 50 | all modules (loans, welfare, rotation, voting), CSV + PDF, audit log, 200 SMS/mo |
| **Chama Plus** | KES 2,500/mo · KES 25,000/yr | unlimited | + multi-group ownership, API access, audit export, 1,000 SMS/mo, priority support |
| Add-on: SMS pack | KES 300 / 500 msgs | — | prepaid credit |
| Add-on: extra group | KES 500/mo | — | for owners running several chamas |

Annual = 10 months (2 free) to pull cash forward and cut dunning cycles. Prices are seed rows,
so a promo or a price test is a data change, not a deploy. Pitch: at 50 members, KES 1,000/month
is KES 20 per member per month — less than one M-Pesa transaction charge, and it replaces a
paper notebook plus a treasurer's Sunday afternoon.

Revenue shape (sanity check, not a forecast): 150 chamas on Chama ≈ KES 150,000 MRR; running
cost at that size is one small Postgres + one app instance + SMS (OTP is the real variable, ~KES
0.8–1.2/message) — gross margin stays above 85% at list price.

### 3.3 Entitlements engine

`features` lookup (`loans`, `welfare`, `rotation`, `voting`, `pdf_export`, `audit_export`,
`api_access`, `multi_group`, `sms`) + `plan_features(plan_id, feature_id, limit_value)`.
`subscriptions` carries `plan_id`, `seats` (active members snapshotted at period start), status
and period. Middleware helpers: `requireFeature(ctx, "loans")` before module routes and
`checkLimit(ctx, "members", current+1)` inside services. Failure is `402 payment_required` with
`{code:"plan_upgrade_required", message:"Loans are part of the Chama plan.", upgrade_url:"…"}` —
never a silent no-op or a hidden button.

Day-31 trial without a card: at T-5 the admin gets a plan banner and an SMS; at T+0 the workspace
moves to Mwanzo limits (members beyond 15 stay readable, no new invites). No data is ever locked
behind a paywall that hides a member's own contributions — history stays visible on every plan.

### 3.4 Collection flow (platform's own paybill, not the chama's)

```
nightly billing.rollup
  → for each subscription at period end: snapshot seats, create invoice
     lines: subscription price, seat overage, add-ons, VAT 16% (configurable), credits
  → status open, due_at = issued_at + 7d
  → notify treasurer (SMS + in-app + email if set)

treasurer: GET /groups/{id}/billing  →  POST /billing/invoices/{invoiceUuid}/pay  (step-up PIN)
  → STK Push on the PLATFORM shortcode (env creds, never tenant creds)
  → callback /api/v1/billing/mpesa/callback/{secret}
  → tx: billing_payments completed + invoice paid + subscription period extended
  → receipt in-app, invoice PDF regenerated as PAID
```

`BillingProvider` interface mirrors `PaymentProvider` (`RequestSTK`, `QuerySTK`,
`VerifyNotification`), with `daraja` and `mock` implementations. Manual bank transfer and
"finance marks paid" paths exist for chamas that pay by cheque, both audited.

**Recurring reality check (documented so nobody promises auto-charge):** M-Pesa STK Push cannot
debit silently — every collection needs the payer's PIN. So the ladder is:

| When | Action |
|---|---|
| T-7 | reminder (SMS + in-app + push), invoice preview visible |
| T-0 | invoice issued + **STK prompt** sent to treasurer |
| T+3, T+7, T+14 | scheduled STK retries (max 3/day total), dunning SMS with a one-tap pay link |
| T+7 | `past_due`: admin writes limited, member contributions continue |
| T+21 | `expired`: read-only, exports available |
| T+90 | offboarding: final export, then deletion of ledger data (audit kept) |

For chamas that want true automation, the billing screen offers **M-Pesa Ratiba** setup
instructions (the treasurer creates a standing order to our paybill in the M-Pesa app or `*334#`);
we verify incoming payments by reference prefix. Card tokenization (Paystack 2.9% cards, 1.5%
M-Pesa; IntaSend ~3%) is a later option for diaspora members or international cards — the
`BillingProvider` interface is the seam, and it costs 1.5–3% of revenue, which is why it is not
the default path.

### 3.5 Fairness rules that protect retention

- Downgrade applies at period end, never mid-period; upgrade is immediate with a prorated credit
  line (never a second charge for the same month).
- A failed payment never deletes data and never hides a member's statements.
- Seat overage is billed at KES 20/member/month above the cap with a 5-member soft tolerance, and
  the admin is warned at 90% of the cap before it happens — no surprise invoices.
- If our own STK causes a double debit, the second payment is auto-credited to the next invoice
  (`invoice_line_kinds = credit`) rather than refunded manually.

### 3.6 What this adds to the build

New module `internal/billing` (catalog, subscriptions, invoices, entitlements, dunning jobs,
platform-auth) plus `/platform` console pages. Slotted as **Phase 8**, with the entitlement hooks
and free-trial subscription created at group creation in **Phase 2** so gates exist from the
start rather than being retrofitted. Flutter gets a small admin-only "Plan & billing" screen under
Group; the real billing console is web.

---

## 4. Assumptions to confirm

1. Prices above are placeholders — confirm before I seed them.
2. We run our own M-Pesa paybill for billing (requires Safaricom onboarding in the business name);
   if that is not ready, Phase 8 ships with manual bank-transfer + finance-marked-paid and STK
   enabled later by config.
3. VAT 16% is applied on invoices and shown separately; confirm if you are not VAT-registered yet
   (then `vat_rate = 0` in `billing_settings`).
4. Free plan stays at 15 members indefinitely (growth channel), not 14-day-only.
5. Platform console is on the same host at `/platform` for v1.
