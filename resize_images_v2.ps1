Add-Type -AssemblyName System.Drawing

$sourceFeature2 = "C:\Users\HYM\.gemini\antigravity\brain\f4362b2c-f55a-423b-82ca-95ce18942bc0\dbros_feature_graphic_v2_1785477546299.jpg"
$targetFeature2 = "C:\dbros_app\feature_1024x500_v2.png"

$imgF2 = [System.Drawing.Image]::FromFile($sourceFeature2)
$bmpF2 = New-Object System.Drawing.Bitmap(1024, 500)
$graphF2 = [System.Drawing.Graphics]::FromImage($bmpF2)
$graphF2.DrawImage($imgF2, 0, 0, 1024, 500)
$bmpF2.Save($targetFeature2, [System.Drawing.Imaging.ImageFormat]::Png)

$imgF2.Dispose()
$bmpF2.Dispose()
$graphF2.Dispose()

$sourceFeature3 = "C:\Users\HYM\.gemini\antigravity\brain\f4362b2c-f55a-423b-82ca-95ce18942bc0\dbros_feature_graphic_v3_1785477556269.jpg"
$targetFeature3 = "C:\dbros_app\feature_1024x500_v3.png"

$imgF3 = [System.Drawing.Image]::FromFile($sourceFeature3)
$bmpF3 = New-Object System.Drawing.Bitmap(1024, 500)
$graphF3 = [System.Drawing.Graphics]::FromImage($bmpF3)
$graphF3.DrawImage($imgF3, 0, 0, 1024, 500)
$bmpF3.Save($targetFeature3, [System.Drawing.Imaging.ImageFormat]::Png)

$imgF3.Dispose()
$bmpF3.Dispose()
$graphF3.Dispose()

Write-Output "Done"
