# QuickCook (Flutter)

Mobile and web client for QuickCook.

**Android APK:** see the repo root [README](../README.md#download-android-apk) for the GitHub download link and API configuration.

## Run in development

```bash
flutter pub get
flutter run
# Physical device on same Wi‑Fi as Docker backend:
# flutter run --dart-define=API_HOST=192.168.x.x
```

## Build release APK

```bash
flutter build apk --release
# With production API:
# flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```
