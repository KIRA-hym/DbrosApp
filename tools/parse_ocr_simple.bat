@echo off
chcp 65001 >nul
cd /d "%~dp0.."
setlocal

set TOOLS=%~dp0
set IN_TXT=%TOOLS%ocr_input.txt
set IN_JSON=%TOOLS%ocr_input.json
set OUT_JSON=%TOOLS%ocr_result.json
set LOG=%TOOLS%ocr_parse_log.txt
set REPORT=%TOOLS%ocr_parse_report.txt

echo.
echo  === OCR 파싱 (서버 없음, 앱과 동일 Dart 파서) ===
echo.

if not exist "%IN_TXT%" (
  echo  ocr_input.txt 가 없습니다: %IN_TXT%
  pause
  exit /b 1
)

echo  입력: %IN_TXT%
echo  파싱 중... 첫 실행은 20~40초 걸릴 수 있습니다.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$t = [IO.File]::ReadAllText('%IN_TXT%', [Text.UTF8Encoding]::new($false)); " ^
  "$o = @{ text = $t; forcedProgram = '자동' } | ConvertTo-Json -Compress; " ^
  "[IO.File]::WriteAllText('%IN_JSON%', $o, [Text.UTF8Encoding]::new($false))"

if errorlevel 1 (
  echo  ocr_input.json 생성 실패
  pause
  exit /b 1
)

set OCR_LAB_INPUT_PATH=%IN_JSON%
set OCR_LAB_OUTPUT_PATH=%OUT_JSON%
set OCR_LAB_LOG=%LOG%

call "%TOOLS%run_ocr_lab_parse.bat"
set EXIT=%ERRORLEVEL%

if exist "%OUT_JSON%" (
  powershell -NoProfile -Command ^
    "$j = Get-Content -LiteralPath '%OUT_JSON%' -Raw -Encoding UTF8 | ConvertFrom-Json; " ^
    "$r = $j.report; if (-not $r) { $r = ($j | ConvertTo-Json -Depth 6) }; " ^
    "[IO.File]::WriteAllText('%REPORT%', $r, [Text.UTF8Encoding]::new($false))"
  echo.
  echo  완료. 결과 파일:
  echo    %OUT_JSON%
  echo    %REPORT%
  echo.
  start "" notepad "%REPORT%"
) else (
  echo.
  echo  결과 파일 없음. flutter exit=%EXIT%
  if exist "%LOG%" (
    echo  로그: %LOG%
    start "" notepad "%LOG%"
  )
)

pause
exit /b %EXIT%
