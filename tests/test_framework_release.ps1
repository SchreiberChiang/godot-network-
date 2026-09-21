[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Bundle,
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
# The six release executables are genuine exports. Network clients deliberately
# use the source driver, not an injected --script override on a release Client.exe.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not [IO.Path]::IsPathRooted($Bundle)){throw '-Bundle must be an absolute path.'}
$package=[IO.Path]::GetFullPath($Bundle).TrimEnd('\','/')
if(-not $package.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'For this repository test, extract the bundle inside this repository first.'}
$cursor=$package
while($cursor.Length -ge $project.Length){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'A package ancestor is a reparse point.'}
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
foreach($path in @($package,(Join-Path $package 'data'),(Join-Path $package 'artifacts'),(Join-Path $package 'artifacts/client'))){
    if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'A package test path is a reparse point.'}
}
foreach($relative in @('project.godot','Operator.exe','Operator.pck','ManagedHost.exe','ManagedHost.pck','checksums.json','artifacts/framework-games.json','tools/protect_data.ps1','games/shooter/Server.exe','games/shooter/Server.pck','games/turns/Server.exe','games/turns/Server.pck','clients/shooter/Client.exe','clients/shooter/Client.pck','clients/turns/Client.exe','clients/turns/Client.pck')){
    if(-not (Test-Path -LiteralPath (Join-Path $package $relative) -PathType Leaf)){throw ('Incomplete native package: '+$relative)}
}
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)){throw 'Godot editor is required for the source network-client driver.'}
# Refuse to reuse a package that is serving another local test or user session.
$active=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase)})
if($active.Count){throw 'A process from this package is already running. Use another freshly extracted bundle.'}
$runId=[Guid]::NewGuid().ToString('N')
$private=Join-Path $package ('data/release-test-'+$runId)
$evidence=Join-Path $project ('logs/framework-release-'+$runId)
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0
$script:failed=0
$script:checks=New-Object Collections.ArrayList
$script:token=''
$script:baseUrl=''
$script:operator=$null
$script:clients=New-Object Collections.ArrayList
$script:nativeOwned=New-Object Collections.ArrayList
$script:knownHostPids=New-Object Collections.Generic.HashSet[int]
$publicSaved=@{}
$publicDirectory=Join-Path $package 'artifacts/client'
$failure=''
$cleanupFailed=$false

