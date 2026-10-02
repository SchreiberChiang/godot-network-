param(
    [string]$Godot='',
    [Parameter(Mandatory=$true)][ValidateSet(4,8)][int]$Clients,
    [Parameter(Mandatory=$true)][string]$RunRoot
)
# Strict Linux source acceptance, one group per invocation. Parent entry:
# bash tests/support/linux_concurrent_login.sh /absolute/godot /absolute/pwsh all
# Every account must register, succeed in one burst login, see the complete
# identity set in one real ENet/DTLS room, close, and relogin individually.
# Capacity refusals, timeouts and unknown failures all fail; no login retry.
# Same deadlines as test_concurrent_login.ps1. after_ms is observation time,
# not the client's login latency. Fake accounts only, never an exported gate.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$Godot=Rk-Godot $Godot
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('/','\')
if (-not $script:RkPosix -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'Linux and pwsh 7 required.' }
$root=[IO.Path]::GetFullPath($RunRoot).TrimEnd('/')
if (-not (Rk-Inside $root (Join-Path $project 'data'))) { throw 'RunRoot must be inside this source project/data.' }
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Use the parent bash entry to create RunRoot first.' }
$cursor=$root
while ($cursor -ne $project) {
    if ((Get-Item -LiteralPath $cursor -Force).LinkTarget) { throw 'RunRoot passes through a link.' }
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
foreach($pair in @(
    @('HOME','home'),@('XDG_CONFIG_HOME','xdg/config'),@('XDG_CACHE_HOME','xdg/cache'),
    @('XDG_DATA_HOME','xdg/data'),@('XDG_STATE_HOME','xdg/state'),@('XDG_RUNTIME_DIR','xdg/runtime'),
    @('TMPDIR','tmp'),@('TMP','tmp'),@('TEMP','tmp')
)) {
    if ([Environment]::GetEnvironmentVariable($pair[0]) -cne (Join-Path $root $pair[1])) { throw ('Parent must isolate '+$pair[0]+' before starting pwsh.') }
}
$sigLine=[IO.File]::ReadAllLines('/proc/self/status') | Where-Object { $_ -match '^SigIgn:' }
if (-not $sigLine -or (([Convert]::ToUInt64(($sigLine -split '\s+')[-1],16) -band 4096) -eq 0)) { throw 'Parent must ignore SIGPIPE before starting pwsh.' }
$modeProbe=Join-Path $root 'umask.probe'
[IO.File]::WriteAllText($modeProbe,'')
try { if ([int][IO.File]::GetUnixFileMode($modeProbe) -ne 384) { throw 'Parent must set umask 077 before starting pwsh.' } }
finally { Remove-Item -LiteralPath $modeProbe }
if (Test-Path -LiteralPath (Join-Path $root 'games.json')) { throw 'RunRoot was already used; do not rerun in an existing test data folder.' }
$version=@(& $Godot --version)
if ($LASTEXITCODE -ne 0 -or ($version -join '') -notmatch '^4\.7\.2\.') { throw 'Godot 4.7.2 required.' }
$id=[Guid]::NewGuid().ToString('N').Substring(0,8)
$data=Join-Path $root 'data'
Rk-ProtectData $project $root
foreach($folder in 'data','public','logs','clients','build') { New-Item -ItemType Directory -Force -Path (Join-Path $root $folder) | Out-Null }
$index=Join-Path $root 'games.json'
$PanelPort=29191
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $root 'logs/operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$data),('--games='+$index),('--public-client-dir='+(Join-Path $root 'public')),('--operator-log-path='+(Join-Path $root 'logs/operator.log')),('--panel-port='+$PanelPort),'--initial-bind=127.0.0.1','--initial-ports=29196,29197,29210,29225')
$console=Join-Path $root 'logs/console.log'
$operator=$null
$script:RkApiUrl='http://127.0.0.1:'+$PanelPort
$passed=0; $failed=0; $outcomes=@(); $okCount=0
$checks=New-Object Collections.ArrayList
$roomId=''
$roomSeen=0
$again=0
$identities=@{}
# Capture Linux start ticks while the exact child is alive. All OS signalling
# below is preceded by comparison with this identity, never a project-wide kill.
$baseStart=${function:Rk-StartHidden}
function ProcessIdentity([int]$ProcessId) {
    try {
        $stat=[IO.File]::ReadAllText('/proc/'+$ProcessId+'/stat')
        $fields=$stat.Substring($stat.LastIndexOf(')')+2).Split(' ')
        $args=([IO.File]::ReadAllText('/proc/'+$ProcessId+'/cmdline')).Split([char]0)
        return @{start=$fields[19];state=$fields[0];args=$args}
    } catch { return $null }
}
function IsFinalChildIdentity($Identity,[string]$FilePath,$Arguments) {
    # bash -c contains the entire target argv before exec. Membership alone can
    # mistake that wrapper for Godot; require the executable at argv[0].
    return $null -ne $Identity -and @($Identity.args).Count -gt 0 -and
        [string]$Identity.args[0] -ceq $FilePath -and
        @($Arguments | Where-Object { [string]$_ -cnotin $Identity.args }).Count -eq 0
}
function Rk-StartHidden([string]$FilePath,$Arguments,[string]$Stdout,[string]$Stderr) {
    $process=& $script:baseStart $FilePath $Arguments $Stdout $Stderr
    # bash exec retains the PID, but the command line may still show bash briefly.
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do {
        $identity=ProcessIdentity $process.Id
        if (IsFinalChildIdentity $identity $FilePath $Arguments) { break }
        if ($process.HasExited) { throw 'Owned child exited before its identity could be recorded.' }
        Start-Sleep -Milliseconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not (IsFinalChildIdentity $identity $FilePath $Arguments)) { throw 'Owned child identity could not be verified; no signal sent.' }
    $script:identities[$process.Id]=$identity
    return $process
}
function RequireOwned($Process) {
    if ($Process.HasExited) { return }
    $now=ProcessIdentity $Process.Id
    $saved=$script:identities[$Process.Id]
    if ($null -eq $saved -or $null -eq $now -or $now.start -cne $saved.start -or
        ($now.args -join "`0") -cne ($saved.args -join "`0")) { throw 'Owned child identity changed; no signal sent.' }
}
function PortsFree {
    # Check all addresses and IPv4/IPv6, including TCP bound-but-not-listening
    # sockets. UDP any-address reservations also prevent starting this test.
    $tcp=@(29191,29196,29197); $udp=@(29210..29225)
    foreach($table in @('tcp','tcp6','udp','udp6')) {
        foreach($line in [IO.File]::ReadAllLines('/proc/net/'+$table) | Select-Object -Skip 1) {
            $parts=$line.Trim() -split '\s+'
            $port=[Convert]::ToInt32(($parts[1] -split ':')[-1],16)
            # TCP TIME_WAIT has no owning listener and need not block a fresh bind.
            if ($table.StartsWith('tcp') -and $parts[3] -eq '06') { continue }
            if (($table.StartsWith('tcp') -and $port -in $tcp) -or ($table.StartsWith('udp') -and $port -in $udp)) { return $false }
        }
    }
    return $true
}
function SourceProcesses {
    $rows=@()
    foreach($entry in Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction SilentlyContinue) {
        if ($entry.Name -notmatch '^\d+$' -or [int]$entry.Name -eq $PID) { continue }
        $identity=ProcessIdentity ([int]$entry.Name)
        if ($null -eq $identity -or $identity.state -eq 'Z') { continue }
        if (@($identity.args | Where-Object { $_ -ceq $project -or $_.StartsWith($project+'/tools/') -or $_.StartsWith($root+'/build/') }).Count -gt 0) {
            $rows+=@{pid=[int]$entry.Name;start=$identity.start}
        }
    }
    return $rows
}
function Check([bool]$Condition,[string]$Name) {
    [void]$script:checks.Add(@{name=$Name;ok=$Condition})
    if ($Condition) { $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) }
}
function Require([bool]$Condition,[string]$Name) { Check $Condition $Name; if (-not $Condition) { throw $Name } }
function ReadStatus {
    $reply=Rk-Api 'status'
    if (-not $reply.ok -or $null -eq $reply.payload -or
        'players' -notin @($reply.payload.PSObject.Properties.Name) -or
        $null -eq $reply.payload.session_cleanup) { throw 'status did not return a valid player and cleanup snapshot' }
    foreach($key in 'pending','running','failed') {
        if ($key -notin @($reply.payload.session_cleanup.PSObject.Properties.Name) -or
            $null -eq $reply.payload.session_cleanup.$key) { throw 'status did not return complete cleanup counters' }
    }
    return $reply.payload
}
function WaitClean([int]$Seconds=45) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $status=ReadStatus
        if (@($status.players).Count -eq 0 -and [int]$status.session_cleanup.pending -eq 0 -and
            [int]$status.session_cleanup.running -eq 0 -and [int]$status.session_cleanup.failed -eq 0) { return $true }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}
