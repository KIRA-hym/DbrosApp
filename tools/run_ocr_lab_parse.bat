@echo off
setlocal
cd /d "%~dp0.."
if "%OCR_LAB_INPUT_PATH%"=="" exit /b 2
if "%OCR_LAB_OUTPUT_PATH%"=="" exit /b 2
if not exist "%OCR_LAB_INPUT_PATH%" exit /b 3
if defined OCR_LAB_LOG (
  flutter test test\ocr_lab_bridge_test.dart --reporter compact > "%OCR_LAB_LOG%" 2>&1
) else (
  flutter test test\ocr_lab_bridge_test.dart --reporter compact
)
exit /b %ERRORLEVEL%
