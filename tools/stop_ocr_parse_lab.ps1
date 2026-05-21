# OCR parse lab TCP port cleanup (default 28765; legacy 8765 optional)
param([int]$Port = 28765)

$killed = @()

function Stop-ListenPid {
    param([int]$ProcessId)
    if ($ProcessId -le 4) { return }
    if ($killed -contains $ProcessId) { return }
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        Write-Host "  Stop: PID $ProcessId ($($p.ProcessName))" -ForegroundColor Yellow
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        $script:killed += $ProcessId
    }
    catch {
        Write-Host "  Skip PID $ProcessId : $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  OCR parse lab - free port $Port" -ForegroundColor Cyan

try {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        Stop-ListenPid -ProcessId $c.OwningProcess
    }
}
catch {
    # Get-NetTCPConnection unavailable
}

$pattern = ":$Port\s"
netstat -ano | Select-String $pattern | Select-String "LISTENING" | ForEach-Object {
    $parts = ($_.Line -split "\s+") | Where-Object { $_ -ne "" }
    if ($parts.Count -ge 1) {
        $pidStr = $parts[-1]
        if ($pidStr -match '^\d+$') {
            Stop-ListenPid -ProcessId ([int]$pidStr)
        }
    }
}

if ($killed.Count -eq 0) {
    Write-Host "  No LISTENING process on port $Port." -ForegroundColor DarkGray
}
else {
    Write-Host "  Done. Stopped: $($killed -join ', ')" -ForegroundColor Green
}

$toolsDir = $PSScriptRoot
$pidFile = Join-Path $toolsDir ".ocr_lab_worker.pid"
if (Test-Path $pidFile) {
    $wpid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($wpid -gt 4) {
        try {
            Stop-Process -Id $wpid -Force -ErrorAction Stop
            Write-Host "  Stopped worker PID $wpid" -ForegroundColor Yellow
        }
        catch {}
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $toolsDir ".ocr_lab_job.json") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $toolsDir ".ocr_lab_worker_alive") -Force -ErrorAction SilentlyContinue

Write-Host ""
Start-Sleep -Milliseconds 400
