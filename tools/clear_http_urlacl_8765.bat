@echo off
chcp 65001 >nul
echo.
echo  Remove stale http.sys URL reservation for OLD port 8765 (Admin required)
echo  New lab port is 28765 — use start_ocr_parse_lab.bat
echo.
netsh http show urlacl | findstr 8765
echo.
netsh http delete urlacl url=http://127.0.0.1:8765/
netsh http delete urlacl url=http://localhost:8765/
netsh http delete urlacl url=http://+:8765/
echo.
echo  Done. You can ignore errors if reservation did not exist.
pause
