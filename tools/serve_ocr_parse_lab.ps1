# OCR parse lab - TCP HTTP server (no HttpListener / no http.sys URL reservation)
# Run: .\tools\serve_ocr_parse_lab.ps1
# Open: http://127.0.0.1:28765/

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$HtmlPath = Join-Path $PSScriptRoot "ocr_parse_lab.html"
# 8765 is often stuck in http.sys (PID 4) after HttpListener — use 28765
$LabPort = 28765
$Utf8 = [System.Text.UTF8Encoding]::new($false)

function Invoke-OcrLabParse {
    param([string]$BodyJson)
    try {
        $id = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $inPath = Join-Path $PSScriptRoot ".ocr_lab_in_$id.json"
        $outPath = Join-Path $PSScriptRoot ".ocr_lab_out_$id.json"
        $logFile = Join-Path $PSScriptRoot ".ocr_lab_log_$id.txt"
        $Bat = Join-Path $PSScriptRoot "run_ocr_lab_parse.bat"

        [System.IO.File]::WriteAllText($inPath, $BodyJson, $Utf8)

        $env:OCR_LAB_INPUT_PATH = $inPath
        $env:OCR_LAB_OUTPUT_PATH = $outPath
        $env:OCR_LAB_LOG = $logFile

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] parsing OCR data (running flutter test)..." -ForegroundColor DarkCyan

        $proc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/c", "`"$Bat`"") `
            -WorkingDirectory $RepoRoot `
            -WindowStyle Hidden `
            -PassThru -Wait

        $exitCode = $proc.ExitCode

        if ($exitCode -ne 0) {
            $tail = ""
            if (Test-Path $logFile) {
                $tail = [System.IO.File]::ReadAllText($logFile, $Utf8).Trim()
                if ($tail.Length -gt 2000) { $tail = $tail.Substring($tail.Length - 2000) }
            }
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
        Remove-Item Env:OCR_LAB_INPUT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:OCR_LAB_OUTPUT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:OCR_LAB_LOG -ErrorAction SilentlyContinue
        Remove-Item $inPath -Force -ErrorAction SilentlyContinue
        Remove-Item $outPath -Force -ErrorAction SilentlyContinue
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
}

function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)

    function Read-HttpLine {
        $bytes = New-Object System.Collections.Generic.List[byte]
        $b = New-Object byte[] 1
        while ($Stream.Read($b, 0, 1) -gt 0) {
            if ($b[0] -eq 10) { break }
            if ($b[0] -ne 13) { $bytes.Add($b[0]) }
        }
        return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
    }

    $requestLine = Read-HttpLine
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
        $line = Read-HttpLine
        if ([string]::IsNullOrEmpty($line)) { break }
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
            while ($read -lt $len) {
                $n = $Stream.Read($raw, $read, $len - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            if ($read -gt 0) {
                $body = [System.Text.Encoding]::UTF8.GetString($raw, 0, $read)
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
            $json = "{`"ok`":true,`"service`":`"ocr_parse_lab`",`"version`":5,`"transport`":`"tcp`"}"
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
Write-Host "  Health: version 5 (Synchronous, no separate worker)" -ForegroundColor DarkGray
Write-Host "  Stop: Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

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
