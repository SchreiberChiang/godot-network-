param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('fill_launches','count')][string]$Mode)
$ErrorActionPreference='Stop'
# Test-only: seeds placeholder launch grants so the 256-grant capacity check can
# be reached quickly. Placeholder secrets are fixed test strings, not real keys.
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$target=[IO.Path]::GetFullPath($Directory)
if ([IO.Path]::GetDirectoryName($target) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($target) -notmatch '^test-grant-storage-[a-f0-9]{32}$') { throw 'Test fixture directory refused' }
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$db=New-Object RoomKitSqlite((Join-Path $target 'assets.sqlite'))
try {
    if ($Mode -eq 'fill_launches') {
        $remaining=255-[long]$db.Query('SELECT count(*) AS total FROM launches',@())[0]['total']
        if ($remaining -le 0) { throw 'Fixture already filled' }
        [void]$db.Query('WITH RECURSIVE fill(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM fill WHERE n<CAST(? AS INTEGER)) INSERT INTO launches(launch_id,room_id,game_id,build_id,secret) SELECT ''fixture_''||n,''fixture_room'',''fixture_game'',''fixture_build'',''fixture-placeholder'' FROM fill',@([string]$remaining))
    }
    @{ok=$true;launch_count=[long]$db.Query('SELECT count(*) AS total FROM launches',@())[0]['total']} | ConvertTo-Json -Compress
} finally { $db.Dispose() }
