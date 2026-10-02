param(
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$IndexPath = '',
    [string]$ConnectionDirectory = '',
    [string]$OutputRoot = '',
    [switch]$Unconfigured,
    [switch]$RepositoryCopy,
    [string]$RepositoryDestination = '',
    [string]$Repository = 'SchreiberChiang/godot-network-',
    [ValidateSet('','swap','swap-published','data-move','data-commit','legacy-move','legacy-commit')][string]$TestFailAt = ''
)
# 从 StartManagement.cmd 当前服务器所用的射击工程导出独立客户端，并附上该服务器的
# 公开 connection.json/server.crt。版本校验保持原样：客户端清单就是服务器自己的清单。
# 同一次导出同时供本地分发（含连接配置）和 GitHub 仓库副本（-RepositoryCopy，不含连接配置）。
# Only client-data/ is runtime state. Move it transactionally to the replacement;
# never register it for retention or copy it into a distribution.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
. (Join-Path $PSScriptRoot 'artifact_retention.ps1')
$utf8=New-Object Text.UTF8Encoding($false)
$helpers=Join-Path $PSScriptRoot 'shooter_client'
if($IndexPath -eq '') { $IndexPath=Join-Path $project 'artifacts\framework-games.json' }
if($ConnectionDirectory -eq '') { $ConnectionDirectory=Join-Path $project 'artifacts\client' }
$defaultPlayerOutput=($OutputRoot -eq '')
if($defaultPlayerOutput) { $OutputRoot=Join-Path $project 'artifacts\player-clients' }
$repositoryDefault=Join-Path $project 'clients\shooter-windows'
if($RepositoryDestination -eq '') { $RepositoryDestination=$repositoryDefault }

