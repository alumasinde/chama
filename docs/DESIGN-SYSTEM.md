# UI / UX Design System

Reference feel: **KCB Mobile** and **Co-operative Bank Kenya** apps — calm, trust-first banking
UI. Deep green brand surface, white cards floating on a pale canvas, one obvious primary action
per screen, money set in large tabular figures, receipts that look official.

What we take from them: the balance card, the 4-up quick-action grid, the rounded 48dp list rows
with circular leading icons, the bottom-sheet amount keypad, the green success tick with a
receipt. What we deliberately do **not** take: marketing carousels, cross-sell banners, dense
legalese. Chama members are often first-time app users; every screen must answer "how much do I
owe" and "how do I pay" in one glance.

---

## 1. Brand tokens (one source: `branding.json`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#0B6E4F` | `#3AA57C` | brand, primary CTA, active tab |
| `primaryDeep` | `#084F39` | `#0B3B2C` | gradient end, headers |
| `accent` | `#D9A227` | `#E8B84B` | highlights, "pending" chips, rotation |
| `danger` | `#B3261E` | `#F2B8B5` | overdue, failed, destructive |
| `success` | `#1E7B4F` | `#7ED9A8` | paid, received |
| `warning` | `#8A5A00` | `#F2C879` | due soon, awaiting action |
| `canvas` | `#F4F6F5` | `#0E1512` | page background |
| `surface` | `#FFFFFF` | `#151F1B` | cards, sheets, tables |
| `ink` | `#0F1F1A` | `#E8EFEB` | primary text |
| `inkMuted` | `#5B6B64` | `#9DAFA7` | secondary text |
| `line` | `#E3E8E5` | `#253029` | 1px borders, table rules |

**Change the app name in one line:** `branding.json → appName`. `make brand` regenerates
`internal/platform/brand/brand.gen.go`, `web/src/lib/brand.gen.ts`,
`mobile/lib/core/brand.gen.dart`, plus the Android/iOS launcher labels. Clients also read
`GET /meta` at boot and prefer the server value, so a rename ships without a store release.
Colours, currency and support email come from the same file. CI greps for hard-coded product
names and fails.

**Type.** Interface: Inter (web) / Inter via `google_fonts` bundled locally (mobile); numerals in
a tabular variant (`font-feature-settings: "tnum"`). Scale: display 32/40, title 22/28,
heading 18/24, body 15/22, label 13/18, caption 12/16. Money ≥ 18px is always tabular.
Kiswahili strings run ~15% longer: no fixed-width buttons, min 44px height, text wraps.

**Space & shape.** 4px base grid; page padding 16 (mobile) / 24 (web); card radius 16, sheet
radius 24 top, chips 999, buttons 14. Elevation is a 1px `line` border plus
`0 1px 2px rgba(15,31,26,.06)`; no heavy shadows. Tap targets ≥ 48×48 with 8px separation.

**Motion.** 180ms `ease-out` for state, 240ms for sheets, 400ms success tick. Respect
`reduce-motion`: cross-fade instead of slide. Skeletons shimmer 1.2s. Never animate a money value
counting up — show the real number immediately.

---

## 2. Mobile information architecture (Flutter)

Bottom navigation, 5 tabs, labels always visible (no icon-only):

`Home · Money · Loans · Group · Profile`

```
Home        balance card, quick actions, next due, group total, recent activity
Money       contributions, fines, welfare payments, statements, pay button
Loans       my loan(s), apply, guarantor requests, schedule, repayments
Group       info, members, rotation (queue + voting), announcements, invite
Profile     personal details, PIN, biometrics, password, notifications, language, logout
```

### 2.1 Onboarding (`/onboarding`)

Full-bleed deep-green header, white sheet rising from the bottom with the form. Steps are one
screen each, with a 4-dot progress rail:

