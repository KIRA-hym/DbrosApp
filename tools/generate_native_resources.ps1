[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$projectRoot = "c:\dbros_app"
$launcherSource = "$projectRoot\assets\icon.png"
$splashSource = "$projectRoot\assets\splash.png"

if (!(Test-Path $launcherSource)) {
    Write-Error "Launcher icon source not found: $launcherSource"
    exit 1
}
if (!(Test-Path $splashSource)) {
    Write-Error "Splash source not found: $splashSource"
    exit 1
}

function Resize-Image {
    param (
        [string]$SourcePath,
        [string]$DestPath,
        [int]$Width,
        [int]$Height
    )
    
    # 디렉토리 자동 생성
    $parentDir = Split-Path $DestPath -Parent
    if (!(Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    try {
        $src = [System.Drawing.Image]::FromFile($SourcePath)
        $dest = New-Object System.Drawing.Bitmap($Width, $Height)
        $g = [System.Drawing.Graphics]::FromImage($dest)
        
        # 고화질 보간 설정
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        
        $g.DrawImage($src, 0, 0, $Width, $Height)
        
        # 덮어쓰기를 위해 기존 파일이 존재하면 지움
        if (Test-Path $DestPath) {
            Remove-Item -Path $DestPath -Force -ErrorAction SilentlyContinue
        }
        
        $dest.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output "Generated: $DestPath ($Width x $Height)"
    }
    catch {
        Write-Error "Failed to generate $DestPath - Error details: $_"
    }
    finally {
        if ($null -ne $g) { $g.Dispose() }
        if ($null -ne $dest) { $dest.Dispose() }
        if ($null -ne $src) { $src.Dispose() }
    }
}

# 1. 런처 아이콘 (launcher_icon.png) - mipmap-*
$launcherIcons = @{
    "android/app/src/main/res/mipmap-mdpi/launcher_icon.png" = @(48, 48)
    "android/app/src/main/res/mipmap-hdpi/launcher_icon.png" = @(72, 72)
    "android/app/src/main/res/mipmap-xhdpi/launcher_icon.png" = @(96, 96)
    "android/app/src/main/res/mipmap-xxhdpi/launcher_icon.png" = @(144, 144)
    "android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png" = @(192, 192)
}

# 2. 적응형 런처 아이콘 전경 (ic_launcher_foreground.png) - drawable-*
$launcherForegrounds = @{
    "android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png" = @(108, 108)
    "android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png" = @(162, 162)
    "android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png" = @(216, 216)
    "android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png" = @(324, 324)
    "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png" = @(432, 432)
}

# 3. 일반 스플래시 이미지 (splash.png) - drawable-* & drawable-night-*
$splashImages = @{
    "android/app/src/main/res/drawable-mdpi/splash.png" = @(320, 480)
    "android/app/src/main/res/drawable-hdpi/splash.png" = @(480, 800)
    "android/app/src/main/res/drawable-xhdpi/splash.png" = @(720, 1280)
    "android/app/src/main/res/drawable-xxhdpi/splash.png" = @(960, 1600)
    "android/app/src/main/res/drawable-xxxhdpi/splash.png" = @(1280, 1920)
    
    "android/app/src/main/res/drawable-night-mdpi/splash.png" = @(320, 480)
    "android/app/src/main/res/drawable-night-hdpi/splash.png" = @(480, 800)
    "android/app/src/main/res/drawable-night-xhdpi/splash.png" = @(720, 1280)
    "android/app/src/main/res/drawable-night-xxhdpi/splash.png" = @(960, 1600)
    "android/app/src/main/res/drawable-night-xxxhdpi/splash.png" = @(1280, 1920)
}

# 4. 안드로이드 12+ 네이티브 스플래시 이미지 (android12splash.png) - drawable-* & drawable-night-*
$android12Splashes = @{
    "android/app/src/main/res/drawable-mdpi/android12splash.png" = @(72, 72)
    "android/app/src/main/res/drawable-hdpi/android12splash.png" = @(108, 108)
    "android/app/src/main/res/drawable-xhdpi/android12splash.png" = @(144, 144)
    "android/app/src/main/res/drawable-xxhdpi/android12splash.png" = @(216, 216)
    "android/app/src/main/res/drawable-xxxhdpi/android12splash.png" = @(288, 288)
    
    "android/app/src/main/res/drawable-night-mdpi/android12splash.png" = @(72, 72)
    "android/app/src/main/res/drawable-night-hdpi/android12splash.png" = @(108, 108)
    "android/app/src/main/res/drawable-night-xhdpi/android12splash.png" = @(144, 144)
    "android/app/src/main/res/drawable-night-xxhdpi/android12splash.png" = @(216, 216)
    "android/app/src/main/res/drawable-night-xxxhdpi/android12splash.png" = @(288, 288)
}

Write-Output "--- Generating Launcher Icons ---"
foreach ($key in $launcherIcons.Keys) {
    $sizes = $launcherIcons[$key]
    Resize-Image -SourcePath $launcherSource -DestPath "$projectRoot\$key" -Width $sizes[0] -Height $sizes[1]
}

Write-Output "--- Generating Adaptive Icon Foregrounds ---"
foreach ($key in $launcherForegrounds.Keys) {
    $sizes = $launcherForegrounds[$key]
    Resize-Image -SourcePath $launcherSource -DestPath "$projectRoot\$key" -Width $sizes[0] -Height $sizes[1]
}

Write-Output "--- Generating Splash Images ---"
foreach ($key in $splashImages.Keys) {
    $sizes = $splashImages[$key]
    Resize-Image -SourcePath $splashSource -DestPath "$projectRoot\$key" -Width $sizes[0] -Height $sizes[1]
}

Write-Output "--- Generating Android 12+ Splash Images ---"
foreach ($key in $android12Splashes.Keys) {
    $sizes = $android12Splashes[$key]
    Resize-Image -SourcePath $launcherSource -DestPath "$projectRoot\$key" -Width $sizes[0] -Height $sizes[1]
}

Write-Output "All android native launcher and splash icons successfully generated offline!"
