param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Work)
# Fake packages only. No Godot, services, signals, account passwords or network.
$ErrorActionPreference='Stop'
if(-not $IsLinux){throw 'This test requires Linux pwsh.'}
$Source=[IO.Path]::GetFullPath($Source);$Work=[IO.Path]::GetFullPath($Work)
if(Test-Path -LiteralPath $Work){throw 'Work must be new.'}
[void][IO.Directory]::CreateDirectory($Work)
$script:pass=0;$script:fail=0
$utf8=[Text.UTF8Encoding]::new($false)
$shell=(Get-Process -Id $PID).Path
$update=Join-Path $Source 'tools/update_linux_package.ps1'
$binding=[regex]::Match([IO.File]::ReadAllText((Join-Path $Source 'tools/sqlite_store.ps1')),"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
function Check([bool]$Condition,[string]$Name){if($Condition){$script:pass++;Write-Output ('PASS '+$Name)}else{$script:fail++;Write-Output ('FAIL '+$Name)}}
function Write([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Package([string]$Name,[string]$Build='new'){
    $root=Join-Path $Work $Name;[void][IO.Directory]::CreateDirectory($root)
    $index=[ordered]@{}
    foreach($game in @('shooter','turns')){
        $index[$game]=@{project=('games/'+$game);server_pack=('games/'+$game+'/Server.pck');server_executable=('games/'+$game+'/Server.x86_64');manifest=@{build_id=($game+'-'+$Build)}}
        Write ($root+'/games/'+$game+'/Server.pck') ('fake pack '+$Build)
        Write ($root+'/games/'+$game+'/Server.x86_64') 'fake engine never executed'
    }
    Write ($root+'/games.json') ($index|ConvertTo-Json -Depth 10)
    Write ($root+'/linux-package.json') (@{format=1;build=$Build;source_commit=('a'*40);engine='4.7.2.stable.official.ed1daf0bf';games=@{shooter=('shooter-'+$Build);turns=('turns-'+$Build)}}|ConvertTo-Json)
    foreach($file in @('Operator.x86_64','Operator.pck','ManagedHost.x86_64','ManagedHost.pck','RoomKit.sh','tools/roomkit_linux.sh')){Write ($root+'/'+$file) 'fake runtime never executed'}
    foreach($name in @('sqlite_store.ps1','account_store.ps1','storage_worker.ps1','operator_maintenance.ps1')){[IO.File]::Copy(($Source+'/tools/'+$name),($root+'/tools/'+$name))}
    Sums $root
    return $root
}
function Sums([string]$Root){$lines=@(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object{$_.Name -ne 'SHA256SUMS.txt' -and -not $_.FullName.StartsWith($Root+'/data/')} | ForEach-Object{(Hash $_.FullName)+'  '+$_.FullName.Substring($Root.Length+1)});Write ($Root+'/SHA256SUMS.txt') (($lines -join "`n")+"`n")}
function Instance([string]$Root,[string]$Name='sample'){
    $inst=$Root+'/data/instance-'+$Name;$data=$inst+'/data';[void][IO.Directory]::CreateDirectory($data)
    $db=[RoomKitSqlite]::new($data+'/accounts.sqlite')
    try{[void]$db.Query('CREATE TABLE sessions(token_hash TEXT,user_id TEXT)',@());[void]$db.Query('CREATE TABLE account_audit(action TEXT)',@());[void]$db.Query('PRAGMA user_version=1',@())}finally{$db.Dispose()}
    $db=[RoomKitSqlite]::new($data+'/assets.sqlite')
    try{[void]$db.Query('CREATE TABLE asset_states(body TEXT)',@());[void]$db.Query('INSERT INTO asset_states(body) VALUES (?)',@('{"coins":567}'));[void]$db.Query('PRAGMA user_version=2',@())}finally{$db.Dispose()}
    Write ($data+'/config.json') '{"lobby_bind":"127.0.0.1","lobby_port":28700,"control_port":28701,"udp_first":28740,"udp_last":28755}'
    Write ($data+'/server.crt') 'FAKE PUBLIC CERTIFICATE';Write ($data+'/server.key') 'FAKE TEST PRIVATE KEY'
    Write ($data+'/backups/snapshot/manifest.json') '{"test":"backup-mark"}';Write ($data+'/account-deletion-journal.jsonl') '{"test":"deletion-mark"}'
    Write ($data+'/operator.json') '{"pid":999999999}';Write ($inst+'/panel.port') "28691`n";Write ($inst+'/games.json') '{"old-absolute-project":"/old/project/path"}'
    return $inst
}
function InvokeUpdate([string[]]$Arguments,[string]$Tool=$update){
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$shell;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-NonInteractive','-File',$Tool)+$Arguments){$info.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($info);$out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(60000)){$process.Kill();throw 'Update test exceeded 60 s.'}
    $output=$out.GetAwaiter().GetResult();$errorText=$err.GetAwaiter().GetResult();$exit=$process.ExitCode;$process.Dispose()
    $line=@($output.Split("`n") | Where-Object{$_.StartsWith('ROOMKIT_UPDATE ')})[-1]
    if(-not $line){throw ('No machine response; stderr='+$errorText)}
    return @{exit=$exit;reply=($line.Substring(15)|ConvertFrom-Json -AsHashtable);stdout=$output;stderr=$errorText}
}
function Prepare([string]$Old,[string]$New,[string]$Name='sample'){return InvokeUpdate @('prepare','--old-package',$Old,'--new-package',$New,'--instance',$Name)}
$old=Package 'old package' 'old';$oldInst=Instance $old;$oldDb=Hash ($oldInst+'/data/assets.sqlite');$new=Package 'new package' 'new'
$result=Prepare $old $new
if($result.exit -ne 0){Write-Output ('PREPARE_DIAGNOSTIC '+($result.reply|ConvertTo-Json -Compress))}
Check ($result.exit -eq 0 -and $result.reply.state -ceq 'PREPARED') 'prepare candidate'
$candidate=$new+'/data/instance-sample';$journal=$new+'/data/update-sample/journal.json'
Check ((Hash ($candidate+'/data/assets.sqlite')) -ceq $oldDb) 'asset database copied byte-for-byte'
Check ((Hash ($oldInst+'/data/assets.sqlite')) -ceq $oldDb) 'old database unchanged'
Check ([IO.File]::ReadAllText($candidate+'/games.json') -ceq [IO.File]::ReadAllText($new+'/games.json')) 'new index replaces stale old index'
Check (-not [IO.File]::Exists($candidate+'/data/operator.json')) 'runtime marker omitted'
Check ([IO.File]::Exists($candidate+'/data/backups/snapshot/manifest.json') -and [IO.File]::Exists($candidate+'/data/account-deletion-journal.jsonl')) 'backups and deletion journal retained'
Check ([IO.File]::ReadAllText($candidate+'/panel.port').Trim() -ceq '28691') 'panel preserved'
Check ([IO.File]::GetUnixFileMode($candidate) -eq [IO.UnixFileMode]'UserRead,UserWrite,UserExecute') 'instance mode 700'
Check ([IO.File]::GetUnixFileMode($candidate+'/data/server.key') -eq [IO.UnixFileMode]'UserRead,UserWrite') 'private file mode 600'
Check (-not [IO.File]::ReadAllText($journal).Contains('FAKE TEST PRIVATE KEY')) 'journal excludes secret file contents'
$result=InvokeUpdate @('verify','--new-package',$new,'--instance','sample');Check ($result.exit -eq 0 -and $result.reply.state -ceq 'VERIFIED') 'offline verify'
$result=InvokeUpdate @('rollback','--new-package',$new,'--instance','sample');Check ($result.exit -eq 0 -and $result.reply.state -ceq 'CANCELLED') 'untouched candidate can be cancelled'
Check ([IO.Directory]::Exists($candidate) -and [IO.File]::Exists($new+'/data/update-sample/offline-snapshot/assets.sqlite')) 'cancellation deletes no data or snapshot'
$result=Prepare $old $new;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'DESTINATION_EXISTS') 'existing destination refused'
$sealed=Package 'sealed';[void](Prepare $old $sealed);[void](InvokeUpdate @('verify','--new-package',$sealed,'--instance','sample'))
$result=InvokeUpdate @('seal','--new-package',$sealed,'--instance','sample');Check ($result.exit -eq 0 -and $result.reply.state -ceq 'SEALED') 'explicit seal'
$result=InvokeUpdate @('rollback','--new-package',$sealed,'--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'UPDATE_STATE_REFUSED') 'sealed rollback refused'
$changed=Package 'changed';[void](Prepare $old $changed);Write ($changed+'/data/instance-sample/data/new-business.json') '{"new":true}'
$result=InvokeUpdate @('rollback','--new-package',$changed,'--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'CANDIDATE_HAS_CHANGED') 'rollback after any candidate write refused'
$damaged=Package 'damaged';Write ($damaged+'/Operator.pck') 'corrupted'
$result=Prepare $old $damaged;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'CHECKSUM_MISMATCH' -and -not [IO.Directory]::Exists($damaged+'/data')) 'corrupt package rejected before writing'
$dup=Package 'duplicate';$result=InvokeUpdate @('prepare','--old-package',$old,'--new-package',$dup,'--instance','sample','--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'ARGUMENTS_INVALID') 'duplicate arguments rejected'
$result=InvokeUpdate @('prepare','--old-package',$old,'--new-package',($dup+'/../duplicate'),'--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'PATH_INVALID') 'dot-dot path rejected'
$linked=Join-Path $Work 'linked';[void](New-Item -ItemType SymbolicLink -Path $linked -Target $dup)
$result=Prepare $old $linked;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'LINK_REFUSED') 'linked package rejected'
Write ($oldInst+'/data/outbox/test/result.json') '{"pending":true}'
$result=Prepare $old $dup;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'PENDING_RESULTS') 'pending result refuses update'
[IO.File]::Delete($oldInst+'/data/outbox/test/result.json')
$copyFail=Package 'copy-fail';$copyTool=Join-Path $Work 'copy-fail-updater.ps1';$copySource=[IO.File]::ReadAllText($update).Replace('Folder $Destination',"if(`$Source.EndsWith('/offline-snapshot')){throw [IO.IOException]::new('injected copy failure')};Folder `$Destination");Write $copyTool $copySource
$result=InvokeUpdate @('prepare','--old-package',$old,'--new-package',$copyFail,'--instance','sample') $copyTool
Check ($result.exit -eq 64 -and $result.reply.state -ceq 'FAILED_PREOPEN' -and -not [IO.Directory]::Exists($copyFail+'/data/instance-sample')) 'injected candidate copy failure refuses publication'
Check ((Hash ($oldInst+'/data/assets.sqlite')) -ceq $oldDb -and [IO.File]::Exists($copyFail+'/data/update-sample/offline-snapshot/assets.sqlite')) 'copy failure keeps old database and offline snapshot'
$fifo=$oldInst+'/data/fifo';& mkfifo -- $fifo
$result=Prepare $old $dup;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'SPECIAL_FILE_REFUSED') 'FIFO refuses without hashing or blocking'
[IO.File]::Delete($fifo)
$packageFifo=Package 'package-fifo';[IO.File]::Delete($packageFifo+'/Operator.pck');& mkfifo -- ($packageFifo+'/Operator.pck')
$result=Prepare $old $packageFifo;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'SPECIAL_FILE_REFUSED') 'checksummed package FIFO refuses without hashing'
$statusFifo=Package 'status-fifo';[void](Prepare $old $statusFifo);[IO.File]::Delete($statusFifo+'/data/update-sample/journal.json');& mkfifo -- ($statusFifo+'/data/update-sample/journal.json')
$result=InvokeUpdate @('status','--new-package',$statusFifo,'--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'SPECIAL_FILE_REFUSED') 'journal FIFO rejected without reading'
$case=Package 'case-files';Write ($oldInst+'/data/Foo') 'Upper';Write ($oldInst+'/data/foo') 'lower';$result=Prepare $old $case
Check ($result.exit -eq 0 -and [IO.File]::Exists($case+'/data/instance-sample/data/Foo') -and [IO.File]::Exists($case+'/data/instance-sample/data/foo')) 'case distinct files copied and fingerprinted'
Write ($case+'/data/instance-sample/data/Foo') 'Upper modified';$result=InvokeUpdate @('rollback','--new-package',$case,'--instance','sample');Check ($result.exit -eq 64 -and $result.reply.code -ceq 'CANDIDATE_HAS_CHANGED') 'case distinct upper file mutation refuses rollback'
$pause=Join-Path $Work 'pause.ps1';Write $pause 'param([string]$Marker) Start-Sleep -Seconds 55'
$sleep=[Diagnostics.ProcessStartInfo]::new();$sleep.FileName=$shell;foreach($arg in @('-NoProfile','-NonInteractive','-File',$pause,'-Marker',($old+'/fake-managed-process'))){$sleep.ArgumentList.Add($arg)};$owned=[Diagnostics.Process]::Start($sleep)
try{$result=Prepare $old $dup;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'PACKAGE_PROCESS_RUNNING') 'live package process refused'}finally{if(-not $owned.HasExited){$owned.Kill()};$owned.WaitForExit();$owned.Dispose()}
$equal=Package 'build=equal';[void](Instance $equal);[IO.File]::Copy('/bin/sleep',($equal+'/Operator.x86_64'),$true);[IO.File]::SetUnixFileMode(($equal+'/Operator.x86_64'),[IO.UnixFileMode]'UserRead,UserWrite,UserExecute')
$sleep=[Diagnostics.ProcessStartInfo]::new();$sleep.FileName='/bin/bash';$sleep.WorkingDirectory=$equal;$sleep.ArgumentList.Add('-c');$sleep.ArgumentList.Add('exec ./Operator.x86_64 55');$owned=[Diagnostics.Process]::Start($sleep)
try{$result=Prepare $equal $dup;Check ($result.exit -eq 64 -and $result.reply.code -ceq 'PACKAGE_PROCESS_RUNNING') 'relative executable under equals package refused'}finally{if(-not $owned.HasExited){$owned.Kill()};$owned.WaitForExit();$owned.Dispose()}
$badVersion=Package 'bad-version';$db=[RoomKitSqlite]::new($oldInst+'/data/assets.sqlite');try{[void]$db.Query('PRAGMA user_version=99',@())}finally{$db.Dispose()}
$versionHash=Hash ($oldInst+'/data/assets.sqlite');$result=Prepare $old $badVersion
Check ($result.exit -eq 64 -and $result.reply.state -ceq 'FAILED_PREOPEN' -and $result.reply.code -ceq 'DATABASE_VERSION_UNSUPPORTED') 'unsupported database aborts before publication'
Check (-not [IO.Directory]::Exists($badVersion+'/data/instance-sample') -and (Hash ($oldInst+'/data/assets.sqlite')) -ceq $versionHash) 'failed validation leaves old database intact'
Write-Output ('RESULT pass='+$script:pass+' fail='+$script:fail)
if($script:fail){exit 1}