1. **Phone** — `+254` locked prefix, 9-digit field, "We'll text you a 6-digit code."
2. **OTP** — 6 boxes, auto-advance, paste-to-fill, "Resend in 0:42", "Change number".
3. **Your name** — `First name`, `Last name` (two fields, never one "full name" field).
4. **Create your 4-digit PIN** — 4 dots, custom numeric keypad (not the OS keyboard), helper
   text "You'll use this PIN to approve payments." Weak PINs rejected with plain copy:
   "Try a PIN that's harder to guess." Then **Confirm PIN** with mismatch shake.
5. **Fingerprint unlock** — fingerprint glyph, "Unlock with your fingerprint next time?"
   [Enable fingerprint] / [Not now]. Uses `local_auth`; failure falls back silently to PIN.
6. **Join or create** — two large cards: "Join a chama" (8-char invite code, auto-uppercase,
   paste support) or "Start a chama" (wizard: name → contribution amount + frequency + day →
   M-Pesa shortcode → invite members). If joining: "Waiting for admin approval" state with the
   group name and admin first name, plus a "Share my details" note.

Optional password lives under Profile → Security → "Add a password (for the web dashboard)",
and login offers a "Use password instead" link. Password is never mandatory on mobile.

**Login:** phone → PIN pad (headline "Welcome back, Wanjiku", masked phone, "Forgot PIN?" →
OTP reset). Fingerprint icon appears if enrolled and unlocks on launch; 5 wrong PINs → locked
sheet with countdown and "Reset PIN with OTP".

### 2.2 Home

```
┌────────────────────────────────────────────┐
│ Hi, Wanjiku            🔔(2)      (avatar) │
│ Umoja Women's Chama  ⌄                     │
│ ┌────────────────────────────────────────┐ │
│ │ My savings            👁                │ │
│ │ KES 34,500.00                          │ │  ← green gradient card
│ │ +KES 2,000 this month   ▲ 12%          │ │
│ └────────────────────────────────────────┘ │
│ ┌────────┬────────┬────────┬────────┐      │
│ │Contri- │  Pay a │ Request│Rotat-  │      │  ← 4-up quick actions
│ │bute    │  fine  │ a loan │ion     │      │
│ └────────┴────────┴────────┴────────┘      │
│ ⏰ Next contribution  KES 2,000 · Fri 15 Nov│  ← due pill (amber if ≤3 days)
│ Group total  KES 486,200   Members 24      │
│ Recent activity                    See all │
│ ● M-Pesa contribution   +2,000   Today     │
│ ● Fine: late payment      −200    Mon       │
└────────────────────────────────────────────┘
```

Rules: balance card is the only gradient surface on the screen. Amounts hide behind the eye
toggle (persisted per device). "Next contribution" is the highest-value information after the
balance. If a loan is in arrears, an amber strip appears above the quick actions: "Loan payment
overdue by 4 days — KES 3,400" with a Pay action.

### 2.3 Contribute (the money path)

1. Tap **Contribute** → amount sheet: preset chips (2,000 · 5,000 · custom), numeric keypad,
   "You're paying into Umoja Women's Chama · M-Pesa Till 5123456".
2. **Reason** selector: Contribution / Fine / Loan repayment / Welfare.
3. **Confirmation bottom sheet — full line-item breakdown, no surprises:**

```
Confirm payment
Contribution (Nov 2026)        KES 2,000.00
Fine balance                         0.00
Loan repayment                       0.00
──────────────────────────────────────────
Total                          KES 2,000.00
Paying to   Umoja Women's Chama
            M-Pesa Till 5123456
From        +254 7•• ••• 234
Platform fee KES 0.00 — the app never holds your money
[ Slide to confirm · or use fingerprint ]
```

4. PIN pad (or fingerprint sheet) → STK sent state: pulsing phone glyph, "Check your phone and
   enter your M-Pesa PIN", 60s countdown, "I've paid" poll, "Cancel".
