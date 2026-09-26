param([ValidatePattern('^[a-z][a-z0-9_]{2,31}$')][string]$GameId='starter_game',[string]$Destination='',[switch]$Managed)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Assert-WorkspacePath([string]$Path) {
    $resolved=[IO.Path]::GetFullPath($Path)
    if(-not [string]::Equals($resolved,$project,[StringComparison]::OrdinalIgnoreCase) -and -not $resolved.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Generation paths must be inside this workspace.' }
    $ancestor=$resolved
    while($ancestor) {
        if(Test-Path -LiteralPath $ancestor) {
            if((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Generation paths must not contain reparse points.' }
        }
        if([string]::Equals($ancestor,$project,[StringComparison]::OrdinalIgnoreCase)) { break }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
}
if(-not $Destination) { $Destination=Join-Path $project ('artifacts\'+$GameId+'-'+[Guid]::NewGuid().ToString('N')) }
$Destination=[IO.Path]::GetFullPath($Destination)
if(-not $Destination.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must be inside this workspace.' }
Assert-WorkspacePath $Destination
if(Test-Path -LiteralPath $Destination) { throw 'Destination already exists; refusing to overwrite it.' }
$templateDirectory=Join-Path $project $(if($Managed){'templates/managed_game'}else{'templates/game'})
foreach($source in @((Join-Path $project 'sdk'),(Join-Path $project 'schemas'),$templateDirectory)) {
    if($Destination.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must not be inside a copied source directory.' }
}
$artifacts=Join-Path $project 'artifacts'
$indexPath=Join-Path $artifacts $(if($Managed){'managed-template.json'}else{'template.json'})
Assert-WorkspacePath $indexPath
if((Test-Path -LiteralPath $indexPath) -and -not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { throw 'The generated index path must be a file.' }
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
New-Item -ItemType Directory -Path $Destination | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'sdk') -Destination $Destination -Recurse
Copy-Item -LiteralPath (Join-Path $project 'schemas') -Destination $Destination -Recurse
foreach($entry in Get-ChildItem -LiteralPath $templateDirectory -Force) {
    if($entry.PSIsContainer -and $entry.Name -eq 'schemas') {
        foreach($schema in Get-ChildItem -LiteralPath $entry.FullName -File) { Copy-Item -LiteralPath $schema.FullName -Destination (Join-Path $Destination 'schemas') }
    } else { Copy-Item -LiteralPath $entry.FullName -Destination $Destination -Recurse }
}
$manifest=Get-Content -Encoding UTF8 -Raw (Join-Path $project 'examples/minimal/multiplayer_manifest.json') | ConvertFrom-Json
$manifest.game_id=$GameId
$manifest.build_id=$GameId+'-dev-001'
$manifest.compatibility_id=$GameId+'-v1'
$manifest.server_artifact=$GameId+'-project-v1'
if($Managed) {
    $manifest.sdk_version='0.5.0'
    $manifest.build_id=$GameId+'-managed-dev-001'
    $manifest.compatibility_id=$GameId+'-managed-v1'
    $manifest.server_artifact=$GameId+'-managed-project-v1'
}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Destination 'game_manifest.json'),($manifest | ConvertTo-Json -Depth 20),$utf8)
[IO.File]::WriteAllText((Join-Path $Destination 'project.godot'),("config_version=5`n[application]`nconfig/name=`""+$GameId+"`"`n[rendering]`nrenderer/rendering_method=`"gl_compatibility`"`n"),$utf8)
if($Managed) {
    $catalog=Get-Content -LiteralPath (Join-Path $Destination 'asset_catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $space=$catalog.spaces.starter_game
    $game=$catalog.games.starter_game
    $game.space=$GameId
    $catalog.spaces=@{$GameId=$space}
    $catalog.games=@{$GameId=$game}
    [IO.File]::WriteAllText((Join-Path $Destination 'asset_catalog.json'),($catalog | ConvertTo-Json -Depth 20),$utf8)
    $index=@{$GameId=@{project=$Destination;manifest=$manifest;name=$GameId;asset_catalog=(Join-Path $Destination 'asset_catalog.json');asset_policy=(Join-Path $Destination 'game/asset_policy.gd');result_schema=(Join-Path $Destination 'schemas/template_result.schema.json')}}
    $indexText=$index | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText((Join-Path $Destination 'managed-games.json'),$indexText,$utf8)
} else {
    $indexText=@{project=$Destination;manifest=$manifest} | ConvertTo-Json -Depth 20
}
# Publish by replacing the index file rather than writing through an existing
# hard link. The previous index remains intact until generation has completed.
Assert-WorkspacePath $indexPath
$temporary=Join-Path $artifacts ('new-game-index-'+[Guid]::NewGuid().ToString('N')+'.tmp')
try {
    [IO.File]::WriteAllText($temporary,$indexText,$utf8)
    if(Test-Path -LiteralPath $indexPath) { [IO.File]::Replace($temporary,$indexPath,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$indexPath) }
} finally {
    if(Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
Write-Output ('NEW_GAME_OK '+$Destination)
