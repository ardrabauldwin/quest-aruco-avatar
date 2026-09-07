param([string]$Device = '2G0YC5ZH0G00HS')
$ErrorActionPreference = 'Stop'
$adbPath = 'C:\Users\bauld\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$backupApk = Join-Path $PSScriptRoot 'previous_installed.apk'
$expectedHash = 'FB0177EABFB0BBC0C60E7C794DC0304881B719B515D2579DED878AAB1F51FC11'
if ((Get-FileHash -LiteralPath $backupApk -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Backup APK checksum does not match. Restore stopped.'
}
& $adbPath -s $Device install -r $backupApk
if ($LASTEXITCODE -ne 0) { throw 'Restore failed. The app was not uninstalled; existing data was retained.' }
Write-Host 'Previous APK restored. Existing app data retained.'
