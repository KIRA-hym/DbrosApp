Add-Type -AssemblyName System.Drawing

$sourceIcon = "C:\DbrosLanding\public\icon.png"
$targetIcon = "C:\dbros_app\icon_512.png"

$img = [System.Drawing.Image]::FromFile($sourceIcon)
$bmp = New-Object System.Drawing.Bitmap(512, 512)
$graph = [System.Drawing.Graphics]::FromImage($bmp)
$graph.DrawImage($img, 0, 0, 512, 512)
$bmp.Save($targetIcon, [System.Drawing.Imaging.ImageFormat]::Png)

$img.Dispose()
$bmp.Dispose()
$graph.Dispose()

$sourceFeature = "C:\Users\HYM\.gemini\antigravity\brain\f4362b2c-f55a-423b-82ca-95ce18942bc0\dbros_feature_graphic_1785476827547.jpg"
$targetFeature = "C:\dbros_app\feature_1024x500.png"

$imgF = [System.Drawing.Image]::FromFile($sourceFeature)
$bmpF = New-Object System.Drawing.Bitmap(1024, 500)
$graphF = [System.Drawing.Graphics]::FromImage($bmpF)
$graphF.DrawImage($imgF, 0, 0, 1024, 500)
$bmpF.Save($targetFeature, [System.Drawing.Imaging.ImageFormat]::Png)

$imgF.Dispose()
$bmpF.Dispose()
$graphF.Dispose()

Write-Output "Done"
