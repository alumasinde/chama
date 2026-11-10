# UI / UX Reference — supplied Chama mockups

Source: two images attached to the request on **10 November 2026**. They are the visual source
of truth for the product UI and **supersede earlier green KCB-style guidance** in
`DESIGN-SYSTEM.md` wherever the two conflict. The app in the mockups is called **Chama**;
product name remains configurable through `branding.json`.

The mockups are light-theme mobile screens. They show a polished, friendly Kenyan fintech app:
deep purple brand surfaces, vivid purple primary actions, green money/confirm actions, white
rounded cards on a lavender canvas, and real member photography.

---

## 1. Brand and visual tokens

**Logo.** Three abstract people — two purple, one green — standing on a green swoosh. The
wordmark is lowercase-feeling bold sans **Chama**, with the tagline **Together • Save • Grow**
underneath. It appears on the splash, onboarding, login and the marketing banner.

**Positioning copy.**

- “Build a stronger financial future together.”
- “Join, Save and Grow Together.”
- “A modern chama app for Kenyans – save as a group, access loans, buy and sell, and more!”
- “Your Digital Chama Partner Anywhere in Kenya.”
- “Chama… Pamoja Tujijenge!”

**Palette (from the images).**

| Token | Value | Use |
|---|---|---|
| `primary` | `#5B2BB5` | primary buttons, selected chips, active nav, brand icon |
| `primaryDeep` | `#2E0A5E` | splash/header gradients, dark purple cards |
| `primarySoft` | `#F1E9FF` | selected tiles, promo panels, icon wells |
| `accent` / `success` | `#16A34A` | “Get Started”, “Pay via M-Pesa”, completion, positive money |
| `accentSoft` | `#E8F8EC` | confirmed chips, positive-change pills |
| `canvas` | `#F7F4FC` | page background |
| `surface` | `#FFFFFF` | cards, sheets, list rows |
| `ink` | `#1D1233` | primary text and amounts |
| `inkMuted` | `#766A86` | labels, secondary copy |
| `line` | `#EAE2F4` | 1px card and row separators |
| `danger` | `#D92D20` | logout, destructive actions, notification dot |
| `warning` | `#C47A00` | due-soon/pending text |

Gradients run deep indigo-purple top-left to vivid purple bottom-right. The skyline photograph
appears at the bottom of the splash/onboarding screens under a purple-to-transparent overlay.
Cards have 20–24px radii, 1px lavender borders, and very soft shadows; they are not glassy.

**Type.** Bold geometric sans for headings and money; regular sans for body. Amounts are always
tabular and prefixed **Ksh** in the mockups (API remains `KES`). Heading hierarchy is strong:
32–36px screen title, 24–28px balance, 16–18px card title, 13–14px supporting text.

**Control language.** Pill chips (contribution amounts, loan duration). 56px primary buttons.
Green button for “pay/confirm/start”, purple for navigation/selection. Circular member avatars
in overlapping clusters. Green `Active` pill. Red count dot on the notification bell. Bottom
navigation is white, purple for the active tab, with label under every icon.

---

## 2. Information architecture

Canonical bottom navigation (take the second image’s order):

`Home · Chamas · Marketplace · Wallet · Profile`

The first image shows `Home · Chamas · Wallet · Marketplace · Profile`; that ordering is an
alternate, not the target. All five tabs always show labels.

```
Home        greeting, total savings, quick actions, my chamas, recent activity
Chamas      group list, group detail, members, contributions, loans, rotation, activity
Marketplace product/service discovery, listing detail, buy/sell (future phase)
Wallet      available balance, deposit/withdraw, transactions
Profile     edit profile, my chamas, my loans, history, notifications, settings, help, logout
```

Contribute, Request Loan, Group Details and Contribution History are pushed screens from Home
or Chamas. They do not replace tab navigation.

---

## 3. Screen inventory

### 3.1 Splash / loading

Full-screen purple gradient. Centered logo and wordmark, tagline, “Build a stronger financial
future together”, Nairobi skyline photo at the bottom with a purple scrim, small white loading
indicator. No navigation.

### 3.2 Onboarding

Photograph of a Kenyan group filling the top two-thirds, white bottom sheet with **Skip** at the
top-right. Headline **Join a Chama or Create Your Own**; supporting copy “Save together, access
loans, and achieve more.” Four progress dots, full-width green **Get Started**, outlined
**Login** underneath. Alternate copy from the second image: “Build your financial future
together.”

### 3.3 Login

Centered logo, **Welcome Back!**, “Login to your account”. Fields: Phone Number and Password
with a visibility eye. Checkbox **Remember Me**, link **Forgot Password?**. Full-width purple
**Login**, divider **OR**, white outlined **Continue with M-Pesa** with the M-Pesa mark, then
“Don’t have an account? **Sign Up**”.

### 3.4 Home

Header: avatar, “Hello Albert 👋”, “Member since 2023” (or “Good morning!”), notification bell
with red dot. Large purple gradient **My Savings Balance / Total Savings** card with a wallet
illustration and a green positive-change line (“+Ksh 1,000 this month”).

Below: **My Chamas** with **See all →**, two group cards showing avatar cluster, group name,
member count, balance and a green **Active** pill. Four lavender quick-action tiles:
**Contribute, Request Loan, Wallet, More** (second variant: **My Chamas, Loans, Marketplace,
More**). A purple **Save Smart / Achieve More** promo card with a plant illustration. **Recent
Activity** feed with circular arrows: “Contribution received +Ksh 1,000 · 2h ago”. Second image
adds **Quick Actions** pastel tiles: Deposit Money, Request Loan, Buy & Sell.

