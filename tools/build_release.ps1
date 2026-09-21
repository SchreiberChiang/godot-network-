param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$id=[Guid]::NewGuid().ToString('N')
$work=Join-Path $project ('artifacts\release-work-'+$id)
$bundle=Join-Path $project ('artifacts\RoomKit-0.1.0-windows-'+$id)
$templates=Join-Path ([IO.Path]::GetDirectoryName($Godot)) 'editor_data\export_templates\4.7.2.stable'
$utf8=New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $work,$bundle | Out-Null
foreach($directory in @('host','sdk','schemas','config','examples','tests','tools','release')) { Copy-Item -LiteralPath (Join-Path $project $directory) -Destination $work -Recurse }
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $work
$preset=@'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
export_filter="all_resources"
include_filter="*.json,*.gd,*.tscn,*.ps1,*.sh,*.html"
exclude_filter=""
export_path=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'@
function Export-Pack([string]$Source,[string]$Destination,[string]$Label) {
    [IO.File]::WriteAllText((Join-Path $Source 'export_presets.cfg'),$preset,$utf8)
    $arguments=@('--headless','--path',$Source,'--export-pack','Windows Desktop',$Destination)
    $quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $stdout=Join-Path $project ('logs\export-'+$Label+'.log')
    $stderr=Join-Path $project ('logs\export-'+$Label+'-stderr.log')
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $handle=$process.Handle
    if(-not $process.WaitForExit(120000)) { $process.Kill(); $process.WaitForExit(); throw "Export timed out: $Label" }
    if($process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $Destination) -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) { throw "Export failed: $Label; inspect $stderr" }
    Write-Output "EXPORT_PACK_OK $Label"
}
function Set-MainLoop([string]$Source,[string]$Entry) {
    [IO.File]::WriteAllText((Join-Path $Source 'main.gd'),("class_name RoomKitMain`nextends `""+$Entry+"`"`n"),$utf8)
    [IO.File]::WriteAllText((Join-Path $Source 'empty.tscn'),("[gd_scene format=3]`n[node name=`"Bootstrap`" type=`"Node`"]`n"),$utf8)
    $projectFile=Join-Path $Source 'project.godot'
    $settings=[IO.File]::ReadAllText($projectFile) -replace '(?m)^run/main_scene=.*\r?\n','' -replace '(?m)^run/main_loop_type=.*\r?\n',''
    $settings=$settings.Replace('[application]',"[application]`nrun/main_loop_type=`"RoomKitMain`"`nrun/main_scene=`"res://empty.tscn`"")
    [IO.File]::WriteAllText($projectFile,$settings,$utf8)
}
Set-MainLoop $work 'res://release/host.gd'
Export-Pack $work (Join-Path $bundle 'RoomHost.pck') 'host'
Copy-Item -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe') -Destination (Join-Path $bundle 'RoomHost.exe')
Copy-Item -LiteralPath (Join-Path $project 'tools') -Destination (Join-Path $bundle 'tools') -Recurse
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $project 'release\Run.ps1'),(Join-Path $project 'release\StartRoomKit.cmd'),(Join-Path $project 'release\Manage.ps1'),(Join-Path $project 'release\StopRoomKit.cmd'),(Join-Path $project 'release\CheckRoomKit.cmd'),(Join-Path $project 'release\README.md') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $project 'release\StartPanel.cmd') -Destination $bundle
& (Join-Path $PSScriptRoot 'build_games.ps1')
$games=Get-Content -Encoding UTF8 -Raw (Join-Path $project 'artifacts\games.json') | ConvertFrom-Json
$index=@{}
foreach($game in @('blocks','turns')) {
    $target=Join-Path $bundle ('games\'+$game)
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $games.$game.manifest.godot_version='4.7.2.stable.official.ed1daf0bf'
    $games.$game.manifest.build_id=$game+'-win-001'
    $games.$game.manifest.compatibility_id=$game+'-win-v1'
    $games.$game.manifest.server_artifact=$game+'-win-v1'
    [IO.File]::WriteAllText((Join-Path $games.$game.project 'game_manifest.json'),($games.$game.manifest | ConvertTo-Json -Depth 20),$utf8)
    Set-MainLoop $games.$game.project 'res://game/room.gd'
    Export-Pack $games.$game.project (Join-Path $target 'Server.pck') ($game+'-server')
    Set-MainLoop $games.$game.project 'res://client.gd'
    Export-Pack $games.$game.project (Join-Path $target 'Client.pck') ($game+'-client')
    Copy-Item -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe') -Destination (Join-Path $target 'Server.exe')
    Copy-Item -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe') -Destination (Join-Path $target 'Client.exe')
    $index[$game]=@{project=('games/'+$game);server_pack=('games/'+$game+'/Server.pck');client_pack=('games/'+$game+'/Client.pck');server_executable=('games/'+$game+'/Server.exe');client_executable=('games/'+$game+'/Client.exe');manifest=$games.$game.manifest}
}
[IO.File]::WriteAllText((Join-Path $bundle 'games.json'),($index | ConvertTo-Json -Depth 30),$utf8)
$manifest=@{version='0.1.0-candidate';engine='4.7.2.stable.official.ed1daf0bf';files=@()}
foreach($file in Get-ChildItem -LiteralPath $bundle -Recurse -File) { $manifest.files+=@{path=$file.FullName.Substring($bundle.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} }
[IO.File]::WriteAllText((Join-Path $bundle 'checksums.json'),($manifest | ConvertTo-Json -Depth 20),$utf8)
$validation=Join-Path $work 'validation'
New-Item -ItemType Directory -Path $validation | Out-Null
[IO.File]::WriteAllText((Join-Path $validation '.gdignore'),'',$utf8)
Copy-Item -LiteralPath (Join-Path $project 'tools') -Destination $validation -Recurse
Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $validation
Set-MainLoop $work 'res://tests/test_launcher_real.gd'
Export-Pack $work (Join-Path $validation 'LauncherCheck.pck') 'launcher-check'
Copy-Item -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe') -Destination (Join-Path $validation 'LauncherCheck.exe')
Set-MainLoop $work 'res://tests/run_portable.gd'
Export-Pack $work (Join-Path $validation 'PortableCheck.pck') 'portable-check'
Copy-Item -LiteralPath (Join-Path $templates 'linux_release.x86_64') -Destination (Join-Path $validation 'PortableCheck.x86_64')
[IO.File]::WriteAllText((Join-Path $project 'artifacts\release.json'),(@{bundle=$bundle;work=$work;validation=$validation} | ConvertTo-Json),$utf8)
Write-Output ('RELEASE_BUILD_OK '+$bundle)
