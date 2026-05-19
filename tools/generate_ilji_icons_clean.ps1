[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\icon_before_text.png"

$textBytes = @(0xec, 0x9d, 0xbc, 0xec, 0xa7, 0x80, 0xea, 0xb4, 0x80, 0xeb, 0xa6, 0xac)
$text = [System.Text.Encoding]::UTF8.GetString($textBytes)

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$fontFamily = $pfc.Families[0]

function Create-IconWithText {
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

# 1. 일지관리 - 큰 글씨 버전 (Legibility focus)
Create-IconWithText -Text $text -FontSize 75 -YCenter 1035 -OutputPath "c:\dbros_app\assets\icon_ilji_large.png"

# 2. 일지관리 - 세련된 여백 버전 (Balance focus)
Create-IconWithText -Text $text -FontSize 55 -YCenter 1040 -OutputPath "c:\dbros_app\assets\icon_ilji_small.png"

$pfc.Dispose()
