$ErrorActionPreference = "Stop"

# 스크립트의 부모 폴더(tool)의 부모 폴더(dbros_app)를 작업 디렉토리로 강제 설정
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PWD.Path }
$projectRoot = Split-Path -Parent $scriptDir
Set-Location -Path $projectRoot

$backupFileName = "dbros_secrets_backup.zip"
$backupPath = ".\$backupFileName"

# 백업할 대상 파일 목록 (경로 포함)
$filesToBackup = @(
    "android\key.properties",
    "android\secret.properties",
    "defines.local.json",
    ".env",
    ".env.local"
)

# 실제로 존재하는 파일만 필터링 (명시적 배열 처리)
$existingFiles = @($filesToBackup | Where-Object { Test-Path $_ })

if ($existingFiles.Length -gt 0) {
    # 기존 백업 파일이 있으면 삭제
    if (Test-Path $backupPath) {
        Remove-Item -Path $backupPath -Force
    }

    Write-Host ">>> Backing up secret files..." -ForegroundColor Cyan
    $tempDir = ".\temp_secrets_backup"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    foreach ($file in $existingFiles) {
        $sourcePath = ".\$file"
        $destPath = "$tempDir\$file"
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $sourcePath -Destination $destPath -Force
    }

    # 임시 폴더의 내용을 압축 (경로 구조 유지)
    Compress-Archive -Path "$tempDir\*" -DestinationPath $backupPath -Force
    
    # 임시 폴더 정리
    Remove-Item -Path $tempDir -Recurse -Force
    
    Write-Host ">>> Done! Backup saved to: $backupFileName" -ForegroundColor Green
    Write-Host ">>> Included files:"
    $existingFiles | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host ">>> No secret files found to backup." -ForegroundColor Yellow
}
