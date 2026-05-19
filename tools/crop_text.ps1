[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

$srcPath = "c:\dbros_app\assets\logo_sample.png"
$destPath = "C:\Users\HYM\.gemini\antigravity\brain\25624d16-7b3a-4a40-9413-675602923bcc\browser\logo_sample_text.png"

$img = New-Object System.Drawing.Bitmap($srcPath)
# Crop Y from 950 to 1200, X from 200 to 1054
$rect = New-Object System.Drawing.Rectangle(200, 950, 854, 250)
$cropped = $img.Clone($rect, $img.PixelFormat)

if (Test-Path $destPath) {
    Remove-Item $destPath -Force | Out-Null
}
$cropped.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
$cropped.Dispose()
$img.Dispose()
Write-Output "Cropped image saved to $destPath"
