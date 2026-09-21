param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('inspect','block_audit','unblock_audit')][string]$Mode='inspect')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$target=[IO.Path]::GetFullPath($Directory)
if ([IO.Path]::GetDirectoryName($target) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($target) -notmatch '^test-account-recovery-[a-f0-9]{32}$') { throw 'Test fixture directory refused' }
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$db=New-Object RoomKitSqlite((Join-Path $target 'accounts.sqlite'))
try {
    if ($Mode -eq 'block_audit') { [void]$db.Query("CREATE TRIGGER reject_recovery_audit BEFORE INSERT ON account_audit WHEN NEW.action='local.reset_player_sessions' BEGIN SELECT RAISE(ABORT,'audit_fixture'); END",@()) }
    elseif ($Mode -eq 'unblock_audit') { [void]$db.Query('DROP TRIGGER reject_recovery_audit',@()) }
    @{ok=$true;player_sessions=[long]$db.Query('SELECT count(*) AS total FROM sessions s JOIN accounts a ON s.user_id=a.user_id WHERE a.role=''player''',@())[0]['total'];admin_sessions=[long]$db.Query('SELECT count(*) AS total FROM sessions s JOIN accounts a ON s.user_id=a.user_id WHERE a.role=''admin''',@())[0]['total'];recovery_audit=[long]$db.Query('SELECT count(*) AS total FROM account_audit WHERE action=''local.reset_player_sessions''',@())[0]['total'];integrity=$db.Query('PRAGMA integrity_check',@())[0]['integrity_check']} | ConvertTo-Json -Compress
} finally { $db.Dispose() }
