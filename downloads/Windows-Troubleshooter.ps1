# Copyright (c) 2026 Girish Tiwari. All rights reserved.
# Use is subject to LICENSE.txt. This notice does not conceal source code.
<#
Digital Signing Service 4.1.8 Troubleshooter ( for E-Office ) - native PowerShell edition.
No batch download, self-extraction, encoded payload, automatic elevation, or execution-policy changes.
Trellix/AMSI and organization policy remain active. If blocked, stop and ask IT to review.
#>
& {
[CmdletBinding()]
param([ValidateSet('menu','console','gui','check')][string]$Mode = 'menu')
if ($env:OS -ne 'Windows_NT') { throw 'This tool requires Windows.' }
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    throw 'Organization policy restricts this PowerShell session. Ask IT to approve this tool; it will not bypass that policy.'
}
# Session logging is embedded so each published entry point remains self-contained.
function Initialize-DscSession([string]$Repository, [string]$ModeName) {
    $script:DscSession = [ordered]@{
        Schema = 1; ToolVersion = '2026.10.27.3'; Repository = $Repository
        SessionId = [guid]::NewGuid().ToString('N'); StartedUtc = [DateTime]::UtcNow.ToString('o')
        UpdatedUtc = ''; Mode = $ModeName; PowerShell = $PSVersionTable.PSVersion.ToString()
        State = 'Running'; ErrorCount = 0; Checks = @(); Improvements = @()
    }
    $script:DscLoggingFailed = $false
    $script:DscErrorKeys = @{}
    $script:DscErrorGroups = @{}
    $script:DscSessionDirectory = $null
    $roots = @()
    if ($env:DSSF_TESTROOT) { $roots = @((Join-Path $env:DSSF_TESTROOT 'out')) }
    else {
        if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'DSC-Signer-Fixer\sessions' }
        if ($env:TEMP) { $roots += Join-Path $env:TEMP 'DSC-Signer-Fixer\sessions' }
    }
    foreach ($root in $roots) {
        try {
            $dir = Join-Path $root ((Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '_' + $script:DscSession.SessionId)
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::WriteAllText((Join-Path $dir 'events.jsonl'), '', (New-Object Text.UTF8Encoding $false))
            $script:DscSessionDirectory = $dir
            break
        } catch { }
    }
    if (-not $script:DscSessionDirectory) { throw 'Cannot create a local session log. Check write access to LOCALAPPDATA or TEMP; no repairs were started.' }
    Write-DscEvent 'Info' 'Session started' @{ Mode = $ModeName }
    Save-DscSession
}
function Write-DscEvent([string]$Level, [string]$Operation, $Data) {
    if (-not $script:DscSessionDirectory) { return }
    try {
        $event = [ordered]@{ TimeUtc = [DateTime]::UtcNow.ToString('o'); SessionId = $script:DscSession.SessionId; Level = $Level; Operation = $Operation; Data = $Data }
        $json = ConvertTo-Json -InputObject $event -Depth 8 -Compress
        [IO.File]::AppendAllText((Join-Path $script:DscSessionDirectory 'events.jsonl'), $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false))
    } catch {
        if (-not $script:DscLoggingFailed) { Write-Warning 'Session logging failed. Check free disk space and folder permissions.' }
        $script:DscLoggingFailed = $true
    }
}
function Write-DscError($Record, [string]$Operation = 'Unhandled exception', [Nullable[int]]$ExitCode = $null) {
    if (-not $script:DscSession) { return }
    $type = 'System.Exception'; $message = [string]$Record; $stack = ''; $line = 0; $errorId = ''
    if ($Record -is [Management.Automation.ErrorRecord]) {
        $type = $Record.Exception.GetType().FullName; $message = $Record.Exception.Message
        $stack = $Record.ScriptStackTrace; $line = $Record.InvocationInfo.ScriptLineNumber
        $errorId = $Record.FullyQualifiedErrorId
    } elseif ($Record -is [Exception]) { $type = $Record.GetType().FullName; $message = $Record.Message; $stack = $Record.StackTrace }
    $key = "$Operation|$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Record))"
    # The same caught ErrorRecord may reach the session trap; log it only once.
    if ($script:DscErrorKeys.ContainsKey($key)) { return }
    $script:DscErrorKeys[$key] = $true
    $script:DscSession.ErrorCount++
    # Only type and numeric line enter the public report. Messages and stack traces remain local.
    $publicKey = "$type|$line|$ExitCode"
    if (-not $script:DscErrorGroups.ContainsKey($publicKey)) {
        $script:DscErrorGroups[$publicKey] = [ordered]@{ Type = $type; Line = $line; Count = 0; ExitCode = $ExitCode }
    }
    $script:DscErrorGroups[$publicKey].Count++
    Write-DscEvent 'Error' $Operation @{ Type = $type; Message = $message; StackTrace = $stack; Line = $line; ErrorId = $errorId; ExitCode = $ExitCode }
    Save-DscSession
}
function Save-DscSession($CheckResults, [string]$State = '') {
    if (-not $script:DscSessionDirectory) { return }
    try {
        if ($null -ne $CheckResults) {
            $script:DscSession.Checks = @($CheckResults.Values | ForEach-Object {
                [ordered]@{ No = $_.No; Status = $_.Status; ActionsAttempted = @($_.Actions).Count; Advice = $_.Advice }
            })
        }
        if ($State) { $script:DscSession.State = $State }
        $script:DscSession.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
        $script:DscSession.Improvements = @($script:DscSession.Checks | Where-Object { $_.Status -in 'FAIL','SKIP','WARN','PENDING' } | ForEach-Object {
            "Review check $($_.No) ($($_.Status)); see the local diagnostic report."
        })
        $doc = [ordered]@{}
        foreach ($key in $script:DscSession.Keys) { $doc[$key] = $script:DscSession[$key] }
        $doc.Errors = @($script:DscErrorGroups.Values)
        $json = ConvertTo-Json -InputObject $doc -Depth 8
        $file = Join-Path $script:DscSessionDirectory 'session.json'
        [IO.File]::WriteAllText(($file + '.tmp'), $json, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath ($file + '.tmp') -Destination $file -Force -ErrorAction Stop
        $report = Get-DscPublicReport
        [IO.File]::WriteAllText((Join-Path $script:DscSessionDirectory 'github-report.md'), $report.Body, (New-Object Text.UTF8Encoding $false))
    } catch {
        if (-not $script:DscLoggingFailed) { Write-Warning 'Could not save the session summary. Existing logs have been retained.' }
        $script:DscLoggingFailed = $true
    }
}
function Get-DscPublicReport([ValidateSet('Error','Improvement')][string]$Kind = 'Error') {
    # An allowlist is safer than trying to redact arbitrary exception messages or logs.
    $repo = [string]$script:DscSession.Repository
    if ($repo -notin @('girishtiwari007/DSC-FIX','girishtiwari007/DSC-FIXR','girishtiwari007/DSC-FIXER')) { throw 'Unsupported report repository.' }
    $version = [string]$script:DscSession.ToolVersion
    if ($version -notmatch '^\d{4}\.\d{2}\.\d{2}\.\d+$') { throw 'Invalid report version.' }
    $checks = @($script:DscSession.Checks | Sort-Object { [int]$_.No } | Select-Object -First 10 | ForEach-Object {
        $no = [int]$_.No; $status = [string]$_.Status
        if ($no -ge 1 -and $no -le 10 -and $status -in 'OK','FIXED','WARN','FAIL','SKIP','NA','NOTRUN','PENDING') { "Check ${no}: $status; attempted actions: $([int]$_.ActionsAttempted)" }
    })
    $errors = @($script:DscErrorGroups.Values | Sort-Object Type,Line | Select-Object -First 12 | ForEach-Object {
        if ($_.Type -match '^[A-Za-z][A-Za-z0-9_.+`]{0,160}$') {
            $code = $(if ($null -ne $_.ExitCode) { "; exit code $([int]$_.ExitCode)" } else { '' })
            "$($_.Type) at line $([int]$_.Line)$code (count $([int]$_.Count))"
        }
    })
    $signature = "$repo|$version|$Kind|$($checks -join '|')|$($errors -join '|')"
    # Counts do not affect grouping between sessions with the same underlying problem.
    $signature = $signature -replace '; attempted actions: \d+', '' -replace '\(count \d+\)', ''
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature))).Replace('-','').Substring(0,16)).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $body = @(
        "## DSC $Kind report", "Tool version: $version", "Fingerprint: dsc-$fingerprint", ''
        '### Check summary', $(if ($checks.Count) { $checks -join "`n" } else { 'No checks completed.' }), ''
        '### Exceptions', $(if ($errors.Count) { $errors -join "`n" } else { 'No exceptions recorded.' }), ''
        '### Expected result / improvement', 'Describe what should happen here.', ''
        '### Steps to reproduce', 'Add steps here. Do not include personal information, passwords, tokens or certificate files.', ''
        'Generated from an allowlist. Exception messages, stack traces, file paths, logs, machine/user names and certificate contents are excluded.'
    ) -join "`n"
    return @{ Repository = $repo; Title = "[DSC $Kind] dsc-$fingerprint ($version)"; Body = $body; Fingerprint = $fingerprint }
}
function Show-DscGitHubReport([ValidateSet('Error','Improvement')][string]$Kind = 'Error', [switch]$UseGui) {
    $report = Get-DscPublicReport $Kind
    $reportPath = Join-Path $script:DscSessionDirectory 'github-report.md'
    [IO.File]::WriteAllText($reportPath, $report.Body, (New-Object Text.UTF8Encoding $false))
    $searchUrl = 'https://github.com/' + $report.Repository + '/issues?q=' + [Uri]::EscapeDataString('is:issue "dsc-' + $report.Fingerprint + '"')
    $newUrl = 'https://github.com/' + $report.Repository + '/issues/new?title=' + [Uri]::EscapeDataString($report.Title) + '&body=' + [Uri]::EscapeDataString($report.Body)
    if ($UseGui) {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $dialog = New-Object Windows.Forms.Form
        try {
            $dialog.Text = 'Preview GitHub report'; $dialog.Size = New-Object Drawing.Size(760,620); $dialog.StartPosition = 'CenterScreen'
            $text = New-Object Windows.Forms.TextBox; $text.Multiline = $true; $text.ReadOnly = $true; $text.ScrollBars = 'Vertical'; $text.Dock = 'Fill'; $text.Text = $report.Body.Replace("`n","`r`n")
            $bar = New-Object Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 72
            $hint = New-Object Windows.Forms.Label; $hint.Dock = 'Top'; $hint.Height = 52; $hint.Text = "Local preview: $reportPath`r`nSearch for this fingerprint first. GitHub opens in your browser; review and submit there. Offline? Keep this file and submit later."
            $search = New-Object Windows.Forms.Button; $search.Text = 'Find existing'; $search.Width = 130
            $create = New-Object Windows.Forms.Button; $create.Text = 'Open new issue'; $create.Width = 140
            $close = New-Object Windows.Forms.Button; $close.Text = 'Close'; $close.Width = 100
            $search.Add_Click({ try { Start-Process $searchUrl -ErrorAction Stop } catch { Write-DscError $_ 'Open GitHub search'; [void][Windows.Forms.MessageBox]::Show('Browser unavailable. The preview is saved locally.') } }.GetNewClosure())
            $create.Add_Click({ try { Start-Process $newUrl -ErrorAction Stop } catch { Write-DscError $_ 'Open GitHub issue'; [void][Windows.Forms.MessageBox]::Show('Browser unavailable. The preview is saved locally.') } }.GetNewClosure())
            $close.Add_Click({ $dialog.Close() }.GetNewClosure())
            $bar.Controls.AddRange(@($search,$create,$close)); $dialog.Controls.AddRange(@($text,$hint,$bar)); [void]$dialog.ShowDialog()
        } finally { $dialog.Dispose() }
    } else {
        Write-Host $report.Body
        Write-Host "Preview saved: $reportPath"
        $choice = Read-Host '[S] Search existing issues  [N] Open new issue  [Enter] Keep locally'
        if ($choice -match '^(?i)s$') { Start-Process $searchUrl -ErrorAction Stop }
        elseif ($choice -match '^(?i)n$') { Start-Process $newUrl -ErrorAction Stop }
    }
}

