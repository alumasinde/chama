# Data Model

PostgreSQL 15+. No `ENUM` types. Every status/type/role/channel is a lookup table with an FK.
All money `NUMERIC(15,2)`. All timestamps `TIMESTAMPTZ` (UTC). Internal PKs
`BIGINT GENERATED ALWAYS AS IDENTITY`; APIs expose `public_id UUID` only.

---

## 1. Lookup tables

Uniform shape, one migration each group, seeded rows included in the same migration:

```sql
CREATE TABLE member_roles (
  id SMALLINT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  description TEXT, sort_order INT NOT NULL DEFAULT 0, is_active BOOLEAN NOT NULL DEFAULT TRUE
);
```

Codes are stable identifiers; Go uses them via constants in `internal/*/models.go`
(`const RoleAdmin = "admin"`) and resolves to `id` once at bootstrap (or by join).
Seeds are inserted with `ON CONFLICT (code) DO NOTHING`, so re-running is safe.

| Table | Seeded `code`s |
|---|---|
| `member_roles` | `admin`, `treasurer`, `secretary`, `member` |
| `member_statuses` | `pending`, `active`, `suspended`, `exited` |
| `contribution_frequencies` | `weekly`, `biweekly`, `monthly`, `quarterly` |
| `transaction_types` | `contribution`, `fine`, `loan_disbursement`, `loan_repayment`, `welfare_contribution`, `welfare_payout`, `rotation_payout`, `adjustment`, `reversal` |
| `transaction_statuses` | `pending`, `completed`, `failed`, `cancelled`, `reversed` |
| `payment_channels` | `mpesa_stk`, `mpesa_manual`, `cash`, `bank_transfer`, `other` |
| `payment_shortcode_types` | `paybill`, `till` |
| `loan_statuses` | `pending_guarantors`, `pending_approval`, `approved`, `rejected`, `active`, `fully_paid`, `defaulted`, `written_off` |
| `guarantor_statuses` | `pending`, `accepted`, `declined` |
| `fine_types` | `late_contribution`, `late_loan_repayment`, `absence`, `custom` |
| `fine_calculation_methods` | `flat`, `percentage` |
| `interest_methods` | `flat`, `reducing_balance` |
| `welfare_claim_statuses` | `pending`, `approved`, `rejected`, `paid` |
| `rotation_cycle_statuses` | `draft`, `active`, `completed` |
| `notification_types` | `contribution_due`, `payment_received`, `loan_update`, `guarantor_request`, `fine_applied`, `rotation_turn`, `general` |
| `otp_purposes` | `login`, `registration`, `pin_reset` |
| `report_job_statuses` | `queued`, `running`, `done`, `failed` |

Additional lookups required by the feature set (same shape):

| Table | Seeded `code`s |
|---|---|
| `fine_statuses` | `unpaid`, `paid`, `waived` |
| `approval_decisions` | `approved`, `rejected` |
| `rotation_ordering_modes` | `random`, `manual`, `vote` |
| `rotation_proposal_statuses` | `open`, `passed`, `rejected`, `cancelled` |
| `vote_choices` | `for`, `against`, `abstain` |
| `daraja_environments` | `sandbox`, `production` |
| `device_platforms` | `android`, `ios`, `web` |
| `platform_roles` | `owner`, `support`, `finance` |
| `features` | `loans`, `welfare`, `rotation`, `voting`, `pdf_export`, `audit_export`, `api_access`, `multi_group`, `sms` |
| `billing_cycles` | `monthly`, `yearly` |
| `subscription_statuses` | `trialing`, `active`, `past_due`, `expired`, `cancelled` |
| `invoice_statuses` | `draft`, `open`, `paid`, `void`, `uncollectible` |
| `invoice_line_kinds` | `subscription`, `seats`, `overage`, `addon`, `credit`, `tax` |

Deliberate note: because the lookup shape is fixed at seven columns, **direction**
(debit/credit effect) is not a column. It lives in `internal/contributions/models.go`
(`ledgerTypeDirection`) and is mirrored by the `v_ledger_entries` view's `CASE`, which is the
only place SQL needs it.

---

## 2. Identity tables

