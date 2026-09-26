param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Real generated-project acceptance. All publishing and runtime data belong to
# an isolated source copy; the normal build index/connection files are untouched.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runId=[Guid]::NewGuid().ToString('N')
$testRoot=Join-Path $project ('data/test-managed-template-'+$runId)
$fixture=Join-Path $testRoot 'project'
$private=Join-Path $fixture 'data/instance'
$evidence=Join-Path $project ('logs/managed-template-'+$runId)
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0
$script:failed=0
$script:checks=New-Object Collections.ArrayList
$script:clients=New-Object Collections.ArrayList
$script:descendants=@{}
$script:token=''
$script:commandNumber=0
$operator=$null
$roomIds=New-Object Collections.ArrayList
$roomPorts=New-Object Collections.ArrayList
$failure=''
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
function Config-Fingerprint($config) {
    $ordered=[ordered]@{}
    foreach($property in @($config.PSObject.Properties|Sort-Object Name)){
        if($property.Name -eq 'asset_spaces'){
            $bindings=[ordered]@{}
            foreach($binding in @($property.Value.PSObject.Properties|Sort-Object Name)){$bindings[$binding.Name]=$binding.Value}
            $ordered[$property.Name]=$bindings
        }else{$ordered[$property.Name]=$property.Value}
    }
    return ($ordered|ConvertTo-Json -Depth 10 -Compress)
}
function Free-TcpPort {
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    try{$listener.Start();return [int]$listener.LocalEndpoint.Port}finally{$listener.Stop()}
}
function Free-UdpPair {
    for($attempt=0;$attempt -lt 100;$attempt++){
        $first=Get-Random -Minimum 38000 -Maximum 49000
        $sockets=New-Object Collections.ArrayList
        $free=$true
        try{
            foreach($port in @($first,($first+1))){
                $socket=New-Object Net.Sockets.UdpClient
                [void]$sockets.Add($socket)
                $socket.ExclusiveAddressUse=$true
                $socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$port)))
            }
        }catch{$free=$false}finally{foreach($socket in $sockets){$socket.Dispose()}}
        if($free){return $first}
    }
    throw 'No free private UDP pair'
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
    $handle=$process.Handle
    return @{name=$name;process=$process;handle=$handle;directory=$directory}
}
function Report($client) {
    $deadline=[DateTime]::UtcNow.AddMilliseconds(200)
    do{
        if(Test-Path -LiteralPath $client.report){try{return Get-Content -Encoding UTF8 -Raw -LiteralPath $client.report|ConvertFrom-Json}catch{}}
        Start-Sleep -Milliseconds 10
    }while([DateTime]::UtcNow -lt $deadline)
    return $null
}
function Wait-Report($client,[scriptblock]$predicate,[int]$seconds=75) {
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do{
        $r=Report $client
        if($null -ne $r -and (& $predicate $r)){return $r}
        if($client.process.HasExited){throw ('Generated client exited before expected state: '+$client.name+' code='+$client.process.ExitCode)}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    throw ('Generated client report timeout: '+$client.name)
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
function Start-Client([string]$name,[string]$game,$credentials,[bool]$register) {
    $directory=Join-Path $evidence $name
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    $settingsPath=Join-Path $private ($name+'.json')
    $report=Join-Path $directory 'report.json'
    $connection=@{url=('wss://127.0.0.1:'+$lobbyPort);ca_certificate=(Join-Path $private 'server.crt');server_hostname='localhost';managed=$true;secure_enet=$true}
    Save-Json $settingsPath @{connection=$connection;username=$credentials.username;password=$credentials.password;display_name=$credentials.display_name;invite_code=$invitation;register=$register;report_path=$report;control_directory=$directory;timeout_ms=600000}
    $client=Start-Owned $name @('--headless','--path',$builds[$game].project,'--script','res://client.gd','--',('--settings='+$settingsPath)) $directory
    $client.report=$report
    $client.game_id=$game
    $client.user_id=''
    [void]$script:clients.Add($client)
    return $client
}
function Remember-Descendants {
    if($null -eq $operator){return}
    $marker=Join-Path $private 'host-running.json'
    if(Test-Path -LiteralPath $marker){
        $record=Get-Content -Encoding UTF8 -Raw -LiteralPath $marker|ConvertFrom-Json
        if(-not $record.verified -or $record.parent_pid -ne $operator.process.Id -or -not [string]::Equals([IO.Path]::GetFullPath($record.executable),[IO.Path]::GetFullPath($Godot),[StringComparison]::OrdinalIgnoreCase)){throw 'Unverified template fixture host ownership'}
        $script:descendants[$record.launch_id]=@{role='host';record=$record}
    }
    $journal=Join-Path $private 'processes.json'
    if(Test-Path -LiteralPath $journal){
        $stored=Get-Content -Encoding UTF8 -Raw -LiteralPath $journal|ConvertFrom-Json
        foreach($entry in $stored.entries.PSObject.Properties){
            $record=$entry.Value.owned
            $parents=@($script:descendants.Values|Where-Object {$_.role -eq 'host' -and $_.record.pid -eq $record.parent_pid})
            if(-not $record.verified -or $parents.Count -ne 1 -or -not [string]::Equals([IO.Path]::GetFullPath($record.executable),[IO.Path]::GetFullPath($Godot),[StringComparison]::OrdinalIgnoreCase)){throw 'Unverified template fixture room ownership'}
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
function Stop-Client($client) {
    if(-not $client.process.HasExited){try{[void](Command $client 'close' @{} 5)}catch{}}
    if(-not $client.process.WaitForExit(5000)){
        Check $false ($client.name+' graceful close watchdog')
        $client.process.Kill()
        if(-not $client.process.WaitForExit(5000)){throw 'Exact owned client exit timeout'}
    }
}
function Wait-Room([string]$roomId,[int]$connected,[int]$seconds=40) {
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do{
        $room=@((Api 'status').payload.rooms|Where-Object room_id -eq $roomId)[0]
        if($null -ne $room -and $room.state -eq 'READY' -and [int]$room.connected -eq $connected -and [int]$room.occupied -eq $connected){return $room}
        Start-Sleep -Milliseconds 150
    }while([DateTime]::UtcNow -lt $deadline)
    throw 'Generated room readiness or occupancy timeout'
}
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
try{
    if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)){throw 'Godot executable not found'}
    & (Join-Path $project 'tools/protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot|Out-Null
    New-Item -ItemType Directory -Force -Path $fixture|Out-Null
    foreach($directory in @('host','sdk','schemas','examples','tools','templates','config')){
        Copy-Item -LiteralPath (Join-Path $project $directory) -Destination $fixture -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $project 'project.godot') -Destination $fixture
    Save-Json (Join-Path $evidence 'source-snapshot.json') @{copied_at_utc=[DateTime]::UtcNow.ToString('o');fixture=$fixture;files=@(Get-ChildItem -LiteralPath (Join-Path $fixture 'host'),(Join-Path $fixture 'sdk'),(Join-Path $fixture 'templates'),(Join-Path $fixture 'schemas'),(Join-Path $fixture 'tools') -Recurse -File|Where-Object {$_.Extension -in @('.gd','.json','.ps1','.html')}|ForEach-Object {@{path=$_.FullName.Substring($fixture.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})}
    & (Join-Path $fixture 'tools/protect_data.ps1') -ProjectRoot $fixture -DataRoot $private|Out-Null
    & (Join-Path $fixture 'tools/protect_runtime.ps1') -ProjectRoot $fixture|Out-Null
    $gameA='template_a_'+$runId.Substring(0,8)
    $gameB='template_b_'+$runId.Substring(0,8)
    $builds=@{}
    foreach($game in @($gameA,$gameB)){
        $destination=Join-Path $fixture ('artifacts/'+$game)
        & (Join-Path $fixture 'tools/new_game.ps1') -Managed -GameId $game -Destination $destination|Out-Null
        $generated=Get-Content -LiteralPath (Join-Path $destination 'managed-games.json') -Raw -Encoding UTF8|ConvertFrom-Json
        $entry=$generated.PSObject.Properties[$game].Value
        Require ($null -ne $entry -and $entry.manifest.game_id -eq $game) ($game+' generated a matching managed index and manifest')
        $builds[$game]=$entry
        Require (Test-Path -LiteralPath (Join-Path $destination 'game/room.gd') -PathType Leaf) ($game+' has independent room entry')
        Require ((Get-FileHash -LiteralPath (Join-Path $destination 'sdk/roomkit/client/account_client.gd')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $fixture 'sdk/roomkit/client/account_client.gd')).Hash) ($game+' uses the copied public account SDK')
    }
    $index=Join-Path $private 'managed-games.json'
    Save-Json $index $builds
    $panelPort=Free-TcpPort
    do{$lobbyPort=Free-TcpPort}while($lobbyPort -eq $panelPort)
    do{$controlPort=Free-TcpPort}while($controlPort -in @($panelPort,$lobbyPort))
    $udpFirst=Free-UdpPair
    $spaces=@{};$spaces[$gameA]=$gameA;$spaces[$gameB]=$gameB
    Save-Json (Join-Path $private 'config.json') @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobbyPort;game_bind='127.0.0.1';control_port=$controlPort;udp_first=$udpFirst;udp_last=($udpFirst+1);max_rooms=2;asset_spaces=$spaces}
    $baseUrl='http://127.0.0.1:'+$panelPort
    $operatorDir=Join-Path $evidence 'operator'
    New-Item -ItemType Directory -Force -Path $operatorDir|Out-Null
    $operator=Start-Owned 'operator' @('--headless','--path',$fixture,'--log-file',(Join-Path $operatorDir 'engine.log'),'--script','res://host/operator.gd','--',('--data-root='+$private),('--panel-port='+$panelPort),('--games='+$index),('--operator-log-path='+(Join-Path $operatorDir 'engine.log'))) $operatorDir
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    $ready=$false
    do{try{$ready=(Api 'setup.status' @{} -Anonymous).ok}catch{Start-Sleep -Milliseconds 250}}while(-not $ready -and -not $operator.process.HasExited -and [DateTime]::UtcNow -lt $deadline)
    Require $ready 'private Operator with two generated games is HTTP ready'
    $setup=Api 'setup.create' @{username=('admin_'+$runId.Substring(0,8));password=('TemplateAdmin!'+[Guid]::NewGuid().ToString('N'))} -Anonymous
    Require ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'private administrator setup'
    $script:token=$setup.payload.token
    $initialConfig=Api 'config.get'
    Require $initialConfig.ok 'administrator reads generated-game configuration'
    $publicConfig=$initialConfig.payload.config
    $editable=@{lobby_bind=$publicConfig.lobby_bind;advertised_host=$publicConfig.advertised_host;lobby_port=$publicConfig.lobby_port;max_rooms=$publicConfig.max_rooms;asset_spaces=$spaces.Clone()}
    Require (Api 'config.set' @{config=$editable;reason='generated game configuration acceptance'}).ok 'administrator saves registry-backed custom GameId asset spaces'
    $savedConfig=Api 'config.get'
    Require ($savedConfig.ok -and (Config-Fingerprint $savedConfig.payload.config) -eq (Config-Fingerprint $publicConfig)) 'saving default generated-game spaces preserves the complete configuration'
    $configHash=(Get-FileHash -LiteralPath (Join-Path $private 'config.json') -Algorithm SHA256).Hash
    $unknownConfig=$editable.Clone()
    $unknownConfig.asset_spaces=$spaces.Clone()
    $unknownConfig.asset_spaces.Remove($gameA)
    $unknownConfig.asset_spaces['unregistered_template']=$gameA
    $unknown=Api 'config.set' @{config=$unknownConfig;reason='reject an unknown registry game'}
    Require (-not $unknown.ok -and $unknown.code -eq 'INVALID_OPTIONS') 'runtime registry rejects a well-formed unknown GameId'
    $afterUnknown=Api 'config.get'
    Require ($afterUnknown.ok -and (Config-Fingerprint $afterUnknown.payload.config) -eq (Config-Fingerprint $publicConfig) -and (Get-FileHash -LiteralPath (Join-Path $private 'config.json') -Algorithm SHA256).Hash -eq $configHash) 'unknown GameId changes neither live nor persisted configuration'
    $illegalConfig=$editable.Clone()
    $illegalConfig.asset_spaces=$spaces.Clone()
    $illegalConfig.asset_spaces[$gameA]='not_a_registered_space'
    $illegal=Api 'config.set' @{config=$illegalConfig;reason='reject an unregistered asset space'}
    Require (-not $illegal.ok -and $illegal.code -eq 'INVALID_OPTIONS') 'runtime registry rejects a well-formed but disallowed asset space'
    $afterIllegal=Api 'config.get'
    Require ($afterIllegal.ok -and (Config-Fingerprint $afterIllegal.payload.config) -eq (Config-Fingerprint $publicConfig) -and (Get-FileHash -LiteralPath (Join-Path $private 'config.json') -Algorithm SHA256).Hash -eq $configHash) 'disallowed space changes neither live nor persisted configuration'
    Save-Json (Join-Path $evidence 'config-validation.json') @{initial=$publicConfig;saved=$savedConfig.payload.config;unknown_game_code=$unknown.code;illegal_space_code=$illegal.code;final=$afterIllegal.payload.config;persisted_sha256=$configHash}
    Require (Api 'server.start').ok 'real managed host starts with generated games only'
    Remember-Descendants
    $rooms=@{}
    foreach($game in @($gameA,$gameB)){
        $mode=@($builds[$game].manifest.modes.PSObject.Properties)[0]
        Require ($null -ne $mode -and @($mode.Value.maps).Count -gt 0) ($game+' provides a real mode and map')
        $created=Api 'room.create' @{game_id=$game;mode=$mode.Name;map=$mode.Value.maps[0];capacity=2}
        Require $created.ok ($game+' room create accepted; code='+[string]$created.code)
        $roomId=[string]$created.payload.room_id
        [void]$roomIds.Add($roomId)
        $rooms[$game]=$roomId
        $room=Wait-Room $roomId 0
        [void]$roomPorts.Add([int]$room.port)
        Require ($room.game_id -eq $game) ($game+' independent room binds UDP and reaches READY')
        Remember-Descendants
    }
    $invite=Api 'invite.create' @{uses=2;expires_hours=1;reason='isolated generated managed game acceptance'}
    Require ($invite.ok -and ([string]$invite.payload.invite_code).Length -eq 32) 'two private registration invitations available'
    $invitation=$invite.payload.invite_code
    $credentials=@{username=('tpl_'+$runId.Substring(0,8));password=('Template!'+[Guid]::NewGuid().ToString('N'));display_name='Template player one'}
    $first=Start-Client 'first_login' $gameA $credentials $true
    $r=Wait-Report $first {param($r) $r.phase -in @('LOBBY','FAILED')} 90
    Require ($r.phase -eq 'LOBBY' -and $r.ok -and $r.registration.ok) 'generated client registers and authenticates over real WSS'
    $first.user_id=[string]$r.user_id
    Require ([int]$r.assets.credits -eq 0 -and 'standard' -in $r.assets.owned) 'generated catalog grants only its free standard badge initially'
    Require (Api 'asset.adjust' @{user_id=$first.user_id;game_id=$gameA;coins_delta=40;xp_delta=0;operation_id=('fund_'+$runId);reason='managed template integration credit grant'}).ok 'administrator commits forty credits to template asset space'
    Require (Command $first 'read').ok 'generated client reads confirmed assets in lobby'
    Require ([int](Report $first).assets.credits -eq 40) 'client sees forty committed credits'
    $purchaseId='buy_'+$runId
    Require (Command $first 'purchase' @{item_id='cobalt';operation_id=$purchaseId}).ok 'generated client buys cobalt badge through public SDK'
    $r=Report $first
    Require ([int]$r.assets.credits -eq 15 -and 'cobalt' -in $r.assets.owned) 'twenty-five credit purchase leaves fifteen and unlocks cobalt'
    Require (Command $first 'purchase' @{item_id='cobalt';operation_id=$purchaseId}).ok 'same purchase operation safely retries'
    Require ([int](Report $first).assets.credits -eq 15) 'purchase retry does not debit twice'
    Require (Command $first 'select' @{slot='badge';item_id='cobalt';operation_id=('select_'+$runId)}).ok 'generated client selects its owned badge in lobby'
    Require ((Report $first).assets.profiles.PSObject.Properties[$gameA].Value.badge -eq 'cobalt') 'confirmed template profile stores cobalt selection'
    Require (Command $first 'join' @{room_id=$rooms[$gameA]}).ok 'generated client joins independent template room over DTLS/ENet'
    $r=Wait-Report $first {param($r) $r.phase -eq 'IN_ROOM' -and @($r.world.players|Where-Object {$_.user_id -eq $first.user_id -and $_.badge -eq 'cobalt'}).Count -eq 1}
    Save-Json (Join-Path $evidence 'authoritative-cobalt.json') $r
    Require ($r.phase -eq 'IN_ROOM') 'authoritative room snapshot carries confirmed cobalt badge'
    [void](Wait-Room $rooms[$gameA] 1)
    Require (Command $first 'read').ok 'template room permits read-only asset inspection'
    $denied=Command $first 'select' @{slot='badge';item_id='standard';operation_id=('denied_'+$runId)}
    Require (-not $denied.ok -and $denied.code -eq 'ASSET_OPERATION_DENIED') 'template policy rejects asset selection while in room'
    Require (Command $first 'leave').ok 'template client leaves to lobby'
    [void](Wait-Room $rooms[$gameA] 0)
    Require (Command $first 'logout').ok 'first session logs out'
    Stop-Client $first
    $again=Start-Client 'second_login' $gameA $credentials $false
    $r=Wait-Report $again {param($r) $r.phase -in @('LOBBY','FAILED')} 90
    Require ($r.phase -eq 'LOBBY' -and $r.ok -and $r.user_id -eq $first.user_id) 'new generated client process logs into same stable account'
    $again.user_id=[string]$r.user_id
    Require ([int]$r.assets.credits -eq 15 -and 'cobalt' -in $r.assets.owned -and $r.assets.profiles.PSObject.Properties[$gameA].Value.badge -eq 'cobalt') 'wallet ownership and chosen badge survive logout and new process login'
    Save-Json (Join-Path $evidence 'persistent-assets.json') @{user_id=$r.user_id;assets=$r.assets}
    Require (Command $again 'join' @{room_id=$rooms[$gameA]}).ok 'relogged generated client rejoins same game'
    [void](Wait-Report $again {param($r) @($r.world.players|Where-Object {$_.user_id -eq $again.user_id -and $_.badge -eq 'cobalt'}).Count -eq 1})
    Require (Command $again 'leave').ok 'relogged client leaves cleanly'
    Require (Command $again 'logout').ok 'relogged session logs out'
    Stop-Client $again
    $otherCredentials=@{username=('tpl2_'+$runId.Substring(0,8));password=('Template!'+[Guid]::NewGuid().ToString('N'));display_name='Template player two'}
    $other=Start-Client 'other_game' $gameB $otherCredentials $true
    $r=Wait-Report $other {param($r) $r.phase -in @('LOBBY','FAILED')} 90
    Require ($r.phase -eq 'LOBBY' -and $r.ok -and $r.registration.ok) 'second independently named generated client authenticates'
    $other.user_id=[string]$r.user_id
    Require ([int]$r.assets.credits -eq 0 -and $r.assets.profiles.PSObject.Properties[$gameB].Value.badge -eq 'standard') 'second GameId exposes its own default asset profile'
    Require (Command $other 'join' @{room_id=$rooms[$gameB]}).ok 'second independent GameId admits a real generated client'
    $r=Wait-Report $other {param($r) @($r.world.players|Where-Object {$_.user_id -eq $other.user_id -and $_.badge -eq 'standard'}).Count -eq 1}
    Save-Json (Join-Path $evidence 'second-game-authoritative.json') $r
    Require (Command $other 'leave').ok 'second game client leaves cleanly'
    Require (Command $other 'logout').ok 'second game session logs out'
    Stop-Client $other
    foreach($roomId in $roomIds){
        [void](Wait-Room $roomId 0)
        Require (Api 'room.stop' @{room_id=$roomId;reason='generated template acceptance complete'}).ok 'generated room stop accepted'
        $deadline=[DateTime]::UtcNow.AddSeconds(35)
        do{Start-Sleep -Milliseconds 150;$row=@((Api 'status').payload.rooms|Where-Object room_id -eq $roomId)[0]}while(-not $row.cleaned -and [DateTime]::UtcNow -lt $deadline)
        Require ($row.cleaned -and $row.state -eq 'STOPPED') 'generated room confirmed exited and resources reclaimed'
    }
    foreach($database in @('accounts.sqlite','assets.sqlite')){
        $bytes=[IO.File]::ReadAllBytes((Join-Path $private $database))
        Require ([Text.Encoding]::ASCII.GetString($bytes,0,15) -eq 'SQLite format 3') ($database+' is a real private SQLite database')
    }
}catch{
    $script:failed++
    $failure=$_.Exception.Message
    Write-Host ('MANAGED_TEMPLATE_TEST_ERROR '+$failure)
}finally{
    try{Remember-Descendants}catch{Check $false 'fixture descendant ownership capture failed'}
    foreach($client in $script:clients){try{Stop-Client $client}catch{Check $false ($client.name+' cleanup failed');if(-not $client.process.HasExited){$client.process.Kill();[void]$client.process.WaitForExit(5000)}}}
    if($null -ne $operator){
        if(-not $operator.process.HasExited){
            try{if($script:token){[void](Api 'server.stop' @{immediate=$true;reason='managed template fixture cleanup'})}}catch{}
            [IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop',$utf8)
            $deadline=[DateTime]::UtcNow.AddSeconds(75)
            while(-not $operator.process.WaitForExit(1000) -and [DateTime]::UtcNow -lt $deadline){}
            if(-not $operator.process.HasExited){Check $false 'operator graceful shutdown watchdog';$operator.process.Kill();[void]$operator.process.WaitForExit(5000)}
        }
        Check ($operator.process.HasExited -and $operator.process.ExitCode -eq 0) 'owned operator exits successfully'
    }
    foreach($item in @($script:descendants.Values|Sort-Object @{Expression={if($_.role -eq 'room'){0}else{1}}})){
        try{Confirm-DescendantExit $item}catch{Check $false ('owned '+$item.role+' exit confirmation failed')}
    }
    foreach($port in $roomPorts){
        $udp=New-Object Net.Sockets.UdpClient
        try{$udp.ExclusiveAddressUse=$true;$udp.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,[int]$port)));Check $true 'final cleanup confirms generated room UDP port released'}catch{Check $false 'generated room UDP port still occupied'}finally{$udp.Dispose()}
    }
    foreach($child in @($script:clients)+@($operator)|Where-Object {$null -ne $_}){
        Check $child.process.HasExited ($child.name+' exact owned process exited')
        if($child.process.HasExited){Check ($child.process.ExitCode -eq 0) ($child.name+' exit code zero')}
        $stderr=Join-Path $child.directory 'stderr.log'
        if(Test-Path -LiteralPath $stderr){Check (-not (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:' -Quiet)) ($child.name+' no runtime errors')}
    }
    Save-Json (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;checks=@($script:checks);failure=$failure;test_root=$testRoot;source_fixture=$fixture;game_ids=@($gameA,$gameB);room_ids=@($roomIds);room_ports=@($roomPorts);headless=$true;scope='Windows localhost generated managed projects using copied SDK, real WSS/DTLS/ENet and SQLite; not GUI/export/LAN acceptance'}
    Write-Host ('MANAGED_TEMPLATE_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
exit $(if($script:failed -eq 0){0}else{1})