Initialize-DscSession 'girishtiwari007/DSC-FIXER' $Mode
try {
$NativeSourcePath = $PSCommandPath
function Invoke-DscNative {
    param([string]$RequestedMode)
    $Results = $null
    $script:DscSession.Mode = $RequestedMode
    try {
    if ($RequestedMode -eq 'gui' -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Write-Host 'Windows popups require STA. Open Windows PowerShell (powershell.exe -STA), then run the native command again, or choose console mode.' -ForegroundColor Yellow
        return
    }
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$TestRoot = $env:DSSF_TESTROOT
$TestMode = -not [string]::IsNullOrEmpty($TestRoot)
$CheckOnly = ($RequestedMode -eq 'check')
$Mode = $(if ($RequestedMode -eq 'gui') { 'gui' } else { 'console' })
$script:Ui = $null; $script:UiJavaOffer = $null; $script:DssInstallOffered=$false; $script:InitialReviewShown=$false; $script:CancelRequested=$false; $script:RepairRunning=$false
$script:UiLog = $null
$script:UiStatus = $null
$script:UiRow = $null; $script:UiProgress=$null
$script:UiStatus = $null
$script:Handoff = $null
if ($TestMode) { $IsAdmin = ($env:DSSF_TEST_ADMIN -eq '1') }
else { $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
$Cfg = [ordered]@{
    SignerHost          = 'eoffsigner.eoffice.gov.in'
    Port                = 55101
    EditionName         = 'Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )'
    DssVersion          = '4.1.8'
    JavaPageUrl         = 'https://www.java.com/en/download/manual.jsp'
    JavaManualUrl       = 'https://www.java.com/en/download/manual.jsp'
    CaThumbprint        = '546D27D0B30A9D00BA41C40DA07CE6C49A8EDA79'
    CaCertBase64        = 'MIID3zCCAsegAwIBAgIUYbdIaFYie6ayPGXR75l5/EEZ2jcwDQYJKoZIhvcNAQENBQAwfzELMAkGA1UEBhMCSU4xEjAQBgNVBAgMCU5FVyBERUxISTEOMAwGA1UEBwwFREVMSEkxJDAiBgNVBAoMG05hdGlvbmFsIEluZm9ybWF0aWNzIENlbnRyZTEOMAwGA1UECwwFTklDU0kxFjAUBgNVBAMMDWVPZmZpY2VDQTIwMjIwHhcNMjIwODI5MTEzNDM0WhcNMjgwODI3MTEzNDM0WjB/MQswCQYDVQQGEwJJTjESMBAGA1UECAwJTkVXIERFTEhJMQ4wDAYDVQQHDAVERUxISTEkMCIGA1UECgwbTmF0aW9uYWwgSW5mb3JtYXRpY3MgQ2VudHJlMQ4wDAYDVQQLDAVOSUNTSTEWMBQGA1UEAwwNZU9mZmljZUNBMjAyMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALZhVibmxgdXmMWe3mulBzjBmQvUHAeH011nTG19kmgTVJnDChwoY7eyMQhrUBUnyFDglo/zQ7VVj2ovOYdTKG+YSDqJu5aYZcnnz9XGHxUKRAuHJu1bCtBzFjuxeHfQCKCSQ2CnMaiYDRZvV8AM62YmhQBmPaj/2zneZbcgDjbIfA/yUct+jbJ22dik7aAkn30C8lT6i4YV+JNfOxe6p8bF9EzgR6W6j9sK2ohkivfeFfW/Vlwx5Abu0v4UrOx7SZAbnLG6vFqhbs/QncZJ2yMzGkmd+dCIl9OBmCrRmrdZrsXCPTDQltPVNj+s6C3TCGgYUB7nXQP2gyTZ2VArhLsCAwEAAaNTMFEwHQYDVR0OBBYEFKhosm4IWo5uALlYJIORnqzReUWfMB8GA1UdIwQYMBaAFKhosm4IWo5uALlYJIORnqzReUWfMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQENBQADggEBAB65aaLcALJ5WeEeQbjIN65GJ2sreYKvlMf8uvYIjfu9YQpmL0ffT/j81DDcbQgFhly0L8YQdd9fx9Rc3Aw4EJcFcpG8N9wVJ87XbqFZ084vH48qg0KgZC53KBVSUVLqkHdaanCZQyKccf8knvQkjQ/7i4yEHsBi5WWgqrlElnJZCjXd0BjS/Hn1P2RgqQO7TmEUzCh8P/M4NChdb5S76QKxcE+Lc/BGSpNy83SHf2gnJzvCDMma/sZZFqSa9TiS/jE2UTFa48wwHYMr1vvUKND+60k6YN/G0jjH5mddf+Okvzh6hg3aCwymkggHPevjwQmQ9Zl+qOsqj1+LFRoiJeQ='
    KillPortOwners      = $true                     # stop any other program listening on 55101
    CreateAutoStartTask = $true                     # start DSS as admin at every logon
    LnaAllowedOrigins   = @('[*.]eoffice.gov.in')    # Chrome/Edge "local network access" allow-list
    EssentialPaths      = @('%SystemRoot%\system32', '%SystemRoot%', '%SystemRoot%\System32\Wbem', '%SystemRoot%\System32\WindowsPowerShell\v1.0\')
    StartWaitSeconds    = 60
    OpenReport          = $true
    # optional: where to download the 4.1.8 installer zip if it is not on this PC (set by install.ps1 / GitHub)
    AllowDssDownload    = $true
    PackageUrl          = 'https://nr.indianrailways.gov.in/uploads/files/1792736602773-DSC_Signer_Tool_with_DSS_4.1.8.zip'
    PackageFallbackUrl  = 'https://drive.usercontent.google.com/download?id=13TrQwUAevLNBgAnR5VF4Hmd4E2-wSwtm&export=download&confirm=t'
    PackageSha256       = ''
}
# where DigitalSignerService 4.1.8 lives on a normal install - checked FIRST for item 3
$script:DiagnosticsOnly=$true
$script:ReviewApproved=$false
$script:DscSession['Edition']=$Cfg.EditionName
$Cfg.RequiredDssPath = 'C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe'
$Cfg.DssExePaths = @($Cfg.RequiredDssPath)
if ($Cfg.AllowDssDownload -and $env:DSSF_PKGURL) { $Cfg.PackageUrl = $env:DSSF_PKGURL }
if ($env:DSSF_PKGSHA256) { $Cfg.PackageSha256 = $env:DSSF_PKGSHA256 }
if($env:DSSF_NO_PACKAGE -eq '1'){$Cfg.AllowDssDownload=$false;$Cfg.PackageUrl=''}
$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''

# ---------------------------------------------------------------- test harness hooks
$StateFile = $null
if ($TestMode) {
    $StateFile = Join-Path $TestRoot 'state.json'
    $cfgFile = Join-Path $TestRoot 'config.json'
    if (Test-Path $cfgFile) {
        $o = Get-Content $cfgFile -Raw | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $Cfg[$p.Name] = $p.Value }
    }
}
$Cfg.IsLiveUrl = "https://$($Cfg.SignerHost):$($Cfg.Port)/check/isLive"
if ($TestMode) { $Cfg.DssExePaths = @((Join-Path $TestRoot "fs/Program Files/Digital Signer Service/$($Cfg.DssVersion)/Digital Signer Service")) }
function Get-MockState { Get-Content $StateFile -Raw | ConvertFrom-Json }
function Save-MockState($s) { $s | ConvertTo-Json -Depth 12 | Set-Content -Path $StateFile -Encoding UTF8 }

# ---------------------------------------------------------------- run folder, logging
$WorkDir = Split-Path -Parent $script:DscSessionDirectory
$RunDir = $script:DscSessionDirectory
$LogFile = Join-Path $RunDir 'fix-log.txt'
$SelfPath = $NativeSourcePath
if ($SelfPath) { $SelfDir = Split-Path -Parent $SelfPath } else { $SelfDir = (Get-Location).Path }

function Log([string]$m) { Add-Content -Path $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Say([string]$m, [string]$c = 'Gray') {
    if ($Mode -ne 'gui') { Write-Host $m -ForegroundColor $c }
    Log $m
    if ($script:UiLog) { & $script:UiLog $m $c }
}
function Update-Ui { if ($script:Ui) { [System.Windows.Forms.Application]::DoEvents() } }
function Wait-Proc($p, [int]$ms) {
    $end = (Get-Date).AddMilliseconds($ms)
    while (-not $p.WaitForExit(200)) { Update-Ui; if ((Get-Date) -gt $end) { return $false } }
    return $true
}

if (-not $TestMode -and $env:SystemRoot) {
    $env:Path = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0;" + $env:Path
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { Write-DscError $_ 'Caught exception';}

# ---------------------------------------------------------------- HTTPS helper (strict = Windows certificate trust)
if (-not ('DssfHttpV3' -as [type])) {
try { Add-Type -IgnoreWarnings -WarningAction SilentlyContinue -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public class DssfHttpResultV3 {
    public bool Ok; public int Status; public string Body = ""; public string Error = "";
    public string Kind = ""; public string SslErrors = ""; public byte[] CertRaw;
    public bool CertificateTrusted; public bool ExpiredAccepted;
}
public static class DssfHttpV3 {
    public static bool IsExpiryOnly(string url, SslPolicyErrors errors, X509ChainStatusFlags[] statuses,
                                    DateTime[] starts, DateTime[] ends, DateTime now) {
        Uri u;
        if (!Uri.TryCreate(url, UriKind.Absolute, out u) || u.Scheme != "https" ||
            !String.Equals(u.Host, "eoffsigner.eoffice.gov.in", StringComparison.OrdinalIgnoreCase) ||
            u.Port != 55101 || u.AbsolutePath != "/check/isLive" || !String.IsNullOrEmpty(u.UserInfo) ||
            !String.IsNullOrEmpty(u.Query) || !String.IsNullOrEmpty(u.Fragment)) return false;
        if (errors != SslPolicyErrors.RemoteCertificateChainErrors || statuses == null || statuses.Length == 0 ||
            starts == null || ends == null || starts.Length == 0 || starts.Length != ends.Length) return false;
        bool hasTimeError = false, expired = false;
        foreach (X509ChainStatusFlags flag in statuses) {
            if (flag == X509ChainStatusFlags.NotTimeValid) hasTimeError = true;
            else if (flag != X509ChainStatusFlags.NoError) return false;
        }
        for (int i = 0; i < starts.Length; i++) {
            if (starts[i].ToUniversalTime() > now.ToUniversalTime()) return false;
            if (ends[i].ToUniversalTime() < now.ToUniversalTime()) expired = true;
        }
        return hasTimeError && expired;
    }
    public static DssfHttpResultV3 Get(string url, bool strict, int timeoutMs) { return Get(url, strict, timeoutMs, false); }
    public static DssfHttpResultV3 Get(string url, bool strict, int timeoutMs, bool allowExpiredSigner) {
        DssfHttpResultV3 r = new DssfHttpResultV3();
        try {
            HttpWebRequest q = (HttpWebRequest)WebRequest.Create(url);
            q.Proxy = null; q.Timeout = timeoutMs; q.ReadWriteTimeout = timeoutMs; q.KeepAlive = false;
            // An exception is never carried across redirects to another endpoint.
            if (allowExpiredSigner) q.AllowAutoRedirect = false;
            q.ServerCertificateValidationCallback = delegate(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) {
                if (cert != null) r.CertRaw = cert.GetRawCertData();
                r.SslErrors = errors.ToString();
                r.CertificateTrusted = errors == SslPolicyErrors.None;
                if (r.CertificateTrusted) return true;
                if (!strict) return true; // Used only by existing diagnostic probes, not by the isLive verdict.
                if (allowExpiredSigner && cert != null && chain != null) {
                    X509ChainStatusFlags[] flags = new X509ChainStatusFlags[chain.ChainStatus.Length];
                    for (int i = 0; i < flags.Length; i++) flags[i] = chain.ChainStatus[i].Status;
                    DateTime[] starts = new DateTime[chain.ChainElements.Count], ends = new DateTime[chain.ChainElements.Count];
                    for (int i = 0; i < starts.Length; i++) {
                        starts[i] = chain.ChainElements[i].Certificate.NotBefore;
                        ends[i] = chain.ChainElements[i].Certificate.NotAfter;
                    }
                    if (IsExpiryOnly(url, errors, flags, starts, ends, DateTime.UtcNow)) { r.ExpiredAccepted = true; return true; }
                }
                return false;
            };
            using (HttpWebResponse resp = (HttpWebResponse)q.GetResponse()) {
                r.Status = (int)resp.StatusCode;
                using (StreamReader sr = new StreamReader(resp.GetResponseStream())) r.Body = sr.ReadToEnd();
            }
            r.Ok = r.Status == 200;
        } catch (WebException ex) {
            r.Kind = ex.Status.ToString(); r.Error = ex.Message;
            if (ex.InnerException != null) r.Error += " | " + ex.InnerException.Message;
            HttpWebResponse er = ex.Response as HttpWebResponse;
            if (er != null) { r.Status = (int)er.StatusCode; er.Close(); }
        } catch (Exception ex) { r.Kind = "Other"; r.Error = ex.Message; }
        return r;
    }
}
'@ } catch { Write-DscError $_ 'Caught exception'; Write-Host "HTTPS helper could not be compiled: $($_.Exception.Message)" -ForegroundColor Red }
}

# =====================================================================
#  Low level OS access (real Windows, or the mock used for testing)
# =====================================================================
function Get-UninstallEntries {
    if ($TestMode) { return @((Get-MockState).apps) }
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $list = @()
    foreach ($k in $keys) {
        $list += Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString, PSChildName
    }
    return $list
}

function Get-EnvRaw([string]$Name, [string]$Scope) {
    if ($TestMode) { $s = Get-MockState; $v = $s.env.$Scope.$Name; return $v }
    if ($Scope -eq 'Machine') { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment') }
    else { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment') }
    if (-not $k) { return $null }
    try { return $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
}

function Set-EnvRaw([string]$Name, [string]$Scope, $Value) {
    Log "ENV $Scope $Name := $Value"
    if ($TestMode) {
        $s = Get-MockState
        $bag = $s.env.$Scope
        if ($null -eq $Value) { $bag.PSObject.Properties.Remove($Name) }
        elseif ($bag.PSObject.Properties[$Name]) { $bag.$Name = $Value }
        else { $bag | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
        Save-MockState $s; return
    }
    if ($Scope -eq 'Machine') { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true) }
    else { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true) }
    try {
        if ($null -eq $Value) { $k.DeleteValue($Name, $false) }
        else {
            $kind = [Microsoft.Win32.RegistryValueKind]::String
            if ($Name -eq 'Path' -or $Value -match '%') { $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $k.SetValue($Name, $Value, $kind)
        }
    } finally { $k.Close() }
}

function Send-EnvChanged {
    if ($TestMode) { return }
    try {
        if (-not ('DssfNative' -as [type])) {
            Add-Type -Namespace '' -Name DssfNative -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
        }
        $r = [UIntPtr]::Zero
        [DssfNative]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null
    } catch { Write-DscError $_ 'Caught exception'; Log "broadcast failed: $_" }
}

function Get-EffectivePathEntries {
    $m = Get-EnvRaw 'Path' 'Machine'; $u = Get-EnvRaw 'Path' 'User'
    $all = @()
    foreach ($x in @($m, $u)) { if ($x) { $all += ($x -split ';' | Where-Object { $_.Trim() }) } }
    return $all
}

function Update-ProcessEnv {
    $p = (Get-EffectivePathEntries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) }) -join ';'
    if (-not $TestMode) { $env:Path = $p }
    foreach ($n in 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS', 'JAVA_OPTIONS') {
        if (-not (Get-EnvRaw $n 'Machine') -and -not (Get-EnvRaw $n 'User')) { Remove-Item "Env:\$n" -ErrorAction SilentlyContinue }
    }
}

function Get-HostsPath { if ($TestMode) { Join-Path $TestRoot 'hosts' } else { Join-Path $env:SystemRoot 'System32\drivers\etc\hosts' } }

function Resolve-Signer {
    if ($TestMode) {
        # simulate the Windows resolver: first active hosts line wins
        $h = [regex]::Escape($Cfg.SignerHost)
        foreach ($l in (Get-Content (Get-HostsPath) -ErrorAction SilentlyContinue)) {
            $t = ($l -split '#')[0].Trim()
            if ($t -match "^(\S+)\s+(.*)$") { if (($matches[2] -split '\s+') -contains $Cfg.SignerHost) { return @($matches[1]) } }
        }
        return @()
    }
    try { return @([Net.Dns]::GetHostAddresses($Cfg.SignerHost) | ForEach-Object { $_.IPAddressToString }) } catch { Write-DscError $_ 'Caught exception'; return @() }
}

function Get-ProcInfo([int]$ProcId) {
    $o = [ordered]@{ Id = $ProcId; Name = '?'; Path = ''; Service = '' }
    if ($TestMode -or -not $IsWindowsHost) {
        try { $o.Path = ((Get-Content "/proc/$ProcId/cmdline" -Raw) -replace "`0", ' ').Trim() } catch { Write-DscError $_ 'Caught exception';}
        try { $o.Name = (Get-Content "/proc/$ProcId/comm" -Raw).Trim() } catch { Write-DscError $_ 'Caught exception';}
        return [pscustomobject]$o
    }
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
    if ($p) { $o.Name = $p.ProcessName; try { $o.Path = $p.Path } catch { Write-DscError $_ 'Caught exception';} }
    $svc = Get-CimInstance Win32_Service -Filter "ProcessId=$ProcId" -ErrorAction SilentlyContinue
    if ($svc) { $o.Service = (@($svc) | ForEach-Object { $_.Name }) -join ',' }
    return [pscustomobject]$o
}
$IsWindowsHost = ($env:OS -eq 'Windows_NT')

function ConvertFrom-NetstatText([string[]]$Lines, [int]$Port) {
    $res = @()
    foreach ($l in $Lines) {
        if ($l -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+(\S+)\s+(\d+)\s*$') {
            if ([int]$matches[2] -eq $Port) { $res += [pscustomobject]@{ State = $matches[3]; Pid = [int]$matches[4] } }
        }
    }
    return $res
}

function Get-PortListeners {
    $port = [int]$Cfg.Port; $ids = @()
    if ($TestMode -or -not $IsWindowsHost) {
        # Linux test host: /proc/net/tcp(6) LISTEN sockets -> inode -> pid
        $hex = '{0:X4}' -f $port; $inodes = @()
        foreach ($f in '/proc/net/tcp', '/proc/net/tcp6') {
            foreach ($l in (Get-Content $f -ErrorAction SilentlyContinue | Select-Object -Skip 1)) {
                $c = ($l.Trim() -split '\s+')
                if ($c[1] -match ":$hex$" -and $c[3] -eq '0A') { $inodes += $c[9] }
            }
        }
        if ($inodes.Count) {
            foreach ($d in (Get-ChildItem /proc -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' })) {
                foreach ($fd in (Get-ChildItem "/proc/$($d.Name)/fd" -ErrorAction SilentlyContinue)) {
                    $tg = "$($fd.Target)"
                    if ($tg -match 'socket:\[(\d+)\]' -and $inodes -contains $matches[1]) { $ids += [int]$d.Name }
                }
            }
        }
    } else {
        try { $ids = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | ForEach-Object { [int]$_.OwningProcess }) }
        catch { Write-DscError $_ 'Caught exception'; $ids = @(ConvertFrom-NetstatText (netstat -ano -p tcp) $port | Where-Object { $_.State -eq 'LISTENING' } | ForEach-Object { $_.Pid }) }
    }
    return @($ids | Sort-Object -Unique | ForEach-Object { Get-ProcInfo $_ })
}

function Get-ExcludedRanges {
    if ($TestMode) { return @((Get-MockState).excludedRanges) }
    $r = @()
    foreach ($fam in 'ipv4', 'ipv6') {
        foreach ($l in (netsh interface $fam show excludedportrange protocol=tcp 2>$null)) {
            if ($l -match '^\s*(\d+)\s+(\d+)\s*(\*?)\s*$') { $r += [pscustomobject]@{ Start = [int]$matches[1]; End = [int]$matches[2]; Admin = [bool]$matches[3] } }
        }
    }
    return $r
}

# =====================================================================
#  DSS helpers
# =====================================================================
function Get-DssEntries { @(Get-UninstallEntries | Where-Object { $_.DisplayName -match '(?i)signer\s*service' }) }

# the standard 'C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe' (or x86); $null if missing
function Get-DssStdExe {
    foreach ($x in $Cfg.DssExePaths) { if ($x -and (Test-Path -LiteralPath $x -PathType Leaf)) { return $x } }
    return $null
}
function Get-ExeVersion([string]$exe) {
    try { $vi = (Get-Item -LiteralPath $exe).VersionInfo; foreach ($v in @($vi.ProductVersion, $vi.FileVersion)) { if ($v -and $v -match '^\s*(\d+\.\d+\.\d+)') { return $matches[1] } } } catch { Write-DscError $_ 'Caught exception';}
    return ''
}
function Find-DssExe {
    $std = Get-DssStdExe
    if ($std) { return $std }
    $cands = @()
    foreach ($e in Get-DssEntries) { if ($e.InstallLocation) { $cands += $e.InstallLocation } }
    if ($TestMode) { $cands += (Join-Path $TestRoot 'fs/Program Files/Digital Signer Service') }
    else {
        foreach ($rk in 'HKLM:\SOFTWARE\eOffice Project Division - NIC\Digital Signer Service', 'HKLM:\SOFTWARE\WOW6432Node\eOffice Project Division - NIC\Digital Signer Service') {
            $p = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
            if ($p) { foreach ($v in $p.PSObject.Properties) { if ($v.Value -is [string] -and $v.Value -match '^[A-Za-z]:\\') { $cands += $v.Value } } }
        }
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ($pf) { $cands += (Join-Path $pf 'Digital Signer Service'); $cands += @(Get-ChildItem -Path $pf -Directory -Filter '*Signer*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
        }
    }
    foreach ($c in ($cands | Select-Object -Unique)) {
        $d = $c.Trim('"')
        if (Test-Path -LiteralPath $d -PathType Leaf) { $d = Split-Path -Parent $d }
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $exe = Get-ChildItem -LiteralPath $d -Recurse -Depth 2 -ErrorAction SilentlyContinue |
               Where-Object { -not $_.PSIsContainer -and $_.Name -match '^(Digital ?Signer ?Service)(\.exe)?$' } | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Get-DssProcesses {
    $res = @()
    if ($TestMode -or -not $IsWindowsHost) {
        foreach ($d in (Get-ChildItem /proc -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' })) {
            try { $cl = (Get-Content "/proc/$($d.Name)/cmdline" -Raw -ErrorAction Stop) -replace "`0", ' ' } catch { Write-DscError $_ 'Caught exception'; continue }
            if ($cl -match 'Digital ?Signer ?Service' -and $cl -notmatch 'pwsh|bash -c|\.bat') { $res += [pscustomobject]@{ Id = [int]$d.Name; Name = 'DigitalSignerService'; Path = $cl } }
        }
        return $res
    }
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        $path = ''; try { $path = $p.Path } catch { Write-DscError $_ 'Caught exception';}
        if ($p.ProcessName -match '(?i)signer' -or $path -match '(?i)\\Digital Signer Service\\') { $res += [pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName; Path = $path } }
    }
    return $res
}

function Test-IsDssProcess($pi) { return ($pi.Name -match '(?i)signer' -or $pi.Path -match '(?i)Digital ?Signer ?Service') }

# ---------------------------------------------------------------- installer package (embedded / chosen / nearby)
$PayloadMarker = '#__DSSF_' + 'PAYLOAD_ZIP__'
$script:PkgOverride = $null
$script:PkgMsi = $null
function Get-PayloadInfo([string]$file) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
    $fs = [IO.File]::OpenRead($file)
    try {
        $n = [int][Math]::Min($fs.Length, 8MB); $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n)
        $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf)     # 1 byte = 1 char, so index = byte offset
        $i = $txt.IndexOf("`n$PayloadMarker")
        if ($i -lt 0) { return $null }
        $j = $txt.IndexOf("`n", $i + 1)
        if ($j -lt 0) { return $null }
        return @{ ScriptEnd = $i + 1; DataStart = $j + 1; DataLen = $fs.Length - ($j + 1) }
    } finally { $fs.Close() }
}
# ---- identify the DSS installer by its CONTENT, not its file name (renamed msi / zip / folder all work)
$script:PkgIdCache = @{}
function Get-MsiIdFromStream($stream) {
    # an MSI starts with the OLE signature D0 CF 11 E0; its string pool (first MBs) holds "Digital Signer Service <version>"
    $n = 4MB; $buf = New-Object byte[] $n; $got = 0
    while ($got -lt $n) { $r = $stream.Read($buf, $got, $n - $got); if ($r -le 0) { break }; $got += $r }
    $id = @{ IsMsi = $false; IsDss = $false; Version = '' }
    if ($got -lt 8) { return $id }
    $id.IsMsi = ($buf[0] -eq 0xD0 -and $buf[1] -eq 0xCF -and $buf[2] -eq 0x11 -and $buf[3] -eq 0xE0)
    if (-not $id.IsMsi) { return $id }
    $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $got)
    $m = [regex]::Match($txt, 'Digital ?Signer ?Service\s*v?(\d+\.\d+\.\d+)')
    if (-not $m.Success) { $u = [Text.Encoding]::Unicode.GetString($buf, 0, $got - ($got % 2)); $m = [regex]::Match($u, 'Digital ?Signer ?Service\s*v?(\d+\.\d+\.\d+)') }
    if ($m.Success) { $id.IsDss = $true; $id.Version = $m.Groups[1].Value }
    elseif ($txt -match 'Digital ?Signer ?Service|DigitalSignerService') { $id.IsDss = $true }
    return $id
}
function Get-MsiIdentity([string]$path) {
    try {
        $fi = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        $key = "$($fi.FullName)|$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
        if ($script:PkgIdCache.ContainsKey($key)) { return $script:PkgIdCache[$key] }
        $fs = [IO.File]::Open($fi.FullName, 'Open', 'Read', 'ReadWrite')
        try { $id = Get-MsiIdFromStream $fs } finally { $fs.Close() }
        $id.Name = $fi.Name; $id.SizeMB = [Math]::Round($fi.Length / 1MB)
        $script:PkgIdCache[$key] = $id
        return $id
    } catch { Write-DscError $_ 'Caught exception'; Log "msi check failed $path : $($_.Exception.Message)"; return @{ IsMsi = $false; IsDss = $false; Version = ''; Error = $_.Exception.Message; Name = (Split-Path -Leaf $path) } }
}
# best DSS msi inside a zip (any file names); returns @{ Name; Version; IsDss } or $null
function Get-ZipMsiInfo([string]$zip) {
    try {
        $fi = Get-Item -LiteralPath $zip -Force -ErrorAction Stop
        $key = "zip|$($fi.FullName)|$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)"
        if ($script:PkgIdCache.ContainsKey($key)) { return $script:PkgIdCache[$key] }
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [IO.Compression.ZipFile]::OpenRead($fi.FullName)
        $best = $null
        try {
            foreach ($e in @($z.Entries | Where-Object { $_.Name -match '(?i)\.msi$' } | Sort-Object { $_.Name -notmatch '(?i)signer' })) {
                $st = $e.Open(); try { $id = Get-MsiIdFromStream $st } finally { $st.Close() }
                if (-not $id.IsDss) { continue }
                $cand = @{ Name = $e.Name; Version = $id.Version; IsDss = $true }
                if ($id.Version -eq $Cfg.DssVersion) { $best = $cand; break }
                if (-not $best) { $best = $cand }
            }
        } finally { $z.Dispose() }
        $script:PkgIdCache[$key] = $best
        return $best
    } catch { Write-DscError $_ 'Caught exception'; Log "zip read failed $zip : $($_.Exception.Message)"; return $null }
}
function Get-ZipMsiName([string]$zip) { $i = Get-ZipMsiInfo $zip; if ($i) { return $i.Name }; return $null }
function Find-InFolder([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $null }
    $all = @(Get-ChildItem -LiteralPath $dir -Recurse -Depth 4 -File -ErrorAction SilentlyContinue)
    $ver = $Cfg.DssVersion; $fallback = $null
    # 1) any .msi (any name) that really is DigitalSignerService - the right version first
    foreach ($m in @($all | Where-Object { $_.Extension -eq '.msi' -and $_.Length -gt 1MB } | Sort-Object { $_.Name -notmatch '(?i)signer|dss' })) {
        $id = Get-MsiIdentity $m.FullName
        if (-not $id.IsDss) { continue }
        $r = @{ Kind = 'msi'; Path = $m.FullName; Text = $m.FullName; Version = $id.Version }
        if ($id.Version -eq $ver) { return $r }
        if (-not $fallback) { $fallback = $r }
    }
    # 2) any .zip (any name) holding a DigitalSignerService msi
    foreach ($z in @($all | Where-Object { $_.Extension -eq '.zip' -and $_.Length -lt 1GB } | Sort-Object { $_.Name -notmatch '(?i)signer|dss' })) {
        $i = Get-ZipMsiInfo $z.FullName
        if (-not $i) { continue }
        $r = @{ Kind = 'zip'; Path = $z.FullName; Text = "$($z.FullName)  ($($i.Name))"; Version = $i.Version }
        if ($i.Version -eq $ver) { return $r }
        if (-not $fallback) { $fallback = $r }
    }
    return $fallback
}
function Test-PackagePath([string]$p) {
    try {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $null }
        if (Test-Path -LiteralPath $p -PathType Container) { return (Find-InFolder $p) }
        if ($p -match '(?i)\.msi$') { $id = Get-MsiIdentity $p; return @{ Kind = 'msi'; Path = $p; Text = $p; Version = $id.Version; Id = $id } }
        if ($p -match '(?i)\.zip$') { $i = Get-ZipMsiInfo $p; if ($i) { return @{ Kind = 'zip'; Path = $p; Text = "$p  ($($i.Name))"; Version = $i.Version } } }
    } catch { Write-DscError $_ 'Caught exception'; Log "package check failed $p : $($_.Exception.Message)" }
    return $null
}
# where is the 4.1.8 installer? (no extraction - safe to call while only testing)
$script:PkgSkipped = $false
# the current user's Downloads folder (also when it was moved, e.g. to D:\Downloads)
function Get-DownloadsFolder {
    if ($TestMode) { return (Join-Path $TestRoot 'Downloads') }
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($v) { $v = [Environment]::ExpandEnvironmentVariables($v); if (Test-Path -LiteralPath $v) { return $v } }
    } catch { Write-DscError $_ 'Caught exception';}
    return (Join-Path $env:USERPROFILE 'Downloads')
}
function Find-DssPackageSource {
    if ($script:PkgSkipped -and -not $script:PkgOverride) { return $null }
    if ($script:PkgOverride) { $x = Test-PackagePath $script:PkgOverride; if ($x) { $x.Text = "chosen by you: $($x.Text)"; return $x } }
    $pi = Get-PayloadInfo $SelfPath
    if ($pi -and $pi.DataLen -gt 1000) { return @{ Kind = 'embedded'; Path = $SelfPath; Text = "built into this tool ($([Math]::Round($pi.DataLen / 1MB)) MB)" } }
    # default place to look: the user's Downloads folder, then next to this tool, Desktop, D:\SOFT DOWNLOAD
    $roots = @((Get-DownloadsFolder), $SelfDir)
    if (-not $TestMode) { $roots += @("$env:USERPROFILE\Desktop", 'D:\SOFT DOWNLOAD') }
    foreach ($r in ($roots | Select-Object -Unique)) { $x = Find-InFolder $r; if ($x) { return $x } }
    return $null
}
# returns the MSI path, unpacking a zip / the embedded package when needed
# download with resume, system proxy, browser user-agent, progress and plain-language errors
function Get-WebFileResume([string]$Url, [string]$OutFile, [int]$Tries = 4) {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { Write-DscError $_ 'Caught exception';}
    $part = "$OutFile.part"; $why = ''
    for ($try = 1; $try -le $Tries; $try++) {
        $have = 0; if (Test-Path -LiteralPath $part) { $have = (Get-Item -LiteralPath $part).Length }
        $resp = $null; $in = $null; $out = $null
        try {
            $req = [Net.HttpWebRequest][Net.WebRequest]::Create($Url)
            $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 DSC-Signer-Fixer'
            $req.Timeout = 30000; $req.ReadWriteTimeout = 60000; $req.AllowAutoRedirect = $true
            try { $req.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $req.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch { Write-DscError $_ 'Caught exception';}
            if ($have -gt 0) { $req.AddRange([long]$have) }
            $resp = $req.GetResponse()
            $append = ($have -gt 0 -and [int]$resp.StatusCode -eq 206)
            if (-not $append) { $have = 0 }
            $total = $have + [long]$resp.ContentLength
            $in = $resp.GetResponseStream()
            $out = New-Object IO.FileStream($part, $(if ($append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }), [IO.FileAccess]::Write)
            $buf = New-Object byte[] 1MB; $done = $have; $last = [DateTime]::MinValue
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n); $done += $n; Update-Ui
                if (((Get-Date) - $last).TotalMilliseconds -gt 700) {
                    $last = Get-Date
                    $pct = $(if ($total -gt 0) { [int](100 * $done / $total) } else { 0 })
                    if($script:UiStatus){$downloadStatus="Downloading DSS installer: $([Math]::Round($done/1MB,1)) MB";if($total -gt 0){$downloadStatus+=" / $([Math]::Round($total/1MB,1)) MB ($pct%)"};& $script:UiStatus $downloadStatus ('Source: '+$Url)}
                    Write-Progress -Activity 'Downloading DigitalSignerService 4.1.8 package' -Status ("{0:N1} of {1:N1} MB" -f ($done / 1MB), ($total / 1MB)) -PercentComplete $pct
                }
            }
            $out.Close(); $out = $null
            if ($total -gt 0 -and (Get-Item -LiteralPath $part).Length -lt $total) { throw (New-Object IO.IOException('connection closed before the download finished')) }
            Write-Progress -Activity 'Downloading DigitalSignerService 4.1.8 package' -Completed
            Move-Item -LiteralPath $part -Destination $OutFile -Force
            return @{ Ok = $true; Text = 'downloaded' }
        } catch { Write-DscError $_ 'Caught exception';
            $ex = $_.Exception; while ($ex.InnerException -and $ex -isnot [Net.WebException]) { $ex = $ex.InnerException }
            $we = $ex -as [Net.WebException]; $code = 0
            if ($we -and $we.Response) { try { $code = [int]$we.Response.StatusCode } catch { Write-DscError $_ 'Caught exception';} }
            $why = $ex.Message; $retry = $true
            if ($we) {
                switch -Regex ($we.Status.ToString()) {
                    'NameResolutionFailure'      { $why = "cannot find the server $(([Uri]$Url).Host) - no internet, or DNS is blocked on this network"; $retry = $false }
                    'ProxyNameResolutionFailure' { $why = 'the proxy server set on this PC cannot be found - check Internet Options > Connections > LAN settings'; $retry = $false }
                    'TrustFailure|SecureChannel' { $why = 'secure (HTTPS) connection failed - check the PC date and time, or the network blocks this site'; $retry = $false }
                    'Timeout'                    { $why = 'the server did not answer in time (slow or blocked network)' }
                    'ConnectFailure'             { $why = 'could not connect to the server (firewall / network blocks it, or the site is down)' }
                }
            }
            if (-not $code -and $why -match '(?i)proxy') {
                if ($why -match '407') { $code = 407 } elseif ($why -match '403') { $why = 'the network proxy / firewall of this office blocks this website - ask IT to allow it, or download it in the browser'; $retry = $false }
            }
            if ($why -match '(?i)No such host|could not be resolved|Name or service not known') { $why = "cannot find the server $(([Uri]$Url).Host) - no internet, or DNS is blocked on this network"; $retry = $false }
            if ($code -eq 404) { $why = 'the file is no longer at this address (404 - moved or deleted on the website)'; $retry = $false }
            elseif ($code -eq 407) { $why = 'the proxy server needs a login - open the link once in the browser, then try again'; $retry = $false }
            elseif ($code -eq 403) { $why = 'the website refused the download (403 - blocked for this network)'; $retry = $false }
            elseif ($code -eq 416) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            Write-Host "      try $try of ${Tries}: $why" -ForegroundColor Yellow
            if (-not $retry) { break }
            Start-Sleep -Seconds ([Math]::Min(2 * $try, 8))
        } finally {
            if ($out) { try { $out.Close() } catch { Write-DscError $_ 'Caught exception';} }
            if ($in) { try { $in.Close() } catch { Write-DscError $_ 'Caught exception';} }
            if ($resp) { try { $resp.Close() } catch { Write-DscError $_ 'Caught exception';} }
        }
    }
    # last resort: Windows background transfer (works through most company proxies)
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Write-Host '      trying Windows background download (BITS) ...' -ForegroundColor Yellow
            Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName 'DSC Signer package' -ErrorAction Stop
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            return @{ Ok = $true; Text = 'downloaded (BITS)' }
        } catch { Write-DscError $_ 'Caught exception'; $why = "$why | BITS: $($_.Exception.Message)" }
    }
    return @{ Ok = $false; Text = $why }
}

# a 'single-file tool' .bat carries the installer zip after a marker line - copy that zip out
function Export-BatPayload([string]$Bat, [string]$OutZip) {
    $fs = [IO.File]::OpenRead($Bat)
    try {
        $n = [int][Math]::Min($fs.Length, 16MB); $buf = New-Object byte[] $n; $got = 0
        while ($got -lt $n) { $r = $fs.Read($buf, $got, $n - $got); if ($r -le 0) { break }; $got += $r }
        $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $got)
        $i = $txt.IndexOf('#__DSSF_' + 'PAYLOAD_ZIP__')
        if ($i -lt 0) { return $false }
        $j = $txt.IndexOf("`n", $i); if ($j -lt 0) { return $false }
        $start = $j + 1
        if ($buf[$start] -ne 0x50 -or $buf[$start + 1] -ne 0x4B) { return $false }   # 'PK' = zip
        [void]$fs.Seek($start, 'Begin')
        $o = [IO.File]::Create($OutZip); try { $fs.CopyTo($o) } finally { $o.Close() }
        return $true
    } finally { $fs.Close() }
}

# fetch the 4.1.8 installer from $Cfg.PackageUrl (set by the online setup) only when a fix needs it.
# Accepts a zip that holds the msi, OR a zip that holds the single-file tool (.bat with the installer inside).
function Get-DssPackageFromWeb {
    if (-not $Cfg.AllowDssDownload -or -not $Cfg.PackageUrl) { return $false }
    if (-not (Confirm-DssDownload)) { return $false }
    $downloadDir=Join-Path (Get-DownloadsFolder) 'DSC-Signer-4.1.8'
    [void][IO.Directory]::CreateDirectory($downloadDir)
    $sources=@($Cfg.PackageUrl)
    if($Cfg.PackageFallbackUrl -and $Cfg.PackageFallbackUrl -ne $Cfg.PackageUrl){$sources+= $Cfg.PackageFallbackUrl}
    $failures=@();$attempt=0
    foreach($url in $sources){
        $attempt++
        $zip=Join-Path $downloadDir ('DSS-4.1.8-'+$script:DscSession.SessionId+'-source'+$attempt+'.zip')
        try {
            Say "      Downloading DSS $($Cfg.DssVersion), source $attempt of $($sources.Count): $url" 'Cyan'
            if($TestMode -and $url -notmatch '^https?:'){Copy-Item -LiteralPath $url -Destination $zip}
            else {
                $download=Get-WebFileResume $url $zip
                if(-not $download.Ok){throw ('Download failed: '+$download.Text)}
            }
            # Reject HTML sign-in/confirmation pages before extraction or execution.
            $stream=[IO.File]::OpenRead($zip)
            try{$signature=New-Object byte[] 4;$read=$stream.Read($signature,0,4)}finally{$stream.Dispose()}
            if($read -lt 4 -or $signature[0] -ne 0x50 -or $signature[1] -ne 0x4B){throw 'The source did not return a ZIP archive. A sign-in, permission or confirmation page may have been returned.'}
            if($Cfg.PackageSha256 -and (Get-DssSha256 $zip) -ne $Cfg.PackageSha256.ToUpper()){
                Move-Item -LiteralPath $zip -Destination ($zip+'.rejected') -Force
                throw 'Installer package SHA256 mismatch. Archive quarantined.'
            }
            $candidate=$zip
            if(-not (Test-PackagePath $candidate)){
                $dir=Join-Path $RunDir ('web-package-'+[guid]::NewGuid().ToString('N'))
                Expand-DssArchive -LiteralPath $zip -DestinationPath $dir -Force
                if(-not (Find-InFolder $dir)){
                    foreach($bat in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter *.bat | Where-Object {$_.Length -gt 1MB})){
                        $payload=Join-Path $dir 'payload.zip'
                        if(Export-BatPayload $bat.FullName $payload){Expand-DssArchive -LiteralPath $payload -DestinationPath (Join-Path $dir 'payload') -Force;Remove-Item -LiteralPath $payload -Force;break}
                    }
                }
                $mapped=Find-InFolder $dir
                if(-not $mapped -or ($mapped.Version -and $mapped.Version -ne $Cfg.DssVersion)){throw "Downloaded package does not contain DSS $($Cfg.DssVersion)."}
                $candidate=$mapped.Path
            }
            if($script:UiStatus){& $script:UiStatus 'Validating downloaded DSS installer before installation ...' ('Package: '+$candidate)}
            $valid=Test-PackageValid $candidate
            if(-not $valid.Ok){throw ('Downloaded installer validation failed: '+$valid.Text)}
            $script:PkgOverride=$candidate;$script:PkgMsi=$null;$script:PkgSkipped=$false
            $script:DssPackageFailure=''
            Write-DscEvent 'Info' 'DSS package downloaded and validated' @{Source=$url;Path=$candidate}
            Say '      Package saved under Downloads and automatically validated.' 'Green'
            return $true
        } catch {
            $reason="Source $attempt ($url): $($_.Exception.Message)"
            $failures+=$reason
            Write-DscError $_ 'DSS package source failed'
            Write-DscEvent 'Warning' 'DSS package fallback' @{Source=$url;Reason=$_.Exception.Message}
            Say ("      $reason" + $(if($attempt -lt $sources.Count){' Trying the approved fallback ...'}else{''})) 'Yellow'
        }
    }
    $script:DssPackageFailure=$failures -join "`r`n"
    throw ('No valid DSS installer could be downloaded. '+$script:DssPackageFailure)
}
function Get-DssPackageMsi {
    if($script:PkgMsi -and (Test-Path -LiteralPath $script:PkgMsi)){
        $cached=Test-PackageValid $script:PkgMsi
        if($cached.Ok){return $script:PkgMsi}
        $script:PkgMsi=$null
    }
    $source=Find-DssPackageSource
    if($source -and $source.Kind -in 'msi','zip'){
        $existing=Test-PackageValid $source.Path
        if(-not $existing.Ok){Log ('Existing package ignored: '+$existing.Text);$source=$null;$script:PkgOverride=$null}
    }
    if(-not $source -and (Get-DssPackageFromWeb)){$source=Find-DssPackageSource}
    if(-not $source){return $null}
    $candidate=$null;$zip=$null
    switch($source.Kind){
        'msi' {$candidate=$source.Path}
        'zip' {$zip=$source.Path}
        'embedded' {
            $payload=Get-PayloadInfo $SelfPath
            $zip=Join-Path $RunDir 'embedded-DSS-package.zip'
            $inputFile=[IO.File]::OpenRead($SelfPath);$outputFile=[IO.File]::Create($zip)
            try{[void]$inputFile.Seek($payload.DataStart,'Begin');$inputFile.CopyTo($outputFile)}finally{$inputFile.Dispose();$outputFile.Dispose()}
        }
    }
    if($zip){
        $destination=Join-Path $RunDir ('mapped-package-'+[guid]::NewGuid().ToString('N'))
        Expand-DssArchive -LiteralPath $zip -DestinationPath $destination -Force
        $found=Find-InFolder $destination
        if($found -and $found.Kind -eq 'msi'){$candidate=$found.Path}
    }
    if(-not $candidate){throw 'No DSS 4.1.8 MSI could be mapped from the package.'}
    $validation=Test-PackageValid $candidate
    if(-not $validation.Ok){throw ('Mapped MSI failed validation: '+$validation.Text)}
    $script:PkgMsi=$candidate
    Write-DscEvent 'Info' 'DSS MSI mapped and validated' @{Path=$candidate}
    return $candidate
}
# validate a chosen zip / msi / folder: it must contain the Digital Signer Service 4.1.8 msi
function Test-PackageValid([string]$p) {
    # never throws: every problem comes back as a NOT VALID text
    try {
        $p = "$p".Trim().Trim('"')
        if (-not $p) { return @{ Ok = $false; Text = 'No location given.' } }
        if ($p.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return @{ Ok = $false; Text = "The path contains invalid characters: $p" } }
        if (-not (Test-Path -LiteralPath $p)) { return @{ Ok = $false; Text = "Not found: $p" } }
        $isDir = Test-Path -LiteralPath $p -PathType Container
        if (-not $isDir -and $p -notmatch '(?i)\.(msi|zip)$') { return @{ Ok = $false; Text = "Please choose the .zip, the .msi, or the folder that contains them (not $(Split-Path -Leaf $p))." } }
        $ver = $Cfg.DssVersion
        if (-not $isDir -and $p -match '(?i)\.msi$') {
            $id = Get-MsiIdentity $p
            if ($id.Error) { return @{ Ok = $false; Text = "Cannot read $($id.Name): $($id.Error)  (close any program using it and try again)" } }
            if (-not $id.IsMsi) { return @{ Ok = $false; Text = "$($id.Name) is not a valid MSI file (damaged or incomplete download?)" } }
            if (-not $id.IsDss) { return @{ Ok = $false; Text = "$($id.Name) is an installer for some other software, not DigitalSignerService" } }
            if ($id.Version -and $id.Version -ne $ver) { return @{ Ok = $false; Text = "$($id.Name) is DigitalSignerService $($id.Version) - version $ver is needed" } }
            return @{ Ok = $true; Text = "VALID - $($id.Name)  (DigitalSignerService $ver, $($id.SizeMB) MB)  in $(Split-Path -Parent (Resolve-Path -LiteralPath $p).ProviderPath)"; Path = $p }
        }
        $x = Test-PackagePath $p
        if (-not $x) {
            $what = $(if ($isDir) { 'this folder (or its sub-folders)' } else { 'this zip' })
            return @{ Ok = $false; Text = "No DigitalSignerService installer (.msi) found in $what : $p" }
        }
        if ($x.Version -and $x.Version -ne $ver) { return @{ Ok = $false; Text = "Found DigitalSignerService $($x.Version), but version $ver is needed: $($x.Text)" } }
        return @{ Ok = $true; Text = "VALID - $($x.Text)  (DigitalSignerService $ver)"; Path = $p }
    } catch { Write-DscError $_ 'Caught exception';
        Log "validate failed $p : $($_.Exception.Message)"
        return @{ Ok = $false; Text = "Could not check this location: $($_.Exception.Message)" }
    }
}
function Get-DefaultPackagePath {
    $src = Find-DssPackageSource
    if (-not $src) { return '' }
    if ($src.Kind -eq 'embedded') { return '(built into this tool)' }
    return $src.Path
}
function Set-PackageOverride([string]$p, [switch]$Quiet) {
    $x = Test-PackagePath $p
    if (-not $x) { Say "      No 'Digital Signer Service ... .msi' found in: $p" 'Red'; return $false }
    $script:PkgOverride = $p; $script:PkgMsi = $null; $script:PkgSkipped = $false
    if (-not $Quiet) { Say "      Installer package selected: $($x.Text)" 'Cyan' } else { Log "Installer package selected: $($x.Text)" }
    return $true
}
function Show-PickPackage([string]$what) {
    # what = file | folder ; returns a path or $null
    try {
        if (-not $env:DSSF_GUISTUB) { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop }
        if ($what -eq 'folder') {
            $d = New-Object System.Windows.Forms.FolderBrowserDialog
            $d.Description = 'Select the folder that contains the DigitalSignerService 4.1.8 zip or msi'
            $d.SelectedPath = (Get-DownloadsFolder)
            if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath }
        } else {
            $d = New-Object System.Windows.Forms.OpenFileDialog
            $d.Title = 'Select DigitalSignerService 4.1.8 zip or msi'
            $d.InitialDirectory = (Get-DownloadsFolder)
            $d.Filter = 'DSS installer (*.zip;*.msi)|*.zip;*.msi|All files (*.*)|*.*'
            if ($d.ShowDialog() -eq 'OK') { return $d.FileName }
        }
    } catch { Write-DscError $_ 'Caught exception'; Log "dialog failed: $_" }
    return $null
}

