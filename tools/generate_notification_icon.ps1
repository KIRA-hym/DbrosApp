# 알림바 small icon: 흰색 D 실루엣 + 투명 배경 PNG 생성
# 원본 형태 유지(팽창 없음), 캔버스에 꽉 차게만 스케일
# 미리보기: tools/notification_icon_preview.html (UTF-8 BOM, 한글은 .i18n.json)
$ErrorActionPreference = "Stop"
[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$root = Split-Path -Parent $PSScriptRoot
$toolsDir = $PSScriptRoot
$source = Join-Path $root "assets\notification_d_source.png"
$destXml = Join-Path $root "android\app\src\main\res\drawable\app_notification_icon.xml"
$previewHtml = Join-Path $toolsDir "notification_icon_preview.html"

$FillRatio = 0.96

if (-not (Test-Path $source)) {
    Write-Error "Source not found: $source"
    exit 1
}

function Read-Utf8File([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8BomFile([string]$Path, [string]$Content) {
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
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

    $pad = [int][Math]::Round($Size * (1 - $FillRatio) / 2)
    $inner = $Size - 2 * $pad

    $src = [System.Drawing.Bitmap]::FromFile($SourcePath)
    try {
        $dest = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($dest)
        try {
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($src, $pad, $pad, $inner, $inner)
        } finally {
            $g.Dispose()
        }

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

        if (Test-Path $DestPath) { Remove-Item $DestPath -Force }
        $dest.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Generated: $DestPath (${Size}x${Size}, fill=$FillRatio)"
    } finally {
        $dest.Dispose()
        $src.Dispose()
    }
}

function Write-NotificationIconPreviewHtml {
    param([string]$HtmlPath, [hashtable]$Sizes, [string]$ToolsDir)

    $i18nPath = Join-Path $ToolsDir "notification_icon_preview.i18n.json"
    $templatePath = Join-Path $ToolsDir "notification_icon_preview.template.html"
    $i18n = Get-Content -LiteralPath $i18nPath -Encoding UTF8 -Raw | ConvertFrom-Json

    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $rows = ""
    foreach ($rel in ($Sizes.Keys | Sort-Object { $Sizes[$_] })) {
        $px = $Sizes[$rel]
        $zoom = [int]($px * 3)
        $webPath = "../$($rel -replace '\\', '/')"
        $rows += "`n    <section class=`"density`">`n"
        $rows += "      <h2>${px}px</h2>`n"
        $rows += "      <p class=`"path`">$rel</p>`n"
        $rows += "      <div class=`"row`">`n"
        $rows += "        <div class=`"panel dark`"><img src=`"$webPath`" width=`"$px`" height=`"$px`" /><span>$($i18n.panelDark)</span></div>`n"
        $rows += "        <div class=`"panel light`"><img src=`"$webPath`" width=`"$px`" height=`"$px`" /><span>$($i18n.panelLight)</span></div>`n"
        $rows += "        <div class=`"panel checker`"><img src=`"$webPath`" width=`"$zoom`" height=`"$zoom`" /><span>$($i18n.panelZoom)</span></div>`n"
        $rows += "      </div>`n"
        $rows += "    </section>`n"
    }

    $metaFill = $i18n.metaFill.Replace('{0}', "$FillRatio")
    $metaGenerated = $i18n.metaGenerated.Replace('{0}', $generatedAt)

    $html = Read-Utf8File $templatePath
    $html = $html.Replace('{{TITLE}}', $i18n.title)
    $html = $html.Replace('{{META_GENERATED}}', $metaGenerated)
    $html = $html.Replace('{{META_FILL}}', $metaFill)
    $html = $html.Replace('{{ABOUT_TITLE}}', $i18n.aboutTitle)
    $html = $html.Replace('{{ABOUT_BODY}}', $i18n.aboutBody)
    $html = $html.Replace('{{HINT_LINE1}}', $i18n.hintLine1)
    $html = $html.Replace('{{HINT_LINE2}}', $i18n.hintLine2)
    $html = $html.Replace('{{ROWS}}', $rows)

    Write-Utf8BomFile -Path $HtmlPath -Content $html
    Write-Host "Preview: $HtmlPath"
}

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

Write-NotificationIconPreviewHtml -HtmlPath $previewHtml -Sizes $sizes -ToolsDir $toolsDir

Write-Host ">>> Validate..."
Push-Location $root
dart run tool/validate_notification_icon.dart
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { exit $code }
Write-Host "Done. Open tools\notification_icon_preview.html in a browser."
