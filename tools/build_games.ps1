param()
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $projectRoot ('artifacts\games-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$entries = @{}
foreach ($item in @(@{id='blocks';source='blocks'}, @{id='turns';source='turn_based'})) {
    $destination = Join-Path $buildRoot $item.id
    New-Item -ItemType Directory -Force -Path (Join-Path $destination 'game'),(Join-Path $destination 'schemas') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'sdk') -Destination (Join-Path $destination 'sdk') -Recurse
    foreach ($script in @('game.gd','adapter.gd','room.gd')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot ('examples\' + $item.source + '\' + $script)) -Destination (Join-Path $destination 'game')
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot ('examples\' + $item.source + '\game_manifest.json')) -Destination $destination
    foreach ($script in @('client.gd','view.gd')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot ('examples\showcase\' + $script)) -Destination $destination
    }
    foreach ($schema in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'schemas') -Filter '*.json' -File) {
        if ($schema.Name -match '^(blocks|turns)_' -and -not $schema.Name.StartsWith($item.id + '_')) { continue }
        Copy-Item -LiteralPath $schema.FullName -Destination (Join-Path $destination 'schemas')
    }
    $projectText = @'
config_version=5
[application]
config/name="RoomKit Game"
[display]
window/size/viewport_width=820
window/size/viewport_height=650
[rendering]
renderer/rendering_method="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
'@
    [IO.File]::WriteAllText((Join-Path $destination 'project.godot'), $projectText, $utf8)
    $manifest = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $destination 'game_manifest.json') | ConvertFrom-Json
    $entries[$item.id] = @{project=$destination;manifest=$manifest}
}
[IO.File]::WriteAllText((Join-Path $projectRoot 'artifacts\games.json'), ($entries | ConvertTo-Json -Depth 15), $utf8)
Write-Output ('BUILD_GAMES_OK ' + $buildRoot)
