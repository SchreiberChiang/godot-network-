param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Work,
    [string]$Foreign=''
)
# L1 storage slice: the production storage helpers of $Source (sqlite_store.ps1,
# account_store.ps1, storage_worker.ps1) driven directly, without Godot, on a
# brand-new fake data directory. The same script runs under Windows PowerShell 5.1
# and PowerShell 7 on Linux, so its PASS/FAIL lines can be compared one by one.
# Requests go to the helpers on standard input (never files or arguments), as in
# production. All accounts, passwords and assets here are test values.
# -Foreign <dir>: additionally open accounts.sqlite / assets.sqlite produced by
# this script on the other platform (its export folder) and use them.
$ErrorActionPreference='Stop'
$Source=[IO.Path]::GetFullPath($Source)
$Work=[IO.Path]::GetFullPath($Work)
if(Test-Path -LiteralPath $Work) { if(@(Get-ChildItem -LiteralPath $Work -Force).Count) { throw 'Work directory must be empty.' } } else { [void][IO.Directory]::CreateDirectory($Work) }
$windows=[IO.Path]::DirectorySeparatorChar -eq '\'
$tools=[IO.Path]::Combine($Source,'tools')
$shell=(Get-Process -Id $PID).Path
$utf8=New-Object Text.UTF8Encoding($false)
$keepText=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
function FromJson([string]$Text) { if($keepText) { return ConvertFrom-Json -InputObject $Text -DateKind String }; return ConvertFrom-Json -InputObject $Text }
$script:passed=0; $script:failed=0; $script:notRun=0
function Check([bool]$Condition,[string]$Name) { if($Condition){ $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) } }
function Info([string]$Text) { Write-Output ('INFO '+$Text) }
function U([int[]]$Codes) { return -join ($Codes | ForEach-Object { [char]::ConvertFromUtf32($_) }) }

