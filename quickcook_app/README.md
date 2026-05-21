# QuickCook (Flutter)

Mobile and web client for QuickCook.

**Android APK:** see the repo root [README](../README.md#download-android-apk) for the GitHub download link and API configuration.

## Run in development

```bash
flutter pub get
flutter run
```

### Physical phone over USB (no IP entry)

From repo root (with backend on port **8001**):

```powershell
.\scripts\adb-reverse.ps1
cd quickcook_app
flutter run
```

Or one step: `.\scripts\run-flutter-usb.ps1`

Debug builds use `http://127.0.0.1:8001/api`; `adb reverse` tunnels that to your PC.

### Physical phone on Wi‑Fi (no USB)

```bash
flutter run --dart-define=API_HOST=192.168.x.x
```

## Build release APK

```bash
flutter build apk --release
# With production API:
# flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```
