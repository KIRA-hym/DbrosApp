$root = "C:\dbros_app"
$pubspecPath = Join-Path $root "pubspec.yaml"

$outDir = Join-Path $root "build\app\outputs\apk\release"
$fallback = Join-Path $outDir "app-release.apk"

if (Test-Path $fallback) {
    Write-Host ">>> Done: $fallback" -ForegroundColor Green
    
    # Auto-deploy to Firebase Hosting (DbrosLanding)
    Write-Host ">>> Starting automatic deploy to Landing page..." -ForegroundColor Cyan
    
    # Parse version from pubspec.yaml
    $pubspecContent = Get-Content $pubspecPath -Raw
    $vMatch = [regex]::Match($pubspecContent, '(?m)^version:\s*(.*?)\+(.*?)$')
    $latestVersion = "1.0.0"
    $versionFormatted = "1_0_0_0"
    if ($vMatch.Success) {
        $vMain = $vMatch.Groups[1].Value
        $vBuild = $vMatch.Groups[2].Value
        $latestVersion = "$vMain.$vBuild"
        
        $vParts = $vMain.Split('.')
        if ($vParts.Length -eq 3) {
            $vBuildPad = $vBuild.PadLeft(2, '0')
            $versionFormatted = "v$($vParts[0])_$($vParts[1])_$($vParts[2])_$vBuildPad"
        } else {
            $versionFormatted = "v$($vMain.Replace('.','_'))_$vBuild"
        }
    }
    
    $todayDate = Get-Date -Format "yyyyMMdd"
    $apkName = "DbrosInstall_${todayDate}_${versionFormatted}.apk"
    $landingDir = "C:\DbrosLanding"
    $landingPublic = Join-Path $landingDir "public"
    $apkDest = Join-Path $landingPublic $apkName
    
    # Remove old APKs
    Get-ChildItem -Path $landingPublic -Filter "DbrosInstall_*.apk" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -Path $landingPublic -Filter "dbros-release.apk" -ErrorAction SilentlyContinue | Remove-Item -Force
    
    # Copy new APK
    Copy-Item -Path $fallback -Destination $apkDest -Force
    Write-Host ">>> Copied APK to Landing: $apkName" -ForegroundColor Green

    # Update version.json
    Write-Host ">>> Updating version.json..." -ForegroundColor Cyan
    $updateDate = Get-Date -Format "yyyy-MM-dd"
    $versionJson = @{
        latest_version = $latestVersion
        update_date = $updateDate
        download_url = "/$apkName"
    }
    $versionJson | ConvertTo-Json -Depth 2 | Set-Content (Join-Path $landingPublic "version.json")
    
    # Deploy
    Write-Host ">>> Deploying Firebase Hosting for DbrosLanding..." -ForegroundColor Cyan
    $oldLoc = Get-Location
    Set-Location $landingDir
    cmd.exe /c "firebase deploy --only hosting --project dbros-apps-7bbmw4"
    Set-Location $oldLoc
    Write-Host ">>> Auto-deploy complete!" -ForegroundColor Green

} else {
    Write-Host ">>> Build finished but APK not found at $fallback" -ForegroundColor Yellow
}
