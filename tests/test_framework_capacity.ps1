param(
    [ValidateRange(15,60)][int]$ObserveSeconds=15,
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
# Real source-host capacity/admission acceptance; not a sustained load benchmark.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runId=[Guid]::NewGuid().ToString('N')
$testRoot=Join-Path $project ('data\test-capacity-'+$runId)
$fixture=Join-Path $testRoot 'project'
$private=Join-Path $fixture 'data\instance'
$evidence=Join-Path $project ('logs\capacity-'+$runId)
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0
$script:failed=0
$script:checks=New-Object Collections.ArrayList
$script:clients=New-Object Collections.ArrayList
$script:samples=New-Object Collections.ArrayList
$script:descendants=@{}
$script:token=''
$script:commandNumber=0
$operator=$null
$roomId=''
$inviteId=''
$failure=''
$observedMs=0
$roomPort=0
function Save-Json($path,$value) {
    $temporary=$path+'.tmp'
    [IO.File]::WriteAllText($temporary,($value|ConvertTo-Json -Depth 50 -Compress),$utf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
}
function Check([bool]$condition,[string]$name) {
    [void]$script:checks.Add(@{name=$name;passed=$condition})
    if($condition){$script:passed++;Write-Host ('PASS '+$name)}else{$script:failed++;Write-Host ('FAIL '+$name)}
}
function Require([bool]$condition,[string]$name) { Check $condition $name; if(-not $condition){throw ('Prerequisite failed: '+$name)} }
function Free-TcpPort {
    $socket=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    try{$socket.Start();return [int]$socket.LocalEndpoint.Port}finally{$socket.Stop()}
}
function Free-UdpPort {
    $socket=New-Object Net.Sockets.UdpClient
    try{$socket.ExclusiveAddressUse=$true;$socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,0)));return [int]$socket.Client.LocalEndPoint.Port}finally{$socket.Dispose()}
}
function Api([string]$action,$payload=@{},[switch]$Anonymous) {
    $headers=@{}
    if($script:token -and -not $Anonymous){$headers.Authorization='Bearer '+$script:token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 25 -Compress))
    try{return Invoke-RestMethod -Uri ($baseUrl+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65}
    catch{throw ('Administrator HTTP request failed: '+$action+' (credentials suppressed)')}
}
function Start-Owned([string]$name,[string[]]$arguments,[string]$directory) {
    $quoted=foreach($argument in $arguments){'"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'console.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    # Retain this exact process handle; never terminate a process found only by PID/name.
    $handle=$process.Handle
    return @{name=$name;process=$process;handle=$handle;directory=$directory}
}
function Report($client) {
    # The real driver atomically replaces this file every 200 ms. Windows may
    # briefly deny/open no file during replacement; do not fabricate tick=0.
    $deadline=[DateTime]::UtcNow.AddMilliseconds(200)
    do{
        if(Test-Path -LiteralPath $client.report){try{return Get-Content -Encoding UTF8 -Raw -LiteralPath $client.report|ConvertFrom-Json}catch{}}
        Start-Sleep -Milliseconds 10
    }while([DateTime]::UtcNow -lt $deadline)
    return $null
}
function Remember-Descendants {
    if($null -eq $operator){return}
    $hostMarker=Join-Path $private 'host-running.json'
    if(Test-Path -LiteralPath $hostMarker){
        $record=Get-Content -Encoding UTF8 -Raw -LiteralPath $hostMarker|ConvertFrom-Json
        if(-not $record.verified -or $record.parent_pid -ne $operator.process.Id -or -not [string]::Equals([IO.Path]::GetFullPath($record.executable),[IO.Path]::GetFullPath($Godot),[StringComparison]::OrdinalIgnoreCase)){throw 'Unverified fixture host ownership record'}
        $script:descendants[$record.launch_id]=@{role='host';record=$record}
    }
    $journal=Join-Path $private 'processes.json'
    if(Test-Path -LiteralPath $journal){
        $stored=Get-Content -Encoding UTF8 -Raw -LiteralPath $journal|ConvertFrom-Json
        foreach($entry in $stored.entries.PSObject.Properties){
            $record=$entry.Value.owned
            $parents=@($script:descendants.Values|Where-Object {$_.role -eq 'host' -and $_.record.pid -eq $record.parent_pid})
            if(-not $record.verified -or $parents.Count -ne 1 -or -not [string]::Equals([IO.Path]::GetFullPath($record.executable),[IO.Path]::GetFullPath($Godot),[StringComparison]::OrdinalIgnoreCase)){throw 'Unverified fixture room ownership record'}
            $script:descendants[$record.launch_id]=@{role='room';record=$record}
        }
    }
}
function Confirm-DescendantExit($item) {
    $record=$item.record
    $probe=& (Join-Path $fixture 'tools/process_identity.ps1') -Mode inspect -ProcessId $record.pid -ExpectedParentPid $record.parent_pid -ExpectedExecutable $record.executable -LaunchId $record.launch_id -ExpectedCreationFileTime $record.created_filetime|ConvertFrom-Json
    if($probe.state -eq 'running'){
        Check $false ('owned '+$item.role+' required forced cleanup after operator stopped')
        $candidate=$null
        try{
            $candidate=[Diagnostics.Process]::GetProcessById([int]$record.pid)
            $held=$candidate.Handle
            # The helper validated parent/launch marker. Recheck immutable identity
            # on this pinned handle so a PID reuse between inspect and open is safe.
            if(-not $candidate.HasExited){
                $created=$candidate.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
                $same=[string]::Equals([IO.Path]::GetFullPath($candidate.MainModule.FileName),[IO.Path]::GetFullPath($record.executable),[StringComparison]::OrdinalIgnoreCase)
                if($created -ne [string]$record.created_filetime -or -not $same){throw 'Descendant identity changed; refusing termination'}
                $candidate.Kill()
                if(-not $candidate.WaitForExit(5000)){throw 'Owned descendant exit timeout'}
            }
            $probe.state='exited'
        }finally{if($null -ne $candidate){$candidate.Dispose()}}
    }
    Check ($probe.state -eq 'exited') ('verified owned '+$item.role+' process has exited')
}
function Wait-Report($client,[scriptblock]$predicate,[int]$seconds=75) {
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do{
        $r=Report $client
        if($null -ne $r -and (& $predicate $r)){return $r}
        if($client.process.HasExited){throw ('Client exited before expected state: '+$client.name+' code='+$client.process.ExitCode)}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    throw ('Client report timeout: '+$client.name)
}
function Start-Client([int]$number) {
    $name='player_'+$number.ToString('D2')
    $directory=Join-Path $evidence $name
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    $bootstrap=Join-Path $private ($name+'.json')
    $report=Join-Path $directory 'report.json'
    $username='cap_'+$runId.Substring(0,8)+'_'+$number
    $password='Capacity!'+[Guid]::NewGuid().ToString('N')
    $connection=@{url=('wss://127.0.0.1:'+$lobbyPort);ca_certificate=(Join-Path $private 'server.crt');server_hostname='localhost';game_id='shooter'}
    Save-Json $bootstrap @{connection=$connection;manifest=$builds.shooter.manifest;game_id='shooter';username=$username;password=$password;display_name=$name;invite_code=$invitation;register=$true;report_path=$report;control_directory=$directory;timeout_ms=1200000}
    $client=Start-Owned $name @('--headless','--path',$fixture,'--script','res://tests/run_framework_clients.gd','--',('--test-config='+$bootstrap)) $directory
    $client.report=$report
    $client.user_id=''
    [void]$script:clients.Add($client)
    return $client
}
function Command($client,[string]$action,$payload=@{},[int]$seconds=75) {
    $script:commandNumber++
    $id='c'+$script:commandNumber.ToString('D6')
    $value=@{id=$id;action=$action}
    foreach($key in $payload.Keys){$value[$key]=$payload[$key]}
    Save-Json (Join-Path $client.directory ($id+'.command.json')) $value
    $r=Wait-Report $client {param($r) @($r.results|Where-Object id -eq $id).Count -gt 0} $seconds
    return @($r.results|Where-Object id -eq $id)[-1]
}
function Room-From($status) { return @($status.payload.rooms|Where-Object room_id -eq $roomId)[0] }
function Wait-Occupancy([int]$count,[int]$seconds=20) {
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do{
        $status=Api 'status'
        $row=Room-From $status
        if($null -ne $row -and [int]$row.connected -eq $count -and [int]$row.occupied -eq $count){return $row}
        Start-Sleep -Milliseconds 150
    }while([DateTime]::UtcNow -lt $deadline)
    throw ('Room occupancy did not reach '+$count)
}
function Stop-Client($client) {
    if(-not $client.process.HasExited){try{[void](Command $client 'close' @{} 5)}catch{}}
    if(-not $client.process.WaitForExit(5000)){
        Check $false ($client.name+' graceful close watchdog')
        $client.process.Kill();$client.process.WaitForExit()
    }
}
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
try{
    if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)){throw 'Godot executable not found'}
    & (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot|Out-Null
    New-Item -ItemType Directory -Force -Path $fixture|Out-Null
    # Isolate the complete current source composition so its fixed public-config
    # output and process journal cannot affect another operator/test session.
    foreach($directory in @('host','sdk','schemas','examples','tools','tests')){
        Copy-Item -LiteralPath (Join-Path $project $directory) -Destination $fixture -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $fixture
    Save-Json (Join-Path $evidence 'source-snapshot.json') @{copied_at_utc=[DateTime]::UtcNow.ToString('o');source_project=$project;fixture=$fixture;files=@(Get-ChildItem -LiteralPath (Join-Path $fixture 'host'),(Join-Path $fixture 'sdk'),(Join-Path $fixture 'examples'),(Join-Path $fixture 'schemas'),(Join-Path $fixture 'tools') -Recurse -File|Where-Object {$_.Extension -in @('.gd','.json','.ps1','.html')}|ForEach-Object {@{path=$_.FullName.Substring($fixture.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})}
    & (Join-Path $fixture 'tools\protect_data.ps1') -ProjectRoot $fixture -DataRoot $private|Out-Null
    & (Join-Path $fixture 'tools\protect_runtime.ps1') -ProjectRoot $fixture|Out-Null
    $index=Join-Path $private 'framework-games.json'
    & (Join-Path $fixture 'tools\build_framework.ps1') -IndexPath $index|Out-Null
    $builds=Get-Content -Encoding UTF8 -Raw -LiteralPath $index|ConvertFrom-Json
    $rules=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $builds.shooter.project 'game/game_config.json')|ConvertFrom-Json
    Require ($rules.duration_ms -eq 300000 -and $rules.minimum_participation_ms -eq 60000 -and $rules.respawn_ms -eq 3000) 'unmodified production gameplay durations'
    $panelPort=Free-TcpPort
    do{$lobbyPort=Free-TcpPort}while($lobbyPort -eq $panelPort)
    do{$controlPort=Free-TcpPort}while($controlPort -in @($panelPort,$lobbyPort))
    $roomPort=Free-UdpPort
    $settings=@{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobbyPort;game_bind='127.0.0.1';control_port=$controlPort;udp_first=$roomPort;udp_last=$roomPort;max_rooms=1;asset_spaces=@{shooter='shooter';turns='turns'}}
    Save-Json (Join-Path $private 'config.json') $settings
    $baseUrl='http://127.0.0.1:'+$panelPort
    $operatorDir=Join-Path $evidence 'operator'
    New-Item -ItemType Directory -Force -Path $operatorDir|Out-Null
    $operator=Start-Owned 'operator' @('--headless','--path',$fixture,'--script','res://host/operator.gd','--',('--data-root='+$private),('--panel-port='+$panelPort),('--games='+$index)) $operatorDir
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    $ready=$false
    do{try{$ready=(Api 'setup.status' @{} -Anonymous).ok}catch{Start-Sleep -Milliseconds 300}}while(-not $ready -and -not $operator.process.HasExited -and [DateTime]::UtcNow -lt $deadline)
    Require $ready 'isolated source operator HTTP ready'
    $setup=Api 'setup.create' @{username=('admin_'+$runId.Substring(0,8));password=('CapacityAdmin!'+[Guid]::NewGuid().ToString('N'))} -Anonymous
    Require ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'private administrator setup'
    $script:token=$setup.payload.token
    Require (Api 'server.start').ok 'real managed host started'
    Remember-Descendants
    $create=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=16}
    Require $create.ok 'capacity sixteen shooter room created'
    $roomId=$create.payload.room_id
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do{Start-Sleep -Milliseconds 200;$room=Room-From (Api 'status')}while(($null -eq $room -or $room.state -eq 'STARTING') -and [DateTime]::UtcNow -lt $deadline)
    Require ($room.state -eq 'READY' -and [int]$room.port -eq $roomPort -and [int]$room.capacity -eq 16) 'real room binds assigned dynamic UDP port and becomes READY'
    Remember-Descendants
    $invite=Api 'invite.create' @{uses=17;expires_hours=1;reason='isolated sixteen player capacity acceptance'}
    Require ($invite.ok -and ([string]$invite.payload.invite_code).Length -eq 32) 'private invitation supports seventeen real registrations'
    $invitation=$invite.payload.invite_code
    $inviteId=$invite.payload.invite_id
    for($number=1;$number -le 17;$number++){
        $client=Start-Client $number
        $r=Wait-Report $client {param($r) $r.phase -in @('LOBBY','FAILED')} 90
        Require ($r.phase -eq 'LOBBY' -and $r.ok -and $r.registration.ok) ($client.name+' registered and WSS authenticated')
        $client.user_id=$r.user_id
    }
    $players=@($script:clients|Select-Object -First 16)
    for($number=0;$number -lt 16;$number++){
        $client=$players[$number]
        $joined=Command $client 'join' @{room_id=$roomId}
        Require $joined.ok ($client.name+' real ENet admission')
        [void](Wait-Report $client {param($r) $r.phase -eq 'IN_ROOM' -and @($r.world.players|Where-Object user_id -eq $client.user_id).Count -eq 1})
    }
    $full=Wait-Occupancy 16
    Require ($full.state -eq 'READY') 'host confirms sixteen connected seats with no pending reservations'
    $seventeenth=$script:clients[16]
    $rejected=Command $seventeenth 'join_sdk' @{room_id=$roomId}
    Require (-not $rejected.ok -and $rejected.code -eq 'ROOM_FULL' -and (Report $seventeenth).phase -eq 'LOBBY') 'seventeenth real client rejected ROOM_FULL and remains in lobby'
    $expected=(@($players|ForEach-Object {$_.user_id}|Sort-Object)-join ',')
    foreach($client in $players){
        $r=Wait-Report $client {param($r) @($r.world.players).Count -eq 16} 15
        Require ((@($r.world.players|ForEach-Object {$_.user_id}|Sort-Object)-join ',') -eq $expected) ($client.name+' receives same sixteen authoritative identities')
        $client.initial_tick=[long]$r.world.tick
        $client.last_observed_tick=[long]$r.world.tick
        $client.last_progress_ms=0
    }
    $initial=(Report $players[0]).world.players|Where-Object user_id -eq $players[0].user_id
    $initialX=[double]$initial.x
    [void](Command $players[0] 'input' @{move=1;duration_ms=8000})
    $heartbeats=[long]$full.heartbeats
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        $status=Api 'status'
        $room=Room-From $status
        $valid=($room.state -eq 'READY' -and [int]$room.connected -eq 16 -and [int]$room.occupied -eq 16)
        $ticks=@()
        foreach($client in $players){
            $r=Report $client
            $valid=$valid -and -not $client.process.HasExited -and $r.phase -eq 'IN_ROOM' -and @($r.world.players).Count -eq 16
            if([long]$r.world.tick -gt $client.last_observed_tick){$client.last_progress_ms=$watch.ElapsedMilliseconds}
            $valid=$valid -and [long]$r.world.tick -ge $client.last_observed_tick -and ($watch.ElapsedMilliseconds-$client.last_progress_ms) -lt 2500
            $client.last_observed_tick=[long]$r.world.tick
            $ticks+=([long]$r.world.tick)
        }
        [void]$script:samples.Add(@{elapsed_ms=$watch.ElapsedMilliseconds;connected=$room.connected;occupied=$room.occupied;heartbeats=$room.heartbeats;heartbeat_age_ms=$room.heartbeat_age_ms;client_ticks=$ticks;valid=$valid})
        if(-not $valid){throw 'A player, seat, snapshot, or READY state was lost during full-capacity observation'}
        Start-Sleep -Milliseconds 500
    }while($watch.Elapsed.TotalSeconds -lt $ObserveSeconds)
    $observedMs=$watch.ElapsedMilliseconds
    Require ($observedMs -ge $ObserveSeconds*1000 -and @($script:samples|Where-Object {-not $_.valid}).Count -eq 0) 'sixteen real clients remain synchronized for entire observation interval'
    $full=Wait-Occupancy 16
    Require ([long]$full.heartbeats -gt $heartbeats -and [long]$full.heartbeat_age_ms -lt 5000) 'room heartbeats continue at full occupancy'
    foreach($client in $players){
        $r=Report $client
        $moving=@($r.world.players|Where-Object user_id -eq $players[0].user_id)[0]
        Require ([long]$r.world.tick -gt $client.initial_tick -and [double]$moving.x -gt $initialX+20) ($client.name+' observes server tick progress and shared real movement')
    }
    for($number=0;$number -lt 16;$number++){
        $client=$players[$number]
        Require (Command $client 'leave').ok ($client.name+' leaves to authenticated lobby')
        [void](Wait-Occupancy (15-$number))
    }
    Require ((Wait-Occupancy 0).occupied -eq 0) 'all sixteen seats and reservations reclaimed after ordered leave'
    $afterLeave=Command $seventeenth 'join' @{room_id=$roomId}
    Require $afterLeave.ok 'previously rejected seventeenth player can use reclaimed capacity'
    [void](Wait-Occupancy 1)
    Require (Command $seventeenth 'leave').ok 'seventeenth player leaves after reclaimed-seat check'
    [void](Wait-Occupancy 0)
    foreach($client in $script:clients){Require (Command $client 'logout').ok ($client.name+' authenticated session logs out');Stop-Client $client}
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{$status=Api 'status';if(@($status.payload.players).Count -eq 0){break};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $deadline)
    Require (@($status.payload.players).Count -eq 0) 'host has no player connections after all logouts'
    Require (Api 'room.stop' @{room_id=$roomId;reason='capacity acceptance complete'}).ok 'room stop accepted'
    $deadline=[DateTime]::UtcNow.AddSeconds(35)
    do{Start-Sleep -Milliseconds 200;$room=Room-From (Api 'status')}while(-not $room.cleaned -and [DateTime]::UtcNow -lt $deadline)
    Require ($room.cleaned -and $room.state -eq 'STOPPED') 'room confirmed exited and resources reclaimed'
    $udp=New-Object Net.Sockets.UdpClient
    try{$udp.ExclusiveAddressUse=$true;$udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$roomPort)));Check $true 'reclaimed room UDP port can be rebound'}finally{$udp.Dispose()}
    $journal=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $private 'processes.json')|ConvertFrom-Json
    Require (@($journal.entries.PSObject.Properties).Count -eq 0) 'confirmed exited room removed from private process journal'
}catch{
    $script:failed++
    $failure=$_.Exception.Message
    Write-Host ('FRAMEWORK_CAPACITY_TEST_ERROR '+$failure)
}finally{
    try{Remember-Descendants}catch{Check $false 'fixture descendant ownership capture failed'}
    foreach($client in $script:clients){try{Stop-Client $client}catch{Check $false ($client.name+' cleanup failed');if(-not $client.process.HasExited){$client.process.Kill();$client.process.WaitForExit()}}}
    if($null -ne $operator){
        if(-not $operator.process.HasExited){
            try{if($script:token){[void](Api 'server.stop' @{immediate=$true;reason='capacity fixture cleanup'})}}catch{}
            [IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop',$utf8)
            $deadline=[DateTime]::UtcNow.AddSeconds(75)
            while(-not $operator.process.WaitForExit(1000) -and [DateTime]::UtcNow -lt $deadline){}
            if(-not $operator.process.HasExited){Check $false 'operator graceful shutdown watchdog';$operator.process.Kill();$operator.process.WaitForExit()}
        }
        Check ($operator.process.ExitCode -eq 0) 'owned operator exits successfully'
    }
    foreach($item in @($script:descendants.Values|Sort-Object @{Expression={if($_.role -eq 'room'){0}else{1}}})){
        try{Confirm-DescendantExit $item}catch{Check $false ('owned '+$item.role+' exit confirmation failed')}
    }
    if($roomId){
        $udp=New-Object Net.Sockets.UdpClient
        try{$udp.ExclusiveAddressUse=$true;$udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$roomPort)));Check $true 'final cleanup confirms room UDP port released'}catch{Check $false 'final cleanup room UDP port still occupied'}finally{$udp.Dispose()}
    }
    foreach($child in @($script:clients)+@($operator)|Where-Object {$null -ne $_}){
        Check $child.process.HasExited ($child.name+' exact owned process exited')
        if($child.name -ne 'operator'){Check ($child.process.ExitCode -eq 0) ($child.name+' exit code zero')}
        $stderr=Join-Path $child.directory 'stderr.log'
        if(Test-Path -LiteralPath $stderr){Check (-not (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:' -Quiet)) ($child.name+' no runtime errors')}
    }
    Save-Json (Join-Path $evidence 'samples.json') @($script:samples)
    Save-Json (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;checks=@($script:checks);failure=$failure;test_root=$testRoot;source_fixture=$fixture;room_id=$roomId;room_port=$roomPort;players=16;overflow_players=1;observed_ms=$observedMs;production_round_ms=300000;headless=$true;scope='Windows localhost real WSS/ENet short capacity and admission; not sustained load or LAN acceptance';samples='samples.json'}
    Write-Host ('FRAMEWORK_CAPACITY_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
exit $(if($script:failed -eq 0){0}else{1})
