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
& (Rk-PowerShell) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'tools/build_framework.ps1') -IndexPath $index -BuildRoot (Join-Path $root 'build') | Out-Null
$lobby=$PanelPort+5
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $root 'logs/operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$data),('--games='+$index),('--public-client-dir='+(Join-Path $root 'public')),('--operator-log-path='+(Join-Path $root 'logs/operator.log')),('--panel-port='+$PanelPort),'--initial-bind=127.0.0.1',('--initial-ports='+$lobby+','+($lobby+1)+','+($lobby+10)+','+($lobby+25)))
$console=Join-Path $root 'logs/console.log'
$operator=$null
$script:RkApiUrl='http://127.0.0.1:'+$PanelPort
$passed=0; $failed=0; $outcomes=@(); $okCount=0
function Check([bool]$Condition,[string]$Name) { if ($Condition) { $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) } }
$burst=New-Object Collections.ArrayList
try {
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
    $invite=(Rk-Api 'invite.create' @{uses=$Clients;expires_hours=1;reason='concurrent login diagnostic'}).payload.invite_code
    $accounts=@()
    for($i=0;$i -lt $Clients;$i++) {
        $account=@{username=('clp'+$i+'_'+$id.Substring(0,5));password=('Load!'+[Guid]::NewGuid().ToString('N'))}
        $client=Rk-StartClient $Godot $project (Join-Path $root 'clients') ('register-'+$i) 'turns' $connection $games.turns.manifest @{username=$account.username;password=$account.password;display_name=('P'+$i);invite_code=$invite;register=$true}
        $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
        [void](Rk-StopClient $client)
        if ($null -eq $ready) { throw ('registration '+$i) }
        $accounts+=$account
    }
    Check $true ('registered '+$Clients+' accounts one after another')
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    while (@((Rk-Api 'status').payload.players).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
    # All at once: start every client, then wait for each.
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $Clients;$i++) { [void]$burst.Add((Rk-StartClient $Godot $project (Join-Path $root 'clients') ('burst-'+$i) 'turns' $connection $games.turns.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false})) }
    $outcomes=@()
    for($i=0;$i -lt $Clients;$i++) {
        $report=Rk-WaitReport $burst[$i] {param($r) ($r.phase -eq 'LOBBY' -and $r.ok) -or $r.phase -eq 'FAILED'} 120
        $code=if ($null -eq $report) { 'NO_REPORT' } elseif ($report.ok) { 'OK' } else { [string]$report.code }
        $outcomes+=$code
        Write-Output ('INFO burst client '+$i+' outcome='+$code+' after_ms='+$clock.ElapsedMilliseconds)
    }
    $okCount=@($outcomes | Where-Object { $_ -eq 'OK' }).Count
    $refusals=@(Select-String -LiteralPath $console -Pattern 'OPERATOR_STORAGE_REFUSED' -ErrorAction SilentlyContinue | ForEach-Object { ($_.Line -replace ' t=\d+','') })
    Write-Output ('INFO simultaneous logins ok='+$okCount+' of '+$Clients+' codes='+(($outcomes | Group-Object | ForEach-Object { $_.Name+':'+$_.Count }) -join ','))
    Write-Output ('INFO operator storage refusals during the burst: '+$refusals.Count)
    $refusals | Group-Object | ForEach-Object { Write-Output ('INFO   '+$_.Count+' x '+$_.Name) }
    Check (@($outcomes | Where-Object { $_ -notin @('OK','STORAGE_UNAVAILABLE','RATE_LIMITED') }).Count -eq 0) 'every simultaneous login either succeeded or was refused with a capacity/storage code (no other failure)'
    if($RequireAll){Check ($okCount -eq $Clients) ('strict acceptance: all burst logins succeed: '+$okCount+' of '+$Clients)}
    foreach($client in $burst) { [void](Rk-StopClient $client) }
    $burst.Clear()
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do { $status=(Rk-Api 'status').payload; if (@($status.players).Count -eq 0 -and [int]$status.session_cleanup.pending -eq 0) { break }; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline)
    Check (@($status.players).Count -eq 0 -and [int]$status.session_cleanup.pending -eq 0 -and [int]$status.session_cleanup.failed -eq 0) ('after the clients closed: nobody listed online, no clean-up pending or failed (failed='+$status.session_cleanup.failed+')')
    $again=0
    for($i=0;$i -lt $Clients;$i++) {
        $client=Rk-StartClient $Godot $project (Join-Path $root 'clients') ('after-'+$i) 'turns' $connection $games.turns.manifest @{username=$accounts[$i].username;password=$accounts[$i].password;register=$false}
        $report=Rk-WaitReport $client {param($r) ($r.phase -eq 'LOBBY' -and $r.ok) -or $r.phase -eq 'FAILED'} 90
        if ($null -ne $report -and $report.ok) { $again++ } else { Write-Output ('INFO account '+$i+' afterwards: '+$(if ($null -eq $report) { 'NO_REPORT' } else { $report.code })) }
        [void](Rk-StopClient $client)
    }
    Check ($again -eq $Clients) ('afterwards every account logs in again (no session left behind): '+$again+' of '+$Clients)
    $cleanup=@(Select-String -LiteralPath $console -Pattern 'SESSION_CLEANUP' -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Line -match 'event=(\w+)') { $Matches[1] } })
    Write-Output ('INFO session clean-up events: '+(($cleanup | Group-Object | ForEach-Object { $_.Name+':'+$_.Count }) -join ','))
    $text=Get-Content -Raw -LiteralPath $console
    Check (-not $text.Contains($admin.password) -and @($accounts | Where-Object { $text.Contains($_.password) }).Count -eq 0) 'no password in the Operator output'
} catch {
    $failed++
    Write-Output ('CONCURRENT_LOGIN_ERROR '+$_.Exception.Message)
} finally {
    foreach($client in $burst) { try { [void](Rk-StopClient $client) } catch { } }
    if ($null -ne $operator -and -not $operator.HasExited) {
        [IO.File]::WriteAllText((Join-Path $data 'operator-stop.request'),'stop')
        if (-not $operator.WaitForExit(120000)) { $operator.Kill(); $failed++; Write-Output 'FAIL Operator did not stop on request' }
    }
    Remove-Item -LiteralPath (Join-Path $root 'admin.json') -ErrorAction SilentlyContinue
    if($null -ne $operator -and $operator.HasExited){Check ($operator.ExitCode -eq 0) 'isolated Operator exits cleanly'}
    if(Test-Path -LiteralPath (Join-Path $root 'logs/stderr.log')){Check ((Get-Item -LiteralPath (Join-Path $root 'logs/stderr.log')).Length -eq 0) 'isolated Operator has no error output'}
    Rk-SaveJson (Join-Path $root 'logs/result.json') @{passed=$passed;failed=$failed;clients=$Clients;successful=$okCount;outcomes=$outcomes;require_all=[bool]$RequireAll}
}
Write-Output ('CONCURRENT_LOGIN_RESULT passed='+$passed+' failed='+$failed+' clients='+$Clients+' evidence='+$root)
if ($failed -gt 0) { exit 1 }
exit 0
