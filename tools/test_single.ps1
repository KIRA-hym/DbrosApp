[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\icon_before_text.png"
$outputPath = "c:\dbros_app\assets\icon_ilji_large.png"

Write-Output "Starting test..."

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]
Write-Output "Font loaded: $($fontFamily.Name)"

$bmp = New-Object System.Drawing.Bitmap($sourcePath)
Write-Output "Source bitmap loaded: $($bmp.Width)x$($bmp.Height)"

$g = [System.Drawing.Graphics]::FromImage($bmp)
Write-Output "Graphics object created"

$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

$font = New-Object System.Drawing.Font($fontFamily, 75, [System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::White
Write-Output "Font and Brush created"

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center

$point = New-Object System.Drawing.PointF(627, 1035)
$g.DrawString("일지관리", $font, $brush, $point, $sf)
Write-Output "Text drawn"

if (Test-Path $outputPath) {
    Write-Output "Removing existing file..."
    Remove-Item $outputPath -Force
}

Write-Output "Saving bitmap..."
$bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "Bitmap saved successfully!"

$sf.Dispose()
$font.Dispose()
$g.Dispose()
$bmp.Dispose()
$pfc.Dispose()
