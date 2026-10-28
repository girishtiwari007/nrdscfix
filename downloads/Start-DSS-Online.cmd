@echo off
setlocal
title Digital Signing Service Troubleshooter
echo Opening PowerShell with your approval to run the DSC-FIXER command.
echo Windows will ask for Administrator permission before opening the tool.
echo You will still review and approve repairs in the troubleshooter.
echo.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $command='[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; irm ''https://raw.githubusercontent.com/girishtiwari007/DSC-FIXER/main/install.ps1'' | iex'; $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; $arguments='-NoProfile -STA -NoExit -Command '+[char]34+$command+[char]34; Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop } catch { Write-Host ('Unable to launch: '+$_.Exception.Message) -ForegroundColor Yellow; exit 1 }"
if errorlevel 1 (
  echo.
  echo Download or launch did not complete. You can retry if UAC was cancelled.
  echo If PowerShell is blocked by your organization, ask IT to approve the tool.
  pause
  exit /b 1
)
endlocal
