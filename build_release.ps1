# 릴리스 APK (단일): pubspec 빌드번호 +1 (bump_pubspec_version.dart 규칙) 후 flutter build apk
# 파일명: assembleRelease 시 build.gradle.kts 가 DbrosInstall_yyyyMMdd_vX_Y_ZZ_BB.apk 로 복사
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

Write-Host ">>> Bump pubspec version (tool/bump_pubspec_version.dart)..." -ForegroundColor Cyan
dart run tool/bump_pubspec_version.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> Validate notification icon..." -ForegroundColor Cyan
dart run tool/validate_notification_icon.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter pub get..." -ForegroundColor Cyan
cmd.exe /c "flutter pub get"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build apk --release..." -ForegroundColor Cyan
cmd.exe /c "flutter build apk --release"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$outDir = Join-Path $root "build\app\outputs\flutter-apk"
$named = Get-ChildItem -Path $outDir -Filter "DbrosInstall_*.apk" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($named) {
    Write-Host ">>> Done: $($named.FullName)" -ForegroundColor Green
} else {
    $fallback = Join-Path $outDir "app-release.apk"
    if (Test-Path $fallback) {
        Write-Host ">>> Done: $fallback" -ForegroundColor Green
    } else {
        Write-Host ">>> Build finished but APK not found under $outDir" -ForegroundColor Yellow
    }
}