### `users`
| column | type | notes |
|---|---|---|
| id | bigint identity PK | |
| public_id | uuid NOT NULL UNIQUE DEFAULT gen_random_uuid() | API identity |
| phone_number | text NOT NULL UNIQUE | E.164, normalised on input |
| first_name | text NOT NULL | no `full_name`, ever |
| last_name | text NOT NULL | |
| email | text NULL | `UNIQUE (lower(email)) WHERE email IS NOT NULL` |
| national_id_enc | bytea NULL | AES-256-GCM |
| password_hash | text NULL | argon2id, nullable (OTP-only members) |
| is_active | boolean NOT NULL DEFAULT TRUE | |
| phone_verified_at | timestamptz NULL | |
| created_at / updated_at | timestamptz NOT NULL DEFAULT now() | |

### `user_pins`
`user_id` bigint PK → users, `pin_hash` text NOT NULL, `failed_attempts` int DEFAULT 0,
`locked_until` timestamptz NULL, `updated_at` timestamptz NOT NULL.

### `user_devices`
`id` bigint identity PK, `user_id` FK, `device_token` text NULL (FCM), `platform_id` smallint FK
`device_platforms`, `device_name` text, `biometric_enabled` boolean DEFAULT FALSE,
`last_seen_at` timestamptz, `created_at` timestamptz. Index `(user_id)`.

### `refresh_tokens`
`id`, `user_id` FK, `token_hash` bytea NOT NULL UNIQUE, `device_id` FK NULL,
`user_agent` text, `ip` inet, `expires_at`, `revoked_at` NULL, `replaced_by` bigint NULL
self-FK, `created_at`. Index `(user_id, expires_at)`.

### `otp_codes`
`id`, `phone_number` text, `code_hash` bytea, `purpose_id` smallint FK `otp_purposes`,
`expires_at`, `consumed_at` NULL, `attempts` smallint DEFAULT 0, `request_ip` inet,
`created_at`. Index `(phone_number, purpose_id, created_at DESC)`.

### `auth_throttle`
`key` text PK (`otp:send:+2547…`, `pin:userId`, `login:ip`), `window_start`, `attempts` int,
`locked_until` timestamptz NULL, `updated_at`.

---

## 3. Group tables

### `groups`
`id`, `public_id` uuid unique, `name` text, `invite_code` text unique (8 chars, Crockford
base32), `description` text, `currency_code` char(3) DEFAULT 'KES', `contribution_amount`
numeric(15,2), `contribution_frequency_id` FK, `contribution_day` smallint (1–28 or weekday
0–6), `late_grace_days` int DEFAULT 3, `created_by` FK users, `created_at`, `updated_at`.
Index `(created_by)`.

### `group_payment_settings`
`group_id` bigint PK/FK, `shortcode_type_id` FK, `shortcode` text, `account_reference_template`
text DEFAULT `CHAMA-{member_short}-{period}`, `daraja_environment_id` FK, `daraja_consumer_key_enc`
bytea, `daraja_consumer_secret_enc` bytea, `daraja_passkey_enc` bytea, `callback_secret_enc`
bytea, `is_verified` bool DEFAULT FALSE, `verified_at`, `updated_by` FK, `updated_at`.
Nothing in this table is ever selected into an API response except type, shortcode, masked key,
`is_verified`, `updated_at`.

### `group_members`
`id`, `group_id` FK, `user_id` FK, `role_id` FK `member_roles`, `status_id` FK `member_statuses`,
`joined_at`, `approved_by` FK NULL, `exited_at` NULL, `created_at`.
`UNIQUE (group_id, user_id)`, index `(user_id, group_id)`, index `(group_id, status_id)`.

### `group_loan_settings`
`group_id` bigint PK/FK, `interest_rate` numeric(6,3) (monthly %), `interest_method_id` FK,
`max_multiple_of_savings` numeric(6,2), `max_term_months` smallint, `guarantors_required`
smallint, `allow_loans` bool DEFAULT TRUE, `updated_at`.

### `fine_rules`
`id`, `group_id` FK, `fine_type_id` FK, `calculation_method_id` FK, `amount_or_rate` numeric(15,2),
`grace_days` smallint DEFAULT 0, `is_active` bool DEFAULT TRUE, `updated_at`.
Partial unique: `UNIQUE (group_id, fine_type_id) WHERE is_active`.

---

## 4. Ledger

