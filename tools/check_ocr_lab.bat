@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo  === OCR Lab 진단 ===
echo.

echo [1] Flutter
where flutter 2>nul
if errorlevel 1 (
  echo  FAIL: flutter not in PATH
) else (
  flutter --version 2>nul | findstr /i "Flutter"
)
echo.

echo [2] TCP port 28765
netstat -ano | findstr ":28765" | findstr LISTENING
echo.

echo [3] Worker alive file
if exist "%~dp0.ocr_lab_worker_alive" (
  type "%~dp0.ocr_lab_worker_alive"
) else (
  echo  missing - WORKER not running
)
echo.

echo [4] HTTP health
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:28765/health' -UseBasicParsing -TimeoutSec 3; $r.Content } catch { 'FAIL: ' + $_.Exception.Message }"
echo.

echo [5] Quick parse test (parse_ocr_simple.bat 과 동일 경로)
set TOOLS=%~dp0
set OCR_LAB_INPUT_PATH=%TOOLS%ocr_input.json
set OCR_LAB_OUTPUT_PATH=%TOOLS%ocr_diag_out.json
set OCR_LAB_LOG=%TOOLS%ocr_diag_log.txt
powershell -NoProfile -Command "[IO.File]::WriteAllText('%TOOLS%ocr_input.json', (@{text='line1';forcedProgram='콜마너'}|ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))"
call "%TOOLS%run_ocr_lab_parse.bat"
if exist "%TOOLS%ocr_diag_out.json" (echo  PASS: bridge test produced output) else (echo  FAIL: no output)
echo.
pause
