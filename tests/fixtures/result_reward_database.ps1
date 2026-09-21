param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('install_failure','drop_failure','fill_capacity','count')][string]$Mode)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$target=[IO.Path]::GetFullPath($Directory)
if ([IO.Path]::GetDirectoryName($target) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($target) -notmatch '^test-result-rewards-[a-f0-9]{32}$') { throw 'Test fixture directory refused' }
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$db=New-Object RoomKitSqlite((Join-Path $target 'assets.sqlite'))
try {
    if ($Mode -eq 'install_failure') {
        [void]$db.Query("CREATE TRIGGER reject_reward_receipt BEFORE INSERT ON asset_receipts WHEN NEW.user_id='reject_user' BEGIN SELECT RAISE(ABORT,'reward_receipt_fixture'); END",@())
    } elseif ($Mode -eq 'drop_failure') {
        [void]$db.Query('DROP TRIGGER reject_reward_receipt',@())
    } elseif ($Mode -eq 'fill_capacity') {
        $remaining=99999-[long]$db.Query('SELECT count(*) AS total FROM asset_receipts',@())[0]['total']
        if ($remaining -le 0) { throw 'Fixture already filled' }
        [void]$db.Query('WITH RECURSIVE fill(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM fill WHERE n<CAST(? AS INTEGER)) INSERT INTO asset_receipts(user_id,request_id,fingerprint,space_id,actor_id,command,previous_body,body) SELECT ''capacity_fixture'',''fill_''||n,''fixture'',''fixture'',''test'',''{}'','''',''{}'' FROM fill',@([string]$remaining))
    }
    @{ok=$true;receipt_count=[long]$db.Query('SELECT count(*) AS total FROM asset_receipts',@())[0]['total'];result_count=[long]$db.Query('SELECT count(*) AS total FROM results',@())[0]['total']} | ConvertTo-Json -Compress
} finally { $db.Dispose() }
