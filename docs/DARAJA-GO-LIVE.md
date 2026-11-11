# Daraja go-live checklist

This project collects M-Pesa payments with **each chama's own Daraja shortcode**. Money moves
from a member's phone straight into that chama's paybill or till and settles to the chama's own
bank or M-Pesa account. The platform never holds chama funds, and no single platform merchant
number is used.

Because the credentials are per chama, go-live happens per chama. Use
**Chama → M-Pesa** in the app to save and verify each chama's details.

## 1. What each chama needs

| Item | Detail |
| --- | --- |
| Shortcode | A Safaricom paybill or Buy Goods (till) number registered to the chama |
| Lipa na M-Pesa Online | Must be enabled on the shortcode, otherwise STK Push is rejected |
| M-Pesa org portal user | A Business Administrator or Business Manager on org.ke.m-pesa.com, needed to approve go-live |
| Daraja app | Created on developer.safaricom.co.ke, with the Lipa na M-Pesa Online product added |
| Passkey | Emailed by Safaricom when the shortcode goes live; unique per shortcode |
| Settlement | Set to the chama's bank or M-Pesa account through the org portal |

A registered chama with a group bank account is the normal case. A chama that still collects on a
personal M-Pesa number cannot use STK Push; it should use **Record a payment** instead.

## 2. Credentials to collect

From the Daraja app (production credentials, not sandbox once live):

- `Consumer Key`
- `Consumer Secret`
- `Passkey` (from the Safaricom go-live email)

Plus the shortcode itself, whether it is a paybill or a till, and the environment
(`sandbox` or `production`). Production keys only work against `https://api.safaricom.co.ke`;
sandbox keys only against `https://sandbox.safaricom.co.ke`.

## 3. Server configuration

```bash
APP_ENV=production
PUBLIC_BASE_URL=https://api.example.co.ke   # public HTTPS origin, no trailing slash
PAYMENTS_PROVIDER=daraja
DARAJA_BASE_URL=https://api.safaricom.co.ke
```

`PAYMENTS_PROVIDER=mock` is development-only and refuses to boot in production.

## 4. Callback URL

Saving a chama's settings returns its callback URL once, in this shape:

```
https://<PUBLIC_BASE_URL>/api/v1/payments/mpesa/callback/<group_public_id>/<callback_secret>
```

Paste it into the Daraja app as the **STK Push result URL**. Requirements:

- Publicly reachable HTTPS. A laptop on `192.168.x.x` will never receive a live callback.
- No `ngrok`, `M-PESA`, `mpesa`, `safaricom`, `exe`, `exec`, `cmd`, `sql` or `query` in the URL.
- Register it from the final production domain.

The callback is authenticated by the per-chama secret in the path and compared in constant time,
so a forged callback cannot settle a ledger row.

## 5. Verify before collecting

Tap **Verify** on the M-Pesa screen. The server mints an OAuth token with the saved key pair for the
chama's chosen environment. A token proves Daraja accepts the keys; there is no endpoint that
validates a passkey without moving money, so a real STK of KES 1 from a test phone is the final
check before telling members to pay.

Verification is stored on the settings row and cleared whenever the settings are saved again.

Then tap **Send a KES 1 test**. It sends a real STK prompt to the manager's own phone using the
chama's shortcode, so an accepted prompt proves the shortcode, passkey and environment agree.
The KES 1 goes to the chama and no ledger row is written, which is why the test is safe to repeat.

## 6. Direct payments (C2B)

If members also pay the paybill or till from their handset without STK Push, register C2B
confirmation and validation URLs on the shortcode:

- Safaricom allows C2B URL registration **once per live shortcode**. Register the final domain.
- C2B and B2C cannot both live on one Daraja app. Pick C2B for collecting, and keep payouts
  (loans, rotation, welfare) recorded manually in the ledger with a channel and reference.
- Without C2B URLs, hand payments do not reach the app: the treasurer records them with
  **Record a payment**.

## 7. Testing

1. Development: `PAYMENTS_PROVIDER=mock`, then use the dev callback endpoint to settle.
2. Sandbox: shortcode `174379` with the published sandbox passkey, test MSISDN only.
3. Production smoke test: KES 1 STK from a real phone, confirm the ledger row completes with the
   M-Pesa receipt code, then confirm the callback was received (server logs, `x-request-id`).

## 8. Troubleshooting

| Symptom | Cause |
| --- | --- |
| `502 provider_error` | Rejected STK: wrong passkey, wrong environment, or Lipa na M-Pesa Online not enabled |
| `422 payment_settings_missing` | The chama has no saved shortcode |
| Verify fails immediately | Key and secret from different apps or environments |
| Payment stays `pending` | Callback never arrived: callback URL not public HTTPS or not saved in the Daraja app |
| `409 reference_already_recorded` | That M-Pesa code is already in this chama's ledger |
