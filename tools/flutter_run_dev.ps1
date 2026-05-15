# 프로젝트 루트에서 flutter run (defines.local.json 있으면 --dart-define-from-file 자동 추가)
#
# 사용 예:
#   .\tools\flutter_run_dev.ps1
#   .\tools\flutter_run_dev.ps1 -d chrome
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $RemainingArgs
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$defineFile = Join-Path $root "defines.local.json"
$extras = [System.Collections.Generic.List[string]]::new()
if (Test-Path $defineFile) {
    $extras.Add("--dart-define-from-file=$defineFile")
    Write-Host ">>> defines.local.json 적용" -ForegroundColor DarkGray
} else {
    Write-Host ">>> WARN: defines.local.json 없음. defines.local.example.json 을 복사해 키를 넣으세요." -ForegroundColor Yellow
}

flutter run @extras @RemainingArgs
exit $LASTEXITCODE
