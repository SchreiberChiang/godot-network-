param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('inspect','expire_sessions','expire_bans','expire_rates','expire_invites')][string]$Mode='inspect')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$directoryPath=[IO.Path]::GetFullPath($Directory)
if ([IO.Path]::GetDirectoryName($directoryPath) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($directoryPath) -notmatch '^test-accounts-[a-f0-9]{32}$') { throw 'Fixture path refused' }
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$handle=New-Object RoomKitSqlite((Join-Path $directoryPath 'accounts.sqlite'))
try {
    if ($Mode -eq 'expire_sessions') { [void]$handle.Query('UPDATE sessions SET expires=1 WHERE user_id IN (SELECT user_id FROM accounts WHERE role=''player'')',@()) }
    elseif ($Mode -eq 'expire_bans') { [void]$handle.Query('UPDATE accounts SET ban_until=1 WHERE role=''player'' AND ban_until>0',@()) }
    elseif ($Mode -eq 'expire_rates') { [void]$handle.Query('UPDATE rate_limits SET window_start=1',@()) }
    elseif ($Mode -eq 'expire_invites') { [void]$handle.Query('UPDATE invites SET expires=1',@()) }
    else {
        $users=$handle.Query('SELECT * FROM accounts',@())
        if ($users.Count -lt 3) { throw 'Missing real accounts' }
        foreach($user in $users) {
            if ($user['algorithm'] -ne 'pbkdf2-sha256' -or [int]$user['iterations'] -ne 600000 -or $user['salt'].Length -ne 44 -or $user['password_hash'].Length -ne 44) { throw 'Invalid password storage' }
        }
        if (@($users | ForEach-Object { $_['salt'] } | Select-Object -Unique).Count -ne $users.Count) { throw 'Salt reuse' }
        $sessions=$handle.Query('SELECT token_hash FROM sessions',@())
        foreach($session in $sessions) { if ($session['token_hash'] -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid session digest' } }
        $invites=$handle.Query('SELECT code_hash,used,max_uses FROM invites',@())
        foreach($invite in $invites) { if ($invite['code_hash'] -cnotmatch '^[a-f0-9]{64}$' -or [int]$invite['used'] -gt [int]$invite['max_uses']) { throw 'Invite invariant' } }
        $rows=$handle.Query('SELECT * FROM account_audit',@())
        $audit=$rows | ConvertTo-Json -Depth 8 -Compress
        if ($audit -match 'very-secret|new-password|reset-password|password_hash|salt') { throw 'Credential leaked to audit' }
        if ($handle.Query('PRAGMA integrity_check',@())[0]['integrity_check'] -ne 'ok') { throw 'Integrity check failed' }
    }
} finally { $handle.Dispose() }
Write-Output 'ACCOUNT_DATABASE_FIXTURE_OK'
