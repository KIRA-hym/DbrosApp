[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$img1 = [System.Drawing.Image]::FromFile("c:\dbros_app\assets\icon.png")
$img2 = [System.Drawing.Image]::FromFile("c:\dbros_app\assets\icon2.png")
Write-Output "icon.png size: $($img1.Width)x$($img1.Height)"
Write-Output "icon2.png size: $($img2.Width)x$($img2.Height)"
$img1.Dispose()
$img2.Dispose()
