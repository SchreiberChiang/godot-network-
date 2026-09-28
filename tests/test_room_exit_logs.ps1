param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',[switch]$AllowErrors,[ValidateSet('host-first','operator-direct')][string]$StopMode='operator-direct',[switch]$Visual,[int]$LeaveCycles=1)
# Isolated reproduction/regression for errors reported around leaving a room and
# stopping services. Own data root, ports, game index, public-client directory and
# exported client. Each step snapshots every log and attributes new ERROR/WARNING
# lines to that step, with wall-clock time and exit codes.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $project ('logs\room-exit-'+$runId)
$testRoot=Join-Path $project ('data\test-room-exit-'+$runId)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0; $script:failed=0; $script:timeline=@()
function Check([bool]$c,[string]$n) { if($c){$script:passed++;Write-Output ('PASS '+$n)}else{$script:failed++;Write-Output ('FAIL '+$n)} }
function Quote($values) { foreach($value in $values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'} }
function FreePort { $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); return $p }
$gamesIndex=Join-Path $evidence 'framework-games.json'
& (Join-Path $project 'tools\build_framework.ps1') -IndexPath $gamesIndex | Out-Null
$index=Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesIndex | ConvertFrom-Json
$buildRoot=[IO.Path]::GetDirectoryName($index.shooter.project)
$logRoots=@($evidence,$testRoot,$buildRoot)
$script:offsets=@{}
function Snap([string]$Step) {
    $found=@()
    foreach($root in $logRoots) {
        if(-not (Test-Path -LiteralPath $root)) { continue }
        foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue) {
            $key=$file.FullName
            $start=0; if($script:offsets.ContainsKey($key)) { $start=$script:offsets[$key] }
            $lines=@(Get-Content -Encoding UTF8 -LiteralPath $key -ErrorAction SilentlyContinue)
            $script:offsets[$key]=$lines.Count
            for($i=$start;$i -lt $lines.Count;$i++) {
                if($lines[$i] -match '^(ERROR|WARNING|SCRIPT ERROR)|Parse Error') {
                    $context=($lines[$i..([Math]::Min($i+6,$lines.Count-1))] | Where-Object { $_ -match 'res://|at:|^(ERROR|WARNING)' }) -join ' | '
                    $found+=[ordered]@{file=$key.Substring($project.Length+1);line=$i+1;text=$context}
                }
            }
        }
    }
    $entry=[ordered]@{step=$Step;time=(Get-Date).ToString('HH:mm:ss.fff');errors=$found}
    $script:timeline+=$entry
    Write-Host ('STEP '+$entry.time+' '+$Step+' new_errors='+$found.Count)
    foreach($e in $found) { Write-Host ('   '+$e.file+':'+$e.line+' '+$e.text) }
    return $found.Count
}

