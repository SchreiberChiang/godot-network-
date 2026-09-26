param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$id=[Guid]::NewGuid().ToString('N')
$fixture=Join-Path $project ('data/room-rules-'+$id+'/project')
$private=Join-Path $fixture 'data/instance'
$evidence=Join-Path $project ('logs/room-rules-'+$id)
$utf8=New-Object Text.UTF8Encoding($false)
$script:token='';$script:passed=0;$script:failed=0
$clients=New-Object Collections.ArrayList
$operator=$null
function Save($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 40),$utf8)}
function Check($value,$name){if($value){$script:passed++;Write-Output ('PASS '+$name)}else{$script:failed++;throw ('FAIL '+$name)}}
function Port { $s=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$s.Start();$n=$s.LocalEndpoint.Port;$s.Stop();return $n }
function Api($action,$payload=@{}) {
    $headers=@{};if($script:token){$headers.Authorization='Bearer '+$script:token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 30 -Compress))
    try{return Invoke-RestMethod -Uri ($url+'/api') -Method Post -Headers $headers -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 45}
    catch{throw ('HTTP request failed: '+$action+' (credentials suppressed)')}
}
function Start-Owned($arguments,$directory){
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    $quoted=foreach($argument in $arguments){'"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
    $p=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'console.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $h=$p.Handle
    return @{process=$p;handle=$h;directory=$directory}
}
function Wait-Room($roomId){
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do { $r=@((Api 'status').payload.rooms|Where-Object room_id -eq $roomId);if($r.Count -and $r[0].state -eq 'READY'){return $r[0]};Start-Sleep -Milliseconds 250 }while([DateTime]::UtcNow -lt $deadline)
    throw 'Room did not become READY'
}
function Report($client){if(Test-Path -LiteralPath $client.report){try{return Get-Content -Raw -Encoding UTF8 -LiteralPath $client.report|ConvertFrom-Json}catch{}};return $null}
function Wait-Report($client,$predicate,$seconds=40){
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do{$r=Report $client;if($null -ne $r -and (& $predicate $r)){return $r};if($client.process.HasExited){throw 'Owned test client exited early'};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $deadline)
    throw 'Timed out awaiting client report'
}
try {
    New-Item -ItemType Directory -Force -Path $fixture,$evidence|Out-Null
    foreach($dir in @('host','sdk','schemas','examples','tools','config')){Copy-Item -LiteralPath (Join-Path $project $dir) -Destination $fixture -Recurse}
    Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $fixture
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'tests')|Out-Null
    Copy-Item -LiteralPath (Join-Path $project 'tests/run_framework_clients.gd') -Destination (Join-Path $fixture 'tests')
    & (Join-Path $fixture 'tools/build_framework.ps1')|Out-Null
    $builds=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $fixture 'artifacts/framework-games.json')|ConvertFrom-Json
    & (Join-Path $fixture 'tools/protect_data.ps1') -ProjectRoot $fixture -DataRoot $private|Out-Null
    $panel=Port;$lobby=Port;$control=Port
    $udp=New-Object Net.Sockets.UdpClient
    $udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,0)));$roomPort=$udp.Client.LocalEndPoint.Port;$udp.Dispose()
    Save (Join-Path $private 'config.json') @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobby;game_bind='127.0.0.1';control_port=$control;udp_first=$roomPort;udp_last=$roomPort;max_rooms=1;asset_spaces=@{shooter='shooter';turns='turns'}}
    $url='http://127.0.0.1:'+$panel
    $operator=Start-Owned @('--headless','--path',$fixture,'--script','res://host/operator.gd','--',('--data-root='+$private),('--panel-port='+$panel)) (Join-Path $evidence 'operator')
    $deadline=[DateTime]::UtcNow.AddSeconds(45);$ready=$false
    do{try{$ready=(Api 'setup.status').ok}catch{Start-Sleep -Milliseconds 250}}while(-not $ready -and [DateTime]::UtcNow -lt $deadline -and -not $operator.process.HasExited)
    Check $ready 'isolated operator HTTP ready'
    $setup=Api 'setup.create' @{username=('rules_'+$id.Substring(0,8));password=('Admin!'+[Guid]::NewGuid().ToString('N'))}
    Check $setup.ok 'isolated administrator initialized'
    $script:token=$setup.payload.token
    Check (Api 'server.start').ok 'real managed host started'
    Check (@((Api 'status').payload.games|Where-Object game_id -eq 'shooter')[0].room_rules.kill_limit.maximum -eq 1000) 'panel receives registered rule definitions'
    $bad=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=2;rules=@{completion_credits=999}}
    Check (-not $bad.ok -and $bad.code -eq 'INVALID_OPTIONS') 'undeclared game rules rejected before spawning'
    $created=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=2;rules=@{duration_seconds=30;kill_limit=3;respawn_seconds=0}}
    Check $created.ok 'custom room accepted'
    $roomId=$created.payload.room_id
    $room=Wait-Room $roomId
    Check ($room.options.rules.duration_seconds -eq 30 -and $room.options.rules.respawn_seconds -eq 0) 'actual READY room publishes normalized rules'
    $invalid=Api 'room.recreate' @{room_id=$roomId;reason='invalid rule probe';rules=@{kill_limit=1001}}
    Check (-not $invalid.ok -and $invalid.code -eq 'INVALID_OPTIONS') 'invalid recreate rejected'
    $still=Wait-Room $roomId
    Check ($still.pid -eq $room.pid) 'invalid recreate leaves original room alive'
    $invite=Api 'invite.create' @{uses=2;expires_hours=1;reason='isolated room rule test'}
    Check $invite.ok 'isolated invitation created'
    foreach($name in @('one','two')){
        $directory=Join-Path $evidence $name
        New-Item -ItemType Directory -Force -Path $directory|Out-Null
        $report=Join-Path $directory 'report.json';$bootstrap=Join-Path $private ($name+'.json')
        Save $bootstrap @{connection=@{url=('wss://127.0.0.1:'+$lobby);ca_certificate=(Join-Path $private 'server.crt');server_hostname='localhost'};manifest=$builds.shooter.manifest;game_id='shooter';username=('r_'+$name+'_'+$id.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=$name;invite_code=$invite.payload.invite_code;register=$true;room_id=$roomId;report_path=$report;control_directory=$directory;timeout_ms=120000}
        $client=Start-Owned @('--headless','--path',$fixture,'--script','res://tests/run_framework_clients.gd','--',('--test-config='+$bootstrap)) $directory
        $client.report=$report;[void]$clients.Add($client)
        $r=Wait-Report $client {param($v) $v.phase -eq 'IN_ROOM' -and $v.world.players.Count -gt 0}
        Check ($r.world.kill_limit -eq 3 -and $r.world.remaining_ms -le 30000 -and $r.world.remaining_ms -gt 20000) ($name+' receives actual ENet match rules')
    }
    $r=Wait-Report $clients[0] {param($v) $v.world.round -ge 2 -and $v.world.last_results.Count -eq 2} 40
    Check ($r.world.last_results.Count -eq 2) 'real 30 second match ends for both players'
    $new=Api 'room.recreate' @{room_id=$roomId;reason='apply changed rules';rules=@{duration_seconds=60;kill_limit=10;respawn_seconds=2}}
    Check $new.ok 'valid rule update recreates room'
    $newId=$new.room_id;if(-not $newId){$newId=$new.payload.room_id}
    $replacement=Wait-Room $newId
    Check ($replacement.pid -ne $room.pid -and $replacement.port -eq $room.port -and $replacement.options.rules.kill_limit -eq 10) 'old process exits and same UDP port safely reused with new rules'
    $old=@((Api 'status').payload.rooms|Where-Object room_id -eq $roomId)[0]
    Check $old.cleaned 'old room reclaimed after recreate'
    Check (Api 'server.stop' @{immediate=$true;reason='test cleanup'}).ok 'test host shutdown accepted'
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do{$state=(Api 'status').payload.host.state;if($state -eq 'STOPPED'){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow -lt $deadline)
    Check ($state -eq 'STOPPED') 'owned host and rooms fully stopped'
} catch {
    $script:failed++;Write-Output $_.Exception.Message
} finally {
    foreach($client in $clients){
        if(-not $client.process.HasExited){Save (Join-Path $client.directory 'quit.command.json') @{id='quit';action='quit'};if(-not $client.process.WaitForExit(5000)){$client.process.Kill();$client.process.WaitForExit()}}
        $client.process.Dispose()
    }
    if($null -ne $operator){
        if(-not $operator.process.HasExited){[IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop');if(-not $operator.process.WaitForExit(45000)){$script:failed++;Write-Output 'FAIL owned operator shutdown timed out; inspect isolated fixture'}}
        if($operator.process.HasExited -and $operator.process.ExitCode -ne 0){$script:failed++}
        $operator.process.Dispose()
    }
    Save (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;scope='local actual Godot TCP WSS DTLS ENet processes and isolated SQLite';fixture=$fixture}
    Write-Output ('ROOM_RULES_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
if($script:failed -gt 0){exit 1}
