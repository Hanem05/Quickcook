# run-fast.ps1
# ---------------------------------------------------------------------------
# Launches QuickCook in the FASTEST way possible for local development.
#
# Why this matters:
#   `flutter run` defaults to DEBUG mode. On Chrome that means every
#   launch compiles all of your Dart code to unminified JS, which produces
#   the ~19 second "Waiting for connection from debug service on Chrome..."
#   delay you keep seeing.
#
#   Release mode produces a single tree-shaken, minified JS bundle that
#   boots in ~1-2 seconds.
#
# Usage:
#   ./run-fast.ps1            # web release (recommended for fastest launch)
#   ./run-fast.ps1 -Mode win  # native Windows desktop (fastest of all)
#   ./run-fast.ps1 -Mode build # static build, served by a tiny http server
# ---------------------------------------------------------------------------

param(
    [ValidateSet('web', 'win', 'build')]
    [string]$Mode = 'web'
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    switch ($Mode) {
        'web' {
            Write-Host "Launching QuickCook on Chrome in RELEASE mode..." -ForegroundColor Cyan
            flutter run -d chrome --release --web-port 5173
        }
        'win' {
            Write-Host "Launching QuickCook as native Windows desktop..." -ForegroundColor Cyan
            flutter run -d windows --release
        }
        'build' {
            Write-Host "Building optimized web bundle..." -ForegroundColor Cyan
            flutter build web --release --pwa-strategy=offline-first
            Write-Host "`nServing build/web on http://127.0.0.1:5173 ..." -ForegroundColor Green
            Push-Location build/web
            try {
                # Use Python's built-in http server (available with most Python installs).
                python -m http.server 5173
            } finally {
                Pop-Location
            }
        }
    }
} finally {
    Pop-Location
}
