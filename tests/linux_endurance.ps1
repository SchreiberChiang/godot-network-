param(
    [Parameter(Mandatory=$true)][string]$Instance,
    [Parameter(Mandatory=$true)][int]$PanelPort,
    [int]$Minutes=60,
    [string]$Godot=''
)
# Low-load endurance of one running instance (work package 4): for $Minutes,
# cycles of: open a room, 2/4/6/8 real headless clients log in one after another
# (login_ms is the slowest single start-to-lobby time), do asset
# operations in the lobby (select with a new operation id, a repeated purchase
# receipt), join the room, play a few turns, leave and close; the room is stopped.
# Every cycle records latencies (room READY, login+join, asset operation, room
# stop, panel status) and memory (Operator, host, system). The administrator of
# tests/linux_l3_acceptance.ps1 is reused; the 8 fake player accounts are created
# here. Each cycle is labelled light (<70 % system CPU), high (70-90 %) or
# saturated (>=90 %) from the Operator's CPU sample taken after it; saturated
# cycles are not low load. Prints the first (baseline), last and worst values. It measures this run
# only; it is not a capacity or long-term statement.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$Godot=Rk-Godot $Godot
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('/','\')
$Instance=[IO.Path]::GetFullPath($Instance).TrimEnd('/','\')
if (-not (Rk-Inside $Instance (Join-Path $project 'data'))) { throw 'Instance outside the project data folder.' }
$data=Join-Path $Instance 'data'
$state=Join-Path $Instance 'acceptance'
$evidence=Join-Path $state ('endurance-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$script:RkApiUrl='http://127.0.0.1:'+$PanelPort
$games=Rk-ReadJson (Join-Path $Instance 'games.json')
$connection=Rk-Connection (Join-Path $Instance 'public')
$rows=Join-Path $evidence 'cycles.jsonl'
$failures=New-Object Collections.ArrayList
function Note([string]$Text) { [void]$failures.Add($Text); Write-Output ('CYCLE_FAILURE '+$Text) }
function Rss([int]$ProcessId) {
    if ($ProcessId -le 0) { return 0 }
    try { foreach($line in [IO.File]::ReadAllLines('/proc/'+$ProcessId+'/status')) { if ($line -match '^VmRSS:\s+(\d+)\s+kB') { return [long]$Matches[1]*1024 } } } catch { }
    return 0
}
function ProjectProcessCount {
    $count=0
    foreach($entry in Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction SilentlyContinue) {
        if ($entry.Name -notmatch '^[0-9]+$' -or [int]$entry.Name -eq $PID) { continue }
        try { if (([IO.File]::ReadAllText('/proc/'+$entry.Name+'/cmdline')).Replace([char]0,' ').Contains($project)) { $count++ } } catch { }
    }
    return $count
}
function Stats($Values) {
    $sorted=@($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return @{count=0} }
    return @{count=$sorted.Count;min=$sorted[0];median=$sorted[[int][Math]::Floor(($sorted.Count-1)/2)];p95=$sorted[[int][Math]::Floor(($sorted.Count-1)*0.95)];max=$sorted[-1]}
}

if (-not (Rk-WaitApi 90)) { throw 'The Operator panel does not answer.' }
if (-not (Rk-AdminLogin (Join-Path $state 'admin.json'))) { throw 'Administrator login failed.' }
$start=Rk-Api 'server.start'
if (-not $start.ok) { throw ('Host start failed: '+$start.code) }
$operatorPid=[int](Rk-ReadJson (Join-Path $data 'operator.json')).pid
# Eight fake players: registered once, funded, each owns the jade theme.
$invite=(Rk-Api 'invite.create' @{uses=8;expires_hours=2;reason='endurance players'}).payload.invite_code
$accounts=@()
for($index=0; $index -lt 8; $index++) {
    $account=@{username=('l3load'+$index+'_'+[Guid]::NewGuid().ToString('N').Substring(0,5));password=('Load!'+[Guid]::NewGuid().ToString('N'));display_name=('Load'+$index)}
    $client=Rk-StartClient $Godot $project $evidence ('setup-'+$index) 'turns' $connection $games.turns.manifest @{username=$account.username;password=$account.password;display_name=$account.display_name;invite_code=$invite;register=$true}
    $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
    if ($null -eq $ready) { [void](Rk-StopClient $client); throw ('Player '+$index+' could not register.') }
    $account.user_id=$ready.user_id
    [void](Rk-Api 'asset.adjust' @{user_id=$account.user_id;game_id='turns';coins_delta=500;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='endurance funding'})
    $account.purchase_key='jade_'+[Guid]::NewGuid().ToString('N')
    $bought=Rk-Command $client 'purchase' @{item_id='jade';operation_id=$account.purchase_key}
    if ($null -eq $bought -or -not $bought.ok) { [void](Rk-StopClient $client); throw ('Player '+$index+' could not buy the theme.') }
    [void](Rk-StopClient $client)
    $accounts+=$account
}
Rk-SaveJson (Join-Path $state 'endurance-accounts.json') $accounts
Write-Output ('ENDURANCE_START minutes='+$Minutes+' players=8 operator_pid='+$operatorPid)
$deadline=[DateTime]::UtcNow.AddMinutes($Minutes)
$sizes=@(2,4,6,8)
$cycle=0
$samples=@()
while ([DateTime]::UtcNow -lt $deadline) {
    $size=$sizes[$cycle % $sizes.Count]
    $row=[ordered]@{cycle=$cycle;clients=$size;started=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    $clients=@()
    $room=$null
    try {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $room=Rk-Api 'room.create' @{game_id='turns';mode='sandbox';map='table';capacity=8}
        if (-not $room.ok) { throw ('room.create '+$room.code) }
        $ready=Rk-WaitRoom $room.payload.room_id 'READY' 60
        if ($null -eq $ready -or $ready.state -ne 'READY') { throw 'room not READY' }
        $row.room_ready_ms=$clock.ElapsedMilliseconds
        $login=@(); $operations=@(); $join=@()
        # Low load: players arrive one after another (each login finishes before the
        # next client starts). A burst of simultaneous logins is not part of this run.
        for($index=0; $index -lt $size; $index++) {
            $account=$accounts[$index]
            $clock.Restart()
            $clients+=Rk-StartClient $Godot $project $evidence ('c'+$cycle+'-'+$index) 'turns' $connection $games.turns.manifest @{username=$account.username;password=$account.password;register=$false}
            $report=Rk-WaitReport $clients[$index] {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
            if ($null -eq $report) { throw ('client '+$index+' login '+(Rk-Report $clients[$index]).code) }
            $login+=$clock.ElapsedMilliseconds
        }
        for($index=0; $index -lt $size; $index++) {
            $theme=if (($cycle+$index) % 2) { 'jade' } else { 'classic' }
            $selected=Rk-Command $clients[$index] 'select' @{slot='theme';item_id=$theme;operation_id=('s'+$cycle+'_'+$index+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8))}
            if ($null -eq $selected -or -not $selected.ok) { throw ('client '+$index+' select '+$selected.code) }
            $operations+=$selected.elapsed_ms
            $receipt=Rk-Command $clients[$index] 'purchase' @{item_id='jade';operation_id=$accounts[$index].purchase_key}
            if ($null -eq $receipt -or -not $receipt.ok) { throw ('client '+$index+' purchase receipt '+$receipt.code) }
            $operations+=$receipt.elapsed_ms
        }
        for($index=0; $index -lt $size; $index++) {
            $joined=Rk-Command $clients[$index] 'join' @{room_id=$room.payload.room_id}
            if ($null -eq $joined -or -not $joined.ok) { throw ('client '+$index+' join '+$joined.code) }
            $join+=$joined.elapsed_ms
        }
        for($move=0; $move -lt 4; $move++) {
            $world=(Rk-Report $clients[0]).world
            $active=@($clients | Where-Object { (Rk-Report $_).user_id -eq $world.active_user })[0]
            if ($null -ne $active) { [void](Rk-Command $active 'choose' @{take=1} 10) }
            Start-Sleep -Milliseconds 150
        }
        foreach($client in $clients) { [void](Rk-Command $client 'leave' @{} 20) }
        foreach($client in $clients) { if (-not (Rk-StopClient $client)) { Note ('cycle '+$cycle+' a client did not close by itself') } }
        $clients=@()
        $clock.Restart()
        $stopped=Rk-Api 'room.stop' @{room_id=$room.payload.room_id;reason='endurance cycle'}
        if (-not $stopped.ok) { throw ('room.stop refused '+$stopped.code) }
        $gone=$false
        $until=[DateTime]::UtcNow.AddSeconds(30)
        # Only a successful status reply counts: a failed one has no room list at all.
        do { $reply=Rk-Api 'status'; if ($reply.ok) { $left=@($reply.payload.rooms | Where-Object { $_.room_id -eq $room.payload.room_id -and $_.state -ne 'STOPPED' }); if ($left.Count -eq 0) { $gone=$true; break } } else { $row.status_failures=[int]$row.status_failures+1; $row.status_code=$reply.code }; Start-Sleep -Milliseconds 300 } while ([DateTime]::UtcNow -lt $until)
        if (-not $gone) { throw 'room did not stop' }
        $room=$null
        $row.room_stop_ms=$clock.ElapsedMilliseconds
        $until=[DateTime]::UtcNow.AddSeconds(20)
        do { $reply=Rk-Api 'status'; $online=if ($reply.ok) { @($reply.payload.players) } else { @('unknown') }; if ($online.Count -eq 0) { break }; Start-Sleep -Milliseconds 300 } while ([DateTime]::UtcNow -lt $until)
        if ($online.Count -gt 0) { throw ('players still listed online 20 s after their clients closed: '+$online.Count) }
        $row.login_ms=(Stats $login).max
        $row.join_ms=(Stats $join).max
        $row.asset_ms_max=(Stats $operations).max
        $row.asset_ms_median=(Stats $operations).median
        $row.ok=$true
    } catch {
        $row.ok=$false
        $row.error=$_.Exception.Message
        Note ('cycle '+$cycle+': '+$_.Exception.Message)
        foreach($client in $clients) { try { [void](Rk-StopClient $client) } catch { } }
        # A failed cycle must not leave its room running into the next ones.
        if ($null -ne $room -and $room.ok) { try { $cleanup=Rk-Api 'room.stop' @{room_id=$room.payload.room_id;reason='endurance cleanup'}; $row.cleanup_code=if ($cleanup.ok) { 'OK' } else { $cleanup.code } } catch { $row.cleanup_code='TRANSPORT' } }
    }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $reply=Rk-Api 'status'
    $status=$reply.payload
    $row.status_ms=$clock.ElapsedMilliseconds
    if (-not $reply.ok) { $row.status_code=$reply.code }
    $row.operator_rss=Rss $operatorPid
    $row.host_rss=Rss ([int]$status.host.pid)
    $row.system_memory_used=$status.metrics.system_memory_used_bytes
    $row.system_cpu=$status.metrics.system_cpu_percent
    $row.processes=ProjectProcessCount
    # Session clean-up owned by the Operator (no token in this view).
    if ($null -ne $status.session_cleanup) { $row.cleanup_pending=[int]$status.session_cleanup.pending; $row.cleanup_failed=[int]$status.session_cleanup.failed }
    if ([int]$row.cleanup_failed -gt 0) { Note ('cycle '+$cycle+': session clean-up failures listed: '+$row.cleanup_failed) }
    $row.load=if ($null -eq $row.system_cpu) { 'unknown' } elseif ([double]$row.system_cpu -ge 90) { 'saturated' } elseif ([double]$row.system_cpu -ge 70) { 'high' } else { 'light' }
    Add-Content -LiteralPath $rows -Value ($row | ConvertTo-Json -Compress) -Encoding utf8
    $samples+=,$row
    if ($cycle % 5 -eq 0) { Write-Output ('ENDURANCE_PROGRESS '+($row | ConvertTo-Json -Compress)) }
    $cycle++
}
[void](Rk-Api 'server.stop' @{immediate=$true;reason='endurance done'})
[void](Rk-WaitHost 'STOPPED')
$ok=@($samples | Where-Object ok)
$first=$ok | Select-Object -First 1
$last=$ok | Select-Object -Last 1
$summary=[ordered]@{
    minutes=$Minutes; cycles=$samples.Count; failed_cycles=@($samples | Where-Object { -not $_.ok }).Count; failures=@($failures)
    clients_per_cycle='2,4,6,8 rotating'
    room_ready_ms=(Stats @($ok | ForEach-Object { $_.room_ready_ms })); login_ms=(Stats @($ok | ForEach-Object { $_.login_ms }))
    join_ms=(Stats @($ok | ForEach-Object { $_.join_ms })); asset_ms=(Stats @($ok | ForEach-Object { $_.asset_ms_max })); room_stop_ms=(Stats @($ok | ForEach-Object { $_.room_stop_ms }))
    status_ms=(Stats @($samples | ForEach-Object { $_.status_ms }))
    operator_rss_first=$first.operator_rss; operator_rss_last=$last.operator_rss; operator_rss_max=(Stats @($samples | ForEach-Object { $_.operator_rss })).max
    host_rss_first=$first.host_rss; host_rss_last=$last.host_rss; host_rss_max=(Stats @($samples | ForEach-Object { $_.host_rss })).max
    system_memory_first=$first.system_memory_used; system_memory_last=$last.system_memory_used
    processes_first=$first.processes; processes_last=$last.processes
    load_cycles=[ordered]@{light=@($samples | Where-Object { $_.load -eq 'light' }).Count; high=@($samples | Where-Object { $_.load -eq 'high' }).Count; saturated=@($samples | Where-Object { $_.load -eq 'saturated' }).Count; unknown=@($samples | Where-Object { $_.load -eq 'unknown' }).Count}
    load_failed_cycles=[ordered]@{light=@($samples | Where-Object { $_.load -eq 'light' -and -not $_.ok }).Count; high=@($samples | Where-Object { $_.load -eq 'high' -and -not $_.ok }).Count; saturated=@($samples | Where-Object { $_.load -eq 'saturated' -and -not $_.ok }).Count}
    login_ms_light=(Stats @($ok | Where-Object { $_.load -eq 'light' } | ForEach-Object { $_.login_ms })); login_ms_saturated=(Stats @($ok | Where-Object { $_.load -eq 'saturated' } | ForEach-Object { $_.login_ms }))
    cleanup_failed_last=$last.cleanup_failed
}
Rk-SaveJson (Join-Path $evidence 'summary.json') $summary
Write-Output ('ENDURANCE_SUMMARY '+($summary | ConvertTo-Json -Compress -Depth 5))
Write-Output ('ENDURANCE_RESULT cycles='+$samples.Count+' failed_cycles='+$summary.failed_cycles+' failures='+$failures.Count)
if ($failures.Count -gt 0 -or $samples.Count -eq 0) { exit 1 }
exit 0