### `transactions` — append-only
| column | type | notes |
|---|---|---|
| id | bigint identity PK | |
| public_id | uuid unique | |
| group_id | bigint FK | |
| user_id | bigint FK | member the row belongs to |
| transaction_type_id | smallint FK | |
| status_id | smallint FK | pending/completed/failed/cancelled/reversed |
| channel_id | smallint FK NULL | null for pure adjustments/payouts |
| amount | numeric(15,2) NOT NULL | always positive; direction from type |
| reference_code | text NULL | M-Pesa receipt / bank ref |
| idempotency_key | text NULL | |
| related_loan_id / related_fine_id | bigint FK NULL | |
| period_label | text NULL | e.g. `2026-11`, `W45-2026` |
| narration | text | |
| raw_callback | jsonb NULL | provider payload |
| recorded_by | bigint FK users NULL | null = system |
| created_at | timestamptz | |
| completed_at | timestamptz NULL | |

Constraints: `amount > 0`; `UNIQUE (group_id, reference_code) WHERE reference_code IS NOT NULL`;
`UNIQUE (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL`.
Indexes: `(group_id, created_at DESC)`, `(user_id, group_id)`, `(group_id, status_id)`,
`(related_loan_id)`, `(transaction_type_id, completed_at)`.

**Trigger `trg_transactions_append_only`** (plpgsql, migration `0010`):
- `BEFORE DELETE` → `RAISE EXCEPTION 'transactions are append-only'`.
- `BEFORE UPDATE`: allows only `pending → completed | failed | cancelled` and only changes to
  `status_id, reference_code, raw_callback, completed_at`. Any update of a row whose `OLD.status_id`
  is not `pending` raises. Anything else raises. This is what makes "never UPDATE completed rows"
  a database fact rather than a code review note.

### `payment_requests`
`id`, `public_id` uuid, `group_id`, `user_id`, `phone_number`, `amount`, `purpose_type_id` FK
`transaction_types`, `checkout_request_id` text UNIQUE, `merchant_request_id` text,
`status_id` FK `transaction_statuses`, `result_code` text, `result_desc` text,
`transaction_id` FK NULL, `idempotency_key` text, `created_at`, `updated_at`.
Indexes: `(checkout_request_id)` unique, `(group_id, created_at DESC)`,
`(status_id, created_at) WHERE status_id IN (pending)` for the reconciler.

### `idempotency_keys`
PK `(user_id, key)`; `route` text, `request_hash` bytea, `state` text (`in_progress|completed`),
`status_code` int NULL, `response_body` jsonb NULL, `created_at`, `expires_at` (24 h).
Index `(expires_at)` for cleanup.

### Read models (views, no stored balances)
- `v_ledger_entries` — completed rows with sign: `+` for contributions, welfare contributions,
  repayments, payouts received, fines paid; `−` for disbursements/payouts made.
- `v_member_balances` — per `(group_id, user_id)`: `savings_balance`, `fines_outstanding`,
  `loan_outstanding`, `welfare_paid`, `net_position`.
- `v_group_totals` — per group: `contributions_collected`, `loans_outstanding`, `fines_outstanding`,
  `cash_in_hand_derived` (sum of completed ledger rows), `active_members`.
- `v_loan_book` — loan + paid-to-date + arrears + age of oldest unpaid installment.
- `v_defaulter_board` — member, overdue amount, days overdue, bucket (`1-30/31-60/61-90/90+`).
- `mv_group_daily_cashflow` (materialised) — `(group_id, day, inflow, outflow)`, unique index on
  `(group_id, day)`, refreshed concurrently hourly.

---

## 5. Loans

### `loans`
`id`, `public_id`, `group_id`, `user_id`, `principal` numeric, `interest_rate` numeric(6,3),
`interest_method_id` FK, `term_months` smallint, `status_id` FK,
`total_interest`, `total_payable` numeric, `purpose` text (max 200), `requested_at`,
`approved_at`, `disbursed_at`, `disbursement_transaction_id` FK NULL, `created_by`,
`updated_at`. Index `(group_id, status_id)`, `(user_id, group_id)`.

### `loan_guarantors`
`id`, `loan_id` FK, `guarantor_user_id` FK, `amount_guaranteed` numeric, `status_id` FK
`guarantor_statuses`, `responded_at`, `created_at`, `UNIQUE (loan_id, guarantor_user_id)`.
Index `(guarantor_user_id, status_id)`.

