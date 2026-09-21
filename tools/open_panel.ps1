param([int]$ExpectedPid=0,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$path=Join-Path $root 'run/panel-access.json'
$deadline=[DateTime]::UtcNow.AddSeconds(30)
while([DateTime]::UtcNow -lt $deadline) {
    if(Test-Path -LiteralPath $path) {
        try {
            $access=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if($access.url -notmatch '^http://127\.0\.0\.1:[0-9]+$' -or $access.token -notmatch '^[0-9a-f]{64}$' -or ($ExpectedPid -ne 0 -and $access.pid -ne $ExpectedPid)) { throw 'Stale panel descriptor' }
            $state=Invoke-RestMethod -Uri ($access.url+'/api/status') -Headers @{Authorization=('Bearer '+$access.token)} -TimeoutSec 2
            if($state.version -ne 1 -or $state.host.pid -ne $access.pid) { throw 'Panel identity mismatch' }
            if(-not $NoBrowser) { Start-Process ($access.url+'/#'+$access.token) }
            Write-Output 'PANEL_READY (local access URL is kept out of logs)'
            return
        } catch { }
    }
    Start-Sleep -Milliseconds 200
}
throw 'Dashboard did not become ready. Inspect logs/play-stderr.log and port 28291.'
