Add-Type -AssemblyName System.Drawing

$basePath = "C:\Users\HYM\.gemini\antigravity\brain\f4362b2c-f55a-423b-82ca-95ce18942bc0\.user_uploaded\"
$iconPath = "C:\DbrosLanding\public\icon.png"
$targetPath = "C:\dbros_app\feature_custom.png"

$bmp = New-Object System.Drawing.Bitmap(1024, 500)
$graph = [System.Drawing.Graphics]::FromImage($bmp)
$graph.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graph.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Background
$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 18, 20, 24))
$graph.FillRectangle($bgBrush, 0, 0, 1024, 500)

# Draw Icon
if (Test-Path $iconPath) {
    $icon = [System.Drawing.Image]::FromFile($iconPath)
    $graph.DrawImage($icon, 67, 150, 200, 200)
    $icon.Dispose()
}

# Screenshots
$screenshots = @(
    "media__1785477655801.png",
    "media__1785477655760.png",
    "media__1785477655754.png",
    "media__1785477655751.png"
)

$startX = 334
$y = 63
$w = 150
$h = 373
$gap = 20

$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 60, 60, 60), 2)

foreach ($file in $screenshots) {
    $path = $basePath + $file
    if (Test-Path $path) {
        $img = [System.Drawing.Image]::FromFile($path)
        $graph.DrawImage($img, $startX, $y, $w, $h)
        $graph.DrawRectangle($pen, $startX, $y, $w, $h)
        $img.Dispose()
    }
    $startX += ($w + $gap)
}

$bmp.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)

$bgBrush.Dispose()
$pen.Dispose()
$bmp.Dispose()
$graph.Dispose()

Write-Output "Done"
