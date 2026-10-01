param()
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot=Join-Path (Join-Path $project 'data') ('test-maintenance-'+[Guid]::NewGuid().ToString('N'))
$utf8=New-Object Text.UTF8Encoding($false)
# Runs under Windows PowerShell 5.1 and under pwsh on Linux (no $IsLinux on 5.1).
$posix=[IO.Path]::DirectorySeparatorChar -eq '/'
$sep=[string][IO.Path]::DirectorySeparatorChar
function Mode([string]$Path) { return [int][IO.File]::GetUnixFileMode($Path) }
$passed=0
$failed=0
function Check([bool]$Value,[string]$Label) {
    if ($Value) { $script:passed++; Write-Output ('PASS maintenance: '+$Label) }
    else { $script:failed++; Write-Output ('FAIL maintenance: '+$Label) }
}
function InvokeMaintenance($Object) {
    $Object.root=$testRoot
    $requestPath=Join-Path $testRoot ('maintenance-request-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($requestPath,($Object | ConvertTo-Json -Depth 10 -Compress),$utf8)
    try { $output=& (Join-Path $project 'tools/operator_maintenance.ps1') -Request $requestPath; return ($output | ConvertFrom-Json) }
    finally { [IO.File]::Delete($requestPath) }
}
function ReadScalar([string]$Database,[string]$Sql,[string]$Column) {
    $handle=New-Object RoomKitSqlite((Join-Path $testRoot $Database))
    try { return $handle.Query($Sql,@())[0][$Column] } finally { $handle.Dispose() }
}
try {
    if ($posix) {
        # Linux counterpart of protect_data.ps1 for this fixture: data and the test root 700.
        foreach($folder in @((Join-Path $project 'data'),$testRoot)) {
            [void][IO.Directory]::CreateDirectory($folder)
            [IO.File]::SetUnixFileMode($folder,[IO.UnixFileMode]'UserRead,UserWrite,UserExecute')
        }
    } else {
        $ready=& (Join-Path $project 'tools/protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot
        if ($ready -notcontains 'PRIVATE_DATA_READY') { throw 'Private fixture failed' }
    }
    $source=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
    $binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    Add-Type -TypeDefinition $binding.Groups[1].Value
    $accounts=New-Object RoomKitSqlite((Join-Path $testRoot 'accounts.sqlite'))
    try {
        [void]$accounts.Query('CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,user_id TEXT)',@())
        [void]$accounts.Query('CREATE TABLE account_audit(id INTEGER PRIMARY KEY,actor_id TEXT,action TEXT,target_id TEXT,reason TEXT,result TEXT,before_body TEXT,after_body TEXT,created_at INTEGER)',@())
        [void]$accounts.Query('INSERT INTO sessions VALUES (''fixture-token-digest'',''fixture-user'')',@())
        [void]$accounts.Query('PRAGMA user_version=1',@())
    } finally { $accounts.Dispose() }
    $assets=New-Object RoomKitSqlite((Join-Path $testRoot 'assets.sqlite'))
    try {
        [void]$assets.Query('PRAGMA journal_mode=WAL',@())
        [void]$assets.Query('CREATE TABLE asset_states(user_id TEXT,space_id TEXT,body TEXT)',@())
        [void]$assets.Query('INSERT INTO asset_states VALUES (''fixture-user'',''fixture-space'',''{"credits":100}'')',@())
        [void]$assets.Query('PRAGMA user_version=2',@())
    } finally { $assets.Dispose() }
    [IO.File]::WriteAllText((Join-Path $testRoot 'config.json'),'{"marker":"original"}',$utf8)
    [IO.File]::WriteAllText((Join-Path $testRoot 'server.crt'),'fixture-public-cert',$utf8)
    [IO.File]::WriteAllText((Join-Path $testRoot 'server.key'),'fixture-private-key-never-output',$utf8)
    Write-Output ('MAINTENANCE_EVIDENCE_DIR='+$testRoot)
    $metrics=InvokeMaintenance @{op='metrics'}
    Check ($metrics.ok -and $metrics.metrics.data_disk_free_bytes -gt 0 -and $metrics.metrics.data_disk_total_bytes -ge $metrics.metrics.data_disk_free_bytes) 'real data volume metrics'
    Check ($metrics.ok -and $metrics.metrics.system_memory_total_bytes -gt 0 -and $metrics.metrics.system_memory_used_bytes -gt 0) 'real system memory metrics'
    Check ($null -eq $metrics.metrics.system_cpu_percent -or ($metrics.metrics.system_cpu_percent -ge 0 -and $metrics.metrics.system_cpu_percent -le 100)) 'CPU sample is bounded or explicitly unavailable'
    $liveWriter=New-Object RoomKitSqlite((Join-Path $testRoot 'assets.sqlite'))
    try {
        [void]$liveWriter.Query('UPDATE asset_states SET body=''{"credits":100}''',@())
        Check (Test-Path -LiteralPath (Join-Path $testRoot 'assets.sqlite-wal')) 'fixture keeps a real committed WAL database open'
        $backup=InvokeMaintenance @{op='backup.create';automatic=$false;reason='manual fixture'}
    } finally { $liveWriter.Dispose() }
    Check ($backup.ok -and $backup.backup_id -match '^backup-') 'native SQLite online manual backup'
    if (-not $backup.ok) { throw ('Backup failed: '+$backup.code) }
    $backupDir=Join-Path (Join-Path $testRoot 'backups') $backup.backup_id
    Check ((Test-Path -LiteralPath (Join-Path $backupDir 'server.key')) -and (Test-Path -LiteralPath (Join-Path $backupDir 'config.json'))) 'private TLS and operator config included'
    Check ((ConvertTo-Json -InputObject $backup -Depth 12) -notmatch 'fixture-private-key|fixture-token-digest') 'backup response redacts credentials'
    if ($posix) {
        $loose=@(Get-ChildItem -LiteralPath $backupDir -File -Force | Where-Object { (Mode $_.FullName) -ne 384 })
        Check ((Mode (Join-Path $testRoot 'backups')) -eq 448 -and (Mode $backupDir) -eq 448 -and $loose.Count -eq 0 -and (Mode (Join-Path $testRoot 'maintenance-audit.jsonl')) -eq 384 -and (Mode (Join-Path $testRoot 'maintenance.lock')) -eq 384) ('Linux: backup folders 700, backup files, audit and lock 600 (loose: '+$loose.Count+')')
    }
    $listed=InvokeMaintenance @{op='backup.list'}
    $publicBackup=@($listed.backups | Where-Object backup_id -eq $backup.backup_id)[0]
    $actualBytes=0L
    foreach($file in Get-ChildItem -LiteralPath $backupDir -File | Where-Object Name -ne 'manifest.json') { $actualBytes+=$file.Length }
    Check ($listed.ok -and $publicBackup.size_bytes -eq $actualBytes -and $actualBytes -gt 0) 'public backup size equals actual payload bytes without manifest overhead'
    Check (@($publicBackup.PSObject.Properties.Name | Where-Object { $_ -notin @('backup_id','created_at','automatic','kind','size_bytes') }).Count -eq 0 -and (ConvertTo-Json -InputObject $publicBackup -Depth 8) -notmatch 'fixture-private-key|fixture-token-digest|server.key|sqlite|[\\/]') 'backup list exposes only metadata, never paths or private contents'
    $assets=New-Object RoomKitSqlite((Join-Path $testRoot 'assets.sqlite'))
    try { [void]$assets.Query('UPDATE asset_states SET body=''{"credits":999}''',@()) } finally { $assets.Dispose() }
    [IO.File]::WriteAllText((Join-Path $testRoot 'config.json'),'{"marker":"changed"}',$utf8)
    [IO.File]::WriteAllText((Join-Path $testRoot 'host-running.json'),'{}',$utf8)
    $refused=InvokeMaintenance @{op='backup.restore';backup_id=$backup.backup_id;reason='running refusal'}
    Check (-not $refused.ok -and $refused.code -eq 'SERVER_RUNNING') 'restore independently refuses running-host marker'
    Check ((ReadScalar 'assets.sqlite' 'SELECT body FROM asset_states' 'body') -eq '{"credits":999}') 'refused restore preserves assets'
    [IO.File]::Delete((Join-Path $testRoot 'host-running.json'))
    $invalid=InvokeMaintenance @{op='backup.restore';backup_id='..\..\accounts.sqlite';reason='path test'}
    Check (-not $invalid.ok -and $invalid.code -eq 'INVALID_BACKUP_ID') 'arbitrary backup path refused'
    $restore=InvokeMaintenance @{op='backup.restore';backup_id=$backup.backup_id;reason='restore fixture'}
    Check ($restore.ok -and $restore.sessions_revoked) 'stopped restore completes and revokes sessions'
    if (-not $restore.ok) { throw ('Restore failed: '+$restore.code) }
    Check ((ReadScalar 'assets.sqlite' 'SELECT body FROM asset_states' 'body') -eq '{"credits":100}') 'real asset data restored'
    Check ((ReadScalar 'accounts.sqlite' 'SELECT count(*) AS total FROM sessions' 'total') -eq '0') 'all backed-up sessions removed'
    Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'config.json')) -eq '{"marker":"original"}') 'operator config restored'
    Check ((ReadScalar 'accounts.sqlite' 'SELECT count(*) AS total FROM account_audit WHERE action=''backup.restore''' 'total') -eq '1') 'restored account database retains restore audit'
    $previous=Join-Path (Join-Path $testRoot 'backups') $restore.previous_backup_id
    $priorDb=New-Object RoomKitSqlite((Join-Path $previous 'assets.sqlite'))
    try { Check ($priorDb.Query('SELECT body FROM asset_states',@())[0]['body'] -eq '{"credits":999}') 'pre-restore backup preserves previous data' } finally { $priorDb.Dispose() }
    Check (-not (Test-Path -LiteralPath (Join-Path $testRoot 'restore-journal.json'))) 'committed journal and temporary tree finalized'
    $heldConfig=[IO.File]::Open((Join-Path $testRoot 'config.json'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { $busyRestore=InvokeMaintenance @{op='backup.restore';backup_id=$backup.backup_id;reason='file lock fixture'} }
    finally { $heldConfig.Dispose() }
    Check (-not $busyRestore.ok -and $busyRestore.code -eq 'FILES_IN_USE') 'restore refuses an actual externally held file handle'
    Check ((ReadScalar 'assets.sqlite' 'SELECT body FROM asset_states' 'body') -eq '{"credits":100}') 'file-handle refusal preserves live data'
    $corrupt=InvokeMaintenance @{op='backup.create';reason='corruption fixture'}
    $corruptDir=Join-Path (Join-Path $testRoot 'backups') $corrupt.backup_id
    [IO.File]::AppendAllText((Join-Path $corruptDir 'assets.sqlite'),'corruption',$utf8)
    $badRestore=InvokeMaintenance @{op='backup.restore';backup_id=$corrupt.backup_id;reason='corrupt refusal'}
    Check (-not $badRestore.ok -and $badRestore.code -eq 'BACKUP_INTEGRITY_FAILED') 'checksum corruption refused before live replacement'
    Check ((ReadScalar 'assets.sqlite' 'SELECT body FROM asset_states' 'body') -eq '{"credits":100}') 'corrupt restore preserves live data'
    # Test-only interrupted-swap fixture: move original files into the same
    # recovery journal layout used by production and install one partial file.
    $stageId='restore-'+[Guid]::NewGuid().ToString('N')
    $stage=Join-Path $testRoot $stageId
    $prior=Join-Path $stage 'previous'
    [void][IO.Directory]::CreateDirectory($prior)
    $names=@('accounts.sqlite','assets.sqlite','config.json','server.crt','server.key','accounts.sqlite-wal','accounts.sqlite-shm','assets.sqlite-wal','assets.sqlite-shm')
    $original=@{}
    foreach($name in $names) { $original[$name]=[IO.File]::Exists((Join-Path $testRoot $name)) }
    [IO.File]::Move((Join-Path $testRoot 'config.json'),(Join-Path $prior 'config.json'))
    [IO.File]::WriteAllText((Join-Path $testRoot 'config.json'),'{"marker":"partial-swap"}',$utf8)
    $journal=@{format=1;stage_id=$stageId;state='moving';backup_id=$backup.backup_id;previous_backup_id=$restore.previous_backup_id;original=$original}
    [IO.File]::WriteAllText((Join-Path $testRoot 'restore-journal.json'),($journal | ConvertTo-Json -Depth 10 -Compress),$utf8)
    [IO.File]::WriteAllText((Join-Path $testRoot 'host-running.json'),'{}',$utf8)
    $blockedRecovery=InvokeMaintenance @{op='backup.list';reason='active host recovery refusal'}
    Check (-not $blockedRecovery.ok -and $blockedRecovery.code -eq 'SERVER_RUNNING') 'interrupted recovery also refuses running-host marker'
    [IO.File]::Delete((Join-Path $testRoot 'host-running.json'))
    $recovered=InvokeMaintenance @{op='backup.list';reason='recover fixture'}
    Check ($recovered.ok -and -not (Test-Path -LiteralPath (Join-Path $testRoot 'restore-journal.json'))) 'interrupted swap journal recovers using actual previous files'
    Check ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'config.json')) -eq '{"marker":"original"}') 'partial replacement rolls back to original config'
    $audit=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'maintenance-audit.jsonl')
    Check ($audit -match 'prepared' -and $audit -match 'committed' -and $audit -match 'rolled_back' -and $audit -notmatch 'fixture-private-key') 'independent before/after/recovery journal survives restore without secrets'
    $automaticOk=$true
    for($index=0;$index -lt 50;$index++) {
        $automatic=InvokeMaintenance @{op='backup.create';automatic=$true;reason='retention fixture'}
        $automaticOk=$automaticOk -and $automatic.ok
    }
    Check $automaticOk 'fifty real automatic SQLite backups complete'
    $list=InvokeMaintenance @{op='backup.list'}
    Check (@($list.backups | Where-Object automatic).Count -eq 48) 'only forty-eight automatic backups retained'
    Check (@($list.backups | Where-Object { $_.backup_id -eq $backup.backup_id }).Count -eq 1) 'manual backup retained regardless of automatic count'
    Check (@($list.backups | Where-Object { $_.backup_id -eq $restore.previous_backup_id }).Count -eq 1) 'pre-restore backup retained regardless of automatic count'
    $outsideRequest=Join-Path $testRoot 'invalid-root.json'
    [IO.File]::WriteAllText($outsideRequest,(@{op='backup.list';root=$project}|ConvertTo-Json -Compress),$utf8)
    $outside=(& (Join-Path $project 'tools/operator_maintenance.ps1') -Request $outsideRequest) | ConvertFrom-Json
    [IO.File]::Delete($outsideRequest)
    Check (-not $outside.ok -and $outside.code -eq 'INVALID_DATA_PATH') 'project root outside private data subtree refused'
    $junction=Join-Path $testRoot 'reparse-fixture'
    # Windows: an NTFS junction; Linux: a symbolic link to a folder.
    [void](New-Item -ItemType $(if ($posix) {'SymbolicLink'} else {'Junction'}) -Path $junction -Target (Join-Path $testRoot 'backups'))
    $junctionRequest=Join-Path $testRoot 'junction-request.json'
    try {
        [IO.File]::WriteAllText($junctionRequest,(@{op='backup.list';root=$junction}|ConvertTo-Json -Compress),$utf8)
        $reparse=(& (Join-Path $project 'tools/operator_maintenance.ps1') -Request $junctionRequest) | ConvertFrom-Json
        Check (-not $reparse.ok -and $reparse.code -eq 'REPARSE_POINT_REFUSED') $(if ($posix) {'actual symbolic link in data path refused'} else {'actual NTFS junction in data path refused'})
    } finally {
        [IO.File]::Delete($junctionRequest)
        $junctionFull=[IO.Path]::GetFullPath($junction)
        $comparison=if ($posix) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
        if (-not $junctionFull.StartsWith($testRoot+$sep,$comparison) -or -not ((Get-Item -LiteralPath $junctionFull -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Junction cleanup identity mismatch' }
        # Removes the link itself, never the folder it points to.
        if ($posix) { [IO.File]::Delete($junctionFull) } else { [IO.Directory]::Delete($junctionFull,$false) }
    }
    Check (Test-Path -LiteralPath (Join-Path $testRoot 'backups')) 'junction cleanup retains real backup directory'
    Check ((ReadScalar 'accounts.sqlite' 'PRAGMA integrity_check' 'integrity_check') -eq 'ok' -and (ReadScalar 'assets.sqlite' 'PRAGMA integrity_check' 'integrity_check') -eq 'ok') 'both live SQLite databases retain integrity'
} catch { $failed++; Write-Output ('FAIL maintenance: '+$_.Exception.Message) }
Write-Output ('MAINTENANCE_RESULT passed='+$passed+' failed='+$failed)
if ($failed) { exit 1 }
exit 0
