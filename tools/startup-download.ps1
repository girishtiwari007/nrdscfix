$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
Write-Host 'Downloading troubleshooter...' -ForegroundColor Cyan
$timer=[Diagnostics.Stopwatch]::StartNew()
$client=New-Object Net.WebClient
try {
    $task=$client.DownloadStringTaskAsync('https://raw.githubusercontent.com/girishtiwari007/DSC-FIXER/main/install.ps1')
    while(-not $task.IsCompleted){
        Write-Progress -Activity 'Downloading troubleshooter' -Status ('Elapsed: '+[int]$timer.Elapsed.TotalSeconds+' seconds. Waiting for GitHub...')
        if($timer.Elapsed.TotalSeconds -ge 90){$client.CancelAsync(); throw 'Download timed out after 90 seconds.'}
        Start-Sleep -Milliseconds 250
    }
    $downloaded=$task.GetAwaiter().GetResult()
} catch {
    Write-Host ('Download failed after '+[int]$timer.Elapsed.TotalSeconds+' seconds: '+$_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Retry: open Start-DSS-Online.cmd again, or rerun this command. Check your internet/proxy connection. If blocked by organization policy, contact IT.'
    return
} finally { Write-Progress -Activity 'Downloading troubleshooter' -Completed; $client.Dispose() }
Write-Host ('Downloaded in '+[math]::Round($timer.Elapsed.TotalSeconds,1)+' seconds. Starting...') -ForegroundColor Green
$downloaded | iex
