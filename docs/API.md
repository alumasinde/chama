# API Surface — `/api/v1`

Implemented through Phase 6: §3 auth/profile, §4 groups/members/invites/settings, §5–§6
ledger and M-Pesa, §7 loans, §8 fines/welfare/rotation, and §9 notifications, reports and audit.
Billing and the platform console remain the agreed contract for Phase 8.

REST, JSON, UTF-8. Same origin for web and mobile. `docs/openapi.yaml` mirrors this document;
keep both in sync when adding an endpoint.

## 1. Conventions

**Error envelope** — every non-2xx:

```json
{ "error": { "code": "insufficient_step_up", "message": "Enter your PIN to continue.",
  "fields": { "amount": "must be at least KES 100" } } }
```

Codes are stable (`validation_failed`, `unauthorized`, `forbidden`, `not_found`,
`conflict`, `step_up_required`, `rate_limited`, `idempotency_conflict`, `request_in_progress`,
`internal_error`). `fields` is present only for validation.

**List endpoints** — `?limit=25&cursor=<opaque>&sort=-created_at&q=&from=&to=` plus
documented filters. Response: `{ "data": [...], "page": { "next_cursor": "...", "has_more": true } }`.
Cursors are base64(`sort_key|id`) and validated; `limit` capped at 100.

**Idempotency** — required `Idempotency-Key` (UUIDv4 or ULID) on money POSTs:
`payments/stk`, `transactions/manual`, `transactions/{id}/reverse`, `loans/{id}/disburse`,
`loans/{id}/repayments`, `fines/{id}/pay`, `welfare/claims/{id}/payout`,
`rotation/cycles/{id}/payouts`. Stored 24 h with the response body.

**Step-up** — `X-Step-Up-Token` required on those same endpoints (see DESIGN §5).

**Headers** — request: `Authorization: Bearer <jwt>`, `X-Client: mobile|web`, `X-Request-Id`
(optional, echoed). Response: `X-Request-Id`, `Cache-Control: no-store` on anything personalised.

**Money** — all amounts are JSON strings with 2 decimals (`"1500.00"`), never numbers, to avoid
float in JS/Dart.

**IDs** — `public_id` UUID in paths and bodies. A sequential ID never appears in a response.
`{groupId}` in paths means group `public_id`.

**Time** — ISO-8601 UTC (`2026-11-09T06:15:00Z`). Date-only fields are `Africa/Nairobi` calendar
dates (`due_date`, `payout_date`, `assessed_on`).

---

## 2. RBAC matrix

Roles resolve from `group_members` per request; `admin` ⊃ `treasurer` ⊃ `secretary` ⊃ `member`
for reads, but write permissions are explicit:

| Capability | admin | treasurer | secretary | member |
|---|---|---|---|---|
| read group, members, own statement | ✓ | ✓ | ✓ | ✓ |
| read all members' statements / ledgers | ✓ | ✓ | ✓ | – |
| edit group profile, roles, approve joins | ✓ | – | – | – |
| payment settings (write / verify) | ✓ | ✓ | – | – |
| manual entry, reverse, reconcile | ✓ | ✓ | – | – |
| loan settings, fines rules | ✓ | ✓ | – | – |
| loan approve / reject | ✓ | ✓ | – | – |
| loan disburse / repayment record | – | ✓ | – | – |
| fines waive | ✓ | ✓ | – | – |
| welfare claim decide / payout | ✓ | ✓ | – | – |
| rotation create / start / payout / propose | ✓ | ✓ | – | – |
| rotation vote | ✓ | ✓ | ✓ | ✓ |
| reports + exports | ✓ | ✓ | ✓ | own only |
| audit log | ✓ | – | – | – |
| STK pay, own loan request, own claim | ✓ | ✓ | ✓ | ✓ |

`secretary` is read-mostly plus member records and voting: it exists so a group can have a
record-keeper who is not a signatory.

---

