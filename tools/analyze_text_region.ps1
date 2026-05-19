[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

function Get-TextBoundingBox([string]$filePath) {
    $img = New-Object System.Drawing.Bitmap($filePath)
    $minX = $img.Width; $maxX = 0; $minY = $img.Height; $maxY = 0
    $found = $false

    # Search only in the very bottom area Y > 1050
    for ($y = 1050; $y -lt $img.Height; $y++) {
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
        return @{ MinX = $minX; MaxX = $maxX; MinY = $minY; MaxY = $maxY; Width = ($maxX - $minX + 1); Height = ($maxY - $minY + 1) }
    }
    return $null
}

$box = Get-TextBoundingBox "c:\dbros_app\assets\logo_sample.png"

if ($box) {
    Write-Output "logo_sample.png Text Bounding Box (Y > 1050):"
    Write-Output "  X: $($box.MinX) to $($box.MaxX) (Width: $($box.Width))"
    Write-Output "  Y: $($box.MinY) to $($box.MaxY) (Height: $($box.Height))"
} else {
    Write-Output "logo_sample.png text not found in Y > 1050"
}