function Controlled([string]$Path,[string]$Label) {
    # Only Git-ignored artifacts\ or logs\ (or the fixed repository copy) may be written.
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $ok=$false
    foreach($root in @('artifacts','logs')) { if($full.StartsWith((Join-Path $project $root)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { $ok=$true } }
    if($Label -eq 'repository' -and $full -ieq $repositoryDefault) { $ok=$true }
    if($Label -eq 'player' -and $full -ieq (Join-Path $project 'PlayerClient')) { $ok=$true }
    if(-not $ok) { throw ('拒绝写入受控范围以外的目录（'+$Label+'）：'+$full) }
    $probe=$full
    while($probe.Length -gt $project.Length) {
        if((Test-Path -LiteralPath $probe) -and ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('拒绝写入链接目录：'+$probe) }
        $probe=[IO.Path]::GetDirectoryName($probe)
    }
    return $full
}
function AssertPlainClientTree([string]$Directory) {
    # Inspect each directory before descending: never follow junctions, symlinks
    # (including dangling links), or hard-linked files into another user's data.
    $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($Directory)
    while($pending.Count) {
        $path=$pending.Pop();$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType)) { throw ('CLIENT_LINKED_CONTENT '+$path) }
        if($item.PSIsContainer) { foreach($child in Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop) { $pending.Push($child.FullName) } }
    }
    if(-not (Get-Item -LiteralPath $Directory -Force).PSIsContainer) { throw ('CLIENT_EXPECTED_DIRECTORY '+$Directory) }
}
function AssertClientStopped([string]$Directory) {
    # Inspection failure fails closed. This check does not stop any process.
    try {
        if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            foreach($process in Get-CimInstance Win32_Process -Filter "Name='Client.exe'" -ErrorAction Stop) {
                if(-not $process.ExecutablePath) { throw 'client_identity_unavailable' }
            }
        }
        $commands=@(Get-RoomKitRetentionProcesses)
    } catch { throw 'CLIENT_PROCESS_CHECK_FAILED' }
    foreach($command in $commands) {
        if($command.IndexOf($Directory,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw ('CLIENT_RUNNING_CLOSE_FIRST '+$Directory) }
    }
}
function FileTable([string]$Directory) {
    AssertPlainClientTree $Directory
    $data=Join-Path $Directory 'client-data'
    if(Test-Path -LiteralPath $data) { AssertPlainClientTree $data }
    $table=[ordered]@{}
    foreach($file in Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | Sort-Object FullName) {
        $relative=$file.FullName.Substring($Directory.Length+1).Replace('\','/')
        if($relative -eq 'client-version.json' -or $relative.StartsWith('client-data/',[StringComparison]::Ordinal)) { continue }
        $table[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $table
}
function CopyPlayerProject([string]$Source,[string]$Destination) {
    # Prepared-project resources are an explicit allowlist. A played source
    # project may hold credentials/pending operations in data/; those bytes must
    # never reach export work or Client.pck, even under an innocuous *.json name.
    $pending=New-Object Collections.Queue
    foreach($item in Get-ChildItem -LiteralPath $Source -Force) {
        if(($item.PSIsContainer -and $item.Name -in @('game','sdk','schemas')) -or
           (-not $item.PSIsContainer -and ($item.Name -in @('project.godot','game_manifest.json') -or $item.Extension -in @('.gd','.uid')))) { $pending.Enqueue($item.FullName) }
    }
    while($pending.Count) {
        $path=[string]$pending.Dequeue();$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.Name -in @('.godot','data','client-data','logs','run','backup','backups')) { continue }
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType)) { throw 'CLIENT_LINKED_EXPORT_RESOURCE' }
        $relative=$item.FullName.Substring($Source.Length+1)
        $destinationPath=Join-Path $Destination $relative
        if($item.PSIsContainer) {
            [void][IO.Directory]::CreateDirectory($destinationPath)
            foreach($child in Get-ChildItem -LiteralPath $path -Force) { $pending.Enqueue($child.FullName) }
        } else {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath))
            Copy-Item -LiteralPath $path -Destination $destinationPath
        }
    }
}
function AssertCleanClientStage([string]$Directory) {
    AssertPlainClientTree $Directory
    foreach($item in Get-ChildItem -LiteralPath $Directory -Recurse -Force) {
        $relative=$item.FullName.Substring($Directory.Length+1).Replace('\','/')
        if($relative -match '(^|/)client-data(/|$)' -or $relative -match '(^|/)data/(client-operations|client-local)(/|$)') { throw 'CLIENT_RUNTIME_IN_DISTRIBUTION' }
    }
}
function CopyGeneratedClient([string]$Source,[string]$Destination) {
    # Never copy a used player tree recursively. Even an empty runtime directory
    # is private state and cannot become a Release attachment.
    AssertPlainClientTree $Source
    $version=Get-Content -LiteralPath (Join-Path $Source 'client-version.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    if(-not $version.PSObject.Properties['generated_files'] -or -not @($version.generated_files).Count) { throw 'CLIENT_GENERATED_WHITELIST_REQUIRED' }
    $names=@('client-version.json')
    foreach($entry in $version.generated_files) {
        $relative=[string]$entry.path
        # Player/Release output is deliberately flat; reject path components,
        # aliases/streams, runtime names and duplicates before touching output.
        if($relative -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $relative -in @('.','..','client-data') -or $relative -in $names) { throw 'CLIENT_INVALID_GENERATED_PATH' }
        $path=Join-Path $Source $relative
        if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$entry.sha256) { throw 'CLIENT_GENERATED_HASH_MISMATCH' }
        $names+=$relative
    }
    if(Test-Path -LiteralPath $Destination) { throw 'CLIENT_DISTRIBUTION_DESTINATION_EXISTS' }
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach($name in $names) { Copy-Item -LiteralPath (Join-Path $Source $name) -Destination (Join-Path $Destination $name) }
    AssertCleanClientStage $Destination
}
function WriteVersion([string]$Directory,$Base) {
    AssertCleanClientStage $Directory
    $version=[ordered]@{}
    foreach($key in $Base.Keys) { $version[$key]=$Base[$key] }
    $core=@()
    foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd')) {
        $path=Join-Path $Directory $name
        $core+=[ordered]@{path=$name;size=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $version.files=$core
    $generated=FileTable $Directory
    $version.generated_files=@($generated.Keys | ForEach-Object { [ordered]@{path=$_;sha256=$generated[$_]} })
    [IO.File]::WriteAllText((Join-Path $Directory 'client-version.json'),($version | ConvertTo-Json -Depth 6),$utf8)
}
function GetLegacyOperationMigrationRoot([string]$Directory) {
    $legacy=Join-Path $Directory 'data'
    if(-not (Test-Path -LiteralPath $legacy)) { return '' }
    AssertPlainClientTree $legacy
    $children=@(Get-ChildItem -LiteralPath $legacy -Force)
    if($children.Count -ne 1 -or $children[0].Name -cne 'client-operations' -or -not $children[0].PSIsContainer) { throw 'CLIENT_LEGACY_UNKNOWN_CONTENT' }
    # Original Godot JSON.stringify receipts had exactly these four string keys.
    # Match the complete object before parsing: reject duplicate/unknown keys,
    # nested values and control bytes rather than letting a JSON parser overwrite.
    $string='"(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"'
    $member='"(?<key>kind|item_id|slot|operation_id)"\s*:\s*'+$string
    $pattern='\A\s*\{\s*'+$member+'(?:\s*,\s*'+$member+')*\s*\}\s*\z'
    foreach($file in Get-ChildItem -LiteralPath $children[0].FullName -Force) {
        if($file.PSIsContainer -or $file.Name -cnotmatch '^[0-9a-f]{64}\.json$' -or $file.Length -gt 4096 -or $file.Length -eq 0) { throw 'CLIENT_LEGACY_UNKNOWN_CONTENT' }
        try { $raw=[IO.File]::ReadAllText($file.FullName,(New-Object Text.UTF8Encoding($false,$true))) } catch { throw 'CLIENT_LEGACY_INVALID_RECEIPT' }
        $match=[regex]::Match($raw,$pattern)
        $keys=@($match.Groups['key'].Captures | ForEach-Object Value)
        if(-not $match.Success -or $keys.Count -ne 4 -or @($keys | Sort-Object -Unique).Count -ne 4) { throw 'CLIENT_LEGACY_INVALID_RECEIPT' }
        try { $receipt=$raw | ConvertFrom-Json -ErrorAction Stop } catch { throw 'CLIENT_LEGACY_INVALID_RECEIPT' }
        if(@('purchase','select') -cnotcontains $receipt.kind -or $receipt.operation_id.Length -ne 32 -or $receipt.item_id.Length -gt 128 -or $receipt.slot.Length -gt 128) { throw 'CLIENT_LEGACY_INVALID_RECEIPT' }
    }
    # An empty client-operations directory is recognized too. Rename the entire
    # data parent so even its empty-directory structure remains recoverable.
    return $legacy
}
function MoveClientDirectory([string]$From,[string]$To,[Collections.ArrayList]$Journal) {
    [IO.Directory]::Move($From,$To)
    [void]$Journal.Add(@{kind='move';from=$From;to=$To})
}
function SafeReplace([string]$Target,[string]$Stage,[string]$BackupRoot,[switch]$CleanDistribution) {
    AssertCleanClientStage $Stage
    if(-not (Test-Path -LiteralPath $Target)) { [IO.Directory]::Move($Stage,$Target); return '' }
    AssertPlainClientTree $Target
    AssertClientStopped $Target
    $data=Join-Path $Target 'client-data'
    $hasData=Test-Path -LiteralPath $data
    if($hasData) {
        AssertPlainClientTree $data
        if($CleanDistribution) { throw 'CLIENT_RUNTIME_IN_RELEASE_TARGET' }
    }
    $legacy=GetLegacyOperationMigrationRoot $Target
    $quarantine=Join-Path $data 'legacy-client-operations'
    if($legacy) {
        if($CleanDistribution) { throw 'CLIENT_RUNTIME_IN_RELEASE_TARGET' }
        if(Test-Path -LiteralPath $quarantine) { throw 'CLIENT_LEGACY_QUARANTINE_COLLISION' }
    }
    $versionFile=Join-Path $Target 'client-version.json'
    if(-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) { throw ('目标目录不是本工具生成的客户端，拒绝覆盖：'+$Target) }
    $old=Get-Content -Encoding UTF8 -Raw -LiteralPath $versionFile | ConvertFrom-Json
    $known=@{}
    if($old.PSObject.Properties['generated_files']) { foreach($entry in $old.generated_files) { $known[$entry.path]=$entry.sha256 } }
    else {
        # Earlier format: core files with hashes plus the fixed helper/config names.
        foreach($entry in $old.files) { $known[$entry.path]=$entry.sha256 }
        foreach($name in @('README.md','SetServer.ps1','SetServer.cmd','CheckClient.ps1','CheckClient.cmd','FetchClient.ps1','FetchClient.cmd','connection.json','server.crt')) { if(-not $known.ContainsKey($name)) { $known[$name]='*' } }
    }
    foreach($path in $known.Keys) { if($path -match '(^|[\\/])client-data([\\/]|$)' -or $path -match '^data([\\/]|$)') { throw 'CLIENT_RUNTIME_IN_GENERATED_MANIFEST' } }
    $problems=@()
    $actual=FileTable $Target
    foreach($path in $actual.Keys) {
        if($legacy -and $path -cmatch '^data/client-operations/[0-9a-f]{64}\.json$') { continue }
        if(-not $known.ContainsKey($path)) { $problems+=('新增 '+$path) }
        elseif($known[$path] -ne '*' -and $known[$path] -ne $actual[$path]) { $problems+=('已改动 '+$path) }
    }
    # Empty unknown directories must not slip through a file-only manifest.
    foreach($directory in Get-ChildItem -LiteralPath $Target -Recurse -Directory -Force) {
        $relative=$directory.FullName.Substring($Target.Length+1).Replace('\','/')
        if($relative -eq 'client-data' -or $relative.StartsWith('client-data/',[StringComparison]::Ordinal)) { continue }
        if($legacy -and @('data','data/client-operations') -ccontains $relative) { continue }
        if(-not @($known.Keys | Where-Object { $_.StartsWith($relative+'/',[StringComparison]::Ordinal) }).Count) { $problems+=('新增目录 '+$relative) }
    }
    if($problems.Count) { throw ('目标目录里有不是本工具生成的内容，为避免丢失已停止，旧目录未改动：'+$Target+'；'+($problems -join '，')+'。请先把这些文件移走，或换一个目录保存。') }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    AssertPlainClientTree $BackupRoot
    $backup=Join-Path $BackupRoot ([IO.Path]::GetFileName($Target)+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,6))
    $backupData=Join-Path $backup 'client-data'
    # Recheck immediately before mutation. All moves below are directory renames,
    # never a recursive copy/delete, so a failed move cannot leave a partial tree.
    AssertClientStopped $Target
    $journal=New-Object Collections.ArrayList
    try {
        MoveClientDirectory $Target $backup $journal
        if($TestFailAt -eq 'swap') { throw 'TEST_INJECTED_SWAP_FAILURE' }
        MoveClientDirectory $Stage $Target $journal
        if($TestFailAt -eq 'swap-published') { throw 'TEST_INJECTED_PUBLISHED_SWAP_FAILURE' }
        if($hasData) {
            if($TestFailAt -eq 'data-move') { throw 'TEST_INJECTED_DATA_MIGRATION_FAILURE' }
            MoveClientDirectory $backupData $data $journal
            if($TestFailAt -eq 'data-commit') { throw 'TEST_INJECTED_DATA_COMMIT_FAILURE' }
        }
        if($legacy) {
            if(-not $hasData) {
                [void][IO.Directory]::CreateDirectory($data)
                [void]$journal.Add(@{kind='mkdir';to=$data})
            }
            if($TestFailAt -eq 'legacy-move') { throw 'TEST_INJECTED_LEGACY_MIGRATION_FAILURE' }
            # Preserve every byte and the full old data/ tree. Server/account
            # binding and any query/replay stay in the explicit client flow.
            MoveClientDirectory (Join-Path $backup 'data') $quarantine $journal
            if($TestFailAt -eq 'legacy-commit') { throw 'TEST_INJECTED_LEGACY_COMMIT_FAILURE' }
        }
    } catch {
        $failure=$_.Exception.Message
        try {
            for($step=$journal.Count-1;$step -ge 0;$step--) {
                $entry=$journal[$step]
                if($entry.kind -eq 'move') { [IO.Directory]::Move($entry.to,$entry.from) }
                else { [IO.Directory]::Delete($entry.to,$false) } # only our empty parent
            }
        } catch {
            # Preserve both trees, including the staging tree, for manual recovery.
            $script:preserveStaging=$true
            throw ('CLIENT_ROLLBACK_REQUIRES_RECOVERY target='+$Target+' backup='+$backup+' stage='+$Stage+'; '+$failure+'; '+$_.Exception.Message)
        }
        throw ('替换失败，已恢复旧目录和数据：'+$failure)
    }
    return $backup
}
function RetainGenerated([string]$Category,[string[]]$Paths,[string]$Outcome='success',[string[]]$References=@()) {
    try {
        Register-RoomKitArtifact -ProjectRoot $project -Category $Category -Paths $Paths -Outcome $Outcome -References $References -Summary @{generator='prepare_player_client';result=$Outcome}|Out-Null
        Invoke-RoomKitArtifactRetention -ProjectRoot $project -Category $Category -ProtectedPaths $References|Out-Null
    } catch { Write-Warning ('ARTIFACT_RETENTION_SKIPPED '+$Category+' registration_or_cleanup_failed') }
}

$OutputRoot=Controlled $OutputRoot 'output'
$target=Join-Path $OutputRoot 'shooter-windows'
if($defaultPlayerOutput) { $target=Controlled (Join-Path $project 'PlayerClient') 'player' }
if($RepositoryCopy) { $RepositoryDestination=Controlled $RepositoryDestination 'repository' }
$template=Join-Path ([IO.Path]::GetDirectoryName($Godot)) 'editor_data\export_templates\4.7.2.stable\windows_release_x86_64.exe'
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw ('Godot editor not found: '+$Godot) }
if(-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw 'The Godot 4.7.2 Windows release export template is missing.' }
if(-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) { throw '缺少游戏索引，请先运行 StartManagement.cmd。' }
foreach($name in $(if($Unconfigured){@()}else{@('connection.json','server.crt')})) {
    if(-not (Test-Path -LiteralPath (Join-Path $ConnectionDirectory $name) -PathType Leaf)) { throw ('缺少公开连接文件 '+$name+'，请先运行 StartManagement.cmd，由管理服务发布。') }
}
$index=Get-Content -Encoding UTF8 -Raw -LiteralPath $IndexPath | ConvertFrom-Json
$source=[string]$index.shooter.project
$manifest=$index.shooter.manifest
if(-not $source -or -not (Test-Path -LiteralPath (Join-Path $source 'client.gd') -PathType Leaf)) { throw '缺少已准备的射击工程，请先运行 StartManagement.cmd。' }
$onDisk=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $source 'game_manifest.json') | ConvertFrom-Json
foreach($key in @('game_id','build_id','compatibility_id','game_protocol')) {
    if([string]$onDisk.$key -ne [string]$manifest.$key) { throw ('Prepared project manifest differs from the server index: '+$key) }
}

