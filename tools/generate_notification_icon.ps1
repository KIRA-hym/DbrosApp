# 알림바 small icon: 흰색 D 실루엣 + 투명 배경 PNG 생성
# 원본: assets/notification_d_source.png (흰 글자·검정 배경 정사각 PNG)
# 출력: drawable-*/app_notification_icon.png (벡터 XML 은 제거됨)
$ErrorActionPreference = "Stop"
[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root "assets\notification_d_source.png"
$destXml = Join-Path $root "android\app\src\main\res\drawable\app_notification_icon.xml"

if (-not (Test-Path $source)) {
    Write-Error "Source not found: $source"
    exit 1
}

function New-NotificationPng {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [int]$Size
    )

    $parent = Split-Path $DestPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $src = [System.Drawing.Bitmap]::FromFile($SourcePath)
    try {
        $dest = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($dest)
        try {
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            # 정사각에 맞춰 중앙 배치 (여백 ~8%)
            $pad = [int]($Size * 0.08)
            $inner = $Size - 2 * $pad
            $g.DrawImage($src, $pad, $pad, $inner, $inner)

            # 흰색 실루엣만 남기기 (알림 아이콘 규칙)
            for ($y = 0; $y -lt $Size; $y++) {
                for ($x = 0; $x -lt $Size; $x++) {
                    $c = $dest.GetPixel($x, $y)
                    $lum = ($c.R * 0.299 + $c.G * 0.587 + $c.B * 0.114)
                    if ($lum -gt 40 -and $c.A -gt 16) {
                        $alpha = [Math]::Min(255, [int]($lum))
                        $dest.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
                    } else {
                        $dest.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
                    }
                }
            }
        } finally {
            $g.Dispose()
        }

        if (Test-Path $DestPath) { Remove-Item $DestPath -Force }
        $dest.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Generated: $DestPath ($Size x $Size)"
    } finally {
        $dest.Dispose()
        $src.Dispose()
    }
}

# 벡터와 이름 충돌 방지: XML 제거 후 PNG만 사용
if (Test-Path $destXml) {
    Remove-Item $destXml -Force
    Write-Host "Removed vector: $destXml"
}

$sizes = @{
    "android/app/src/main/res/drawable-mdpi/app_notification_icon.png"    = 24
    "android/app/src/main/res/drawable-hdpi/app_notification_icon.png"    = 36
    "android/app/src/main/res/drawable-xhdpi/app_notification_icon.png"   = 48
    "android/app/src/main/res/drawable-xxhdpi/app_notification_icon.png"  = 72
    "android/app/src/main/res/drawable-xxxhdpi/app_notification_icon.png" = 96
}

foreach ($rel in $sizes.Keys) {
    $out = Join-Path $root ($rel -replace '/', '\')
    New-NotificationPng -SourcePath $source -DestPath $out -Size $sizes[$rel]
}

Write-Host ">>> Validate..."
Push-Location $root
dart run tool/validate_notification_icon.dart
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { exit $code }
Write-Host "Done."