$panelPort=FreePort
$settings=@{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=(FreePort);game_bind='127.0.0.1';control_port=(FreePort);udp_first=28640;udp_last=28671;max_rooms=16;asset_spaces=@{shooter='shooter';turns='turns'}}
[IO.File]::WriteAllText((Join-Path $testRoot 'config.json'),($settings|ConvertTo-Json -Compress),$utf8)
$baseUrl='http://127.0.0.1:'+$panelPort
$script:token=''
function Api($action,$payload=@{},[switch]$Anonymous) {
    $headers=@{}; if($script:token -and -not $Anonymous){$headers.Authorization='Bearer '+$script:token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 20 -Compress))
    return Invoke-RestMethod -Uri ($baseUrl+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65
}
function WaitHost([string]$State,[int]$Seconds=60) { $d=[DateTime]::UtcNow.AddSeconds($Seconds); do { Start-Sleep -Milliseconds 300; $s=(Api 'status').payload } while($s.host.state -ne $State -and [DateTime]::UtcNow -lt $d); return $s }
function WaitRoom([string]$Room) { $d=[DateTime]::UtcNow.AddSeconds(45); do { Start-Sleep -Milliseconds 300; $r=@((Api 'status').payload.rooms|Where-Object room_id -eq $Room)[0] } while(($null -eq $r -or $r.state -ne 'READY') -and [DateTime]::UtcNow -lt $d); return $r }
$publicDir=Join-Path $evidence 'public-client'
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $evidence 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$testRoot),('--panel-port='+$panelPort),('--games='+$gamesIndex),('--public-client-dir='+$publicDir))
$operator=Start-Process -FilePath $Godot -ArgumentList (Quote $arguments) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'operator-console.log') -RedirectStandardError (Join-Path $evidence 'operator-stderr.log')
$operatorHandle=$operator.Handle
$clientsRun=@()
function StartClient([string]$Name,[string]$Room,[string]$After,[int]$HoldMs=2000) {
    $plan=Join-Path $testRoot ('plan-'+$Name+'.json'); $report=Join-Path $evidence ('report-'+$Name+'.json')
    [IO.File]::WriteAllText($plan,(@{username=('rx_'+$Name+'_'+$runId.Substring(0,6));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('rx_'+$Name);invite_code=$script:invite;register=$true;room_id=$Room;expect_players=1;hold_ms=$HoldMs;after=$After;lobby_ms=3000;timeout_ms=90000;report_path=$report}|ConvertTo-Json),$utf8)
    $p=Start-Process -FilePath (Join-Path $script:client 'Client.exe') -ArgumentList (Quote (@($(if(-not $Visual){'--headless'}))+@('--','--game=shooter',('--connection-config='+(Join-Path $script:client 'connection.json')),('--autoplay='+$plan)))) -WorkingDirectory $script:client -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence ('client-'+$Name+'.log')) -RedirectStandardError (Join-Path $evidence ('client-'+$Name+'-stderr.log'))
    return @{process=$p;handle=$p.Handle;plan=$plan;report=$report}
}
function FinishClient($c) {
    $p=$c.process; $report=$c.report
    if(-not $p.WaitForExit(150000)) { $p.Kill(); $p.WaitForExit() }
    if(Test-Path $c.plan) { Remove-Item -LiteralPath $c.plan -Force }
    $r=$null; if(Test-Path $report){ $r=Get-Content -Encoding UTF8 -Raw $report | ConvertFrom-Json }
    return @{exit=$p.ExitCode;report=$r}
}
function RunClient([string]$Name,[string]$Room,[string]$After,[int]$HoldMs=2000) { return FinishClient (StartClient $Name $Room $After $HoldMs) }
$stepErrors=@{}
$script:stayer=$null
try {
    $d=[DateTime]::UtcNow.AddSeconds(45); $ready=$false
    while(-not $ready -and [DateTime]::UtcNow -lt $d -and -not $operator.HasExited) { try { $ready=(Api 'setup.status' @{} -Anonymous).ok } catch { Start-Sleep -Milliseconds 300 } }
    if(-not $ready) { throw 'operator not ready' }
    $setup=Api 'setup.create' @{username=('admin_'+$runId.Substring(0,8));password=('Test!'+[Guid]::NewGuid().ToString('N'))} -Anonymous
    $script:token=$setup.payload.token
    Check (Api 'server.start').ok 'host start'
    $script:invite=(Api 'invite.create' @{uses=40;expires_hours=1;reason='room exit repro'}).payload.invite_code
    $prep=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\prepare_player_client.ps1') -Godot $Godot -IndexPath $gamesIndex -ConnectionDirectory $publicDir -OutputRoot (Join-Path $evidence 'out')
    $script:client=Join-Path $evidence 'out\shooter-windows'
    Check ($LASTEXITCODE -eq 0) 'isolated client prepared'
    $stepErrors.setup=Snap 'setup (operator, host, client export)'

    $room1=(Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=4}).payload.room_id
    Check ((WaitRoom $room1).state -eq 'READY') 'room 1 READY'
    $stepErrors.room_ready=Snap 'room 1 ready'
    $a=RunClient 'leave' $room1 'leave'
    Check ($a.report.stage -eq 'left_room') ('client joins then leaves room (stage='+$a.report.stage+', exit='+$a.exit+')')
    Start-Sleep -Seconds 3
    $stepErrors.leave=Snap 'A: single player leave room, back to lobby, close client'
    for($cycle=2;$cycle -le $LeaveCycles;$cycle++) {
        $c=RunClient ('leave'+$cycle) $room1 'leave' 1000
        Check ($c.report.stage -eq 'left_room') ('leave cycle '+$cycle+' (stage='+$c.report.stage+')')
        Start-Sleep -Milliseconds 1500
        $stepErrors[('leave'+$cycle)]=Snap ('A'+$cycle+': repeated leave')
    }

    $b=RunClient 'close' $room1 'close'
    Check ($b.report.stage -eq 'in_room_synced') ('client joins then closes window in room (exit='+$b.exit+')')
    Start-Sleep -Seconds 3
    $stepErrors.close=Snap 'B: close client while in room'

    $own=RunClient 'owner' '' 'leave'
    Check ($own.report.stage -eq 'left_room' -and $own.report.created_room) ('player creates own room, joins, leaves (stage='+$own.report.stage+')')
    Start-Sleep -Seconds 3
    $stepErrors.owner_leave=Snap 'A2: player-created room, leave'

    # A player stays in the room while services stop, as in manual play.
    $script:stayer=StartClient 'stay' $room1 'close' 60000
    Start-Sleep -Seconds 15 # register, login and join take about 5-10 s
    if($StopMode -eq 'host-first') {
        $stop=Api 'server.stop' @{immediate=$true;reason='room exit repro'}
        $s=WaitHost 'STOPPED'
        Check ($stop.ok -and $s.host.state -eq 'STOPPED') 'host stopped with a player in the room'
        $stepErrors.host_stop=Snap 'C: stop game host (player in room)'
    }
} finally {
    if(-not $operator.HasExited) {
        [IO.File]::WriteAllText((Join-Path $testRoot 'operator-stop.request'),'stop')
        if(-not $operator.WaitForExit(65000)) { $operator.Kill(); $operator.WaitForExit(); Check $false 'operator graceful stop' }
    }
    Check ($operator.ExitCode -eq 0) ('operator exit code '+$operator.ExitCode+' (stop='+$StopMode+')')
    if($script:stayer) { $st=FinishClient $script:stayer; Write-Host ('stayer client exit='+$st.exit+' stage='+$st.report.stage) }
    $stepErrors.operator_stop=Snap 'D: stop operator'
    [IO.File]::WriteAllText((Join-Path $evidence 'timeline.json'),($script:timeline|ConvertTo-Json -Depth 8),$utf8)
}
if(-not $AllowErrors) {
    foreach($k in @($stepErrors.Keys | Where-Object { $_ -notin @('setup','room_ready') })) { Check ($stepErrors[$k] -eq 0) ('no new engine errors in step '+$k) }
}
Write-Output ('ROOM_EXIT_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
if($script:failed) { exit 1 }
exit 0
