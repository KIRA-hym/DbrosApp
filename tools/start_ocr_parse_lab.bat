@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo  OCR parse lab
echo  =============
echo  Starting local server...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_ocr_parse_lab.ps1"
echo.
start "OCR Parse Lab SERVER" powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve_ocr_parse_lab.ps1"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:28765/"
echo.
echo  If parse fails: check SERVER window for errors.
echo.
exit /b 0
