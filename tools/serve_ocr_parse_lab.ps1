# OCR parse lab - TCP HTTP server (no HttpListener / no http.sys URL reservation)
# Run: .\tools\serve_ocr_parse_lab.ps1
# Open: http://127.0.0.1:28765/

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$HtmlPath = Join-Path $PSScriptRoot "ocr_parse_lab.html"
$JobFile = Join-Path $PSScriptRoot ".ocr_lab_job.json"
$AliveFile = Join-Path $PSScriptRoot ".ocr_lab_worker_alive"
$WorkerPidFile = Join-Path $PSScriptRoot ".ocr_lab_worker.pid"
# 8765 is often stuck in http.sys (PID 4) after HttpListener — use 28765
$LabPort = 28765
$Utf8 = [System.Text.UTF8Encoding]::new($false)

function Clear-StaleLabArtifacts {
    if (Test-Path $JobFile) {
        $age = ((Get-Date) - (Get-Item $JobFile).LastWriteTime).TotalSeconds
        if ($age -gt 45) {
            Remove-Item $JobFile -Force -ErrorAction SilentlyContinue
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] removed stale job file" -ForegroundColor DarkYellow
        }
    }
    Get-ChildItem $PSScriptRoot -Filter ".ocr_lab_done_*.json" -ErrorAction SilentlyContinue |
        Where-Object { ((Get-Date) - $_.LastWriteTime).TotalHours -gt 1 } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Test-WorkerAlive {
    if (-not (Test-Path $AliveFile)) { return $false }
    try {
        $t = [datetime]::Parse([System.IO.File]::ReadAllText($AliveFile).Trim())
        return ((Get-Date) - $t).TotalSeconds -lt 15
    }
    catch { return $false }
}

function Invoke-OcrLabParse {
    param([string]$BodyJson)
    try {
        Clear-StaleLabArtifacts

        if (-not (Test-WorkerAlive)) {
            $err = @{
                ok    = $false
                error = "WORKER 창이 없습니다. start_ocr_parse_lab.bat 실행 후 'OCR Parse Lab WORKER' 창이 떠 있어야 합니다. 또는 서버 없이 tools\parse_ocr_simple.bat 사용."
            }
            return ($err | ConvertTo-Json -Compress)
        }

        $id = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $inPath = Join-Path $PSScriptRoot ".ocr_lab_in_$id.json"
        $outPath = Join-Path $PSScriptRoot ".ocr_lab_out_$id.json"
        $donePath = Join-Path $PSScriptRoot ".ocr_lab_done_$id.json"
        $logFile = Join-Path $PSScriptRoot ".ocr_lab_flutter_log.txt"

        [System.IO.File]::WriteAllText($inPath, $BodyJson, $Utf8)

        $waitUntil = (Get-Date).AddSeconds(90)
        while ((Test-Path $JobFile) -and (Get-Date) -lt $waitUntil) {
            Start-Sleep -Milliseconds 300
        }
        if (Test-Path $JobFile) {
            Remove-Item $JobFile -Force -ErrorAction SilentlyContinue
        }

        $deadline = (Get-Date).AddSeconds(600)

        $job = @{
            id         = $id
            inputPath  = $inPath
            outputPath = $outPath
            logPath    = $logFile
            donePath   = $donePath
        } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($JobFile, $job, $Utf8)

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] queued job $id (worker parses)..." -ForegroundColor DarkCyan

        while (-not (Test-Path $donePath) -and (Get-Date) -lt $deadline) {
            if (-not (Test-WorkerAlive)) {
                $err = @{ ok = $false; error = "worker stopped during parse" }
                return ($err | ConvertTo-Json -Compress)
            }
            Start-Sleep -Milliseconds 500
        }

        if (-not (Test-Path $donePath)) {
            $err = @{ ok = $false; error = "parse timeout (10 min) — check Worker window" }
            return ($err | ConvertTo-Json -Compress)
        }

        $done = [System.IO.File]::ReadAllText($donePath, $Utf8) | ConvertFrom-Json
        $exitCode = [int]$done.exitCode

        if ($exitCode -ne 0) {
            $tail = ""
            if (Test-Path $logFile) {
                $tail = [System.IO.File]::ReadAllText($logFile, $Utf8).Trim()
                if ($tail.Length -gt 2000) { $tail = $tail.Substring($tail.Length - 2000) }
            }
            if ($done.error) { $tail = "$($done.error)`n$tail" }
            $err = @{
                ok    = $false
                error = "flutter test failed (exit $exitCode)"
                log   = $tail
            }
            return ($err | ConvertTo-Json -Compress)
        }
        if (-not (Test-Path $outPath)) {
            $err = @{ ok = $false; error = "no output from bridge test" }
            return ($err | ConvertTo-Json -Compress)
        }
        return [System.IO.File]::ReadAllText($outPath, $Utf8)
    }
    catch {
        $err = @{ ok = $false; error = $_.Exception.Message }
        return ($err | ConvertTo-Json -Compress)
    }
    finally {
        Get-ChildItem $PSScriptRoot -Filter ".ocr_lab_in_*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem $PSScriptRoot -Filter ".ocr_lab_out_*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem $PSScriptRoot -Filter ".ocr_lab_done_*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)

    $reader = New-Object System.IO.StreamReader($Stream, $Utf8, $false, 65536, $true)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return @{ Method = ""; Path = "/"; Body = "" }
    }

    $parts = $requestLine.Split(" ", 3)
    $method = if ($parts.Length -gt 0) { $parts[0].Trim().ToUpper() } else { "GET" }
    $path = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "/" }
    if ($path.Contains("?")) { $path = $path.Split("?")[0] }
    $path = $path.TrimEnd("/")
    if ([string]::IsNullOrEmpty($path)) { $path = "/" }

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") { break }
        $colon = $line.IndexOf(":")
        if ($colon -gt 0) {
            $key = $line.Substring(0, $colon).Trim().ToLower()
            $val = $line.Substring($colon + 1).Trim()
            $headers[$key] = $val
        }
    }

    $body = ""
    if ($headers.ContainsKey("content-length")) {
        $len = [int]$headers["content-length"]
        if ($len -gt 0) {
            $raw = New-Object byte[] $len
            $read = 0
            $base = $reader.BaseStream
            while ($read -lt $len) {
                $n = $base.Read($raw, $read, $len - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            if ($read -gt 0) {
                $body = $Utf8.GetString($raw, 0, $read)
            }
        }
    }

    return @{ Method = $method; Path = $path; Body = $body }
}

function Write-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        [byte[]]$BodyBytes,
        [string]$ContentType,
        [hashtable]$ExtraHeaders = @{}
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $StatusCode $StatusText`r`n")
    [void]$sb.Append("Content-Type: $ContentType`r`n")
    [void]$sb.Append("Content-Length: $($BodyBytes.Length)`r`n")
    [void]$sb.Append("Connection: close`r`n")
    [void]$sb.Append("Access-Control-Allow-Origin: *`r`n")
    foreach ($k in $ExtraHeaders.Keys) {
        [void]$sb.Append("$k`: $($ExtraHeaders[$k])`r`n")
    }
    [void]$sb.Append("`r`n")
    $headerBytes = $Utf8.GetBytes($sb.ToString())
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($BodyBytes.Length -gt 0) {
        $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
    }
    $Stream.Flush()
}

