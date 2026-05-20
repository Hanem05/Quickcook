# QuickCook

Recipe app with a **Laravel** API (`quick_cook_backend`) and **Flutter** mobile/web client (`quickcook_app`).

## Download Android APK

After a successful CD run or a manual **Build Android APK** workflow, install the app from GitHub Releases:

**[Latest APK download](https://github.com/Hanem05/Quickcook/releases/latest/download/quickcook.apk)**

Releases page (all builds): [github.com/Hanem05/Quickcook/releases](https://github.com/Hanem05/Quickcook/releases)

### How releases are built

| Trigger | What runs |
|--------|-----------|
| Push to `main` | [CI/CD](.github/workflows/ci-cd.yml) — tests, then web + APK release |
| Manual | **Actions → CI/CD → Run workflow** (optional `api_base_url`; set `skip_release` to test-only) |

### Point the app at your API

Set a repository **variable** (not secret) so CI bakes the correct backend URL into the APK:

1. GitHub → **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Add `API_BASE_URL`, e.g. `https://your-server.com/api` or `http://192.168.1.10:8001/api` for local Docker on Wi‑Fi

Or run **Build Android APK** manually and pass `api_base_url` in the workflow input.

### Install on a phone

1. Download `quickcook.apk` from the link above.
2. Enable “Install unknown apps” for your browser/files app if Android asks.
3. Open the APK and install.

The backend must be reachable from the phone (same Wi‑Fi for local Docker, or a public HTTPS host for production).

## Build APK locally

```bash
cd quickcook_app
flutter pub get
flutter build apk --release
# Optional production API:
# flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```

Output: `quickcook_app/build/app/outputs/flutter-apk/app-release.apk`

## Project layout

| Path | Description |
|------|-------------|
| `quick_cook_backend/` | Laravel API |
| `quickcook_app/` | Flutter app (Android, iOS, web) |
| `docker-compose.yml` | Local stack (API + MySQL + Redis) |
