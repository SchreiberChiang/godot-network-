param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$data=Join-Path $project 'data'
$root=''
$lock=$null
$journal=$null
$staging=''
$utf8=New-Object Text.UTF8Encoding($false)
$knownFiles=@('accounts.sqlite','assets.sqlite','config.json','server.crt','server.key')
$swapFiles=$knownFiles+@('accounts.sqlite-wal','accounts.sqlite-shm','assets.sqlite-wal','assets.sqlite-shm')
function Fail([string]$Code) { throw ('MAINTENANCE:'+$Code) }
function SafePath([string]$Path,[string]$Boundary=$root) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $boundaryFull=[IO.Path]::GetFullPath($Boundary).TrimEnd('\','/')
    if ($full -ne $boundaryFull -and -not $full.StartsWith($boundaryFull+'\',[StringComparison]::OrdinalIgnoreCase)) { Fail 'INVALID_DATA_PATH' }
    $cursor=$full
    while ($cursor.Length -ge $boundaryFull.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { Fail 'REPARSE_POINT_REFUSED' }
        }
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function AtomicJson([string]$Path,$Object) {
    $destination=SafePath $Path
    $temp=$destination+'.tmp'
    [void](SafePath $temp)
    $bytes=$utf8.GetBytes((ConvertTo-Json -InputObject $Object -Compress -Depth 16))
    $file=[IO.File]::Open($temp,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $file.Write($bytes,0,$bytes.Length); $file.Flush($true) } finally { $file.Dispose() }
    if ([IO.File]::Exists($destination)) { [IO.File]::Replace($temp,$destination,[System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temp,$destination) }
}
function ReadJson([string]$Path) {
    $path=SafePath $Path
    if (-not [IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -gt 65536) { Fail 'INVALID_BACKUP' }
    return (Get-Content -Encoding UTF8 -Raw -LiteralPath $path | ConvertFrom-Json)
}
function InitializeSqlite {
    if ('RoomKitSqlite' -as [type]) { return }
    $source=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $PSScriptRoot 'sqlite_store.ps1')
    $binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    if (-not $binding.Success) { Fail 'STORAGE_UNAVAILABLE' }
    Add-Type -TypeDefinition $binding.Groups[1].Value
}
function CheckDatabase([string]$Path,[string]$Name) {
    [void](SafePath $Path)
    if (-not [IO.File]::Exists($Path)) { Fail 'BACKUP_NOT_READY' }
    $db=New-Object RoomKitSqlite($Path)
    try {
        if ($db.Query('PRAGMA integrity_check',@())[0]['integrity_check'] -ne 'ok') { Fail 'BACKUP_INTEGRITY_FAILED' }
        $version=$db.Query('PRAGMA user_version',@())[0]['user_version']
        if (($Name -eq 'accounts.sqlite' -and $version -ne '1') -or ($Name -eq 'assets.sqlite' -and $version -ne '2')) { Fail 'BACKUP_VERSION_UNSUPPORTED' }
        if ($Name -eq 'accounts.sqlite') { [void]$db.Query('SELECT token_hash,user_id FROM sessions LIMIT 0',@()); [void]$db.Query('SELECT action FROM account_audit LIMIT 0',@()) }
        else { [void]$db.Query('SELECT body FROM asset_states LIMIT 0',@()) }
    } finally { $db.Dispose() }
}
function Audit([string]$Stage,[string]$BackupId,[string]$BeforeId='', [string]$Code='') {
    $record=@{time=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();op=$requestObject.op;stage=$Stage;backup_id=$BackupId;previous_backup_id=$BeforeId;reason=$reason;code=$Code}
    $path=SafePath (Join-Path $root 'maintenance-audit.jsonl')
    $stream=[IO.File]::Open($path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $bytes=$utf8.GetBytes((ConvertTo-Json -InputObject $record -Compress)+"`n"); $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function BackupManifests {
    $folder=SafePath (Join-Path $root 'backups')
    $list=@()
    if (-not [IO.Directory]::Exists($folder)) { return ,$list }
    foreach($directory in Get-ChildItem -LiteralPath $folder -Directory -Force) {
        if ($directory.Name -cnotmatch '^backup-[0-9]{17}-[a-f0-9]{8}$') { continue }
        [void](SafePath $directory.FullName)
        try {
            $manifest=ReadJson (Join-Path $directory.FullName 'manifest.json')
            if ($manifest.format -ne 1 -or $manifest.backup_id -cne $directory.Name -or $manifest.kind -notin @('manual','automatic','pre_restore') -or $manifest.automatic -isnot [bool] -or ($manifest.automatic -ne ($manifest.kind -eq 'automatic'))) { continue }
            if ($manifest.created_at -isnot [long] -and $manifest.created_at -isnot [int]) { continue }
            if ($manifest.files -isnot [PSCustomObject]) { continue }
            $names=@($manifest.files.PSObject.Properties.Name)
            if ('accounts.sqlite' -notin $names -or 'assets.sqlite' -notin $names -or @($names | Where-Object { $_ -notin $knownFiles }).Count) { continue }
            $valid=$true
            foreach($name in $names) {
                if ($manifest.files.$name.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or [long]$manifest.files.$name.size -lt 0) { $valid=$false }
            }
            if ($valid) { $list+=,$manifest }
        } catch { if ($_.Exception.Message -like '*REPARSE_POINT_REFUSED*') { throw } }
    }
    return ,$list
}
function PublicBackups {
    return @(foreach($item in ((BackupManifests) | Sort-Object created_at,backup_id -Descending)) {
        $bytes=0L
        foreach($entry in $item.files.PSObject.Properties) { $bytes+=[long]$entry.Value.size }
        @{backup_id=$item.backup_id;created_at=[long]$item.created_at;automatic=[bool]$item.automatic;kind=$item.kind;size_bytes=$bytes}
    })
}
function RemovePrivateTree([string]$Directory) {
    # Enumerate, validate, and delete using only native .NET filesystem methods.
    # Never pass enumerated paths to another shell or delete outside this root.
    $path=SafePath $Directory
    if ($path -eq $root) { Fail 'INVALID_DATA_PATH' }
    if (-not [IO.Directory]::Exists($path)) { return }
    foreach($entry in Get-ChildItem -LiteralPath $path -Force) {
        [void](SafePath $entry.FullName)
        if ($entry.PSIsContainer) { RemovePrivateTree $entry.FullName }
        else { [IO.File]::Delete($entry.FullName) }
    }
    [IO.Directory]::Delete($path,$false)
}
function RetainAutomatic {
    $automatic=@((BackupManifests) | Where-Object { $_.automatic -and $_.kind -eq 'automatic' } | Sort-Object created_at,backup_id -Descending)
    foreach($old in ($automatic | Select-Object -Skip 48)) {
        $path=SafePath (Join-Path (Join-Path $root 'backups') $old.backup_id)
        RemovePrivateTree $path
    }
}
function CreateBackup([string]$Kind) {
    foreach($name in @('accounts.sqlite','assets.sqlite')) { CheckDatabase (SafePath (Join-Path $root $name)) $name }
    $backups=SafePath (Join-Path $root 'backups')
    [void][IO.Directory]::CreateDirectory($backups)
    $id='backup-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
    $stage=SafePath (Join-Path $backups ('.pending-'+[Guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($stage)
    $files=@{}
    try {
        foreach($name in $knownFiles) {
            $source=SafePath (Join-Path $root $name)
            if (-not [IO.File]::Exists($source)) { continue }
            $target=SafePath (Join-Path $stage $name)
            if ($name.EndsWith('.sqlite')) {
                $db=New-Object RoomKitSqlite($source)
                try { $db.Backup($target) } finally { $db.Dispose() }
                CheckDatabase $target $name
            } else { [IO.File]::Copy($source,$target,$false) }
            $files[$name]=@{sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;size=(Get-Item -LiteralPath $target).Length}
        }
        $manifest=@{format=1;backup_id=$id;created_at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();automatic=($Kind -eq 'automatic');kind=$Kind;files=$files}
        AtomicJson (Join-Path $stage 'manifest.json') $manifest
        [IO.Directory]::Move($stage,(SafePath (Join-Path $backups $id)))
        if ($Kind -eq 'automatic') { RetainAutomatic }
        return $id
    } catch { if ([IO.Directory]::Exists($stage)) { RemovePrivateTree $stage }; throw }
}
function CheckStopped {
    if (Test-Path -LiteralPath (SafePath (Join-Path $root 'host-running.json'))) { Fail 'SERVER_RUNNING' }
}
function RecoverJournal {
    $journalPath=SafePath (Join-Path $root 'restore-journal.json')
    if (-not [IO.File]::Exists($journalPath)) { return }
    CheckStopped
    $saved=ReadJson $journalPath
    if ($saved.format -ne 1 -or $saved.stage_id -cnotmatch '^restore-[a-f0-9]{32}$' -or $saved.state -notin @('moving','committed','rolled_back')) { Fail 'RESTORE_RECOVERY_REQUIRED' }
    $directory=SafePath (Join-Path $root $saved.stage_id)
    $previous=SafePath (Join-Path $directory 'previous')
    if ($saved.original -isnot [PSCustomObject] -or @($saved.original.PSObject.Properties.Name).Count -ne $swapFiles.Count) { Fail 'RESTORE_RECOVERY_REQUIRED' }
    foreach($name in $swapFiles) { if ($saved.original.$name -isnot [bool]) { Fail 'RESTORE_RECOVERY_REQUIRED' } }
    if ($saved.state -eq 'moving') {
        foreach($name in $swapFiles) {
            $target=SafePath (Join-Path $root $name)
            $old=SafePath (Join-Path $previous $name)
            if ([IO.File]::Exists($old)) {
                if ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
                [IO.File]::Move($old,$target)
            } elseif (-not $saved.original.$name) {
                if ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
            } elseif (-not [IO.File]::Exists($target)) { Fail 'RESTORE_RECOVERY_REQUIRED' }
        }
        $saved.state='rolled_back'
        AtomicJson $journalPath $saved
        Audit 'rolled_back' $saved.backup_id $saved.previous_backup_id 'INTERRUPTED_RESTORE'
    }
    if ([IO.Directory]::Exists($directory)) { RemovePrivateTree $directory }
    [IO.File]::Delete($journalPath)
}
function RestoreBackup([string]$Id) {
    CheckStopped
    if ($Id -cnotmatch '^backup-[0-9]{17}-[a-f0-9]{8}$') { Fail 'INVALID_BACKUP_ID' }
    $matches=@((BackupManifests) | Where-Object { $_.backup_id -ceq $Id })
    if ($matches.Count -ne 1) { Fail 'BACKUP_NOT_FOUND' }
    $manifest=$matches[0]
    $backup=SafePath (Join-Path (Join-Path $root 'backups') $Id)
    foreach($name in $manifest.files.PSObject.Properties.Name) {
        $file=SafePath (Join-Path $backup $name)
        if (-not [IO.File]::Exists($file) -or (Get-Item -LiteralPath $file).Length -ne [long]$manifest.files.$name.size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $manifest.files.$name.sha256) { Fail 'BACKUP_INTEGRITY_FAILED' }
    }
    foreach($name in @('accounts.sqlite','assets.sqlite')) { CheckDatabase (Join-Path $backup $name) $name }
    $before=CreateBackup 'pre_restore'
    Audit 'prepared' $Id $before
    CheckStopped
    $stageId='restore-'+[Guid]::NewGuid().ToString('N')
    $stage=SafePath (Join-Path $root $stageId)
    $ready=SafePath (Join-Path $stage 'ready')
    $previous=SafePath (Join-Path $stage 'previous')
    [void][IO.Directory]::CreateDirectory($ready)
    [void][IO.Directory]::CreateDirectory($previous)
    $moving=$false
    $committed=$false
    try {
        foreach($name in $manifest.files.PSObject.Properties.Name) { [IO.File]::Copy((Join-Path $backup $name),(Join-Path $ready $name),$false) }
        $accountDb=New-Object RoomKitSqlite((Join-Path $ready 'accounts.sqlite'))
        try {
            [void]$accountDb.Query('BEGIN IMMEDIATE',@())
            [void]$accountDb.Query('DELETE FROM sessions',@())
            [void]$accountDb.Query('INSERT INTO account_audit (actor_id,action,target_id,reason,result,before_body,after_body,created_at) VALUES (''operator'',''backup.restore'',?,?,''OK'',?,?,?)',@($Id,$reason,('{"backup_id":"'+$before+'"}'),('{"backup_id":"'+$Id+'","sessions_revoked":true}'),[string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
            [void]$accountDb.Query('COMMIT',@())
        } finally { $accountDb.Dispose() }
        foreach($name in @('accounts.sqlite','assets.sqlite')) {
            $live=SafePath (Join-Path $root $name)
            $db=New-Object RoomKitSqlite($live)
            try {
                $checkpoint=$db.Query('PRAGMA wal_checkpoint(TRUNCATE)',@())
                if ([int]$checkpoint[0]['busy'] -ne 0) { Fail 'DATABASE_BUSY' }
            } finally { $db.Dispose() }
        }
        $original=@{}
        foreach($name in $swapFiles) {
            $live=SafePath (Join-Path $root $name)
            if ([IO.Directory]::Exists($live)) { Fail 'FILES_IN_USE' }
            $original[$name]=[IO.File]::Exists($live)
            if ($original[$name]) {
                # Ensure no leftover SQLite/file handles before replacing files.
                try { $probe=[IO.File]::Open($live,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $probe.Dispose() } catch { Fail 'FILES_IN_USE' }
            }
        }
        CheckStopped
        $saved=@{format=1;stage_id=$stageId;state='moving';backup_id=$Id;previous_backup_id=$before;original=$original}
        AtomicJson (Join-Path $root 'restore-journal.json') $saved
        $moving=$true
        foreach($name in $swapFiles) {
            $live=SafePath (Join-Path $root $name)
            if ($original[$name]) { [IO.File]::Move($live,(Join-Path $previous $name)) }
            $replacement=SafePath (Join-Path $ready $name)
            if ([IO.File]::Exists($replacement)) { [IO.File]::Move($replacement,$live) }
        }
        $saved.state='committed'
        AtomicJson (Join-Path $root 'restore-journal.json') $saved
        $committed=$true
        Audit 'committed' $Id $before
        RecoverJournal
        return @{ok=$true;code='';backup_id=$Id;previous_backup_id=$before;sessions_revoked=$true}
    } catch {
        if ($moving -and -not $committed) { RecoverJournal }
        elseif (-not $moving -and [IO.Directory]::Exists($stage)) { RemovePrivateTree $stage }
        Audit 'failed' $Id $before 'RESTORE_FAILED'
        throw
    }
}
function Metrics {
    $metrics=@{system_cpu_percent=$null;system_memory_used_bytes=$null;system_memory_total_bytes=$null;data_disk_free_bytes=$null;data_disk_total_bytes=$null}
    try {
        $os=Get-CimInstance Win32_OperatingSystem
        $metrics.system_memory_total_bytes=[long]$os.TotalVisibleMemorySize*1024
        $metrics.system_memory_used_bytes=([long]$os.TotalVisibleMemorySize-[long]$os.FreePhysicalMemory)*1024
    } catch {}
    try {
        $cpu=@(Get-CimInstance Win32_Processor | Where-Object { $null -ne $_.LoadPercentage })
        if ($cpu.Count) { $metrics.system_cpu_percent=[math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average,1) }
    } catch {}
    try {
        $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($root))
        if ($drive.IsReady) { $metrics.data_disk_free_bytes=$drive.AvailableFreeSpace; $metrics.data_disk_total_bytes=$drive.TotalSize }
    } catch {}
    return $metrics
}
try {
    if (-not (Test-Path -LiteralPath (Join-Path $project 'project.godot'))) { Fail 'INVALID_PROJECT' }
    if ((Get-Item -LiteralPath $Request).Length -gt 8192) { Fail 'INVALID_MAINTENANCE_REQUEST' }
    $requestObject=Get-Content -Encoding UTF8 -Raw -LiteralPath $Request | ConvertFrom-Json
    if ($requestObject -isnot [PSCustomObject] -or $requestObject.op -notin @('metrics','backup.create','backup.list','backup.restore') -or $requestObject.root -isnot [string] -or -not [IO.Path]::IsPathRooted($requestObject.root)) { Fail 'INVALID_MAINTENANCE_REQUEST' }
    $root=SafePath $requestObject.root $data
    if ($root -eq $data -or -not [IO.Directory]::Exists($root)) { Fail 'INVALID_DATA_PATH' }
    [void](SafePath $Request)
    $owner=[IO.Directory]::GetAccessControl($root).GetOwner([Security.Principal.SecurityIdentifier])
    if ($owner -ne [Security.Principal.WindowsIdentity]::GetCurrent().User) { Fail 'PRIVATE_DATA_FAILED' }
    foreach($rule in [IO.Directory]::GetAccessControl($root).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $rule.IdentityReference -ne $owner) { Fail 'PRIVATE_DATA_FAILED' }
    }
    $reason=if ($null -ne $requestObject.PSObject.Properties['reason']) { $requestObject.reason } else { '' }
    if ($reason -isnot [string] -or $reason.Length -gt 256 -or $reason -match '[\x00-\x1f]') { Fail 'INVALID_MAINTENANCE_REQUEST' }
    if ($requestObject.op -eq 'metrics') {
        $result=@{ok=$true;code='';metrics=(Metrics);recovery_required=([IO.File]::Exists((Join-Path $root 'restore-journal.json')))}
    } else {
        InitializeSqlite
        try { $lock=[IO.File]::Open((SafePath (Join-Path $root 'maintenance.lock')),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { Fail 'MAINTENANCE_BUSY' }
        RecoverJournal
        switch ($requestObject.op) {
            'backup.list' { $result=@{ok=$true;code='';backups=@(PublicBackups)} }
            'backup.create' {
                $automatic=$false
                if ($null -ne $requestObject.PSObject.Properties['automatic']) {
                    if ($requestObject.automatic -isnot [bool]) { Fail 'INVALID_MAINTENANCE_REQUEST' }
                    $automatic=$requestObject.automatic
                }
                $kind=if ($automatic) {'automatic'} else {'manual'}
                $id=CreateBackup $kind
                Audit 'created' $id
                $result=@{ok=$true;code='';backup_id=$id;backups=@(PublicBackups)}
            }
            'backup.restore' { $result=RestoreBackup $requestObject.backup_id }
        }
    }
} catch {
    $message=$_.Exception.Message
    $code=if ($message.StartsWith('MAINTENANCE:')) {$message.Substring(12)} else {'MAINTENANCE_UNAVAILABLE'}
    $result=@{ok=$false;code=$code}
} finally { if ($lock) { $lock.Dispose() } }
$json=ConvertTo-Json -InputObject $result -Compress -Depth 12
[regex]::Replace($json,'[^\x00-\x7F]',{ param($match) '\u{0:x4}' -f [int][char]$match.Value })