### `loan_schedule_items`
`id`, `loan_id` FK, `installment_no` smallint, `due_date` date, `principal_due` numeric,
`interest_due` numeric, `paid_amount` numeric DEFAULT 0, `paid_at` NULL.
`UNIQUE (loan_id, installment_no)`; `INDEX (due_date, loan_id) WHERE paid_at IS NULL`.

### `loan_approvals`
`id`, `loan_id` FK, `approver_id` FK, `decision_id` FK `approval_decisions`, `comment` text,
`created_at`. `UNIQUE (loan_id, approver_id)`.

Schedule generation is deterministic and persisted at approval time. Repayments allocate oldest
installment first (`ORDER BY installment_no`), setting `paid_amount` partially or fully; a
repayment that overflows marks the loan `fully_paid`.

---

## 6. Fines

### `fines`
`id`, `public_id`, `group_id`, `user_id`, `fine_rule_id` FK NULL, `fine_type_id` FK,
`amount` numeric, `reason` text, `status_id` FK `fine_statuses`, `period_label` text,
`assessed_on` date, `waived_by` FK NULL, `waive_reason` text, `payment_transaction_id` FK NULL,
`created_at`.
`UNIQUE (group_id, user_id, fine_rule_id, period_label)` (job idempotency);
index `(group_id, status_id)`, `(user_id, status_id)`.

---

## 7. Welfare

- `welfare_funds`: `group_id` PK/FK, `public_id`, `name`, `monthly_amount` numeric, `is_active`,
  `created_at`, `updated_at`; one fund per chama.
- `welfare_contributions`: `id`, `public_id`, `fund_id` FK, `user_id` FK, `amount`, `period_label`,
  `transaction_id` FK NULL, `created_at`; `UNIQUE (fund_id, user_id, period_label)`, composite
  tenant FK back to the fund.
- `welfare_claims`: `id`, `public_id`, `fund_id`, `user_id`, `amount`, `reason`,
  `status_id` FK `welfare_claim_statuses`, `requested_at`, `decided_by` FK NULL, `decided_at`,
  `payout_transaction_id` FK NULL, `comment` text.

---

## 8. Rotation (merry-go-round) incl. voting

- `rotation_cycles`: `id`, `public_id`, `group_id`, `name`, `status_id` FK
  `rotation_cycle_statuses`, `ordering_mode_id` FK `rotation_ordering_modes`,
  `contribution_amount` numeric, `starts_on` date, `member_count` smallint,
  `draw_seed` text NULL (verifiable random draw), `created_by`, `created_at`, `completed_at`.
- `rotation_slots`: `id`, `public_id`, `cycle_id` FK, `member_id` FK users, `position` smallint,
  `payout_date` date, `payout_transaction_id` FK NULL. `UNIQUE (cycle_id, position)`,
  `UNIQUE (cycle_id, member_id)`; composite tenant FK back to the cycle.
- `rotation_proposals`: `id`, `public_id`, `cycle_id` FK, `group_id`, `proposed_by` FK,
  `status_id` FK `rotation_proposal_statuses`, `quorum_percent` smallint DEFAULT 60,
  `opens_at`, `closes_at` NOT NULL, `closed_at` NULL, `result` jsonb NULL
  (`{for, against, abstain, eligible, quorum_met}`). Partial unique index on
  `(cycle_id) WHERE closed_at IS NULL` permits one open proposal per cycle.
- `rotation_proposal_slots`: `proposal_id` FK, `position` smallint, `member_id` FK,
  PK `(proposal_id, position)`, `UNIQUE (proposal_id, member_id)`.
- `rotation_votes`: `id`, `proposal_id` FK, `member_id` FK, `choice_id` FK `vote_choices`,
  `cast_at`. `UNIQUE (proposal_id, member_id)` — one vote, changeable until close (upsert while
  `status = open`).

Vote weight is 1 per active member in v1; `result` records `eligible` so the ledger of a
contested vote is reproducible. Closing is idempotent: a job closes expired proposals in a
transaction with `SELECT … FOR UPDATE` on the proposal row.

---

## 9. Operations

### `notifications`
`id`, `public_id`, `user_id` FK, `group_id` FK NULL, `type_id` FK, `title` text, `body` text,
`data` jsonb, `dedupe_key` text NULL, `read_at` NULL, `pushed_at` NULL, `created_at`.
`UNIQUE (user_id, dedupe_key)` is what makes each domain event create at most one row; a failed
push leaves `pushed_at` NULL and is retried only by a later explicit action, never by duplicating
the notification. Indexes: `(user_id, created_at DESC)` and the partial unread index
`(user_id, created_at DESC) WHERE read_at IS NULL`.