## 3. Auth & profile

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/auth/otp/request` | public | `{phone_number, purpose}`; 3/10 min; returns `{expires_in, resend_after}`; dev returns `dev_code` only when `APP_ENV=development` |
| POST | `/auth/otp/verify` | public | `{phone_number, code, purpose}` → new user: `{registration_token}`; existing: token pair |
| POST | `/auth/register` | registration token | `{first_name, last_name, pin, email?, national_id?, password?}` → token pair |
| POST | `/auth/login` | public | `{phone_number, password}` → token pair (rate-limited) |
| POST | `/auth/pin/verify` | auth | `{pin}` → `{step_up_token, expires_in}` |
| POST | `/auth/pin/reset` | public | `{phone_number, code, new_pin}` (OTP `pin_reset`) |
| POST | `/auth/token/refresh` | public | `{refresh_token, device_id}` → rotated pair; reuse revokes family |
| POST | `/auth/logout` | auth | revokes family |
| GET | `/me` | auth | profile + memberships (group, role, status) |
| PATCH | `/me` | auth | `first_name, last_name, email, national_id` |
| POST | `/me/pin` | auth + step-up | change PIN (requires current PIN) |
| POST | `/me/password` | auth | set/change password (requires PIN) |
| GET | `/me/devices` · POST `/me/devices` · DELETE `/me/devices/{id}` | auth | OTP/PIN-gated device registration; delete revokes family |
| GET | `/meta` | public | `{app_name, short_name, currency, primary_color, support_email, features, server_time}` |
| GET | `/healthz` · `/readyz` | public | liveness / DB ping |

---

## 4. Groups & memberships

| Method | Path | Role |
|---|---|---|
| POST | `/groups` | auth (creator becomes admin) |
| GET | `/groups` | auth (my groups) |
| GET | `/invites/{code}` | public (`group_name`, `admin_first_name`, `active_members`, `currency`, `contribution_amount`, `contribution_frequency`) |
| GET · PATCH | `/groups/{groupId}` | member · admin |
| POST | `/groups/join` | auth (`{invite_code}` → membership `pending`) |
| GET | `/groups/{groupId}/members` | member |
| PATCH | `/groups/{groupId}/members/{userId}` | admin (`{role_code?, status_code?}`) |
| POST | `/groups/{groupId}/invites/rotate` | admin |
| GET · PUT | `/groups/{groupId}/payment-settings` | admin/treasurer |
| POST | `/groups/{groupId}/payment-settings/verify` | **planned** — live Daraja verification is not mounted yet |
| GET · PUT | `/groups/{groupId}/loan-settings` | admin/treasurer |
| GET · POST · PATCH | `/groups/{groupId}/fine-rules` | admin/treasurer |

`GET payment-settings` returns `{configured, shortcode_type, shortcode,
account_reference_template, daraja_environment, consumer_key_masked: "••••7f2a",
consumer_secret_masked, passkey_masked, is_verified, verified_at, updated_at}` — never a secret.
`PUT` accepts plaintext creds over TLS and encrypts them with AES-256-GCM (AAD binds the group
and column); omitting a secret keeps the stored value. The `callback_url` (which embeds the
unguessable group secret) appears only in the `PUT` response that first saves it.

`GET /invites/{code}` is the public preview used by `/join/{code}`; it returns only the chama
name, inviting admin's first name, active member count and contribution terms. Invalid or
rotated codes return the same generic `404`. `POST /groups/join` returns
`{group_id, group_name, status: "pending", message}` and is idempotent. Pending members get
`403 membership_pending` from group-scoped reads. Member
updates take `{role?, status?}` with role ∈ `admin|treasurer|secretary|member` and status ∈
`active|pending|suspended|exited`; demoting or removing the last active admin returns
`409 last_admin`. Rotating the invite returns `{invite_code}` and invalidates the old code.

---

## 5. Ledger, contributions, statements

| Method | Path | Role |
|---|---|---|
| GET | `/groups/{groupId}/transactions` | **implemented** — member, `?limit=1..100&cursor=`, newest first |
| GET | `/groups/{groupId}/transactions/{txId}` | **implemented** — member, receipt detail |
| GET | `/groups/{groupId}/contributions` | member (schedule with due/paid/overdue per member) |
| GET | `/groups/{groupId}/contributions/summary` | member |
| GET | `/groups/{groupId}/transactions` | member (filters: type, status, channel, user, from, to) |
| GET | `/groups/{groupId}/transactions/{txId}` | member |
| POST | `/groups/{groupId}/transactions/manual` | treasurer (idempotent, step-up, audited) |
| POST | `/groups/{groupId}/transactions/{txId}/reverse` | admin/treasurer (idempotent, step-up) |
| GET | `/groups/{groupId}/statement` | admin/treasurer/secretary |
| GET | `/me/statement?group_id=` | auth |
| GET | `/me/balances` | auth (per group: savings, fines, loan) |

Manual entry body: `{user_id, transaction_type, channel, amount, reference_code, period_label?,
narration}`. Rejection reasons are explicit (`amount_exceeds_expected`, `period_closed`).

---

## 6. Payments

| Method | Path | Role |
|---|---|---|
| POST | `/groups/{groupId}/payments/stk` | member (idempotent, step-up) |
| GET | `/groups/{groupId}/payments/requests` | member (own) / treasurer (all) |
| POST | `/groups/{groupId}/payments/{requestId}/reconcile` | treasurer |
| POST | `/payments/mpesa/callback/{groupPublicId}/{callbackSecret}` | public, secret-authenticated |
| POST | `/payments/mock/callback` | dev/test only (`PAYMENTS_PROVIDER=mock`, 404 in production) |

STK is implemented. Body: `{amount, purpose, phone_number?}` where purpose ∈
`contribution | fine | loan_repayment | welfare_contribution`. Requires both
`X-Step-Up-Token` (403 `step_up_required` without it) and `Idempotency-Key` (8–128 chars;
replaying the same key and body returns the original `202`, a different body returns
`409 idempotency_conflict`, and an unfinished request returns `409 request_in_progress`).
202 response: `{payment_request_id, checkout_request_id, status: "pending", amount, purpose}`.
Amounts must be whole shillings (`422 amount_not_whole_shillings`); missing credentials return
`422 payment_settings_missing`, and a Daraja rejection returns `502 provider_error`.

STK uses the chama's own Till/Paybill and credentials, with account reference template
tokens `{member_short}` and `{period}`. A pending ledger row and the payment request are
written in one transaction, so a member sees the request immediately.

Callback always replies `200 {"ResultCode":0,"ResultDesc":"Accepted"}` after persisting, even for
unknown IDs (no information leak), with mismatched group/secret → `403` empty body. The path
secret is compared in constant time. Duplicate callbacks settle at most once (the second leaves
the completed row untouched), and a failed result stores `status: failed`.

---

## 7. Loans

| Method | Path | Role |
|---|---|---|
| GET | `/groups/{groupId}/loans/settings` | member |
| PUT | `/groups/{groupId}/loans/settings` | admin/treasurer |
| POST | `/groups/{groupId}/loans` | member (step-up) |
| GET | `/groups/{groupId}/loans` | member (own) / admin/treasurer (all); `?status=` |
| GET | `/groups/{groupId}/loans/{loanId}` | member (own) / admin/treasurer |
| GET | `/groups/{groupId}/loans/{loanId}/schedule` | member (own) / admin/treasurer |
| POST | `/groups/{groupId}/loans/{loanId}/guarantors/respond` | invited guarantor (`{decision: accepted|declined}`) |
| POST | `/groups/{groupId}/loans/{loanId}/decision` | admin/treasurer (`{decision, comment}`) |
| POST | `/groups/{groupId}/loans/{loanId}/disburse` | treasurer (step-up) |
| POST | `/groups/{groupId}/loans/{loanId}/repayments` | treasurer (step-up) |
| POST | `/groups/{groupId}/loans/defaults/run` | admin/treasurer |

Application body: `{amount, term_months, purpose, guarantors: [{user_id, amount}]}`. The
engine enforces `allow_loans`, the savings multiple, the maximum term and the exact guarantor
count. Each guarantee is checked against that member's savings minus guarantees on live loans
(`422 guarantor_cover_exceeded`). Applications start in `pending_guarantors`, or
`pending_approval` when the policy requires no guarantors.

When every guarantor has responded, the loan moves to `pending_approval` if enough accepted,
otherwise it is rejected automatically. `decision` answers `409 loan_not_pending_approval`
while guarantors are still pending (or the loan is no longer awaiting a decision), and
`422 guarantors_pending` / `422 guarantors_missing` if the tally is short.

Approval persists the amortization schedule: flat interest spreads `P × monthly_rate × n`;
reducing balance uses `EMI = P·i / (1 − (1+i)^−n)` with interest recomputed on the opening
balance. Rounding is half-up per installment and the final row absorbs the remainder, so
`Σ principal_due = principal` and `Σ interest_due = total_interest` exactly. Schedules are
never recomputed on read.

Disbursement and repayment are manual records only (no B2C). Both require a fresh step-up
token, create a completed ledger row (`loan_disbursement` or `loan_repayment`) and are guarded
by the expected loan status. Repayments allocate oldest-first across unpaid installments; an
amount above the outstanding balance returns `422 repayment_exceeds_balance`. The nightly
default scan (03:00 EAT) marks an active loan `defaulted` when an installment is unpaid for
30+ days; the same scan is available on demand.

Loan detail includes `status`, `principal`, `interest_rate`, `interest_method`, `term_months`,
`total_interest`, `total_payable`, `paid_to_date`, `outstanding`, `guarantors[]` and
`approvals[]`; the schedule endpoint returns `installment_no`, `due_date`, `principal_due`,
`interest_due`, `paid_amount`, `total_due` and `paid_at`.

---

## 8. Fines, welfare, rotation

| Method | Path | Role |
|---|---|---|
| GET | `/groups/{groupId}/fines/rules` | member |
| PUT | `/groups/{groupId}/fines/rules/{fineType}` | admin/treasurer |
| GET | `/groups/{groupId}/fines` | member (own) / admin/treasurer (all); `?status=` |
| POST | `/groups/{groupId}/fines` | admin/treasurer (custom fine) |
| GET | `/groups/{groupId}/fines/{fineId}` | member (own) / admin/treasurer |
| POST | `/groups/{groupId}/fines/{fineId}/waive` | admin/treasurer (reason required) |
| POST | `/groups/{groupId}/fines/{fineId}/pay` | treasurer (manual, step-up) |
| POST | `/groups/{groupId}/fines/evaluate` | admin/treasurer |
| GET · PUT | `/groups/{groupId}/welfare` | member · admin/treasurer |
| GET | `/groups/{groupId}/welfare/contributions` | member (own) / admin/treasurer (all) |
| POST | `/groups/{groupId}/welfare/contributions` | admin/treasurer (manual, step-up) |
| GET · POST | `/groups/{groupId}/welfare/claims` | member |
| GET | `/groups/{groupId}/welfare/claims/{claimId}` | member (own) / admin/treasurer |
| POST | `/groups/{groupId}/welfare/claims/{claimId}/decision` | admin/treasurer |
| POST | `/groups/{groupId}/welfare/claims/{claimId}/payout` | treasurer (idempotent, step-up) |
| POST · GET | `/groups/{groupId}/rotation/cycles` | admin/treasurer · member |
| GET | `/groups/{groupId}/rotation/cycles/{cycleId}` | member |
| POST | `/groups/{groupId}/rotation/cycles/{cycleId}/start` | admin/treasurer (materialises slots) |
| GET · POST | `/groups/{groupId}/rotation/cycles/{cycleId}/proposals` | member · admin/treasurer (`{slots[], closes_at, quorum_percent}`) |
| GET | `/groups/{groupId}/rotation/proposals/{proposalId}` | member (includes tally + own vote) |
| POST | `/groups/{groupId}/rotation/proposals/{proposalId}/vote` | member (`{choice}`, upsert while open) |
| POST | `/groups/{groupId}/rotation/cycles/{cycleId}/payouts` | treasurer (idempotent, step-up) |
| GET | `/me/rotation` | auth (my position and payout date) |

Fine rules use `{calculation_method, amount_or_rate, grace_days}` for types
`late_contribution`, `late_loan_repayment`, `absence` and `custom`; a percentage cannot exceed
100. Custom fines are always `custom` with no rule, and require `{user_id, amount, reason}`.

Evaluation covers the last completed period for the chama's cadence (weekly, biweekly,
monthly or quarterly) and charges active members with no completed contribution in it. The
nightly job runs at 02:00 EAT and writes nothing for a period until its grace window has
passed. It is idempotent per `(group, member, rule, period)`, so a second run creates zero
rows. Waiving requires a reason and only works on an unpaid fine (`409 fine_not_unpaid`).
Manual payment must be for the full fine amount and writes a completed `fine` ledger row in
the same transaction as the status change.

Welfare has one fund per chama (`GET` returns `{configured:false}` before setup). Contributions
are one per member per period (`?period_label`, default current `YYYY-MM`), unique on
`(fund, member, period)`; a completed M-Pesa `welfare_contribution` links to the same row. Claims
move `pending → approved|rejected → paid`; a payout requires an approved claim with enough fund
balance, writes a completed `welfare_payout` ledger row and marks the claim paid in one
transaction. Repeating a payout returns `409 claim_not_approved`.

Rotation cycles are `draft → active → completed`. `random` starts with a stored hex seed that
derives the order from `SHA-256(seed:member)`; `manual` takes the order when created; `vote`
starts only after a passing proposal. A proposal names every active member exactly once, has a
`closes_at` within 30 days and `quorum_percent` (default 60). Votes are `for|against|abstain`,
one per member, upserted while open. Quorum is `ceil(eligible × percent / 100)`; a tie fails
because passing requires `for > against`. A passed proposal auto-starts its cycle. Payouts follow
slot position, are step-up-protected, write `rotation_payout` ledger rows, and the final payout
completes the cycle. `GET /me/rotation` returns the caller’s position and payout date.

---

## 9. Notifications, reports, audit

| Method | Path | Role |
|---|---|---|
| GET | `/notifications` | auth (`?unread=true`) |
| POST | `/notifications/read` | auth (`{ids[]}` or `{all:true}`) |
| POST | `/me/devices` | auth (FCM token; already listed above) |
| GET | `/groups/{groupId}/reports/dashboard` | member |
| GET | `/groups/{groupId}/reports/loan-book` | admin/treasurer/secretary |
| GET | `/groups/{groupId}/reports/defaulters` | admin/treasurer/secretary |
| GET | `/groups/{groupId}/reports/fines` | admin/treasurer/secretary |
| GET | `/groups/{groupId}/reports/jobs` | admin/treasurer/secretary |
| POST | `/groups/{groupId}/reports/jobs` | admin/treasurer/secretary (`{report_code, params, format}`) |
| GET | `/groups/{groupId}/reports/jobs/{jobId}/download` | admin/treasurer/secretary (streams CSV/PDF) |
| GET | `/groups/{groupId}/audit-logs` | admin (filters: action, entity_type, from, to) |
| GET | `/groups/{groupId}/audit-logs/{auditId}` | admin (full before/after entry) |

Notifications are inserted once per `(user_id, dedupe_key)` with `ON CONFLICT DO NOTHING`, then
pushed best-effort to the member’s registered devices through the `Pusher` interface. The
default provider is `console`; `PUSH_PROVIDER=fcm` uses the legacy FCM key when configured.
Domain hooks cover payment received, contribution due reminders, guarantor requests, loan
updates, fines and rotation turns. `GET /notifications?unread=true` returns
`{data, unread_count}`; `POST /notifications/read` accepts `{ids:[uuid]}` or `{all:true}` and
returns `{marked_read}`. A failed push never fails the domain action or creates a second row.

Nightly jobs (EAT): fines 02:00, loan defaults 03:00, rotation proposal close 04:00,
contribution reminders 08:00.

---

## 10. Billing (tenant) and platform console

Billing is separate from the ledger: invoices never appear in `/groups/{id}/transactions`.

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/groups/{groupId}/billing` | admin | plan, status, period end, seats, usage, next invoice |
| GET | `/groups/{groupId}/billing/plans` | admin | public catalog with KES prices and feature lists |
| POST | `/groups/{groupId}/billing/subscribe` | admin (step-up) | `{plan_code, cycle}`; upgrade prorated, downgrade at period end |
| POST | `/groups/{groupId}/billing/cancel` | admin (step-up) | `{at_period_end: true}` |
| GET | `/groups/{groupId}/billing/invoices` | admin | cursor list, `?status=open` |
| GET | `/groups/{groupId}/billing/invoices/{invoiceUuid}` | admin | lines, VAT, payments |
| POST | `/groups/{groupId}/billing/invoices/{invoiceUuid}/pay` | admin (step-up, idempotent) | STK on the **platform** shortcode; `202` |
| POST | `/groups/{groupId}/billing/usage` | admin | read-only metrics for the current period |
| POST | `/billing/mpesa/callback/{billingSecret}` | public | platform billing callback |
| POST | `/platform/auth/login` | public | email + password (+ TOTP when enabled); `aud=platform` token |
| POST | `/platform/auth/token/refresh` | platform | same rotation rules as tenants |
| GET | `/platform/groups` | platform | tenant list: plan, status, MRR, last activity |
| GET | `/platform/groups/{groupId}` | platform | metadata + usage; **never** payment credentials or ledger |
| GET | `/platform/invoices` · `POST /platform/invoices/{invoiceUuid}/mark-paid` | finance | manual settlement (bank/cheque), audited, requires reference |
| POST | `/platform/invoices/{invoiceUuid}/void` · `/credit-note` | finance | audited |
| GET | `/platform/plans` · `POST` · `PATCH /platform/plans/{code}` | owner | catalog edits, no deploy |
| GET | `/platform/revenue` | owner/finance | MRR, collected, outstanding, churn |

`402 payment_required` is reserved for entitlement failures:
`{code:"plan_upgrade_required"|"subscription_expired"|"member_limit_reached", message, upgrade_url}`.
Feature gates return this before handler execution, so a client never sees a half-finished action.

---

## 11. Status codes used

`200` read/update · `201` created (including report exports) · `202` accepted (STK, reconcile) · `204` deleted ·
`400` validation · `401` missing/expired token · `402` plan/entitlement (`plan_upgrade_required`,
`subscription_expired`, `member_limit_reached`) · `403` permission or step-up · `404` not found or
not a member (no existence leak) · `409` conflict/idempotency · `422` business rule violation
(`loan_exceeds_limit`, `pin_locked`) · `429` rate limited · `500` internal.

Business-rule failures use `422` with a machine code the app maps to friendly copy, e.g.
`loan_exceeds_limit` → "This is more than your savings allow. Maximum is KES 45,000."
