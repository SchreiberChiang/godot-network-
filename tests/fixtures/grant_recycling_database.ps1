param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('fill','inspect','legacy')][string]$Mode)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target=[IO.Path]::GetFullPath($Directory)
$allowed=Join-Path $project 'data'
if (-not $target.StartsWith($allowed+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $target -match '[\\/]framework([\\/]|$)') { throw 'Test fixture directory refused' }
$cursor=$target
while($cursor) {
    if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -Force -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Test fixture link refused' }
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$db=New-Object RoomKitSqlite((Join-Path $target 'assets.sqlite'))
try {
    if($Mode -eq 'legacy') {
        [void]$db.Query('CREATE TABLE launches(launch_id TEXT PRIMARY KEY,room_id TEXT NOT NULL,game_id TEXT NOT NULL,build_id TEXT NOT NULL,secret TEXT NOT NULL)',@())
        [void]$db.Query('INSERT INTO launches VALUES (?,?,?,?,?)',@(('a'*32),'legacy_room','grant_fixture','grant_build',('b'*64)))
        [void]$db.Query('PRAGMA user_version=2',@())
    } elseif($Mode -eq 'fill') {
        $remaining=256-[long]$db.Query('SELECT count(*) AS n FROM launches',@())[0]['n']
        if($remaining -gt 0) { [void]$db.Query('WITH RECURSIVE fill(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM fill WHERE n<CAST(? AS INTEGER)) INSERT INTO launches(launch_id,room_id,game_id,build_id,secret) SELECT ''fixture_''||n,''fixture_room'',''grant_fixture'',''grant_build'',? FROM fill',@([string]$remaining,('c'*64))) }
    }
    $result=@{ok=$true;count=[long]$db.Query('SELECT count(*) AS n FROM launches',@())[0]['n']}
    if($Mode -eq 'inspect') {
        $result.grants=@($db.Query('SELECT launch_id,ended_at FROM launches',@()).ToArray())
        $result.expired=@($db.Query('SELECT * FROM expired_launches',@()).ToArray())
        $result.expired_columns=@($db.Query('PRAGMA table_info(expired_launches)',@()).ToArray())
        $result.signature_count=[long]$db.Query('SELECT count(*) AS n FROM result_signatures',@())[0]['n']
    }
    $result | ConvertTo-Json -Depth 15 -Compress
} finally { $db.Dispose() }
