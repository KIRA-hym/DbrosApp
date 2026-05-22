# Read pubspec.yaml
$pubspecPath = "pubspec.yaml"
$content = Get-Content $pubspecPath -Encoding UTF8

# Extract version line
$versionRegex = "^version:\s*(.+)$"
$versionLineIndex = -1
$currentVersionStr = ""

for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match $versionRegex) {
        $versionLineIndex = $i
        $currentVersionStr = $matches[1]
        break
    }
}

if ($versionLineIndex -eq -1) {
    Write-Host "버전 정보를 pubspec.yaml에서 찾을 수 없습니다." -ForegroundColor Red
    exit 1
}

# Example version string: 1.0.03+6
$versionRegex2 = "^(\d+)\.(\d+)\.(\d+)\+(\d+)$"
if ($currentVersionStr -match $versionRegex2) {
    $major = $matches[1]
    $minor = $matches[2]
    $patchStr = $matches[3]
    $buildStr = $matches[4]
    
    $patchNum = [int]$patchStr + 1
    $buildNum = [int]$buildStr + 1
    
    # Keep padding if patch string starts with 0
    $newPatchStr = $patchNum.ToString()
    if ($patchStr.StartsWith("0") -and $newPatchStr.Length -lt $patchStr.Length) {
        $newPatchStr = $newPatchStr.PadLeft($patchStr.Length, '0')
    }

    $newVersionStr = "${major}.${minor}.${newPatchStr}+${buildNum}"
    
    $content[$versionLineIndex] = "version: $newVersionStr"
    Set-Content -Path $pubspecPath -Value $content -Encoding UTF8
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "자동 버전업 완료: $currentVersionStr -> $newVersionStr" -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Cyan
} else {
    Write-Host "버전 형식이 일치하지 않아(ex: 1.0.0+1) 자동 버전업을 스킵합니다. 현재 버전: $currentVersionStr" -ForegroundColor Yellow
    $newVersionStr = $currentVersionStr
}

Write-Host "`n클린 작업을 시작합니다..." -ForegroundColor Cyan
cmd.exe /c "flutter clean"

Write-Host "`n종속성 패키지를 설치합니다..." -ForegroundColor Cyan
cmd.exe /c "flutter pub get"

Write-Host "`n릴리즈 APK 빌드를 시작합니다. (시간이 다소 소요됩니다)..." -ForegroundColor Cyan
cmd.exe /c "flutter build apk --release"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n빌드에 실패했습니다. (Exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

$date = Get-Date -Format "yyyy-MM-dd"
$newName = "DbrosInstall_${date}_${newVersionStr}.apk"
$outputDir = "build\outputs"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    Move-Item -Path $apkPath -Destination "$outputDir\$newName" -Force
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "✨ 빌드 및 파일명 변경 성공! ✨" -ForegroundColor Green
    Write-Host "저장 위치: $outputDir\$newName" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan
} else {
    Write-Host "`n에러: APK 파일을 찾을 수 없습니다." -ForegroundColor Red
}
