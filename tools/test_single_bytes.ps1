[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\icon_before_text.png"
$outputPath = "c:\dbros_app\assets\icon_ilji_large.png"

# "일지관리" in UTF-8 bytes to prevent parser issues
$textBytes = @(0xec, 0x9d, 0xbc, 0xec, 0xa7, 0x80, 0xea, 0xb4, 0x80, 0xeb, 0xa6, 0xac)
$text = [System.Text.Encoding]::UTF8.GetString($textBytes)

Write-Output "Text decoded: $text"

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]

$bmp = New-Object System.Drawing.Bitmap($sourcePath)
$g = [System.Drawing.Graphics]::FromImage($bmp)

$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

$font = New-Object System.Drawing.Font($fontFamily, 75, [System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::White

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center

$point = New-Object System.Drawing.PointF(627, 1035)
$g.DrawString($text, $font, $brush, $point, $sf)

if (Test-Path $outputPath) {
    Remove-Item $outputPath -Force | Out-Null
}

$bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "Saved: $outputPath"

$sf.Dispose()
$font.Dispose()
$g.Dispose()
$bmp.Dispose()
$pfc.Dispose()
