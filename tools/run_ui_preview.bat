@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo =======================================
echo     Flutter UI Web Preview
echo =======================================
echo.
echo =======================================================
echo  When the server starts, open your browser and go to:
echo  http://localhost:38080
echo =======================================================
echo.
call flutter run -d web-server --web-port 38080
pause
