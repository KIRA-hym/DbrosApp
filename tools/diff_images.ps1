[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$img1 = New-Object System.Drawing.Bitmap("c:\dbros_app\assets\icon.png")
$img2 = New-Object System.Drawing.Bitmap("c:\dbros_app\assets\icon2.png")

$diffCount = 0
$minX = $img1.Width
$maxX = 0
$minY = $img1.Height
$maxY = 0

for ($y = 0; $y -lt $img1.Height; $y++) {
    for ($x = 0; $x -lt $img1.Width; $x++) {
        $c1 = $img1.GetPixel($x, $y)
        $c2 = $img2.GetPixel($x, $y)
        if ($c1.ToArgb() -ne $c2.ToArgb()) {
            $diffCount++
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}

Write-Output "Total differing pixels: $diffCount"
if ($diffCount -gt 0) {
    Write-Output "Difference bounding box: X: $minX to $maxX, Y: $minY to $maxY"
}

$img1.Dispose()
$img2.Dispose()
