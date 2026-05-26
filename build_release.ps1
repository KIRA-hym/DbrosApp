# 릴리스 APK (단일): pubspec 빌드번호 +1 (bump_pubspec_version.dart 규칙) 후 flutter build apk
# 파일명: assembleRelease 시 build.gradle.kts 가 DbrosInstall_yyyyMMdd_vX_Y_ZZ_BB.apk 로 복사
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

$pubspecPath = Join-Path $root "pubspec.yaml"
$backupPath = Join-Path $root "pubspec.yaml.bak"

# Backup pubspec.yaml
Copy-Item -Path $pubspecPath -Destination $backupPath -Force

try {
    Write-Host ">>> Bump pubspec version (tool/bump_pubspec_version.dart)..." -ForegroundColor Cyan
    dart run tool/bump_pubspec_version.dart
    if ($LASTEXITCODE -ne 0) { throw "Version bump failed." }

    Write-Host ">>> Validate notification icon..." -ForegroundColor Cyan
    dart run tool/validate_notification_icon.dart
    if ($LASTEXITCODE -ne 0) { throw "Icon validation failed." }

    Write-Host ">>> flutter pub get..." -ForegroundColor Cyan
    cmd.exe /c "flutter pub get"
    if ($LASTEXITCODE -ne 0) { throw "Pub get failed." }

    Write-Host ">>> flutter build apk --release..." -ForegroundColor Cyan
    cmd.exe /c "flutter build apk --release"
    if ($LASTEXITCODE -ne 0) { throw "APK Build failed." }
}
catch {
    Write-Host ">>> Build failed! Restoring original pubspec.yaml..." -ForegroundColor Red
    Copy-Item -Path $backupPath -Destination $pubspecPath -Force
    Remove-Item -Path $backupPath -Force
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# If build successful, remove backup
if (Test-Path $backupPath) {
    Remove-Item -Path $backupPath -Force
}

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