function SaveJson([string]$Path,$Value){
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 40 -Compress),$utf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Check([bool]$Condition,[string]$Name){
    [void]$script:checks.Add(@{name=$Name;passed=$Condition})
    if(-not $Condition){$script:failed++;throw ('FAIL '+$Name)}
    $script:passed++;Write-Host ('PASS '+$Name)
}
function QuoteArgs($Values){return @($Values|ForEach-Object {'"'+([string]$_ -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'})}
function StartOwned([string]$Executable,$Arguments,[string]$Name){
    $stdout=Join-Path $evidence ($Name+'-console.log')
    $stderr=Join-Path $evidence ($Name+'-stderr.log')
    if('--log-file' -notin $Arguments){$Arguments=@('--log-file',(Join-Path $evidence ($Name+'.log')))+$Arguments}
    $process=Start-Process -FilePath $Executable -ArgumentList (QuoteArgs $Arguments) -WorkingDirectory $package -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $heldHandle=$process.Handle
    return @{process=$process;handle=$heldHandle;stdout=$stdout;stderr=$stderr;name=$Name;created=$process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()}
}
function WaitOwned($Entry,[int]$Seconds){
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {if($Entry.process.WaitForExit(250)){return $true}}while([DateTime]::UtcNow -lt $deadline)
    return $false
}
function EndExact($Entry){
    if($Entry.process.HasExited){return}
    if($null -eq ('RoomKitReleaseTestProcess' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoomKitReleaseTestProcess {
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TerminateProcess(IntPtr handle, uint exitCode);
}
'@
    }
    # The retained Windows HANDLE pins the exact process object; never reopen a PID.
    if(-not [RoomKitReleaseTestProcess]::TerminateProcess($Entry.handle,71) -or -not (WaitOwned $Entry 5)){throw ('Exact-handle cleanup failed: '+$Entry.name)}
}
function FreeTcpPort{
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    try{$listener.Start();return $listener.LocalEndpoint.Port}finally{$listener.Stop()}
}
function FreeUdpRange{
    for($attempt=0;$attempt -lt 100;$attempt++){
        $first=Get-Random -Minimum 45000 -Maximum 60000
        $held=New-Object Collections.ArrayList
        $usable=$true
        try{foreach($port in $first..($first+7)){$socket=New-Object Net.Sockets.UdpClient;[void]$held.Add($socket);$socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$port)))}}
        catch{$usable=$false}finally{foreach($socket in $held){$socket.Dispose()}}
        if($usable){return $first}
    }
    throw 'No free loopback UDP range found.'
}
function Api([string]$Action,$Payload=@{},[switch]$Anonymous){
    $headers=@{}
    if($script:token -and -not $Anonymous){$headers.Authorization='Bearer '+$script:token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$Action;payload=$Payload}|ConvertTo-Json -Depth 25 -Compress))
    try{return Invoke-RestMethod -Uri ($script:baseUrl+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65}
    catch{throw ('HTTP transport failed for '+$Action+'; credentials and response body suppressed.')}
}
function CaptureJournalProcess($Record,[string]$Kind){
    if($null -eq $Record -or -not $Record.verified -or [string]$Record.created_filetime -notmatch '^\d+$' -or [string]$Record.launch_id -notmatch '^[a-f0-9]{16,64}$'){throw 'Unverified native process ownership record.'}
    $expected=if($Kind -eq 'host'){@((Join-Path $package 'ManagedHost.exe'))}else{@((Join-Path $package 'games/shooter/Server.exe'),(Join-Path $package 'games/turns/Server.exe'))}
    $recordExecutable=[IO.Path]::GetFullPath([string]$Record.executable)
    if($recordExecutable -notin $expected){throw 'Native ownership executable is outside the expected package entries.'}
    if(($Kind -eq 'host' -and [int]$Record.parent_pid -ne $script:operator.process.Id) -or ($Kind -eq 'room' -and -not $script:knownHostPids.Contains([int]$Record.parent_pid))){throw 'Native ownership parent is not this test host/operator.'}
    foreach($entry in $script:nativeOwned){if($entry.process.Id -eq [int]$Record.pid -and $entry.created -eq [string]$Record.created_filetime){return $entry}}
    try{$process=[Diagnostics.Process]::GetProcessById([int]$Record.pid)}catch [ArgumentException]{return $null}
    $handle=$process.Handle
    if($process.HasExited){$process.Dispose();return $null}
    $creation=$process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
    $metadata=Get-CimInstance Win32_Process -Filter ('ProcessId = '+[int]$Record.pid) -OperationTimeoutSec 3
    $marker='(?<!\S)"?--launch-id='+[regex]::Escape([string]$Record.launch_id)+'"?(?=\s|$)'
    if($creation -ne [string]$Record.created_filetime -or $process.MainModule.FileName -ine $recordExecutable -or $null -eq $metadata -or [int]$metadata.ParentProcessId -ne [int]$Record.parent_pid -or -not [regex]::IsMatch([string]$metadata.CommandLine,$marker)){$process.Dispose();throw 'Native process identity did not match the private ownership journal.'}
    $entry=@{process=$process;handle=$handle;created=$creation;name=($Kind+'-'+$Record.launch_id);kind=$Kind}
    [void]$script:nativeOwned.Add($entry)
    if($Kind -eq 'host'){[void]$script:knownHostPids.Add($process.Id)}
    return $entry
}
function CaptureKnownChildren{
    $hostJournal=Join-Path $private 'host-running.json'
    if(Test-Path -LiteralPath $hostJournal){$record=Get-Content -LiteralPath $hostJournal -Encoding UTF8 -Raw|ConvertFrom-Json;[void](CaptureJournalProcess $record 'host')}
    $roomJournal=Join-Path $private 'processes.json'
    if(Test-Path -LiteralPath $roomJournal){
        $journal=Get-Content -LiteralPath $roomJournal -Encoding UTF8 -Raw|ConvertFrom-Json
        foreach($property in $journal.entries.PSObject.Properties){if($property.Value.owned.verified){[void](CaptureJournalProcess $property.Value.owned 'room')}}
    }
}
function WaitRoom([string]$RoomId){
    $deadline=[DateTime]::UtcNow.AddSeconds(50)
    do{
        $status=Api 'status'
        $room=@($status.payload.rooms|Where-Object room_id -eq $RoomId)[0]
        CaptureKnownChildren
        if($null -ne $room -and $room.state -eq 'READY'){return $room}
        if($null -ne $room -and $room.state -in @('FAILED','EXITED')){throw ('Native room failed: '+$room.code)}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    throw 'Native room READY timed out.'
}
function TestExportedUi([string]$Game,[string]$ConnectionPath){
    $entry=StartOwned (Join-Path $package ('clients/'+$Game+'/Client.exe')) @('--headless','--','--ui-smoke=true',('--game='+$Game),('--connection-config='+$ConnectionPath)) ($Game+'-exported-ui')
    try{
        Check (WaitOwned $entry 30) ($Game+' exported Client.exe UI completes')
        Check ($entry.process.ExitCode -eq 0 -and (Select-String -LiteralPath $entry.stdout -Pattern 'FRAMEWORK_UI_RESULT login_ready=true' -Quiet)) ($Game+' exported login UI initializes; no network/visual claim')
    }finally{if(-not $entry.process.HasExited){EndExact $entry};$entry.process.Dispose()}
}
function ReadReport($Client){
    if(Test-Path -LiteralPath $Client.report){try{return Get-Content -LiteralPath $Client.report -Encoding UTF8 -Raw|ConvertFrom-Json}catch{return $null}}
    return $null
}
function StartDriver([string]$Game,[string]$RoomId,[string]$Invite,$Manifest,$Connection){
    $directory=Join-Path $evidence $Game
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    $bootstrap=Join-Path $private ('driver-'+$Game+'.json')
    $report=Join-Path $directory 'report.json'
    SaveJson $bootstrap @{connection=$Connection;manifest=$Manifest;game_id=$Game;username=('release_'+$Game+'_'+$runId.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('Release '+$Game);invite_code=$Invite;register=$true;room_id=$RoomId;report_path=$report;control_directory=$directory;timeout_ms=240000}
    $entry=StartOwned $Godot @('--headless','--path',$project,'--script','res://tests/run_framework_clients.gd','--',('--test-config='+$bootstrap)) ($Game+'-source-driver')
    $entry.game=$Game;$entry.directory=$directory;$entry.report=$report
    [void]$script:clients.Add($entry)
    $deadline=[DateTime]::UtcNow.AddSeconds(75)
    do{
        $value=ReadReport $entry
        if($null -ne $value){
            if($value.phase -eq 'FAILED'){throw ('Source network driver failed: '+$Game+' code='+$value.code)}
            if($value.phase -eq 'IN_ROOM' -and $value.initial_join_ok -and $value.world.players.Count -ge 1){return $entry}
        }
        if($entry.process.HasExited){throw ('Source network driver exited: '+$Game)}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $deadline)
    throw ('Source driver admission timed out: '+$Game)
}
function CloseDriver($Entry){
    if(-not $Entry.process.HasExited){SaveJson (Join-Path $Entry.directory 'close.command.json') @{id='close';action='close'}}
    if(-not (WaitOwned $Entry 12)){throw ('Source driver graceful shutdown timed out: '+$Entry.game)}
}

New-Item -ItemType Directory -Force -Path $evidence|Out-Null
try{
    $checksums=Get-Content -LiteralPath (Join-Path $package 'checksums.json') -Encoding UTF8 -Raw|ConvertFrom-Json
    foreach($item in $checksums.files){
        $path=[IO.Path]::GetFullPath((Join-Path $package $item.path))
        if(-not $path.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $item.sha256){throw ('Package checksum mismatch: '+$item.path)}
    }
    Check ($checksums.files.Count -gt 0) ('native package checksums '+$checksums.files.Count)
    foreach($name in @('connection.json','server.crt')){
        $path=Join-Path $publicDirectory $name
        $publicSaved[$name]=@{exists=(Test-Path -LiteralPath $path -PathType Leaf);bytes=$null}
        if($publicSaved[$name].exists){$publicSaved[$name].bytes=[IO.File]::ReadAllBytes($path)}
    }
    & (Join-Path $package 'tools/protect_data.ps1') -ProjectRoot $package -DataRoot $private|Out-Null
    $udpFirst=FreeUdpRange
    $lobbyPort=FreeTcpPort
    do{$controlPort=FreeTcpPort}while($controlPort -eq $lobbyPort)
    do{$panelPort=FreeTcpPort}while($panelPort -in @($lobbyPort,$controlPort))
    $settings=@{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobbyPort;game_bind='127.0.0.1';control_port=$controlPort;udp_first=$udpFirst;udp_last=($udpFirst+7);max_rooms=4;asset_spaces=@{shooter='shooter';turns='turns'}}
    SaveJson (Join-Path $private 'config.json') $settings
    $script:baseUrl='http://127.0.0.1:'+$panelPort
    $script:operator=StartOwned (Join-Path $package 'Operator.exe') @('--headless','--log-file',(Join-Path $evidence 'operator.log'),'--',('--data-root='+$private),('--panel-port='+$panelPort)) 'operator'
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    $ready=$false
    do{
        $descriptor=Join-Path $private 'operator.json'
        if(Test-Path -LiteralPath $descriptor){
            $record=Get-Content -LiteralPath $descriptor -Encoding UTF8 -Raw|ConvertFrom-Json
            if([int]$record.pid -eq $script:operator.process.Id -and [int]$record.port -eq $panelPort){try{$ready=(Api 'setup.status' @{} -Anonymous).ok}catch{}}
        }
        if(-not $ready){Start-Sleep -Milliseconds 200}
    }while(-not $ready -and [DateTime]::UtcNow -lt $deadline -and -not $script:operator.process.HasExited)
    Check $ready 'native independent HTTP ready with private descriptor'
    foreach($database in @('accounts.sqlite','assets.sqlite')){Check (Test-Path -LiteralPath (Join-Path $private $database) -PathType Leaf) ('native SQLite initialized '+$database)}
    $public=Get-Content -LiteralPath (Join-Path $publicDirectory 'connection.json') -Encoding UTF8 -Raw|ConvertFrom-Json
    Check ($public.url -eq ('wss://127.0.0.1:'+$lobbyPort)) 'published WSS port is an integer after JSON configuration load'
    foreach($game in @('shooter','turns')){TestExportedUi $game (Join-Path $publicDirectory 'connection.json')}
    $password='Admin!'+[Guid]::NewGuid().ToString('N')
    $credentials=@{username=('release_admin_'+$runId.Substring(0,8));password=$password}
    $setup=Api 'setup.create' $credentials -Anonymous
    Check ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'native administrator setup'
    $login=Api 'admin.login' $credentials -Anonymous
    Check ($login.ok -and $login.payload.token) 'native administrator login'
    $script:token=$login.payload.token
    Check ((Api 'status').payload.host.state -eq 'STOPPED') 'native operator remains available with host stopped'
    Check (Api 'server.start').ok 'native managed host starts'
    CaptureKnownChildren
    Check ($script:knownHostPids.Count -eq 1) 'actual ManagedHost.exe identity verified and handle retained'
    $rooms=@{}
    foreach($game in @('shooter','turns')){
        $options=if($game -eq 'shooter'){@{game_id=$game;mode='ffa';map='depot';capacity=4}}else{@{game_id=$game;mode='sandbox';map='table';capacity=4}}
        $created=Api 'room.create' $options
        Check $created.ok ($game+' native room created')
        $room=WaitRoom $created.payload.room_id
        $rooms[$game]=$room
        Check (@($script:nativeOwned|Where-Object {$_.kind -eq 'room' -and $_.process.Id -eq [int]$room.pid}).Count -eq 1) ($game+' actual Server.exe identity verified at READY')
        $endpoints=@(Get-NetUDPEndpoint -LocalPort ([int]$room.port) -ErrorAction SilentlyContinue|Where-Object OwningProcess -eq ([int]$room.pid))
        Check ($endpoints.Count -ge 1) ($game+' native allocated UDP actually bound')
    }
    $invitation=Api 'invite.create' @{uses=4;expires_hours=1;reason='isolated native release acceptance'}
    Check ($invitation.ok -and $invitation.payload.invite_code.Length -eq 32) 'native registration invitation created'
    $index=Get-Content -LiteralPath (Join-Path $package 'artifacts/framework-games.json') -Encoding UTF8 -Raw|ConvertFrom-Json
    $connection=@{url=('wss://127.0.0.1:'+$lobbyPort);ca_certificate=(Join-Path $private 'server.crt');server_hostname='localhost';secure_enet=$true;managed=$true}
    foreach($game in @('shooter','turns')){
        $client=StartDriver $game $rooms[$game].room_id $invitation.payload.invite_code $index.$game.manifest $connection
        $report=ReadReport $client
        Check ($report.registration.ok -and $report.user_id -ne '') ($game+' source driver actually registers and logs in over native WSS')
        Check ($report.initial_join_ok -and $report.world.players.Count -ge 1) ($game+' source driver joins native ENet and receives replicated player')
    }
    $status=Api 'status'
    foreach($game in @('shooter','turns')){
        $room=@($status.payload.rooms|Where-Object room_id -eq $rooms[$game].room_id)[0]
        Check ([int]$room.heartbeats -gt 0 -and [int]$room.connected -ge 1) ($game+' native heartbeat and player count')
    }
    foreach($client in $script:clients){CloseDriver $client;Check ($client.process.ExitCode -eq 0) ($client.game+' source driver graceful exit 0')}
    Check (Api 'server.stop' @{immediate=$true;reason='native release test complete'}).ok 'native server stop accepted'
    $deadline=[DateTime]::UtcNow.AddSeconds(50)
    do{$status=Api 'status';if($status.payload.host.state -eq 'STOPPED'){break};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $deadline)
    Check ($status.payload.host.state -eq 'STOPPED') 'native host stopped and panel still responds'
    foreach($entry in $script:nativeOwned){Check $entry.process.HasExited ($entry.kind+' exact process handle confirms exit')}
    $heldUdp=New-Object Collections.ArrayList
    try{foreach($room in $rooms.Values){$socket=New-Object Net.Sockets.UdpClient;[void]$heldUdp.Add($socket);$socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,[int]$room.port)))};Check $true 'native UDP ports can be bound again'}finally{foreach($socket in $heldUdp){$socket.Dispose()}}
    [IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop',$utf8)
    Check ((WaitOwned $script:operator 30) -and $script:operator.process.ExitCode -eq 0) 'native Operator.exe graceful exit 0'
    $logs=@(Get-ChildItem -LiteralPath $evidence -File -Recurse -Filter '*stderr.log')+@(Get-ChildItem -LiteralPath (Join-Path $private 'logs') -File -Recurse -ErrorAction SilentlyContinue)
    foreach($log in $logs){Check (-not (Select-String -LiteralPath $log.FullName -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:' -Quiet)) ('no runtime error in '+$log.Name)}
}catch{
    if(-not $_.Exception.Message.StartsWith('FAIL ')){$script:failed++}
    $failure=$_.Exception.Message
    Write-Host ('FRAMEWORK_RELEASE_FAILURE '+$failure)
}finally{
    foreach($entry in $script:clients){
        if(-not $entry.process.HasExited){try{CloseDriver $entry}catch{$cleanupFailed=$true;Write-Host ('CLEANUP '+$_.Exception.Message);try{EndExact $entry}catch{Write-Host ('CLEANUP '+$_.Exception.Message)}}}
    }
    if($null -ne $script:operator){
        if(-not $script:operator.process.HasExited){
            try{CaptureKnownChildren}catch{$cleanupFailed=$true;Write-Host ('CLEANUP '+$_.Exception.Message)}
            [IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop',$utf8)
            if(-not (WaitOwned $script:operator 60)){
                $cleanupFailed=$true;Write-Host 'CLEANUP operator graceful shutdown watchdog expired.'
                try{CaptureKnownChildren}catch{Write-Host ('CLEANUP '+$_.Exception.Message)}
                try{EndExact $script:operator}catch{Write-Host ('CLEANUP '+$_.Exception.Message)}
            }
        }
        # The operator can exit unexpectedly; retained, verified child handles
        # still identify only this test's processes and prevent PID reuse.
        foreach($entry in @($script:nativeOwned|Sort-Object {$_.kind -eq 'host'})){
            if(-not $entry.process.HasExited){$cleanupFailed=$true;try{EndExact $entry}catch{Write-Host ('CLEANUP '+$_.Exception.Message)}}
        }
    }
    foreach($name in $publicSaved.Keys){
        $path=Join-Path $publicDirectory $name
        try{if($publicSaved[$name].exists){[IO.File]::WriteAllBytes($path,$publicSaved[$name].bytes)}elseif(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}}catch{$cleanupFailed=$true;Write-Host ('CLEANUP could not restore public file '+$name)}
    }
    foreach($entry in @($script:clients)+@($script:nativeOwned)+@($script:operator)){
        if($null -ne $entry){if(-not $entry.process.HasExited){$cleanupFailed=$true};$entry.process.Dispose()}
    }
    if($cleanupFailed){$script:failed++}
    SaveJson (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;failure=$failure;cleanup_failed=$cleanupFailed;checks=@($script:checks);bundle=$package;data_root=$private;native_server_test='actual exported executables; see individual checks';native_client_test='exported login UI initialization only';network_clients='source driver with explicit bundle manifests';browser_visual_test='not run';evidence=$evidence}
    Write-Host ('FRAMEWORK_RELEASE_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
if($script:failed){exit 1}
exit 0