# ---------------------------------------------------------------- build ONE file = this tool + installer zip
function Build-PortableTool {
    Say 'Batch packing is not available in the native PowerShell edition. Use a separately approved MSI package when installation is needed.' 'Yellow'
    return $null
}

function Invoke-Exe([string]$File, [string]$ArgLine, [int]$TimeoutSec = 900) {
    Log "RUN $File $ArgLine"
    if($script:UiStatus){& $script:UiStatus ("Running $File - waiting for it to finish; see the session log for details.")}
    if ($TestMode) { return 0 }
    Write-DscEvent 'Info' 'Process started' @{ File = $File; TimeoutSeconds = $TimeoutSec }
    $p = Start-Process -FilePath $File -ArgumentList $ArgLine -PassThru -WindowStyle Hidden -ErrorAction Stop
    try {
        if (-not (Wait-Proc $p ($TimeoutSec * 1000))) {
            try { $p.Kill() } catch { Write-DscError $_ 'Stop timed out process' }
            Write-DscError (New-Object TimeoutException('Process exceeded its timeout.')) 'Process timeout'
            Write-DscEvent 'Error' 'Process exited' @{ File = $File; ExitCode = -1 }
            return -1
        }
        $code = $p.ExitCode
        Write-DscEvent 'Info' 'Process exited' @{ File = $File; ExitCode = $code }
        if ($code -notin 0,3010,1641) { Write-DscError (New-Object InvalidOperationException("Process failed with exit code $code.")) 'Process failed' -ExitCode $code }
        return $code
    } finally { $p.Dispose() }
}

# =====================================================================
#  Result bookkeeping
# =====================================================================
$Results = [ordered]@{}
function New-Result([int]$No, [string]$Title) {
    $r = [pscustomobject]@{ No = $No; Title = $Title; Status = 'PENDING'; Before = 'NOTRUN'; BeforeValue = ''; Value = ''
        Detail = New-Object System.Collections.ArrayList; Actions = New-Object System.Collections.ArrayList; Advice = '' }
    $Results["$No"] = $r; return $r
}
function Add-Detail($r, [string]$t) { [void]$r.Detail.Add($t); Log "  [$($r.No)] $t" }
function Add-Action($r, [string]$t) { [void]$r.Actions.Add($t); Say "      -> $t" 'Cyan' }
function Get-Label([string]$st) {
    switch ($st) { 'OK' { 'TEST OK' } 'WARN' { 'OK - WARNING' } 'NA' { 'N/A' } 'FIXED' { 'FIXED-OK' } 'SKIP' { 'NOT FIXED' } 'NOTRUN' { 'NOT NEEDED' } 'PENDING' { '...' } default { 'FAILED' } }
}
function Get-Color([string]$st) {
    switch ($st) { 'OK' { 'Green' } 'FIXED' { 'Green' } 'WARN' { 'Yellow' } 'NA' { 'DarkGray' } 'NOTRUN' { 'DarkGray' } default { 'Red' } }
}
function Show-Row($r) {
    $t = $r.Title; if ($t.Length -gt 48) { $t = $t.Substring(0, 48) }
    $v = $r.Value; if ($v.Length -gt 88) { $v = $v.Substring(0, 88) + '...' }
    Write-Host ('  {0,2}  ' -f $r.DisplayNo) -NoNewline
    Write-Host ('{0,-10}' -f (Get-Label $r.Status)) -ForegroundColor (Get-Color $r.Status) -NoNewline
    Write-Host (' {0,-49}' -f $t) -NoNewline
    Write-Host $v -ForegroundColor DarkCyan
    Log ("  [{0}] {1} {2} | {3}" -f $r.No, (Get-Label $r.Status), $r.Title, $r.Value)
}
function Set-FromTest($r, $t) {
    if ($t.DiagnosticError -or $t.Inconclusive) {
        $r | Add-Member -NotePropertyName Fixable -NotePropertyValue $false -Force
        $r.Status='WARN'; $r.Value='Diagnostic not verified; see log'; $r.Advice='No repair is inferred from an unavailable diagnostic.'
        return
    }
    $r | Add-Member -NotePropertyName Fixable -NotePropertyValue ([bool]($t.Fixable -or -not $t.Pass)) -Force
    if ($t.NA) { $r.Status = 'NA' } elseif ($t.Pass) { $r.Status = $(if ($t.Warn) { 'WARN' } else { 'OK' }) } else { $r.Status = 'FAIL' }
    if ($t.Value -and ($t.Pass -or $t.NA)) { $r.Value = $t.Value } elseif (-not $t.Pass -and $t.FailValue) { $r.Value = $t.FailValue } elseif ($t.Info) { $r.Value = @($t.Info)[0] } else { $r.Value = '' }
    if (-not $t.Pass -and $t.Advice -and -not $r.Advice) { $r.Advice = $t.Advice }
}
$script:Answers = @(); if ($env:DSSF_ANSWERS) { $script:Answers = @($env:DSSF_ANSWERS -split ',') }
function AskText([string]$q) {
    if ($TestMode) {
        $a = ''; if ($script:Answers.Count) { $a = $script:Answers[0]; $script:Answers = @($script:Answers | Select-Object -Skip 1) }
        Say "$q $a" 'Yellow'; return $a
    }
    Write-Host $q -ForegroundColor Yellow -NoNewline; return (Read-Host)
}
function Ask([string]$q, [string[]]$valid, [string]$def) {
    while ($true) {
        if ($TestMode) {
            if ($script:Answers.Count) { $a = $script:Answers[0]; $script:Answers = @($script:Answers | Select-Object -Skip 1) } else { $a = $def }
            Say "$q $a" 'Yellow'
        } else {
            Write-Host $q -ForegroundColor Yellow -NoNewline; $a = Read-Host
        }
        $a = "$a".Trim().ToUpper(); if (-not $a) { $a = $def }
        if ($valid -contains $a) { Log "ANSWER $q -> $a"; return $a }
    }
}

# =====================================================================
#  CHECK 6 - hosts file
# =====================================================================
function Test-Hosts {
    $path=Get-HostsPath; $hostName=$Cfg.SignerHost; $good=0; $bad=@(); $info=@()
    try {$lines=[IO.File]::ReadAllLines($path)} catch {
        Write-DscError $_ 'Read hosts diagnostic'
        return @{Pass=$false;Info=@('hosts file could not be read: '+$_.Exception.Message);Advice='Run as administrator or ask IT to review hosts-file access.'}
    }
    foreach($line in $lines){
        $active=($line -split '#',2)[0].Trim()
        if(-not $active){continue}
        $tokens=@($active -split '\s+')
        if($tokens.Count -gt 1 -and @($tokens | Select-Object -Skip 1) -contains $hostName){
            if($tokens[0] -eq '127.0.0.1'){$good++}else{$bad+=$active}
        }
    }
    $ips=@(Resolve-Signer)
    $resolvesOk=$ips.Count -gt 0 -and @($ips | Where-Object {$_ -ne '127.0.0.1'}).Count -eq 0
    if(-not $good){$info+="No active valid '127.0.0.1 $hostName' mapping was found."}
    foreach($line in $bad){$info+=('Conflicting active mapping: '+$line)}
    if(-not $resolvesOk){$info+="$hostName resolves to '$($ips -join ', ')' instead of only 127.0.0.1."}
    $pass=$good -ge 1 -and $bad.Count -eq 0 -and $resolvesOk
    if($pass){$info=@("$good active loopback mapping(s); $hostName resolves to 127.0.0.1.")}
    return @{Pass=$pass;Info=$info;Value=$(if($pass){"127.0.0.1 $hostName"}else{''});Advice='Review and apply the hosts repair to create a separate loopback entry. Unrelated entries are preserved. If access is blocked, ask IT to review it.'}
}
function Repair-Hosts($r) {
    $path=Get-HostsPath; $hostName=$Cfg.SignerHost; $h=[regex]::Escape($hostName)
    # A readable, verified backup is required before changing the hosts file.
    $lines=[IO.File]::ReadAllLines($path)
    $backup=Join-Path $RunDir ('hosts.backup-'+[guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash){throw 'Hosts backup verification failed. No hosts changes were made.'}
    $out=New-Object 'Collections.Generic.List[string]'
    foreach($line in $lines){
        if($line.TrimStart().StartsWith('#')){$out.Add($line);continue}
        # Recover a missing newline before the exact signer loopback entry.
        # Example: 0.0.0.1 other.example127.0.0.1 eoffsigner.eoffice.gov.in
        $parts=[regex]::Split($line,"(?<=\S)(?=127\.0\.0\.1\s+$h(?:\s|#|$))")
        foreach($part in $parts){
            $pieces=$part -split '#',2; $active=$pieces[0].Trim()
            $tokens=@($active -split '\s+')
            if($tokens.Count -gt 1 -and @($tokens | Select-Object -Skip 1) -contains $hostName){
                $aliases=@($tokens | Select-Object -Skip 1 | Where-Object {$_ -ine $hostName})
                $comment=$(if($pieces.Count -gt 1){'#'+$pieces[1]}else{''})
                if($aliases.Count){$out.Add($tokens[0]+' '+($aliases -join ' ')+$(if($comment){' '+$comment}else{''}))}
                elseif($comment){$out.Add($comment)}
            }else{$out.Add($part)}
        }
    }
    while($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count-1])){$out.RemoveAt($out.Count-1)}
    $out.Add("127.0.0.1 $hostName")
    $file=Get-Item -LiteralPath $path -Force; $attributes=$file.Attributes
    try {
        if($attributes -band [IO.FileAttributes]::ReadOnly){$file.Attributes=$attributes -band (-bnot [IO.FileAttributes]::ReadOnly)}
        [IO.File]::WriteAllText($path,($out -join "`r`n")+"`r`n",(New-Object Text.UTF8Encoding $false))
    } finally { (Get-Item -LiteralPath $path -Force).Attributes=$attributes }
    Add-Action $r "Hosts repaired with a separate '127.0.0.1 $hostName' line. Verified original backup: $backup"
    if(-not $TestMode){ipconfig /flushdns | Out-Null;Add-Action $r 'DNS cache flushed'}
}