### `audit_logs` — append-only
`id`, `group_id` FK NULL, `actor_user_id` FK NULL, `action_code` text (e.g. `payment.manual.create`),
`entity_type` text, `entity_id` bigint, `before` jsonb, `after` jsonb, `ip` inet,
`request_id` text, `created_at`. Index `(group_id, created_at DESC)`, `(actor_user_id)`,
`(entity_type, entity_id)`. `BEFORE DELETE` trigger raises; `BEFORE UPDATE` trigger raises.

### `report_jobs`
`id`, `public_id`, `group_id` FK, `requested_by` FK, `report_code` text, `params` jsonb,
`status_id` FK `report_job_statuses`, `file_path` text NULL, `error` text NULL, `created_at`,
`started_at`, `finished_at`. Index `(group_id, created_at DESC)`, `(status_id)`.

### `jobs` (queue)
`id` bigint identity PK, `kind` text, `payload` jsonb, `run_after` timestamptz DEFAULT now(),
`attempts` smallint DEFAULT 0, `locked_by` text NULL, `locked_at` timestamptz NULL,
`last_error` text NULL, `created_at`. Index `(kind, run_after) WHERE locked_at IS NULL`.
Claim: `SELECT … FOR UPDATE SKIP LOCKED LIMIT n` then `UPDATE … SET locked_by, locked_at`.

---

## 10. Billing, plans and platform console

Separate from the chama ledger by design — no `group_id`-less money ever enters `transactions`.

### `platform_users`
`id`, `public_id`, `email` (unique, lower), `password_hash` (argon2id), `role_id` FK
`platform_roles`, `totp_secret_enc` bytea NULL, `is_active`, `last_login_at`, `created_at`.

### `plans`
`id`, `code` unique, `name`, `description`, `price_monthly` numeric, `price_yearly` numeric,
`member_limit` int NULL (NULL = unlimited), `trial_days` smallint, `is_active`, `sort_order`,
`version` int. Historical invoices keep `plan_id` + a price snapshot on the line, so a price
change never rewrites history.

### `plan_features`
`plan_id` FK, `feature_id` FK, `limit_value` int NULL (NULL = unlimited), PK `(plan_id, feature_id)`.

### `addons` / `subscription_addons`
`addons`: `id`, `code`, `name`, `unit_price`, `feature_id` FK, `unit_label`. `subscription_addons`:
`subscription_id`, `addon_id`, `quantity`, `is_active`, `updated_at`, PK `(subscription_id, addon_id)`.

### `subscriptions`
`id`, `public_id`, `group_id` FK, `plan_id` FK, `status_id` FK `subscription_statuses`,
`cycle_id` FK `billing_cycles`, `seats` int, `current_period_start`, `current_period_end`,
`trial_ends_at` NULL, `cancel_at_period_end` bool, `past_due_since` NULL, `created_at`,
`updated_at`. Partial unique: `UNIQUE (group_id) WHERE status_id IN (trialing, active, past_due)`.

### `invoices`
`id`, `public_id`, `number` text unique (`INV-2026-000123`, PDF only — never a URL key),
`group_id`, `subscription_id`, `period_start`, `period_end`, `subtotal`, `vat_amount`, `total`,
`currency`, `status_id` FK `invoice_statuses`, `due_at`, `issued_at`, `paid_at`, `notes`,
`created_at`. Index `(group_id, created_at DESC)`, `(status_id, due_at)`.

### `invoice_lines`
`id`, `invoice_id` FK, `kind_id` FK `invoice_line_kinds`, `description`, `quantity` numeric(10,2),
`unit_amount`, `amount`, `feature_id` FK NULL, `addon_id` FK NULL.

### `billing_payments`
`id`, `public_id`, `invoice_id` FK, `channel_id` FK `payment_channels`, `amount`,
`reference_code` NULL, `checkout_request_id` NULL unique, `merchant_request_id` NULL,
`status_id` FK `transaction_statuses`, `result_code`, `result_desc`, `raw_callback` jsonb,
`paid_at`, `recorded_by_platform_user` FK NULL, `created_at`.
Index `(invoice_id)`, `(status_id, created_at) WHERE status_id = 1` (pending).

