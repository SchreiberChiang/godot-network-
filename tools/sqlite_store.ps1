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
using System.Runtime.InteropServices;
public sealed class RoomKitSqlite : IDisposable {
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
function Query([string]$Sql,[string[]]$Values=@()) { return ,($db.Query($Sql,$Values)) }
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
        $requestObject=$RequestJson | ConvertFrom-Json
    } elseif ($Request) {
        $requestObject=Get-Content -Encoding UTF8 -LiteralPath $Request -Raw | ConvertFrom-Json
    } else {
        # Stdin mode from bounded_helper.ps1: one base64 UTF-8 JSON line. Used for
        # requests carrying room result signing keys, so they never touch disk.
        $line=[Console]::In.ReadLine()
        if ([string]::IsNullOrEmpty($line) -or $line.Length -gt 65536 -or $line.Length % 4 -ne 0 -or $line -notmatch '^[A-Za-z0-9+/]*={0,2}$') { throw 'INVALID_STORAGE_REQUEST' }
        $requestObject=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line)) | ConvertFrom-Json
    }
    $db=New-Object RoomKitSqlite($Database)
    $result=@{ok=$true;code=''}
    if ($requestObject.op -eq 'init') {
        $version=(Query 'PRAGMA user_version')[0]['user_version']
        if ($version -notin @('0','1','2')) { throw 'UNSUPPORTED_DATABASE_VERSION' }
        [void](Query 'PRAGMA journal_mode=WAL')
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        [void](Query 'CREATE TABLE IF NOT EXISTS launches (launch_id TEXT PRIMARY KEY, room_id TEXT NOT NULL, game_id TEXT NOT NULL, build_id TEXT NOT NULL, secret TEXT NOT NULL)')
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
        $body=$requestObject.body | ConvertFrom-Json
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
        if ([int](Query 'SELECT count(*) AS count FROM launches')[0]['count'] -ge 256) { $result=@{ok=$false;code='STORAGE_CAPACITY_EXCEEDED'} }
        else { [void](Query 'INSERT INTO launches (launch_id,room_id,game_id,build_id,secret) VALUES (?,?,?,?,?)' @($g.launch_id,$g.room_id,$g.game_id,$g.build_id,$g.secret)) }
        [void](Query 'COMMIT'); $transaction=$false
    } elseif ($requestObject.op -eq 'grants') {
        $result.grants=@((Query 'SELECT * FROM launches').ToArray())
    } elseif ($requestObject.op -eq 'accept') {
        $r=$requestObject.record
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        $existing=Query 'SELECT record_hash FROM results WHERE result_id=?' @($r.result_id)
        $match=Query 'SELECT result_id FROM results WHERE game_id=? AND match_id=? AND result_kind=?' @($r.game_id,$r.match_id,$r.result_kind)
        if ($existing.Count -gt 0) {
            $result.ok=$existing[0]['record_hash'] -eq $requestObject.record_hash
            $result.code=if ($result.ok) {'DUPLICATE'} else {'RESULT_CONFLICT'}
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
                foreach($reward in $rewards) {
                    $rows=Query 'SELECT revision,body FROM asset_states WHERE user_id=? AND space_id=?' @($reward.user_id,$reward.space_id)
                    $previous=if($rows.Count){$rows[0]['body']}else{''}
                    $state=if($rows.Count){$previous|ConvertFrom-Json}else{[pscustomobject]@{revision=0;credits=0;experience=0;owned=@();profiles=@{}}}
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
        if (-not $target.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $target)) { throw 'INVALID_BACKUP_PATH' }
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
