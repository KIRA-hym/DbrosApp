# 지도 기능 ON/OFF 2종 APK 빌드 스크립트
# - owner: MAP_FEATURES_ENABLED=true
# - public: MAP_FEATURES_ENABLED=false
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-VersionSuffix {
    $pubspec = Get-Content "$root\pubspec.yaml" -Raw
    $m = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
    if (-not $m.Success) { return "v0_0_00_0" }
    $name = $m.Groups[1].Value.Replace('.', '_')
    $build = $m.Groups[2].Value
    return "v${name}_${build}"
}

function Copy-NamedApk([string]$variantTag) {
    $outDir = "$root\build\app\outputs\flutter-apk"
    $src = Join-Path $outDir "app-release.apk"
    if (-not (Test-Path $src)) {
        throw "app-release.apk 를 찾을 수 없습니다: $src"
    }
    $date = Get-Date -Format "yyyyMMdd"
    $ver = Get-VersionSuffix
    $dst = Join-Path $outDir "DbrosInstall_${date}_${ver}_${variantTag}.apk"
    Copy-Item $src $dst -Force
    Write-Host ">>> Created: $dst"
}

Write-Host ">>> flutter pub get..."
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> Build owner APK (maps ON)..."
flutter build apk --release --dart-define=MAP_FEATURES_ENABLED=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-NamedApk "owner"

Write-Host ">>> Build public APK (maps OFF)..."
flutter build apk --release --dart-define=MAP_FEATURES_ENABLED=false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-NamedApk "public"

Write-Host ">>> Done."
