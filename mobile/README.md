# Chama mobile

Flutter client for the Chama Ledger API.

## Run

```bash
cd mobile
flutter pub get
flutter run
```

The default API origin is `http://localhost:8081` on iOS/desktop and
`http://10.0.2.2:8081` on the Android emulator. Override it for a physical phone or a hosted
backend:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.100.11:8080
```

The development OTP is returned by the API and shown under the code field when
`APP_ENV=development`.

## Checks

```bash
flutter analyze
flutter test
```

The app currently covers sign-in/registration, the chama dashboard, chama details, members,
ledger, loans, welfare, wallet balances, notifications, profile, joining and creating a chama,
fines, rotation, loan requests and guarantees, welfare claims, and M-Pesa payments with PIN
step-up and centered receipts. Fingerprint sign-in is available on supported Android, iOS,macOS and Windows devices; the web build falls back to phone-number sign-in. Managers can connect the chama's own M-Pesa
shortcode (paybill or till) in the app and record payments the treasurer received outside it.
