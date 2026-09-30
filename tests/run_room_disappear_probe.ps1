param(
    [ValidateSet('127.0.0.1','0.0.0.0')][string]$Bind='0.0.0.0',
    [string]$AdvertisedHost='',
    [int]$IdleSeconds=45,
    [int]$ObserveSeconds=15,
    [switch]$SkipUdp,
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
# Isolated reproduction for "empty room disappears after READY". Uses the admin UI
# fixture (own data root, ports, games index); never the user's service or data.
# Phases: idle empty room, then diagnostic UDP traffic against the room port
# (tests/run_room_udp_probe.gd). Records a per-second room state timeline and the
# redacted ROOM_CONTROL_CLOSED / ROOM_SHUTDOWN lines. No credentials are logged.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($AdvertisedHost -eq '') {
    $lan=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1)
    $AdvertisedHost=if($lan.Count){ $lan[0].IPAddress } else { '127.0.0.1' }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tests\run_admin_ui_fixture.ps1') -Action start -Bind $Bind -AdvertisedHost $AdvertisedHost | Write-Output
if($LASTEXITCODE -ne 0) { throw 'fixture start failed' }
$ctx=Get-Content -Encoding UTF8 -Raw (Join-Path $project 'run\admin-ui-fixture.json') | ConvertFrom-Json
$out=Join-Path $ctx.evidence 'disappear'
New-Item -ItemType Directory -Force $out | Out-Null
$timeline=Join-Path $out 'timeline.jsonl'
$utf8=New-Object Text.UTF8Encoding($false)
$script:token=''
function Api($action,$payload=@{}) {
    $headers=@{}; if($script:token){ $headers.Authorization='Bearer '+$script:token }
    $body=@{action=$action;payload=$payload}|ConvertTo-Json -Depth 6 -Compress
    $r=Invoke-RestMethod -Uri ($ctx.url+'/api') -Method Post -ContentType 'application/json; charset=utf-8' -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
    if(-not $r.ok){ throw ($action+' failed: '+$r.code) }
    return $r.payload
}
function Record($phase) {
    $st=Api 'status'
    foreach($room in @($st.rooms)) {
        if($room.cleaned -and $room.state -eq 'STOPPED') { continue }
        [IO.File]::AppendAllText($timeline,((@{t=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();phase=$phase;room=$room.room_id;state=$room.state;code=$room.code;port=$room.port;heartbeats=$room.heartbeats;heartbeat_age_ms=$room.heartbeat_age_ms;cleaned=$room.cleaned}|ConvertTo-Json -Compress)+"`n"),$utf8)
    }
    return $st
}
function Observe($phase,$roomId,$seconds) {
    $until=[DateTime]::UtcNow.AddSeconds($seconds)
    while([DateTime]::UtcNow -lt $until) {
        $st=Record $phase
        $row=@($st.rooms) | Where-Object { $_.room_id -eq $roomId } | Select-Object -First 1
        if(-not $row -or $row.state -ne 'READY') { return $false }
        Start-Sleep -Milliseconds 1000
    }
    return $true
}
function NewRoom($phase) {
    $created=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=8;rules=@{}}
    $id=[string]$created.room.room_id
    if(-not $id) { $id=[string]$created.room_id }
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    do { Start-Sleep -Milliseconds 500; $st=Record ($phase+':start'); $row=@($st.rooms) | Where-Object { $_.room_id -eq $id } | Select-Object -First 1 } while((-not $row -or $row.state -ne 'READY') -and [DateTime]::UtcNow -lt $deadline -and (-not $row -or $row.state -notin @('FAILED','STOPPED')))
    if(-not $row -or $row.state -ne 'READY') { throw ('room did not become READY in phase '+$phase) }
    return $row
}
function Probe($mode,$port,$repeat) {
    $log=Join-Path $out ('probe-'+$mode+'.log')
    $probeArgs=@('--headless','--path',$project,'--script','res://tests/run_room_udp_probe.gd','--',"--host=127.0.0.1","--port=$port","--mode=$mode","--repeat=$repeat",('--certificate='+(Join-Path $ctx.root 'server.crt')))
    $quoted=foreach($a in $probeArgs){ '"'+($a -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $p=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError ($log+'.err')
    $h=$p.Handle
    if(-not $p.WaitForExit(120000)) { $p.Kill(); throw ('probe timeout '+$mode) }
    return ((Get-Content -Encoding UTF8 $log | Where-Object { $_ -match '^PROBE_' }) -join ' ')
}
function Invite() { $r=Api 'invite.create' @{uses=1;expires_hours=1;reason='room disappear probe'}; if($r.invite_code){ return [string]$r.invite_code }; return [string]$r.invite.code }
function StartClient($name,$roomId,$timeoutMs,$holdMs) {
    # A private plan in the fixture's data root; the password never leaves it and
    # the file is removed after the client exits.
    $client=Join-Path $ctx.evidence 'out\shooter-windows\Client.exe'
    $plan=Join-Path $ctx.root ('plan-'+$name+'.json'); $report=Join-Path $out ('client-'+$name+'.json')
    [IO.File]::WriteAllText($plan,(@{username=$name;password=('Probe!'+[Guid]::NewGuid().ToString('N'));display_name=$name;invite_code=(Invite);register=$true;room_id=$roomId;timeout_ms=$timeoutMs;hold_ms=$holdMs;after='leave';lobby_ms=5000;report_path=$report}|ConvertTo-Json),$utf8)
    $quoted=foreach($a in @('--headless','--',('--autoplay='+$plan))){ '"'+$a+'"' }
    $p=Start-Process -FilePath $client -ArgumentList $quoted -WorkingDirectory ([IO.Path]::GetDirectoryName($client)) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $out ('client-'+$name+'.log')) -RedirectStandardError (Join-Path $out ('client-'+$name+'.err.log'))
    $h=$p.Handle
    return @{process=$p;plan=$plan;report=$report}
}
function FinishClient($c) {
    if(-not $c.process.WaitForExit(120000)) { $c.process.Kill() }
    Remove-Item -LiteralPath $c.plan -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $c.report) { $r=Get-Content -Encoding UTF8 -Raw $c.report | ConvertFrom-Json; return ('stage='+$r.stage+' join="'+$r.join_message+'" leave="'+$r.leave_message+'"') }
    return 'no report'
}
$summary=@()
try {
    $pw='Probe!'+[Guid]::NewGuid().ToString('N')
    $script:token=(Api 'setup.create' @{username='probe_admin';password=$pw}).token
    [void](Api 'server.start')
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    do { Start-Sleep -Milliseconds 700; $st=Api 'status' } while($st.host.state -ne 'RUNNING' -and [DateTime]::UtcNow -lt $deadline)
    if($st.host.state -ne 'RUNNING') { throw 'host not running' }
    $room=NewRoom 'idle'
    $alive=Observe 'idle' $room.room_id $IdleSeconds
    $summary+=('idle '+$IdleSeconds+'s bind='+$Bind+' advertised='+$(if($AdvertisedHost -eq '127.0.0.1'){'loopback'}else{'lan'})+': '+$(if($alive){'still READY'}else{'LEFT READY'}))
    # Export and register once through the fixture (prepares the client directory).
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tests\run_admin_ui_fixture.ps1') -Action player -Invite (Invite) | Write-Output
    if(-not $alive) { $room=NewRoom 'lobby_idle'; $alive=$true }
    $idleClient=StartClient ('pl_'+[Guid]::NewGuid().ToString('N').Substring(0,6)) ('r_'+[Guid]::NewGuid().ToString('N')) 40000 0
    $alive=Observe 'lobby_idle' $room.room_id 40
    $summary+=('lobby client polling 40s: '+(FinishClient $idleClient)+' -> room '+$(if($alive){'still READY'}else{'LEFT READY'}))
    if(-not $alive) { $room=NewRoom 'join'; $alive=$true }
    $joinClient=StartClient ('pj_'+[Guid]::NewGuid().ToString('N').Substring(0,6)) $room.room_id 60000 15000
    $until=[DateTime]::UtcNow.AddSeconds(45)
    while(-not $joinClient.process.HasExited -and [DateTime]::UtcNow -lt $until) { [void](Record 'join'); Start-Sleep -Milliseconds 1000 }
    $joined=FinishClient $joinClient
    Start-Sleep -Seconds 3
    # Rooms of one build share server.log; keep this room's copy before the next room starts.
    $shared=Join-Path ([string]((Get-Content -Encoding UTF8 -Raw $ctx.games_index | ConvertFrom-Json).shooter.project)) 'server.log'
    if(Test-Path -LiteralPath $shared) { Copy-Item -LiteralPath $shared -Destination (Join-Path $out 'join-room-server.log') }
    $st=Record 'after_leave'; $row=@($st.rooms) | Where-Object { $_.room_id -eq $room.room_id } | Select-Object -First 1
    $alive=[bool]($row -and $row.state -eq 'READY')
    if($alive) { $alive=Observe 'after_leave' $room.room_id $ObserveSeconds }
    $summary+=('real join via advertised host: '+$joined+' -> room '+$(if($alive){'still READY'}else{'LEFT READY ('+$row.state+' '+$row.code+')'}))
    foreach($mode in $(if($SkipUdp){@()}else{@('garbage','enet_plain','dtls_wrong_name','dtls_untrusted')})) {
        if(-not $alive) { $room=NewRoom $mode; $alive=$true }
        $probe=Probe $mode $room.port 3
        $alive=Observe $mode $room.room_id $ObserveSeconds
        $summary+=($mode+': '+$probe+' -> room '+$(if($alive){'still READY'}else{'LEFT READY'}))
    }
} finally {
    Start-Sleep -Seconds 2
    $hostLog=Join-Path $ctx.root 'logs\managed-host.log'
    if(Test-Path -LiteralPath $hostLog) { Get-Content -Encoding UTF8 $hostLog | Where-Object { $_ -match '^ROOM_(STATE|CONTROL_CLOSED)' } | Set-Content -Encoding UTF8 (Join-Path $out 'host-room-lines.log') }
    $index=Get-Content -Encoding UTF8 -Raw $ctx.games_index | ConvertFrom-Json
    $roomLog=Join-Path ([string]$index.shooter.project) 'server.log'
    if(Test-Path -LiteralPath $roomLog) { Copy-Item -LiteralPath $roomLog -Destination (Join-Path $out 'last-room-server.log') }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tests\run_admin_ui_fixture.ps1') -Action stop | Write-Output
    $summary | Set-Content -Encoding UTF8 (Join-Path $out 'summary.txt')
    $summary | Write-Output
    Write-Output ('EVIDENCE '+$out)
}