$tracked=New-Object Collections.ArrayList
function TrackClient($Client) {
    $Client.expected_exit=0
    $Client.stopped=$false
    [void]$script:tracked.Add($Client)
    return $Client
}
function StopOwnedClient($Client) {
    if (-not $Client.process.HasExited) {
        RequireOwned $Client.process
        try { [void](Rk-Command $Client 'close' @{} 8) } catch { }
    }
    $clean=$true
    if (-not $Client.process.WaitForExit(5000)) {
        # Check immediately before signalling, including after the close wait.
        RequireOwned $Client.process
        $Client.process.Kill()
        [void]$Client.process.WaitForExit(5000)
        $clean=$false
    }
    Remove-Item -LiteralPath (Join-Path $Client.directory 'bootstrap.json') -ErrorAction SilentlyContinue
    return $clean -and $Client.process.HasExited -and $Client.process.ExitCode -eq 0
}
function StopTrackedClient($Client) {
    if ($Client.stopped) { return }
    RequireOwned $Client.process
    # A rejected initial login deliberately quits(1). Prove it exits by itself
    # before invoking the owned close helper, whose boolean only accepts zero.
    $natural=$true
    if ($Client.expected_exit -eq 1) { $natural=$Client.process.WaitForExit(5000) }
    $clean=StopOwnedClient $Client
    $exited=$Client.process.HasExited
    $exit=if ($exited) { $Client.process.ExitCode } else { 'RUNNING' }
    $valid=if ($Client.expected_exit -eq 1) { $natural -and $exited -and $exit -eq 1 } else { $clean -and $exited -and $exit -eq 0 }
    Check $valid ('client '+$Client.name+' closes with expected exit '+$Client.expected_exit+' (actual='+$exit+')')
    $errorFile=Join-Path $Client.directory 'stderr.log'
    Check ((Test-Path -LiteralPath $errorFile) -and (Get-Item -LiteralPath $errorFile).Length -eq 0) ('client '+$Client.name+' has no error output')
    $Client.stopped=$exited
}
function WaitOnlineSet([string[]]$ExpectedIds,[int]$Seconds=10) {
    $expected=@($ExpectedIds | Sort-Object)
    if (@($expected | Select-Object -Unique).Count -ne $expected.Count -or '' -in $expected) { return $false }
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $status=ReadStatus
        $actual=@($status.players | ForEach-Object { [string]$_.user_id } | Sort-Object)
        if ($actual.Count -eq $expected.Count -and ($actual -join '|') -ceq ($expected -join '|')) { return $true }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}
