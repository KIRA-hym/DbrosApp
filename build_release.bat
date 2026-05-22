@echo off
chcp 65001 > nul
echo =================================================
echo        자동 빌드 및 패키징 스크립트 시작
echo =================================================
powershell.exe -ExecutionPolicy Bypass -File build_release.ps1
echo.
pause
