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

$defineFile = Join-Path $root "defines.local.json"
$geminiDefines = @()
if (Test-Path $defineFile) {
    $geminiDefines += "--dart-define-from-file=$defineFile"
    Write-Host ">>> GEMINI_API_KEY: defines.local.json (--dart-define-from-file)" -ForegroundColor DarkGray
} elseif ($env:GEMINI_API_KEY -and $env:GEMINI_API_KEY.Trim()) {
    $geminiDefines += "--dart-define=GEMINI_API_KEY=$($env:GEMINI_API_KEY)"
    Write-Host ">>> GEMINI_API_KEY: environment (--dart-define)" -ForegroundColor DarkGray
} else {
    Write-Host ">>> WARN: defines.local.json 없고 GEMINI_API_KEY 도 없음. Gemini 비활성(예시: defines.local.example.json 복사)." -ForegroundColor Yellow
}

Write-Host ">>> flutter build apk --release..."
flutter build apk --release @geminiDefines
exit $LASTEXITCODE
