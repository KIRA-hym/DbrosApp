[Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$img = [System.Drawing.Image]::FromFile("c:\dbros_app\assets\logo_sample.png")
Write-Output "logo_sample.png Size: $($img.Width)x$($img.Height)"
$img.Dispose()