5. Result screen: green tick, amount, receipt (`QK47Y2LM9P`), channel, date, "Share receipt" /
   "Done". Failure: red icon, plain reason mapped from `result_desc`, "Try again" (new
   idempotency key), "Pay another way" (cash → shows treasurer's number).

Every money/loan action goes through this same confirm → authorise → result shape.

### 2.4 Statements

Segmented toggle `My statement | Group` (group tab role-gated). Sticky month header rows,
grouped by month with month totals. Row: circular type icon, title, `period_label` subtitle,
trailing amount (`+` green / `−` ink) and status chip. Tap → detail sheet with reference,
recorded-by, and "Report a problem" (creates an audited support note). Offline: Drift cache
renders with a 4px amber "Showing saved data · last updated 09:14" bar. Export button on group
tab (treasurer) → submits a `report_jobs` entry and shows "We'll notify you when your CSV is
ready".

### 2.5 Loans

`My loan` card (balance, next installment, progress bar of paid/total) → `Request group loan`
form: amount (with "You can borrow up to KES 45,000" from `max_multiple_of_savings`),
term in months (chips 3/6/12), purpose, then **a live schedule preview** — the amortization
table with per-installment principal/interest, total interest and total payable. Confirmation
sheet restates: principal, interest, total, term, first due date, guarantors needed. Then PIN.
Guarantor requests: list with borrower avatar, amount, "Accept" / "Decline" (each writes an
audited decision).

### 2.6 Rotation + voting (merry-go-round)

Cycle screen shows a vertical numbered queue with dates; my slot is pinned at top
("Your turn: 12 Feb 2027, position 7"). Voting card, when a proposal is open:

```
Payout order vote                     Closes in 2d 4h
Proposed by Treasurer · 12 of 24 voted (need 15)
1. Akinyi  2. Wanjiku  3. Otieno  …
[ Vote yes ]  [ Vote no ]   See full order
```

After voting: "You voted yes · change vote" while open. After close: result strip with counts and
"Order approved" or "Not approved — treasurer will re-propose". Abstain is available from the
overflow menu (it still counts toward quorum but neither side). Copy is plain: never "quorum
threshold", say "at least 15 members need to vote".

### 2.7 Group, notifications, profile

Group: name, contribution terms, shortcode (read-only), members list with role chips, invite
card with the code + "Share invite" (WhatsApp/system share), and admin-only actions inline.
Notifications: filter chips (All / Payments / Loans / Group), unread dot, tap marks read and
deep-links. Profile: first/last name edit, phone (verified tick), PIN change, fingerprint toggle,
password, language (`English` / `Kiswahili`), app version, logout (with confirm sheet).

### 2.8 States, errors, copy

- **Never a blank screen:** every list has a shimmer skeleton (3–5 rows shaped like the content),
  then empty state (icon, one sentence, one action) or error state (plain sentence + "Try again").
- Empty examples: "No contributions yet. Your first payment will appear here."
- Errors are conversational, never codes: "We couldn't reach M-Pesa. Your money is safe — try
  again in a minute." Server codes never shown; `X-Request-Id` is available under "Details" for
  support.
- Offline banner is amber, ~4px, persistent until reconnected; payments are disabled offline
  (button explains why) while statements stay readable.
- Amounts always to 2dp with thousands separators, `KES` prefix. Dates: "Fri 15 Nov" for recent,
  "15 Nov 2026" otherwise; all in Africa/Nairobi.
- Confirmation verbs match the action ("Approve loan", "Record payout"), and destructive actions
  require typed reason or a second sheet.

### 2.9 Plan & billing (admin only)

Under `Group → Plan`, visible to admin/treasurer and hidden from members. Card shows plan name,
price, renewal date, seats used vs cap (`38 of 50`), and the next invoice amount. Actions:
**Change plan** (plan cards with a feature checklist, monthly/annual toggle showing "2 months
free"), **Pay invoice** (same confirm → PIN → receipt shape as any payment), and **View invoices**.
Status states are explicit and calm: `Trialing · 12 days left`, `Paid · renews 1 Dec`,
`Payment due · 3 days late` (amber, with Pay now), `Read-only · contributions still accepted`
(when expired — the copy leads with what still works). Never a red wall or a data-loss threat.
Downgrade shows exactly what stops working and when ("At period end: new loans pause. Existing
loans and all statements stay available.").

### 2.10 Accessibility & i18n

Dynamic type up to 200% without clipping (no fixed-height text rows), AA contrast on all tokens,
`Semantics` labels on icons and money ("My savings, 34,500 shillings"), 48dp targets, focus order
follows reading order, PIN pad operable with screen reader. English + Kiswahili via ARB
(`app_en.arb`, `app_sw.arb`); currency words, not symbols, in sw where natural
("Shilingi 2,000"). All strings in ARB — no literals in widgets.

---

## 3. Web dashboard (Svelte)

Layout: 240px rail (collapsible to 64), sticky top bar with group switcher, search, theme toggle,
avatar. Content max-width 1440, 24px gutters. Role-aware nav: members never see Settings/Audit.

Pages: **Dashboard** (4 KPI tiles: collected this period, outstanding loans, fines unpaid, active
members; collections-vs-outstanding area chart; cash-flow bars; top defaulters list; recent
activity feed), **Members** (table + invite link + approve queue badge), **Contributions**
(period filter, per-member grid with due/paid/overdue), **Transactions** (filter bar, manual entry
drawer, reverse flow), **Loans** (queue tabs: awaiting guarantors / approval / active / arrears;
detail with schedule, guarantors, approvals, actions), **Fines** (rules tab + list), **Welfare**
(fund settings, contributions, claims queue), **Rotation** (cycles, slots table, propose order,
vote tally, record payout),**Reports**, **Payment Settings** (write-only credential fields with "configured" badges + Verify), **Billing** (plan, seats, usage meters, invoices table, pay-invoice drawer with STK status, VAT lines, invoice PDF), **Audit Log** (filterable, before/after diff drawer), **Settings**.

Table conventions: sticky header + sticky first column, 40px rows, zebra off, hover tint, sort
carets, row actions in an overflow menu, server-side pagination footer ("1–25 of 412"), column
visibility menu, and an **Export** button on every table (CSV/PDF via `report_jobs`).
Loading: skeleton rows, never a spinner over an empty table. Destructive/destructive-adjacent
actions (reverse, waive, write-off) use a confirmation dialog with a required reason.
Dark theme is a token swap; charts use the same scale with adjusted contrast.

---

## 4. Component inventory (shared vocabulary, built once per platform)

`BalanceCard` · `QuickAction` · `SectionHeader` · `MoneyText` · `StatusChip` · `ListRow` ·
`EmptyState` · `Skeleton` · `PinPad` · `AmountKeypad` · `ConfirmSheet` · `StepUpSheet` ·
`Receipt` · `DatePill` · `Avatar` (initials, deterministic colour by public_id) · `VoteCard` ·
`ProgressBar` · `FilterBar` · `DataTable` · `Drawer` · `Toast` · `OfflineBar`.

---

## 5. Screen-by-screen acceptance (what "done" means visually)

1. Onboarding completes in ≤ 90s on a 3G connection with no dead ends; PIN setup cannot be
   skipped or set to a blocked value; fingerprint prompt is dismissible.
2. Home renders meaningful content within 300ms of a warm start from Drift cache, skeletons on
   cold start only.
3. Contribute confirmation lists every line item that affects the amount; total equals the sum
   exactly (integer cents); no payment proceeds without PIN/biometric.
4. Every ledger list shows status, amount and date without horizontal scroll at 360dp width.
5. Voting screen makes the requirement and the deadline obvious without explaining jargon.
6. Web tables hold 100 rows without layout shift, keyboard-navigable, export offered.
7. Light and dark pass AA; nothing is communicated by colour alone (icons/text pair with it).
