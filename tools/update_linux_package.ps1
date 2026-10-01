# Linux-only, conservative offline migration. Every output is a fixed code or
# non-secret deployment metadata. Never prints a database/request/certificate.
# Keep this companion beside update_linux_package.sh. Existing package launch
# entries remain independent; the update tool never launches or kills services.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$script:journal=$null
$script:journalPath=''
$script:lock=$null
$script:staging=''
$script:published=$false
$utf8=[Text.UTF8Encoding]::new($false)
function Fail([string]$Code) { throw ('UPDATE:'+ $Code) }
function ReadJson([string]$Path) {
    [void](Safe $Path)
    if(-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -gt 16777216){Fail 'JSON_INVALID'}
    Regular $Path
    return [IO.File]::ReadAllText($Path,$utf8) | ConvertFrom-Json -AsHashtable -DateKind String
}
function Safe([string]$Path) {
    if(-not $Path.StartsWith('/') -or $Path.Contains('\') -or $Path.Split('/') -contains '..' -or $Path.Contains([char]0)){Fail 'PATH_INVALID'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('/')
    if($full -eq ''){Fail 'PATH_INVALID'}
    $cursor=$full
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkTarget)){Fail 'LINK_REFUSED'}
        $next=[IO.Path]::GetDirectoryName($cursor)
        if($next -eq $cursor){break}
        $cursor=$next
    }
    return $full
}
function Child([string]$Root,[string]$Relative) {
    if($Relative -eq '' -or $Relative.StartsWith('/') -or $Relative.Contains('\') -or $Relative.Split('/') -contains '..'){Fail 'PATH_INVALID'}
    $full=Safe ($Root+'/'+$Relative)
    if(-not $full.StartsWith($Root+'/',[StringComparison]::Ordinal)){Fail 'PATH_OUTSIDE'}
    return $full
}
function Private([string]$Path,[bool]$Directory) {
    [void](Safe $Path)
    $mode=if($Directory){[IO.UnixFileMode]'UserRead,UserWrite,UserExecute'}else{[IO.UnixFileMode]'UserRead,UserWrite'}
    [IO.File]::SetUnixFileMode($Path,$mode)
    if([IO.File]::GetUnixFileMode($Path) -ne $mode){Fail 'PRIVATE_PATH_FAILED'}
}
function Folder([string]$Path) {
    [void](Safe $Path)
    [void][IO.Directory]::CreateDirectory($Path)
    Private $Path $true
}
function Atomic([string]$Path,$Object) {
    [void](Safe $Path)
    $temp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
    $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { Private $temp $false; $bytes=$utf8.GetBytes(($Object|ConvertTo-Json -Depth 32 -Compress)+"`n");$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Move($temp,$Path,$true)
    Private $Path $false
}
function Regular([string]$Path) {
    # FIFO/socket objects look like FileInfo to .NET. Never hash or read them.
    # Native arguments are passed directly; no shell interprets path contents.
    $type=& stat --format=%F -- $Path
    if($LASTEXITCODE -ne 0 -or $type -notin @('regular file','regular empty file')){Fail 'SPECIAL_FILE_REFUSED'}
}
function Entries([string]$Root) {
    [void](Safe $Root)
    $stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Root)
    $files=[Collections.Generic.List[string]]::new()
    while($stack.Count){
        $directory=$stack.Pop()
        foreach($item in Get-ChildItem -LiteralPath $directory -Force){
            [void](Safe $item.FullName)
            if($item.PSIsContainer){$stack.Push($item.FullName)}
            elseif($item -is [IO.FileInfo]){
                # FIFOs/sockets also look like FileInfo to .NET; hashing one may
                # wait forever. Ask stat directly, without shell interpolation.
                Regular $item.FullName
                $files.Add($item.FullName.Substring($Root.Length+1))
            }
            else{Fail 'SPECIAL_FILE_REFUSED'}
        }
    }
    return @($files | Sort-Object -CaseSensitive -Culture '')
}
function Digest([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Fingerprints([string]$Root) {
    # Linux permits foo and Foo simultaneously. The default PowerShell
    # hashtable would collapse them and miss changes in one of those files.
    $result=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach($name in Entries $Root){$result[$name]=Digest (Child $Root $name)}
    return $result
}
function EqualMaps($A,$B) {
    if($A.Count -ne $B.Count){return $false}
    foreach($key in $A.Keys){if(-not $B.Contains($key) -or $A[$key] -cne $B[$key]){return $false}}
    return $true
}
function AssertStopped([string]$Package) {
    # Inspect command-line arguments as individual NUL-delimited strings, never
    # a shell pattern. Exclude this update process and its ancestors only.
    $skip=[Collections.Generic.HashSet[int]]::new()
    $current=$PID
    while($current -gt 0 -and $skip.Add($current)){
        $stat=[IO.File]::ReadAllText('/proc/'+$current+'/stat')
        $tail=$stat.Substring($stat.LastIndexOf(')')+2).Split(' ')
        $current=[int]$tail[1]
    }
    foreach($directory in Get-ChildItem -LiteralPath '/proc' -Directory){
        if($directory.Name -notmatch '^\d+$' -or $skip.Contains([int]$directory.Name)){continue}
        # Cover ./Operator and relative --path/scripts too. These kernel links
        # are observations of a process, not deployment paths to copy through.
        foreach($probe in @('exe','cwd')){
            try{$target=[string][IO.File]::ResolveLinkTarget($directory.FullName+'/'+$probe,$true).FullName}catch{$target=''}
            if($target -ceq $Package -or $target.StartsWith($Package+'/',[StringComparison]::Ordinal)){Fail 'PACKAGE_PROCESS_RUNNING'}
        }
        try{$bytes=[IO.File]::ReadAllBytes($directory.FullName+'/cmdline')}catch{continue}
        if(-not $bytes.Length){continue}
        foreach($argument in $utf8.GetString($bytes).Split([char]0)){
            if($argument -ceq $Package -or $argument.StartsWith($Package+'/',[StringComparison]::Ordinal)){Fail 'PACKAGE_PROCESS_RUNNING'}
            if($argument.StartsWith('--') -and $argument.Contains('=')){
                $value=$argument.Substring($argument.IndexOf('=')+1)
                if($value -ceq $Package -or $value.StartsWith($Package+'/',[StringComparison]::Ordinal)){Fail 'PACKAGE_PROCESS_RUNNING'}
            }
        }
    }
}
function Package([string]$Root) {
    [void](Safe $Root)
    if(-not [IO.Directory]::Exists($Root)){Fail 'PACKAGE_MISSING'}
    $manifest=Child $Root 'SHA256SUMS.txt'
    if(-not [IO.File]::Exists($manifest)){Fail 'CHECKSUM_MANIFEST_MISSING'}
    Regular $manifest
    $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($line in [IO.File]::ReadAllLines($manifest)){
        if($line -notmatch '^([0-9a-f]{64})  ([a-zA-Z0-9_./-]+)$'){Fail 'CHECKSUM_LINE_INVALID'}
        $hash=$Matches[1];$relative=$Matches[2]
        if(-not $known.Add($relative)){Fail 'CHECKSUM_DUPLICATE'}
        $file=Child $Root $relative
        if(-not [IO.File]::Exists($file)){Fail 'CHECKSUM_MISMATCH'}
        Regular $file
        if((Digest $file) -cne $hash){Fail 'CHECKSUM_MISMATCH'}
    }
    foreach($name in @('linux-package.json','games.json','Operator.x86_64','Operator.pck','ManagedHost.x86_64','ManagedHost.pck','RoomKit.sh','tools/roomkit_linux.sh','tools/sqlite_store.ps1','tools/account_store.ps1','tools/storage_worker.ps1','tools/operator_maintenance.ps1','games/shooter/Server.x86_64','games/shooter/Server.pck','games/turns/Server.x86_64','games/turns/Server.pck')){
        if(-not $known.Contains($name)){Fail 'CHECKSUM_MANIFEST_INCOMPLETE'}
    }
    $metadata=ReadJson (Child $Root 'linux-package.json')
    if($metadata.format -ne 1 -or $metadata.engine -cne '4.7.2.stable.official.ed1daf0bf' -or $metadata.build -isnot [string] -or $metadata.source_commit -notmatch '^[0-9a-f]{40}$'){Fail 'PACKAGE_FORMAT_UNSUPPORTED'}
    $index=ReadJson (Child $Root 'games.json')
    if(-not $index.Count){Fail 'GAME_INDEX_INVALID'}
    foreach($id in $index.Keys){
        if($id -notmatch '^[a-z0-9-]+$'){Fail 'GAME_INDEX_INVALID'}
        $game=$index[$id]
        if($game.project -cne ('games/'+$id) -or $game.server_pack -cne ('games/'+$id+'/Server.pck') -or $game.server_executable -cne ('games/'+$id+'/Server.x86_64') -or $game.manifest.build_id -cne $metadata.games[$id]){Fail 'GAME_INDEX_INVALID'}
        [void](Child $Root $game.project)
    }
    return $metadata
}
function NoPending([string]$Data) {
    foreach($relative in Entries $Data){
        if($relative.StartsWith('outbox/') -and $relative.EndsWith('.json') -and -not $relative.EndsWith('.rejected.json')){Fail 'PENDING_RESULTS'}
        if($relative -match '(^|/)(account|sqlite|grant|maintenance)-request[^/]*\.json$'){Fail 'UNFINISHED_REQUEST_FILE'}
    }
    foreach($name in @('host-running.json','processes.json')){
        # A stale process journal needs a deliberate recovery run, not erasure
        # disguised as migration. A normal stop removes these active markers.
        if([IO.File]::Exists((Child $Data $name))){
            $record=ReadJson (Child $Data $name)
            if($name -eq 'host-running.json' -or ($record.entries -and $record.entries.Count)){Fail 'RECOVERY_REQUIRED'}
        }
    }
}
function InitializeSqlite([string]$Root) {
    if('RoomKitSqlite' -as [type]){return}
    $source=[IO.File]::ReadAllText((Child $Root 'tools/sqlite_store.ps1'))
    $binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    if(-not $binding.Success){Fail 'SQLITE_BINDING_UNSUPPORTED'}
    Add-Type -TypeDefinition $binding.Groups[1].Value
}
function CheckDatabases([string]$Root,[string]$Data) {
    InitializeSqlite $Root
    foreach($entry in @(@{name='accounts.sqlite';version='1'},@{name='assets.sqlite';version='2'})){
        $path=Child $Data $entry.name
        if(-not [IO.File]::Exists($path)){Fail 'DATABASE_MISSING'}
        $db=[RoomKitSqlite]::new($path)
        try{
            if($db.Query('PRAGMA integrity_check',@())[0]['integrity_check'] -cne 'ok'){Fail 'DATABASE_INTEGRITY_FAILED'}
            if($db.Query('PRAGMA user_version',@())[0]['user_version'] -cne $entry.version){Fail 'DATABASE_VERSION_UNSUPPORTED'}
            if($entry.name -eq 'accounts.sqlite'){[void]$db.Query('SELECT token_hash,user_id FROM sessions LIMIT 0',@());[void]$db.Query('SELECT action FROM account_audit LIMIT 0',@())}
            else{[void]$db.Query('SELECT body FROM asset_states LIMIT 0',@())}
        }finally{$db.Dispose()}
        foreach($suffix in @('','-wal','-shm','-journal')){if([IO.File]::Exists($path+$suffix)){Private ($path+$suffix) $false}}
    }
}
function CopyTree([string]$Source,[string]$Destination,[string[]]$Exclude=@()) {
    Folder $Destination
    foreach($relative in Entries $Source){
        if($Exclude -ccontains $relative){continue}
        $file=Child $Source $relative;$target=Child $Destination $relative
        $parent=[IO.Path]::GetDirectoryName($target)
        $cursor=$parent
        while($cursor.Length -ge $Destination.Length){Folder $cursor;if($cursor -ceq $Destination){break};$cursor=[IO.Path]::GetDirectoryName($cursor)}
        [IO.File]::Copy($file,$target,$false);Private $target $false
        if((Digest $file) -cne (Digest $target)){Fail 'COPY_VERIFY_FAILED'}
    }
}
function LoadJournal([string]$Package,[string]$Name) {
    $script:journalPath=Child $Package ('data/update-'+$Name+'/journal.json')
    $script:journal=ReadJson $script:journalPath
    if($script:journal.format -ne 1 -or $script:journal.new_package -cne $Package -or $script:journal.instance -cne $Name){Fail 'UPDATE_JOURNAL_INVALID'}
    if((Child $Package ('data/instance-'+$Name)) -cne $script:journal.new_instance){Fail 'UPDATE_JOURNAL_INVALID'}
    [void](Safe $script:journal.old_package)
    if((Child $script:journal.old_package ('data/instance-'+$Name)) -cne $script:journal.old_instance){Fail 'UPDATE_JOURNAL_INVALID'}
}
function Emit {
    $canRollback=$false
    if($script:journal.state -in @('PREPARED','VERIFIED')){
        try{
            AssertStopped $script:journal.new_package;AssertStopped $script:journal.old_package
            $canRollback=(EqualMaps $script:journal.candidate_files (Fingerprints $script:journal.new_instance)) -and (EqualMaps $script:journal.source_files (Fingerprints (Child $script:journal.old_instance 'data')))
        }catch{$canRollback=$false}
    }
    $object=@{ok=$true;state=$script:journal.state;instance=$script:journal.instance;old_package=$script:journal.old_package;new_package=$script:journal.new_package;new_instance=$script:journal.new_instance;journal=$script:journalPath;rollback_allowed=$canRollback;code=''}
    Write-Output ('ROOMKIT_UPDATE '+($object|ConvertTo-Json -Compress))
}
try {
    if(-not $IsLinux -or [Environment]::UserName -ceq 'root'){Fail 'LINUX_ORDINARY_USER_REQUIRED'}
    if($args.Count -lt 1){Fail 'ARGUMENTS_INVALID'}
    $command=[string]$args[0]
    if($command -notin @('prepare','verify','status','seal','rollback')){Fail 'COMMAND_INVALID'}
    $options=@{}
    for($i=1;$i -lt $args.Count;$i+=2){
        if($i+1 -ge $args.Count -or $args[$i] -notin @('--old-package','--new-package','--instance') -or $options.ContainsKey($args[$i])){Fail 'ARGUMENTS_INVALID'}
        $options[$args[$i]]=[string]$args[$i+1]
    }
    if(-not $options.ContainsKey('--new-package') -or -not $options.ContainsKey('--instance')){Fail 'ARGUMENTS_INVALID'}
    $name=$options['--instance']
    if($name -notmatch '^[a-z0-9-]{1,32}$'){Fail 'INSTANCE_INVALID'}
    $new=Safe $options['--new-package']
    $newInstance=Child $new ('data/instance-'+$name)
    $update=Child $new ('data/update-'+$name)
    if($command -ne 'prepare' -and $options.ContainsKey('--old-package')){Fail 'ARGUMENTS_INVALID'}
    if($command -eq 'prepare'){
        if(-not $options.ContainsKey('--old-package')){Fail 'ARGUMENTS_INVALID'}
        $old=Safe $options['--old-package']
        if($new -ceq $old -or $new.StartsWith($old+'/') -or $old.StartsWith($new+'/')){Fail 'PACKAGE_OVERLAP'}
        $oldInstance=Child $old ('data/instance-'+$name)
        $oldData=Child $oldInstance 'data'
        if(-not [IO.Directory]::Exists($oldData)){Fail 'OLD_INSTANCE_MISSING'}
        AssertStopped $old;AssertStopped $new
        $oldMetadata=Package $old;$newMetadata=Package $new
        if([IO.Directory]::Exists($newInstance) -or [IO.File]::Exists($newInstance) -or [IO.Directory]::Exists($update)){Fail 'DESTINATION_EXISTS'}
        NoPending $oldData
        $before=Fingerprints $oldData
        foreach($file in @('accounts.sqlite','assets.sqlite','config.json','server.crt','server.key')){if(-not $before.Contains($file)){Fail 'OLD_INSTANCE_INCOMPLETE'}}
        if(-not [IO.File]::Exists((Child $oldInstance 'panel.port'))){Fail 'PANEL_SETTING_MISSING'}
        Regular (Child $oldInstance 'panel.port')
        $panel=[IO.File]::ReadAllText((Child $oldInstance 'panel.port')).Trim()
        if($panel -notmatch '^\d+$' -or [int]$panel -lt 1024 -or [int]$panel -gt 65535 -or [int]$panel -eq 28291){Fail 'PANEL_SETTING_INVALID'}
        Folder (Child $new 'data');Folder $update
        $script:lock=[IO.File]::Open((Child $update 'lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        Private (Child $update 'lock') $false
        $script:journalPath=Child $update 'journal.json'
        $script:journal=@{format=1;state='PREPARING';instance=$name;old_package=$old;new_package=$new;old_instance=$oldInstance;new_instance=$newInstance;old_build=$oldMetadata.build;new_build=$newMetadata.build;created_at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();failure=''}
        Atomic $script:journalPath $script:journal
        $snapshot=Child $update 'offline-snapshot'
        CopyTree $oldData $snapshot
        if(-not (EqualMaps $before (Fingerprints $snapshot))){Fail 'SNAPSHOT_VERIFY_FAILED'}
        $script:staging=Child $new ('data/update-'+$name+'/candidate')
        Folder $script:staging
        CopyTree $snapshot (Child $script:staging 'data') @('operator.json','host-running.json','processes.json','operator-stop.request')
        # Keep port configuration; recreate games from NEW immutable package and
        # regenerate public data/HOME/cache/run on the next normal start.
        [IO.File]::WriteAllText((Child $script:staging 'panel.port'),$panel+"`n",$utf8);Private (Child $script:staging 'panel.port') $false
        [IO.File]::Copy((Child $new 'games.json'),(Child $script:staging 'games.json'));Private (Child $script:staging 'games.json') $false
        CheckDatabases $new (Child $script:staging 'data')
        AssertStopped $old;AssertStopped $new
        if(-not (EqualMaps $before (Fingerprints $oldData))){Fail 'SOURCE_CHANGED_DURING_COPY'}
        $script:journal.source_files=$before
        $script:journal.candidate_files=Fingerprints $script:staging
        $script:journal.snapshot=$snapshot
        [IO.Directory]::Move($script:staging,$newInstance)
        $script:published=$true;$script:journal.state='PREPARED';Atomic $script:journalPath $script:journal
        Emit
    }else{
        if($command -eq 'status'){LoadJournal $new $name;Emit;exit 0}
        $lockPath=Child $update 'lock';Regular $lockPath
        try{$script:lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{Fail 'UPDATE_BUSY'}
        # Read state ONLY after acquiring the same lock used by all mutations.
        # An earlier reader must not overwrite a concurrently sealed journal.
        LoadJournal $new $name
        if($script:journal.state -notin @('PREPARED','VERIFIED')){Fail 'UPDATE_STATE_REFUSED'}
        AssertStopped $new;AssertStopped $script:journal.old_package
        [void](Package $new)
        if(-not (EqualMaps $script:journal.candidate_files (Fingerprints $newInstance))){Fail 'CANDIDATE_HAS_CHANGED'}
        if(-not (EqualMaps $script:journal.source_files (Fingerprints (Child $script:journal.old_instance 'data')))){Fail 'OLD_DATA_HAS_CHANGED'}
        if($command -eq 'verify'){
            CheckDatabases $new (Child $newInstance 'data')
            if(-not (EqualMaps $script:journal.candidate_files (Fingerprints $newInstance))){Fail 'DATABASE_CHECK_CHANGED_CANDIDATE'}
            $script:journal.state='VERIFIED'
        }elseif($command -eq 'seal'){
            if($script:journal.state -cne 'VERIFIED'){Fail 'VERIFY_FIRST'}
            $script:journal.state='SEALED'
        }else{
            # Cancellation keeps every file and the old offline snapshot. Once
            # business data has changed, even startup changes, reject instead.
            $script:journal.state='CANCELLED'
        }
        Atomic $script:journalPath $script:journal
        Emit
    }
}catch{
    $code=if($_.Exception.Message.StartsWith('UPDATE:')){$_.Exception.Message.Substring(7)}else{'UPDATE_IO_FAILED'}
    if($null -ne $script:journal -and $script:journal.state -ceq 'PREPARING'){
        $script:journal.state=if($script:published){'PUBLICATION_UNCONFIRMED'}else{'FAILED_PREOPEN'}
        $script:journal.failure=$code
        try{Atomic $script:journalPath $script:journal}catch{}
    }
    Write-Output ('ROOMKIT_UPDATE '+(@{ok=$false;state=if($script:journal){$script:journal.state}else{'REJECTED'};code=$code;instance=if($options){$options['--instance']}else{''};error_type=$_.Exception.GetType().Name;error_line=$_.InvocationInfo.ScriptLineNumber}|ConvertTo-Json -Compress))
    exit 64
}finally{if($null -ne $script:lock){$script:lock.Dispose()}}
