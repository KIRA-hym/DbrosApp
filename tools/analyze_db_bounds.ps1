[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$path = "c:\dbros_app\assets\icon_before_text.png"
$img = New-Object System.Drawing.Bitmap($path)

$srcX = 204; $srcY = 359; $srcW = 898; $srcH = 517
$minX = $srcW; $maxX = 0; $minY = $srcH; $maxY = 0

for ($y = $srcY; $y -lt ($srcY + $srcH); $y++) {
    for ($x = $srcX; $x -lt ($srcX + $srcW); $x++) {
        $c = $img.GetPixel($x, $y)
        $lum = ($c.R * 0.299 + $c.G * 0.587 + $c.B * 0.114)
        if ($lum -gt 80 -and $c.A -gt 200) {
            $lx = $x - $srcX
            $ly = $y - $srcY
            if ($lx -gt [int]($srcW * 0.38)) { continue }
            if ($ly -gt [int]($srcH * 0.58)) { continue }
            if ($lx -lt $minX) { $minX = $lx }
            if ($lx -gt $maxX) { $maxX = $lx }
            if ($ly -lt $minY) { $minY = $ly }
            if ($ly -gt $maxY) { $maxY = $ly }
        }
    }
}

$pad = 12
$cx = $srcX + [Math]::Max(0, $minX - $pad)
$cy = $srcY + [Math]::Max(0, $minY - $pad)
$cw = [Math]::Min($srcW - $minX + $pad, $maxX - $minX + 1 + 2 * $pad)
$ch = [Math]::Min($srcH - $minY + $pad, $maxY - $minY + 1 + 2 * $pad)

Write-Output "Db text bbox rel: X=$minX..$maxX Y=$minY..$maxY"
Write-Output "Crop: X=$cx Y=$cy W=$cw H=$ch"

$img.Dispose()
