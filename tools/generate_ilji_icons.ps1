[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
$sourcePath = "c:\dbros_app\assets\icon_before_text.png"

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

    try {
        $bmp = New-Object System.Drawing.Bitmap($sourcePath)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        
        $font = New-Object System.Drawing.Font($fontFamily, $FontSize, [System.Drawing.FontStyle]::Bold)
        $brush = [System.Drawing.Brushes]::White
        
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        
        $g.DrawString($Text, $font, $brush, (New-Object System.Drawing.PointF(627, $YCenter)), $sf)
        
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
    catch {
        Write-Output "Error generating $OutputPath : $_"
        Write-Output $_.ScriptStackTrace
    }
}

# 1. 일지관리 - 큰 글씨 버전 (Legibility focus)
Create-IconWithText -Text "일지관리" -FontSize 75 -YCenter 1035 -OutputPath "c:\dbros_app\assets\icon_ilji_large.png"

# 2. 일지관리 - 세련된 여백 버전 (Balance focus)
Create-IconWithText -Text "일지관리" -FontSize 55 -YCenter 1040 -OutputPath "c:\dbros_app\assets\icon_ilji_small.png"

$pfc.Dispose()
