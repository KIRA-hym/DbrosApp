# OCR parse worker — flutter test only runs here (separate console from HTTP server)
$ErrorActionPreference = "Continue"
$ToolsDir = $PSScriptRoot
$RepoRoot = Split-Path $ToolsDir -Parent
$JobFile = Join-Path $ToolsDir ".ocr_lab_job.json"
$AliveFile = Join-Path $ToolsDir ".ocr_lab_worker_alive"
$PidFile = Join-Path $ToolsDir ".ocr_lab_worker.pid"
$Utf8 = [System.Text.UTF8Encoding]::new($false)
$Bat = Join-Path $ToolsDir "run_ocr_lab_parse.bat"

Set-Content -Path $PidFile -Value $PID -Encoding ASCII
Write-Host ""
Write-Host "  OCR parse WORKER (flutter runs here)" -ForegroundColor Green
Write-Host "  Keep this window open while using the lab." -ForegroundColor DarkGray
Write-Host ""

while ($true) {
    try {
        Set-Content -Path $AliveFile -Value (Get-Date).ToString("o") -Encoding ASCII
    }
    catch {}

    if (Test-Path $JobFile) {
        $job = $null
        try {
            $raw = [System.IO.File]::ReadAllText($JobFile, $Utf8)
            $job = $raw | ConvertFrom-Json
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] bad job file: $_" -ForegroundColor Red
            Remove-Item $JobFile -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
            continue
        }

        Remove-Item $JobFile -Force -ErrorAction SilentlyContinue

        $inPath = $job.inputPath
        $outPath = $job.outputPath
        $logPath = $job.logPath
        $donePath = $job.donePath
        $jobId = $job.id

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] job $jobId start" -ForegroundColor DarkCyan

        if (Test-Path $outPath) { Remove-Item $outPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $donePath) { Remove-Item $donePath -Force -ErrorAction SilentlyContinue }

        $exitCode = 1
        $errMsg = ""
        try {
            if (-not (Test-Path $Bat)) {
                $errMsg = "run_ocr_lab_parse.bat not found"
            }
            else {
                $env:OCR_LAB_INPUT_PATH = $inPath
                $env:OCR_LAB_OUTPUT_PATH = $outPath
                $env:OCR_LAB_LOG = $logPath

                $proc = Start-Process -FilePath "cmd.exe" `
                    -ArgumentList @("/c", "`"$Bat`"") `
                    -WorkingDirectory $RepoRoot `
                    -WindowStyle Hidden `
                    -PassThru -Wait

                $exitCode = $proc.ExitCode
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            $exitCode = 1
        }
        finally {
            Remove-Item Env:OCR_LAB_INPUT_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:OCR_LAB_OUTPUT_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:OCR_LAB_LOG -ErrorAction SilentlyContinue
        }

        $done = @{
            id       = $jobId
            exitCode = $exitCode
            error    = $errMsg
            finished = (Get-Date).ToString("o")
        }
        [System.IO.File]::WriteAllText($donePath, ($done | ConvertTo-Json -Compress), $Utf8)

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] job $jobId done (exit $exitCode)" -ForegroundColor DarkCyan
    }

    Start-Sleep -Milliseconds 350
}