$id=[Guid]::NewGuid().ToString('N')
$staging=Join-Path $OutputRoot ('.staging-'+$id)
$work=Join-Path $staging 'project'
$stage=Join-Path $staging 'shooter-windows'
$repoStage=Join-Path $staging 'repository'
New-Item -ItemType Directory -Force -Path $work,$stage,(Join-Path $project 'logs') | Out-Null
$retentionOutcome='failure'
$script:preserveStaging=$false
try {
    CopyPlayerProject $source $work
    [IO.File]::WriteAllText((Join-Path $work 'main.gd'),"class_name PlayerClientMain`nextends `"res://client.gd`"`n",$utf8)
    [IO.File]::WriteAllText((Join-Path $work 'empty.tscn'),"[gd_scene format=3]`n[node name=`"Bootstrap`" type=`"Node`"]`n",$utf8)
    $settingsFile=Join-Path $work 'project.godot'
    $text=[IO.File]::ReadAllText($settingsFile) -replace '(?m)^run/main_scene=.*\r?\n','' -replace '(?m)^run/main_loop_type=.*\r?\n',''
    [IO.File]::WriteAllText($settingsFile,$text.Replace('[application]',"[application]`nrun/main_loop_type=`"PlayerClientMain`"`nrun/main_scene=`"res://empty.tscn`""),$utf8)
    $preset=@'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
export_filter="all_resources"
include_filter="*.json,*.gd,*.tscn"
exclude_filter="**/preview.gd,**/test_runner.gd,client-data/*,**/client-data/*,data/*,**/data/*,logs/*,**/logs/*,run/*,**/run/*,backups/*,**/backups/*"
export_path=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'@
    [IO.File]::WriteAllText((Join-Path $work 'export_presets.cfg'),$preset,$utf8)
    $pack=Join-Path $stage 'Client.pck'
    $stdout=Join-Path $project ('logs\player-client-export-'+$id+'.log')
    $stderr=Join-Path $project ('logs\player-client-export-'+$id+'-stderr.log')
    $arguments=@('--headless','--path',$work,'--export-pack','Windows Desktop',$pack)
    $quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $ownedHandle=$process.Handle
    if(-not $process.WaitForExit(180000)) { $process.Kill(); $process.WaitForExit(); throw 'Client export timed out.' }
    if($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack -PathType Leaf) -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' -Quiet)) { throw ('Client export failed; see '+$stderr) }
    Copy-Item -LiteralPath $template -Destination (Join-Path $stage 'Client.exe')
    foreach($name in @('RunGame.ps1','StartGame.cmd','SetServer.ps1','SetServer.cmd','CheckClient.ps1','CheckClient.cmd')) { Copy-Item -LiteralPath (Join-Path $helpers $name) -Destination $stage }

    $pckHash=(Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash.ToLowerInvariant()
    $tag='shooter-client-'+(([string]$manifest.build_id) -replace '[^A-Za-z0-9.-]','-')+'-'+$pckHash.Substring(0,8)
    $base=[ordered]@{format=2;source=$(if($Unconfigured){'PreparedIndex'}else{'StartManagement'});game_id=$manifest.game_id;build_id=$manifest.build_id;compatibility_id=$manifest.compatibility_id;game_protocol=$manifest.game_protocol;engine_template='4.7.2.stable windows_release_x86_64';prepared_at=[DateTime]::UtcNow.ToString('o');release_tag=$tag;release_url=('https://github.com/'+$Repository+'/releases/download/'+$tag+'/')}

    # Repository copy: identical export, no server-specific files, plus GitHub fetch helpers.
    if($RepositoryCopy) {
        Copy-Item -LiteralPath $stage -Destination $repoStage -Recurse
        foreach($name in @('FetchClient.ps1','FetchClient.cmd')) { Copy-Item -LiteralPath (Join-Path $helpers $name) -Destination $repoStage }
        Copy-Item -LiteralPath (Join-Path $helpers 'README.md') -Destination (Join-Path $repoStage 'README.md')
        WriteVersion $repoStage $base
    }
    Copy-Item -LiteralPath (Join-Path $helpers 'PLAYER_README.md') -Destination (Join-Path $stage 'README.md')
    if($Unconfigured) {
        [IO.File]::WriteAllText((Join-Path $stage 'README.md'),@'
# RoomKit shooter player - server not configured yet

This is a complete Windows player program; no Godot editor is required.
It deliberately does NOT contain connection.json or server.crt. The build
machine has not started your target server or created a certificate for it.

1. Ask the actual server host for its PUBLIC connection.json and server.crt.
2. Drag their containing folder onto SetServer.cmd. Never accept a private key.
3. Double-click Client.exe (StartGame.cmd is also available), then register with
   an invitation from the host, log in, and create/join a shooter room.

Keep the whole folder together when giving it to a player. CheckClient.cmd
checks the executable/pack hashes and reports whether a server is configured.
client-version.json must match the server build; admission checks are unchanged.
Server updates may need a matching fresh player folder. Do not give players
server databases, private certificates, administrator credentials or backups.

Local settings, diagnostic logs and pending operations go in client-data/ beside
Client.exe. Close every client before rebuilding: a plain, link-free client-data
folder is preserved in the replacement, and failed swaps/migrations restore the
old client and data. Other unexpected files still block rebuilding. Never send
client-data to another player or a Release; send only an exported redacted report.
Use a freshly generated clean folder for distribution, not a used player folder.
'@,$utf8)
    }
    # SetServer validates the public files (wss url, allowed fields, no private key).
    if(-not $Unconfigured) {
        $set=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'SetServer.ps1') $ConnectionDirectory
        if($LASTEXITCODE -ne 0) { throw ('公开连接文件未通过检查：'+($set -join ' ')) }
    }
    WriteVersion $stage $base

    foreach($directory in @($stage,$repoStage)) {
        if(-not (Test-Path -LiteralPath $directory)) { continue }
        AssertCleanClientStage $directory
        foreach($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Force) {
            $relative=$file.FullName.Substring($directory.Length+1).Replace('\','/')
            if($relative -match '(^|/)(data|run|logs|backups?)/|\.(key|sqlite|db|token)$|admin|secret') { throw ('客户端目录中出现不应分发的文件：'+$relative) }
            if($file.Extension -in @('.crt','.pem','.json') -and ([IO.File]::ReadAllText($file.FullName) -match 'PRIVATE KEY')) { throw ('客户端目录中出现私钥：'+$relative) }
        }
        foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.ps1' -File) {
            $tokens=$null; $errors=$null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            if($errors.Count) { throw ('PowerShell parse failure: '+$file.Name) }
        }
    }
    if($RepositoryCopy -and ((Test-Path -LiteralPath (Join-Path $repoStage 'connection.json')) -or (Test-Path -LiteralPath (Join-Path $repoStage 'server.crt')))) { throw '仓库副本不应包含服务器连接文件。' }

    $previous=SafeReplace $target $stage (Join-Path $OutputRoot 'previous')
    if($previous) { Write-Output ('PLAYER_CLIENT_PREVIOUS '+$previous);RetainGenerated 'player-client-previous' @($previous) }
    if($RepositoryCopy) {
        $repoPrevious=SafeReplace $RepositoryDestination $repoStage (Join-Path $OutputRoot 'previous-repository')
        if($repoPrevious) { Write-Output ('REPOSITORY_CLIENT_PREVIOUS '+$repoPrevious);RetainGenerated 'player-client-repository-previous' @($repoPrevious) }
        Write-Output ('REPOSITORY_CLIENT_READY '+$RepositoryDestination+' tag='+$tag)
        # GitHub Release attachments: exactly the repository copy's files, Client.exe
        # included, uploaded one by one (no archive). The list and hashes sit beside
        # the folder so the folder holds only what gets uploaded.
        $releaseDir=Join-Path $OutputRoot ('release-'+$tag)
        $releaseStage=Join-Path $staging 'release'
        CopyGeneratedClient $RepositoryDestination $releaseStage
        $releasePrevious=SafeReplace $releaseDir $releaseStage (Join-Path $OutputRoot 'previous-release') -CleanDistribution
        if($releasePrevious) { Write-Output ('RELEASE_ASSETS_PREVIOUS '+$releasePrevious);RetainGenerated 'player-client-release-previous' @($releasePrevious) }
        $assets=@(Get-ChildItem -LiteralPath $releaseDir -File | Sort-Object Name | ForEach-Object { [ordered]@{name=$_.Name;size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
        if(@(Get-ChildItem -LiteralPath $releaseDir -Directory).Count) { throw 'Release attachments must be a flat folder.' }
        if(-not ($assets | Where-Object { $_.name -eq 'Client.exe' })) { throw 'Release attachments are missing Client.exe.' }
        [IO.File]::WriteAllText(($releaseDir+'.json'),([ordered]@{tag=$tag;build_id=$manifest.build_id;repository=$Repository;target_path='clients/shooter-windows';assets=$assets}|ConvertTo-Json -Depth 4),$utf8)
        [IO.File]::WriteAllText(($releaseDir+'-SHA256SUMS.txt'),((($assets | ForEach-Object { $_.sha256+'  '+$_.name }) -join "`n")+"`n"),$utf8)
        Write-Output ('RELEASE_ASSETS_READY '+$releaseDir+' files='+$assets.Count+' bytes='+(Get-ChildItem -LiteralPath $releaseDir -File | Measure-Object Length -Sum).Sum)
        RetainGenerated 'player-client-release' @($releaseDir,($releaseDir+'.json'),($releaseDir+'-SHA256SUMS.txt')) 'success' @($releaseDir)
    }
    $retentionOutcome='success'
} finally {
    if(-not $script:preserveStaging -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force }
    if($null -ne $process){$process.Dispose()}
    $exportLogs=@($stdout,$stderr)|Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}
    if($exportLogs.Count){RetainGenerated 'player-client-export' $exportLogs $retentionOutcome}
}
$connection=if($Unconfigured){[pscustomobject]@{url='UNCONFIGURED'}}else{Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $target 'connection.json') | ConvertFrom-Json}
$size=(Get-ChildItem -LiteralPath $target -Recurse -File | Measure-Object Length -Sum).Sum
Write-Output ('PLAYER_CLIENT_READY '+$target+' build='+$manifest.build_id+' tag='+$tag+' url='+$connection.url+' bytes='+$size)
if([string]$connection.url -match '^wss://(127\.|localhost)') {
    Write-Output 'WARNING: 服务器对外地址是本机回环地址，只能在这台电脑上连接。给朋友用前，请在管理后台停止游戏服务器、把对外 IP 设为本机局域网地址、重新启动，然后再运行 PreparePlayerClient.cmd。'
}