### 3.5 My Chamas

Back arrow, **My Chamas**, plus action. Pale purple summary row **Your Groups / 2 Groups**. Group
rows with avatar cluster, name, member count, balance and active pill; chevron on the right.
White **Join a Chama** button. **Why Join a Chama?** panel with three green ticks: Save together,
Access affordable loans, Plan for the future.

### 3.6 Group details

Back arrow, **Group Details**, overflow menu. Member photograph cover. Overlapping white card:
group name, green **Active**, “24 Members • Ksh 12,500 Balance”. Four lavender action tiles:
Members, Contributions, Loans, More. Tabs **Overview | Transactions**. Overview shows **Next
Contribution** card (calendar icon, due 30 Nov 2025), **Group Rules** (“Monthly contribution:
Ksh 1,000”) and a purple **View Members** button. Second variant leads with the group’s goal,
**Total Savings Ksh 85,000**, a purple **Contribute Now**, member avatar strip (+19), and recent
contributions by named members.

### 3.7 Contribute

Back arrow, **Contribute**. Purple gradient group card with avatar cluster, group name and
balance. **Contribution Amount** chips: 500, 1,000 (selected purple), 2,000, Other. **Payment
Method** row with M-Pesa logo and chevron. Full-width green **Pay via M-Pesa**; lock line
“Secure & Encrypted”.

### 3.8 Contribution history

Back arrow, **Contribution History**. Group avatar/name header. Segmented chips **All | This
Year | This Month**. Month-grouped rows: green check, date, “Ksh 1,000”, green **Confirmed**.
Clean list with generous 16px vertical rhythm.

### 3.9 Loans

Back arrow, **Loans**. Purple gradient **Available Loan Limit Ksh 50,000** card with wallet.
Purple **Request a Loan**. **My Loans / See all**; loan card with amount, green **Approved** or
**Active** chip, repayment date, percentage repaid and progress bar; repaid loan row with green
**Repaid** chip.

### 3.10 Request loan

Back arrow, **Request Loan**. Amount field with Ksh prefix. Duration chips **1M / 2M / 3M / 6M**,
selected purple. Purpose dropdown. Summary panel: Monthly Repayment, interest, total. Full-width
purple **Submit Request**. Inputs are large and touch-friendly; no dense table until approval.

### 3.11 Marketplace

Header **Marketplace** with menu/search (or back arrow). Hero panel: “Buy & Sell Easily on
Chama — From smartphones to household items.” + purple **Shop Now**, product illustration.
Category circles: Phones, Electronics, Home & Living, Fashion. **Featured Products** two-column
grid with photo, name, price, purple cart button and **View**. First variant uses tabs
**Products | Services**, with tomatoes, shoes, phone and chair listings.

Marketplace is part of the product direction but has no backend in Phase 5; do not invent
escrow, checkout or holding of funds for it.

### 3.12 Wallet

Back arrow, **My Wallet**. Purple gradient **Available Balance Ksh 12,500** (variant: Ksh 8,750)
with white **Send / Deposit** and **Withdraw** buttons. **Recent Transactions / See all**:
circular green down-arrow for contribution/deposit, purple up-arrow for withdrawal, cart icon
for purchase; signed amounts and relative time. Bottom nav visible with Wallet active.

### 3.13 Profile & settings

Back arrow, **Profile & Settings**. Large avatar, name, phone. Lavender **Edit Profile** pill.
Grouped white list rows with leading line icons and chevrons: My Chamas, My Loans, Transaction
History, Notifications (red dot), App Settings, Help & Support, About Chama. Full-width pale red
**Logout** with door icon.

---

## 4. Marketing banner (second image)

Wide desktop/marketing composition: logo left with “Join, Save and Grow Together” and the
supporting sentence; badge “Your Digital Chama Partner Anywhere in Kenya” with a Kenyan flag;
five phone screens; trust bar **Secure & Trusted · Save in Groups · Access Loans · Buy & Sell
Locally · Pay with M-Pesa**; italic script “Chama… Pamoja Tujijenge!” over a Kenyan flag/skyline
treatment.

Use this for landing-page and store-listing art direction. Keep the app UI itself free of
marketing carousels and cross-sell noise.

---

## 5. Interaction rules carried forward

1. One primary money action per screen; green means pay/confirm/start, purple means choose/go.
2. Money is the largest element after the screen title, always tabular, 2dp where precision
   matters, thousands separated.
3. Cards are white, rounded and quiet; gradients are reserved for balance/hero surfaces.
4. Member identity uses real avatar clusters and first names, never abstract silhouettes.
5. Status is always text + colour (`Active`, `Confirmed`, `Approved`), never colour alone.
6. Lists use leading circular icon, title, supporting line, trailing amount/status; 56–64px rows.
7. Bottom sheets for amount entry and confirmation; pushed screens for history/detail.
8. Notification red dot appears only when unread; tapping opens the notification list.
9. Keep the green “secure/encrypted” reassurance near payment actions.
10. English copy is plain; Kiswahili must wrap without truncation (allow 15% extra width).

---

## 6. Deliberate differences from the current design system

- Purple replaces deep green as the brand surface; green becomes the action/positive colour.
- The bottom navigation is the mockups’ five tabs, not `Home · Money · Loans · Group · Profile`.
- Group detail is a hero-photo screen with four action tiles, not a settings-like page.
- Marketplace is a first-class tab in the UX direction, even though its backend is future work.
