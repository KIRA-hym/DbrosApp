[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\logo_sample.png"

$textBytes = @(0xec, 0x9d, 0xbc, 0xec, 0xa7, 0x80, 0xea, 0xb4, 0x80, 0xeb, 0xa6, 0xac)
$text = [System.Text.Encoding]::UTF8.GetString($textBytes) # "일지관리"

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]

function Create-LogoOption {
    param (
        [string]$Text,
        [float]$FontSize,
        [float]$YCenter,
        [string]$OutputPath
    )

    $bmp = New-Object System.Drawing.Bitmap($sourcePath)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    
    # Clear the old text area (Y: 930 to 1050)
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 13, 13, 13))
    $g.FillRectangle($bgBrush, 0, 930, 1254, 120)
    $bgBrush.Dispose()
    
    $font = New-Object System.Drawing.Font($fontFamily, $FontSize, [System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::White
    
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    
    $point = New-Object System.Drawing.PointF(627, $YCenter)
    $g.DrawString($Text, $font, $brush, $point, $sf)
    
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force | Out-Null
    }
    
    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Generated: $OutputPath"
    
    $sf.Dispose()
    $font.Dispose()
    $g.Dispose()
    $bmp.Dispose()
}

# Generate both versions
Create-LogoOption -Text $text -FontSize 65 -YCenter 975 -OutputPath "c:\dbros_app\assets\logo_sample_large.png"
Create-LogoOption -Text $text -FontSize 48 -YCenter 975 -OutputPath "c:\dbros_app\assets\logo_sample_small.png"

$pfc.Dispose()
