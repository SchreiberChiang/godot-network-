# BuildRoot: parent folder of the prepared game projects (default: artifacts);
# the Linux start entry keeps them inside its instance folder.
param([string]$IndexPath = '', [string]$BuildRoot = '')
$ErrorActionPreference='Stop'
# Runs under Windows PowerShell 5.1 and pwsh on Linux: paths use '/', which both accept.
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$sep=[string][IO.Path]::DirectorySeparatorChar
$comparison=if ($sep -eq '/') { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
if ($BuildRoot -eq '') { $BuildRoot=Join-Path $projectRoot 'artifacts' }
$BuildRoot=[IO.Path]::GetFullPath($BuildRoot).TrimEnd('\','/')
if (-not $BuildRoot.StartsWith($projectRoot+$sep,$comparison)) { throw 'Framework build folder must stay within this project.' }
$buildRoot=Join-Path $BuildRoot ('framework-'+[Guid]::NewGuid().ToString('N'))
$entries=@{}
$services=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $projectRoot 'examples/framework/services.json') | ConvertFrom-Json
$utf8=New-Object Text.UTF8Encoding($false)
if ($IndexPath -eq '') { $IndexPath=Join-Path $projectRoot 'artifacts/framework-games.json' }
$IndexPath=[IO.Path]::GetFullPath($IndexPath)
if (-not $IndexPath.StartsWith($projectRoot+$sep,$comparison)) { throw 'Framework index must stay within this project.' }
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($IndexPath)) | Out-Null
. (Join-Path $PSScriptRoot 'content_digest.ps1')
foreach($item in @(@{id='shooter';source='shooter'},@{id='turns';source='turn_based'})) {
    $destination=Join-Path $buildRoot $item.id
    New-Item -ItemType Directory -Force -Path (Join-Path $destination 'game'),(Join-Path $destination 'schemas') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'sdk') -Destination $destination -Recurse
    foreach($name in @('game.gd','adapter.gd','room.gd','asset_policy.gd','rewards.gd','game_config.json')) {
        $source=Join-Path $projectRoot ('examples\'+$item.source+'\'+$name)
        if(Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $destination 'game') }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot ('examples\'+$item.source+'\game_manifest.json')) -Destination $destination
    if(Test-Path -LiteralPath (Join-Path $projectRoot 'examples/framework')) {
        foreach($name in @('client.gd','view.gd','sound.gd')) { Copy-Item -LiteralPath (Join-Path $projectRoot ('examples\framework\'+$name)) -Destination $destination }
    }
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'schemas') -Filter '*.json' -File) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination 'schemas') }
    $settings=@'
config_version=5
[application]
config/name="RoomKit Game"
[display]
window/size/viewport_width=1100
window/size/viewport_height=780
[rendering]
renderer/rendering_method="gl_compatibility"
[debug]
file_logging/enable_file_logging=false
'@
    [IO.File]::WriteAllText((Join-Path $destination 'project.godot'),$settings,$utf8)
    $manifest=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $destination 'game_manifest.json') | ConvertFrom-Json
    # The legacy turns demonstration retains its original source manifest. Only
    # this managed build negotiates the accounts/assets SDK and its own identity.
    $manifest.sdk_version='0.5.0'
    if ($item.id -eq 'turns') {
        $manifest.build_id='turns-managed-dev-001'
        $manifest.compatibility_id='turns-managed-v1'
        $manifest.server_artifact='turns-managed-project-v1'
    }
    # Bind the build identity to the prepared project's content. The server index,
    # the room's manifest and every exported client come from this same directory,
    # so a client built from different code carries a different build_id and the
    # lobby rejects it (BUILD_MISMATCH) instead of admitting a stale client.
    $manifest.build_id=$manifest.build_id+'-src-'+(ContentDigest $destination)
    $manifestText=$manifest | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText((Join-Path $destination 'game_manifest.json'),$manifestText,$utf8)
    [IO.File]::WriteAllText((Join-Path $destination 'game\game_manifest.json'),$manifestText,$utf8)
    $entries[$item.id]=@{project=$destination;manifest=$manifest}
    foreach($field in $services.($item.id).PSObject.Properties) { $entries[$item.id][$field.Name]=$field.Value }
}
[IO.File]::WriteAllText($IndexPath,($entries | ConvertTo-Json -Depth 20),$utf8)
Write-Output ('BUILD_FRAMEWORK_OK '+$buildRoot)
