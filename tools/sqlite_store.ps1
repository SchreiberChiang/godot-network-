param([Parameter(Mandatory=$true)][string]$Database,[Parameter(Mandatory=$true)][string]$Request)
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
try {
    $requestObject=Get-Content -Encoding UTF8 -LiteralPath $Request -Raw | ConvertFrom-Json
    $db=New-Object RoomKitSqlite($Database)
    $result=@{ok=$true;code=''}
    if ($requestObject.op -eq 'init') {
        [void](Query 'PRAGMA journal_mode=WAL')
        $version=(Query 'PRAGMA user_version')[0]['user_version']
        if ($version -notin @('0','1')) { throw 'UNSUPPORTED_DATABASE_VERSION' }
        [void](Query 'BEGIN IMMEDIATE'); $transaction=$true
        [void](Query 'CREATE TABLE IF NOT EXISTS launches (launch_id TEXT PRIMARY KEY, room_id TEXT NOT NULL, game_id TEXT NOT NULL, build_id TEXT NOT NULL, secret TEXT NOT NULL)')
        [void](Query 'CREATE TABLE IF NOT EXISTS results (result_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, match_id TEXT NOT NULL, result_kind TEXT NOT NULL, record_hash TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(game_id, match_id, result_kind))')
        [void](Query 'PRAGMA user_version=1')
        [void](Query 'COMMIT'); $transaction=$false
        $result.sqlite_version=(Query 'SELECT sqlite_version() AS version')[0]['version']
    } elseif ((Query 'PRAGMA user_version')[0]['user_version'] -ne '1') { throw 'DATABASE_NOT_INITIALIZED' }
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
        else { [void](Query 'INSERT INTO results (result_id,game_id,match_id,result_kind,record_hash,body) VALUES (?,?,?,?,?,?)' @($r.result_id,$r.game_id,$r.match_id,$r.result_kind,$requestObject.record_hash,$requestObject.body)) }
        [void](Query 'COMMIT'); $transaction=$false
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
    Write-Output '{"ok":false,"code":"STORAGE_UNAVAILABLE"}'
    exit 1
} finally { if ($db) { $db.Dispose() } }
