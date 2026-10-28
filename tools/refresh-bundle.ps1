$ErrorActionPreference='Stop'
$downloads=Join-Path (Split-Path $PSScriptRoot -Parent) 'downloads'
[void][IO.Directory]::CreateDirectory($downloads)
$source='D:\github\DSC-FIXER'
$tool=Join-Path $downloads 'Windows-Troubleshooter.ps1'
Copy-Item -LiteralPath (Join-Path $source 'install.ps1') -Destination $tool
if((Get-FileHash -LiteralPath $tool).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source 'install.ps1')).Hash){throw 'Snapshot hash mismatch'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-Troubleshooter.cmd') -Destination (Join-Path $downloads 'Start-Troubleshooter.cmd')
Copy-Item -LiteralPath (Join-Path $source 'LICENSE.txt') -Destination (Join-Path $downloads 'LICENSE.txt')
@'
Digital Signing Service 4.1.8 Troubleshooter (for E-Office)
Developed by Girish Tiwari

1. Extract ALL files from the ZIP into one folder.
2. Open Start-Troubleshooter.cmd.
3. Approve Windows UAC to open the administrator PowerShell menu.
4. Choose Option 1 (console) or Option 2 (Windows GUI).
5. Review checks and explicitly approve any repairs or installer downloads.
6. Retain the session-log path if an error occurs.

This bundle is unsigned. It does not bypass execution policy or antivirus.
If organizational policy blocks it, obtain IT approval.
No Java, remote-support application, or DSS installer is bundled here.
The PowerShell tool downloads DSS only after approval, validates its package,
and uses the configured direct source with Google Drive fallback.
See LICENSE.txt. Third-party software retains its publisher's terms.
'@ | Set-Content -LiteralPath (Join-Path $downloads 'START-HERE.txt') -Encoding UTF8
$files=@('Windows-Troubleshooter.ps1','Start-Troubleshooter.cmd','LICENSE.txt','START-HERE.txt')
$inventory=foreach($name in $files){$hash=(Get-FileHash -LiteralPath (Join-Path $downloads $name) -Algorithm SHA256).Hash; "$hash  $name"}
$inventory | Set-Content -LiteralPath (Join-Path $downloads 'SHA256SUMS.txt') -Encoding ASCII
$files+='SHA256SUMS.txt'
$zip=Join-Path $downloads 'DSS-Windows-Launcher.zip'
Compress-Archive -LiteralPath @($files|ForEach-Object{Join-Path $downloads $_}) -DestinationPath $zip -Force
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($tool,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
Write-Output 'Launcher ZIP built. Bundled script matches source; syntax verified. No launcher or repairs executed.'
