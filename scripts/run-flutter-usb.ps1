# USB physical device: port-forward then flutter run (debug).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
& "$PSScriptRoot\adb-reverse.ps1"
Set-Location "$Root\quickcook_app"
flutter run @args
