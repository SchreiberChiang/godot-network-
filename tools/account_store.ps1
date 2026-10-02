param([Parameter(Mandatory=$true)][string]$Database,[string]$RequestJson='')
# -RequestJson is for in-process calls from storage_worker.ps1 only (it carries
# session tokens); never pass a request on a process command line.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
# Passwords and session tokens arrive only on standard input as one base64 line
# from bounded_helper.ps1, never in files, process arguments, SQL diagnostics,
# audit fields or exception output.
$bindingSource=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $PSScriptRoot 'sqlite_store.ps1')
$binding=[regex]::Match($bindingSource,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $binding.Success) { Write-Output '{"ok":false,"code":"STORAGE_UNAVAILABLE"}'; exit 0 }
Add-Type -TypeDefinition ($binding.Groups[1].Value.Replace('sqlite3_busy_timeout(handle,1500)','sqlite3_busy_timeout(handle,10000)'))
Add-Type -TypeDefinition @'
using System;
using System.Reflection;
using System.Security.Cryptography;
public static class RoomKitPasswords {
    public static string RandomHex(int count) {
        var bytes = new byte[count];
        using(var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
    }
    // PBKDF2-HMAC-SHA256 over the UTF-8 password, 32 bytes, on every platform.
    // Modern .NET marks the constructor obsolete in favour of a static method that
    // .NET Framework does not have, so both are reached without a compile-time
    // reference; the algorithm, parameters and stored format are unchanged.
    public static string Derive(string password, string salt, int iterations) {
        byte[] saltBytes = Convert.FromBase64String(salt);
        MethodInfo direct = typeof(Rfc2898DeriveBytes).GetMethod("Pbkdf2", new Type[] { typeof(string), typeof(byte[]), typeof(int), typeof(HashAlgorithmName), typeof(int) });
        if(direct != null) return Convert.ToBase64String((byte[])direct.Invoke(null, new object[] { password, saltBytes, iterations, HashAlgorithmName.SHA256, 32 }));
        using(var kdf = (Rfc2898DeriveBytes)Activator.CreateInstance(typeof(Rfc2898DeriveBytes), new object[] { password, saltBytes, iterations, HashAlgorithmName.SHA256 }))
            return Convert.ToBase64String(kdf.GetBytes(32));
    }
    public static bool Verify(string password, string salt, int iterations, string expected) {
        var actual = Convert.FromBase64String(Derive(password, salt, iterations));
        var stored = Convert.FromBase64String(expected);
        if(stored.Length != actual.Length) return false;
        int difference = 0;
        for(int i = 0; i < actual.Length; i++) difference |= actual[i] ^ stored[i];
        return difference == 0;
    }
    public static string Salt() {
        var bytes = new byte[32];
        using(var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        return Convert.ToBase64String(bytes);
    }
    public static string Digest(string value) {
        using(var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(System.Text.Encoding.UTF8.GetBytes(value))).Replace("-", "").ToLowerInvariant();
    }
}
'@
$db=$null
$transaction=$false
$actor=$null
# PowerShell 7 turns date-looking JSON strings into DateTime values by default;
# Windows PowerShell 5.1 keeps them as text. Keep text on both.
$jsonKeepsText=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
function ParseJson([string]$Text) { if ($jsonKeepsText) { return ConvertFrom-Json -InputObject $Text -DateKind String }; return ConvertFrom-Json -InputObject $Text }
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$iterations=600000
function Query([string]$Sql,[string[]]$Values=@()) { return ,($db.Query($Sql,$Values)) }
function Fail([string]$Code) { throw ('ACCOUNT:'+ $Code) }
function Value([string]$Name,$Default='') {
    $property=$r.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}
function TextValue([string]$Name,[int]$Min,[int]$Max) {
    $value=Value $Name
    if ($value -isnot [string] -or $value.Length -lt $Min -or $value.Length -gt $Max -or $value -match '[\x00-\x1f\x7f]') { Fail 'INVALID_ACCOUNT_REQUEST' }
    return $value
}
function NumberValue([string]$Name,[long]$Default,[long]$Min,[long]$Max) {
    $value=Value $Name $Default
    if ($value -is [string] -or $value -is [bool] -or [double]$value -ne [math]::Floor([double]$value) -or [double]$value -lt $Min -or [double]$value -gt $Max) { Fail 'INVALID_ACCOUNT_REQUEST' }
    return [long]$value
}
function Username {
    $value=TextValue 'username' 3 32
    if ($value -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{2,31}$') { Fail 'INVALID_ACCOUNT_REQUEST' }
    return $value.ToLowerInvariant()
}
# Test-stage deletion (docs/17 section 7). The pseudonym is derived from the random
# user_id only, so audit rows and tombstones stay linkable without keeping the ID.
# Job states: assets_pending (account blocked) -> done with closed=0 (both databases
# done, Operator audit/journal still pending) -> closed=1. user_id and username stay
# in the job only until closed, because the Operator needs them to finish its files.
function EnsureDeletions {
    [void](Query 'CREATE TABLE IF NOT EXISTS account_deletions (job_id TEXT PRIMARY KEY, subject TEXT NOT NULL UNIQUE, user_id TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN (''assets_pending'',''done'')), actor_id TEXT NOT NULL, reason TEXT NOT NULL, account_created_at INTEGER NOT NULL, created_at INTEGER NOT NULL, finished_at INTEGER NOT NULL DEFAULT 0, username TEXT NOT NULL DEFAULT '''', closed INTEGER NOT NULL DEFAULT 0)')
    # Tables made by the first, unreleased version lack the last two columns; their
    # finished jobs had already done the Operator steps, so they count as closed.
    $columns=@(foreach($row in (Query 'PRAGMA table_info(account_deletions)')) { $row['name'] })
    if ($columns -notcontains 'username') { [void](Query 'ALTER TABLE account_deletions ADD COLUMN username TEXT NOT NULL DEFAULT ''''') }
    if ($columns -notcontains 'closed') {
        [void](Query 'ALTER TABLE account_deletions ADD COLUMN closed INTEGER NOT NULL DEFAULT 0')
        [void](Query 'UPDATE account_deletions SET closed=1 WHERE state=''done''')
    }
}
function Subject([string]$Id) { return 'deleted_'+([RoomKitPasswords]::Digest($Id)).Substring(0,32) }
# Replaces every case-insensitive occurrence of the user_id and username in free text
# (reasons, audit snapshots) with the pseudonym.
function Scrub([string]$Text,[string[]]$Needles,[string]$Replacement) {
    foreach($needle in $Needles) { if ($needle.Length -ge 3) { $Text=[regex]::Replace($Text,[regex]::Escape($needle),$Replacement,[Text.RegularExpressions.RegexOptions]::IgnoreCase) } }
    return $Text
}
function JobState($Row) { if ($Row['state'] -eq 'assets_pending') { return 'assets_pending' }; if ([int]$Row['closed'] -eq 1) { return 'done' }; return 'operator_pending' }
function DeletionPending([string]$Id) { return (Query 'SELECT job_id FROM account_deletions WHERE user_id=? AND state=''assets_pending''' @($Id)).Count -gt 0 }
function AlreadyDeleted([string]$Id) { return (Query 'SELECT job_id FROM account_deletions WHERE subject=? AND state=''done''' @(Subject $Id)).Count -gt 0 }
function Identity($row) { return @{user_id=$row['user_id'];display_name=$row['display_name'];role=$row['role']} }
function PublicAccount($row) {
    $until=[long]$row['ban_until']
    $active=(Query 'SELECT expires FROM sessions WHERE user_id=? AND expires>?' @($row['user_id'],[string]$now)).Count -gt 0
    return @{user_id=$row['user_id'];username=$row['username'];display_name=$row['display_name'];role=$row['role'];created_at=[long]$row['created_at'];ban_until=$until;ban_reason=$row['ban_reason'];banned=($until -eq -1 -or $until -gt $now);active=$active;deletion_pending=(DeletionPending $row['user_id'])}
}
function FindUser([string]$UserId) {
    $rows=Query 'SELECT * FROM accounts WHERE user_id=?' @($UserId)
    if (-not $rows.Count) { if (AlreadyDeleted $UserId) { Fail 'ACCOUNT_ALREADY_DELETED' }; Fail 'ACCOUNT_NOT_FOUND' }
    return $rows[0]
}
function Authenticate {
    $token=TextValue 'token' 64 64
    if ($token -cnotmatch '^[a-f0-9]{64}$') { Fail 'AUTH_FAILED' }
    $rows=Query 'SELECT a.*,s.expires FROM sessions s JOIN accounts a ON a.user_id=s.user_id WHERE s.token_hash=? AND s.expires>?' @([RoomKitPasswords]::Digest($token),[string]$now)
    if (-not $rows.Count) { Fail 'AUTH_FAILED' }
    $row=$rows[0]
    if ([long]$row['ban_until'] -eq -1 -or [long]$row['ban_until'] -gt $now) { Fail 'ACCOUNT_BANNED' }
    return $row
}
function RequireAdmin {
    $script:actor=Authenticate
    if ($actor['role'] -ne 'admin') { Fail 'ADMIN_REQUIRED' }
}
function Audit([string]$Action,[string]$Target,[string]$Reason,[string]$Code='OK',$Before=@{},$After=@{}) {
    $actorId=if ($actor) {$actor['user_id']} else {''}
    $beforeJson=ConvertTo-Json -InputObject $Before -Depth 8 -Compress
    $afterJson=ConvertTo-Json -InputObject $After -Depth 8 -Compress
    [void](Query 'INSERT INTO account_audit (actor_id,action,target_id,reason,result,before_body,after_body,created_at) VALUES (?,?,?,?,?,?,?,?)' @($actorId,$Action,$Target,$Reason,$Code,$beforeJson,$afterJson,[string]$now))
}
function RateKeys([string]$Username) {
    $ip=TextValue 'client_ip' 1 64
    return @(('ip:'+[RoomKitPasswords]::Digest($ip)),('user:'+[RoomKitPasswords]::Digest($Username)))
}
function CheckRate($Keys,[switch]$ReadOnly) {
    # Login's preflight must not obtain a write lock just to reject a request
    # already limited. The write transaction calls this again authoritatively.
    if (-not $ReadOnly) { [void](Query 'DELETE FROM rate_limits WHERE window_start<=?' @([string]($now-900))) }
    foreach($key in $Keys) {
        $limit=if ($key.StartsWith('ip:')) {20} else {5}
        $rows=Query 'SELECT failures FROM rate_limits WHERE rate_key=? AND window_start>?' @($key,[string]($now-900))
        if ($rows.Count -and [int]$rows[0]['failures'] -ge $limit) { Fail 'RATE_LIMITED' }
    }
    if ([long](Query 'SELECT count(*) AS total FROM rate_limits WHERE window_start>?' @([string]($now-900)))[0]['total'] -ge 10000) { Fail 'RATE_LIMITED' }
}
function FailRate($Keys,[string]$Code,[string]$Action) {
    foreach($key in $Keys) {
        [void](Query 'INSERT INTO rate_limits (rate_key,failures,window_start) VALUES (?,1,?) ON CONFLICT(rate_key) DO UPDATE SET failures=failures+1' @($key,[string]$now))
    }
    Audit $Action '' '' $Code
    return @{ok=$false;code=$Code}
}
function NewPassword([string]$Password) {
    $salt=[RoomKitPasswords]::Salt()
    return @{salt=$salt;hash=[RoomKitPasswords]::Derive($Password,$salt,$iterations)}
}
function CheckPassword($Row,[string]$Password) {
    if ($Row['algorithm'] -ne 'pbkdf2-sha256' -or [int]$Row['iterations'] -ne $iterations) { Fail 'STORAGE_UNAVAILABLE' }
    return [RoomKitPasswords]::Verify($Password,$Row['salt'],[int]$Row['iterations'],$Row['password_hash'])
}
function SameCredentials($Before,$Current) {
    if ($null -eq $Before -or $null -eq $Current) { return $false }
    foreach($field in 'user_id','algorithm','iterations','salt','password_hash') {
        if (-not [string]::Equals([string]$Before[$field],[string]$Current[$field],[StringComparison]::Ordinal)) { return $false }
    }
    return $true
}
try {
    if ($RequestJson) {
        $bytes=[Text.Encoding]::UTF8.GetBytes($RequestJson)
    } else {
        # 10924 base64 characters encode the same 8192-byte request limit as before.
        $line=[Console]::In.ReadLine()
        if ([string]::IsNullOrEmpty($line) -or $line.Length -gt 10924 -or $line.Length % 4 -ne 0 -or $line -notmatch '^[A-Za-z0-9+/]*={0,2}$') { Fail 'INVALID_ACCOUNT_REQUEST' }
        $bytes=[Convert]::FromBase64String($line)
    }
    if ($bytes.Length -gt 8192) { Fail 'INVALID_ACCOUNT_REQUEST' }
    $r=ParseJson ([Text.Encoding]::UTF8.GetString($bytes))
    if ($r -isnot [PSCustomObject]) { Fail 'INVALID_ACCOUNT_REQUEST' }
    $op=TextValue 'op' 1 40
    $db=New-Object RoomKitSqlite($Database)
    if ($op -eq 'init') {
        if ((Query 'PRAGMA user_version')[0]['user_version'] -notin @('0','1')) { Fail 'UNSUPPORTED_DATABASE_VERSION' }
        [void](Query 'PRAGMA journal_mode=WAL')
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        [void](Query 'CREATE TABLE IF NOT EXISTS accounts (user_id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN (''admin'',''player'')), algorithm TEXT NOT NULL, iterations INTEGER NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, ban_until INTEGER NOT NULL DEFAULT 0, ban_reason TEXT NOT NULL DEFAULT '''', created_at INTEGER NOT NULL)')
        [void](Query 'CREATE UNIQUE INDEX IF NOT EXISTS singleton_admin ON accounts(role) WHERE role=''admin''')
        [void](Query 'CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE REFERENCES accounts(user_id), expires INTEGER NOT NULL, created_at INTEGER NOT NULL)')
        [void](Query 'CREATE TABLE IF NOT EXISTS invites (invite_id TEXT PRIMARY KEY, code_hash TEXT NOT NULL UNIQUE, max_uses INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, created_by TEXT NOT NULL)')
        [void](Query 'CREATE TABLE IF NOT EXISTS rate_limits (rate_key TEXT PRIMARY KEY, failures INTEGER NOT NULL, window_start INTEGER NOT NULL)')
        [void](Query 'CREATE TABLE IF NOT EXISTS account_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, actor_id TEXT NOT NULL, action TEXT NOT NULL, target_id TEXT NOT NULL, reason TEXT NOT NULL, result TEXT NOT NULL, before_body TEXT NOT NULL, after_body TEXT NOT NULL, created_at INTEGER NOT NULL)')
        EnsureDeletions
        [void](Query 'PRAGMA user_version=1')
        [void](Query 'COMMIT'); $transaction=$false
        $result=@{ok=$true;code='';sqlite_version=(Query 'SELECT sqlite_version() AS version')[0]['version']}
    } else {
        if ((Query 'PRAGMA user_version')[0]['user_version'] -ne '1') { Fail 'DATABASE_NOT_INITIALIZED' }
        $loginSnapshot=$null; $loginVerified=$false
        if ($op -eq 'account.login') {
            $loginUsername=Username
            $loginPassword=TextValue 'password' 8 128
            $loginKeys=RateKeys $loginUsername
            CheckRate $loginKeys -ReadOnly
            $loginRows=Query 'SELECT * FROM accounts WHERE username=?' @($loginUsername)
            # Do the expensive, unchanged KDF without holding SQLite's only
            # write lock. Never make this stale snapshot the audit actor.
            if ($loginRows.Count) {
                $loginSnapshot=$loginRows[0]
                $loginVerified=CheckPassword $loginSnapshot $loginPassword
            } else {
                [void][RoomKitPasswords]::Derive($loginPassword,'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',$iterations)
            }
        }
        # One transaction serializes setup, invite consumption, duplicate login,
        # rate limits and credential/session revocation across helper processes.
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        # Additive table with the same user_version: a restored older backup gains it here.
        EnsureDeletions
        if ($op -ne 'local.reset_player_sessions') { [void](Query 'DELETE FROM sessions WHERE expires<=?' @([string]$now)) }
        $result=@{ok=$true;code=''}
        switch ($op) {
            'local.reset_player_sessions' {
                # Local owner-only lifecycle hook. Not accepted by the account
                # request schema or any network RPC operation whitelist.
                # No caller-controlled role, token, filter or reason is accepted.
                if (@($r.PSObject.Properties.Name).Count -ne 1) { Fail 'INVALID_ACCOUNT_REQUEST' }
                $revoked=[long](Query 'SELECT count(*) AS total FROM sessions s JOIN accounts a ON a.user_id=s.user_id WHERE a.role=''player''')[0]['total']
                [void](Query 'DELETE FROM sessions WHERE user_id IN (SELECT user_id FROM accounts WHERE role=''player'')')
                $actor=@{user_id='system:operator'}
                Audit $op '' 'operator_restart_after_verified_exit' 'OK' @{player_sessions=$revoked} @{player_sessions=0}
                $result.revoked=$revoked
            }
            'setup.status' {
                $result.initialized=[int](Query 'SELECT count(*) AS total FROM accounts WHERE role=''admin''')[0]['total'] -gt 0
            }
            'setup.admin' {
                if ([int](Query 'SELECT count(*) AS total FROM accounts WHERE role=''admin''')[0]['total']) { Fail 'SETUP_COMPLETE' }
                $username=Username
                $password=TextValue 'password' 8 128
                $display=TextValue 'display_name' 1 32
                $secret=NewPassword $password
                $userId='admin_'+[RoomKitPasswords]::RandomHex(16)
                [void](Query 'INSERT INTO accounts (user_id,username,display_name,role,algorithm,iterations,salt,password_hash,created_at) VALUES (?,?,?,''admin'',''pbkdf2-sha256'',?,?,?,?)' @($userId,$username,$display,[string]$iterations,$secret.salt,$secret.hash,[string]$now))
                $actor=FindUser $userId
                Audit $op $userId 'initial_setup'
                $result.identity=Identity $actor
            }
            'account.register' {
                if (-not [int](Query 'SELECT count(*) AS total FROM accounts WHERE role=''admin''')[0]['total']) { Fail 'SETUP_REQUIRED' }
                $username=Username
                $password=TextValue 'password' 8 128
                $display=TextValue 'display_name' 1 32
                $invite=TextValue 'invite_code' 32 32
                $keys=RateKeys $username
                CheckRate $keys
                $existing=Query 'SELECT user_id FROM accounts WHERE username=?' @($username)
                $invitations=Query 'SELECT * FROM invites WHERE code_hash=? AND revoked=0 AND used<max_uses AND expires>?' @([RoomKitPasswords]::Digest($invite),[string]$now)
                if (-not $invitations.Count) { $result=FailRate $keys 'INVITE_INVALID' $op; break }
                if ($existing.Count) { $result=FailRate $keys 'USERNAME_UNAVAILABLE' $op; break }
                if ([long](Query 'SELECT count(*) AS total FROM accounts')[0]['total'] -ge 10000) { Fail 'ACCOUNT_CAPACITY_EXCEEDED' }
                $secret=NewPassword $password
                $userId='user_'+[RoomKitPasswords]::RandomHex(16)
                [void](Query 'INSERT INTO accounts (user_id,username,display_name,role,algorithm,iterations,salt,password_hash,created_at) VALUES (?,?,?,''player'',''pbkdf2-sha256'',?,?,?,?)' @($userId,$username,$display,[string]$iterations,$secret.salt,$secret.hash,[string]$now))
                [void](Query 'UPDATE invites SET used=used+1 WHERE invite_id=?' @($invitations[0]['invite_id']))
                Audit $op $userId 'invite_registration'
                $result.identity=Identity (FindUser $userId)
            }
            'account.login' {
                $username=Username
                $password=TextValue 'password' 8 128
                $keys=RateKeys $username
                CheckRate $keys
                $rows=Query 'SELECT * FROM accounts WHERE username=?' @($username)
                # Recheck both rate limits and the credentials while writes are
                # serialized. Reset/delete/recreation during verification cannot
                # turn an old password check into a new session. No retry/KDF replay.
                $valid=$loginVerified -and $rows.Count -gt 0 -and (SameCredentials $loginSnapshot $rows[0])
                if (-not $valid) { $result=FailRate $keys 'AUTH_FAILED' $op; break }
                $actor=$rows[0]
                if ([long]$actor['ban_until'] -eq -1 -or [long]$actor['ban_until'] -gt $now) { $result=FailRate $keys 'ACCOUNT_BANNED' $op; break }
                if ((Query 'SELECT token_hash FROM sessions WHERE user_id=?' @($actor['user_id'])).Count) {
                    if ($actor['role'] -ne 'admin') { Fail 'ALREADY_LOGGED_IN' }
                    # A valid operator password rotates the previous browser
                    # session. There is still only one active admin bearer.
                    [void](Query 'DELETE FROM sessions WHERE user_id=?' @($actor['user_id']))
                }
                $token=[RoomKitPasswords]::RandomHex(32)
                $expires=$now+43200
                [void](Query 'INSERT INTO sessions (token_hash,user_id,expires,created_at) VALUES (?,?,?,?)' @([RoomKitPasswords]::Digest($token),$actor['user_id'],[string]$expires,[string]$now))
                [void](Query 'DELETE FROM rate_limits WHERE rate_key=?' @($keys[1]))
                Audit $op $actor['user_id'] ''
                $result.token=$token; $result.expires=$expires; $result.identity=Identity $actor
            }
            'session.authenticate' {
                $actor=Authenticate
                $result.identity=Identity $actor
                $result.expires=[long]$actor['expires']
            }
            'session.logout' {
                $actor=Authenticate
                [void](Query 'DELETE FROM sessions WHERE user_id=?' @($actor['user_id']))
                Audit $op $actor['user_id'] ''
            }
            'account.rename' {
                $actor=Authenticate
                $display=TextValue 'display_name' 1 32
                $id=[string](Value 'user_id' $actor['user_id'])
                $reason='self_service'
                if ($id -ne $actor['user_id']) {
                    if ($actor['role'] -ne 'admin') { Fail 'ADMIN_REQUIRED' }
                    $reason=TextValue 'reason' 1 256
                }
                $target=FindUser $id
                if (DeletionPending $id) { Fail 'ACCOUNT_DELETION_PENDING' }
                [void](Query 'UPDATE accounts SET display_name=? WHERE user_id=?' @($display,$id))
                Audit $op $id $reason 'OK' @{display_name=$target['display_name']} @{display_name=$display}
                $result.identity=Identity (FindUser $id)
            }
            'account.change_password' {
                $actor=Authenticate
                $password=TextValue 'password' 8 128
                $replacement=TextValue 'new_password' 8 128
                $keys=RateKeys $actor['username']
                CheckRate $keys
                if (-not (CheckPassword $actor $password)) { $result=FailRate $keys 'AUTH_FAILED' $op; break }
                $secret=NewPassword $replacement
                [void](Query 'UPDATE accounts SET salt=?,password_hash=?,iterations=? WHERE user_id=?' @($secret.salt,$secret.hash,[string]$iterations,$actor['user_id']))
                [void](Query 'DELETE FROM sessions WHERE user_id=?' @($actor['user_id']))
                Audit $op $actor['user_id'] 'self_service'
                $result.reauthenticate=$true
            }
            'invite.create' {
                RequireAdmin
                $uses=NumberValue 'uses' 1 1 1000
                $expires=NumberValue 'expires' ($now+604800) ($now+1) ($now+31536000)
                $reason=TextValue 'reason' 1 256
                if ([long](Query 'SELECT count(*) AS total FROM invites')[0]['total'] -ge 10000) { Fail 'INVITE_CAPACITY_EXCEEDED' }
                $code=[RoomKitPasswords]::RandomHex(16)
                $inviteId='invite_'+[RoomKitPasswords]::RandomHex(16)
                [void](Query 'INSERT INTO invites (invite_id,code_hash,max_uses,expires,created_at,created_by) VALUES (?,?,?,?,?,?)' @($inviteId,[RoomKitPasswords]::Digest($code),[string]$uses,[string]$expires,[string]$now,$actor['user_id']))
                Audit $op $inviteId $reason
                $result.invite_code=$code; $result.invite_id=$inviteId; $result.uses=$uses; $result.expires=$expires
            }
            'invite.list' {
                RequireAdmin
                $offset=NumberValue 'offset' 0 0 1000000
                $limit=NumberValue 'limit' 100 1 200
                $rows=Query 'SELECT invite_id,max_uses,used,expires,revoked,created_at,created_by FROM invites ORDER BY created_at DESC,rowid DESC LIMIT ? OFFSET ?' @([string]$limit,[string]$offset)
                $result.invites=@(foreach($row in $rows) { @{invite_id=$row['invite_id'];max_uses=[int]$row['max_uses'];used=[int]$row['used'];expires=[long]$row['expires'];revoked=([int]$row['revoked'] -eq 1);created_at=[long]$row['created_at'];created_by=$row['created_by']} })
                $result.total=[long](Query 'SELECT count(*) AS total FROM invites')[0]['total']
            }
            'invite.revoke' {
                RequireAdmin
                $id=TextValue 'invite_id' 1 64
                $reason=TextValue 'reason' 1 256
                if (-not (Query 'SELECT invite_id FROM invites WHERE invite_id=?' @($id)).Count) { Fail 'INVITE_NOT_FOUND' }
                [void](Query 'UPDATE invites SET revoked=1 WHERE invite_id=?' @($id))
                Audit $op $id $reason
            }
            'account.list' {
                RequireAdmin
                $offset=NumberValue 'offset' 0 0 1000000
                $limit=NumberValue 'limit' 100 1 200
                $search=[string](Value 'search' '')
                if ($search.Length -gt 64) { Fail 'INVALID_ACCOUNT_REQUEST' }
                $rows=Query 'SELECT * FROM accounts WHERE instr(username,?)>0 OR instr(display_name,?)>0 OR instr(user_id,?)>0 ORDER BY created_at DESC,rowid DESC LIMIT ? OFFSET ?' @($search.ToLowerInvariant(),$search,$search,[string]$limit,[string]$offset)
                $result.accounts=@(foreach($row in $rows) { PublicAccount $row })
                $result.total=[long](Query 'SELECT count(*) AS total FROM accounts WHERE instr(username,?)>0 OR instr(display_name,?)>0 OR instr(user_id,?)>0' @($search.ToLowerInvariant(),$search,$search))[0]['total']
            }
            'account.get' {
                $actor=Authenticate
                $id=[string](Value 'user_id' $actor['user_id'])
                if ($actor['role'] -ne 'admin' -and $id -ne $actor['user_id']) { Fail 'ADMIN_REQUIRED' }
                $result.account=PublicAccount (FindUser $id)
            }
            {$_ -in @('account.reset_password','account.ban','account.unban','session.revoke_all')} {
                RequireAdmin
                $reason=TextValue 'reason' 1 256
                $id=TextValue 'user_id' 0 64
                if ($op -eq 'session.revoke_all' -and $id -eq '') {
                    [void](Query 'DELETE FROM sessions WHERE user_id IN (SELECT user_id FROM accounts WHERE role=''player'')')
                    Audit $op '' $reason
                    break
                }
                $target=FindUser $id
                if ($target['role'] -eq 'admin') { Fail 'ADMIN_SELF_PROTECTION' }
                # A pending deletion keeps the account blocked until it completes.
                if (DeletionPending $id) { Fail 'ACCOUNT_DELETION_PENDING' }
                $before=PublicAccount $target
                if ($op -eq 'account.reset_password') {
                    $secret=NewPassword (TextValue 'password' 8 128)
                    [void](Query 'UPDATE accounts SET salt=?,password_hash=?,iterations=? WHERE user_id=?' @($secret.salt,$secret.hash,[string]$iterations,$id))
                } elseif ($op -eq 'account.ban') {
                    $until=NumberValue 'until' 0 0 9007199254740991
                    if ($until -ne 0 -and $until -le $now) { Fail 'INVALID_ACCOUNT_REQUEST' }
                    if ($until -eq 0) { $until=-1 }
                    [void](Query 'UPDATE accounts SET ban_until=?,ban_reason=? WHERE user_id=?' @([string]$until,$reason,$id))
                } elseif ($op -eq 'account.unban') {
                    [void](Query 'UPDATE accounts SET ban_until=0,ban_reason='''' WHERE user_id=?' @($id))
                }
                if ($op -ne 'account.unban') { [void](Query 'DELETE FROM sessions WHERE user_id=?' @($id)) }
                Audit $op $id $reason 'OK' $before (PublicAccount (FindUser $id))
            }
            'account.delete_begin' {
                # Step 1. Blocks sign-in and revokes sessions, then records a job that
                # stays open until the asset purge, local.deletion_finish and the
                # Operator's own close-out (local.deletion_close) have all succeeded.
                # Repeating the request resumes the same job, including after the
                # account row itself is already gone (job waiting for the Operator).
                RequireAdmin
                $reason=TextValue 'reason' 1 256
                $id=TextValue 'user_id' 1 64
                $confirm=(TextValue 'confirm_username' 3 32).ToLowerInvariant()
                $subject=Subject $id
                # The administrator's free-text reason never keeps the target's names.
                $reason=Scrub $reason @($id,$confirm) $subject
                $rows=Query 'SELECT * FROM accounts WHERE user_id=?' @($id)
                if (-not $rows.Count) {
                    $waiting=Query 'SELECT * FROM account_deletions WHERE user_id=? AND state=''done'' AND closed=0' @($id)
                    if (-not $waiting.Count) { if (AlreadyDeleted $id) { Fail 'ACCOUNT_ALREADY_DELETED' }; Fail 'ACCOUNT_NOT_FOUND' }
                    if ($waiting[0]['username'] -cne $confirm) { Fail 'DELETE_CONFIRMATION_MISMATCH' }
                    Audit $op $subject $reason 'OK' @{} @{job_id=$waiting[0]['job_id'];state='operator_pending';resumed=$true}
                    $result.deletion=@{job_id=$waiting[0]['job_id'];user_id=$id;subject=$subject;state='operator_pending';account_created_at=[long]$waiting[0]['account_created_at'];resumed=$true;sessions_revoked=0}
                    break
                }
                $target=$rows[0]
                if ($target['role'] -eq 'admin') { Fail 'ADMIN_SELF_PROTECTION' }
                if ($target['username'] -cne $confirm) { Fail 'DELETE_CONFIRMATION_MISMATCH' }
                $job=Query 'SELECT job_id FROM account_deletions WHERE user_id=? AND state=''assets_pending''' @($id)
                $resumed=$job.Count -gt 0
                $jobId=if ($resumed) { $job[0]['job_id'] } else { 'deletion_'+[RoomKitPasswords]::RandomHex(16) }
                if (-not $resumed) {
                    [void](Query 'INSERT INTO account_deletions (job_id,subject,user_id,username,state,closed,actor_id,reason,account_created_at,created_at) VALUES (?,?,?,?,''assets_pending'',0,?,?,?,?)' @($jobId,$subject,$id,$target['username'],$actor['user_id'],$reason,[string]$target['created_at'],[string]$now))
                }
                $revoked=[long](Query 'SELECT count(*) AS total FROM sessions WHERE user_id=?' @($id))[0]['total']
                [void](Query 'DELETE FROM sessions WHERE user_id=?' @($id))
                [void](Query 'UPDATE accounts SET ban_until=-1,ban_reason=''account_deletion_pending'' WHERE user_id=?' @($id))
                Audit $op $subject $reason 'OK' @{} @{job_id=$jobId;state='assets_pending';resumed=$resumed}
                $result.deletion=@{job_id=$jobId;user_id=$id;subject=$subject;state='assets_pending';account_created_at=[long]$target['created_at'];resumed=$resumed;sessions_revoked=$revoked}
            }
            'local.deletion_pending' {
                # Local owner-only recovery hook, like local.reset_player_sessions:
                # absent from the account request schema and from every RPC whitelist.
                if (@($r.PSObject.Properties.Name).Count -ne 1) { Fail 'INVALID_ACCOUNT_REQUEST' }
                $rows=Query 'SELECT * FROM account_deletions WHERE state=''assets_pending'' OR closed=0 ORDER BY created_at,job_id LIMIT 100'
                $result.deletions=@(foreach($row in $rows) { @{job_id=$row['job_id'];user_id=$row['user_id'];username=$row['username'];subject=$row['subject'];state=(JobState $row);account_created_at=[long]$row['account_created_at']} })
            }
            'local.deletion_finish' {
                # Step 3, only after the asset purge succeeded. Removes the account row,
                # its sessions and login rate-limit key; audit rows about the account get
                # the pseudonym and lose their snapshots and reason, and the user_id or
                # username inside any other audit row's text is replaced too. Rows keep
                # action, time and result. The job then waits for the Operator.
                if (@($r.PSObject.Properties.Name).Count -ne 2) { Fail 'INVALID_ACCOUNT_REQUEST' }
                $jobId=TextValue 'job_id' 1 64
                $job=Query 'SELECT * FROM account_deletions WHERE job_id=?' @($jobId)
                if (-not $job.Count) { Fail 'DELETION_NOT_FOUND' }
                $job=$job[0]
                if ($job['state'] -eq 'done') {
                    $result.code='DUPLICATE'
                    $result.deletion=@{job_id=$jobId;subject=$job['subject'];state=(JobState $job)}
                    break
                }
                $id=$job['user_id']; $subject=$job['subject']; $name=$job['username']
                $actor=@{user_id=$job['actor_id']}
                $revoked=[long](Query 'SELECT count(*) AS total FROM sessions WHERE user_id=?' @($id))[0]['total']
                [void](Query 'DELETE FROM sessions WHERE user_id=?' @($id))
                $limits=0
                if ($name) {
                    $key='user:'+[RoomKitPasswords]::Digest($name)
                    $limits=[long](Query 'SELECT count(*) AS total FROM rate_limits WHERE rate_key=?' @($key))[0]['total']
                    [void](Query 'DELETE FROM rate_limits WHERE rate_key=?' @($key))
                }
                $audited=[long](Query 'SELECT count(*) AS total FROM account_audit WHERE target_id=? OR actor_id=?' @($id,$id))[0]['total']
                [void](Query 'UPDATE account_audit SET target_id=?,reason=''redacted:account_deleted'',before_body=''{}'',after_body=''{}'' WHERE target_id=?' @($subject,$id))
                [void](Query 'UPDATE account_audit SET actor_id=? WHERE actor_id=?' @($subject,$id))
                $scrubbed=0
                foreach($needle in @($id,$name)) {
                    if ($needle.Length -lt 3) { continue }
                    foreach($row in (Query 'SELECT id,reason,before_body,after_body FROM account_audit WHERE instr(lower(reason),lower(?))>0 OR instr(lower(before_body),lower(?))>0 OR instr(lower(after_body),lower(?))>0' @($needle,$needle,$needle))) {
                        [void](Query 'UPDATE account_audit SET reason=?,before_body=?,after_body=? WHERE id=?' @((Scrub $row['reason'] @($id,$name) $subject),(Scrub $row['before_body'] @($id,$name) $subject),(Scrub $row['after_body'] @($id,$name) $subject),$row['id']))
                        $scrubbed++
                    }
                }
                [void](Query 'DELETE FROM accounts WHERE user_id=?' @($id))
                [void](Query 'UPDATE account_deletions SET state=''done'',closed=0,finished_at=? WHERE job_id=?' @([string]$now,$jobId))
                Audit 'account.delete' $subject (Scrub $job['reason'] @($id,$name) $subject) 'OK' @{} @{job_id=$jobId;state='operator_pending'}
                $result.deletion=@{job_id=$jobId;subject=$subject;state='operator_pending';sessions_revoked=$revoked;rate_limits_removed=$limits;audit_rows_deidentified=$audited;audit_texts_scrubbed=$scrubbed}
            }
            'local.deletion_close' {
                # Step 5, called by the Operator only after its own audit files are
                # de-identified and its deletion journal entry is durably written.
                # Drops the last copies of the user_id, username and reason.
                if (@($r.PSObject.Properties.Name).Count -ne 2) { Fail 'INVALID_ACCOUNT_REQUEST' }
                $jobId=TextValue 'job_id' 1 64
                $job=Query 'SELECT * FROM account_deletions WHERE job_id=?' @($jobId)
                if (-not $job.Count) { Fail 'DELETION_NOT_FOUND' }
                $job=$job[0]
                if ($job['state'] -ne 'done') { Fail 'DELETION_NOT_READY' }
                if ([int]$job['closed'] -eq 1) {
                    $result.code='DUPLICATE'
                    $result.deletion=@{job_id=$jobId;subject=$job['subject'];state='done'}
                    break
                }
                [void](Query 'UPDATE account_deletions SET closed=1,user_id='''',username='''',reason='''',finished_at=? WHERE job_id=?' @([string]$now,$jobId))
                $actor=@{user_id=$job['actor_id']}
                Audit 'account.delete_closed' $job['subject'] '' 'OK' @{} @{job_id=$jobId;state='done'}
                $result.deletion=@{job_id=$jobId;subject=$job['subject'];state='done'}
            }
            'audit.list' {
                RequireAdmin
                $offset=NumberValue 'offset' 0 0 1000000
                $limit=NumberValue 'limit' 100 1 200
                $result.rows=@((Query 'SELECT id,actor_id,action,target_id,reason,result,before_body,after_body,created_at FROM account_audit ORDER BY id DESC LIMIT ? OFFSET ?' @([string]$limit,[string]$offset)).ToArray())
                $result.total=[long](Query 'SELECT count(*) AS total FROM account_audit')[0]['total']
            }
            default { Fail 'INVALID_ACCOUNT_REQUEST' }
        }
        [void](Query 'COMMIT'); $transaction=$false
    }
} catch {
    if ($transaction -and $db) { try { [void](Query 'ROLLBACK') } catch {} }
    $message=$_.Exception.Message
    $code=if ($message.StartsWith('ACCOUNT:')) {$message.Substring(8)} else {'STORAGE_UNAVAILABLE'}
    # Rejected authenticated modifications are audited too, after rollback. No
    # password, token, invitation code or exception detail enters this record.
    if ($actor -and $db -and $op -notin @('session.authenticate','setup.status','account.get','account.list','invite.list','audit.list')) {
        try {
            $targetId=[string](Value 'user_id' '')
            if ($targetId.Length -gt 64) { $targetId='' }
            # Never write a deleted (or being deleted) account's user_id back into the audit.
            $deleted=$op -eq 'account.delete_begin'
            if ($targetId -and -not $deleted) { try { $deleted=AlreadyDeleted $targetId } catch {} }
            $safeReason=[string](Value 'reason' '')
            if ($safeReason.Length -gt 256) { $safeReason='' }
            if ($targetId -and $deleted) {
                # ...nor its user_id or the typed username inside the reason text.
                $safeReason=Scrub $safeReason @($targetId,[string](Value 'confirm_username' '')) (Subject $targetId)
                $targetId=Subject $targetId
            }
            Audit $op $targetId $safeReason $code
        } catch {}
    }
    $result=@{ok=$false;code=$code}
} finally { if ($db) { $db.Dispose() } }
$json=ConvertTo-Json -InputObject $result -Compress -Depth 12
[regex]::Replace($json,'[^\x00-\x7F]',{ param($match) '\u{0:x4}' -f [int][char]$match.Value })
