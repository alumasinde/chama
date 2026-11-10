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
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8081
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
and M-Pesa contribution confirmation with PIN step-up. Marketplace is present in the navigation
but intentionally has no listings until its backend ships.
