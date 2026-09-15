Get-ChildItem -Path 'C:\Users\HYM\.shorebird\bin\cache\flutter\e16cf749ccaa38d7050335ff305def49b1c7c84c' -Recurse | Unblock-File
Set-Location 'C:\dbros_app'
shorebird patch android --release-version=1.1.6+110603 --force
