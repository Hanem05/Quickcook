# Forwards phone localhost:8001 → PC localhost:8001 (USB debugging).
# Run once per USB session before `flutter run` on a physical device.
$ErrorActionPreference = 'Stop'
$port = if ($args.Count -gt 0) { $args[0] } else { '8001' }
Write-Host "adb reverse tcp:$port tcp:$port"
adb reverse "tcp:$port" "tcp:$port"
if ($LASTEXITCODE -ne 0) {
    Write-Error "adb reverse failed. Connect the phone via USB and enable USB debugging."
}
Write-Host "OK — app can use http://127.0.0.1:$port/api on the device."
