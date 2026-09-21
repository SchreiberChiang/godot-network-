param([ValidateSet('verify','status','stop','results','backup')][string]$Operation='status')
$ErrorActionPreference='Stop'
$bundle=$PSScriptRoot
$store=Join-Path $bundle 'data/showcase-results'
if($Operation -eq 'verify') {
    $manifest=Get-Content -Encoding UTF8 -Raw (Join-Path $bundle 'checksums.json') | ConvertFrom-Json
    foreach($entry in $manifest.files) {
        $path=[IO.Path]::GetFullPath((Join-Path $bundle $entry.path))
        if(-not $path.StartsWith($bundle+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path outside package' }
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { throw ('Checksum mismatch: '+$entry.path) }
    }
    Write-Output ('PACKAGE_VERIFY_OK files='+$manifest.files.Count)
    exit 0
}
if($Operation -eq 'stop') {
    if(-not(Test-Path -LiteralPath $store -PathType Container)) { throw 'No managed session data; nothing to stop.' }
    [IO.File]::WriteAllText((Join-Path $store 'stop.request'),'stop')
    Write-Output 'STOP_REQUESTED; the host will ask its own clients and rooms to exit. No PID is killed.'
    exit 0
}
if($Operation -eq 'status') {
    $listener=Get-NetTCPConnection -LocalPort 28290 -State Listen -ErrorAction SilentlyContinue
    Write-Output ('CONTROL_PORT_LISTENING='+[bool]$listener+' (port observation, not proof of process identity)')
    $journal=Join-Path $store 'processes.json'
    if(Test-Path -LiteralPath $journal) {
        $state=Get-Content -Encoding UTF8 -Raw $journal | ConvertFrom-Json
        Write-Output ('JOURNAL_ENTRIES='+@($state.entries.PSObject.Properties).Count+' (may include quarantined previous runs)')
    }
    exit 0
}
if(-not(Test-Path -LiteralPath (Join-Path $store 'results.sqlite'))) { throw 'No interactive result database yet; finish a turn-based round first.' }
$request=Join-Path $store ('operator-'+[Guid]::NewGuid().ToString('N')+'.json')
try {
    $job=@{op= $(if($Operation -eq 'backup') {'backup'} else {'inspect'})}
    if($Operation -eq 'backup') { $job.destination=Join-Path $store ('backup-'+[Guid]::NewGuid().ToString('N')+'.sqlite') }
    [IO.File]::WriteAllText($request,($job | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bundle 'tools/sqlite_store.ps1') -Database (Join-Path $store 'results.sqlite') -Request $request
    if($LASTEXITCODE -ne 0) { throw 'SQLite operation failed' }
} finally { if(Test-Path -LiteralPath $request) { Remove-Item -LiteralPath $request } }
