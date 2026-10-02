param([Parameter(Mandatory=$true)][string]$Database,[string]$Request='',[string]$RequestJson='')
# -RequestJson is for in-process calls from storage_worker.ps1 only; never pass a
# request on a process command line.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
# Only the host launches this helper. SQL is fixed here, values are bound parameters.
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
public sealed class RoomKitSqlite : IDisposable {
    // One binding for both platforms. Windows keeps the system winsqlite3.dll. On
    // other systems the same import name is resolved to the system SQLite library
    // before the first call; the resolver API only exists on modern .NET, so it is
    // reached through reflection and this source still compiles for Windows
    // PowerShell 5.1. SQL, transactions and text handling are identical.
    const string PosixLibrary = "libsqlite3.so.0";
    static RoomKitSqlite() {
        if(System.IO.Path.DirectorySeparatorChar == '\\') return;
        Type native = Type.GetType("System.Runtime.InteropServices.NativeLibrary");
        Type resolver = Type.GetType("System.Runtime.InteropServices.DllImportResolver");
        if(native == null || resolver == null) throw new PlatformNotSupportedException("SQLITE_LIBRARY_UNAVAILABLE");
        MethodInfo resolve = typeof(RoomKitSqlite).GetMethod("Resolve", BindingFlags.NonPublic | BindingFlags.Static);
        native.GetMethod("SetDllImportResolver").Invoke(null, new object[] { typeof(RoomKitSqlite).Assembly, Delegate.CreateDelegate(resolver, resolve) });
    }
    static IntPtr Resolve(string name, Assembly assembly, DllImportSearchPath? path) {
        if(name != "winsqlite3.dll") return IntPtr.Zero;
        Type native = Type.GetType("System.Runtime.InteropServices.NativeLibrary");
        return (IntPtr)native.GetMethod("Load", new Type[] { typeof(string) }).Invoke(null, new object[] { PosixLibrary });
    }
    public static string LibraryName() { return System.IO.Path.DirectorySeparatorChar == '\\' ? "winsqlite3.dll" : PosixLibrary; }
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open16([MarshalAs(UnmanagedType.LPWStr)] string path, out IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int length, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int length, IntPtr destructor);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_name(IntPtr stmt, int index);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int index);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt, int index);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_backup_init(IntPtr dest, string destName, IntPtr source, string sourceName);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_backup_step(IntPtr backup, int pages);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_backup_finish(IntPtr backup);
    IntPtr handle;
    static byte[] Utf8(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
    static string Read(IntPtr p, int length) { if(p==IntPtr.Zero) return ""; var bytes=new byte[length]; Marshal.Copy(p,bytes,0,length); return Encoding.UTF8.GetString(bytes); }
    public RoomKitSqlite(string path) {
        int rc=sqlite3_open16(path,out handle);
        if(rc!=0) { if(handle!=IntPtr.Zero) sqlite3_close(handle); handle=IntPtr.Zero; throw new Exception("SQLITE_OPEN_FAILED"); }
        sqlite3_busy_timeout(handle,1500);
        Query("PRAGMA synchronous=FULL",new string[0]);
    }
    public List<Dictionary<string,string>> Query(string sql, string[] args) {
        IntPtr stmt;
        byte[] bytes=Utf8(sql);
        if(sqlite3_prepare_v2(handle,bytes,bytes.Length,out stmt,IntPtr.Zero)!=0) throw new Exception("SQLITE_PREPARE_FAILED");
        try {
            for(int i=0;i<args.Length;i++) { byte[] value=Utf8(args[i]); if(sqlite3_bind_text(stmt,i+1,value,value.Length-1,new IntPtr(-1))!=0) throw new Exception("SQLITE_BIND_FAILED"); }
            var rows=new List<Dictionary<string,string>>(); int rc;
            while((rc=sqlite3_step(stmt))==100) {
                var row=new Dictionary<string,string>();
                for(int i=0;i<sqlite3_column_count(stmt);i++) row[Marshal.PtrToStringAnsi(sqlite3_column_name(stmt,i))]=Read(sqlite3_column_text(stmt,i),sqlite3_column_bytes(stmt,i));
                rows.Add(row);
            }
            if(rc!=101) throw new Exception("SQLITE_STEP_FAILED_"+rc);
            return rows;
        } finally { sqlite3_finalize(stmt); }
    }
    public void Backup(string destination) {
        using(var target=new RoomKitSqlite(destination)) {
            IntPtr backup=sqlite3_backup_init(target.handle,"main",handle,"main");
            if(backup==IntPtr.Zero) throw new Exception("BACKUP_INIT_FAILED");
            int rc=sqlite3_backup_step(backup,-1); int finish=sqlite3_backup_finish(backup);
            if(rc!=101 || finish!=0) throw new Exception("BACKUP_FAILED");
        }
    }
    public void Dispose() { if(handle!=IntPtr.Zero) { sqlite3_close(handle); handle=IntPtr.Zero; } }
}
'@
$db=$null
$transaction=$false
# PowerShell 7 turns date-looking JSON strings into DateTime values by default;
# Windows PowerShell 5.1 keeps them as text. Keep text on both.
$jsonKeepsText=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
function ParseJson([string]$Text) { if ($jsonKeepsText) { return ConvertFrom-Json -InputObject $Text -DateKind String }; return ConvertFrom-Json -InputObject $Text }
function Query([string]$Sql,[string[]]$Values=@()) { return ,($db.Query($Sql,$Values)) }
# Internal host time, never copied from the public record or its timestamps.
# Tests inject it through ResultService.clock; production uses the system clock.
function ServerNow {
    if ($null -ne $requestObject.PSObject.Properties['server_now']) {
        if (-not (RewardInteger $requestObject.server_now 9007199254740991)) { throw 'INVALID_STORAGE_REQUEST' }
        return [long]$requestObject.server_now
    }
    return [long][Math]::Floor(([DateTime]::UtcNow-[DateTime]'1970-01-01').TotalSeconds)
}
function SignBody([string]$Body,[string]$Secret) {
    if ($Secret -cnotmatch '^[a-f0-9]{64}$') { return '' }
    $key=New-Object byte[] 32
    for($i=0;$i -lt 32;$i++) { $key[$i]=[Convert]::ToByte($Secret.Substring($i*2,2),16) }
    $hmac=New-Object Security.Cryptography.HMACSHA256(,$key)
    try { return [BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body))).Replace('-','').ToLowerInvariant() }
    finally { $hmac.Dispose() }
}
function PruneGrants([long]$Now) {
    # Called only within BEGIN IMMEDIATE, the same lock used by acceptance.
    $old=Query 'SELECT launch_id,room_id,game_id,build_id,secret,ended_at FROM launches WHERE ended_at IS NOT NULL AND CAST(ended_at AS INTEGER)+604800<=CAST(? AS INTEGER)' @([string]$Now)
    foreach($grant in $old) {
        # Upgrade old accepted records conservatively. Only the unchanged signed
        # canonical body can reconstruct a missing receipt signature. Deleted
        # accounts may have anonymized bodies; do not synthesize a new identity.
        $legacy=Query 'SELECT r.result_id,r.record_hash,r.body FROM results r LEFT JOIN result_signatures s ON s.result_id=r.result_id WHERE s.result_id IS NULL AND r.match_id LIKE ?' @('m_'+$grant['launch_id']+'_%')
        foreach($entry in $legacy) {
            $record=ParseJson $entry['body']
            if ($record.launch_id -cne $grant['launch_id']) { continue }
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry['body']))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
            if ($hash -ceq $entry['record_hash']) { [void](Query 'INSERT OR IGNORE INTO result_signatures(result_id,signature) VALUES (?,?)' @($entry['result_id'],(SignBody $entry['body'] $grant['secret']))) }
        }
        [void](Query 'INSERT OR IGNORE INTO expired_launches(launch_id,room_id,game_id,build_id,ended_at) VALUES (?,?,?,?,?)' @($grant['launch_id'],$grant['room_id'],$grant['game_id'],$grant['build_id'],$grant['ended_at']))
        [void](Query 'DELETE FROM launches WHERE launch_id=? AND ended_at IS NOT NULL AND CAST(ended_at AS INTEGER)+604800<=CAST(? AS INTEGER)' @($grant['launch_id'],[string]$Now))
    }
    return @($old | ForEach-Object { $_['launch_id'] })
}
# Deleted test accounts (docs/17 section 7) leave only this pseudonym, the same one
# account_store.ps1 derives. Additive table under the same user_version.
$tombstoneTable='CREATE TABLE IF NOT EXISTS deleted_subjects (subject TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL)'
function Subject([string]$Id) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return 'deleted_'+[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Id))).Replace('-','').ToLowerInvariant().Substring(0,32) }
    finally { $sha.Dispose() }
}
function Deleted([string]$Id) { return (Query 'SELECT subject FROM deleted_subjects WHERE subject=?' @(Subject $Id)).Count -gt 0 }
function CollectStrings($Value,$Found) {
    if ($Value -is [string]) { if ($Value.Length -ge 1 -and $Value.Length -le 128) { [void]$Found.Add($Value) } }
    elseif ($Value -is [PSCustomObject]) { foreach($property in $Value.PSObject.Properties) { CollectStrings $property.Value $Found } }
    elseif ($Value -is [Array]) { foreach($item in $Value) { CollectStrings $item $Found } }
}
function RewardInteger($Value,[long]$Maximum) {
    # JSON integer semantics allow 1.0, but never coerce strings/bools/null or
    # silently round fractions through PowerShell's [long] conversion.
    if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) { return $false }
    return (-not [double]::IsNaN([double]$Value) -and -not [double]::IsInfinity([double]$Value) -and [double]$Value -ge 0 -and [double]$Value -le $Maximum -and [double]$Value -eq [math]::Floor([double]$Value))
}
try {
    if ($RequestJson) {
        $requestObject=ParseJson $RequestJson
    } elseif ($Request) {
        $requestObject=ParseJson (Get-Content -Encoding UTF8 -LiteralPath $Request -Raw)
    } else {
        # Stdin mode from bounded_helper.ps1: one base64 UTF-8 JSON line. Used for
        # requests carrying room result signing keys, so they never touch disk.
        $line=[Console]::In.ReadLine()
        if ([string]::IsNullOrEmpty($line) -or $line.Length -gt 65536 -or $line.Length % 4 -ne 0 -or $line -notmatch '^[A-Za-z0-9+/]*={0,2}$') { throw 'INVALID_STORAGE_REQUEST' }
        $requestObject=ParseJson ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line)))
    }
    $db=New-Object RoomKitSqlite($Database)
    $result=@{ok=$true;code=''}
    if ($requestObject.op -eq 'init') {
        $version=(Query 'PRAGMA user_version')[0]['user_version']
        if ($version -notin @('0','1','2')) { throw 'UNSUPPORTED_DATABASE_VERSION' }
        [void](Query 'PRAGMA journal_mode=WAL')
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        [void](Query 'CREATE TABLE IF NOT EXISTS launches (launch_id TEXT PRIMARY KEY, room_id TEXT NOT NULL, game_id TEXT NOT NULL, build_id TEXT NOT NULL, secret TEXT NOT NULL)')
        if (@((Query 'PRAGMA table_info(launches)') | Where-Object { $_['name'] -eq 'ended_at' }).Count -eq 0) { [void](Query 'ALTER TABLE launches ADD COLUMN ended_at INTEGER') }
        [void](Query 'CREATE TABLE IF NOT EXISTS expired_launches (launch_id TEXT PRIMARY KEY,room_id TEXT NOT NULL,game_id TEXT NOT NULL,build_id TEXT NOT NULL,ended_at INTEGER NOT NULL,rejected_count INTEGER NOT NULL DEFAULT 0,last_rejected_hash TEXT NOT NULL DEFAULT '''')')
        [void](Query 'CREATE TABLE IF NOT EXISTS result_signatures (result_id TEXT PRIMARY KEY,signature TEXT NOT NULL)')
        [void](Query 'CREATE TABLE IF NOT EXISTS results (result_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, match_id TEXT NOT NULL, result_kind TEXT NOT NULL, record_hash TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(game_id, match_id, result_kind))')
        [void](Query 'CREATE TABLE IF NOT EXISTS asset_states (user_id TEXT NOT NULL, space_id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision>=0), body TEXT NOT NULL, PRIMARY KEY(user_id,space_id))')
        [void](Query 'CREATE TABLE IF NOT EXISTS asset_receipts (user_id TEXT NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL, space_id TEXT NOT NULL, actor_id TEXT NOT NULL, command TEXT NOT NULL, previous_body TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id,request_id))')
        [void](Query $tombstoneTable)
        [void](Query 'PRAGMA user_version=2')
        [void](Query 'COMMIT'); $transaction=$false
        $result.sqlite_version=(Query 'SELECT sqlite_version() AS version')[0]['version']
    } elseif ((Query 'PRAGMA user_version')[0]['user_version'] -notin @('1','2')) { throw 'DATABASE_NOT_INITIALIZED' }
    elseif ($requestObject.op -eq 'asset.read') {
        $rows=Query 'SELECT body FROM asset_states WHERE user_id=? AND space_id=?' @($requestObject.user_id,$requestObject.space_id)
        $result.body=if ($rows.Count) { $rows[0]['body'] } else { '' }
    } elseif ($requestObject.op -eq 'asset.snapshot') {
        # Read the receipt and current state in one helper invocation. The later
        # asset.commit still performs the authoritative CAS/idempotency checks.
        $rows=Query 'SELECT fingerprint,body FROM asset_receipts WHERE user_id=? AND request_id=?' @($requestObject.user_id,$requestObject.request_id)
        $result.found=$rows.Count -gt 0
        if ($result.found) {
            if ($rows[0]['fingerprint'] -cne $requestObject.fingerprint) { $result=@{ok=$false;code='REQUEST_CONFLICT'} }
            else { $result.body=$rows[0]['body']; $result.code='DUPLICATE' }
        } else {
            $state=Query 'SELECT body FROM asset_states WHERE user_id=? AND space_id=?' @($requestObject.user_id,$requestObject.space_id)
            $result.body=if ($state.Count) { $state[0]['body'] } else { '' }
        }
    } elseif ($requestObject.op -eq 'asset.receipt') {
        $rows=Query 'SELECT fingerprint,body FROM asset_receipts WHERE user_id=? AND request_id=?' @($requestObject.user_id,$requestObject.request_id)
        $result.found=$rows.Count -gt 0
        if ($result.found) {
            if ($rows[0]['fingerprint'] -cne $requestObject.fingerprint) { $result=@{ok=$false;code='REQUEST_CONFLICT'} }
            else { $result.body=$rows[0]['body']; $result.code='DUPLICATE' }
        }
    } elseif ($requestObject.op -eq 'asset.commit') {
        # This is an internal CAS transaction, never a public SQL/asset write endpoint.
        $body=ParseJson $requestObject.body
        if ($requestObject.body.Length -gt 65536 -or [long]$requestObject.expected_revision -lt 0 -or [long]$body.revision -ne ([long]$requestObject.expected_revision+1) -or [long]$body.revision -gt 2147483647) { throw 'INVALID_ASSET_COMMIT' }
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        [void](Query $tombstoneTable)
        $receipt=Query 'SELECT fingerprint,body FROM asset_receipts WHERE user_id=? AND request_id=?' @($requestObject.user_id,$requestObject.request_id)
        $current=Query 'SELECT revision,body FROM asset_states WHERE user_id=? AND space_id=?' @($requestObject.user_id,$requestObject.space_id)
        $revision=if ($current.Count) { [long]$current[0]['revision'] } else { 0L }
        # A deleted account never gets assets back, whoever writes (player, admin, retry).
        if (Deleted ([string]$requestObject.user_id)) { $result=@{ok=$false;code='ACCOUNT_DELETED'} }
        elseif ($receipt.Count) {
            if ($receipt[0]['fingerprint'] -cne $requestObject.fingerprint) { $result=@{ok=$false;code='REQUEST_CONFLICT'} }
            else { $result.body=$receipt[0]['body']; $result.code='DUPLICATE' }
        } elseif ($revision -ne [long]$requestObject.expected_revision) { $result=@{ok=$false;code='ASSET_VERSION_CONFLICT'} }
        elseif ([long](Query 'SELECT count(*) AS count FROM asset_receipts')[0]['count'] -ge 100000) { $result=@{ok=$false;code='STORAGE_CAPACITY_EXCEEDED'} }
        else {
            $previous=if ($current.Count) { $current[0]['body'] } else { '' }
            [void](Query 'INSERT INTO asset_states (user_id,space_id,revision,body) VALUES (?,?,?,?) ON CONFLICT(user_id,space_id) DO UPDATE SET revision=excluded.revision,body=excluded.body' @($requestObject.user_id,$requestObject.space_id,[string]$body.revision,$requestObject.body))
            [void](Query 'INSERT INTO asset_receipts (user_id,request_id,fingerprint,space_id,actor_id,command,previous_body,body) VALUES (?,?,?,?,?,?,?,?)' @($requestObject.user_id,$requestObject.request_id,$requestObject.fingerprint,$requestObject.space_id,$requestObject.actor_id,$requestObject.command,$previous,$requestObject.body))
            $result.body=$requestObject.body
        }
        [void](Query 'COMMIT'); $transaction=$false
    } elseif ($requestObject.op -eq 'asset.audit') {
        $result.rows=@((Query 'SELECT request_id,space_id,actor_id,command,previous_body,body,created_at FROM asset_receipts WHERE user_id=? ORDER BY rowid DESC LIMIT 100' @($requestObject.user_id)).ToArray())
    } elseif ($requestObject.op -eq 'asset.audit_all') {
        # Trusted operator only. No user-supplied SQL, order, filter or limit.
        if (@($requestObject.PSObject.Properties.Name).Count -ne 1) { $result=@{ok=$false;code='INVALID_ASSET_COMMAND'} }
        else { $result.rows=@((Query 'SELECT user_id,request_id,space_id,actor_id,command,previous_body,body,created_at FROM asset_receipts ORDER BY rowid DESC LIMIT 100').ToArray()) }
    }
    elseif ($requestObject.op -eq 'grant') {
        $g=$requestObject.grant
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        $result.pruned=@(PruneGrants (ServerNow))
        if ([int](Query 'SELECT count(*) AS count FROM launches')[0]['count'] -ge 256) { $result=@{ok=$false;code='STORAGE_CAPACITY_EXCEEDED'} }
        elseif ((Query 'SELECT launch_id FROM expired_launches WHERE launch_id=?' @($g.launch_id)).Count) { throw 'EXPIRED_LAUNCH_REUSE' }
        else { [void](Query 'INSERT INTO launches (launch_id,room_id,game_id,build_id,secret) VALUES (?,?,?,?,?)' @($g.launch_id,$g.room_id,$g.game_id,$g.build_id,$g.secret)) }
        [void](Query 'COMMIT'); $transaction=$false
    } elseif ($requestObject.op -eq 'grant.end') {
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        $ended=if($null -ne $requestObject.PSObject.Properties['ended_at']) { $requestObject.ended_at } else { ServerNow }
        if (-not (RewardInteger $ended (ServerNow))) { throw 'INVALID_STORAGE_REQUEST' }
        [void](Query 'UPDATE launches SET ended_at=COALESCE(ended_at,CAST(? AS INTEGER)) WHERE launch_id=?' @([string]$ended,$requestObject.launch_id))
        [void](Query 'COMMIT'); $transaction=$false
    } elseif ($requestObject.op -eq 'grants') {
        $result.grants=@((Query 'SELECT * FROM launches').ToArray())
    } elseif ($requestObject.op -eq 'accept') {
        $r=$requestObject.record
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        $existing=Query 'SELECT record_hash FROM results WHERE result_id=?' @($r.result_id)
        $match=Query 'SELECT result_id FROM results WHERE game_id=? AND match_id=? AND result_kind=?' @($r.game_id,$r.match_id,$r.result_kind)
        $signed=$null -ne $requestObject.PSObject.Properties['signature']
        $authorization=''
        if ($signed) {
            $launch=Query 'SELECT room_id,game_id,build_id,secret,ended_at FROM launches WHERE launch_id=?' @($r.launch_id)
            $expired=Query 'SELECT launch_id FROM expired_launches WHERE launch_id=?' @($r.launch_id)
            $receipt=Query 'SELECT signature FROM result_signatures WHERE result_id=?' @($r.result_id)
            $exact=$existing.Count -gt 0 -and $receipt.Count -gt 0 -and $existing[0]['record_hash'] -ceq $requestObject.record_hash -and $receipt[0]['signature'] -ceq $requestObject.signature
            if ($launch.Count -eq 0) { $authorization=if($exact){'DUPLICATE'}elseif($expired.Count){'RESULT_EXPIRED'}else{'AUTH_FAILED'} }
            elseif ($launch[0]['room_id'] -cne $r.room_id -or $launch[0]['game_id'] -cne $r.game_id -or $launch[0]['build_id'] -cne $r.build_id -or (SignBody $requestObject.body $launch[0]['secret']) -cne $requestObject.signature) { $authorization='AUTH_FAILED' }
            # A legacy accepted row may predate signature receipts. While its
            # grant key still exists, metadata + HMAC above authenticates the
            # original submitted body even if deletion anonymized the stored body.
            elseif ($existing.Count -gt 0 -and $existing[0]['record_hash'] -ceq $requestObject.record_hash) {
                [void](Query 'INSERT OR IGNORE INTO result_signatures(result_id,signature) VALUES (?,?)' @($r.result_id,$requestObject.signature))
                $authorization='DUPLICATE'
            }
            elseif ($launch[0]['ended_at'] -ne '' -and [long]$launch[0]['ended_at']+604800 -le (ServerNow)) { $authorization='RESULT_EXPIRED' }
        }
        if ($authorization -eq 'DUPLICATE') { $result=@{ok=$true;code='DUPLICATE'} }
        elseif ($authorization) {
            $result=@{ok=$false;code=$authorization}
            if ($authorization -eq 'RESULT_EXPIRED') {
                [void](Query 'INSERT OR IGNORE INTO expired_launches(launch_id,room_id,game_id,build_id,ended_at) SELECT launch_id,room_id,game_id,build_id,ended_at FROM launches WHERE launch_id=? AND ended_at IS NOT NULL' @($r.launch_id))
                [void](Query 'UPDATE expired_launches SET rejected_count=rejected_count+1,last_rejected_hash=? WHERE launch_id=?' @($requestObject.record_hash,$r.launch_id))
            }
        } elseif ($existing.Count -gt 0) {
            $result.ok=$existing[0]['record_hash'] -eq $requestObject.record_hash
            $result.code=if ($result.ok) {'DUPLICATE'} else {'RESULT_CONFLICT'}
            if ($result.ok -and $signed) { [void](Query 'INSERT OR IGNORE INTO result_signatures(result_id,signature) VALUES (?,?)' @($r.result_id,$requestObject.signature)) }
        } elseif ($match.Count -gt 0) { $result=@{ok=$false;code='MATCH_RESULT_CONFLICT'} }
        elseif ([int](Query 'SELECT count(*) AS count FROM results')[0]['count'] -ge 10000) { $result=@{ok=$false;code='STORAGE_CAPACITY_EXCEEDED'} }
        else {
            $rewards=@()
            if ($null -ne $requestObject.PSObject.Properties['rewards']) {
                if ($requestObject.rewards -isnot [Array] -or $requestObject.rewards.Count -gt 256) { throw 'INVALID_REWARD' }
                $rewards=$requestObject.rewards
            }
            $rewardUsers=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach($reward in $rewards) {
                if ($reward -isnot [PSCustomObject] -or @($reward.PSObject.Properties.Name).Count -ne 4) { throw 'INVALID_REWARD' }
                if ($reward.user_id -isnot [string] -or $reward.user_id.Length -lt 1 -or $reward.user_id.Length -gt 128 -or $reward.user_id -match '[\x00-\x1f\x7f]' -or $reward.space_id -isnot [string] -or $reward.space_id -cnotmatch '^[a-z][a-z0-9_]{1,63}$' -or -not (RewardInteger $reward.credits 1000000) -or -not (RewardInteger $reward.experience 1000000) -or -not $rewardUsers.Add($reward.user_id)) { throw 'INVALID_REWARD' }
            }
            # Late settlement for a deleted account: the other players are still paid,
            # the deleted one gets no wallet back, and the stored body carries only the
            # pseudonym. record_hash stays the signed original, so retries remain DUPLICATE.
            $storedBody=$requestObject.body
            [void](Query $tombstoneTable)
            if ([long](Query 'SELECT count(*) AS count FROM deleted_subjects')[0]['count'] -gt 0) {
                $found=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                CollectStrings $r $found
                $removed=@(foreach($value in $found) { if (Deleted $value) { $value } })
                if ($removed.Count) {
                    foreach($value in $removed) { $storedBody=$storedBody.Replace('"'+$value+'"','"'+(Subject $value)+'"') }
                    $kept=@($rewards | Where-Object { $removed -cnotcontains $_.user_id })
                    $result.rewards_skipped=$rewards.Count-$kept.Count
                    $rewards=$kept
                }
            }
            if ($rewards.Count -gt 0 -and ([long](Query 'SELECT count(*) AS count FROM asset_receipts')[0]['count']+$rewards.Count) -gt 100000) {
                $result=@{ok=$false;code='STORAGE_CAPACITY_EXCEEDED'}
            } else {
                [void](Query 'INSERT INTO results (result_id,game_id,match_id,result_kind,record_hash,body) VALUES (?,?,?,?,?,?)' @($r.result_id,$r.game_id,$r.match_id,$r.result_kind,$requestObject.record_hash,$storedBody))
                if ($signed) { [void](Query 'INSERT INTO result_signatures(result_id,signature) VALUES (?,?)' @($r.result_id,$requestObject.signature)) }
                foreach($reward in $rewards) {
                    $rows=Query 'SELECT revision,body FROM asset_states WHERE user_id=? AND space_id=?' @($reward.user_id,$reward.space_id)
                    $previous=if($rows.Count){$rows[0]['body']}else{''}
                    $state=if($rows.Count){ParseJson $previous}else{[pscustomobject]@{revision=0;credits=0;experience=0;owned=@();profiles=@{}}}
                    if ($state -isnot [PSCustomObject] -or -not (RewardInteger $state.credits 1000000000) -or -not (RewardInteger $state.experience 1000000000) -or -not (RewardInteger $state.revision 2147483647) -or ($rows.Count -and [long]$rows[0]['revision'] -ne [long]$state.revision)) { throw 'ASSET_LIMIT_EXCEEDED' }
                    $state.credits=[long]$state.credits+[long]$reward.credits
                    $state.experience=[long]$state.experience+[long]$reward.experience
                    $state.revision=[long]$state.revision+1
                    if($state.credits -gt 1000000000 -or $state.experience -gt 1000000000 -or $state.revision -gt 2147483647) {throw 'ASSET_LIMIT_EXCEEDED'}
                    $body=$state|ConvertTo-Json -Compress -Depth 20
                    if ($body.Length -gt 65536) { throw 'ASSET_LIMIT_EXCEEDED' }
                    $command=@{kind='result_reward';result_id=$r.result_id;credits=$reward.credits;experience=$reward.experience}|ConvertTo-Json -Compress
                    [void](Query 'INSERT INTO asset_states (user_id,space_id,revision,body) VALUES (?,?,?,?) ON CONFLICT(user_id,space_id) DO UPDATE SET revision=excluded.revision,body=excluded.body' @($reward.user_id,$reward.space_id,[string]$state.revision,$body))
                    [void](Query 'INSERT INTO asset_receipts (user_id,request_id,fingerprint,space_id,actor_id,command,previous_body,body) VALUES (?,?,?,?,?,?,?,?)' @($reward.user_id,('result_'+$r.result_id),$requestObject.record_hash,$reward.space_id,('game:'+ $r.game_id),$command,$previous,$body))
                }
            }
        }
        [void](Query 'COMMIT'); $transaction=$false
    } elseif ($requestObject.op -eq 'asset.purge_user') {
        # Step 2 of the test-stage account deletion; trusted operator only. One
        # transaction removes every space's state and receipts of this user, replaces
        # the user_id in stored results and in receipts it acted on, and records the
        # tombstone. Repeating it is harmless, which the resumable job relies on.
        # With the optional username, free text in other users' receipt commands
        # (administrator reasons) loses the user_id and username as well.
        $id=$requestObject.user_id
        $name=if ($null -ne $requestObject.PSObject.Properties['username']) { $requestObject.username } else { '' }
        if (@($requestObject.PSObject.Properties.Name).Count -notin @(2,3) -or $name -isnot [string] -or $name.Length -gt 32 -or $name -match '[\x00-\x1f\x7f]' -or $id -isnot [string] -or $id.Length -lt 1 -or $id.Length -gt 128 -or $id -match '[\x00-\x1f\x7f]') { $result=@{ok=$false;code='INVALID_ASSET_COMMAND'} }
        else {
            $subject=Subject $id
            [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
            [void](Query $tombstoneTable)
            $spaces=@(foreach($row in (Query 'SELECT space_id FROM asset_states WHERE user_id=? ORDER BY space_id' @($id))) { $row['space_id'] })
            $receiptCount=[long](Query 'SELECT count(*) AS count FROM asset_receipts WHERE user_id=?' @($id))[0]['count']
            $actorCount=[long](Query 'SELECT count(*) AS count FROM asset_receipts WHERE actor_id=? AND user_id<>?' @($id,$id))[0]['count']
            [void](Query 'DELETE FROM asset_states WHERE user_id=?' @($id))
            [void](Query 'DELETE FROM asset_receipts WHERE user_id=?' @($id))
            [void](Query 'UPDATE asset_receipts SET actor_id=? WHERE actor_id=?' @($subject,$id))
            $quoted='"'+$id+'"'
            $rows=Query 'SELECT result_id,body FROM results WHERE instr(body,?)>0' @($quoted)
            foreach($row in $rows) { [void](Query 'UPDATE results SET body=? WHERE result_id=?' @($row['body'].Replace($quoted,'"'+$subject+'"'),$row['result_id'])) }
            $scrubbed=0
            foreach($needle in @($id,$name)) {
                if ($needle.Length -lt 3) { continue }
                foreach($row in (Query 'SELECT user_id,request_id,command FROM asset_receipts WHERE instr(lower(command),lower(?))>0' @($needle))) {
                    $text=$row['command']
                    foreach($value in @($id,$name)) { if ($value.Length -ge 3) { $text=[regex]::Replace($text,[regex]::Escape($value),$subject,[Text.RegularExpressions.RegexOptions]::IgnoreCase) } }
                    [void](Query 'UPDATE asset_receipts SET command=? WHERE user_id=? AND request_id=?' @($text,$row['user_id'],$row['request_id']))
                    $scrubbed++
                }
            }
            [void](Query 'INSERT OR IGNORE INTO deleted_subjects (subject,deleted_at) VALUES (?,?)' @($subject,[string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()))
            [void](Query 'COMMIT'); $transaction=$false
            $result.subject=$subject
            $result.spaces=$spaces
            $result.asset_states=$spaces.Count
            $result.asset_receipts=$receiptCount
            $result.actor_receipts=$actorCount
            $result.results_deidentified=$rows.Count
            $result.receipt_texts_scrubbed=$scrubbed
        }
    } elseif ($requestObject.op -eq 'inspect') {
        $result.count=[int](Query 'SELECT count(*) AS count FROM results')[0]['count']
        $result.integrity=(Query 'PRAGMA integrity_check')[0]['integrity_check']
        $result.rows=@((Query 'SELECT body FROM results ORDER BY rowid DESC LIMIT 100').ToArray())
    } elseif ($requestObject.op -eq 'backup') {
        $target=[IO.Path]::GetFullPath($requestObject.destination)
        $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Database))
        # Platform separator; names are case-insensitive only on Windows.
        $separator=[IO.Path]::DirectorySeparatorChar
        $comparison=if ($separator -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if (-not $target.StartsWith($parent+$separator,$comparison) -or (Test-Path -LiteralPath $target)) { throw 'INVALID_BACKUP_PATH' }
        $db.Backup($target)
    } else { throw 'UNKNOWN_STORAGE_OPERATION' }
    # Godot's Windows OS.execute pipe may decode through the system code page.
    # ASCII JSON escapes preserve Unicode regardless of that pipe encoding.
    $json=$result | ConvertTo-Json -Compress -Depth 30
    [regex]::Replace($json,'[^\x00-\x7F]',{ param($match) '\u{0:x4}' -f [int][char]$match.Value })
} catch {
    if ($transaction -and $db) { try { [void](Query 'ROLLBACK') } catch {} }
    # Do not log SQL, records or signing keys on failure.
    if ($_.Exception.Message -in @('INVALID_REWARD','ASSET_LIMIT_EXCEEDED')) {
        Write-Output ('{"ok":false,"code":"'+$_.Exception.Message+'"}')
        exit 0
    }
    Write-Output '{"ok":false,"code":"STORAGE_UNAVAILABLE"}'
    exit 1
} finally { if ($db) { $db.Dispose() } }
