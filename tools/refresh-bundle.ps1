$ErrorActionPreference='Stop'
$downloads=Join-Path (Split-Path $PSScriptRoot -Parent) 'downloads'
[void][IO.Directory]::CreateDirectory($downloads)
$source='D:\github\DSC-FIXER'
$tool=Join-Path $downloads 'Windows-Troubleshooter.ps1'
Copy-Item -LiteralPath (Join-Path $source 'troubleshooter.ps1') -Destination $tool
if((Get-FileHash -LiteralPath $tool).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source 'troubleshooter.ps1')).Hash){throw 'Snapshot hash mismatch'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-Troubleshooter.cmd') -Destination (Join-Path $downloads 'Start-Troubleshooter.cmd')
Copy-Item -LiteralPath (Join-Path $source 'LICENSE.txt') -Destination (Join-Path $downloads 'LICENSE.txt')
@'
Digital Signing Service 4.1.8 Troubleshooter (for E-Office)
Developed by Girish Tiwari

1. Extract ALL files from the ZIP into one folder.
2. Open Start-Troubleshooter.cmd.
3. Approve Windows UAC to open the administrator PowerShell menu.
4. Choose Option 1 (console), 2 (full Windows GUI), 3 (Reset Java & setting for other Websites), 5 (CRIS Signer Switcher & Installer), or 6 (APAR Signer Service 7.0.2 GUI).
5. Review checks and explicitly approve any repairs or installer downloads.
6. Option 3: select browsers and railway sites. Continue / Cancel is asked for each browser.
   Complete Delete data / Reset permissions yourself in the browser for the selected sites only.
   Working Java stays installed; Java updates are optional.
7. Option 5: Check status first. IPAS port 2068; IRWCMS/IRCEP port 2039.
   Choose Install / Repair both + desktop switcher if needed. Approve UAC and review CRIS products to remove.
   Both inspected packages download before uninstall; then IPAS and IRWCMS install to separate folders.
   Setup creates CRISSigner_IPAS, CRISSigner_IRWCMS and a compact desktop-only CRIS Switcher with UAC.
   Existing CRIS configuration may be replaced. Changed installer hashes block automatic setup.
   Separate verbose MSI logs and a setup journal show progress, partial failures and reboot requirements.
8. Option 6: APAR 7.0.2 uses port 55103; E-Office 4.1.8 uses port 55101.
   Downloads and silent installation need approval. The other supported DSS version is preserved.
9. Retain the session-log path if an error occurs.

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
