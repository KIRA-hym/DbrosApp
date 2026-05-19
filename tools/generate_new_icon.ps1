[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\icon_before_text.png"
$outputPath = "c:\dbros_app\assets\icon.png"

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]

# Define "운행관리" using unicode character codes to avoid encoding issues
$text = [char]0xC6B4 + [char]0xD589 + [char]0xAD00 + [char]0xB9AC

$srcX = 204
$srcY = 359
$srcW = 898
$srcH = 517

# Selected Option B Parameters
$LogoWidth = 620
$LogoY = 380
$FontSize = 65
$TextY = 840

try {
    $srcImg = [System.Drawing.Image]::FromFile($sourcePath)
    $destBmp = New-Object System.Drawing.Bitmap(1254, 1254)
    $g = [System.Drawing.Graphics]::FromImage($destBmp)
    
    # 1. Clear background to #121418
    $bgColor = [System.Drawing.Color]::FromArgb(255, 18, 20, 24)
    $g.Clear($bgColor)
    
    # 2. Draw scaled logo with transparency color key
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $lowColor = [System.Drawing.Color]::FromArgb(0, 0, 0)
    $highColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $attr.SetColorKey($lowColor, $highColor)
    
    # Scale height proportionally
    $logoHeight = [int]($srcH * ($LogoWidth / $srcW))
    $logoX = [int]((1254 - $LogoWidth) / 2)
    
    $destRect = New-Object System.Drawing.Rectangle($logoX, $LogoY, $LogoWidth, $logoHeight)
    
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    
    $g.DrawImage($srcImg, $destRect, $srcX, $srcY, $srcW, $srcH, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    
    # 3. Draw Text
    $font = New-Object System.Drawing.Font($fontFamily, $FontSize, [System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::White
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.DrawString($text, $font, $brush, (New-Object System.Drawing.PointF(627, $TextY)), $sf)
    
    # 4. Save
    if (Test-Path $outputPath) { Remove-Item $outputPath -Force | Out-Null }
    $destBmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Successfully updated: $outputPath"
    
    # Clean up
    $sf.Dispose()
    $font.Dispose()
    $attr.Dispose()
    $g.Dispose()
    $destBmp.Dispose()
    $srcImg.Dispose()
}
catch {
    Write-Error "Failed to generate new icon: $_"
}

$pfc.Dispose()
