call flutter clean
call flutter pub get
call flutter build apk --release
powershell -Command "$ver = (Select-String -Path pubspec.yaml -Pattern '^version: (.+)').Matches.Groups[1].Value.Trim() ; $date = Get-Date -Format 'yyyy-MM-dd' ; $newName = 'DbrosInstall_' + $date + '_' + $ver + '.apk' ; New-Item -ItemType Directory -Force -Path build\outputs ; Move-Item -Path build\app\outputs\flutter-apk\app-release.apk -Destination ('build\outputs\' + $newName) -Force ; Write-Host ('Built and renamed to ' + $newName)"