$burst=New-Object Collections.ArrayList
try {
    Require (PortsFree) 'panel 29191, lobby 29196, control 29197 and UDP 29210-29225 are free before build/start'
    Require (@(SourceProcesses).Count -eq 0) 'this source has no existing engine or helper process (shared res://run stays isolated)'
    Rk-SaveJson (Join-Path $root 'logs/environment.json') @{platform='Linux';powershell=[string]$PSVersionTable.PSVersion;godot=($version -join '');engine=$Godot;source=$project;run_root=$root;ports=@{panel=29191;lobby=29196;control=29197;udp_first=29210;udp_last=29225};require_all=$true;evidence_kind='source';umask='077';sigpipe_ignored=$true}
    & (Rk-PowerShell) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'tools/build_framework.ps1') -IndexPath $index -BuildRoot (Join-Path $root 'build') | Out-Null
    $buildExit=$LASTEXITCODE
    Require ($buildExit -eq 0 -and (Test-Path -LiteralPath $index)) ('isolated game build succeeds (exit='+$buildExit+')')
    Require (PortsFree) 'reserved ports are still free immediately before Operator start'
    $operator=Rk-StartHidden $Godot $arguments $console (Join-Path $root 'logs/stderr.log')
    if (-not (Rk-WaitApi 90)) { throw 'Operator did not answer' }
    $admin=@{username=('cladmin_'+$id.Substring(0,6));password=('Adm!'+[Guid]::NewGuid().ToString('N'))}
    Rk-SaveJson (Join-Path $root 'admin.json') $admin
    $setup=Rk-Api 'setup.create' $admin -Anonymous
    if (-not $setup.ok) { throw ('setup '+$setup.code) }
    $script:RkToken=$setup.payload.token
    Require (Rk-Api 'server.start').ok 'managed host starts'
    Require ((Rk-WaitHost 'RUNNING' 90).host.state -eq 'RUNNING') 'managed host reaches RUNNING'
    $games=Rk-ReadJson $index
    $connection=Rk-Connection (Join-Path $root 'public')
    $invitation=Rk-Api 'invite.create' @{uses=$Clients;expires_hours=1;reason='concurrent login diagnostic'}
    Require ($invitation.ok -and $invitation.payload.invite_code) 'isolated invitation is created'
    $invite=$invitation.payload.invite_code
    $accounts=@()
    Require (WaitClean) 'no player session or cleanup is pending before registrations'
    for($i=0;$i -lt $Clients;$i++) {
        $account=@{username=('clp'+$i+'_'+$id.Substring(0,5));password=('Load!'+[Guid]::NewGuid().ToString('N'))}
        $client=TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('register-'+$i) 'shooter' $connection $games.shooter.manifest @{username=$account.username;password=$account.password;display_name=('P'+$i);invite_code=$invite;register=$true})
        $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
        Require ($null -ne $ready -and -not $client.process.HasExited -and [string]$ready.user_id -ne '') ('registration '+$i+' reaches the lobby with a live player identity')
        $account.user_id=[string]$ready.user_id
        Require ($null -ne $ready.registration -and $ready.registration.ok) ('registration '+$i+' explicitly succeeded')
        StopTrackedClient $client
        Require (WaitClean) ('registration '+$i+' leaves no online session or pending, running or failed cleanup')
        $accounts+=$account
    }
    Check $true ('registered '+$Clients+' accounts one after another')
    Require (WaitClean) 'all registration cleanup is drained before the burst'
    # All at once: start every client, then wait for each.
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $Clients;$i++) { [void]$burst.Add((TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('burst-'+$i) 'shooter' $connection $games.shooter.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false}))) }
    $outcomes=@()
    $onlineIds=@()
    for($i=0;$i -lt $Clients;$i++) {
        $report=Rk-WaitReport $burst[$i] {param($r) ($r.phase -eq 'LOBBY' -and $r.ok) -or $r.phase -eq 'FAILED'} 120
        $code=if ($null -eq $report) { 'NO_REPORT' } elseif ($report.ok) { 'OK' } else { [string]$report.code }
        $outcomes+=$code
        if ($code -eq 'OK') {
            Check (-not $burst[$i].process.HasExited -and [string]$report.user_id -ceq $accounts[$i].user_id) ('burst client '+$i+' is alive with its registered identity')
            $onlineIds+=[string]$report.user_id
        } elseif ($null -ne $report -and $report.phase -eq 'FAILED') { $burst[$i].expected_exit=1 }
        Write-Output ('INFO burst client '+$i+' outcome='+$code+' after_ms='+$clock.ElapsedMilliseconds)
    }
    $okCount=@($outcomes | Where-Object { $_ -eq 'OK' }).Count
    $refusals=@(Select-String -LiteralPath $console -Pattern 'OPERATOR_STORAGE_REFUSED' -ErrorAction SilentlyContinue | ForEach-Object { ($_.Line -replace ' t=\d+','') })
    Write-Output ('INFO simultaneous logins ok='+$okCount+' of '+$Clients+' codes='+(($outcomes | Group-Object | ForEach-Object { $_.Name+':'+$_.Count }) -join ','))
    Write-Output ('INFO operator storage refusals during the burst: '+$refusals.Count)
    $refusals | Group-Object | ForEach-Object { Write-Output ('INFO   '+$_.Count+' x '+$_.Name) }
    Check (@($outcomes | Where-Object { $_ -ne 'OK' }).Count -eq 0) 'every simultaneous login succeeded (capacity/storage/unknown/missing outcomes fail)'
    Check ($okCount -eq $Clients) ('strict acceptance: all burst logins succeed: '+$okCount+' of '+$Clients)
    Check (WaitOnlineSet $onlineIds) ('backend online player set matches all '+$okCount+' successful burst clients')
    $liveSuccess=0
    for($i=0;$i -lt $Clients;$i++) { if ($outcomes[$i] -eq 'OK' -and -not $burst[$i].process.HasExited) { $liveSuccess++ } }
    Check ($liveSuccess -eq $okCount) 'all successful clients remain alive together after the reports and backend snapshot agree'
    if ($okCount -eq $Clients -and $liveSuccess -eq $Clients) {
        $created=Rk-Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=$Clients}
        Require ($created.ok -and [string]$created.payload.room_id -ne '') ('one shooter room with capacity '+$Clients+' is created')
        $roomId=[string]$created.payload.room_id
        $row=Rk-WaitRoom $roomId 'READY' 60
        Require ($null -ne $row -and $row.state -eq 'READY') 'same room is READY after binding its UDP port'
        for($i=0;$i -lt $Clients;$i++) {
            $joined=Rk-Command $burst[$i] 'join_sdk' @{room_id=$roomId} 65
            Require ($null -ne $joined -and $joined.ok) ('burst client '+$i+' real ENet/DTLS admission succeeds')
        }
        $expected=@($accounts | ForEach-Object { [string]$_.user_id } | Sort-Object)
        Require (@($expected | Select-Object -Unique).Count -eq $Clients) 'all registered player identities are distinct'
        for($i=0;$i -lt $Clients;$i++) {
            $seen=Rk-WaitReport $burst[$i] {
                param($r)
                $actual=@($r.world.players | ForEach-Object { [string]$_.user_id } | Sort-Object)
                $r.ok -and $r.phase -eq 'IN_ROOM' -and $r.user_id -ceq $accounts[$i].user_id -and
                    $actual.Count -eq $Clients -and ($actual -join '|') -ceq ($expected -join '|')
            } 90
            Check ($null -ne $seen -and -not $burst[$i].process.HasExited) ('burst client '+$i+' sees every registered identity in the same live room')
            if ($null -ne $seen) {
                $roomSeen++
                Rk-SaveJson (Join-Path $root ('logs/room-seen-'+$i+'.json')) @{client=$i;room_id=$roomId;phase=$seen.phase;user_id=$seen.user_id;seen_user_ids=@($seen.world.players | ForEach-Object { [string]$_.user_id });tick=$seen.world.tick}
            }
        }
        Check (WaitOnlineSet $expected) 'backend still contains exactly the full group after all same-room snapshots'
        Check (@($burst | Where-Object { -not $_.process.HasExited -and (Rk-Report $_).phase -eq 'IN_ROOM' }).Count -eq $Clients) 'the entire group remains alive in the same room after mutual visibility'
        foreach($client in $burst) {
            $left=Rk-Command $client 'leave' @{} 20
            Check ($null -ne $left -and $left.ok) ('client '+$client.name+' leaves the room back to the lobby')
        }
    } else { Check $false 'same-room full-group mutual visibility was not run because strict burst login failed' }
    foreach($client in $burst) { StopTrackedClient $client }
    $burst.Clear()
    Require (WaitClean) 'after the burst closes: nobody online and no pending, running or failed cleanup'
    Rk-SaveJson (Join-Path $root 'logs/after-burst-cleanup.json') (ReadStatus)
    if ($roomId) {
        Require (Rk-Api 'room.stop' @{room_id=$roomId;reason='strict Linux concurrency cleanup'}).ok 'same-room stop request succeeds'
        $stopped=Rk-WaitRoom $roomId 'STOPPED' 60
        Require ($null -ne $stopped -and $stopped.state -eq 'STOPPED') 'same-room exits and releases its resources'
        $roomId=''
    }
    $again=0
    for($i=0;$i -lt $Clients;$i++) {
        $client=TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('after-'+$i) 'shooter' $connection $games.shooter.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false})
        $report=Rk-WaitReport $client {param($r) ($r.phase -eq 'LOBBY' -and $r.ok) -or $r.phase -eq 'FAILED'} 90
        $valid=$null -ne $report -and $report.ok -and -not $client.process.HasExited -and [string]$report.user_id -ceq $accounts[$i].user_id
        Check $valid ('relogin '+$i+' succeeds once with the original registered identity')
        if ($valid) { $again++ } else { Write-Output ('INFO account '+$i+' afterwards: '+$(if ($null -eq $report) { 'NO_REPORT' } else { $report.code })); if($null -ne $report -and $report.phase -eq 'FAILED'){$client.expected_exit=1} }
        StopTrackedClient $client
        Require (WaitClean) ('relogin '+$i+' leaves no online session or cleanup')
    }
    Check ($again -eq $Clients) ('afterwards every account logs in again (no session left behind): '+$again+' of '+$Clients)
    Require (WaitClean) 'final relogin batch is completely drained'
    Rk-SaveJson (Join-Path $root 'logs/final-cleanup.json') (ReadStatus)
    $cleanup=@(Select-String -LiteralPath $console -Pattern 'SESSION_CLEANUP' -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Line -match 'event=(\w+)') { $Matches[1] } })
    Write-Output ('INFO session clean-up events: '+(($cleanup | Group-Object | ForEach-Object { $_.Name+':'+$_.Count }) -join ','))
    $text=Get-Content -Raw -LiteralPath $console
    Check (-not $text.Contains($admin.password) -and @($accounts | Where-Object { $text.Contains($_.password) }).Count -eq 0) 'no password in the Operator output'
} catch {
    $failed++
    Write-Output ('LINUX_CONCURRENT_LOGIN_ERROR '+$_.Exception.Message)
} finally {
    foreach($client in $tracked) {
        if (-not $client.stopped) {
            try { StopTrackedClient $client } catch { $failed++; Write-Output ('FAIL cleanup of client '+$client.name+' could not be confirmed') }
        }
    }
    try {
        if ($null -ne $operator -and -not $operator.HasExited) {
            RequireOwned $operator
            [IO.File]::WriteAllText((Join-Path $data 'operator-stop.request'),'stop')
            if (-not $operator.WaitForExit(120000)) {
                RequireOwned $operator
                $operator.Kill()
                [void]$operator.WaitForExit(10000)
                Check $false 'Operator did not stop on request (only the verified owned child was ended)'
            }
        }
        Check ($null -ne $operator -and $operator.HasExited -and $operator.ExitCode -eq 0) 'isolated Operator exits cleanly'
    } catch { Check $false 'Operator cleanup could not be confirmed; no unverified process was signalled' }
    Remove-Item -LiteralPath (Join-Path $root 'admin.json') -ErrorAction SilentlyContinue
    try {
        $errorFile=Join-Path $root 'logs/stderr.log'
        Check ((Test-Path -LiteralPath $errorFile) -and (Get-Item -LiteralPath $errorFile).Length -eq 0) 'isolated Operator has no error output'
        $errors=@(Get-ChildItem -LiteralPath (Join-Path $root 'logs'),(Join-Path $root 'clients'),(Join-Path $root 'data') -File -Recurse -Filter '*.log' |
            Select-String -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:|ObjectDB instances leaked|resources still in use' |
            ForEach-Object { @{file=$_.Path;line=$_.LineNumber} })
        Rk-SaveJson (Join-Path $root 'logs/error-lines.json') $errors
        Check ($errors.Count -eq 0) 'source Operator, host, room and client logs have no script/resource errors'
        $residual=@(SourceProcesses)
        Rk-SaveJson (Join-Path $root 'logs/residual-processes.json') $residual
        Check ($residual.Count -eq 0) 'no source engine, room or storage-helper process remains'
        Check (PortsFree) 'panel, lobby, control and all reserved UDP ports are free after shutdown'
    } catch { Check $false 'final logs, process and port checks could not be confirmed' }
    try {
        Rk-SaveJson (Join-Path $root 'logs/result.json') @{passed=$passed;failed=$failed;clients=$Clients;successful=$okCount;outcomes=$outcomes;require_all=$true;same_room_seen=$roomSeen;relogged=$again;checks=@($checks);evidence_kind='source';exported_gate='NOTRUN'}
    } catch { $failed++; Write-Output 'FAIL could not save the final result file' }
}
Write-Output ('LINUX_CONCURRENT_LOGIN_RESULT passed='+$passed+' failed='+$failed+' clients='+$Clients+' same_room_seen='+$roomSeen+' evidence='+$root)
if ($failed -gt 0) { exit 1 }
exit 0
