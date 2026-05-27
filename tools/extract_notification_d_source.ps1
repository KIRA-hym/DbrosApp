# Db 참조 이미지(금색 네온) → notification_d_source.png (흰색 실루엣 + 검정)
param(
    [string]$SourcePath = "",
    [int]$OutSize = 512,
    [int]$Pad = 36,
    [int]$LumThreshold = 36
)

$ErrorActionPreference = "Stop"
[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $root "assets\db_reference.png"
}
$outputPath = Join-Path $root "assets\notification_d_source.png"

if (-not (Test-Path $SourcePath)) {
    Write-Error "Source not found: $SourcePath"
    exit 1
}

$srcImg = [System.Drawing.Image]::FromFile($SourcePath)
try {
    $dest = New-Object System.Drawing.Bitmap($OutSize, $OutSize)
    try {
        $g = [System.Drawing.Graphics]::FromImage($dest)
        try {
            $g.Clear([System.Drawing.Color]::Black)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $inner = $OutSize - 2 * $Pad
            $scale = [Math]::Min($inner / $srcImg.Width, $inner / $srcImg.Height)
            $drawW = [int]($srcImg.Width * $scale)
            $drawH = [int]($srcImg.Height * $scale)
            $drawX = [int](($OutSize - $drawW) / 2)
            $drawY = [int](($OutSize - $drawH) / 2)
            $g.DrawImage($srcImg, $drawX, $drawY, $drawW, $drawH)
        } finally {
            $g.Dispose()
        }

        for ($y = 0; $y -lt $OutSize; $y++) {
            for ($x = 0; $x -lt $OutSize; $x++) {
                $c = $dest.GetPixel($x, $y)
                $lum = ($c.R * 0.299 + $c.G * 0.587 + $c.B * 0.114)
                if ($lum -gt $LumThreshold) {
                    $alpha = [Math]::Min(255, [int]($lum * 1.08))
                    $dest.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
                } else {
                    $dest.SetPixel($x, $y, [System.Drawing.Color]::Black)
                }
            }
        }

        if (Test-Path $outputPath) { Remove-Item $outputPath -Force }
        $dest.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Source: $SourcePath"
        Write-Host "Saved: $outputPath (${OutSize}x${OutSize})"
    } finally {
        $dest.Dispose()
    }
} finally {
    $srcImg.Dispose()
}
