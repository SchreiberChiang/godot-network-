param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('legacy','rollback')][string]$Mode='legacy')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$directoryPath=[IO.Path]::GetFullPath($Directory)
$allowedParent=Join-Path $project 'data'
if ([IO.Path]::GetDirectoryName($directoryPath) -ne $allowedParent -or [IO.Path]::GetFileName($directoryPath) -notmatch '^test-assets-[a-f0-9]{32}$') { throw 'Fixture must be in this test run directory.' }
$protection=& (Join-Path $project 'tools/protect_data.ps1') -ProjectRoot $project -DataRoot $directoryPath
if ($protection -notcontains 'PRIVATE_DATA_READY') { throw 'Private fixture directory failed.' }
$database=Join-Path $directoryPath 'assets.sqlite'
if ($Mode -eq 'legacy' -and (Test-Path -LiteralPath $database)) { throw 'Refusing to overwrite existing database.' }
# Reuse the production native binding without executing its request dispatcher.
$source=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $binding.Success) { throw 'Native binding not found.' }
Add-Type -TypeDefinition $binding.Groups[1].Value
$databaseHandle=New-Object RoomKitSqlite($database)
try {
    if ($Mode -eq 'legacy') {
        [void]$databaseHandle.Query('CREATE TABLE launches (launch_id TEXT PRIMARY KEY, room_id TEXT NOT NULL, game_id TEXT NOT NULL, build_id TEXT NOT NULL, secret TEXT NOT NULL)',@())
        [void]$databaseHandle.Query('CREATE TABLE results (result_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, match_id TEXT NOT NULL, result_kind TEXT NOT NULL, record_hash TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(game_id,match_id,result_kind))',@())
        [void]$databaseHandle.Query('INSERT INTO results (result_id,game_id,match_id,result_kind,record_hash,body) VALUES (?,?,?,?,?,?)',@('legacy-result','turns','legacy-match','final','fixture','{"fixture":"preserve-me"}'))
        [void]$databaseHandle.Query('PRAGMA user_version=1',@())
    } else {
        # Force an error after asset_states changes but before receipt commit.
        [void]$databaseHandle.Query("CREATE TRIGGER reject_fixture_receipt BEFORE INSERT ON asset_receipts WHEN NEW.user_id='rollback-user' BEGIN SELECT RAISE(ABORT,'fixture'); END",@())
    }
} finally { $databaseHandle.Dispose() }
Write-Output 'ASSET_DATABASE_FIXTURE_OK'
