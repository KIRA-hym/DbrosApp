# 릴리스 APK: pubspec 빌드번호 증가 후 flutter build apk
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host ">>> Bump pubspec version..."
dart run tool/bump_pubspec_version.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter pub get..."
dart pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build apk --release..."
flutter build apk --release
exit $LASTEXITCODE
