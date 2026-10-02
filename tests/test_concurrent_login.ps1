param([string]$Godot='',[ValidateRange(2,8)][int]$Clients=6,[ValidateRange(1024,65495)][int]$PanelPort=28695,[switch]$RequireAll)
# Diagnostic: $Clients real headless clients are started in a burst against an
# isolated Operator (data/concurrent-login-<id>, its own ports, index copy and
# public folder). Records each login's outcome, the Operator's storage refusals
# and session clean-up, then checks that no session is left behind: after all
# clients closed, every account logs in once more, one after another. A refused
# login is never repeated blindly. Expected refusals (capacity) are reported, not
# hidden; they do not mean every simultaneous login passed. -RequireAll makes
# any refused/missing burst login fail the run. after_ms is the time when the
# driver observes a report, not a measurement of that client's login latency.
# Fake accounts only.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$Godot=Rk-Godot $Godot
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('/','\')
$id=[Guid]::NewGuid().ToString('N').Substring(0,8)
$root=Join-Path (Join-Path $project 'data') ('concurrent-login-'+$id)
$data=Join-Path $root 'data'
Rk-ProtectData $project $root
foreach($folder in 'data','public','logs','clients','build') { New-Item -ItemType Directory -Force -Path (Join-Path $root $folder) | Out-Null }
$index=Join-Path $root 'games.json'
$lobby=$PanelPort+5
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $root 'logs/operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$data),('--games='+$index),('--public-client-dir='+(Join-Path $root 'public')),('--operator-log-path='+(Join-Path $root 'logs/operator.log')),('--panel-port='+$PanelPort),'--initial-bind=127.0.0.1',('--initial-ports='+$lobby+','+($lobby+1)+','+($lobby+10)+','+($lobby+25)))
$console=Join-Path $root 'logs/console.log'
$operator=$null
$script:RkApiUrl='http://127.0.0.1:'+$PanelPort
$passed=0; $failed=0; $outcomes=@(); $okCount=0
function Check([bool]$Condition,[string]$Name) { if ($Condition) { $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) } }
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
function StopTrackedClient($Client) {
    if ($Client.stopped) { return }
    # A rejected initial login deliberately quits(1). Prove it exits by itself
    # before invoking the common close helper, whose boolean only accepts zero.
    $natural=$true
    if ($Client.expected_exit -eq 1) { $natural=$Client.process.WaitForExit(5000) }
    $clean=Rk-StopClient $Client
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
    & (Rk-PowerShell) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'tools/build_framework.ps1') -IndexPath $index -BuildRoot (Join-Path $root 'build') | Out-Null
    $buildExit=$LASTEXITCODE
    Require ($buildExit -eq 0 -and (Test-Path -LiteralPath $index)) ('isolated game build succeeds (exit='+$buildExit+')')
    $operator=Rk-StartHidden $Godot $arguments $console (Join-Path $root 'logs/stderr.log')
    if (-not (Rk-WaitApi 90)) { throw 'Operator did not answer' }
    $admin=@{username=('cladmin_'+$id.Substring(0,6));password=('Adm!'+[Guid]::NewGuid().ToString('N'))}
    Rk-SaveJson (Join-Path $root 'admin.json') $admin
    $setup=Rk-Api 'setup.create' $admin -Anonymous
    if (-not $setup.ok) { throw ('setup '+$setup.code) }
    $script:RkToken=$setup.payload.token
    if (-not (Rk-Api 'server.start').ok) { throw 'host start' }
    $games=Rk-ReadJson $index
    $connection=Rk-Connection (Join-Path $root 'public')
    $invitation=Rk-Api 'invite.create' @{uses=$Clients;expires_hours=1;reason='concurrent login diagnostic'}
    Require ($invitation.ok -and $invitation.payload.invite_code) 'isolated invitation is created'
    $invite=$invitation.payload.invite_code
    $accounts=@()
    Require (WaitClean) 'no player session or cleanup is pending before registrations'
    for($i=0;$i -lt $Clients;$i++) {
        $account=@{username=('clp'+$i+'_'+$id.Substring(0,5));password=('Load!'+[Guid]::NewGuid().ToString('N'))}
        $client=TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('register-'+$i) 'turns' $connection $games.turns.manifest @{username=$account.username;password=$account.password;display_name=('P'+$i);invite_code=$invite;register=$true})
        $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
        Require ($null -ne $ready -and -not $client.process.HasExited -and [string]$ready.user_id -ne '') ('registration '+$i+' reaches the lobby with a live player identity')
        $account.user_id=[string]$ready.user_id
        StopTrackedClient $client
        Require (WaitClean) ('registration '+$i+' leaves no online session or pending, running or failed cleanup')
        $accounts+=$account
    }
    Check $true ('registered '+$Clients+' accounts one after another')
    Require (WaitClean) 'all registration cleanup is drained before the burst'
    # All at once: start every client, then wait for each.
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $Clients;$i++) { [void]$burst.Add((TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('burst-'+$i) 'turns' $connection $games.turns.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false}))) }
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
    Check (@($outcomes | Where-Object { $_ -notin @('OK','STORAGE_UNAVAILABLE','RATE_LIMITED') }).Count -eq 0) 'every simultaneous login either succeeded or was refused with a capacity/storage code (no other failure)'
    if($RequireAll){Check ($okCount -eq $Clients) ('strict acceptance: all burst logins succeed: '+$okCount+' of '+$Clients)}
    Check (WaitOnlineSet $onlineIds) ('backend online player set matches all '+$okCount+' successful burst clients')
    $liveSuccess=0
    for($i=0;$i -lt $Clients;$i++) { if ($outcomes[$i] -eq 'OK' -and -not $burst[$i].process.HasExited) { $liveSuccess++ } }
    Check ($liveSuccess -eq $okCount) 'all successful clients remain alive together after the reports and backend snapshot agree'
    foreach($client in $burst) { StopTrackedClient $client }
    $burst.Clear()
    Require (WaitClean) 'after the burst closes: nobody online and no pending, running or failed cleanup'
    $again=0
    for($i=0;$i -lt $Clients;$i++) {
        $client=TrackClient (Rk-StartClient $Godot $project (Join-Path $root 'clients') ('after-'+$i) 'turns' $connection $games.turns.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false})
        $report=Rk-WaitReport $client {param($r) ($r.phase -eq 'LOBBY' -and $r.ok) -or $r.phase -eq 'FAILED'} 90
        if ($null -ne $report -and $report.ok -and -not $client.process.HasExited -and [string]$report.user_id -ceq $accounts[$i].user_id) { $again++ } else { Write-Output ('INFO account '+$i+' afterwards: '+$(if ($null -eq $report) { 'NO_REPORT' } else { $report.code })); if($null -ne $report -and $report.phase -eq 'FAILED'){$client.expected_exit=1} }
        StopTrackedClient $client
        Require (WaitClean) ('relogin '+$i+' leaves no online session or cleanup')
    }
    Check ($again -eq $Clients) ('afterwards every account logs in again (no session left behind): '+$again+' of '+$Clients)
    Require (WaitClean) 'final relogin batch is completely drained'
    $cleanup=@(Select-String -LiteralPath $console -Pattern 'SESSION_CLEANUP' -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Line -match 'event=(\w+)') { $Matches[1] } })
    Write-Output ('INFO session clean-up events: '+(($cleanup | Group-Object | ForEach-Object { $_.Name+':'+$_.Count }) -join ','))
    $text=Get-Content -Raw -LiteralPath $console
    Check (-not $text.Contains($admin.password) -and @($accounts | Where-Object { $text.Contains($_.password) }).Count -eq 0) 'no password in the Operator output'
} catch {
    $failed++
    Write-Output ('CONCURRENT_LOGIN_ERROR '+$_.Exception.Message)
} finally {
    foreach($client in $tracked) {
        if (-not $client.stopped) {
            try { StopTrackedClient $client } catch { $failed++; Write-Output ('FAIL cleanup of client '+$client.name+' could not be confirmed') }
        }
    }
    if ($null -ne $operator -and -not $operator.HasExited) {
        [IO.File]::WriteAllText((Join-Path $data 'operator-stop.request'),'stop')
        if (-not $operator.WaitForExit(120000)) { $operator.Kill(); [void]$operator.WaitForExit(10000); $failed++; Write-Output 'FAIL Operator did not stop on request' }
    }
    Remove-Item -LiteralPath (Join-Path $root 'admin.json') -ErrorAction SilentlyContinue
    if($null -ne $operator -and $operator.HasExited){Check ($operator.ExitCode -eq 0) 'isolated Operator exits cleanly'}
    if(Test-Path -LiteralPath (Join-Path $root 'logs/stderr.log')){Check ((Get-Item -LiteralPath (Join-Path $root 'logs/stderr.log')).Length -eq 0) 'isolated Operator has no error output'}
    Rk-SaveJson (Join-Path $root 'logs/result.json') @{passed=$passed;failed=$failed;clients=$Clients;successful=$okCount;outcomes=$outcomes;require_all=[bool]$RequireAll}
}
Write-Output ('CONCURRENT_LOGIN_RESULT passed='+$passed+' failed='+$failed+' clients='+$Clients+' evidence='+$root)
if ($failed -gt 0) { exit 1 }
exit 0
