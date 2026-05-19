[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$img = New-Object System.Drawing.Bitmap("c:\dbros_app\assets\logo_sample.png")
Write-Output "Pixel (100, 1100) Color: $($img.GetPixel(100, 1100))"
Write-Output "Pixel (627, 1100) Color: $($img.GetPixel(627, 1100))"
Write-Output "Pixel (100, 850) Color: $($img.GetPixel(100, 850))"
Write-Output "Pixel (100, 1000) Color: $($img.GetPixel(100, 1000))"
$img.Dispose()
