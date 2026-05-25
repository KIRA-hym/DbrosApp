# ============================================================
# DbrosApp — Firebase Cloud Functions 배포 스크립트
# 실행 방법: PowerShell에서 이 파일을 우클릭 > "PowerShell로 실행"
#            또는 터미널에서: .\tools\deploy_functions.ps1
# ============================================================

Set-Location "c:\DbrosApp"

Write-Host "=== [1/3] Firebase 로그인 확인 ===" -ForegroundColor Cyan
firebase login --reauth

Write-Host "`n=== [2/3] functions/ 패키지 설치 ===" -ForegroundColor Cyan
Set-Location "c:\DbrosApp\functions"
npm install

Write-Host "`n=== [3/3] Cloud Functions 배포 ===" -ForegroundColor Cyan
Set-Location "c:\DbrosApp"
firebase deploy --only functions

Write-Host "`n=== 배포 완료! ===" -ForegroundColor Green
Write-Host "Firebase 콘솔 > Functions 탭에서 sendAdminPush 함수를 확인하세요." -ForegroundColor Green
pause