# =====================================================================
#  CHECK 5 - environment variables
# =====================================================================
$ToolOptionVars = 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS', 'JAVA_OPTIONS'
function Get-StaleReason([string]$entry) {
    $x = [Environment]::ExpandEnvironmentVariables($entry).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($x)) { return $null }
    if (-not (Test-Path -LiteralPath $x)) { return 'folder does not exist' }
    $javaFiles = @(Get-ChildItem -LiteralPath $x -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^javaw?(\.exe)?$' })
    if ($x -match '(?i)javapath') {
        foreach ($j in $javaFiles) {
            if ($j.LinkType -eq 'SymbolicLink') {
                $tg = @($j.Target)[0]
                if ($tg -and -not [IO.Path]::IsPathRooted($tg)) { $tg = Join-Path $x $tg }
                if ($tg -and -not (Test-Path -LiteralPath $tg)) { return 'javapath link points to an uninstalled Java' }
            }
        }
    }
    if ($x -match '(?i)[\\/]bin[\\/]?$' -and $javaFiles.Count -eq 0) { return 'no java.exe in this folder' }
    return $null
}
function Test-EnvVars {
    $issues = @(); $plan = @()
    foreach ($scope in 'Machine', 'User') {
        $p = Get-EnvRaw 'Path' $scope
        if ($p) {
            $seen = @{}
            foreach ($e in ($p -split ';')) {
                if (-not $e.Trim()) { continue }
                if ($e -notmatch '(?i)java|jre|jdk') { continue }
                $key = [Environment]::ExpandEnvironmentVariables($e).Trim().TrimEnd('\', '/').ToLower()
                if ($seen.ContainsKey($key)) { $issues += "$scope PATH: duplicate '$e'"; $plan += @{ Scope = $scope; Entry = $e }; continue }
                $seen[$key] = 1
                $why = Get-StaleReason $e
                if ($why) { $issues += "$scope PATH: '$e' ($why)"; $plan += @{ Scope = $scope; Entry = $e } }
            }
        }
        foreach ($v in 'JAVA_HOME', 'JRE_HOME') {
            $val = Get-EnvRaw $v $scope
            if ($val) {
                $x = [Environment]::ExpandEnvironmentVariables($val).Trim('"')
                $ok = (Test-Path -LiteralPath (Join-Path $x 'bin/java.exe')) -or (Test-Path -LiteralPath (Join-Path $x 'bin/java'))
                if (-not $ok) { $issues += "$scope $v = '$val' (no Java there)"; $plan += @{ Scope = $scope; Var = $v } }
            }
        }
        foreach ($v in $ToolOptionVars) {
            $val = Get-EnvRaw $v $scope
            if ($val) { $issues += "$scope $v = '$val' (tool options break Java start-up)"; $plan += @{ Scope = $scope; Var = $v } }
        }
    }
    $mp = @((Get-EnvRaw 'Path' 'Machine') -split ';' | Where-Object { $_.Trim() } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().TrimEnd('\', '/').ToLower() })
    foreach ($ess in $Cfg.EssentialPaths) {
        $x = [Environment]::ExpandEnvironmentVariables($ess).TrimEnd('\', '/').ToLower()
        if ($mp -notcontains $x) { $issues += "Machine PATH: Windows folder '$ess' is missing (breaks powershell / java / installers)"; $plan += @{ Scope = 'Machine'; AddPath = $ess } }
    }
    $info = $issues; if (-not $issues) { $info = @('No stale Java PATH entries, JAVA_HOME OK, no JAVA_TOOL_OPTIONS / _JAVA_OPTIONS') }
    return @{ Pass = ($issues.Count -eq 0); Info = $info; Plan = $plan; Value = $(if ($issues.Count) { "$($issues.Count) problem(s)" } else { 'clean' }); Advice = 'Edit System Properties > Environment Variables manually.' }
}
function Repair-EnvVars($r, $t) {
    $bk = [ordered]@{}
    foreach ($s in 'Machine', 'User') { foreach ($n in @('Path', 'JAVA_HOME', 'JRE_HOME') + $ToolOptionVars) { $bk["$s|$n"] = Get-EnvRaw $n $s } }
    $bk | ConvertTo-Json | Set-Content (Join-Path $RunDir 'environment.backup.json')
    foreach ($s in 'Machine', 'User') {
        $drop = @($t.Plan | Where-Object { $_.Scope -eq $s -and $_.Entry } | ForEach-Object { $_.Entry })
        if ($drop.Count) {
            $kept = New-Object System.Collections.Generic.List[string]; $seen = @{}
            foreach ($e in ((Get-EnvRaw 'Path' $s) -split ';')) {
                if (-not $e.Trim()) { continue }
                $key = [Environment]::ExpandEnvironmentVariables($e).Trim().TrimEnd('\', '/').ToLower()
                if ($drop -contains $e -and ($seen.ContainsKey($key) -or (Get-StaleReason $e))) { Add-Action $r "Removed $s PATH entry '$e'"; continue }
                $seen[$key] = 1; $kept.Add($e)
            }
            Set-EnvRaw 'Path' $s ($kept -join ';')
        }
        foreach ($v in @($t.Plan | Where-Object { $_.Scope -eq $s -and $_.Var } | ForEach-Object { $_.Var })) {
            Set-EnvRaw $v $s $null; Add-Action $r "Deleted $s variable $v"
        }
    }
    $adds = @($t.Plan | Where-Object { $_.AddPath } | ForEach-Object { $_.AddPath })
    if ($adds.Count) {
        $cur = Get-EnvRaw 'Path' 'Machine'
        $front = ($adds -join ';')
        if ($cur) { $new = "$front;$cur" } else { $new = $front }
        Set-EnvRaw 'Path' 'Machine' $new
        foreach ($a in $adds) { Add-Action $r "Restored Windows folder '$a' in system PATH" }
    }
    Send-EnvChanged; Update-ProcessEnv
    Add-Action $r 'Old values saved in environment.backup.json'
}

# =====================================================================
#  CHECK 1 / 7 - Java
# =====================================================================
$script:JavaLatest = $null
function Get-JavaLatest {
    if ($script:JavaLatest) { return $script:JavaLatest }
    $o = @{ Update = 0; Url = $null; Error = $null }
    try {
        if ($TestMode) { $html = Get-Content (Join-Path $TestRoot 'java_manual.html') -Raw }
        else { $html = (Invoke-WebRequest -Uri $Cfg.JavaPageUrl -UseBasicParsing -TimeoutSec 30).Content }
        $m = [regex]::Match($html, 'Version\s+8\s+Update\s+(\d+)')
        if ($m.Success) { $o.Update = [int]$m.Groups[1].Value }
        foreach ($a in [regex]::Matches($html, '<a\b[^>]*>[\s\S]*?</a>', 'IgnoreCase')) {
            if ($a.Value -match '(?i)Windows\s+Offline' -and $a.Value -match '(?i)64-bit' -and $a.Value -match 'href="([^"]*AutoDL[^"]*)"') {
                $o.Url = [Net.WebUtility]::HtmlDecode($matches[1]); break
            }
        }
    } catch { Write-DscError $_ 'Caught exception'; $o.Error = $_.Exception.Message }
    $script:JavaLatest = $o; return $o
}
function Get-InstalledJava {
    $res = @()
    foreach ($e in Get-UninstallEntries) {
        if ($e.DisplayName -match '^Java\s*(\d+)\s*Update\s*(\d+)') {
            $res += [pscustomobject]@{ Name = $e.DisplayName; Major = [int]$matches[1]; Update = [int]$matches[2]; Is64 = ($e.DisplayName -match '64-bit'); Location = $e.InstallLocation; Uninstall = $e.UninstallString }
        }
    }
    return $res
}
function Test-JavaLatest {
    # Historical function name retained; this check deliberately does not fetch update metadata.
    $installed = @(Get-InstalledJava)
    $best = $installed | Where-Object { $_.Major -eq 8 -and $_.Is64 } | Sort-Object Update -Descending | Select-Object -First 1
    if (-not $best) {
        return @{ Pass = $false; Info = @('A suitable Java 8 64-bit installation was not found.'); Advice = 'Locate or install suitable Java 8 64-bit; updating working Java is optional.' }
    }
    return @{ Pass = $true; Value = "Java 8 Update $($best.Update) (64-bit) installed"; Info = @('Existing Java retained. Update checks are deferred to the optional indicator.') }
}
function Install-JavaLatest($r) {
    $lat = Get-JavaLatest
    if ($TestMode) { Invoke-MockJavaInstall $lat.Update; Add-Action $r "Installed Java 8 Update $($lat.Update) (64-bit) silently"; return }
    $done = $false
    if ($lat.Url) {
        $file = Join-Path $RunDir 'java-latest-x64.exe'
        Say "      Downloading Java 8 Update $($lat.Update) (64-bit) ..."
        try {
            Invoke-WebRequest -Uri $lat.Url -OutFile $file -UseBasicParsing -TimeoutSec 900
            $sig = Get-AuthenticodeSignature -FilePath $file
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Oracle') { throw "installer signature not valid ($($sig.Status))" }
            Get-Process -Name 'javaw', 'java', 'jp2launcher' -ErrorAction SilentlyContinue | Where-Object { $_.Path -notmatch '(?i)Signer' } | Out-Null
            $code = Invoke-Exe $file '/s REMOVEOUTOFDATEJRES=1 AUTO_UPDATE=0 WEB_ANALYTICS=0'
            Add-Action $r "Java installer finished (exit code $code)"
            $done = ($code -eq 0 -or $code -eq 3010)
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        } catch { Write-DscError $_ 'Caught exception'; Add-Action $r "Java download/install failed: $($_.Exception.Message)" }
    }
    if (-not $done -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Say '      Trying winget ...'
        $code = Invoke-Exe 'winget' 'install -e --id Oracle.JavaRuntimeEnvironment --silent --accept-package-agreements --accept-source-agreements'
        Add-Action $r "winget install Oracle.JavaRuntimeEnvironment (exit code $code)"
    }
    Update-ProcessEnv
}

function Find-JavaOnPath {
    foreach ($e in Get-EffectivePathEntries) {
        $d = [Environment]::ExpandEnvironmentVariables($e).Trim().Trim('"')
        foreach ($n in 'java.exe', 'java') {
            $f = Join-Path $d $n
            if (Test-Path -LiteralPath $f -PathType Leaf) {
                $it = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
                if ($it -and $it.LinkType -eq 'SymbolicLink') { $tg = @($it.Target)[0]; if ($tg -and -not [IO.Path]::IsPathRooted($tg)) { $tg = Join-Path $d $tg }; if ($tg -and -not (Test-Path -LiteralPath $tg)) { continue } }
                return $f
            }
        }
    }
    return $null
}
function Test-JavaWorks {
    $exe=Find-JavaOnPath
    if(-not $exe){return @{Pass=$false;Info=@('Java command not found on PATH.');Kind='nopath';Advice='Select PATH/Java repair if required.'}}
    $result=Invoke-JavaVersion $exe
    $version='';if($result.Text -match 'version\s+"([^"]+)"'){$version=$matches[1]}
    if($result.Code -ne 0 -or -not $version){return @{Pass=$false;Info=@("java -version failed (exit $($result.Code)): $($result.Text)");Kind='broken';Exe=$exe}}
    if($result.Text -match 'Picked up'){return @{Pass=$false;Info=@('Java options variables are still active.');Kind='options';Exe=$exe}}
    $information=@("java -version OK: $version ($exe)")
    $dss=Find-DssExe
    if($dss){
        $bundled=Get-ChildItem -LiteralPath (Split-Path -Parent $dss) -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^java(\.exe)?$' -and $_.DirectoryName -match '(?i)bin$'} | Select-Object -First 1
        if($bundled){$bundle=Invoke-JavaVersion $bundled.FullName;if($bundle.Code -ne 0){return @{Pass=$false;Info=@("Bundled Java failed: $($bundle.Text)");Kind='dssjre'}};$information+='Bundled Signer Java starts OK.'}
    }
    return @{Pass=$true;Info=$information;Value="java $version runs OK"}
}
function Repair-JavaWorks($r, $t) {
    switch ($t.Kind) {
        'nopath' {
            $best = Get-InstalledJava | Where-Object { $_.Major -eq 8 } | Sort-Object Update -Descending | Select-Object -First 1
            if (-not $best) { Install-JavaLatest $r; $best = Get-InstalledJava | Where-Object { $_.Major -eq 8 } | Sort-Object Update -Descending | Select-Object -First 1 }
            if ($best -and $best.Location) {
                $bin = Join-Path $best.Location 'bin'
                $mp = Get-EnvRaw 'Path' 'Machine'
                Set-EnvRaw 'Path' 'Machine' ("$bin;" + $mp); Add-Action $r "Added '$bin' to system PATH"
                Send-EnvChanged; Update-ProcessEnv
            }
        }
        'order' {
            $bin = Join-Path $t.Best.Location 'bin'
            $mp = Get-EnvRaw 'Path' 'Machine'
            Set-EnvRaw 'Path' 'Machine' ("$bin;" + $mp); Add-Action $r "Put latest Java '$bin' first in system PATH"
            Send-EnvChanged; Update-ProcessEnv
        }
        'options' { foreach ($v in $ToolOptionVars) { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }; Add-Action $r 'Cleared Java options variables' }
        'dssjre' { Repair-DssInstall $r -ForceRepair }
        default { Install-JavaLatest $r }
    }
}

# =====================================================================
#  CHECK 2 - port 55101
# =====================================================================
function Test-Port {
    $info = @(); $bad = @()
    $lis = @(Get-PortListeners)
    foreach ($p in $lis) {
        if (Test-IsDssProcess $p) { $info += "Port $($Cfg.Port) used by Digital Signer Service (PID $($p.Id)) - correct" }
        else { $bad += $p; $info += "Port $($Cfg.Port) occupied by '$($p.Name)' PID $($p.Id) $($p.Path) $(if($p.Service){"[service $($p.Service)]"})" }
    }
    $blocked = @(Get-ExcludedRanges | Where-Object { $Cfg.Port -ge $_.Start -and $Cfg.Port -le $_.End -and -not $_.Admin })
    foreach ($b in $blocked) { $info += "Port $($Cfg.Port) is inside Windows reserved range $($b.Start)-$($b.End) (Hyper-V/WinNAT)" }
    if (-not $lis.Count -and -not $blocked.Count) { $info += "Port $($Cfg.Port) is free" }
    $val = 'free'; if ($lis.Count -and -not $bad.Count) { $val = 'used by Digital Signer Service (correct)' }
    return @{ Pass = ($bad.Count -eq 0 -and $blocked.Count -eq 0); Info = $info; Value = $val; Bad = $bad; Blocked = $blocked; Advice = 'Uninstall/stop the other software that uses port 55101.' }
}
function Repair-Port($r, $t) {
    if ($Cfg.KillPortOwners) {
        foreach ($p in $t.Bad) {
            if ($p.Service -and -not $TestMode) {
                foreach ($s in ($p.Service -split ',')) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue; Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue; Add-Action $r "Stopped service '$s' and set it to Manual (it was holding port $($Cfg.Port))" }
            }
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Add-Action $r "Closed '$($p.Name)' (PID $($p.Id)) that was holding port $($Cfg.Port)"
        }
        Start-Sleep -Seconds 2
    } else { $r.Advice = 'Close the program using port 55101.' }
    if ($t.Blocked.Count) {
        if ($TestMode) { $s = Get-MockState; $s.excludedRanges = @($s.excludedRanges | Where-Object { -not ($Cfg.Port -ge $_.Start -and $Cfg.Port -le $_.End) }) + @([pscustomobject]@{ Start = $Cfg.Port; End = $Cfg.Port; Admin = $true }); Save-MockState $s }
        else {
            net stop winnat 2>&1 | Out-Null
            netsh int ipv4 add excludedportrange protocol=tcp startport=$($Cfg.Port) numberofports=1 store=persistent 2>&1 | Out-Null
            netsh int ipv6 add excludedportrange protocol=tcp startport=$($Cfg.Port) numberofports=1 store=persistent 2>&1 | Out-Null
            net start winnat 2>&1 | Out-Null
        }
        Add-Action $r "Reserved port $($Cfg.Port) for the Signer Service (restarted WinNAT)"
    }
}

# =====================================================================
#  CHECK 3 - DigitalSignerService 4.1.8 installed
# =====================================================================
function Test-DssInstall {
    $info = @(); $entries = @(Get-DssEntries); $ver = $Cfg.DssVersion
    $old  = @($entries | Where-Object { "$($_.DisplayVersion) $($_.DisplayName)" -notmatch [regex]::Escape($ver) })
    $good = @($entries | Where-Object { "$($_.DisplayVersion) $($_.DisplayName)" -match [regex]::Escape($ver) })
    $std = Get-DssStdExe; $exe = $null; $installed = $false; $where = ''
    if ($std) {
        # 1) the standard install path decides first
        $fv = Get-ExeVersion $std
        if ($fv -and $fv -ne $ver) { $info += "Found $std, but its version is $fv (not $ver)" }
        else { $installed = $true; $exe = $std; $where = Split-Path -Parent $std; $info += "Found $std$(if ($fv) { " (version $fv)" })" }
    } else {
        $info += "Not found: $($Cfg.DssExePaths[0])"
        # 2) otherwise: installed somewhere else? (registry entry + program files)
        $other = Find-DssExe
        if ($good.Count -and $other) { $info += "Found another installation at $other, but the required standard path is missing." }
        elseif ($good.Count) { $info += 'An installed entry exists but the program files are missing (broken install)' }
    }
    foreach ($o in $old) { $info += "Old/other version installed: $($o.DisplayName) (version $($o.DisplayVersion))" }
    $pass = ($installed -and $old.Count -eq 0)
    $val = ''; if ($pass) { $val = "version $ver  -  $where" }
    $notInst = (-not $installed)
    $pkgMissing = $false
    if (-not $pass) {
        $src = Find-DssPackageSource
        if ($src) { $info += "Installer ready: $($src.Text)" }
        elseif ($Cfg.PackageUrl) { $info += "Installer not on this PC - it can be downloaded at step 6 from $($Cfg.PackageUrl)" }
        elseif ($notInst) { $info += "Installer package $ver NOT selected - use 'Locate installer' (zip, msi or folder)"; $pkgMissing = $true }
    }
    $fv2 = ''
    if ($notInst -and $old.Count) { $fv2 = "NOT INSTALLED in this system (old $($old[0].DisplayVersion) found)" }
    elseif ($notInst) { $fv2 = 'NOT INSTALLED in this system' }
    elseif ($old.Count) { $fv2 = "old version $($old[0].DisplayVersion) must be removed" }
    if ($fv2) { if (Find-DssPackageSource) { $fv2 += '  |  installer ready' } elseif ($Cfg.PackageUrl) { $fv2 += '  |  installer can be prepared at step 6' } elseif ($notInst) { $fv2 += '  |  installer NOT selected' } }
    return @{ Pass = [bool]$pass; Info = $info; Value = $val; FailValue = $fv2; NotInstalled = $notInst; Old = $old; Good = $good; Exe = $exe; PkgMissing = $pkgMissing
              Advice = "Use 'Locate installer' to pick the DigitalSignerService $ver zip/msi/folder, then Fix again." }
}
function Repair-DssInstall($r, $t, [switch]$ForceRepair) {
    if (-not $t) { $t = Test-DssInstall }
    # Secure and validate the replacement BEFORE stopping or removing anything.
    $msi = Get-DssPackageMsi
    if (-not $msi -and $script:RequestPackage -and (-not $Cfg.AllowDssDownload -or -not $Cfg.PackageUrl)) { if (& $script:RequestPackage) { $msi = Get-DssPackageMsi } }
    if (-not $msi) { throw "No approved, validated $($Cfg.DssVersion) installer is ready. A declined or failed download leaves DSS unchanged; no stop or uninstall was started." }
    $valid = Test-PackageValid $msi
    if (-not $valid.Ok) { throw "Replacement installer rejected: $($valid.Text). DSS was not stopped or uninstalled." }
    Stop-Dss $r
    foreach ($o in $t.Old) {
        if ($o.UninstallString -notmatch '\{[0-9A-Fa-f\-]{36}\}') { throw "Cannot safely uninstall '$($o.DisplayName)'; use Control Panel, then retry." }
        $g = $matches[0]
        if ($TestMode) { Invoke-MockUninstall $o.DisplayName; $c = 0 }
        else { $c = Invoke-Exe 'msiexec.exe' "/x $g /qn /norestart" }
        if ($c -notin 0,3010,1641) { throw "DSS uninstall failed (exit $c). Installation was not continued." }
        Add-Action $r "Uninstalled old '$($o.DisplayName)' (exit $c)"
        if ($c -in 3010,1641) { $r.Advice = 'Restart Windows, then run the checks again before continuing installation.'; throw "DSS uninstall requires a restart (exit $c); further installation deferred." }
    }
    # The pre-uninstall snapshot may contain a path that no longer exists.
    $t = Test-DssInstall
    $log = Join-Path $RunDir 'dss-install.log'
    if (($t.Good.Count -or $t.Exe) -and ($ForceRepair -or -not $t.Exe)) {
        if ($TestMode) { Invoke-MockDssInstall; $c = 0 }
        else { $c = Invoke-Exe 'msiexec.exe' ("/fa `"$msi`" /qn /norestart /l*v `"$log`"") }
        if ($c -notin 0,3010,1641) { throw "DSS repair failed (exit $c). See dss-install.log." }
        Add-Action $r "Repaired program files (exit $c)"
    } elseif (-not $t.Exe) {
        if ($TestMode) { Invoke-MockDssInstall; $c = 0 }
        else { $c = Invoke-Exe 'msiexec.exe' ("/i `"$msi`" /qn /norestart ALLUSERS=1 /l*v `"$log`"") }
        if ($c -notin 0,3010,1641) { throw "DSS installation failed (exit $c). See dss-install.log." }
        Add-Action $r "Installed DigitalSignerService $($Cfg.DssVersion) (exit $c)"
    }
    if ($c -in 3010,1641) { $r.Advice = 'Installer requires a Windows restart. Restart, then run checks again.' }
}

# =====================================================================
#  CHECK 4 - service running as admin + isLive
# =====================================================================
function Get-CaCertBytes { return ,([Convert]::FromBase64String($Cfg.CaCertBase64)) }
function Test-CaTrusted {
    if ($TestMode) { return (Test-Path (Join-Path $TestRoot "trusted/$($Cfg.CaThumbprint).cer")) }
    return [bool](Get-ChildItem "Cert:\LocalMachine\Root\$($Cfg.CaThumbprint)" -ErrorAction SilentlyContinue)
}
function Install-CaCert($r) {
    [byte[]]$bytes = Get-CaCertBytes
    $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
    if ($c.Thumbprint -ne $Cfg.CaThumbprint) { Add-Action $r 'Embedded CA certificate mismatch - not installed'; return }
    if ($TestMode) { New-Item -ItemType Directory -Force (Join-Path $TestRoot 'trusted') | Out-Null; [IO.File]::WriteAllBytes((Join-Path $TestRoot "trusted/$($c.Thumbprint).cer"), $bytes) }
    else {
        $st = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', 'LocalMachine'
        $st.Open('ReadWrite'); $st.Add($c); $st.Close()
    }
    Add-Action $r "Installed eOffice root certificate ($($c.GetNameInfo('SimpleName', $false))) into Trusted Root store"
}
function Test-CertChainMock([byte[]]$raw) {
    # test-mode stand-in for Windows trust: chain must end in a cert we "installed"
    if (-not $raw) { return $false }
    $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$raw)
    $ch = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $ch.ChainPolicy.RevocationMode = 'NoCheck'
    $ch.ChainPolicy.TrustMode = 'CustomRootTrust'
    foreach ($f in (Get-ChildItem (Join-Path $TestRoot 'trusted') -Filter *.cer -ErrorAction SilentlyContinue)) {
        [void]$ch.ChainPolicy.CustomTrustStore.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $f.FullName))
    }
    if (-not $ch.Build($leaf)) { return $false }
    $san = ($leaf.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | ForEach-Object { $_.Format($false) }) -join ' '
    return ($san -match [regex]::Escape($Cfg.SignerHost) -or $leaf.Subject -match [regex]::Escape($Cfg.SignerHost))
}
function Invoke-IsLive {
    $result = [DssfHttpV3]::Get($Cfg.IsLiveUrl, $true, 8000, $true)
    if ($TestMode -and $result.Ok -and -not (Test-CertChainMock $result.CertRaw)) { $result.Ok=$false; $result.Kind='TrustFailure'; $result.Error='certificate not trusted (mock store)' }
    return $result
}
$script:NotSecure = $null
function Get-CertReason([byte[]]$raw, [string]$sslErr) {
    $why = "certificate not trusted ($sslErr)"
    try {
        if ($raw) {
            $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($raw)
            $now = Get-Date
            if ($now -gt $c.NotAfter) { return "the signer's certificate EXPIRED on $($c.NotAfter.ToString('dd-MMM-yyyy')) (issued by $($c.GetNameInfo('SimpleName', $true)))" }
            if ($now -lt $c.NotBefore) { return "the signer's certificate is valid only from $($c.NotBefore.ToString('dd-MMM-yyyy')) - check the PC date/time" }
            $why = "certificate issued by '$($c.GetNameInfo('SimpleName', $true))' is not trusted on this PC ($sslErr)"
        }
    } catch { Write-DscError $_ 'Caught exception';}
    return $why
}
function Test-DscLiveResponse([string]$Body) {
    return ($Body -match '(?i)\bsuccess\b' -and $Body -match ('(?<![\d.])' + [regex]::Escape($Cfg.DssVersion) + '(?![\d.])'))
}
function Open-StartupBrowser {
    Write-DscEvent 'Info' 'Startup browser requested' @{ Url = $Cfg.IsLiveUrl }
    if ($TestMode) { Log "OPEN DEFAULT $($Cfg.IsLiveUrl) [test]"; return $true }
    try {
        Start-Process -FilePath $Cfg.IsLiveUrl -ErrorAction Stop
        if($script:Ui -and -not $script:Ui.IsDisposed){$script:Ui.TopMost=$script:G.PinTop.Checked;$script:Ui.BringToFront();[void]$script:Ui.Activate()}
        return $true
    } catch {
        Write-DscError $_ 'Open startup browser'
        Say ('Could not open the default browser. Open this address manually: ' + $Cfg.IsLiveUrl) 'Yellow'
        return $false
    }
}
function Invoke-StartupSequence([switch]$OpenBrowser, [switch]$FullCheck) {
    $script:DiagnosticsOnly=$true; $script:ReviewApproved=$false
    if($script:UiProgress){& $script:UiProgress 'begin-checks' $null @($Defs).Count}
    # Read-only checks and package preparation first; selected repairs happen afterwards.
    Say ''; Say 'STEP 1 - Open isLive and check success for DigitalSignerService 4.1.8.' 'White'
    $opened = $false
    if ($OpenBrowser) { $opened = Open-StartupBrowser }
    Invoke-AllTests @(4)
    $ready = ($Results['4'].Status -in 'OK','FIXED','WARN')
    $script:DscSession['StartupReady'] = $ready
    $script:DscSession['StartupBrowserOpened'] = $opened
    Say ''; Say 'STEP 2 - Check the required Digital Signer Service installation path.' 'White'
    Invoke-AllTests @(3)
    Say ''; Say 'STEP 3 - Check PATH and environment cleanup (back up before selected repairs).' 'White'
    Invoke-AllTests @(5)
    Say ''; Say 'STEP 4 - Check Java execution, then installed Java. No update prompt.' 'White'
    Invoke-AllTests @(7)
    Invoke-AllTests @(1)
    Say ''; Say 'STEP 5 - Check port 55101 and its listener.' 'White'
    Invoke-AllTests @(2)
    Say ''; Say 'STEP 6 - Prepare and automatically validate an installer only if needed.' 'White'
    [void](Prepare-DscInstaller)
    Say ''; Say 'STEP 7 - Optional Java update indicator.' 'White'
    Update-JavaOffer
    Say ''; Say 'STEP 8 - Check the service process, hosts and browser settings.' 'White'
    try {
        $processes = @(Get-DssProcesses)
        Add-Detail $Results['4'] $(if ($processes.Count) { 'Signer process PIDs: ' + (($processes | ForEach-Object { $_.Id }) -join ', ') } else { 'Signer process is not running.' })
    } catch { Write-DscError $_ 'Service process diagnostic' }
    Invoke-AllTests @(6,8,9,10)
    return $ready
}

function Test-IsLive {
    $response = Invoke-IsLive
    if ($response.Ok -and (Test-DscLiveResponse $response.Body)) {
        $text = "success. DSC Signer Service version : $($Cfg.DssVersion)"
        if ($response.ExpiredAccepted) {
            return @{ Pass=$true; Warn=$true; Fixable=$false; ExpiredAccepted=$true; CertificateTrusted=$false; Value="$text - expired certificate alert ignored for signer only"
                Info=@($text,'Certificate expiry is a non-blocking warning for this signer endpoint. Use the browser exception action where offered. Other trust errors remain failures.') }
        }
        return @{ Pass=$true; CertificateTrusted=$true; Value=$text; Info=@($text,'HTTPS certificate trusted.') }
    }
    $kind='down';$information=@()
    if ($response.Ok) { $kind='version';$information += 'The expected success response for DSS 4.1.8 was not received.' }
    elseif ($response.Kind -match 'TrustFailure|SecureChannelFailure' -or ($response.SslErrors -and $response.SslErrors -ne 'None')) { $kind='cert';$information += Get-CertReason $response.CertRaw $response.SslErrors }
    else { $information += "isLive not reachable: $($response.Kind) $($response.Error)" }
    return @{Pass=$false;Kind=$kind;Info=$information;FailValue=$information[0];Procs=@();Advice='Continue the ordered diagnostics. Only a date-expiry-only alert for the signer endpoint is accepted; other certificate errors need review.'}
}
function Stop-Dss($r) {
    $ps = @(Get-DssProcesses)
    foreach ($p in $ps) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    if ($ps.Count -and $r) { Add-Action $r "Stopped running Signer Service (PID $(($ps | ForEach-Object { $_.Id }) -join ','))" }
    if ($ps.Count) { Start-Sleep -Seconds 2 }
}
function Start-DssAdmin($r) {
    $exe = Find-DssExe
    if (-not $exe) { Add-Action $r 'Signer Service program not found - cannot start'; return $false }
    $promptHelp='If Windows/Java asks to allow Digital Signer Service, verify the program path/publisher is the approved signer or its Java runtime, then choose Allow for your trusted organization network. Keep Public networks unselected unless IT requires them. Do not approve unrelated Java programs.'
    Add-Action $r $promptHelp
    if($script:UiStatus){& $script:UiStatus 'Starting signer: check for a Windows/Java Allow prompt behind this window.'}
    Update-Ui
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    Add-Action $r "Started '$exe' as Administrator"
    $deadline = (Get-Date).AddSeconds([int]$Cfg.StartWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        for($tick=0;$tick -lt 20;$tick++){Start-Sleep -Milliseconds 100;Update-Ui}
        $x = [DssfHttpV3]::Get($Cfg.IsLiveUrl, $false, 3000)
        if ($x.Ok) { return $true }
    }
    $r.Advice=$promptHelp
    Add-Action $r "Service did not answer within $($Cfg.StartWaitSeconds) s. Check for a pending Windows/Java prompt, then run the check again."
    return $false
}
function Set-DssRunAsAdmin($r) {
    $exe = Find-DssExe; if (-not $exe) { return }
    if ($TestMode) {
        $s = Get-MockState
        $s | Add-Member -NotePropertyName runAsAdmin -NotePropertyValue $exe -Force
        if ($Cfg.CreateAutoStartTask) { $s | Add-Member -NotePropertyName autostartTask -NotePropertyValue $exe -Force }
        Save-MockState $s; Add-Action $r 'Set Signer Service to always "Run as administrator" + auto-start at logon'
    }
    else {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $k -Name $exe -ErrorAction SilentlyContinue).$exe
        if ($cur -notmatch 'RUNASADMIN') { New-ItemProperty -Path $k -Name $exe -Value '~ RUNASADMIN' -PropertyType String -Force | Out-Null; Add-Action $r 'Set Signer Service to always "Run as administrator"' }
        if ($Cfg.CreateAutoStartTask) {
            try {
                $user = (Get-CimInstance Win32_ComputerSystem).UserName; if (-not $user) { $user = "$env:USERDOMAIN\$env:USERNAME" }
                $tn = 'DSC Signer Service (Run as Admin)'
                if (-not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue)) {
                    $a = New-ScheduledTaskAction -Execute $exe -WorkingDirectory (Split-Path -Parent $exe)
                    $tr = New-ScheduledTaskTrigger -AtLogOn -User $user
                    $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
                    $st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
                    Register-ScheduledTask -TaskName $tn -Action $a -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null
                    Add-Action $r "Auto-start at logon (as admin) created for $user"
                }
            } catch { Write-DscError $_ 'Caught exception'; Log "task: $_" }
        }
    }
}
function Repair-IsLive($r, $t) {
    if (-not (Test-CaTrusted)) { Install-CaCert $r }
    Set-DssRunAsAdmin $r
    $chk = Invoke-IsLive
    if ($chk.Ok -and (Test-DscLiveResponse $chk.Body)) { return }
    if ($t.Kind -eq 'version') { Repair-DssInstall $r -ForceRepair }
    if (@(Get-DssProcesses).Count) { Stop-Dss $r }
    # port must be free for the service itself
    $pt = Test-Port; if (-not $pt.Pass) { Repair-Port $r $pt }
    [void](Start-DssAdmin $r)
}

# =====================================================================
#  CHECKS 8-10 - isLive in Chrome / Edge / Firefox
# =====================================================================
function Get-LnaValues([string]$Browser) {
    if ($TestMode) { $s = Get-MockState; return @($s.lna.$Browser) }
    $k = if ($Browser -eq 'Edge') { 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\LocalNetworkAccessAllowedForUrls' } else { 'HKLM:\SOFTWARE\Policies\Google\Chrome\LocalNetworkAccessAllowedForUrls' }
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if (-not $p) { return @() }
    return @($p.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { "$($_.Value)" })
}
function Get-ProxyInfo {
    if ($TestMode) { return (Get-MockState).proxy }
    $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Enable = [int]$p.ProxyEnable; Server = "$($p.ProxyServer)"; Override = "$($p.ProxyOverride)"; Pac = "$($p.AutoConfigURL)" }
}
function Set-ProxyBypass($r) {
    $px = Get-ProxyInfo
    if ($px.Enable -eq 1 -and $px.Override -notmatch [regex]::Escape($Cfg.SignerHost)) {
        $new = (@($px.Override -split ';' | Where-Object { $_ }) + @($Cfg.SignerHost, '127.0.0.1', 'localhost') | Select-Object -Unique) -join ';'
        if ($TestMode) { $s = Get-MockState; $s.proxy.Override = $new; Save-MockState $s }
        else { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyOverride -Value $new }
        Add-Action $r "Added $($Cfg.SignerHost) to the Windows proxy bypass list"
    }
}
function Set-LnaPolicy($r, [string]$b) {
    $vals = @(Get-LnaValues $b)
    foreach ($o in $Cfg.LnaAllowedOrigins) {
        if ($vals -contains $o) { continue }
        if ($TestMode) { $s = Get-MockState; $s.lna.$b = @($s.lna.$b) + $o; Save-MockState $s }
        else {
            $k = if ($b -eq 'Edge') { 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\LocalNetworkAccessAllowedForUrls' } else { 'HKLM:\SOFTWARE\Policies\Google\Chrome\LocalNetworkAccessAllowedForUrls' }
            if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
            $n = 1; $names = @((Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { [int]$_.Name })
            while ($names -contains $n) { $n++ }
            New-ItemProperty -Path $k -Name "$n" -Value $o -PropertyType String -Force | Out-Null
        }
        $vals += $o
        Add-Action $r "$b policy: eOffice pages ($o) allowed to reach the local signer - restart $b"
    }
}

function Find-Browser([string]$Name) {
    if ($TestMode) {
        $b = @((Get-MockState).browsers) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($b) { return [pscustomobject]@{ Name = $Name; Exe = $b.Exe; Version = $b.Version } }
        return $null
    }
    $exeName = @{ Chrome = 'chrome.exe'; Edge = 'msedge.exe'; Firefox = 'firefox.exe' }[$Name]
    $cands = @()
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths') {
        $v = (Get-ItemProperty "$root\$exeName" -ErrorAction SilentlyContinue).'(default)'
        if ($v) { $cands += $v.Trim('"') }
    }
    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $la = $env:LOCALAPPDATA
    switch ($Name) {
        'Chrome'  { $cands += "$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$la\Google\Chrome\Application\chrome.exe" }
        'Edge'    { $cands += "$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe", "$la\Microsoft\Edge\Application\msedge.exe" }
        'Firefox' {
            $cands += "$pf\Mozilla Firefox\firefox.exe", "$pf86\Mozilla Firefox\firefox.exe", "$la\Mozilla Firefox\firefox.exe"
            foreach ($mk in 'HKLM:\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox', 'HKCU:\SOFTWARE\Mozilla\Mozilla Firefox') {
                try { $cv = (Get-ItemProperty $mk -ErrorAction Stop).CurrentVersion; if ($cv) { $px = (Get-ItemProperty "$mk\$cv\Main" -ErrorAction Stop).PathToExe; if ($px) { $cands += $px } } } catch { Write-DscError $_ 'Caught exception';}
            }
        }
    }
    $cands = @($cands | Where-Object { $_ })
    foreach ($c in $cands) {
        try { if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return [pscustomobject]@{ Name = $Name; Exe = $c; Version = "$((Get-Item -LiteralPath $c).VersionInfo.ProductVersion)" } } } catch { Write-DscError $_ 'Caught exception';}
    }
    return $null
}

# Real browser test: Chrome / Edge opened invisibly (own temporary profile) on the isLive URL
function Invoke-HeadlessCheck($b) {
    $profile=Join-Path $RunDir ('browser-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($profile)
    $arguments=@('--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-extensions',"--user-data-dir=`"$profile`"",'--virtual-time-budget=6000','--dump-dom',$Cfg.IsLiveUrl)
    $result=@{Html='';Err='';ExitCode=$null;Inconclusive=$false}
    $process=$null
    try {
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=$b.Exe;$info.Arguments=$arguments -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$info
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not (Wait-Proc $process 20000)){try{$process.Kill()}catch{};$result.Err='Browser probe timed out.';$result.Inconclusive=$true}
        elseif([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),3000)){
            $result.Html=$stdout.Result;$result.Err=$stderr.Result;$result.ExitCode=$process.ExitCode
        }else{$result.Err='Browser output did not close.';$result.Inconclusive=$true}
        if(-not $result.Html -and -not $result.Err){$result.Inconclusive=$true}
    }catch{Write-DscError $_ 'Browser diagnostic';$result.Err=$_.Exception.Message;$result.Inconclusive=$true}
    finally{
        if($process){$process.Dispose()}
        $parent=[IO.Path]::GetFullPath($RunDir).TrimEnd('\')+'\'
        $target=[IO.Path]::GetFullPath($profile)
        if($target.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)) {Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue}
    }
    Log "HEADLESS $($b.Name): exit=$($result.ExitCode); chars=$($result.Html.Length); inconclusive=$($result.Inconclusive); $($result.Err)"
    return $result
}

function Test-NotSecure {
    if ($null -eq $script:NotSecureChecked) {
        $s1 = [DssfHttpV3]::Get($Cfg.IsLiveUrl, (-not $TestMode), 5000)
        $script:NotSecureChecked = $true
        if ($TestMode) { $script:NotSecureFlag = ($s1.Ok -and -not (Test-CertChainMock $s1.CertRaw)) } else { $script:NotSecureFlag = (-not $s1.Ok -and ([DssfHttpV3]::Get($Cfg.IsLiveUrl, $false, 5000)).Ok) }
    }
    return $script:NotSecureFlag
}
function Test-ChromiumBrowser([string]$Name) {
    $browser=Find-Browser $Name
    if(-not $browser){return @{Pass=$true;NA=$true;Value='not installed';Info=@("$Name not installed.")}}
    $probe=Invoke-HeadlessCheck $browser
    $combined="$($probe.Html) $($probe.Err)"
    $code='';if($combined -match '(ERR_[A-Z_]+)'){$code=$matches[1]}
    $live=$ByNo[4].Last
    if($code -eq 'ERR_CERT_DATE_INVALID' -and $live.Pass -and $live.ExpiredAccepted){
        return @{Pass=$true;Warn=$true;Fixable=$false;Browser=$browser;Kind=@();Value="$Name - accepted signer expiry warning";Info=@('isLive success is confirmed. The fresh browser profile requires the approved signer expiry exception.');Advice='Use Browser exception help if the browser offers Advanced/Proceed.'}
    }
    if($probe.Inconclusive -or (-not $probe.Html -and -not $code)){
        return @{Pass=$true;Warn=$true;Fixable=$false;Browser=$browser;Kind=@();BrowserVerified=$false;Value="$Name - browser probe not verified";Info=@('The automated browser probe returned no usable page. This does not establish a browser or Signer Service failure.',$probe.Err);Advice='Inspect the isLive page in the already-open browser. No automatic repair is proposed for an inconclusive probe.'}
    }
    $ok=(Test-DscLiveResponse $probe.Html) -and $code -notmatch '^ERR_CERT_|^ERR_SSL_'
    if(-not $ok){
        $kind='service';if($code -match 'CERT|SSL'){$kind='cert'}elseif($code -match 'PROXY|TUNNEL'){$kind='proxy'}elseif($code -match 'NAME_NOT_RESOLVED|ADDRESS'){$kind='hosts'}
        return @{Pass=$false;Browser=$browser;Kind=@($kind);Value="$Name - browser check failed $code";Info=@("Browser did not return expected isLive content: $code",$probe.Err);Advice='Review this browser-specific issue; see the independent isLive result.'}
    }
    $allowed=@(Get-LnaValues $Name);$missing=@($Cfg.LnaAllowedOrigins | Where-Object {$allowed -notcontains $_})
    if($missing.Count){return @{Pass=$true;Warn=$true;Fixable=$true;Browser=$browser;Kind=@('lna');BrowserVerified=$true;Value="$Name - isLive success; eOffice access policy needs review";Info=@('Browser isLive success verified. eOffice Local Network Access policy is not configured.')}}
    return @{Pass=$true;Browser=$browser;Kind=@();BrowserVerified=$true;Value="$Name - isLive success";Info=@('Browser page verified with normal certificate validation.')}
}
function Repair-ChromiumBrowser($r, $t, [string]$Name) {
    foreach ($k in $t.Kind) {
        switch ($k) {
            'cert'    { if (-not (Test-CaTrusted)) { Install-CaCert $r } else { Add-Action $r 'eOffice root certificate already trusted - restarting the Signer Service'; Stop-Dss $r; [void](Start-DssAdmin $r) } }
            'proxy'   { Set-ProxyBypass $r }
            'hosts'   { Repair-Hosts $r }
            'service' { $it = Test-IsLive; if (-not $it.Pass) { Repair-IsLive $r $it } }
            'lna'     { Set-LnaPolicy $r $Name }
        }
    }
}

# Firefox keeps its own certificate store and proxy settings
function Get-FirefoxPrefsFiles {
    if ($TestMode) { $d = Join-Path $TestRoot 'ffprofiles' } else { $d = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles' }
    return @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'prefs.js' } | Where-Object { Test-Path -LiteralPath $_ })
}
function Get-FfPref([string]$text, [string]$name) {
    $m = [regex]::Match($text, 'user_pref\("' + [regex]::Escape($name) + '",\s*("?)([^"\)]*)\1\);')
    if ($m.Success) { return $m.Groups[2].Value }; return $null
}
function Get-FfRootsPolicy {
    if ($TestMode) { return [int](Get-MockState).ffPolicyRoots }
    return [int](Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\Certificates' -ErrorAction SilentlyContinue).ImportEnterpriseRoots
}
function Test-Firefox {
    $b = Find-Browser 'Firefox'
    if (-not $b) { return @{ Pass = $true; NA = $true; Value = 'not installed'; Info = @('Firefox is not installed') } }
    $info = @(); $kind = @()
    $major = 0; if ("$($b.Version)" -match '^(\d+)') { $major = [int]$matches[1] }
    $policy = (Get-FfRootsPolicy) -eq 1
    $prefFalse = $false; $prefTrue = $false; $manualNoBypass = @()
    foreach ($f in Get-FirefoxPrefsFiles) {
        $tx = Get-Content -LiteralPath $f -Raw
        $er = Get-FfPref $tx 'security.enterprise_roots.enabled'
        if ($er -eq 'false') { $prefFalse = $true } elseif ($er -eq 'true') { $prefTrue = $true }
        if ((Get-FfPref $tx 'network.proxy.type') -eq '1') {
            $np = Get-FfPref $tx 'network.proxy.no_proxies_on'
            if ("$np" -notmatch [regex]::Escape($Cfg.SignerHost)) { $manualNoBypass += $f }
        }
    }
    $rootsOk = $policy -or $prefTrue -or ($major -ge 120 -and -not $prefFalse)
    if (-not $rootsOk) { $info += "Firefox $($b.Version) does not use the Windows certificate store (eOffice certificate not trusted)"; $kind += 'roots' }
    if (-not (Test-CaTrusted)) { $info += 'eOffice root certificate missing from Windows store'; $kind += 'ca' }
    if ($manualNoBypass.Count) { $info += "Firefox has a manual proxy without '$($Cfg.SignerHost)' in 'No proxy for'"; $kind += 'proxy' }
    $live = Test-IsLive
    if (-not $live.Pass) { $info += 'Signer Service isLive is not answering correctly'; $kind += 'service' }
    if (-not $kind.Count) { $info += "Firefox $($b.Version): certificate trust and proxy settings OK, isLive answering" }
    $val = ''; if (-not $kind.Count) { $val = "Firefox $($b.Version) - settings OK" }
    return @{ Pass = ($kind.Count -eq 0); Warn = [bool]$live.ExpiredAccepted; Fixable = $false; Info = $info; Kind = $kind; Browser = $b; Value = $val; Prefs = $manualNoBypass
              Advice = 'In Firefox: Settings > Privacy & Security > Certificates > View Certificates > Authorities > Import eOfficeCA2022.cer, then open the isLive link.' }
}
function Repair-Firefox($r, $t) {
    foreach ($k in $t.Kind) {
        switch ($k) {
            'ca'    { Install-CaCert $r }
            'roots' {
                if ($TestMode) { $s = Get-MockState; $s | Add-Member -NotePropertyName ffPolicyRoots -NotePropertyValue 1 -Force; Save-MockState $s }
                else {
                    $kp = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\Certificates'
                    if (-not (Test-Path $kp)) { New-Item -Path $kp -Force | Out-Null }
                    New-ItemProperty -Path $kp -Name ImportEnterpriseRoots -Value 1 -PropertyType DWord -Force | Out-Null
                }
                Add-Action $r 'Firefox policy: trust certificates in the Windows store (restart Firefox)'
            }
            'proxy' {
                foreach ($f in $t.Prefs) {
                    $tx = Get-Content -LiteralPath $f -Raw
                    $np = "$(Get-FfPref $tx 'network.proxy.no_proxies_on')"
                    $new = (@($np -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) + $Cfg.SignerHost | Select-Object -Unique) -join ', '
                    $uj = Join-Path (Split-Path -Parent $f) 'user.js'
                    Add-Content -LiteralPath $uj -Value "user_pref(`"network.proxy.no_proxies_on`", `"$new`");"
                    if ($TestMode) { $tx2 = [regex]::Replace($tx, 'user_pref\("network\.proxy\.no_proxies_on",[^\n]*\n?', ''); Set-Content -LiteralPath $f -Value ($tx2 + "user_pref(`"network.proxy.no_proxies_on`", `"$new`");`n") -NoNewline }
                    Add-Action $r "Firefox: added $($Cfg.SignerHost) to 'No proxy for' (applies when Firefox restarts)"
                }
            }
            'service' { $it = Test-IsLive; if (-not $it.Pass) { Repair-IsLive $r $it } }
        }
    }
}

# opens isLive in every browser that is installed (Chrome / Edge / Firefox) - a missing browser is simply skipped
function Open-InBrowsers {
    $res = @{ Opened = @(); Missing = @(); Failed = @() }
    foreach ($n in 'Chrome', 'Edge', 'Firefox') {
        $b = $null; try { $b = Find-Browser $n } catch { Write-DscError $_ 'Caught exception'; Log "find $n failed: $($_.Exception.Message)" }
        if (-not $b) { $res.Missing += $n; continue }
        Say "      Opening isLive in $n ..." 'Cyan'
        if ($TestMode) { Log "OPEN $($b.Exe) $($Cfg.IsLiveUrl)"; $res.Opened += $n; continue }
        try {
            # open as the normal (non-admin) user; fall back to a direct start
            $ok = $false
            try {
                $p = Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" -ArgumentList ('/trustlevel:0x20000 "\"' + $b.Exe + '\" ' + $Cfg.IsLiveUrl + '"') -PassThru -WindowStyle Hidden -ErrorAction Stop
                if ($p.WaitForExit(10000) -and $p.ExitCode -eq 0) { $ok = $true }
            } catch { Write-DscError $_ 'Caught exception';}
            if (-not $ok) { Start-Process -FilePath $b.Exe -ArgumentList $Cfg.IsLiveUrl -ErrorAction Stop }
            $res.Opened += $n
        } catch { Write-DscError $_ 'Caught exception'; Log "open in $n failed: $($_.Exception.Message)"; $res.Failed += $n }
    }
    if (-not $res.Opened.Count) {
        # none of the three found / started: use the PC's default browser
        try { if (-not $TestMode) { Start-Process $Cfg.IsLiveUrl -ErrorAction Stop }; $res.Opened += 'default browser' } catch { Write-DscError $_ 'Caught exception'; Log "default browser failed: $($_.Exception.Message)" }
    }
    $msg = "Opened in: $(if ($res.Opened.Count) { $res.Opened -join ', ' } else { 'nothing' })"
    if ($res.Missing.Count) { $msg += "   |   not installed (skipped): $($res.Missing -join ', ')" }
    if ($res.Failed.Count) { $msg += "   |   could not start: $($res.Failed -join ', ')" }
    Say "      $msg" 'Cyan'
    $res.Text = $msg
    return $res
}

# =====================================================================
#  Test-mode simulators (never used on a real PC)
# =====================================================================
function Invoke-MockJavaInstall([int]$upd) {
    $s = Get-MockState
    $dir = Join-Path $TestRoot "fs/Program Files/Java/jre1.8.0_$upd"
    New-Item -ItemType Directory -Force (Join-Path $dir 'bin') | Out-Null
    $js = Join-Path $dir 'bin/java'
    Set-Content $js "#!/bin/sh`necho 'java version `"1.8.0_$upd`"' 1>&2`necho 'Java(TM) SE Runtime Environment (build 1.8.0_$upd-b07)' 1>&2`nexit 0"
    chmod +x $js
    $jp = Join-Path $TestRoot 'fs/Common Files/Oracle/Java/javapath'
    New-Item -ItemType Directory -Force $jp | Out-Null
    Remove-Item (Join-Path $jp 'java') -Force -ErrorAction SilentlyContinue
    New-Item -ItemType SymbolicLink -Path (Join-Path $jp 'java') -Target $js | Out-Null
    $s.apps = @($s.apps | Where-Object { $_.DisplayName -notmatch '^Java\s*8' }) + @([pscustomobject]@{ DisplayName = "Java 8 Update $upd (64-bit)"; DisplayVersion = "8.0.$upd"; InstallLocation = $dir; UninstallString = 'MsiExec.exe /X{26A24AE4-039D-4CA4-87B4-2F64180TEST}' })
    if (($s.env.Machine.Path -split ';') -notcontains $jp) { $s.env.Machine.Path = "$jp;" + $s.env.Machine.Path }
    Save-MockState $s
}
function Invoke-MockUninstall([string]$name) { $s = Get-MockState; $s.apps = @($s.apps | Where-Object { $_.DisplayName -ne $name }); Save-MockState $s }
function Invoke-MockDssInstall {
    $s = Get-MockState
    $dir = Join-Path $TestRoot 'fs/Program Files/Digital Signer Service/4.1.8'
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item (Join-Path $TestRoot 'DigitalSignerService') (Join-Path $dir 'Digital Signer Service') -Force
    chmod +x (Join-Path $dir 'Digital Signer Service')
    if (-not ($s.apps | Where-Object { $_.DisplayName -match 'Signer Service' })) {
        $s.apps = @($s.apps) + @([pscustomobject]@{ DisplayName = 'Digital Signer Service 4.1.8'; DisplayVersion = '4.1.8'; InstallLocation = $dir; UninstallString = 'MsiExec.exe /X{D1F4F61A-77B9-47DC-832F-B2F7CDAC969F}' })
    }
    Save-MockState $s
}

# =====================================================================
#  HTML report
# =====================================================================
function ConvertTo-Html5([string]$s) { return [Net.WebUtility]::HtmlEncode($s) }
function Write-Report {
    $file = Join-Path $RunDir 'DSC-Signer-Report.html'
    $all = @($Results.Values)
    $failed = @($all | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'SKIP' }).Count
    $fixed = @($all | Where-Object { $_.Status -eq 'FIXED' }).Count
    $warns = @($all | Where-Object { $_.Status -eq 'WARN' }).Count
    $state=Get-DscOverallState
    $findings=Get-DscFindingsSummary
    $banner="Signer service: " + $state.Title; $bsub=$findings.Text
    $bcls=$(if($state.Working){'ok'}elseif(-not $state.Verified){'wn'}else{'bad'})
    $cards = ''; $rows = ''
    foreach ($r in $all) {
        switch ($r.Status) { 'OK' { $pill = 'TEST OK'; $c = 'ok' } 'FIXED' { $pill = 'FIXED &#183; TEST OK'; $c = 'fixed' } 'WARN' { $pill = 'TEST OK &#183; NOTE'; $c = 'warn' } 'NA' { $pill = 'NOT INSTALLED'; $c = 'na' } 'NOTRUN' { $pill = 'NOT NEEDED'; $c = 'na' } 'PENDING' { $pill = 'NOT TESTED'; $c = 'na' } 'SKIP' { $pill = 'NOT FIXED (skipped)'; $c = 'bad' } default { $pill = 'FAILED'; $c = 'bad' } }
        $det = ($r.Detail | ForEach-Object { "<li>$(ConvertTo-Html5 $_)</li>" }) -join ''
        $act = ''; if ($r.Actions.Count) { $act = '<div class="lbl">What the tool did</div><ul class="act">' + (($r.Actions | ForEach-Object { "<li>$(ConvertTo-Html5 $_)</li>" }) -join '') + '</ul>' }
        $adv = ''; if ($r.Status -eq 'FAIL' -and $r.Advice) { $adv = "<div class='adv'><b>Do this:</b> $(ConvertTo-Html5 $r.Advice)</div>" }
        $rows += "<tr><td>$($r.DisplayNo)</td><td>$(ConvertTo-Html5 $r.Title)</td><td class='s-$(($r.Before).ToLower())'>$(Get-Label $r.Before)</td><td class='s-$(($r.Status).ToLower())'>$(Get-Label $r.Status)</td><td>$(ConvertTo-Html5 $r.Value)</td></tr>"
        $cards += "<section class='card $c'><div class='head'><span class='no'>$($r.No)</span><h2>$(ConvertTo-Html5 $r.Title)</h2><span class='pill'>$pill</span></div><ul class='det'>$det</ul>$act$adv</section>`n"
    }
    $machine = ConvertTo-Html5 ("{0}  |  {1}  |  {2}" -f [Environment]::MachineName, [Environment]::UserName, (Get-Date -Format 'dd-MMM-yyyy HH:mm'))
    $url = $Cfg.IsLiveUrl; $ver = $Cfg.DssVersion
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DSC Signer Check | Build 2026.10.27.3</title>
<style>
:root{--bg:#f4f6f9;--card:#fff;--ink:#16202c;--mute:#5d6b7a;--ok:#13804a;--okbg:#e6f6ed;--fx:#0b6aa6;--fxbg:#e5f1fa;--wn:#9a6400;--wnbg:#fdf3e1;--bd:#c62828;--bdbg:#fdeaea;--line:#e2e7ee}
@media (prefers-color-scheme:dark){:root{--bg:#0f141a;--card:#18202a;--ink:#e8edf3;--mute:#9aa8b6;--okbg:#123222;--fxbg:#10283a;--wnbg:#33280f;--bdbg:#3a1616;--line:#26313d;--ok:#4cc38a;--fx:#5fb3ec;--wn:#e3b04b;--bd:#ff6b6b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
.wrap{max-width:920px;margin:0 auto;padding:24px 16px 48px}
header{display:flex;justify-content:space-between;align-items:flex-end;gap:12px;flex-wrap:wrap;margin-bottom:16px}
header h1{font-size:20px;margin:0}header .m{color:var(--mute);font-size:13px}
.banner{border-radius:14px;padding:22px 24px;margin-bottom:18px;display:flex;gap:18px;align-items:center}
.banner.ok{background:var(--okbg);color:var(--ok)}.banner.wn{background:var(--wnbg);color:var(--wn)}.banner.bad{background:var(--bdbg);color:var(--bd)}
.banner .big{font-size:28px;font-weight:800;letter-spacing:.5px}.banner .sub{color:var(--ink);opacity:.85}
.mark{font-size:40px;line-height:1}
.live{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 20px;margin-bottom:18px}
.live .row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.live code{font-size:13px;word-break:break-all}
button{font:inherit;border:0;border-radius:8px;padding:8px 14px;background:var(--fx);color:#fff;cursor:pointer}
.card{background:var(--card);border:1px solid var(--line);border-left:6px solid var(--line);border-radius:12px;padding:14px 18px;margin-bottom:12px}
.card.na{opacity:.7}table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden;margin-bottom:18px;font-size:14px}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--mute);font-size:12px;text-transform:uppercase}
.s-ok,.s-fixed{color:var(--ok);font-weight:700}.s-warn{color:var(--wn);font-weight:700}.s-fail,.s-skip{color:var(--bd);font-weight:700}.s-na,.s-notrun,.s-pending{color:var(--mute)}
.tw{overflow-x:auto}
.card.ok{border-left-color:var(--ok)}.card.fixed{border-left-color:var(--fx)}.card.warn{border-left-color:var(--wn)}.card.bad{border-left-color:var(--bd)}
.head{display:flex;align-items:center;gap:12px}.head h2{font-size:16px;margin:0;flex:1}
.no{width:28px;height:28px;border-radius:50%;background:var(--bg);display:grid;place-items:center;font-weight:700;font-size:13px}
.pill{font-size:12px;font-weight:800;padding:4px 10px;border-radius:999px;white-space:nowrap}
.ok .pill{background:var(--okbg);color:var(--ok)}.fixed .pill{background:var(--fxbg);color:var(--fx)}.warn .pill{background:var(--wnbg);color:var(--wn)}.bad .pill{background:var(--bdbg);color:var(--bd)}
ul{margin:8px 0 0;padding-left:20px}li{margin:2px 0}.det{color:var(--mute)}.lbl{font-size:12px;font-weight:700;text-transform:uppercase;color:var(--mute);margin-top:10px}
.act li{color:var(--fx)}.adv{margin-top:10px;background:var(--bdbg);border-radius:8px;padding:8px 12px}
footer{color:var(--mute);font-size:13px;margin-top:20px}
</style></head><body><div class="wrap">
<header><h1>Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )</h1><div class="m">$($Cfg.EditionName) | Build 2026.10.27.3<br>$machine</div></header>
<div class="banner $bcls"><div class="mark">$(if($failed -eq 0 -and -not $warns){'&#10004;'}else{'&#9888;'})</div><div><div class="big">$banner</div><div class="sub">$bsub</div></div></div>
<div class="live"><div class="row"><b>Live browser test:</b><span id="lv">checking&#8230;</span><button onclick="chk()">Test again</button></div>
<div class="m" style="margin-top:6px"><code>$url</code> &#8212; <a href="$url" target="_blank">open in new tab</a></div></div>
<div class="tw"><table><tr><th>#</th><th>Check</th><th>First test</th><th>Now</th><th>State / version</th></tr>$rows</table></div>
$cards
<footer>Log, backups and this report: $(ConvertTo-Html5 $RunDir)<br>Re-run any time by running <b>install.ps1</b> again. Firefox users: Settings &#8250; Privacy &amp; Security &#8250; Certificates &#8250; enable "Allow Firefox to trust third-party root certificates".</footer>
</div><script>
function chk(){var e=document.getElementById('lv');e.textContent='checking\u2026';e.style.color='';
var x=new XMLHttpRequest();try{x.open('GET','$url?t='+Date.now(),true);}catch(err){e.textContent='Browser blocked the request';return;}
x.timeout=8000;x.onload=function(){var ok=x.status==200&&/\bsuccess\b/i.test(x.responseText)&&x.responseText.indexOf('$ver')>-1;e.textContent=(ok?'TEST OK \u2014 ':'Unexpected answer \u2014 ')+x.responseText.substring(0,120);e.style.color=ok?'var(--ok)':'var(--bd)';};
x.onerror=x.ontimeout=function(){e.innerHTML='This page could not test it directly (browsers often block local checks from a saved file). Click <a href="$url" target="_blank">open in new tab</a> &#8212; it must show <b>$ver</b>. A certificate warning there means: run the tool again.';e.style.color='var(--wn)';};x.send();}
chk();</script></body></html>
"@
    [IO.File]::WriteAllText($file, $html, (New-Object Text.UTF8Encoding $false))
    return $file
}

# =====================================================================
#  MAIN
# =====================================================================
Log "Tool: $SelfPath   RunDir: $RunDir   Mode: $Mode"

function Update-JavaOffer {
    $script:JavaUpdateOffer = @{ Available = $false; Current = 0; Latest = 0; Text = 'Java update not required.' }
    if ($script:UiJavaOffer) { & $script:UiJavaOffer }
    if ($Results['1'].Status -notin 'OK','FIXED' -or $Results['7'].Status -notin 'OK','FIXED') { return }
    $best = Get-InstalledJava | Where-Object { $_.Major -eq 8 -and $_.Is64 } | Sort-Object Update -Descending | Select-Object -First 1
    if (-not $best) { return }
    $latest = Get-JavaLatest
    $script:JavaUpdateOffer.Current = $best.Update
    $script:JavaUpdateOffer.Latest = $latest.Update
    if ($latest.Update -gt $best.Update) {
        $script:JavaUpdateOffer.Available = $true
        $script:JavaUpdateOffer.Text = "Optional Java update: $($best.Update) -> $($latest.Update). Working Java is kept unless you choose Update Java."
        Say $script:JavaUpdateOffer.Text 'Yellow'
    } elseif (-not $latest.Update) { $script:JavaUpdateOffer.Text = 'Java update availability could not be checked. Existing working Java is kept.' }
    Write-DscEvent 'Info' 'Optional Java update checked' $script:JavaUpdateOffer
    if ($script:UiJavaOffer) { & $script:UiJavaOffer }
}

function Invoke-OptionalJavaUpdate([switch]$Confirmed) {
    if (-not $Confirmed -or -not $script:JavaUpdateOffer.Available) { return $false }
    if (-not $IsAdmin) { Say 'Open an Administrator PowerShell session, run this tool again and choose Update Java.' 'Yellow'; return $false }
    Write-DscEvent 'Info' 'Optional Java update selected' @{}
    Install-JavaLatest $ByNo[1].R
    $script:JavaLatest = $null
    return $true
}

function Prepare-DscInstaller {
    if($script:DiagnosticsOnly){
        if($Results['3'].Status -in 'FAIL','SKIP'){Add-Detail $Results['3'] 'Installer preparation is deferred until Review / Pending fixes.'}
        return $false
    }
    if ($Results['3'].Status -notin 'FAIL','SKIP') { return $false }
    if ($CheckOnly) { Add-Detail $Results['3'] 'Installer download/preparation deferred in check-only mode.'; return $false }
    try {
        $source = Find-DssPackageSource
        if (-not $source -and (-not $Cfg.AllowDssDownload -or -not $Cfg.PackageUrl)) {
            Add-Detail $Results['3'] 'Local-package edition: select an approved local 4.1.8 ZIP/MSI/folder. No DSS download was attempted.'
            return $false
        }
        $msi = Get-DssPackageMsi
        if (-not $msi) { Add-Detail $Results['3'] 'No usable installer is ready; use Locate installer.'; return $false }
        $validation = Test-PackageValid $msi
        if (-not $validation.Ok) { throw ('Installer rejected: ' + $validation.Text) }
        $script:PkgMsi = $msi
        Add-Detail $Results['3'] ('Installer automatically validated: ' + $msi + '. Installation still requires selecting a repair.')
        Write-DscEvent 'Info' 'Installer validated' @{ Path = $msi }
        return $true
    } catch { Write-DscError $_ 'Installer preparation'; Add-Detail $Results['3'] ('Installer preparation failed: ' + $_.Exception.Message); return $false }
}

function Show-SignerCertificateHelp([switch]$UseGui) {
    $url = 'https://eoffsigner.eoffice.gov.in:55101/check/isLive'
    $text = "For this signer address only: $url`r`nIf the browser offers Advanced, choose Proceed or Add Exception for this address. This is the pre-approved signer exception.`r`nIf the browser does not offer that action, follow your IT administrator's instructions. No global browser certificate policy is changed."
    if ($UseGui) {
        Start-Process -FilePath $url -ErrorAction Stop
        [void][Windows.Forms.MessageBox]::Show($text, 'Signer certificate exception', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
    } else { Say $text 'Yellow' }
}

function Get-DscOverallState {
    $live=$Results['4'];$definition=$ByNo[4]
    $failures=@($Defs | Where-Object {$_.No -ne 4 -and $_.R.Status -in 'FAIL','SKIP'}).Count
    $warnings=@($Defs | Where-Object {$_.R.Status -eq 'WARN'}).Count
    if (-not $definition.Tested -or $definition.Last.DiagnosticError -or $definition.Last.Inconclusive) {
        return @{Working=$false;Verified=$false;Title='isLive NOT VERIFIED';Detail='The isLive diagnostic did not complete. See the diagnostic log.';Failures=$failures;Warnings=$warnings}
    }
    if ($live.Status -in 'OK','FIXED','WARN') {
        $detail="isLive success. $failures additional check(s) need attention; $warnings warning(s)."
        if($definition.Last.ExpiredAccepted){$detail+=' The signer expiry alert is accepted.'}
        return @{Working=$true;Verified=$true;Title=$(if($definition.Last.ExpiredAccepted){'WORKING - EXPIRY ACCEPTED'}else{'WORKING'});Detail=$detail;Failures=$failures;Warnings=$warnings}
    }
    return @{Working=$false;Verified=$true;Title='isLive NOT WORKING';Detail='The isLive request did not return the required success response. Review the results below.';Failures=$failures;Warnings=$warnings}
}

function Invoke-JavaVersion([string]$File) {
    # Java writes its successful -version output to stderr. Read it as text, not a PowerShell error.
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$File;$info.Arguments='-version';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    try {
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not (Wait-Proc $process 15000)){try{$process.Kill()}catch{};return @{Code=-1;Text='Java version probe timed out.'}}
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),3000)){return @{Code=-1;Text='Java output did not close.'}}
        return @{Code=$process.ExitCode;Text=($stdout.Result+' '+$stderr.Result).Trim()}
    } finally {$process.Dispose()}
}

function Get-DscFindingsSummary {
    $others=@($Defs | Where-Object {$_.No -ne 4})
    $failed=@($others | Where-Object {$_.R.Status -in 'FAIL','SKIP'}).Count
    $unverified=@($others | Where-Object {$_.Last.DiagnosticError -or $_.Last.Inconclusive -or ($_.R.Status -eq 'WARN' -and $_.Last.BrowserVerified -eq $false)}).Count
    $warnings=@($others | Where-Object {$_.R.Status -eq 'WARN'}).Count
    $pending=@($others | Where-Object {$_.R.Status -in 'PENDING','NOTRUN'}).Count
    return @{Failures=$failed;Warnings=$warnings;Unverified=$unverified;Pending=$pending;Text="Other checks: $failed need attention | $warnings warnings ($unverified unverified) | $pending not checked"}
}
function Request-ConsoleReview($Fixable) {
    if($CheckOnly -or -not @($Fixable).Count){return @()}
    Say 'Diagnostics finished. No repairs have been applied.' 'White'
    if((Ask '   [R] Review / Pending fixes   [N] Finish without repairs : ' @('R','N') 'N') -ne 'R'){return @()}
    $script:DiagnosticsOnly=$false
    $script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
    try {
        [void](Prepare-DscInstaller)
        Invoke-InstallerCheckConsole
        Show-Fixable $Fixable
        $answer=Ask '   Apply reviewed fixes? [A] All listed   [S] Select individually   [N] Cancel : ' @('A','S','N') 'N'
        if($answer -eq 'A'){return @($Fixable | ForEach-Object {$_.No})}
        $selected=@()
        if($answer -eq 'S'){
            foreach($definition in $Fixable){if((Ask ("   Apply [{0}] {1}? [Y/N] : " -f $definition.DisplayNo,$definition.Title) @('Y','N') 'N') -eq 'Y'){$selected+=$definition.No}}
        }
        return $selected
    } finally {$script:DiagnosticsOnly=$true}
}

function Read-DssDownloadApproval([string]$Message) {
    if($Mode -eq 'gui') {
        return ([Windows.Forms.MessageBox]::Show($script:G.Form,$Message,'DSS 4.1.8 - permission to continue',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2) -eq 'Yes')
    }
    Say $Message 'Yellow'
    return ((Ask '   Download DSS 4.1.8 now? [Y/N] : ' @('Y','N') 'N') -eq 'Y')
}
function Get-DssSha256([string]$LiteralPath) {
    $hash=[Security.Cryptography.SHA256]::Create()
    $file=[IO.File]::Open($LiteralPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{return [BitConverter]::ToString($hash.ComputeHash($file)).Replace('-','')}
    finally{$file.Dispose();$hash.Dispose()}
}
function Confirm-DssDownload {
    if($CheckOnly -or ($script:DiagnosticsOnly -and -not $script:ReviewApproved)){return $false}
    if(-not $Cfg.AllowDssDownload -or -not $Cfg.PackageUrl){return $false}
    $key="$($Cfg.DssVersion)|$($Cfg.PackageUrl)|$($Cfg.PackageSha256)|$($Cfg.PackageFallbackUrl)"
    if($script:DssDownloadConsentKey -eq $key -and $script:DssDownloadConsent -eq 'Granted'){return $true}
    if($script:DssDownloadConsentKey -eq $key -and $script:DssDownloadConsent -eq 'Declined'){return $false}
    $script:DssDownloadConsentKey=$key
    $message="Download DigitalSignerService $($Cfg.DssVersion) (about 100 MB)?`r`nSource: $($Cfg.PackageUrl)`r`nFallback: $($Cfg.PackageFallbackUrl)`r`nThe package will be saved under your Downloads folder, validated and mapped automatically. Downloading does not install it. Installation still requires your reviewed Apply action."
    $approved=Read-DssDownloadApproval $message
    $script:DssDownloadConsent=$(if($approved){'Granted'}else{'Declined'})
    Write-DscEvent 'Info' 'DSS download permission' @{Approved=[bool]$approved;Source=$Cfg.PackageUrl}
    return [bool]$approved
}
function Start-DssInstallRequest {
    $script:DssInstallOutcome = 'Failed'
    $script:DssPackageFailure = ''
    if ($CheckOnly) { $script:DssInstallOutcome='Unavailable'; return $false }
    if (-not $IsAdmin) {
        $script:DssPackageFailure='Open Windows PowerShell as Administrator and run the tool again. No installation was started.'
        return $false
    }
    if (-not $Cfg.AllowDssDownload -or -not $Cfg.PackageUrl) {
        $script:DssPackageFailure='Installer downloads are disabled. No installation was started.'
        return $false
    }
    $message = "Download and install DigitalSignerService $($Cfg.DssVersion), then continue checks?`r`n`r`nSource: $($Cfg.PackageUrl)`r`nFallback: $($Cfg.PackageFallbackUrl)`r`nThe tool will reuse a validated package or download it to Downloads, validate and map the MSI, stop DSS if necessary, remove older DSS versions if present, and install silently. No other repairs are included. A restart may be required.`r`n`r`nChoose Yes to apply these changes now, or No to leave the installation unchanged."
    if (-not (Read-DssDownloadApproval $message)) {
        $script:DssInstallOutcome='Declined'
        Write-DscEvent 'Info' 'DSS install and continue declined' @{}
        return $false
    }
    $previousDiagnostics=$script:DiagnosticsOnly
    $previousReview=$script:ReviewApproved
    try {
        $script:DiagnosticsOnly=$false; $script:ReviewApproved=$true
        $script:DssDownloadConsentKey="$($Cfg.DssVersion)|$($Cfg.PackageUrl)|$($Cfg.PackageSha256)|$($Cfg.PackageFallbackUrl)"
        $script:DssDownloadConsent='Granted'
        Write-DscEvent 'Info' 'DSS install and continue approved' @{Source=$Cfg.PackageUrl;Check=3}
        Say 'Downloading or reusing the installer, validating, then installing DSS silently ...' 'Cyan'
        # Invoke the shared repair directly so a failed download cannot stop/remove DSS.
        $definition=$ByNo[3]
        if($script:UiProgress){& $script:UiProgress 'begin-repairs' $null 1;& $script:UiProgress 'repairing' $definition 0}
        $before=Test-DssInstall
        if ($before.Pass -and -not $before.Warn) {
            $script:DssInstallOutcome='AlreadyInstalled'
            Say 'DSS 4.1.8 is already installed correctly; continuing checks without reinstalling.' 'Green'
            return $true
        }
        Repair-DssInstall $definition.R $before
        $after=Test-DssInstall
        if (-not $after.Pass) { throw 'The installer finished but DSS 4.1.8 installation validation did not pass. See dss-install.log and the installation row.' }
        $definition.Fixed=$true
        if($script:UiProgress){& $script:UiProgress 'repaired' $definition 0}
        $script:DssInstallOutcome='Installed'
        Write-DscEvent 'Info' 'DSS install completed' @{Check=3}
        return $true
    } catch {
        $reason=$_.Exception.Message
        if ($script:DssPackageFailure) { $reason=$script:DssPackageFailure + ' ' + $reason }
        $script:DssPackageFailure=$reason
        Write-DscError $_ 'DSS install and continue'
        Add-Detail $Results['3'] ('Download/install failed: ' + $reason)
        return $false
    } finally {
        $script:DiagnosticsOnly=$previousDiagnostics
        $script:ReviewApproved=$previousReview
    }
}
function Start-DssPackageRequest {
    # Called only by an explicit Get installer / package action, never diagnostics.
    if($CheckOnly){return $false}
    $previous=$script:DiagnosticsOnly
    $script:DiagnosticsOnly=$false
    $script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
    try {
        $msi=Get-DssPackageMsi
        if(-not $msi){return $false}
        $valid=Test-PackageValid $msi
        if(-not $valid.Ok){throw ('Installer mapping rejected: '+$valid.Text)}
        $script:PkgMsi=$msi
        Say ('Installer validated and mapped: '+$msi) 'Green'
        return $true
    } finally {$script:DiagnosticsOnly=$previous}
}
function Expand-DssArchive([string]$LiteralPath,[string]$DestinationPath,[switch]$Force) {
    # Use the framework ZIP reader; never change execution policy to load an archive module.
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $root=[IO.Path]::GetFullPath($DestinationPath).TrimEnd('\')
    [void][IO.Directory]::CreateDirectory($root)
    if((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Archive destination is linked.'}
    $prefix=$root+'\';$archive=[IO.Compression.ZipFile]::OpenRead($LiteralPath)
    try {
        if($archive.Entries.Count -gt 10000){throw 'Too many archive entries.'}
        [long]$total=0
        foreach($entry in $archive.Entries){
            $total+=$entry.Length
            if($total -gt 2GB){throw 'Installer archive exceeds the extraction limit.'}
            if((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'Linked archive entries are not supported.'}
            $target=[IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Installer archive contains an unsafe path.'}
            $parent=Split-Path -Parent $target
            $check=$parent
            while($check -and $check.Length -ge $root.Length){
                if((Test-Path -LiteralPath $check) -and ((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Archive path contains a linked directory.'}
                if($check -eq $root){break};$check=Split-Path -Parent $check
            }
            if(-not $entry.Name){[void][IO.Directory]::CreateDirectory($target);continue}
            [void][IO.Directory]::CreateDirectory($parent)
            if((Test-Path -LiteralPath $target) -and -not $Force){throw 'Duplicate archive destination.'}
            if((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Archive target is linked.'}
            $inputFile=$null;$outputFile=$null
            try{$inputFile=$entry.Open();$outputFile=[IO.File]::Open($target,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);$inputFile.CopyTo($outputFile)}
            finally{if($inputFile){$inputFile.Dispose()};if($outputFile){$outputFile.Dispose()}}
        }
    } finally {$archive.Dispose()}
}

$Defs = @(
    @{ No = 4;  Title = 'Signer Service running, isLive success';   T = { Test-IsLive };      F = { param($r, $t) Repair-IsLive $r $t };       Plan = 'Install eOffice root certificate, start Signer Service as administrator, auto-start at logon' },
    @{ No = 3;  Title = "DigitalSignerService $($Cfg.DssVersion) installed properly"; T = { Test-DssInstall }; F = { param($r, $t) Repair-DssInstall $r $t }; Plan = "Remove old Signer Service, install $($Cfg.DssVersion) silently (built-in / chosen / nearby installer)" },
    @{ No = 5;  Title = 'Clean PATH: no stale Java / JAVA_TOOL_OPTIONS';     T = { Test-EnvVars };     F = { param($r, $t) Repair-EnvVars $r $t };      Plan = 'Remove stale Java PATH entries, bad JAVA_HOME, JAVA_TOOL_OPTIONS; restore missing Windows PATH folders (backup kept)' },
    @{ No = 7;  Title = 'Java works properly';                               T = { Test-JavaWorks };   F = { param($r, $t) Repair-JavaWorks $r $t };    Plan = 'Put the latest Java first on PATH / reinstall Java' },
    @{ No = 1;  Title = 'Suitable Java Runtime installed';                     T = { Test-JavaLatest };  F = { param($r, $t) Install-JavaLatest $r };       Plan = 'Keep suitable installed Java; install suitable Java only when absent. Updating working Java is an optional separate action.' },
    @{ No = 2;  Title = "Port $($Cfg.Port) not occupied by other software";  T = { Test-Port };        F = { param($r, $t) Repair-Port $r $t };         Plan = "Close the program holding port $($Cfg.Port) / free the Windows-reserved port" },
    @{ No = 6;  Title = 'hosts: 127.0.0.1 eoffsigner.eoffice.gov.in';        T = { Test-Hosts };       F = { param($r, $t) Repair-Hosts $r };           Plan = 'Correct the hosts line to 127.0.0.1 eoffsigner.eoffice.gov.in (backup kept), flush DNS' },
    @{ No = 8;  Title = 'Chrome shows isLive success';                       T = { Test-ChromiumBrowser 'Chrome' }; F = { param($r, $t) Repair-ChromiumBrowser $r $t 'Chrome' }; Plan = 'Fix whatever blocks Chrome: certificate, proxy bypass, hosts, service; allow eOffice pages to reach the signer' },
    @{ No = 9;  Title = 'Edge shows isLive success';                         T = { Test-ChromiumBrowser 'Edge' };   F = { param($r, $t) Repair-ChromiumBrowser $r $t 'Edge' };   Plan = 'Fix whatever blocks Edge: certificate, proxy bypass, hosts, service; allow eOffice pages to reach the signer' },
    @{ No = 10; Title = 'Firefox can show isLive success';                   T = { Test-Firefox };     F = { param($r, $t) Repair-Firefox $r $t };      Plan = 'Make Firefox trust the Windows certificate store, add proxy exception, start service' }
)
$FixOrder = 5, 7, 1, 2, 3, 6, 4, 8, 9, 10
$ByNo = @{}; $displayNo = 0; foreach ($d in $Defs) { $displayNo++; $d.DisplayNo = $displayNo; $d.R = New-Result $d.No $d.Title; $d.R | Add-Member DisplayNo $displayNo; $ByNo[$d.No] = $d }
# ---------------- engine shared by the window and the console
$QuickNos = @(4)                  # first gate: secure isLive success
function Invoke-AllTests([int[]]$Nos) {
    $script:NotSecureChecked = $null; $script:NotSecure = $null
    foreach ($d in $Defs) {
        if ($Nos -and $Nos -notcontains $d.No) { continue }
        if($script:UiProgress){& $script:UiProgress 'checking' $d 0}
        if ($script:UiStatus) { & $script:UiStatus "Checking [$($d.DisplayNo)] $($d.Title) ..." }
        Update-Ui
        try { $t = & $d.T; if ($null -eq $t) { throw 'Diagnostic returned no result.' } }
        catch {
            Write-DscError $_ ("Diagnostic check " + $d.No)
            $t = @{ Pass = $false; DiagnosticError = $true; Info = @('Diagnostic raised an exception; see events.jsonl.'); Advice = 'Review the local error log before attempting this repair.' }
        }
        $d.Last = $t
        $prev = $d.R.Status
        Set-FromTest $d.R $t
        if (-not $d.Tested) {
            $d.Tested = $true; $d.T0 = $t; $d.R.Before = $d.R.Status; $d.R.BeforeValue = $d.R.Value
            foreach ($i in $t.Info) { Add-Detail $d.R "Found: $i" }
        } else {
            if ($d.Fixed) { if ($t.Pass -and -not $t.Warn) { $d.R.Status = 'FIXED' } }
            elseif ($prev -eq 'SKIP' -and $d.R.Status -in 'FAIL', 'WARN') { $d.R.Status = 'SKIP' }
            foreach ($i in $t.Info) { Add-Detail $d.R "Now: $i" }
        }
        if ($script:UiRow) { & $script:UiRow $d }
        if($script:UiProgress){& $script:UiProgress 'checked' $d 0}
    }
}
# 'OK' = everything works / 'WARN' = works with warnings / 'FAIL' = not working
function Get-QuickVerdict {
    $st = @($QuickNos | ForEach-Object { $ByNo[$_].R.Status })
    if ($st -contains 'FAIL' -or $st -contains 'SKIP' -or $st -contains 'PENDING') { return 'FAIL' }
    if ($st -contains 'WARN') { return 'WARN' }
    return 'OK'
}
function Set-NotNeeded {
    foreach ($d in $Defs) { if (-not $d.Tested) { $d.R.Status = 'NOTRUN'; $d.R.Value = 'not needed - secure isLive success'; if ($script:UiRow) { & $script:UiRow $d } } }
}
function Invoke-Fixes([int[]]$nos) {
    if(-not $script:ReviewApproved){throw 'Review / Pending fixes and explicitly apply them before running repairs.'}
    if($script:UiProgress){& $script:UiProgress 'begin-repairs' $null @($FixOrder | Where-Object {$nos -contains $_}).Count}
    foreach ($no in $FixOrder) {
        if ($nos -notcontains $no) { continue }
        Update-Ui
        if($script:CancelRequested){if($script:UiProgress){& $script:UiProgress 'cancelled' $null 0};Write-DscEvent 'Info' 'Repair queue stopped' @{BeforeCheck=$no}; break}
        $d = $ByNo[$no]; $r = $d.R
        if($script:UiProgress){& $script:UiProgress 'repairing' $d 0}
        if ($script:UiStatus) { & $script:UiStatus "Repairing [$($d.DisplayNo)] $($d.Title) ..." }
        Say ''; Say ("   [{0}] {1}" -f $no, $d.Title) 'White'
        try { $t = & $d.T; if ($null -eq $t) { throw 'Repair precheck returned no result.' } }
        catch { Write-DscError $_ ("Repair precheck " + $no); $r.Status = 'FAIL'; $r.Advice = 'Repair was skipped because its precheck failed.'; if($script:UiProgress){& $script:UiProgress 'repaired' $d 0}; continue }
        if($script:CancelRequested){if($script:UiProgress){& $script:UiProgress 'cancelled' $null 0};break}
        $d.Fixed=$true
        Write-DscEvent 'Info' 'Repair attempted' @{ Check = $no }
        if ($t.Pass -and -not $t.Warn) { Add-Detail $r 'Solved by an earlier fix'; Say '      -> already solved by an earlier fix' 'Cyan' }
        else { try { & $d.F $r $t } catch { Write-DscError $_ ("Repair check " + $no); $r.Status = 'FAIL'; $r.Advice = $_.Exception.Message; Add-Detail $r "Repair error: $($_.Exception.Message)"; Log $_.ScriptStackTrace } }
        if($script:UiProgress){& $script:UiProgress 'repaired' $d 0}
        Update-Ui
    }
}
function Get-Failed { @($Defs | Where-Object { $_.R.Status -eq 'FAIL' -or $_.R.Status -eq 'SKIP' }) }
function Get-Fixable { @($Defs | Where-Object { $_.R.Status -in 'FAIL', 'SKIP' -or ($_.R.Status -eq 'WARN' -and $_.R.Fixable) }) }
# fixing needs admin rights: restart this tool elevated and hand over what to fix
function Request-Elevation([int[]]$nos, [string]$NextMode) {
    $message = 'Repairs require Administrator rights. Close this tool, open Windows PowerShell using Run as administrator, then run the same install.ps1 command again. No repairs were started.'
    Say $message 'Yellow'
    if ($Mode -eq 'gui') {
        [void][Windows.Forms.MessageBox]::Show($message, 'Administrator required', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
    }
    return $false
}
if ($script:Handoff -and $script:Handoff.pkg) { $script:PkgOverride = [string]$script:Handoff.pkg }
if ($Cfg.AllowDssDownload -and $script:Handoff -and $script:Handoff.pkgurl) { $Cfg.PackageUrl = [string]$script:Handoff.pkgurl; $Cfg.PackageSha256 = [string]$script:Handoff.pkgsha }
if($script:Handoff -and $script:Handoff.nopackage){$Cfg.AllowDssDownload=$false;$Cfg.PackageUrl=''}
function Save-Results {
    Save-DscSession $Results
    $rep = Write-Report
    $Results.Values | Select-Object No, DisplayNo, Title, Before, BeforeValue, Status, Value, @{n = 'Detail'; e = { $_.Detail -join ' | ' } }, @{n = 'Actions'; e = { $_.Actions -join ' | ' } }, Advice |
        ConvertTo-Json | Set-Content (Join-Path $RunDir 'result.json')
    return $rep
}

# ---------------- PACK mode
function Start-Pack {
    Say "Building ONE file that contains this tool + the DigitalSignerService $($Cfg.DssVersion) installer ..." 'White'
    if (-not (Find-DssPackageSource)) { if (-not (Request-PackageConsole)) { Say 'Cancelled.' 'Red'; return } }
    [void](Build-PortableTool)
}

# ---------------- CONSOLE mode
# step 2 (console): where is the 4.1.8 installer? validate it, then ask to perform the check
function Select-PackageConsole([string]$Reason, [switch]$Start) {
    # same validation everywhere: start, 'locate', DSS not installed, installer needed during Fix
    if ($Reason) { Say ''; Say "   $Reason" 'Red' }
    $def = Get-DefaultPackagePath
    while ($true) {
        if ($def) { Say "   Found: $def" 'Gray' }
        $last = $(if ($Start) { '[X] exit' } else { '[X] cancel' })
        $q = "   [Enter] use it   [F] pick zip/msi   [D] pick folder   [P] type a path   [S] skip   $last : "
        if (-not $def) { $q = "   [F] pick zip/msi   [D] pick folder   [P] type a path   [S] skip (no installer)   $last : " }
        $a = Ask $q @('U', 'F', 'D', 'P', 'S', 'X') $(if ($def) { 'U' } else { 'S' })
        if ($a -eq 'X') { return 'exit' }
        if ($a -eq 'S') { $script:PkgSkipped = $true; $script:PkgOverride = $null; Say '   Skipped - continuing without an installer (it is only needed if DSS 4.1.8 must be installed).' 'Yellow'; return 'skip' }
        $p = $null
        switch ($a) { 'U' { $p = $def } 'F' { $p = Show-PickPackage 'file' } 'D' { $p = Show-PickPackage 'folder' } 'P' { $p = AskText '   Full path of the zip, msi or folder : ' } }
        if ($a -in 'F', 'D' -and -not $p) { $p = AskText '   (no dialog) Full path of the zip, msi or folder : ' }
        if ($p -eq '(built into this tool)') { $script:PkgSkipped = $false; Say '   VALID - installer built into this tool' 'Green'; return 'ok' }
        $v = Test-PackageValid $p
        if ($v.Ok) { [void](Set-PackageOverride $v.Path -Quiet); Say "   $($v.Text)" 'Green'; return 'ok' }
        Say "   NOT VALID - $($v.Text)" 'Red'; $def = ''
    }
}
$script:PkgAsked = $false
# step 2: is DSS 4.1.8 at its standard path? only if NOT, ask for the installer package
function Request-PackageStart {
    $ver = $Cfg.DssVersion
    Say ''; Say "STEP 2 - Is DigitalSignerService $ver installed?  ($($Cfg.DssExePaths[0]))" 'White'
    $t3 = Test-DssInstall
    if (-not $t3.NotInstalled) { Say "   FOUND - $($t3.Exe)" 'Green'; return $true }
    Say "   NOT INSTALLED in this system - $($Cfg.DssExePaths[0]) was not found." 'Red'
    $script:PkgAsked = $true
    return ((Select-PackageConsole "Select the DigitalSignerService $ver installer package (zip / msi / folder) - it is linked for the fix:" -Start) -ne 'exit')
}
function Request-PackageConsole {
    if($Cfg.AllowDssDownload -and $Cfg.PackageUrl){return (Start-DssPackageRequest)}
    return ((Select-PackageConsole "The DigitalSignerService $($Cfg.DssVersion) installer is needed to install the Signer Service - select it:") -eq 'ok') }
# DSS 4.1.8 not installed: say it in red and ask for the installer, then test row 3 again
function Invoke-InstallerCheckConsole {
    if($Cfg.AllowDssDownload -and $Cfg.PackageUrl){return}
    $d3 = $ByNo[3]
    if (-not $d3.Tested -or $d3.R.Status -notin 'FAIL', 'SKIP' -or -not $d3.Last.NotInstalled) { return }
    Say ''; Say "   DigitalSignerService $($Cfg.DssVersion) is NOT INSTALLED in this system." 'Red'
    if ($script:PkgAsked -and -not (Find-DssPackageSource)) { Say "   No installer linked - item 3 cannot be fixed until one is chosen (you will be asked again during Fix)." 'Gray'; return }
    if (Find-DssPackageSource) { Say "   Installer ready: $((Find-DssPackageSource).Text)  - choose Fix for item 3." 'Gray'; return }
    if ((Select-PackageConsole "Select the DigitalSignerService $($Cfg.DssVersion) installer (zip / msi / folder) - it is validated and item 3 is tested again:") -eq 'ok') {
        Invoke-AllTests @(3); Show-Row $d3.R
    }
}

function Show-Fixable($list) {
    foreach ($d in $list) {
        Say ("   [{0}] {1}   ({2})" -f $d.DisplayNo, $d.Title, (Get-Label $d.R.Status)) $(if ($d.R.Status -eq 'WARN') { 'Yellow' } else { 'Red' })
        foreach ($i in $d.Last.Info) { Say "        found : $i" 'Gray' }
        Say "        fix   : $($d.Plan)" 'Cyan'
    }
}
function Start-Console {
    if (-not $TestMode) { Clear-Host }
    Say '=================================================================' 'White'
    Say ("$($Cfg.EditionName) | Build 2026.10.27.3") 'White'
    Say "  Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )$(if($CheckOnly){'   [CHECK ONLY]'})$(if($TestMode){'   [TEST MODE]'})" 'White'
    Say "  Running as: $(if($IsAdmin){'Administrator'}else{'normal user (reopen PowerShell as Administrator for repairs)'})" 'Gray'
    Say '=================================================================' 'White'
    $handFix = @(); if ($script:Handoff) { $handFix = @($script:Handoff.fix | ForEach-Object { [int]$_ }) }
    $ready = Invoke-StartupSequence -OpenBrowser:(-not $CheckOnly) -FullCheck:($CheckOnly -or $handFix.Count -gt 0)
    foreach ($d in $Defs) { if ($d.Tested) { Show-Row $d.R } }
    $state=Get-DscOverallState
    Say ("Signer service: " + $state.Title) 'White'
    Say (Get-DscFindingsSummary).Text
    $fixable=@(Get-Fixable)
    $doFix=@(Request-ConsoleReview $fixable)
    if($doFix.Count -and -not $IsAdmin){
        [void](Request-Elevation $doFix 'consolefix')
        [void](Save-Results); return
    }
    if ($doFix.Count) {
        $script:RequestPackage = { Request-PackageConsole }
        Say ''; Say 'Fixing ...' 'White'
        $script:ReviewApproved=$true
        try {Invoke-Fixes $doFix} finally {$script:ReviewApproved=$false}
        Say ''; Say 'Testing again ...' 'White'; Say ''
        [void](Invoke-StartupSequence -FullCheck)
        foreach ($d in $Defs) { Show-Row $d.R }
    }
    $bad = @(Get-Failed).Count; $warn = @($Defs | Where-Object { $_.R.Status -eq 'WARN' }).Count
    Say ''
    if ($Results['4'].Status -in 'OK', 'FIXED', 'WARN') { Say "   isLive: $($Results['4'].Value)" $(if ($Results['4'].Status -eq 'WARN') { 'Yellow' } else { 'Green' }) }
    $state=Get-DscOverallState
    Say ("   Signer service: " + $state.Title) $(if($state.Working){'Green'}else{'Yellow'})
    Say (Get-DscFindingsSummary).Text
    if (-not $CheckOnly -and $doFix.Count -and $Results['4'].Status -in 'OK', 'FIXED', 'WARN') {
        Say ''
        if ((Ask '   Open the isLive page in Chrome / Edge / Firefox so you can see "success"?  [Y/N] : ' @('Y', 'N') 'N') -eq 'Y') {
            Say '   (Restart a browser first if a browser setting was changed above.)' 'Gray'
            [void](Open-InBrowsers)
        }
    }
    $report = Save-Results
    Say ("Session logs: " + $script:DscSessionDirectory)
    if (-not $CheckOnly -and -not $TestMode) {
        if ($script:JavaUpdateOffer.Available) { Say $script:JavaUpdateOffer.Text 'Yellow' }
        $reportChoice = Ask '   [U] Optional Java update   [C] Browser exception help   [E] Error report   [I] Improvement   [N] Finish : ' @('U','C','E','I','N') 'N'
        if ($reportChoice -eq 'C') { Show-SignerCertificateHelp }
        if ($reportChoice -eq 'U' -and $script:JavaUpdateOffer.Available) {
            if ((Ask '   Install the optional Java update? [Y/N] : ' @('Y','N') 'N') -eq 'Y') {
                if (Invoke-OptionalJavaUpdate -Confirmed) { [void](Invoke-StartupSequence -FullCheck); $report = Save-Results }
            }
        }
        if ($reportChoice -eq 'E') { Show-DscGitHubReport }
        elseif ($reportChoice -eq 'I') { Show-DscGitHubReport -Kind Improvement }
    }
    Say ''; Say "Report: $report"
    if ($Cfg.OpenReport -and -not $TestMode -and -not $CheckOnly -and ($bad -or $doFix.Count)) { Start-Process $report }
}

# ---------------- WINDOW (visual) mode
# fonts / system colours (replaceable by the test harness, which has no Windows desktop)
function New-UiFont([string]$Name, [double]$Size, [switch]$Bold) {
    if ($env:DSSF_GUISTUB) { return [System.Windows.Forms.StubFont]::new($Name, $Size) }
    try {
        if ($Bold) { return New-Object Drawing.Font($Name, [single]$Size, [Drawing.FontStyle]::Bold) }
        return New-Object Drawing.Font($Name, [single]$Size)
    } catch { Write-DscError $_ 'Caught exception'; return New-Object Drawing.Font('Microsoft Sans Serif', [single]$Size) }
}
function Get-SysColor([string]$Name) {
    if ($env:DSSF_GUISTUB) { if ($Name -eq 'WindowText') { return [Drawing.Color]::Black } else { return [Drawing.Color]::LightGray } }
    return [Drawing.SystemColors]::$Name
}
function Start-Gui {
    if (-not $env:DSSF_GUISTUB) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing }
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $G = @{}; $script:G = $G
    $C = @{
        Navy = [Drawing.Color]::FromArgb(11, 61, 99); Ok = [Drawing.Color]::FromArgb(19, 128, 74); Bad = [Drawing.Color]::FromArgb(198, 40, 40)
        Warn = [Drawing.Color]::FromArgb(154, 100, 0); Fix = [Drawing.Color]::FromArgb(11, 106, 166); Mute = [Drawing.Color]::FromArgb(110, 120, 130)
        OkBg = [Drawing.Color]::FromArgb(230, 246, 237); BadBg = [Drawing.Color]::FromArgb(253, 234, 234); Amber = [Drawing.Color]::FromArgb(255, 213, 120)
    }
    $script:GC = $C
    # every button / window event runs through this: an error is shown and logged, the window never freezes
    function Invoke-UiSafe([scriptblock]$Body) {
        try { & $Body }
        catch { Write-DscError $_ 'Caught exception';
            $err = $_
            Log "UI error: $($err.Exception.Message) @ line $($err.InvocationInfo.ScriptLineNumber): $($err.InvocationInfo.Line.Trim())"
            try { Set-Busy $false } catch { Write-DscError $_ 'Caught exception';}
            try { $script:G.Stat.Text = "Error: $($err.Exception.Message)" } catch { Write-DscError $_ 'Caught exception';}
            try { [void][Windows.Forms.MessageBox]::Show($script:G.Form,"Something went wrong:`r`n$($err.Exception.Message)`r`n`r`nThe window still works - click 'Run full check' to try again, or Close.`r`nLog: $LogFile", 'Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) } catch { Write-DscError $_ 'Caught exception';}
        }
    }
    $font = (New-UiFont 'Segoe UI' 9.5)
    $f = New-Object Windows.Forms.Form
    $f.Text = "$($Cfg.EditionName) | Build 2026.10.27.3 | DSS $($Cfg.DssVersion)"
    $f.Size = New-Object Drawing.Size(1100, 760); $f.MinimumSize = New-Object Drawing.Size(900, 600)
    $f.TopMost=$true
    $f.StartPosition = 'CenterScreen'; $f.Font = $font; $f.BackColor = [Drawing.Color]::White
    $G.Form = $f

    # header
    $hdr = New-Object Windows.Forms.Panel; $hdr.Dock = 'Top'; $hdr.Height = 74; $hdr.BackColor = $C.Navy
    $t1 = New-Object Windows.Forms.Label; $t1.UseMnemonic = $false; $t1.Text = 'Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )'; $t1.ForeColor = [Drawing.Color]::White
    $t1.Font = (New-UiFont 'Segoe UI Semibold' 13); $t1.AutoSize = $true; $t1.Location = New-Object Drawing.Point(16, 8)
    $t2 = New-Object Windows.Forms.Label; $t2.ForeColor = [Drawing.Color]::FromArgb(200, 220, 235); $t2.AutoSize = $true; $t2.Location = New-Object Drawing.Point(18, 44)
    $t2.Text = "isLive, installation path, PATH, Java, port, installer preparation and remaining checks   |   $([Environment]::MachineName)   |   $(if ($IsAdmin) { 'Administrator' } else { 'normal user' })"
    $hdr.Controls.AddRange(@($t1, $t2)); $G.Sub = $t2

    # isLive banner
    $live = New-Object Windows.Forms.Label; $live.Dock = 'Top'; $live.Height = 44; $live.TextAlign = 'MiddleLeft'
    $live.Padding = New-Object Windows.Forms.Padding(16, 0, 0, 0); $live.Font = (New-UiFont 'Segoe UI Semibold' 12)
    $other=New-Object Windows.Forms.Label; $other.Dock='Top'; $other.Height=32; $other.Padding=New-Object Windows.Forms.Padding(16,0,0,0); $other.TextAlign='MiddleLeft'; $other.Text='Other checks: diagnostics running ...'; $G.Findings=$other
    $live.Text = 'Signer service: testing ...'; $live.UseMnemonic = $false; $t2.UseMnemonic = $false; $live.BackColor = [Drawing.Color]::FromArgb(240, 243, 247); $G.Live = $live

    # buttons
    $bar = New-Object Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 52; $bar.WrapContents = $true; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'; $bar.Padding = New-Object Windows.Forms.Padding(10, 9, 10, 6)
    $bar.BackColor = [Drawing.Color]::FromArgb(244, 246, 249)
    function New-Btn($text, $w) { $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Width = $w; $b.Height = 32; $b.FlatStyle = 'Standard'; $b.UseVisualStyleBackColor = $true; $b.Margin = New-Object Windows.Forms.Padding(4, 0, 4, 0); return $b }
    $G.BGitHub = New-Btn 'Report error ...' 130
    $G.BImprove = New-Btn 'Suggest improvement ...' 165
    $bar.Controls.AddRange(@($G.BGitHub, $G.BImprove))
    $G.BJavaUpdate = New-Btn 'Update Java (optional)' 165
    $G.BJavaUpdate.Visible = $false
    $G.BCertificate = New-Btn 'Browser exception ...' 150
    $G.BCertificate.Visible = $false
    $bar.Controls.AddRange(@($G.BJavaUpdate, $G.BCertificate))
    $G.JavaTimer = New-Object Windows.Forms.Timer; $G.JavaTimer.Interval = 600
    $G.JavaTimer.Add_Tick({
        if ($script:G.BJavaUpdate.BackColor -eq [Drawing.Color]::Yellow) { $script:G.BJavaUpdate.BackColor = [Drawing.Color]::Orange }
        else { $script:G.BJavaUpdate.BackColor = [Drawing.Color]::Yellow }
    })
    $script:UiJavaOffer = {
        if ($script:G.Form.IsDisposed) { return }
        $script:G.BJavaUpdate.Visible = [bool]$script:JavaUpdateOffer.Available
        if ($script:JavaUpdateOffer.Available) { $script:G.JavaTimer.Start() } else { $script:G.JavaTimer.Stop() }
        [Windows.Forms.Application]::DoEvents()
    }
    $G.BTest = New-Btn 'Run full check' 115
    $G.BFix = New-Btn 'Review / Pending fixes ...' 185
    $G.BLocate = New-Btn 'Download + install DSS ...' 185
    $G.BOpen = New-Btn 'Open DSC isLive Service Test-Check in browsers' 330
    $G.BOpen.BackColor = [Drawing.Color]::FromArgb(255, 221, 0); $G.BOpen.UseVisualStyleBackColor = $false
    $G.BOpen.Font = (New-UiFont 'Segoe UI Semibold' 9.5)
    $G.BReport = New-Btn 'Open report' 105
    $G.BPack = New-Btn 'Batch packing unavailable' 150; $G.BPack.Visible = $false
    $G.BClose = New-Btn 'Close' 80
    $G.BCancel = New-Btn 'Cancel remaining fixes' 165; $G.BCancel.Enabled=$false
    # pointing hand (Wingdings 'F' = right-pointing hand, present on every Windows) + flashing 'Open DSC isLive' button
    $G.Hand = New-Object Windows.Forms.Label; $G.Hand.UseMnemonic = $false; $G.Hand.AutoSize = $true; $G.Hand.Text = 'F'
    $G.Hand.Font = (New-UiFont 'Wingdings' 20); $G.Hand.ForeColor = [Drawing.Color]::FromArgb(198, 40, 40)
    $G.Hand.Margin = New-Object Windows.Forms.Padding(10, 0, 2, 0); $G.Hand.Visible = $false
    $G.BOpen.Cursor = [Windows.Forms.Cursors]::Hand
    $bar.Controls.AddRange(@($G.BTest, $G.BFix, $G.BLocate, $G.Hand, $G.BOpen, $G.BReport, $G.BPack, $G.BCancel, $G.BClose))
    $G.Flash = New-Object Windows.Forms.Timer; $G.Flash.Interval = 450; $script:FlashOn = $false
    $G.Flash.Add_Tick({
        try {
            $G = $script:G; $script:FlashOn = -not $script:FlashOn
            if ($script:FlashOn) { $G.BOpen.BackColor = [Drawing.Color]::FromArgb(255, 140, 0); $G.BOpen.ForeColor = [Drawing.Color]::White; $G.Hand.Margin = New-Object Windows.Forms.Padding(16, 0, 0, 0) }
            else { $G.BOpen.BackColor = [Drawing.Color]::FromArgb(255, 221, 0); $G.BOpen.ForeColor = [Drawing.Color]::Black; $G.Hand.Margin = New-Object Windows.Forms.Padding(8, 0, 8, 0) }
        } catch { Write-DscError $_ 'Caught exception'; try { $script:G.Flash.Stop() } catch { Write-DscError $_ 'Caught exception';} }
    })

    # status strip
    $ss = New-Object Windows.Forms.StatusStrip
    $G.Stat = New-Object Windows.Forms.ToolStripStatusLabel; $G.Stat.Spring = $true; $G.Stat.TextAlign = 'MiddleLeft'; $G.Stat.Text = 'Ready'
    $G.Prog = New-Object Windows.Forms.ToolStripProgressBar; $G.Prog.Style = 'Continuous'; $G.Prog.Visible = $false; $G.Prog.Width = 160
    [void]$ss.Items.Add($G.Stat); [void]$ss.Items.Add($G.Prog)

    # A persistent, step-based battery display; 100% means processed, not repaired.
    $progressPanel=New-Object Windows.Forms.Panel; $progressPanel.Dock='Bottom'; $progressPanel.Height=88; $progressPanel.Width=$f.ClientSize.Width
    $progressPanel.BackColor=[Drawing.Color]::FromArgb(237,244,253)
    $G.Stage=New-Object Windows.Forms.Label; $G.Stage.Location=New-Object Drawing.Point(12,5); $G.Stage.Size=New-Object Drawing.Size(($progressPanel.Width-24),22); $G.Stage.Anchor='Top,Left,Right'; $G.Stage.Font=(New-UiFont 'Segoe UI' 10 -Bold); $G.Stage.Text='Ready to check Digital Signer Service.'
    $G.Target=New-Object Windows.Forms.Label; $G.Target.Location=New-Object Drawing.Point(12,28); $G.Target.Size=New-Object Drawing.Size(($progressPanel.Width-24),20); $G.Target.Anchor='Top,Left,Right'; $G.Target.AutoEllipsis=$true; $G.Target.Text='Current target and action will appear here.'
    $batteryFrame=New-Object Windows.Forms.Panel; $batteryFrame.Location=New-Object Drawing.Point(12,54); $batteryFrame.Size=New-Object Drawing.Size(216,22); $batteryFrame.BorderStyle='FixedSingle'
    $G.Battery=New-Object Windows.Forms.ProgressBar; $G.Battery.Dock='Fill'; $G.Battery.Minimum=0; $G.Battery.Maximum=100; $G.Battery.Style='Continuous'; $batteryFrame.Controls.Add($G.Battery)
    $batteryCap=New-Object Windows.Forms.Panel; $batteryCap.Location=New-Object Drawing.Point(229,60); $batteryCap.Size=New-Object Drawing.Size(5,10); $batteryCap.BackColor=[Drawing.Color]::FromArgb(41,83,137)
    $G.ProgressCount=New-Object Windows.Forms.Label; $G.ProgressCount.Location=New-Object Drawing.Point(248,55); $G.ProgressCount.Size=New-Object Drawing.Size(($progressPanel.Width-420),22); $G.ProgressCount.Anchor='Top,Left,Right'; $G.ProgressCount.Text='0 steps processed'
    $G.PinTop=New-Object Windows.Forms.CheckBox; $G.PinTop.Text='Keep GUI on top'; $G.PinTop.Checked=$true; $G.PinTop.AutoSize=$true; $G.PinTop.Location=New-Object Drawing.Point(($progressPanel.Width-155),56); $G.PinTop.Anchor='Top,Right'
    $G.PinTop.Add_CheckedChanged({$script:G.Form.TopMost=$script:G.PinTop.Checked})
    $progressPanel.Controls.AddRange(@($G.Stage,$G.Target,$batteryFrame,$batteryCap,$G.ProgressCount,$G.PinTop))

    # list + details
    $split = New-Object Windows.Forms.SplitContainer; $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'
    $lv = New-Object Windows.Forms.ListView; $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true
    $lv.HideSelection = $false; $lv.Font = (New-UiFont 'Segoe UI' 10); $lv.HeaderStyle = 'Nonclickable'
    [void]$lv.Columns.Add('Check #', 78); [void]$lv.Columns.Add('Check', 360); [void]$lv.Columns.Add('Status', 110); [void]$lv.Columns.Add('State / version', 520)
    $G.List = $lv; $G.RowsById = @{}
    foreach ($d in $Defs) {
        $it = New-Object Windows.Forms.ListViewItem("$($lv.Items.Count + 1)"); $it.UseItemStyleForSubItems = $false; $it.Tag = $d.No
        [void]$it.SubItems.Add($d.Title); [void]$it.SubItems.Add('...'); [void]$it.SubItems.Add('')
        [void]$lv.Items.Add($it); $G.RowsById[[int]$d.No] = $it
    }
    $txt = New-Object Windows.Forms.TextBox; $txt.Dock = 'Fill'; $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = 'Vertical'
    $txt.Font = (New-UiFont 'Consolas' 9.5); $txt.BackColor = [Drawing.Color]::FromArgb(250, 251, 252); $G.Txt = $txt
    $split.Panel1.Controls.Add($lv); $split.Panel2.Controls.Add($txt)

    $f.Controls.Add($split); $f.Controls.Add($other); $f.Controls.Add($live); $f.Controls.Add($hdr); $f.Controls.Add($progressPanel); $f.Controls.Add($bar); $f.Controls.Add($ss)
    $G.Split = $split


    # ---- helpers bound to the window
    $script:UiLog = { param($m, $clr) $box = $script:G.Txt; if ($box -and $script:G.LogMode) { $box.AppendText($m + "`r`n") } }
    $script:UiStatus = { param($m,$target) $script:G.Stat.Text = $m; $script:G.Stage.Text=$m; if($target){$script:G.Target.Text=$target}; [System.Windows.Forms.Application]::DoEvents() }
    $script:UiRow = {
        param($d)
        try { & $script:UiRowInner $d } catch { Write-DscError $_ 'Caught exception'; Log "row display error [$($d.No)]: $($_.Exception.Message)" }
    }
    $script:UiRowInner = {
        param($d)
        $C = $script:GC; $it = $script:G.RowsById[[int]$d.No]
        $st = $d.R.Status; $lab = Get-Label $st
        $it.SubItems[2].Text = $lab; $it.SubItems[3].Text = $d.R.Value
        $col = $C.Ok; $bg = [Drawing.Color]::White
        switch ($st) { 'FAIL' { $col = $C.Bad; $bg = $C.BadBg } 'SKIP' { $col = $C.Bad; $bg = $C.BadBg } 'WARN' { $col = $C.Warn; $bg = [Drawing.Color]::FromArgb(253, 243, 225) } 'NA' { $col = $C.Mute } 'NOTRUN' { $col = $C.Mute } 'PENDING' { $col = $C.Mute } 'FIXED' { $col = $C.Fix } }
        $it.SubItems[2].ForeColor = $col; $it.SubItems[2].Font = (New-UiFont 'Segoe UI' 10 -Bold)
        foreach ($si in $it.SubItems) { $si.BackColor = $bg }
        if ($d.No -eq 3 -and $st -in 'FAIL', 'SKIP' -and $d.Last.NotInstalled) { $it.SubItems[3].ForeColor = $C.Bad; $it.SubItems[3].Font = (New-UiFont 'Segoe UI' 10 -Bold) }
        else { $it.SubItems[3].ForeColor = (Get-SysColor WindowText); $it.SubItems[3].Font = $script:G.List.Font }
        $it.Checked = $false
        [System.Windows.Forms.Application]::DoEvents()
    }
    function Get-GuiWorkTarget([int]$No) {
        switch($No){
            4 {return $Cfg.IsLiveUrl}
            3 {return 'C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe / validated DSS installer'}
            5 {return 'Windows PATH, JAVA_HOME and Java option variables'}
            7 {return 'java.exe execution and version response'}
            1 {return 'Installed Java 8 / 64-bit runtime'}
            2 {return 'Local TCP port 55101 and its listener process'}
            6 {return ($env:SystemRoot+'\System32\drivers\etc\hosts -> 127.0.0.1 eoffsigner.eoffice.gov.in')}
            8 {return 'Chrome -> signer isLive HTTPS endpoint'}
            9 {return 'Edge -> signer isLive HTTPS endpoint'}
            10 {return 'Firefox -> signer isLive HTTPS endpoint'}
        }
        return 'Digital Signer Service diagnostics'
    }
    $script:UiProgress = {
        param($event,$definition,$total)
        $ui=$script:G
        if($event -in 'begin-checks','begin-repairs'){
            $ui.ProgressPhase=$(if($event -eq 'begin-checks'){'Checks'}else{'Repairs'})
            $ui.ProgressTotal=[Math]::Max(1,[int]$total)
            $ui.ProgressDone=New-Object 'Collections.Generic.HashSet[int]'
            $ui.Battery.Value=0; $ui.Prog.Value=0
            $ui.Stage.Text=$ui.ProgressPhase+' starting ...'
            $ui.Target.Text='Progress counts steps; downloads and installers can take longer.'
        } elseif($event -eq 'cancelled'){
            $ui.Stage.Text='Remaining repairs cancelled. Completed work will be checked again.'
        } elseif($definition){
            if($null -eq $ui.ProgressDone){$ui.ProgressDone=New-Object 'Collections.Generic.HashSet[int]';$ui.ProgressTotal=10;$ui.ProgressPhase='Checks'}
            $ui.Target.Text='Target: '+(Get-GuiWorkTarget $definition.No)
            if($event -in 'checked','repaired'){
                [void]$ui.ProgressDone.Add([int]$definition.No)
                $ui.Stage.Text=$(if($event -eq 'checked'){'Checked'}else{'Repair attempt finished; recheck follows'})+" [$($definition.DisplayNo)] $($definition.Title)"
                if($event -eq 'checked'){$ui.Stage.Text+=' - '+(Get-Label $definition.R.Status)}
            }else{$ui.Stage.Text=$(if($event -eq 'checking'){'Checking'}else{'Repairing'})+" [$($definition.DisplayNo)] $($definition.Title)"}
            $pct=[Math]::Min(100,[int](100*$ui.ProgressDone.Count/$ui.ProgressTotal))
            $ui.Battery.Value=$pct; $ui.Prog.Value=$pct
        }
        if($null -ne $ui.ProgressDone){$ui.ProgressCount.Text="$($ui.ProgressPhase): $($ui.ProgressDone.Count)/$($ui.ProgressTotal) steps ($($ui.Battery.Value)%); see results for success."}
        [System.Windows.Forms.Application]::DoEvents()
    }

    $script:Ui = $f
    $script:RequestPackage = { if($Cfg.AllowDssDownload -and $Cfg.PackageUrl){return (Start-DssPackageRequest)}; return ((Show-PackageDialog "The installer is needed to install DigitalSignerService $($Cfg.DssVersion) - select the zip / msi / folder") -eq 'ok') }

    function Start-Flash { try { $script:G.Hand.Visible = $true; $script:G.Flash.Start() } catch { Write-DscError $_ 'Caught exception';} }
    function Stop-Flash {
        try {
            $script:G.Flash.Stop(); $script:G.Hand.Visible = $false
            $script:G.BOpen.BackColor = [Drawing.Color]::FromArgb(255, 221, 0); $script:G.BOpen.ForeColor = [Drawing.Color]::Black
        } catch { Write-DscError $_ 'Caught exception';}
    }
    function Set-Busy([bool]$b) {
        $script:G.Busy=$b
        $script:G.BClose.Enabled=-not $b
        $script:G.BCancel.Enabled=($b -and $script:RepairRunning -and -not $script:CancelRequested)
        foreach ($k in 'BTest', 'BFix', 'BLocate', 'BOpen', 'BReport', 'BPack', 'BGitHub', 'BImprove', 'BJavaUpdate', 'BCertificate') { $script:G[$k].Enabled = -not $b }
        $script:G.Prog.Visible = $b
        $script:G.Form.Cursor = $(if ($b) { [Windows.Forms.Cursors]::WaitCursor } else { [Windows.Forms.Cursors]::Default })
        [System.Windows.Forms.Application]::DoEvents()
    }
    function Show-Detail {
        try {
            $G = $script:G
            if ($G.List.SelectedItems.Count -eq 0) { return }
            $d = $ByNo[[int]$G.List.SelectedItems[0].Tag]; $r = $d.R
            $lines = @("[$($d.DisplayNo)] $($d.Title)", "Status : $(Get-Label $r.Status)    (first test: $(Get-Label $r.Before))", "State  : $($r.Value)", '')
            $lines += $r.Detail | ForEach-Object { "  $_" }
            if ($r.Status -in 'FAIL', 'SKIP' -or ($r.Status -eq 'WARN' -and $r.Fixable)) { $lines += ''; $lines += "Fix plan: $($d.Plan)" }
            if ($r.Actions.Count) { $lines += ''; $lines += 'What the tool did:'; $lines += $r.Actions | ForEach-Object { "  -> $_" } }
            if ($r.Status -in 'FAIL', 'SKIP', 'WARN' -and $r.Advice) { $lines += ''; $lines += "Note: $($r.Advice)" }
            $G.LogMode = $false; $G.Txt.Text = ($lines -join "`r`n")
        } catch { Write-DscError $_ 'Caught exception'; Log "detail panel error: $($_.Exception.Message)" }
    }
    function Update-Summary {
        $G = $script:G; $C = $script:GC
        $G.BJavaUpdate.Visible = [bool]$script:JavaUpdateOffer.Available
        if ($script:JavaUpdateOffer.Available) { $G.JavaTimer.Start() } else { $G.JavaTimer.Stop() }
        $G.BCertificate.Visible = [bool]$ByNo[4].Last.ExpiredAccepted
        if ($Results['4'].Status -in 'OK', 'FIXED', 'WARN') { Start-Flash } else { Stop-Flash }
        $l = $Results['4']; $fails = @(Get-Failed); $fx = @(Get-Fixable); $warn = @($Defs | Where-Object { $_.R.Status -eq 'WARN' })
        $amberBg = [Drawing.Color]::FromArgb(253, 243, 225)
        $d3 = $ByNo[3]
        $state=Get-DscOverallState
        $G.Live.Text='Signer service: '+$state.Title + '  -  ' + $l.Value
        $G.Live.ForeColor=$(if($state.Working){$C.Ok}elseif(-not $state.Verified){$C.Warn}else{$C.Bad})
        $G.Live.BackColor=$(if($state.Working){$C.OkBg}elseif(-not $state.Verified){$amberBg}else{$C.BadBg})
        $findings=Get-DscFindingsSummary
        $G.Findings.Text=$findings.Text
        $G.Findings.ForeColor=$(if($findings.Failures){$C.Bad}elseif($findings.Warnings){$C.Warn}else{$C.Ok})
        $G.Sub.Text='Diagnostics only. Review / Pending fixes when ready; no repair has been applied automatically.' 
        $G.Stat.Text="Signer service: $($state.Title) | Other checks: $($findings.Failures) issues, $($findings.Warnings) warnings"
        $G.BFix.Enabled = ($fx.Count -gt 0)
        $miss = [bool]($ByNo[3].Tested -and $ByNo[3].R.Status -in 'FAIL', 'SKIP' -and $ByNo[3].Last.NotInstalled -and -not (Find-DssPackageSource))
        $G.BLocate.BackColor = $(if ($miss) { $C.Amber } else { (Get-SysColor Control) })
        $G.BLocate.UseVisualStyleBackColor = -not $miss
    }
    function Invoke-GuiTest([switch]$Full) {
        Set-Busy $true; $script:G.LogMode = $true; $script:G.Txt.Clear()
        try {
            if ($Full) { [void](Invoke-StartupSequence -FullCheck) }
            else { [void](Invoke-StartupSequence -OpenBrowser) }
            [void](Save-Results)
        } finally { Set-Busy $false }
        Update-Summary
        if ($script:G.List.Items.Count -gt 3) { foreach ($row in $script:G.List.Items) { if ([int]$row.Tag -eq 4) { $row.Selected = $true } } }
    }
    # DSS 4.1.8 not installed and no installer chosen: red pop-up with the same locate dialog, then test 3 again
    function Invoke-InstallerCheckGui {
        if($Cfg.AllowDssDownload -and $Cfg.PackageUrl){return}
        $d3 = $ByNo[3]
        if (-not $d3.Tested -or $d3.R.Status -notin 'FAIL', 'SKIP' -or -not $d3.Last.NotInstalled) { return }
        if (Find-DssPackageSource) { return }
        if ($script:PkgAsked) { return }      # already asked at the start; 'Locate installer' or Fix will ask again
        $res = Show-PackageDialog "DigitalSignerService $($Cfg.DssVersion) is NOT INSTALLED in this system - select the installer (zip / msi / folder)"
        if ($res -eq 'ok') {
            Set-Busy $true; Invoke-AllTests @(3); [void](Save-Results); Set-Busy $false; Update-Summary
            foreach ($row in $script:G.List.Items) { if ([int]$row.Tag -eq 3) { $row.Selected = $true } }; Show-Detail
        }
    }
    # step 9: after the dashboard - fix ALL, choose the rows, or not now
    function Show-InitialPendingReview {
        if($script:InitialReviewShown){return}
        $script:InitialReviewShown=$true
        if(@(Get-Fixable).Count){Show-FixChoice}
    }
    function Show-FixChoice {
        $fx = @(Get-Fixable); if (-not $fx.Count) { return }
        $selected=@($script:G.List.CheckedItems | ForEach-Object {[int]$_.Tag})
        if($selected.Count){$fx=@($fx | Where-Object {$selected -contains $_.No})}
        # Review is display-only: downloads and mapping start only after Apply.
        $C = $script:GC
        $d = New-Object Windows.Forms.Form
        $d.Text = 'Review / Pending fixes - no changes until Apply'; $d.Size = New-Object Drawing.Size(780, (250 + 20 * [Math]::Min($fx.Count, 10)))
        $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
        $d.Font = (New-UiFont 'Segoe UI' 9.5); $d.BackColor = [Drawing.Color]::White
        $hd = New-Object Windows.Forms.Label; $hd.UseMnemonic = $false; $hd.AutoSize = $false; $hd.Location = New-Object Drawing.Point(18, 12); $hd.Size = New-Object Drawing.Size(730, 26)
        $hd.Font = (New-UiFont 'Segoe UI Semibold' 11); $hd.Text = "$($fx.Count) item(s) on the dashboard can be fixed:"
        $lst = New-Object Windows.Forms.TextBox; $lst.Multiline = $true; $lst.ReadOnly = $true; $lst.ScrollBars = 'Vertical'
        $lst.Location = New-Object Drawing.Point(18, 42); $lst.Size = New-Object Drawing.Size(730, (40 + 20 * [Math]::Min($fx.Count, 10))); $lst.Font = (New-UiFont 'Consolas' 9)
        $lst.Text = (($fx | ForEach-Object { "[$($_.DisplayNo)] $($_.Title)  ($(Get-Label $_.R.Status))`r`n      -> $($_.Plan)" }) -join "`r`n")
        $nt = New-Object Windows.Forms.Label; $nt.UseMnemonic = $false; $nt.AutoSize = $false; $nt.Size = New-Object Drawing.Size(730, 38)
        $nt.Location = New-Object Drawing.Point(18, ($lst.Top + $lst.Height + 8)); $nt.ForeColor = $C.Mute
        $nt.Text = 'No DSS installation snapshot is created. Existing PATH/hosts repair safeguards remain.' + $(if (-not $IsAdmin) { ' Reopen Windows PowerShell as Administrator before applying repairs.' } else { '' })
        $y = $nt.Top + $nt.Height + 8
        $ba = New-Object Windows.Forms.Button; $ba.Text = "Apply listed ($($fx.Count))"; $ba.Location = New-Object Drawing.Point(18, $y); $ba.Size = New-Object Drawing.Size(150, 36)
        $ba.BackColor = [Drawing.Color]::FromArgb(255, 221, 0); $ba.UseVisualStyleBackColor = $false; $ba.Font = (New-UiFont 'Segoe UI Semibold' 10)
        $bs = New-Object Windows.Forms.Button; $bs.Text = 'Select items ...'; $bs.Location = New-Object Drawing.Point(176, $y); $bs.Size = New-Object Drawing.Size(150, 36)
        $bn = New-Object Windows.Forms.Button; $bn.Text = 'Cancel fixes'; $bn.Location = New-Object Drawing.Point(334, $y); $bn.Size = New-Object Drawing.Size(110, 36)
        $d.Controls.AddRange(@($hd, $lst, $nt, $ba, $bs, $bn))
        $script:FixDlg = @{ Form = $d; Result = 'none' }
        $ba.Add_Click({ Invoke-UiSafe { $script:FixDlg.Result = 'all'; $script:FixDlg.Form.Close() } })
        $bs.Add_Click({ Invoke-UiSafe { $script:FixDlg.Result = 'select'; $script:FixDlg.Form.Close() } })
        $bn.Add_Click({ Invoke-UiSafe { $script:FixDlg.Result = 'none'; $script:FixDlg.Form.Close() } })
        $d.AcceptButton = $bn; $d.CancelButton = $bn
        [void]$d.ShowDialog($script:G.Form)
        switch ($script:FixDlg.Result) {
            'all'    { $script:ReviewApproved=$true; try {Invoke-GuiFix (@($fx | ForEach-Object { $_.No })) -NoAsk} finally {$script:ReviewApproved=$false} }
            'select' {
                $script:G.Sub.Text = "Tick the rows you want fixed (untick the others), then click 'Review / Pending fixes'."
                $script:G.BFix.BackColor = [Drawing.Color]::FromArgb(255, 221, 0); $script:G.BFix.UseVisualStyleBackColor = $false
            }
            default  { $script:G.Sub.Text = "Nothing was changed. Tick rows and click 'Review / Pending fixes' whenever you are ready." }
        }
    }
    function Invoke-GuiFix([int[]]$nos, [switch]$NoAsk) {
        $G = $script:G
        if (-not $NoAsk) {
            $msg = "The tool will make these changes on this PC:`r`n`r`n"
            foreach ($n in $nos) { $msg += "[$($ByNo[$n].DisplayNo)] $($ByNo[$n].Title)`r`n      -> $($ByNo[$n].Plan)`r`n" }
            $msg += "`r`nNo DSS installation snapshot is created. Existing PATH/hosts repair safeguards remain."
            if (-not $IsAdmin) { $msg += "`r`n`r`nThis needs administrator rights: Reopen Windows PowerShell as Administrator before applying repairs." }
            $msg += "`r`n`r`nContinue?"
            if ([Windows.Forms.MessageBox]::Show($script:G.Form,$msg, 'Permission to fix', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question) -ne 'Yes') { return }
        }
        if (-not $IsAdmin) {
            if (Request-Elevation $nos 'fix') { $G.Form.Close() }
            else { [void][Windows.Forms.MessageBox]::Show($script:G.Form,'Administrator permission was not given - nothing was changed.', 'Fix', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) }
            return
        }
        foreach ($d in (Get-Failed)) { if ($nos -notcontains $d.No) { $d.R.Status = 'SKIP' } }
        $script:CancelRequested=$false; $script:RepairRunning=$true
        try {
            Set-Busy $true; $G.LogMode = $true; $G.Txt.Clear(); $G.Sub.Text = 'Applying reviewed fixes. Cancel remaining fixes stops the queue after the current operation.'
            Invoke-Fixes $nos
            $script:RepairRunning=$false; $G.BCancel.Enabled=$false
            Say ''; Say 'Testing again ...' 'White'
            [void](Invoke-StartupSequence -FullCheck); [void](Save-Results)
        } finally {$script:RepairRunning=$false; Set-Busy $false; Update-Summary}
        if($script:CancelRequested){$G.Sub.Text='Remaining fixes cancelled. Completed work was rechecked; review pending items when ready.';return}
        Invoke-InstallerCheckGui
        $fails = @(Get-Failed)
        if ($Results['4'].Status -in 'OK', 'FIXED', 'WARN') {
            $q = $(if ($fails.Count) { "$($fails.Count) item(s) still need attention (see red rows).`r`n`r`n" } else { "Done - isLive: $($Results['4'].Value)`r`n`r`n" }) + "Open the isLive page in Chrome / Edge / Firefox to see 'success'?`r`n(Restart a browser first if a browser setting was changed.)"
            if ([Windows.Forms.MessageBox]::Show($script:G.Form,$q, 'Done', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information) -eq 'Yes') { Stop-Flash; [void](Open-InBrowsers) } else { Start-Flash }
        } else { [void][Windows.Forms.MessageBox]::Show($script:G.Form,"$($fails.Count) item(s) still need attention. Click a red row to see what to do.", 'Done', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) }
    }

    # ---- events
    $lv.Add_ItemCheck({ param($s, $e) $d = $ByNo[[int]$s.Items[$e.Index].Tag]; if (-not ($d.R.Status -in 'FAIL', 'SKIP' -or ($d.R.Status -eq 'WARN' -and $d.R.Fixable))) { $e.NewValue = 'Unchecked' } })
    $lv.Add_SelectedIndexChanged({ Invoke-UiSafe { Show-Detail } })
    $G.BTest.Add_Click({ Invoke-UiSafe { Invoke-GuiTest -Full; Show-Detail; Show-InitialPendingReview } })
    $G.BCertificate.Add_Click({ Invoke-UiSafe { Show-SignerCertificateHelp -UseGui } })
    $G.BJavaUpdate.Add_Click({ Invoke-UiSafe {
        if (-not $IsAdmin) { [void][Windows.Forms.MessageBox]::Show($script:G.Form,'Reopen this tool in an Administrator PowerShell session and select Update Java.', 'Optional Java update'); return }
        if ([Windows.Forms.MessageBox]::Show($script:G.Form,$script:JavaUpdateOffer.Text + "`r`nInstall this optional update?", 'Optional Java update', [Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') { return }
        Set-Busy $true
        try { [void](Invoke-OptionalJavaUpdate -Confirmed); Invoke-GuiTest -Full; Show-Detail }
        finally { Set-Busy $false }
    } })
    $f.Add_FormClosed({ $script:UiJavaOffer = $null; $script:G.JavaTimer.Stop(); $script:G.JavaTimer.Dispose(); $script:G.Flash.Stop(); $script:G.Flash.Dispose() })
    $G.BCancel.Add_Click({ Invoke-UiSafe {
        $script:CancelRequested=$true; $script:G.BCancel.Enabled=$false
        $script:G.Stat.Text='Cancel requested. The current operation will finish; remaining fixes will be skipped.'
        Write-DscEvent 'Info' 'Remaining repairs cancelled by user' @{}
    } })
    $f.Add_FormClosing({ param($sender,$eventArgs)
        if($script:G.Busy){$eventArgs.Cancel=$true;$script:G.Stat.Text='An operation is active. Use Cancel remaining fixes, or wait for checks to finish.'}
    })
    $G.BClose.Add_Click({ Invoke-UiSafe { $script:G.Form.Close() } })
    $G.BReport.Add_Click({ Invoke-UiSafe { $rp = Save-Results; Start-Process $rp } })
    $G.BGitHub.Add_Click({ Invoke-UiSafe { Save-DscSession $Results; Show-DscGitHubReport -UseGui } })
    $G.BImprove.Add_Click({ Invoke-UiSafe { Save-DscSession $Results; Show-DscGitHubReport -Kind Improvement -UseGui } })
    function Invoke-DssInstallAndContinueGui {
        Set-Busy $true; $script:G.LogMode=$true
        try {
            $installed=Start-DssInstallRequest
            if ($installed) {
                $script:G.Sub.Text='DSS installation validated. Continuing the ordered checks ...'
                Invoke-GuiTest -Full; Show-Detail
            } elseif ($script:DssInstallOutcome -ne 'Declined') {
                [void][Windows.Forms.MessageBox]::Show($script:G.Form,$script:DssPackageFailure + "`r`n`r`nSession logs: " + $script:DscSessionDirectory, 'DSS download / installation failed', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
            }
        } finally { Set-Busy $false; Update-Summary; [void](Save-Results) }
    }
    $G.BLocate.Add_Click({ Invoke-UiSafe {
        if($Cfg.AllowDssDownload -and $Cfg.PackageUrl){
            Invoke-DssInstallAndContinueGui
            return
        }
        $res = Show-PackageDialog
        if ($res -eq 'exit') { return }
        if (-not ($Defs | Where-Object { $_.Tested })) {
            # nothing tested yet: same as the start - ask to perform the check
            Invoke-GuiTest; Show-Detail
        } else {
            Set-Busy $true; Invoke-AllTests @(3); [void](Save-Results); Set-Busy $false; Update-Summary
            foreach ($row in $script:G.List.Items) { if ([int]$row.Tag -eq 3) { $row.Selected = $true } }
        }
        Show-Detail
    } })
    $G.BOpen.Add_Click({ Invoke-UiSafe {
        if ($Results['4'].Status -notin 'OK', 'FIXED') {
            if ([Windows.Forms.MessageBox]::Show($script:G.Form,"isLive is not OK yet - the browsers will show an error.`r`nOpen anyway?", 'Open isLive', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question) -ne 'Yes') { return }
        }
        Stop-Flash
        $o = Open-InBrowsers
        [void][Windows.Forms.MessageBox]::Show($script:G.Form,"$($o.Text -replace '   \|   ', "`r`n")`r`n`r`nThe page must show:  success.  DSC Signer Service version : $($Cfg.DssVersion)`r`nAn expiry-only alert may be accepted for this signer. Use Browser exception help where needed.", 'DSC isLive Service Test-Check', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
    } })
    $G.BPack.Add_Click({ Invoke-UiSafe {
        if ([Windows.Forms.MessageBox]::Show($script:G.Form,"Create ONE file (about 100 MB) that contains this tool and the DigitalSignerService $($Cfg.DssVersion) installer?`r`nIt will be saved next to this tool.", 'Build single-file tool', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question) -ne 'Yes') { return }
        if (-not (Find-DssPackageSource)) { if (-not (& $script:RequestPackage)) { return } }
        Set-Busy $true; $script:G.LogMode = $true; $out = Build-PortableTool; Set-Busy $false
        if ($out) { [void][Windows.Forms.MessageBox]::Show($script:G.Form,"Created:`r`n$out`r`n`r`nCopy this one file to any PC and double-click it - the installer is inside.", 'Build single-file tool', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) }
    } })
    $G.BFix.Add_Click({ Invoke-UiSafe {
        Set-Busy $true
        try { Show-FixChoice } finally { Set-Busy $false; Update-Summary }
    } })
    function Show-PackageDialog([string]$Reason = '', [switch]$Start) {
        # one dialog for every place the installer is needed: start, 'Locate installer', DSS not installed, Fix
        $C = $script:GC
        $d = New-Object Windows.Forms.Form
        $d.Text = $(if ($Start) { "Step 2 - DigitalSignerService $($Cfg.DssVersion) installer" } else { "Locate DigitalSignerService $($Cfg.DssVersion) installer" })
        $d.Size = New-Object Drawing.Size(760, 300)
        $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
        $d.Font = (New-UiFont 'Segoe UI' 9.5); $d.BackColor = [Drawing.Color]::White
        $l1 = New-Object Windows.Forms.Label; $l1.UseMnemonic = $false; $l1.AutoSize = $false; $l1.Location = New-Object Drawing.Point(18, 14); $l1.Size = New-Object Drawing.Size(710, 40)
        $l1.Text = "Select the DigitalSignerService $($Cfg.DssVersion) installer: the ZIP, the MSI, or the folder that contains it. It is only used if the service has to be (re)installed."
        $tb = New-Object Windows.Forms.TextBox; $tb.Location = New-Object Drawing.Point(18, 62); $tb.Size = New-Object Drawing.Size(710, 26); $tb.Text = (Get-DefaultPackagePath)
        $b1 = New-Object Windows.Forms.Button; $b1.Text = 'Browse ZIP / MSI ...'; $b1.Location = New-Object Drawing.Point(18, 98); $b1.Size = New-Object Drawing.Size(160, 32)
        $b2 = New-Object Windows.Forms.Button; $b2.Text = 'Browse folder ...'; $b2.Location = New-Object Drawing.Point(186, 98); $b2.Size = New-Object Drawing.Size(150, 32)
        $b3 = New-Object Windows.Forms.Button; $b3.Text = 'Validate'; $b3.Location = New-Object Drawing.Point(344, 98); $b3.Size = New-Object Drawing.Size(100, 32)
        $st = New-Object Windows.Forms.Label; $st.UseMnemonic = $false; $st.AutoSize = $false; $st.Location = New-Object Drawing.Point(18, 140); $st.Size = New-Object Drawing.Size(710, 48)
        $st.Font = (New-UiFont 'Segoe UI Semibold' 10)
        $ok = New-Object Windows.Forms.Button; $ok.Text = 'Continue'; $ok.Location = New-Object Drawing.Point(408, 206); $ok.Size = New-Object Drawing.Size(120, 34)
        $sk = New-Object Windows.Forms.Button; $sk.Text = 'Skip installer'; $sk.Location = New-Object Drawing.Point(536, 206); $sk.Size = New-Object Drawing.Size(110, 34)
        $cx = New-Object Windows.Forms.Button; $cx.Text = 'Exit'; $cx.Location = New-Object Drawing.Point(654, 206); $cx.Size = New-Object Drawing.Size(74, 34)
        $d.Controls.AddRange(@($l1, $tb, $b1, $b2, $b3, $st, $ok, $sk, $cx))
        if (-not $Start) { $cx.Text = 'Cancel' }
        if ($Reason) {
            $rl = New-Object Windows.Forms.Label; $rl.UseMnemonic = $false; $rl.AutoSize = $false; $rl.Dock = 'Top'; $rl.Height = 46
            $rl.Text = "  $Reason"; $rl.TextAlign = 'MiddleLeft'; $rl.ForeColor = [Drawing.Color]::White; $rl.BackColor = $C.Bad
            $rl.Font = (New-UiFont 'Segoe UI Semibold' 10.5)
            $d.Height += 46
            foreach ($ctl in $d.Controls) { $ctl.Top += 46 }
            $d.Controls.Add($rl)
        }
        $script:PkgDlg = @{ Form = $d; Tb = $tb; St = $st; Ok = $ok; Valid = $false; Result = 'exit' }
        $validate = {
            $PD = $script:PkgDlg; $C = $script:GC; $p = $PD.Tb.Text.Trim()
            if ($p -eq '(built into this tool)') { $PD.Valid = $true; $PD.St.Text = 'VALID - installer built into this tool'; $PD.St.ForeColor = $C.Ok; $PD.Ok.Enabled = $true; return }
            try { $v = Test-PackageValid $p } catch { Write-DscError $_ 'Caught exception'; $v = @{ Ok = $false; Text = "Could not check this location: $($_.Exception.Message)" } }
            $PD.Valid = $v.Ok; $PD.Ok.Enabled = $v.Ok
            if ($v.Ok) { $PD.St.Text = $v.Text; $PD.St.ForeColor = $C.Ok } else { $PD.St.Text = "NOT VALID - $($v.Text)"; $PD.St.ForeColor = $C.Bad }
        }
        $script:PkgValidate = $validate
        $b1.Add_Click({ Invoke-UiSafe { $p = Show-PickPackage 'file'; if ($p) { $script:PkgDlg.Tb.Text = $p; & $script:PkgValidate } } })
        $b2.Add_Click({ Invoke-UiSafe { $p = Show-PickPackage 'folder'; if ($p) { $script:PkgDlg.Tb.Text = $p; & $script:PkgValidate } } })
        $b3.Add_Click({ Invoke-UiSafe { & $script:PkgValidate } })
        $tb.Add_Leave({ & $script:PkgValidate })
        $ok.Add_Click({ Invoke-UiSafe { $script:PkgDlg.Result = 'ok'; $script:PkgDlg.Form.Close() } })
        $sk.Add_Click({ Invoke-UiSafe { $script:PkgDlg.Result = 'skip'; $script:PkgDlg.Form.Close() } })
        $cx.Add_Click({ Invoke-UiSafe { $script:PkgDlg.Result = 'exit'; $script:PkgDlg.Form.Close() } })
        $ok.Enabled = $false
        if ($tb.Text) { & $validate } else { $st.Text = "No installer found automatically - click 'Browse ZIP / MSI' or 'Browse folder'."; $st.ForeColor = $C.Warn }
        $d.AcceptButton = $ok
        [void]$d.ShowDialog($script:G.Form)
        $res = $script:PkgDlg.Result
        if ($res -eq 'ok') {
            $p = $script:PkgDlg.Tb.Text.Trim()
            if ($p -ne '(built into this tool)') { [void](Set-PackageOverride $p -Quiet) } else { $script:PkgSkipped = $false }
            Add-Detail $ByNo[3].R "Installer selected: $($script:PkgDlg.St.Text)"
        } elseif ($res -eq 'skip') { $script:PkgSkipped = $true; $script:PkgOverride = $null; $script:PkgMsi = $null; Add-Detail $ByNo[3].R 'Installer skipped by user' }
        return $res
    }

    $f.Add_Shown({ Invoke-UiSafe {
        try { $script:G.Split.SplitterDistance = [int]($script:G.Split.Height * 0.52) } catch { Write-DscError $_ 'Caught exception';}
        $hand = @(); if ($script:Handoff) { $hand = @($script:Handoff.fix | ForEach-Object { [int]$_ }) }
        if ($hand.Count) {
            $script:G.Sub.Text = "Reopened as administrator to fix: $($hand -join ', ') - testing again first ..."
            Invoke-GuiTest -Full
            $todo = @(Get-Fixable | Where-Object { $hand -contains $_.No } | ForEach-Object { $_.No })
            if ($todo.Count) { $script:G.Sub.Text="Diagnostics complete. Review / Pending fixes to continue after elevation." }
            else { [void][Windows.Forms.MessageBox]::Show($script:G.Form,'Nothing left to fix - it already works.', 'Fix', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) }
        } else {
            $script:G.Sub.Text = 'Step 1: opening isLive; expiry-only alerts are warnings. Continuing the ordered checks ...'
            Invoke-GuiTest
            Show-Detail
            # Pending repairs are presented together after the first complete diagnostic run.
        }
        Show-Detail
        Show-InitialPendingReview
    } })
    [void]$f.ShowDialog()
}


    if ($Mode -eq 'gui') { Start-Gui } else { Start-Console }
    } finally { Save-DscSession $Results }
}
function Invoke-DscSelection([string]$Selection) {
    try { Invoke-DscNative $Selection }
    catch { Write-DscError $_ 'Caught exception';
        Write-Host ('Digital Signing Service 4.1.8 Troubleshooter ( for E-Office ) stopped: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'If Trellix or organization policy blocked an action, stop here and share the detection with IT. This tool does not change antivirus settings.' -ForegroundColor Yellow
    }
}
function Show-DscMenu {
    $interactive = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected
    $width = 94
    if ($interactive) {
        try {
            $width = [Math]::Max(12, [Math]::Min(94, $Host.UI.RawUI.WindowSize.Width - 1))
            Clear-Host
        } catch { }
    }
    $inside = $width - 4
    $rule = '+' + ('-' * ($width - 2)) + '+'
    function Write-MenuRow([string]$Text = '', [ConsoleColor]$Color = 'Gray', [switch]$Bold) {
        $rowPrefix = ''; $rowSuffix = ''
        if ($Bold -and $interactive -and $Host.UI.SupportsVirtualTerminal) {
            $rowPrefix = [string][char]27 + '[1m'
            $rowSuffix = [string][char]27 + '[22m'
        }
        if (-not $Text.Length) {
            Write-Host ('| ' + (' ' * $inside) + ' |') -ForegroundColor $Color
            return
        }
        while ($Text.Length -gt $inside) {
            $split = $Text.LastIndexOf(' ', $inside)
            if ($split -lt 1) { $split = $inside }
            Write-Host ($rowPrefix + '| ' + $Text.Substring(0, $split).PadRight($inside) + ' |' + $rowSuffix) -ForegroundColor $Color
            $Text = $Text.Substring($split).TrimStart()
        }
        Write-Host ($rowPrefix + '| ' + $Text.PadRight($inside) + ' |' + $rowSuffix) -ForegroundColor $Color
    }
    Write-Host ''
    Write-Host $rule -ForegroundColor Cyan
    Write-MenuRow 'Digital Signing Service 4.1.8 Troubleshooter ( for E-Office )' Yellow -Bold
    Write-MenuRow 'Native PowerShell | Build 2026.10.27.3' White
    Write-MenuRow
    Write-MenuRow 'Developed by Girish Tiwari' Gray
    Write-MenuRow 'Senior Information Technology, Certified Microsoft Engineer' Gray
    Write-Host $rule -ForegroundColor Cyan
    Write-MenuRow
    Write-MenuRow 'Option 1. PowerShell Console Method' Green
    Write-MenuRow
    Write-MenuRow 'Option 2. Windows GUI-New Window Console Method' Cyan
    Write-MenuRow
    Write-MenuRow 'Option 3. Refresh menu' Yellow
    Write-MenuRow
    Write-MenuRow 'Option 4. Exit' Gray
    Write-MenuRow
    Write-Host $rule -ForegroundColor Cyan
    Write-MenuRow 'Checks run first. Review and select repairs before applying.' White
    Write-MenuRow 'Repairs require an Administrator session.' Gray
    Write-MenuRow
    Write-MenuRow ('Session logs: ' + $script:DscSessionDirectory) DarkGray
    Write-Host $rule -ForegroundColor Cyan
    Write-Host ''
}
if ($Mode -ne 'menu') { Invoke-DscSelection $Mode; return }
while ($true) {
    Show-DscMenu
    $menuInstruction = 'Select any one option to proceed further (1-4):'
    Write-Host $menuInstruction -ForegroundColor Black -BackgroundColor Yellow
    $choice = Read-Host 'Choose 1-4'
    switch ($choice) {
        '1' { Invoke-DscSelection 'console' }
        '2' { Invoke-DscSelection 'gui' }
        '3' { continue }
        '4' { return }
        default { Write-Host 'Enter a number from 1 to 4.' -ForegroundColor Yellow }
    }
}
} catch {
    Write-DscError $_ 'Session stopped'
    Write-Host ('Digital Signing Service 4.1.8 Troubleshooter ( for E-Office ) stopped: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    Save-DscSession -State $(if ($script:DscSession.ErrorCount) { 'CompletedWithErrors' } else { 'Completed' })
    Write-Host ('Session logs: ' + $script:DscSessionDirectory)
}
} @args