# 오너 APK 한 종만 빌드 (MAP_FEATURES_ENABLED=true) 후 DbrosInstall_*_owner.apk 로 복사
#
# 사용 예:
#   .\tools\build_owner_apk.ps1
#   .\tools\build_owner_apk.ps1 -SkipGitCheck
param(
    [switch] $SkipGitCheck
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Assert-GitCommittedAndPushedForReleaseBuild {
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return }
    } catch {
        return
    }
    $dirty = git -C $root status --porcelain 2>$null
    if ($dirty) {
        Write-Host ">>> ERROR: uncommitted changes. Commit first or use -SkipGitCheck." -ForegroundColor Red
        git -C $root status -s
        exit 1
    }
    $null = git -C $root rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    $upstream = git -C $root rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) { return }
    $ahead = git -C $root rev-list --count '@{u}..HEAD' 2>$null
    if ($LASTEXITCODE -eq 0 -and $ahead -match '^\d+$' -and [int]$ahead -gt 0) {
        Write-Host ">>> ERROR: $ahead unpushed commit(s). git push first or use -SkipGitCheck." -ForegroundColor Red
        exit 1
    }
}

if (-not $SkipGitCheck) {
    Assert-GitCommittedAndPushedForReleaseBuild
} else {
    Write-Host ">>> SkipGitCheck: skip commit/push gate" -ForegroundColor Yellow
}

function Get-VersionSuffix {
    $pubspec = Get-Content "$root\pubspec.yaml" -Raw
    $m = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
    if (-not $m.Success) { return "v0_0_00_0" }
    $name = $m.Groups[1].Value.Replace('.', '_')
    $build = $m.Groups[2].Value
    return "v${name}_${build}"
}

Write-Host ">>> flutter pub get..."
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build apk --release (owner / maps ON, --no-tree-shake-icons)..."
flutter build apk --release --dart-define=MAP_FEATURES_ENABLED=true --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$outDir = "$root\build\app\outputs\flutter-apk"
$src = Join-Path $outDir "app-release.apk"
if (-not (Test-Path $src)) { throw "app-release.apk not found: $src" }
$date = Get-Date -Format "yyyyMMdd"
$ver = Get-VersionSuffix
$dst = Join-Path $outDir "DbrosInstall_${date}_${ver}_owner.apk"
Copy-Item $src $dst -Force
Write-Host ">>> Created: $dst"
Write-Host ">>> Done."
