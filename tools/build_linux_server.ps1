param(
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$OutputDirectory=''
)
# Windows-hosted Linux export. Only fresh, ignored artifacts directories are written.
# Game identities come from build_framework.ps1 and are never rewritten per platform.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$id=[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$utf8=New-Object Text.UTF8Encoding($false)
function SafeArtifact([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if(-not $full.StartsWith($project+'\artifacts\',[StringComparison]::OrdinalIgnoreCase)){throw 'Linux build output must be inside this project artifacts folder.'}
    $cursor=$full
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked build path.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    if(Test-Path -LiteralPath $full){throw 'Linux build output already exists; nothing is replaced.'}
    return $full
}
function WriteUtf8([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function SetEntry([string]$Folder,[string]$Entry){
    WriteUtf8 (Join-Path $Folder 'main.gd') ("class_name FrameworkExportMain`nextends `""+$Entry+"`"`n")
    WriteUtf8 (Join-Path $Folder 'empty.tscn') "[gd_scene format=3]`n[node name=`"Bootstrap`" type=`"Node`"]`n"
    $settings=[IO.File]::ReadAllText((Join-Path $Folder 'project.godot')) -replace '(?m)^run/main_scene=.*\r?\n','' -replace '(?m)^run/main_loop_type=.*\r?\n',''
    WriteUtf8 (Join-Path $Folder 'project.godot') ($settings.Replace('[application]',"[application]`nrun/main_loop_type=`"FrameworkExportMain`"`nrun/main_scene=`"res://empty.tscn`""))
}
$preset=@'
[preset.0]
name="Linux Server"
platform="Linux/X11"
runnable=true
dedicated_server=false
export_filter="all_resources"
include_filter="*.json,*.gd,*.tscn,*.ps1,*.html"
exclude_filter="**/preview.gd,**/test_runner.gd"
export_path=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'@
function ExportPack([string]$Folder,[string]$Pack,[string]$Label){
    WriteUtf8 (Join-Path $Folder 'export_presets.cfg') $preset
    $arguments=@('--headless','--path',$Folder,'--export-pack','Linux Server',$Pack)
    $quoted=@($arguments|ForEach-Object {'"'+($_ -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'})
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $work ($Label+'.out')) -RedirectStandardError (Join-Path $work ($Label+'.err'))
    $handle=$process.Handle
    try {
        if(-not $process.WaitForExit(180000)){$process.Kill();[void]$process.WaitForExit(5000);throw ('Export timed out: '+$Label)}
        if($process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $Pack -PathType Leaf) -or (Select-String -LiteralPath (Join-Path $work ($Label+'.err')) -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' -Quiet)){throw ('Export failed: '+$Label+'; see '+$work)}
    }finally{$process.Dispose()}
    Write-Output ('LINUX_EXPORT_OK '+$Label)
}
if($OutputDirectory -eq ''){$OutputDirectory=Join-Path $project ('artifacts/RoomKit-0.5.0-linux-x86_64-'+$id)}
$bundle=SafeArtifact $OutputDirectory
$work=SafeArtifact (Join-Path $project ('artifacts/linux-server-build-'+$id))
$template=Join-Path ([IO.Path]::GetDirectoryName($Godot)) 'editor_data/export_templates/4.7.2.stable/linux_release.x86_64'
if(-not(Test-Path -LiteralPath $Godot -PathType Leaf) -or -not(Test-Path -LiteralPath $template -PathType Leaf)){throw 'The tested editor and Linux x86_64 release template are required.'}
$editorVersion=(& $Godot --headless --version | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $editorVersion -notmatch '^4\.7\.2\.stable\.(steam|official)\.ed1daf0bf$'){throw 'The export editor must be the tested Godot 4.7.2 ed1daf0bf build.'}
if((Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'd9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63'){throw 'Linux template differs from the tested Godot 4.7.2 official template.'}
$buildOutcome='failure'
try {
[void][IO.Directory]::CreateDirectory($work);[void][IO.Directory]::CreateDirectory($bundle)
$hostProject=Join-Path $work 'host-project'
$sourceFiles=New-Object Collections.ArrayList
foreach($folder in @('host','sdk','schemas','config','examples')){
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $project $folder) -Recurse -File){
        if($file.Extension -notin @('.gd','.json','.tscn','.html') -or $file.Name -in @('preview.gd','test_runner.gd')){continue}
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refused linked runtime source.'}
        $relative=$file.FullName.Substring($project.Length+1).Replace('\','/')
        $target=Join-Path $hostProject $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target));Copy-Item -LiteralPath $file.FullName -Destination $target
        [void]$sourceFiles.Add(@{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})
    }
}
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $hostProject
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination $bundle
foreach($notice in @('LICENSE.txt','COPYRIGHT.txt')){
    $noticeSource=Join-Path ([IO.Path]::GetDirectoryName($Godot)) $notice
    if(-not(Test-Path -LiteralPath $noticeSource -PathType Leaf)){throw 'Godot runtime copyright notices are required for distribution.'}
    Copy-Item -LiteralPath $noticeSource -Destination (Join-Path $bundle ('GODOT-'+$notice))
}
foreach($inputFile in @('RoomKit.sh','tools/roomkit.ps1','tools/roomkit_entry.ps1','project.godot','LICENSE','PrepareEnvironment.sh','tools/prepare_environment.sh','tools/runtime_paths.sh','tools/build_linux_server.ps1','tools/build_framework.ps1','tools/content_digest.ps1','tools/roomkit_linux.sh','tools/linux_package_check.sh')){
    [void]$sourceFiles.Add(@{path=$inputFile;sha256=(Get-FileHash -LiteralPath (Join-Path $project $inputFile) -Algorithm SHA256).Hash.ToLowerInvariant()})
}
foreach($helper in @('sqlite_store.ps1','account_store.ps1','storage_worker.ps1','operator_maintenance.ps1')){
    foreach($folder in @($hostProject,$bundle)){[void][IO.Directory]::CreateDirectory((Join-Path $folder 'tools'));Copy-Item -LiteralPath (Join-Path $PSScriptRoot $helper) -Destination (Join-Path $folder ('tools/'+$helper))}
    [void]$sourceFiles.Add(@{path=('tools/'+$helper);sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $helper) -Algorithm SHA256).Hash.ToLowerInvariant()})
}
$sourceIndex=Join-Path $work 'games-source.json'
& (Join-Path $PSScriptRoot 'build_framework.ps1') -IndexPath $sourceIndex -BuildRoot (Join-Path $work 'games')
$games=Get-Content -LiteralPath $sourceIndex -Encoding UTF8 -Raw | ConvertFrom-Json
$index=[ordered]@{}
foreach($game in @('shooter','turns')){
    $entry=$games.$game
    $directory=Join-Path $bundle ('games/'+$game);[void][IO.Directory]::CreateDirectory($directory)
    $index[$game]=[ordered]@{project=('games/'+$game);server_pack=('games/'+$game+'/Server.pck');server_executable=('games/'+$game+'/Server.x86_64');manifest=$entry.manifest}
    foreach($field in @('name','asset_catalog','asset_policy','result_schema','reward_script')){if($entry.PSObject.Properties[$field]){$index[$game][$field]=$entry.$field}}
    SetEntry $entry.project 'res://game/room.gd'
    ExportPack $entry.project (Join-Path $directory 'Server.pck') ($game+'-room')
    Copy-Item -LiteralPath $template -Destination (Join-Path $directory 'Server.x86_64')
}
WriteUtf8 (Join-Path $bundle 'games.json') ($index|ConvertTo-Json -Depth 30)
foreach($entry in @(@{name='Operator';script='res://host/operator.gd'},@{name='ManagedHost';script='res://host/managed_host.gd'})){
    SetEntry $hostProject $entry.script
    ExportPack $hostProject (Join-Path $bundle ($entry.name+'.pck')) $entry.name
    Copy-Item -LiteralPath $template -Destination (Join-Path $bundle ($entry.name+'.x86_64'))
}
foreach($name in @('roomkit.ps1','roomkit_entry.ps1','roomkit_linux.sh','linux_package_check.sh','prepare_environment.sh','runtime_paths.sh')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $bundle ('tools/'+$name))}
Copy-Item -LiteralPath (Join-Path $project 'PrepareEnvironment.sh') -Destination (Join-Path $bundle 'PrepareEnvironment.sh')
foreach($name in @('update_linux_package.sh','update_linux_package.ps1')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $bundle ('tools/'+$name))
    [void]$sourceFiles.Add(@{path=('tools/'+$name);sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()})
}
Copy-Item -LiteralPath (Join-Path $project 'RoomKit.sh') -Destination (Join-Path $bundle 'RoomKit.sh')
WriteUtf8 (Join-Path $bundle 'CheckPackage.sh') "#!/usr/bin/env bash`nexec bash `"`$(dirname `"`$0`")/tools/linux_package_check.sh`" `"`$@`"`n"
WriteUtf8 (Join-Path $bundle 'UpdateRoomKit.sh') "#!/usr/bin/env bash`nexec bash `"`$(dirname `"`$0`")/tools/update_linux_package.sh`" `"`$@`"`n"
$base=(& git -C $project rev-parse HEAD).Trim();if($LASTEXITCODE){throw 'Cannot identify source commit.'}
WriteUtf8 (Join-Path $bundle 'linux-package.json') (@{format=1;build=$id;source_commit=$base;engine='4.7.2.stable.official.ed1daf0bf';pwsh='external 7.6.6';games=@{shooter=$games.shooter.manifest.build_id;turns=$games.turns.manifest.build_id};source_files=@($sourceFiles)}|ConvertTo-Json -Depth 10)
WriteUtf8 (Join-Path $bundle 'README.md') @'
# RoomKit Linux x86_64 server candidate

This is a normal server directory, not a source checkout. Keep all files together.
Godot is included. Run bash PrepareEnvironment.sh check first (read-only).
bash PrepareEnvironment.sh prepare downloads the missing tested pwsh 7.6.6 from
official GitHub into artifacts/environment/tools, without sudo/global changes.
If GitHub is unavailable, import the official archive with --offline and
--pwsh-archive /ABS/powershell-7.6.6-linux-x64.tar.gz; its SHA256 is fixed.
System SQLite, ICU and OpenSSL must be present; missing libraries are reported,
not installed. Set ROOMKIT_PWSH for another tested absolute pwsh path.
Run as an ordinary user in a writable directory. Preparation starts no service.

1. bash CheckPackage.sh (hashes, engine identity, native libraries; no service).
2. bash RoomKit.sh start (creates an isolated instance; defaults to loopback).
3. Open the printed URL in this Linux machine's browser. From another machine
   forward the same panel port with SSH; never expose the administrator port.
4. Set an administrator, start the game host in the panel, create invitations.
5. bash RoomKit.sh status (inspect without stopping).
6. bash RoomKit.sh stop (request shutdown; no signals).

Ports/address can be set on first start with --panel-port, --lobby-port,
--control-port, --udp-range, --bind. Data/HOME/cache/tmp live in data/instance-NAME.
Use --instance NAME consistently. Stop before moving/removing the directory.
The package also writes run/ and games/<game>/server.log; keep it writable.
Godot runtime notices are in GODOT-LICENSE.txt and GODOT-COPYRIGHT.txt.
Windows player clients are distributed separately and must match games.json.
This candidate has not been proven on every Linux distribution or on ARM.

Offline update (same supported database versions only): stop the old instance
with its own RoomKit.sh first. In the new package run UpdateRoomKit.sh prepare
--old-package ABS_OLD --new-package ABS_NEW --instance NAME. Then verify and seal
with --new-package ABS_NEW --instance NAME, before RoomKit.sh start --instance NAME.
status inspects the update journal; rollback only cancels an untouched unsealed
candidate. All files and snapshots remain. It never restores old data over new
writes, starts a service, upgrades database formats, or deletes the old package.
Even startup writes prevent automatic rollback. Failed startup needs review.
'@
$checksums=foreach($file in Get-ChildItem -LiteralPath $bundle -Recurse -File | Sort-Object FullName){$relative=$file.FullName.Substring($bundle.Length+1).Replace('\','/');(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$relative}
WriteUtf8 (Join-Path $bundle 'SHA256SUMS.txt') (($checksums -join "`n")+"`n")
WriteUtf8 (Join-Path $work 'build-result.json') (@{bundle=$bundle;work=$work;source_index=$sourceIndex;build=$id;source_commit=$base;files=@($checksums).Count;shooter=$games.shooter.manifest.build_id;turns=$games.turns.manifest.build_id}|ConvertTo-Json)
Write-Output ('LINUX_SERVER_DIRECTORY '+$bundle)
Write-Output ('LINUX_BUILD_EVIDENCE '+$work)
$buildOutcome='success'
} finally {
# Retention is available when integrated with the project artifact manager.
$retention=Join-Path $PSScriptRoot 'artifact_retention.ps1'
if(Test-Path -LiteralPath $retention -PathType Leaf){
    try {
        . $retention
        if(Test-Path -LiteralPath $work -PathType Container){
            Register-RoomKitArtifact -ProjectRoot $project -Category 'linux-server-build' -Paths @($work) -Outcome $buildOutcome -Summary @{bundle=$bundle;build=$id;source_commit=$base}|Out-Null
            Invoke-RoomKitArtifactRetention -ProjectRoot $project -Category 'linux-server-build' -ProtectedPaths @($bundle,$sourceIndex)|Out-Null
        }
        # Paired deliveries own the whole parent; do not independently delete
        # their Server child and invalidate the parent's immutable fingerprint.
        if($bundle.StartsWith((Join-Path $project 'artifacts/deployments')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -eq $false -and (Test-Path -LiteralPath $bundle -PathType Container)){
            Register-RoomKitArtifact -ProjectRoot $project -Category 'linux-server-directory' -Paths @($bundle) -Outcome $buildOutcome -Summary @{build=$id;source_commit=$base}|Out-Null
            Invoke-RoomKitArtifactRetention -ProjectRoot $project -Category 'linux-server-directory' -ProtectedPaths @($bundle)|Out-Null
        }
    }catch{Write-Warning 'ARTIFACT_RETENTION_SKIPPED linux_build_registration_or_cleanup_failed'}
}
}
