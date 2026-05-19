try {
    [Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
    $fontPath = "c:\dbros_app\assets\fonts\GmarketSansTTFBold.ttf"
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($fontPath)
    $fontFamily = $pfc.Families[0]
    
    Write-Output "Font family name: $($fontFamily.Name)"
    
    $font1 = New-Object System.Drawing.Font($fontFamily, 75, [System.Drawing.FontStyle]::Bold)
    Write-Output "Font 1 created successfully"
    $font1.Dispose()
    
    $pfc.Dispose()
} catch {
    Write-Output "Error: $_"
    Write-Output $_.ScriptStackTrace
}
