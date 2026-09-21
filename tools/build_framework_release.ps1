param(
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$id=[Guid]::NewGuid().ToString('N')
$work=Join-Path $project ('artifacts\framework-release-work-'+$id)
$bundle=Join-Path $project ('artifacts\RoomKit-0.5.0-framework-windows-'+$id)
$source=Join-Path $work 'host-project'
$templates=Join-Path ([IO.Path]::GetDirectoryName($Godot)) 'editor_data\export_templates\4.7.2.stable'
$template=Join-Path $templates 'windows_release_x86_64.exe'
$utf8=New-Object Text.UTF8Encoding($false)
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Godot editor executable is missing.' }
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw 'The tested Godot 4.7.2 Windows release export template is missing.' }
New-Item -ItemType Directory -Force -Path $work,$source,$bundle,(Join-Path $project 'logs') | Out-Null
$helpers=@('bounded_helper.ps1','process_identity.ps1','protect_runtime.ps1','protect_data.ps1','sqlite_store.ps1','account_store.ps1','operator_maintenance.ps1')
$preset=@'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
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
function WriteUtf8([string]$Path,[string]$Text) {
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function CopyRuntime([string]$From,[string]$To) {
    foreach($file in Get-ChildItem -LiteralPath $From -File -Recurse) {
        if($file.Extension -notin @('.gd','.json','.tscn','.html') -or $file.Name -in @('preview.gd','test_runner.gd')) { continue }
        $relative=$file.FullName.Substring($From.Length+1)
        $destination=Join-Path $To $relative
        New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($destination)) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
function SetMainLoop([string]$Project,[string]$Entry) {
    WriteUtf8 (Join-Path $Project 'main.gd') ("class_name FrameworkExportMain`nextends `""+$Entry+"`"`n")
    WriteUtf8 (Join-Path $Project 'empty.tscn') "[gd_scene format=3]`n[node name=`"Bootstrap`" type=`"Node`"]`n"
    $file=Join-Path $Project 'project.godot'
    $text=[IO.File]::ReadAllText($file) -replace '(?m)^run/main_scene=.*\r?\n','' -replace '(?m)^run/main_loop_type=.*\r?\n',''
    $text=$text.Replace('[application]',"[application]`nrun/main_loop_type=`"FrameworkExportMain`"`nrun/main_scene=`"res://empty.tscn`"")
    WriteUtf8 $file $text
}
function ExportPack([string]$ProjectPath,[string]$Pack,[string]$Label) {
    WriteUtf8 (Join-Path $ProjectPath 'export_presets.cfg') $preset
    $arguments=@('--headless','--path',$ProjectPath,'--export-pack','Windows Desktop',$Pack)
    $quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $stdout=Join-Path $project ('logs\framework-export-'+$id+'-'+$Label+'.log')
    $stderr=Join-Path $project ('logs\framework-export-'+$id+'-'+$Label+'-stderr.log')
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $ownedHandle=$process.Handle
    if(-not $process.WaitForExit(120000)) { $process.Kill(); $process.WaitForExit(); throw ('Export timed out: '+$Label) }
    if($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Pack -PathType Leaf) -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' -Quiet)) { throw ('Export failed: '+$Label+'; see '+$stderr) }
    Write-Output ('FRAMEWORK_EXPORT_OK '+$Label)
}
function WriteCmd([string]$Path,[string]$Command) {
    WriteUtf8 $Path ("@echo off`r`ncd /d `"%~dp0`"`r`n"+$Command+"`r`nset `"result=%errorlevel%`"`r`nif not `"%result%`"==`"0`" pause`r`nexit /b %result%`r`n")
}

# Copy only this repository's runtime sources. Existing demonstration release
# metadata and source game manifests are never modified by this build.
foreach($directory in @('host','sdk','schemas','config','examples')) {
    CopyRuntime (Join-Path $project $directory) (Join-Path $source $directory)
}
foreach($helper in $helpers) {
    foreach($target in @((Join-Path $source 'tools'),(Join-Path $bundle 'tools'))) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item -LiteralPath (Join-Path $project ('tools\'+$helper)) -Destination $target
    }
}
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $source
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination $bundle
$sourceIndex=Join-Path $work 'framework-games.source.json'
& (Join-Path $PSScriptRoot 'build_framework.ps1') -IndexPath $sourceIndex
$games=Get-Content -Encoding UTF8 -Raw -LiteralPath $sourceIndex | ConvertFrom-Json
$index=@{}
foreach($game in @('shooter','turns')) {
    $entry=$games.$game
    $entry.manifest.godot_version='4.7.2.stable.official.ed1daf0bf'
    $entry.manifest.sdk_version='0.5.0'
    $entry.manifest.build_id=$game+'-framework-win-001'
    $entry.manifest.compatibility_id=$game+'-framework-win-v1'
    $entry.manifest.server_artifact=$game+'-framework-win-v1'
    $manifestText=$entry.manifest | ConvertTo-Json -Depth 20
    WriteUtf8 (Join-Path $entry.project 'game_manifest.json') $manifestText
    WriteUtf8 (Join-Path $entry.project 'game\game_manifest.json') $manifestText
    $serverDirectory=Join-Path $bundle ('games\'+$game)
    $clientDirectory=Join-Path $bundle ('clients\'+$game)
    New-Item -ItemType Directory -Force -Path $serverDirectory,$clientDirectory | Out-Null
    $index[$game]=@{project=('games/'+$game);server_pack=('games/'+$game+'/Server.pck');server_executable=('games/'+$game+'/Server.exe');client_pack=('clients/'+$game+'/Client.pck');client_executable=('clients/'+$game+'/Client.exe');manifest=$entry.manifest}
    if(-not $PrepareOnly) {
        SetMainLoop $entry.project 'res://game/room.gd'
        ExportPack $entry.project (Join-Path $serverDirectory 'Server.pck') ($game+'-server')
        Copy-Item -LiteralPath $template -Destination (Join-Path $serverDirectory 'Server.exe')
        SetMainLoop $entry.project 'res://client.gd'
        ExportPack $entry.project (Join-Path $clientDirectory 'Client.pck') ($game+'-client')
        Copy-Item -LiteralPath $template -Destination (Join-Path $clientDirectory 'Client.exe')
    }
}
WriteUtf8 (Join-Path $bundle 'artifacts\framework-games.json') ($index | ConvertTo-Json -Depth 30)
if(-not $PrepareOnly) {
    SetMainLoop $source 'res://host/operator.gd'
    ExportPack $source (Join-Path $bundle 'Operator.pck') 'operator'
    Copy-Item -LiteralPath $template -Destination (Join-Path $bundle 'Operator.exe')
    SetMainLoop $source 'res://host/managed_host.gd'
    ExportPack $source (Join-Path $bundle 'ManagedHost.pck') 'managed-host'
    Copy-Item -LiteralPath $template -Destination (Join-Path $bundle 'ManagedHost.exe')
}

$launcher=@'
param([ValidateSet('panel','client','stop','verify','publish-clients')][string]$Operation='panel',[ValidateSet('shooter','turns')][string]$Game='shooter',[ValidateRange(1024,65535)][int]$PanelPort=28291,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$utf8=New-Object Text.UTF8Encoding($false)
Set-Location -LiteralPath $packageRoot
function QuoteArgs($Arguments) { return @($Arguments | ForEach-Object { '"'+([string]$_ -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }) }
function PublishClients {
    $configuration=Join-Path $packageRoot 'artifacts\client\connection.json'
    $certificate=Join-Path $packageRoot 'artifacts\client\server.crt'
    if(-not (Test-Path -LiteralPath $configuration) -or -not (Test-Path -LiteralPath $certificate)) { throw 'Start the management panel first to publish the public connection configuration.' }
    $connection=Get-Content -Encoding UTF8 -Raw -LiteralPath $configuration | ConvertFrom-Json
    $connection.ca_certificate='server.crt'
    foreach($gameId in @('shooter','turns')) {
        $destination=Join-Path $packageRoot ('clients\'+$gameId)
        Copy-Item -LiteralPath $certificate -Destination (Join-Path $destination 'server.crt') -Force
        [IO.File]::WriteAllText((Join-Path $destination 'connection.json'),($connection | ConvertTo-Json -Depth 12),$utf8)
    }
}
if($Operation -eq 'verify') {
    $manifest=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $packageRoot 'checksums.json') | ConvertFrom-Json
    foreach($file in $manifest.files) {
        $path=[IO.Path]::GetFullPath((Join-Path $packageRoot $file.path))
        if(-not $path.StartsWith($packageRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256) { throw ('Package checksum mismatch: '+$file.path) }
    }
    Write-Output ('FRAMEWORK_PACKAGE_VALID files='+$manifest.files.Count)
    exit 0
}
if($Operation -eq 'stop') {
    $data=Join-Path $packageRoot 'data\framework'
    if(-not (Test-Path -LiteralPath $data -PathType Container)) { throw 'The management service has not initialized this package.' }
    [IO.File]::WriteAllText((Join-Path $data 'operator-stop.request'),'stop',$utf8)
    Write-Output 'FRAMEWORK_STOP_REQUESTED: the operator will stop its owned host and rooms, then exit.'
    exit 0
}
if($Operation -eq 'publish-clients') { PublishClients; Write-Output 'PUBLIC_CLIENT_CONFIG_READY'; exit 0 }
if($Operation -eq 'client') {
    PublishClients
    $clientDirectory=Join-Path $packageRoot ('clients\'+$Game)
    & (Join-Path $clientDirectory 'RunGame.ps1')
    exit 0
}
& (Join-Path $packageRoot 'tools\protect_runtime.ps1') -ProjectRoot $packageRoot
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot 'logs') | Out-Null
$descriptor=Join-Path $packageRoot 'data\framework\operator.json'
$existing=$null
if(Test-Path -LiteralPath $descriptor) {
    try {
        $record=Get-Content -Encoding UTF8 -Raw -LiteralPath $descriptor | ConvertFrom-Json
        $recordPid=0; $recordPort=0
        if(-not [int]::TryParse([string]$record.pid,[ref]$recordPid) -or $recordPid -le 0 -or -not [int]::TryParse([string]$record.port,[ref]$recordPort) -or $recordPort -lt 1 -or $recordPort -gt 65535) { throw 'Invalid descriptor fields.' }
        $candidate=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$recordPid) -ErrorAction Stop
    } catch { throw 'Cannot verify the existing operator descriptor. Refusing duplicate startup; inspect data/framework/operator.json.' }
    $responds=$false
    [Net.ServicePointManager]::Expect100Continue=$false
    try {
        $reply=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$recordPort+'/api') -Method Post -ContentType 'application/json' -Body '{"action":"setup.status","payload":{}}' -TimeoutSec 3
        $responds=$reply.ok -eq $true
    } catch { $responds=$false }
    if($null -ne $candidate) {
        if($candidate.ExecutablePath -ieq (Join-Path $packageRoot 'Operator.exe') -and $responds) {
            $listeners=@(Get-NetTCPConnection -State Listen -LocalAddress 127.0.0.1 -LocalPort $recordPort -ErrorAction SilentlyContinue | Where-Object OwningProcess -eq $recordPid)
            if($listeners.Count -eq 1) { $existing=$record }
        }
        if($null -eq $existing) { throw 'The descriptor PID still exists but this package HTTP service could not be verified. Refusing duplicate startup or PID-based termination.' }
    } else {
        if($responds) { throw 'The recorded process is gone but its HTTP address responds. Refusing to adopt another service.' }
        # Only a confirmed absent PID plus unavailable HTTP permits deleting
        # these two fixed stale signal files, never databases or process journals.
        Remove-Item -LiteralPath $descriptor -Force
        $staleStop=Join-Path $packageRoot 'data\framework\operator-stop.request'
        if(Test-Path -LiteralPath $staleStop -PathType Leaf) { Remove-Item -LiteralPath $staleStop -Force }
    }
}
if($null -eq $existing) {
    $arguments=QuoteArgs @('--headless','--log-file',(Join-Path $packageRoot 'logs\operator.log'),'--',('--panel-port='+$PanelPort))
    $process=Start-Process -FilePath (Join-Path $packageRoot 'Operator.exe') -ArgumentList $arguments -WorkingDirectory $packageRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $packageRoot 'logs\operator-console.log') -RedirectStandardError (Join-Path $packageRoot 'logs\operator-stderr.log')
    $ownedHandle=$process.Handle
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    while([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if($process.HasExited) { throw 'Operator exited during startup. Inspect logs/operator-stderr.log and logs/operator.log.' }
        if(Test-Path -LiteralPath $descriptor) {
            try { $record=Get-Content -Encoding UTF8 -Raw -LiteralPath $descriptor | ConvertFrom-Json } catch { $record=$null }
            if($null -ne $record -and [int]$record.pid -eq $process.Id) { $existing=$record; break }
        }
        Start-Sleep -Milliseconds 200
    }
    if($null -eq $existing) {
        $process.Kill() # Only the startup process created above, held by this handle.
        $process.WaitForExit()
        throw 'Operator startup exceeded 90 seconds. Inspect the package logs.'
    }
}
PublishClients
$url='http://127.0.0.1:'+([int]$existing.port)
if(-not $NoBrowser) { Start-Process $url }
Write-Output ('FRAMEWORK_PANEL_READY '+$url)
'@
WriteUtf8 (Join-Path $bundle 'RunFramework.ps1') $launcher
WriteCmd (Join-Path $bundle 'StartPanel.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation panel %*'
WriteCmd (Join-Path $bundle 'StopFramework.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation stop %*'
WriteCmd (Join-Path $bundle 'CheckFramework.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation verify %*'
WriteCmd (Join-Path $bundle 'StartShooter.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation client -Game shooter %*'
WriteCmd (Join-Path $bundle 'StartTurns.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation client -Game turns %*'
WriteCmd (Join-Path $bundle 'PublishClients.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunFramework.ps1" -Operation publish-clients %*'
$playerLauncher=@'
param()
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot)
$configuration=Join-Path $directory 'connection.json'
if(-not (Test-Path -LiteralPath $configuration -PathType Leaf)) { throw 'Missing public connection.json. On the server run StartPanel.cmd then PublishClients.cmd, and copy this entire client directory.' }
$arguments=@('--','--game=__GAME__',('--connection-config='+$configuration))
$quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
Start-Process -FilePath (Join-Path $directory 'Client.exe') -ArgumentList $quoted -WorkingDirectory $directory | Out-Null
'@
foreach($game in @('shooter','turns')) {
    $directory=Join-Path $bundle ('clients\'+$game)
    WriteUtf8 (Join-Path $directory 'RunGame.ps1') $playerLauncher.Replace('__GAME__',$game)
    WriteCmd (Join-Path $directory 'StartGame.cmd') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RunGame.ps1" %*'
}
$readme=@'
# RoomKit 0.5.0 framework Windows candidate

This package is independent of the previous demonstration release. Godot editor,
Node.js and an external database server are not required. Windows PowerShell and
Windows' built-in winsqlite3.dll are required. Extract to a writable directory.

1. Run CheckFramework.cmd to verify immutable package files.
2. Run StartPanel.cmd. Create the administrator, then start the game server from
   the browser. The management panel stays available when the game host stops.
3. Generate a player invitation. StartShooter.cmd and StartTurns.cmd open the two
   game clients. Run an entry twice to open two player windows, using two accounts.
4. Stop the game server in the browser; StopFramework.cmd also stops the operator.
5. For LAN testing, stop the game host, set the advertised IP in the panel, then
   run PublishClients.cmd. Copy clients/shooter or clients/turns as a complete
   folder to the player machine and run StartGame.cmd. These directories contain
   the public connection configuration and certificate only, never server.key,
   administrator tokens or account databases. Firewall changes are not automatic.

Runtime data is kept in data/framework; private bootstrap files are under run;
logs are under logs. Keep backups before replacing this package. Do not copy old
game projects or databases into it. Backups contain sensitive server data and
must not be included in a player distribution.

Operator.exe, ManagedHost.exe and each game server/client use their matching PCK
with a fixed MainLoop entry. Do not launch them using --script/--main-pack overrides.
The package checksum list does not include runtime configuration or private data.

The build itself does not prove multiplayer, restart, restore or LAN acceptance.
Use the branch STATUS.md for actual test results and unverified environments.
'@
WriteUtf8 (Join-Path $bundle 'README.md') $readme
Copy-Item -LiteralPath (Join-Path $project 'docs\19_admin_ui.md') -Destination (Join-Path $bundle 'ADMIN_GUIDE_ZH.md')

# Validate all produced PowerShell files before publishing an index.
foreach($file in Get-ChildItem -LiteralPath $bundle -Filter '*.ps1' -Recurse -File) {
    $parseTokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$parseTokens,[ref]$parseErrors)
    if($parseErrors.Count) { throw ('PowerShell parse failure: '+$file.FullName+' '+$parseErrors[0].Message) }
}
$metadata=@{format=1;version='0.5.0-framework-candidate';engine='4.7.2.stable.official.ed1daf0bf';bundle=$bundle;work=$work;source_index=$sourceIndex;prepared_only=[bool]$PrepareOnly}
if(-not $PrepareOnly) {
    $checksums=@{version='0.5.0-framework-candidate';engine=$metadata.engine;files=@()}
    foreach($file in Get-ChildItem -LiteralPath $bundle -Recurse -File) {
        $relative=$file.FullName.Substring($bundle.Length+1).Replace('\','/')
        if($relative -match '(^|/)(data|run|logs)/|\.key$|\.sqlite(?:-|$)|(^|/)(preview|test_runner)\.gd$') { throw ('Unexpected private or fixture artifact: '+$relative) }
        $checksums.files+=@{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    WriteUtf8 (Join-Path $bundle 'checksums.json') ($checksums | ConvertTo-Json -Depth 20)
    $archive=$bundle+'.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($bundle,$archive,[IO.Compression.CompressionLevel]::Optimal,$false)
    $metadata.archive=$archive
    $metadata.sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata.immutable_files=$checksums.files.Count
}
WriteUtf8 (Join-Path $project 'artifacts\framework-release.json') ($metadata | ConvertTo-Json -Depth 20)
Write-Output (('FRAMEWORK_RELEASE_PREPARED ',$bundle) -join '')
if(-not $PrepareOnly) { Write-Output ('FRAMEWORK_RELEASE_BUILD_OK '+$bundle) }
