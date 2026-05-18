# 지도·개인지출(오너 전용) ON/OFF 2종 APK 빌드 스크립트
# - owner: MAP_FEATURES_ENABLED=true (지도 + 개인지출관리)
# - public: MAP_FEATURES_ENABLED=false (지도·개인지출관리 비활성)
# 오너만 + _owner 파일명: .\tools\build_owner_apk.ps1
#
# 사용 예:
#   .\tools\build_dual_apk.ps1                    # 릴리스 배포용: 깨끗한 워킹트리 + push 검사
#   .\tools\build_dual_apk.ps1 -SkipGitCheck      # 단말기 로컬 설치 테스트만 할 때
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
        Write-Host ">>> ERROR: 커밋되지 않은 변경이 있습니다. 모두 커밋한 뒤 다시 빌드하세요." -ForegroundColor Red
        git -C $root status -s
        exit 1
    }

    $null = git -C $root rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return }

    $upstream = git -C $root rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        Write-Host ">>> WARN: upstream 브랜치가 없어 푸시 여부는 검사하지 않습니다. (git push -u origin <브랜치> 권장)" -ForegroundColor Yellow
        return
    }

    $ahead = git -C $root rev-list --count '@{u}..HEAD' 2>$null
    if ($LASTEXITCODE -eq 0 -and $ahead -match '^\d+$' -and [int]$ahead -gt 0) {
        Write-Host ">>> ERROR: 원격에 푸시되지 않은 커밋이 $ahead 개 있습니다. git push 후 다시 빌드하세요." -ForegroundColor Red
        exit 1
    }
}

if (-not $SkipGitCheck) {
    Assert-GitCommittedAndPushedForReleaseBuild
} else {
    Write-Host ">>> SkipGitCheck: skip commit/push gate (local device install only)" -ForegroundColor Yellow
}

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
cmd /c flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> Build owner APK (maps ON)..."
cmd /c flutter build apk --release --dart-define=MAP_FEATURES_ENABLED=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-NamedApk "owner"

Write-Host ">>> Build public APK (maps OFF)..."
cmd /c flutter build apk --release --dart-define=MAP_FEATURES_ENABLED=false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-NamedApk "public"

Write-Host ">>> Done."
