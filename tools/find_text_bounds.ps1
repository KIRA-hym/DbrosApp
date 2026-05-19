[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$img = New-Object System.Drawing.Bitmap("c:\dbros_app\assets\logo_sample.png")
$minX = $img.Width; $maxX = 0; $minY = $img.Height; $maxY = 0
$found = $false

for ($y = 950; $y -lt 1200; $y++) {
    for ($x = 0; $x -lt $img.Width; $x++) {
        $c = $img.GetPixel($x, $y)
        # Look for white text pixels (R > 200, G > 200, B > 200)
        if ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -gt 200) {
            $found = $true
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$img.Dispose()

if ($found) {
    Write-Output "Text Bounding Box: MinX=$minX, MaxX=$maxX, MinY=$minY, MaxY=$maxY, Width=$($maxX - $minX + 1), Height=$($maxY - $minY + 1)"
} else {
    Write-Output "No white pixels found in the Y range [950, 1200]."
}
