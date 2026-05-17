# 홈작업용 apk 듀얼빌드 및 구글 드라이브 복사 스크립트
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host ">>> 1. 듀얼 빌드 스크립트 실행 (SkipGitCheck)" -ForegroundColor Cyan
.\tools\build_dual_apk.ps1 -SkipGitCheck

$gDrivePath = "G:\내 드라이브\Dbros"
if (-not (Test-Path $gDrivePath)) {
    Write-Host ">>> 구글 드라이브 경로가 존재하지 않아 폴더를 생성합니다: $gDrivePath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $gDrivePath | Out-Null
}

$outDir = "$root\build\app\outputs\flutter-apk"

# 오늘 날짜와 버전 정보 파싱 (build_dual_apk와 동일한 방식)
function Get-VersionSuffix {
    $pubspec = Get-Content "$root\pubspec.yaml" -Raw
    $m = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
    if (-not $m.Success) { return "v0_0_00_0" }
    $name = $m.Groups[1].Value.Replace('.', '_')
    $build = $m.Groups[2].Value
    return "v${name}_${build}"
}

$date = Get-Date -Format "yyyyMMdd"
$ver = Get-VersionSuffix

$ownerApkName = "DbrosInstall_${date}_${ver}_owner.apk"
$publicApkName = "DbrosInstall_${date}_${ver}_public.apk"

$ownerApk = Join-Path $outDir $ownerApkName
$publicApk = Join-Path $outDir $publicApkName

Write-Host ">>> 2. 생성된 APK 구글 드라이브로 복사" -ForegroundColor Cyan

if (Test-Path $ownerApk) {
    Copy-Item $ownerApk $gDrivePath -Force
    Write-Host "  -> 복사 완료: $ownerApkName" -ForegroundColor Green
} else {
    Write-Host "  -> 오너 APK를 찾을 수 없습니다: $ownerApk" -ForegroundColor Red
}

if (Test-Path $publicApk) {
    Copy-Item $publicApk $gDrivePath -Force
    Write-Host "  -> 퍼블릭 APK 복사 완료: $publicApkName" -ForegroundColor Green
} else {
    Write-Host "  -> 퍼블릭 APK를 찾을 수 없습니다: $publicApk" -ForegroundColor Red
}

Write-Host ">>> 홈작업용 APK 빌드 및 업로드 완료!" -ForegroundColor Cyan
