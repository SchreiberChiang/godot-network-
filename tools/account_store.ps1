param([Parameter(Mandatory=$true)][string]$Database,[Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
# Passwords and session tokens are passed only in the private request file, never
# in process arguments, SQL diagnostics, audit fields or exception output.
$bindingSource=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $PSScriptRoot 'sqlite_store.ps1')
$binding=[regex]::Match($bindingSource,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $binding.Success) { Write-Output '{"ok":false,"code":"STORAGE_UNAVAILABLE"}'; exit 0 }
Add-Type -TypeDefinition ($binding.Groups[1].Value.Replace('sqlite3_busy_timeout(handle,1500)','sqlite3_busy_timeout(handle,10000)'))
Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
public static class RoomKitPasswords {
    public static string RandomHex(int count) {
        var bytes = new byte[count];
        using(var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
    }
    public static string Derive(string password, string salt, int iterations) {
        using(var kdf = new Rfc2898DeriveBytes(password, Convert.FromBase64String(salt), iterations, HashAlgorithmName.SHA256))
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
function Identity($row) { return @{user_id=$row['user_id'];display_name=$row['display_name'];role=$row['role']} }
function PublicAccount($row) {
    $until=[long]$row['ban_until']
    $active=(Query 'SELECT expires FROM sessions WHERE user_id=? AND expires>?' @($row['user_id'],[string]$now)).Count -gt 0
    return @{user_id=$row['user_id'];username=$row['username'];display_name=$row['display_name'];role=$row['role'];created_at=[long]$row['created_at'];ban_until=$until;ban_reason=$row['ban_reason'];banned=($until -eq -1 -or $until -gt $now);active=$active}
}
function FindUser([string]$UserId) {
    $rows=Query 'SELECT * FROM accounts WHERE user_id=?' @($UserId)
    if (-not $rows.Count) { Fail 'ACCOUNT_NOT_FOUND' }
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
function CheckRate($Keys) {
    [void](Query 'DELETE FROM rate_limits WHERE window_start<=?' @([string]($now-900)))
    foreach($key in $Keys) {
        $limit=if ($key.StartsWith('ip:')) {20} else {5}
        $rows=Query 'SELECT failures FROM rate_limits WHERE rate_key=?' @($key)
        if ($rows.Count -and [int]$rows[0]['failures'] -ge $limit) { Fail 'RATE_LIMITED' }
    }
    if ([long](Query 'SELECT count(*) AS total FROM rate_limits')[0]['total'] -ge 10000) { Fail 'RATE_LIMITED' }
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
try {
    $info=Get-Item -LiteralPath $Request
    if ($info.Length -gt 8192) { Fail 'INVALID_ACCOUNT_REQUEST' }
    $r=Get-Content -Encoding UTF8 -LiteralPath $Request -Raw | ConvertFrom-Json
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
        [void](Query 'PRAGMA user_version=1')
        [void](Query 'COMMIT'); $transaction=$false
        $result=@{ok=$true;code='';sqlite_version=(Query 'SELECT sqlite_version() AS version')[0]['version']}
    } else {
        if ((Query 'PRAGMA user_version')[0]['user_version'] -ne '1') { Fail 'DATABASE_NOT_INITIALIZED' }
        # One transaction serializes setup, invite consumption, duplicate login,
        # rate limits and credential/session revocation across helper processes.
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
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
                $password=TextValue 'password' 10 128
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
                $password=TextValue 'password' 10 128
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
                $password=TextValue 'password' 10 128
                $keys=RateKeys $username
                CheckRate $keys
                $rows=Query 'SELECT * FROM accounts WHERE username=?' @($username)
                $valid=$false
                if ($rows.Count) { $valid=CheckPassword $rows[0] $password }
                else { [void][RoomKitPasswords]::Derive($password,'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',$iterations) }
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
                [void](Query 'UPDATE accounts SET display_name=? WHERE user_id=?' @($display,$id))
                Audit $op $id $reason 'OK' @{display_name=$target['display_name']} @{display_name=$display}
                $result.identity=Identity (FindUser $id)
            }
            'account.change_password' {
                $actor=Authenticate
                $password=TextValue 'password' 10 128
                $replacement=TextValue 'new_password' 10 128
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
                $before=PublicAccount $target
                if ($op -eq 'account.reset_password') {
                    $secret=NewPassword (TextValue 'password' 10 128)
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
            $safeReason=[string](Value 'reason' '')
            if ($safeReason.Length -gt 256) { $safeReason='' }
            Audit $op $targetId $safeReason $code
        } catch {}
    }
    $result=@{ok=$false;code=$code}
} finally { if ($db) { $db.Dispose() } }
$json=ConvertTo-Json -InputObject $result -Compress -Depth 12
[regex]::Replace($json,'[^\x00-\x7F]',{ param($match) '\u{0:x4}' -f [int][char]$match.Value })
