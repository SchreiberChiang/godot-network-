param([ValidatePattern('^[a-z][a-z0-9_]{2,31}$')][string]$GameId='starter_game',[string]$Destination='')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $Destination) { $Destination=Join-Path $project ('artifacts\'+$GameId+'-'+[Guid]::NewGuid().ToString('N')) }
$Destination=[IO.Path]::GetFullPath($Destination)
if(-not $Destination.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must be inside this workspace.' }
if(Test-Path -LiteralPath $Destination) { throw 'Destination already exists; refusing to overwrite it.' }
New-Item -ItemType Directory -Path $Destination | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'sdk') -Destination $Destination -Recurse
Copy-Item -LiteralPath (Join-Path $project 'schemas') -Destination $Destination -Recurse
foreach($file in Get-ChildItem -LiteralPath (Join-Path $project 'templates/game') -File) { Copy-Item -LiteralPath $file.FullName -Destination $Destination }
$manifest=Get-Content -Encoding UTF8 -Raw (Join-Path $project 'examples/minimal/multiplayer_manifest.json') | ConvertFrom-Json
$manifest.game_id=$GameId
$manifest.build_id=$GameId+'-dev-001'
$manifest.compatibility_id=$GameId+'-v1'
$manifest.server_artifact=$GameId+'-project-v1'
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Destination 'game_manifest.json'),($manifest | ConvertTo-Json -Depth 20),$utf8)
[IO.File]::WriteAllText((Join-Path $Destination 'project.godot'),("config_version=5`n[application]`nconfig/name=`""+$GameId+"`"`n[rendering]`nrenderer/rendering_method=`"gl_compatibility`"`n"),$utf8)
[IO.File]::WriteAllText((Join-Path $project 'artifacts/template.json'),(@{project=$Destination;manifest=$manifest} | ConvertTo-Json -Depth 20),$utf8)
Write-Output ('NEW_GAME_OK '+$Destination)
