@echo off
setlocal
title E-Office Digital Signing Troubleshooter
set "DSS_LAUNCH_ROOT=%~dp0"
echo Digital Signing Service 4.1.8 Troubleshooter (for E-Office)
echo.
echo Windows will ask for Administrator permission.
echo The troubleshooter checks first. You choose any repairs.
echo.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $tool=Join-Path $env:DSS_LAUNCH_ROOT 'Windows-Troubleshooter.ps1'; if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){throw 'Extract all ZIP files into the same folder before running this launcher.'}; $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; $arguments='-NoProfile -STA -File '+[char]34+$tool+[char]34; Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop } catch { Write-Host ('Unable to launch: '+$_.Exception.Message) -ForegroundColor Yellow; exit 1 }"
if errorlevel 1 (
  echo.
  echo Launch did not complete. If UAC was cancelled, you can try again.
  echo If organization policy blocks PowerShell, ask IT to approve the tool.
  pause
  exit /b 1
)
endlocal