### `usage_events`
`id`, `group_id` FK, `feature_id` FK, `quantity` int, `dedupe_key` text UNIQUE, `invoice_id` FK
NULL, `occurred_at`. Written by STK, SMS and PDF paths; aggregated into `overage` lines. Never
mutated after billing.

### `billing_settings` (single row, id = 1)
`shortcode_type_id` FK, `shortcode`, `environment_id` FK, `consumer_key_enc`,
`consumer_secret_enc`, `passkey_enc`, `callback_secret_enc`, `vat_rate` numeric(5,2) DEFAULT 16.00,
`invoice_prefix` text DEFAULT 'INV', `grace_days` smallint DEFAULT 7, `updated_at`.

### Revenue read model
`v_platform_revenue`: `(month, mrr, new_tenants, churned_tenants, collected, outstanding)`.

---

## 11. Migration plan (forward-only, paired `up`/`down`)

| # | File | Contents |
|---|---|---|
| 0001 | `lookups_identity` | 17 spec lookups + seeds |
| 0002 | `lookups_extended` | fine_statuses, approval_decisions, rotation modes/proposal statuses, vote_choices, daraja_environments, device_platforms + seeds |
| 0003 | `users_auth` | users, user_pins, user_devices, refresh_tokens, otp_codes, auth_throttle |
| 0004 | `groups_members` | groups, group_members, group_loan_settings, fine_rules |
| 0005 | `payment_settings` | group_payment_settings |
| 0006 | `ledger` | transactions, payment_requests, idempotency_keys |
| 0007 | `append_only` | append-only triggers for transactions and audit_logs |
| 0008 | `loans` | group_loan_settings, loans, loan_guarantors, loan_schedule_items, loan_approvals |
| 0009 | `fines` | fine_rules, fines |
| 0010 | `welfare` | welfare_funds, welfare_contributions, welfare_claims |
| 0011 | `rotation` | cycles, slots, proposals, proposal_slots, votes |
| 0012 | `notifications` | notifications + dedupe/unread indexes |
| 0013+ | planned | reports/jobs, platform console, billing, views/materialized |
| — | `seed_dev` (guarded) | demo chama, only when `APP_ENV=development` via Makefile target, never in `make migrate` |

`down` reverses each step in dependency order (drop views → triggers → tables → lookups).
Migration 0017 is not part of the migration chain; it is `make seed-dev` running a Go command,
so production can never be seeded by accident.

---

## 12. Tenancy rules (schema-level)

- Every tenant-owned table carries `group_id`, including children (`loan_schedule_items`,
  `loan_guarantors`, `invoice_*` excluded — billing is platform-scoped).
- Parents expose `UNIQUE (id, group_id)`; children reference `(parent_id, group_id)` — a child
  row cannot attach to another tenant's parent even under a service bug.
- Child tables with a natural parent chain (`rotation_votes → rotation_proposals → rotation_cycles`)
  carry `group_id` for the same reason and are additionally checked by RLS.
- RLS in production: `ENABLE ROW LEVEL SECURITY` on tenant tables, policy
  `USING (group_id = current_setting('app.group_id')::bigint)`; the app role is not the table owner.
- Integration suite includes a **tenant matrix test**: for every tenant endpoint, call it with a
  foreign `groupUuid` and assert `404` and zero rows written.

---

## 13. Invariants I will test

1. `UPDATE` on a completed transaction raises.
2. Duplicate M-Pesa callback leaves exactly one `completed` row and one ledger row.
3. `Σ loan_schedule_items.principal_due = principal` and `Σ interest_due = total_interest`
   for both interest methods, across rounding edge cases (e.g. 10,000 @ 10% × 7).
4. `v_member_balances.savings_balance = Σ completed contributions − Σ completed reversals`.
5. Fine job run twice for the same day creates one row per `(member, rule, period)`.
6. Two members voting twice → one row each; a vote after `closes_at` is rejected.
7. Cross-tenant composite FK rejects a `loan_schedule_item` whose `group_id` differs from its loan.
8. A billing invoice never creates a `transactions` row; `v_member_balances` is unchanged by
   subscription payment, upgrade, downgrade or tenant expiry.
9. Invoice totals equal `Σ invoice_lines` including VAT; a prorated upgrade never double-charges
   the same period.