# Test values. Non-ASCII text is built from code points so this file stays ASCII.
$password='Slice-'+(U 0x5BC6,0x7801)+'-Pass-01'
$adminName=(U 0x7BA1,0x7406,0x5458)+' '+(U 0x3A9)
$playerName=(U 0x73A9,0x5BB6)+' '+(U 0x4E00)+' '+(U 0x1F3AE)
$dateName='2026-09-30T10:00:00Z'
$reasonText=(U 0x6D4B,0x8BD5)+' '+(U 0x53D1,0x653E)+' '+(U 0x1F381)+" it's <ok> & done"
$dataName=(U 0x5B58,0x6863)+' '+(U 0x6D4B,0x8BD5)+' dir'
$fixedSalt='AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='
$fixedHash='3uy/ydkNOuRRnl10Y7Sxi6J9sbgKDfOaYIka1YRc3bA='
$data=[IO.Path]::Combine($Work,$dataName)
[void][IO.Directory]::CreateDirectory($data)
$accountsDb=[IO.Path]::Combine($data,'accounts.sqlite')
$assetsDb=[IO.Path]::Combine($data,'assets.sqlite')
Info ('platform='+[Environment]::OSVersion.Platform+' ps='+$PSVersionTable.PSVersion+' runtime='+[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)

# ---- child helper processes (request on stdin as one base64 line) ----
function Quote($values) { foreach($value in $values){ '"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
function StartShell([string[]]$Arguments) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$shell
    $prefix=@('-NoProfile','-NonInteractive'); if($windows) { $prefix+=@('-ExecutionPolicy','Bypass') }
    $info.Arguments=(Quote ($prefix+$Arguments)) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    # Windows PowerShell 5.1 derives the child stdin encoding from the console
    # input encoding and may emit a byte order mark; requests are ASCII base64.
    if($windows) { try { [Console]::InputEncoding=$utf8 } catch {} }
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$info
    [void]$process.Start()
    return $process
}
$script:timings=New-Object Collections.ArrayList
$script:notes=New-Object Collections.ArrayList
function Call([string]$Helper,[string]$Database,$Request,[string]$Label='') {
    $json=ConvertTo-Json -InputObject $Request -Compress -Depth 12
    $line=[Convert]::ToBase64String($utf8.GetBytes($json))
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $process=StartShell @('-File',[IO.Path]::Combine($tools,$Helper),'-Database',$Database)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine($line); $process.StandardInput.Close()
        if(-not $process.WaitForExit(120000)) { $process.Kill(); return [pscustomobject]@{ok=$false;code='DRIVER_TIMEOUT'} }
        $watch.Stop()
        if($Label) { [void]$script:timings.Add([pscustomobject]@{label=$Label;ms=[int]$watch.ElapsedMilliseconds}) }
        $text=$stdout.Result.Trim()
        if(-not $text.StartsWith('{')) { return [pscustomobject]@{ok=$false;code='DRIVER_NO_JSON';exit=$process.ExitCode;stderr=($stderr.Result -split "`n" | Select-Object -First 3) -join ' | '} }
        $reply=FromJson $text
        if(@($text.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count) { $reply | Add-Member -NotePropertyName non_ascii_output -NotePropertyValue $true }
        return $reply
    } finally { $process.Dispose() }
}
function Account($Request,[string]$Label='') { return Call 'account_store.ps1' $accountsDb $Request $Label }
function Asset($Request,[string]$Label='') { return Call 'sqlite_store.ps1' $assetsDb $Request $Label }

# ---- 1. shared SQLite binding, in this process ----
try {
    $source=[IO.File]::ReadAllText([IO.Path]::Combine($tools,'sqlite_store.ps1'))
    $binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    Add-Type -TypeDefinition $binding.Groups[1].Value
    $expectedLibrary=if($windows){'winsqlite3.dll'}else{'libsqlite3.so.0'}
    Check ([RoomKitSqlite]::LibraryName() -eq $expectedLibrary) ('binding uses the platform SQLite library ('+[RoomKitSqlite]::LibraryName()+')')
    $probePath=[IO.Path]::Combine($data,'probe '+(U 0x6570,0x636E)+'.sqlite')
    $probe=New-Object RoomKitSqlite($probePath)
    try {
        Info ('sqlite_version='+$probe.Query('SELECT sqlite_version() AS v',[string[]]@())[0]['v'])
        [void]$probe.Query('CREATE TABLE t (id TEXT PRIMARY KEY, body TEXT NOT NULL)',[string[]]@())
        $values=@($playerName,$reasonText,"x'); DROP TABLE t;--",'',(U 0x1F600,0x1F3AE))
        for($i=0;$i -lt $values.Count;$i++) { [void]$probe.Query('INSERT INTO t (id,body) VALUES (?,?)',[string[]]@([string]$i,$values[$i])) }
        $rows=$probe.Query('SELECT id,body FROM t ORDER BY id',[string[]]@())
        $same=$rows.Count -eq $values.Count
        for($i=0;$i -lt $values.Count -and $same;$i++) { $same=$rows[$i]['body'] -ceq $values[$i] }
        Check $same 'bound parameters round-trip Unicode, quotes and SQL-looking text exactly'
        Check ($probe.Query('SELECT length(body) AS n FROM t WHERE id=?',[string[]]@('0'))[0]['n'] -eq [string]([Globalization.StringInfo]::new($playerName).LengthInTextElements)) 'SQLite counts the stored text in characters (UTF-8 stored correctly)'
        $copy=[IO.Path]::Combine($data,'probe copy.sqlite')
        $probe.Backup($copy)
    } finally { $probe.Dispose() }
    Check ([IO.File]::Exists($probePath)) 'database opens at a path with Chinese characters and spaces'
    $reopened=New-Object RoomKitSqlite($copy)
    try { Check ($reopened.Query('SELECT body FROM t WHERE id=?',[string[]]@('1'))[0]['body'] -ceq $reasonText -and $reopened.Query('PRAGMA integrity_check',[string[]]@())[0]['integrity_check'] -eq 'ok') 'backup handle writes a copy that reopens with the same text and passes the integrity check' } finally { $reopened.Dispose() }
} catch {
    $e=$_.Exception; $chain=@(); while($e) { $chain+=($e.GetType().Name+': '+$e.Message); $e=$e.InnerException }
    Check $false ('shared SQLite binding loads and works :: '+(($chain | Select-Object -First 4) -join ' <- '))
}

# ---- 2. password derivation ----
try {
    $accountSource=[IO.File]::ReadAllText([IO.Path]::Combine($tools,'account_store.ps1'))
    $passwords=[regex]::Matches($accountSource,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@") | Where-Object { $_.Groups[1].Value.Contains('RoomKitPasswords') } | Select-Object -First 1
    Add-Type -TypeDefinition $passwords.Groups[1].Value
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $derived=[RoomKitPasswords]::Derive($password,$fixedSalt,600000)
    $watch.Stop()
    Info ('pbkdf2_600000_ms='+[int]$watch.ElapsedMilliseconds)
    Check ($derived -ceq $fixedHash) 'PBKDF2-SHA256 (600000 iterations, fixed salt, Unicode password) matches the independent known answer'
    Check ([RoomKitPasswords]::Verify($password,$fixedSalt,600000,$fixedHash) -and -not [RoomKitPasswords]::Verify($password+'x',$fixedSalt,600000,$fixedHash)) 'password verification accepts the right password and rejects a wrong one'
} catch { Check $false ('password derivation available :: '+$_.Exception.Message) }

# ---- 3. accounts through the production helper ----
$ip='192.0.2.10'
$reply=Account @{op='init'} 'account init (first call)'
Check ($reply.ok -eq $true) ('account database initializes ('+$reply.code+$reply.stderr+')')
Check ((Account @{op='setup.status'}).initialized -eq $false) 'new database reports no administrator'
$admin=Account @{op='setup.admin';username='slice_admin';password=$password;display_name=$adminName} 'setup.admin'
Check ($admin.ok -eq $true -and $admin.identity.role -eq 'admin' -and $admin.identity.display_name -ceq $adminName) 'administrator is created with its Unicode display name'
Check ((Account @{op='setup.admin';username='slice_admin2';password=$password;display_name='x'}).code -eq 'SETUP_COMPLETE') 'a second administrator setup is refused'
$adminLogin=Account @{op='account.login';username='slice_admin';password=$password;client_ip=$ip} 'admin login'
Check ($adminLogin.ok -eq $true -and [string]$adminLogin.token -cmatch '^[a-f0-9]{64}$') 'administrator logs in and receives a session token'
$invite=Account @{op='invite.create';token=$adminLogin.token;uses=2;reason=$reasonText}
Check ($invite.ok -eq $true -and [string]$invite.invite_code -cmatch '^[a-f0-9]{32}$') 'administrator creates an invite code'
$player=Account @{op='account.register';username='slice_player';password=$password;display_name=$playerName;invite_code=$invite.invite_code;client_ip=$ip} 'account.register'
Check ($player.ok -eq $true -and $player.identity.role -eq 'player' -and $player.identity.display_name -ceq $playerName) 'player registers with the invite and a Unicode display name'
Check ((Account @{op='account.register';username='slice_player';password=$password;display_name='x';invite_code=$invite.invite_code;client_ip=$ip}).code -eq 'USERNAME_UNAVAILABLE') 'a duplicate username is refused'
Check ((Account @{op='account.register';username='slice_other';password=$password;display_name='x';invite_code=('0'*32);client_ip=$ip}).code -eq 'INVITE_INVALID') 'an unknown invite code is refused'
$dated=Account @{op='account.register';username='slice_dated';password=$password;display_name=$dateName;invite_code=$invite.invite_code;client_ip=$ip}
Check ($dated.ok -eq $true -and $dated.identity.display_name -ceq $dateName) ('a date-looking display name stays text ('+$dated.code+')')
Check ((Account @{op='account.register';username='slice_third';password=$password;display_name='x';invite_code=$invite.invite_code;client_ip=$ip}).code -eq 'INVITE_INVALID') 'an invite is refused after its two uses'
$wrong=Account @{op='account.login';username='slice_player';password=($password+'!');client_ip=$ip} 'login with wrong password'
Check ($wrong.ok -eq $false -and $wrong.code -eq 'AUTH_FAILED') 'a wrong password is rejected'
$login=Account @{op='account.login';username='slice_player';password=$password;client_ip=$ip} 'player login'
Check ($login.ok -eq $true -and [string]$login.token -cmatch '^[a-f0-9]{64}$') 'player logs in with the right password'
$session=Account @{op='session.authenticate';token=$login.token} 'session.authenticate (one-shot)'
Check ($session.ok -eq $true -and $session.identity.user_id -ceq $player.identity.user_id -and $session.identity.display_name -ceq $playerName) 'session check returns the same identity and display name'
Check ((Account @{op='session.authenticate';token=('f'*64)}).code -eq 'AUTH_FAILED') 'an unknown session token is rejected'
Check ((Account @{op='account.login';username='slice_player';password=$password;client_ip=$ip}).code -eq 'ALREADY_LOGGED_IN') 'a second player login is refused while a session exists'
Check (-not $session.non_ascii_output -and -not $admin.non_ascii_output) 'helper output is ASCII-only JSON (Unicode escaped)'
$userId=[string]$player.identity.user_id

# ---- 4. assets through the production helper ----
function Body([int]$Revision,[int]$Credits,[string[]]$Owned,[hashtable]$Profiles) { return (ConvertTo-Json -Compress -Depth 6 -InputObject ([ordered]@{revision=$Revision;credits=$Credits;experience=0;owned=@($Owned);profiles=$Profiles})) }
function Commit([string]$RequestId,[string]$Fingerprint,[int]$Expected,[string]$Body,[string]$Command,[string]$Label='') {
    return Asset ([ordered]@{op='asset.commit';user_id=$userId;space_id='shooter';request_id=$RequestId;fingerprint=$Fingerprint;expected_revision=$Expected;body=$Body;actor_id='admin:slice';command=$Command}) $Label
}
function Balance { $row=Asset @{op='asset.read';user_id=$userId;space_id='shooter'}; if([string]$row.body -eq '') { return $null }; return FromJson $row.body }
$reply=Asset @{op='init'} 'asset init (first call)'
Check ($reply.ok -eq $true) ('asset database initializes ('+$reply.code+$reply.stderr+')')
Info ('asset database sqlite_version='+$reply.sqlite_version)
Check ((Asset @{op='asset.read';user_id=$userId;space_id='shooter'}).body -eq '') 'a new player has no stored assets'
$grantCommand=ConvertTo-Json -Compress -InputObject ([ordered]@{kind='admin_adjust';credits=500;reason=$reasonText})
$grant=Commit 'req_grant' 'fp_grant' 0 (Body 1 500 @('rifle') @{shooter=@{primary='rifle'}}) $grantCommand 'asset.commit'
Check ($grant.ok -eq $true -and $grant.code -eq '') 'first commit stores the granted balance'
$buyBody=Body 2 380 @('rifle','smg') @{shooter=@{primary='rifle'}}
$buy=Commit 'req_buy' 'fp_buy' 1 $buyBody '{"kind":"purchase","item_id":"smg","price":120}'
Check ($buy.ok -eq $true -and (Balance).credits -eq 380) 'purchase commit deducts the price'
$again=Commit 'req_buy' 'fp_buy' 1 $buyBody '{"kind":"purchase","item_id":"smg","price":120}'
$after=Balance
Check ($again.ok -eq $true -and $again.code -eq 'DUPLICATE' -and $again.body -ceq $buyBody -and $after.credits -eq 380 -and $after.revision -eq 2) 'repeating the same purchase request returns the stored receipt and deducts only once'
Check ((Commit 'req_buy' 'fp_other' 2 (Body 3 260 @('rifle','smg') @{}) '{}').code -eq 'REQUEST_CONFLICT') 'the same request id with different content is refused'
Check ((Commit 'req_stale' 'fp_stale' 1 (Body 2 100 @('rifle') @{}) '{}').code -eq 'ASSET_VERSION_CONFLICT') 'a commit based on a stale revision is refused'
$jump=Commit 'req_jump' 'fp_jump' 2 (Body 9 0 @() @{}) '{}'
Check ($jump.ok -eq $false) 'a commit that skips revisions is refused'
$select=Commit 'req_select' 'fp_select' 2 (Body 3 380 @('rifle','smg') @{shooter=@{primary='smg'}}) '{"kind":"select","slot":"primary","item_id":"smg"}'
$final=Balance
Check ($select.ok -eq $true -and $final.revision -eq 3 -and $final.credits -eq 380 -and $final.profiles.shooter.primary -eq 'smg' -and @($final.owned) -contains 'smg') 'selection commit saves the loadout; balance is unchanged by the refused requests'
$snapshot=Asset @{op='asset.snapshot';user_id=$userId;space_id='shooter';request_id='req_buy';fingerprint='fp_buy'}
Check ($snapshot.found -eq $true -and $snapshot.code -eq 'DUPLICATE') 'snapshot reports the purchase receipt'
$receipt=Asset @{op='asset.receipt';user_id=$userId;request_id='req_nope';fingerprint='x'}
Check ($receipt.ok -eq $true -and $receipt.found -eq $false) 'an unknown request has no receipt'
$audit=Asset @{op='asset.audit';user_id=$userId}
$grantRow=@($audit.rows) | Where-Object { $_.request_id -eq 'req_grant' }
Check (@($audit.rows).Count -eq 3 -and (FromJson $grantRow.command).reason -ceq $reasonText) 'three receipts are recorded and the Unicode command text is preserved exactly'
Check ((Asset @{op='inspect'}).integrity -eq 'ok') 'asset database passes the integrity check'

# ---- 5. backup, restore, reopen ----
$assetBackup=[IO.Path]::Combine($data,'assets backup.sqlite')
Check ((Asset @{op='backup';destination=$assetBackup} 'asset backup').ok -eq $true -and [IO.File]::Exists($assetBackup)) 'asset backup is written next to the database (path with spaces)'
Check ((Asset @{op='backup';destination=$assetBackup}).ok -eq $false) 'backup refuses to overwrite an existing file'
Check ((Asset @{op='backup';destination=[IO.Path]::Combine($Work,'outside.sqlite')}).ok -eq $false -and -not [IO.File]::Exists([IO.Path]::Combine($Work,'outside.sqlite'))) 'backup refuses a destination outside the database folder'
$accountBackup=[IO.Path]::Combine($data,'accounts backup.sqlite')
try { $handle=New-Object RoomKitSqlite($accountsDb); try { $handle.Backup($accountBackup) } finally { $handle.Dispose() } } catch {}
Check ([IO.File]::Exists($accountBackup)) 'account backup is written through the shared binding'
$spend=Commit 'req_spend' 'fp_spend' 3 (Body 4 0 @('rifle','smg') @{shooter=@{primary='smg'}}) '{"kind":"admin_adjust","credits":-380}'
$logout=Account @{op='session.logout';token=$login.token}
Check ($spend.ok -eq $true -and (Balance).credits -eq 0 -and $logout.ok -eq $true -and (Account @{op='session.authenticate';token=$login.token}).code -eq 'AUTH_FAILED') 'state changes after the backup (balance spent, session ended)'
foreach($name in @('assets.sqlite','assets.sqlite-wal','assets.sqlite-shm','accounts.sqlite','accounts.sqlite-wal','accounts.sqlite-shm')) { $path=[IO.Path]::Combine($data,$name); if([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
[IO.File]::Copy($assetBackup,$assetsDb); [IO.File]::Copy($accountBackup,$accountsDb)
$restored=Balance
Check ($restored.credits -eq 380 -and $restored.revision -eq 3 -and (Asset @{op='inspect'}).integrity -eq 'ok') 'restored asset database reopens with the balance from the backup'
$resumed=Account @{op='session.authenticate';token=$login.token}
Check ($resumed.ok -eq $true -and $resumed.identity.display_name -ceq $playerName) 'restored account database reopens and the session from the backup is valid again'

# ---- 6. resident worker (isolated; ends when its input closes) ----
function Worker([string]$Helper,[string]$Database,$Request,[int]$Count,[string]$Label) {
    $process=StartShell @('-File',[IO.Path]::Combine($tools,'storage_worker.ps1'),'-Helper',$Helper,'-Database',$Database,'-IdleSeconds','60')
    try {
        $line=[Convert]::ToBase64String($utf8.GetBytes((ConvertTo-Json -InputObject $Request -Compress -Depth 8)))
        $times=@(); $good=0
        for($i=0;$i -lt $Count;$i++) {
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $process.StandardInput.WriteLine($line); $process.StandardInput.Flush()
            $task=$process.StandardOutput.ReadLineAsync()
            if(-not $task.Wait(60000)) { break }
            $watch.Stop(); $times+=[double]$watch.Elapsed.TotalMilliseconds
            if($task.Result -and (FromJson $task.Result).ok -eq $true) { $good++ }
        }
        $process.Refresh(); $memory=[math]::Round($process.WorkingSet64/1MB,1); $peak=[math]::Round($process.PeakWorkingSet64/1MB,1)
        $process.StandardInput.Close()
        $exited=$process.WaitForExit(10000)
        $warm=@($times | Select-Object -Skip 1 | Sort-Object)
        $median=if($warm.Count){ [math]::Round($warm[[int][math]::Floor($warm.Count/2)],1) } else { -1 }
        $p95=if($warm.Count){ [math]::Round($warm[[math]::Min($warm.Count-1,[int][math]::Ceiling($warm.Count*0.95)-1)],1) } else { -1 }
        [void]$script:notes.Add($Label+' worker: first_reply_ms='+[int]$times[0]+' warm_median_ms='+$median+' warm_p95_ms='+$p95+' requests='+$times.Count+' working_set_mb='+$memory+' peak_mb='+$peak)
        return [pscustomobject]@{good=$good;exited=$exited;code=$(if($exited){$process.ExitCode}else{-1})}
    } finally { if(-not $process.HasExited) { $process.Kill() }; $process.Dispose() }
}
$assetWorker=Worker 'sqlite_store.ps1' $assetsDb @{op='asset.read';user_id=$userId;space_id='shooter'} 30 'asset.read'
Check ($assetWorker.good -eq 30) 'resident asset worker answers 30 reads'
Check ($assetWorker.exited -and $assetWorker.code -eq 0) 'resident asset worker exits by itself when its input closes'
$accountWorker=Worker 'account_store.ps1' $accountsDb @{op='session.authenticate';token=$login.token} 20 'session.authenticate'
Check ($accountWorker.good -eq 20) 'resident account worker answers 20 session checks'
Check ($accountWorker.exited -and $accountWorker.code -eq 0) 'resident account worker exits by itself when its input closes'

# ---- 7. file permissions ----
if($windows) { $script:notRun++; Write-Output 'NOT RUN owner-only permissions (POSIX modes; Windows uses ACLs via protect_data.ps1)' }
else {
    $modes=@{}; foreach($path in @($data,$accountsDb,$assetsDb,$assetBackup)) { $modes[[IO.Path]::GetFileName($path)]=(& stat -c '%a' $path) }
    Info ('modes: '+(($modes.GetEnumerator() | ForEach-Object { $_.Value }) -join ','))
    Check ($modes[[IO.Path]::GetFileName($data)] -eq '700' -and $modes['accounts.sqlite'] -eq '600' -and $modes['assets.sqlite'] -eq '600' -and $modes['assets backup.sqlite'] -eq '600') 'test data folder is 700 and databases are 600 (owner only)'
}

# ---- 8. export two fresh single-file databases for the other platform ----
$export=[IO.Path]::Combine($Work,'export'); [void][IO.Directory]::CreateDirectory($export)
[void](Account @{op='session.logout';token=$login.token})
$exportAssets=[IO.Path]::Combine($data,'assets export.sqlite')
$exported=(Asset @{op='backup';destination=$exportAssets}).ok -eq $true
try { $handle=New-Object RoomKitSqlite($accountsDb); try { $handle.Backup([IO.Path]::Combine($export,'accounts.sqlite')) } finally { $handle.Dispose() } } catch { $exported=$false }
if($exported) { [IO.File]::Move($exportAssets,[IO.Path]::Combine($export,'assets.sqlite')) }
Check ($exported -and [IO.File]::Exists([IO.Path]::Combine($export,'accounts.sqlite')) -and [IO.File]::Exists([IO.Path]::Combine($export,'assets.sqlite'))) 'exports single-file copies of both test databases'

# ---- 9. databases produced on the other platform ----
if($Foreign) {
    $foreignData=[IO.Path]::Combine($Work,'foreign '+$dataName); [void][IO.Directory]::CreateDirectory($foreignData)
    $accountsDb=[IO.Path]::Combine($foreignData,'accounts.sqlite'); $assetsDb=[IO.Path]::Combine($foreignData,'assets.sqlite')
    [IO.File]::Copy([IO.Path]::Combine([IO.Path]::GetFullPath($Foreign),'accounts.sqlite'),$accountsDb)
    [IO.File]::Copy([IO.Path]::Combine([IO.Path]::GetFullPath($Foreign),'assets.sqlite'),$assetsDb)
    Check ((Asset @{op='inspect'}).integrity -eq 'ok') 'foreign asset database passes the integrity check'
    $foreignLogin=Account @{op='account.login';username='slice_player';password=$password;client_ip=$ip}
    Check ($foreignLogin.ok -eq $true) ('foreign account database accepts the player login (password hash made on the other platform) ('+$foreignLogin.code+')')
    Check ($foreignLogin.identity.display_name -ceq $playerName) 'foreign account keeps the Unicode display name'
    Check ((Account @{op='account.login';username='slice_player';password=($password+'!');client_ip=$ip}).ok -eq $false) 'foreign account database still rejects a wrong password'
    $userId=[string]$foreignLogin.identity.user_id
    $foreignState=Balance
    Check ($foreignState.credits -eq 380 -and $foreignState.revision -eq 3 -and $foreignState.profiles.shooter.primary -eq 'smg') 'foreign asset database holds the expected balance and loadout'
    $foreignAudit=Asset @{op='asset.audit';user_id=$userId}
    Check ((FromJson (@($foreignAudit.rows) | Where-Object { $_.request_id -eq 'req_grant' }).command).reason -ceq $reasonText) 'foreign receipts keep the Unicode command text'
    Check ((Commit 'req_foreign' 'fp_foreign' 3 (Body 4 400 @('rifle','smg') @{shooter=@{primary='smg'}}) '{"kind":"admin_adjust","credits":20}').ok -eq $true -and (Balance).credits -eq 400) 'foreign asset database accepts a new commit on this platform'
    Check ((Commit 'req_buy' 'fp_buy' 1 $buyBody '{}').code -eq 'DUPLICATE') 'foreign receipts still make the old purchase request idempotent'
} else { $script:notRun++; Write-Output 'NOT RUN foreign databases (no -Foreign folder supplied)' }

foreach($note in $script:notes) { Info $note }
foreach($group in ($script:timings | Group-Object label)) { Info ('one-shot '+$group.Name+': ms='+(($group.Group | ForEach-Object { $_.ms }) -join ',')) }
Write-Output ('STORAGE_SLICE_RESULT passed='+$script:passed+' failed='+$script:failed+' not_run='+$script:notRun)
exit $(if($script:failed -eq 0){0}else{1})