function Handle-Client {
    param([System.Net.Sockets.TcpClient]$Client)
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 600000
    $stream.WriteTimeout = 600000

    try {
        $req = Read-HttpRequest -Stream $stream
    }
    catch {
        $msg = (@{ ok = $false; error = "bad request: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
        Write-HttpResponse -Stream $stream -StatusCode 400 -StatusText "Bad Request" `
            -BodyBytes ($Utf8.GetBytes($msg)) -ContentType "application/json; charset=utf-8"
        return
    }

    $method = $req.Method
    $path = $req.Path

    try {
        if ($method -eq "OPTIONS") {
            Write-HttpResponse -Stream $stream -StatusCode 204 -StatusText "No Content" `
                -BodyBytes @() -ContentType "text/plain" `
                -ExtraHeaders @{
                "Access-Control-Allow-Methods" = "GET, POST, OPTIONS"
                "Access-Control-Allow-Headers" = "Content-Type"
            }
            return
        }

        if ($method -eq "GET" -and $path -eq "/health") {
            $workerOk = Test-WorkerAlive
            $json = "{`"ok`":true,`"service`":`"ocr_parse_lab`",`"version`":4,`"transport`":`"tcp`",`"worker`":$($workerOk.ToString().ToLower())}"
            Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText "OK" `
                -BodyBytes ($Utf8.GetBytes($json)) -ContentType "application/json; charset=utf-8"
            return
        }

        if ($method -eq "POST" -and $path -eq "/parse") {
            $result = Invoke-OcrLabParse -BodyJson $req.Body
            Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText "OK" `
                -BodyBytes ($Utf8.GetBytes($result)) -ContentType "application/json; charset=utf-8"
            return
        }

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/ocr_parse_lab.html")) {
            if (-not (Test-Path $HtmlPath)) {
                $msg = $Utf8.GetBytes("ocr_parse_lab.html not found")
                Write-HttpResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" `
                    -BodyBytes $msg -ContentType "text/plain; charset=utf-8"
                return
            }
            $html = [System.IO.File]::ReadAllBytes($HtmlPath)
            Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText "OK" `
                -BodyBytes $html -ContentType "text/html; charset=utf-8"
            return
        }

        $nf = $Utf8.GetBytes("Not Found")
        Write-HttpResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" `
            -BodyBytes $nf -ContentType "text/plain; charset=utf-8"
    }
    catch {
        $msg = (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
        Write-HttpResponse -Stream $stream -StatusCode 500 -StatusText "Error" `
            -BodyBytes ($Utf8.GetBytes($msg)) -ContentType "application/json; charset=utf-8"
    }
}

# --- Start TCP listener (avoids http.sys URL reservation conflicts) ---
$ip = [System.Net.IPAddress]::Parse("127.0.0.1")
$tcp = [System.Net.Sockets.TcpListener]::new($ip, $LabPort)

try {
    $tcp.Start()
}
catch {
    Write-Host ""
    Write-Host "  Cannot bind TCP port $LabPort :" $_.Exception.Message -ForegroundColor Red
    Write-Host "  Run: .\tools\stop_ocr_parse_lab.bat" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host ""
Write-Host "  OCR parse lab server running (TCP)" -ForegroundColor Cyan
Write-Host "  http://127.0.0.1:$LabPort/" -ForegroundColor Yellow
Write-Host "  Health: version 4 = Server + Worker (2 windows)" -ForegroundColor DarkGray
Write-Host "  No web? use tools\parse_ocr_simple.bat" -ForegroundColor DarkGray
Write-Host "  Stop: Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

Clear-StaleLabArtifacts

try {
    while ($true) {
        $client = $null
        try {
            $client = $tcp.AcceptTcpClient()
            Handle-Client -Client $client
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Request error: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            if ($null -ne $client) { $client.Close() }
        }
    }
}
catch {
    Write-Host ""
    Write-Host "  Server stopped:" $_.Exception.Message -ForegroundColor Red
}
finally {
    if ($null -ne $tcp) { $tcp.Stop() }
    Write-Host ""
    Read-Host "Press Enter to close this window"
}
