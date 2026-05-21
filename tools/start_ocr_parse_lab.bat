@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo  OCR parse lab
echo  =============
echo  TWO windows must stay open:
echo    1) OCR Parse Lab WORKER  (flutter test)
echo    2) OCR Parse Lab SERVER  (web http://127.0.0.1:28765/)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_ocr_parse_lab.ps1"
echo.
start "OCR Parse Lab WORKER" powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0ocr_lab_worker.ps1"
timeout /t 2 /nobreak >nul
start "OCR Parse Lab SERVER" powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve_ocr_parse_lab.ps1"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:28765/"
echo.
echo  If parse fails: check WORKER window for errors.
echo.
exit /b 0
