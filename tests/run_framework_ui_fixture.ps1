[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Bundle)
# Isolated genuine native programs for manual/browser UI acceptance.
# This fixture never initializes an administrator or starts a game host itself.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not [IO.Path]::IsPathRooted($Bundle)){throw '-Bundle must be an absolute path.'}
$package=[IO.Path]::GetFullPath($Bundle).TrimEnd('\','/')
if(-not $package.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Extract the native bundle inside this repository.'}
$cursor=$package
while($cursor.Length -ge $project.Length){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Package ancestor is a reparse point.'}
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
foreach($relative in @('project.godot','checksums.json','Operator.exe','Operator.pck','ManagedHost.exe','ManagedHost.pck','artifacts/framework-games.json','tools/protect_data.ps1','clients/shooter/Client.exe','clients/shooter/Client.pck','clients/turns/Client.exe','clients/turns/Client.pck')){
    if(-not (Test-Path -LiteralPath (Join-Path $package $relative) -PathType Leaf)){throw ('Incomplete native package: '+$relative)}
}
foreach($relative in @('data','artifacts','artifacts/client')){
    $path=Join-Path $package $relative
    if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Package runtime path is a reparse point.'}
}
$active=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -and $_.ExecutablePath.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase)})
if($active.Count){throw 'A process from this bundle already exists. Use another independent extraction.'}
$runId=[Guid]::NewGuid().ToString('N')
$private=Join-Path $package ('data/ui-test-'+$runId)
$evidence=Join-Path $project ('logs/framework-ui-'+$runId)
$commands=Join-Path $private 'commands'
$commandResults=Join-Path $private 'command-results'
$contextPath=Join-Path $private 'context.json'
$connectionPath=Join-Path $private 'connection-public.json'
$publicDirectory=Join-Path $package 'artifacts/client'
$utf8=New-Object Text.UTF8Encoding($false)
$script:operator=$null
$script:clients=New-Object Collections.ArrayList
$script:nativeOwned=New-Object Collections.ArrayList
$script:knownHostPids=New-Object Collections.Generic.HashSet[int]
$script:commandIds=New-Object Collections.Generic.HashSet[string]
$publicSaved=@{}
$failure=''
$cleanupFailed=$false
$forcedCleanup=$false
$ready=$false
$timedOut=$false

function SaveJson([string]$Path,$Value){
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 40 -Compress),$utf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function QuoteArgs($Values){return @($Values|ForEach-Object {'"'+([string]$_ -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'})}

function StartOwned([string]$Executable,$Arguments,[string]$Name,[switch]$Visible){
    $stdout=Join-Path $evidence ($Name+'-console.log')
    $stderr=Join-Path $evidence ($Name+'-stderr.log')
    if('--log-file' -notin $Arguments){$Arguments=@('--log-file',(Join-Path $evidence ($Name+'.log')))+$Arguments}
    $process=Start-Process -FilePath $Executable -ArgumentList (QuoteArgs $Arguments) -WorkingDirectory $package -WindowStyle $(if($Visible){'Normal'}else{'Hidden'}) -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
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
    if($null -eq ('RoomKitUiFixtureProcess' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoomKitUiFixtureProcess {
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TerminateProcess(IntPtr handle, uint exitCode);
}
'@
    }
    # The retained Windows HANDLE pins the exact process object; never reopen a PID.
    if(-not [RoomKitUiFixtureProcess]::TerminateProcess($Entry.handle,71) -or -not (WaitOwned $Entry 5)){throw ('Exact-handle cleanup failed: '+$Entry.name)}
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

function RefreshPublicConnection{
    $published=Join-Path $publicDirectory 'connection.json'
    if(-not (Test-Path -LiteralPath $published)){return}
    $value=Get-Content -LiteralPath $published -Encoding UTF8 -Raw|ConvertFrom-Json
    if(-not $value.url -or -not $value.server_hostname){throw 'Public connection file is incomplete.'}
    $value.ca_certificate=Join-Path $private 'server.crt'
    SaveJson $connectionPath $value
}
function WriteFixtureState([string]$Phase){
    $visible=@($script:clients|ForEach-Object {@{name=$_.name;game=$_.game;pid=$_.process.Id;alive=(-not $_.process.HasExited)}})
    SaveJson (Join-Path $private 'fixture-state.json') @{phase=$Phase;operator_pid=$(if($null -ne $script:operator){$script:operator.process.Id}else{0});clients=$visible;captured_native_children=$script:nativeOwned.Count;deadline_utc=$deadline.ToString('o')}
}
function LaunchClient([string]$Game,[string]$CommandId){
    if(@($script:clients|Where-Object {-not $_.process.HasExited}).Count -ge 8){return @{ok=$false;code='CLIENT_LIMIT'}}
    RefreshPublicConnection
    $name=$Game+'-'+$CommandId
    # A normal window is intentional: these clients are for human UI acceptance.
    # Passwords/tokens never appear in arguments, environment variables or logs.
    $entry=StartOwned (Join-Path $package ('clients/'+$Game+'/Client.exe')) @('--',('--game='+$Game),('--connection-config='+$connectionPath)) $name -Visible
    $entry.game=$Game
    [void]$script:clients.Add($entry)
    return @{ok=$true;code='';pid=$entry.process.Id;game=$Game}
}
function PollCommands{
    foreach($file in @(Get-ChildItem -LiteralPath $commands -File -Filter '*.command.json'|Sort-Object Name)){
        $id=$file.Name.Substring(0,$file.Name.Length-'.command.json'.Length)
        if($id -notmatch '^[A-Za-z0-9_-]{1,64}$' -or $script:commandIds.Contains($id)){continue}
        if($file.Length -gt 4096){SaveJson (Join-Path $commandResults ($id+'.json')) @{ok=$false;code='COMMAND_TOO_LARGE'};[void]$script:commandIds.Add($id);continue}
        try{$command=Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Raw|ConvertFrom-Json}catch{continue}
        # Only these named actions are accepted. Payload paths and arguments
        # cannot replace the fixed executable or this fixture connection file.
        $result=switch([string]$command.action){
            'launch_shooter' {LaunchClient 'shooter' $id}
            'launch_turns' {LaunchClient 'turns' $id}
            default {@{ok=$false;code='UNKNOWN_COMMAND'}}
        }
        SaveJson (Join-Path $commandResults ($id+'.json')) $result
        [void]$script:commandIds.Add($id)
        WriteFixtureState 'READY'
    }
}
function CloseClient($Entry){
    if($Entry.process.HasExited){return}
    $Entry.process.Refresh()
    [void]$Entry.process.CloseMainWindow()
    if(-not (WaitOwned $Entry 15)){
        $script:forcedCleanup=$true
        EndExact $Entry
    }
}

New-Item -ItemType Directory -Force -Path $evidence|Out-Null
try{
    $checksums=Get-Content -LiteralPath (Join-Path $package 'checksums.json') -Encoding UTF8 -Raw|ConvertFrom-Json
    foreach($item in $checksums.files){
        $path=[IO.Path]::GetFullPath((Join-Path $package $item.path))
        if(-not $path.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $item.sha256){throw ('Package checksum mismatch: '+$item.path)}
    }
    foreach($name in @('connection.json','server.crt')){
        $path=Join-Path $publicDirectory $name
        $publicSaved[$name]=@{exists=(Test-Path -LiteralPath $path -PathType Leaf);bytes=$null}
        if($publicSaved[$name].exists){$publicSaved[$name].bytes=[IO.File]::ReadAllBytes($path)}
    }
    & (Join-Path $package 'tools/protect_data.ps1') -ProjectRoot $package -DataRoot $private|Out-Null
    New-Item -ItemType Directory -Force -Path $commands,$commandResults|Out-Null
    $udpFirst=FreeUdpRange
    $lobbyPort=FreeTcpPort
    do{$controlPort=FreeTcpPort}while($controlPort -eq $lobbyPort)
    do{$panelPort=FreeTcpPort}while($panelPort -in @($lobbyPort,$controlPort))
    SaveJson (Join-Path $private 'config.json') @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobbyPort;game_bind='127.0.0.1';control_port=$controlPort;udp_first=$udpFirst;udp_last=($udpFirst+7);max_rooms=8;asset_spaces=@{shooter='shooter';turns='turns'}}
    $url='http://127.0.0.1:'+$panelPort
    $script:operator=StartOwned (Join-Path $package 'Operator.exe') @('--headless','--log-file',(Join-Path $evidence 'operator.log'),'--',('--data-root='+$private),('--panel-port='+$panelPort),('--operator-log-path='+(Join-Path $evidence 'operator.log'))) 'operator'
    $startupDeadline=[DateTime]::UtcNow.AddSeconds(60)
    do{
        $descriptor=Join-Path $private 'operator.json'
        if(Test-Path -LiteralPath $descriptor){
            try{
                $record=Get-Content -LiteralPath $descriptor -Encoding UTF8 -Raw|ConvertFrom-Json
                if([int]$record.pid -eq $script:operator.process.Id -and [int]$record.port -eq $panelPort){
                    $response=Invoke-RestMethod -Uri ($url+'/api') -Method Post -ContentType 'application/json' -Body '{"action":"setup.status","payload":{}}' -TimeoutSec 3
                    $ready=$response.ok -and -not $response.payload.initialized
                }
            }catch{}
        }
        if(-not $ready){Start-Sleep -Milliseconds 200}
    }while(-not $ready -and [DateTime]::UtcNow -lt $startupDeadline -and -not $script:operator.process.HasExited)
    if(-not $ready){throw 'Fresh native Operator did not expose the uninitialized setup screen.'}
    RefreshPublicConnection
    $suffix=$runId.Substring(0,8)
    $admin=@{username=('ui_admin_'+$suffix);password=('Admin!'+[Guid]::NewGuid().ToString('N'))}
    $players=@{}
    foreach($name in @('shooter_one','shooter_two','turns_one','turns_two')){$players[$name]=@{username=('ui_'+$name+'_'+$suffix);password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('UI '+$name)}}
    $deadline=[DateTime]::UtcNow.AddMinutes(40)
    SaveJson $contextPath @{url=$url;privateRoot=$private;evidence=$evidence;publicConnectionPath=$connectionPath;commandsDirectory=$commands;commandResultsDirectory=$commandResults;closeRequest=(Join-Path $private 'close.request');operator_pid=$script:operator.process.Id;bundle=$package;admin=$admin;players=$players;deadline_utc=$deadline.ToString('o')}
    WriteFixtureState 'READY'
    # No credentials or context contents are printed. The caller derives the
    # private context path from the bundle and this non-secret fixture ID.
    Write-Output ('FRAMEWORK_UI_FIXTURE_READY id='+$runId+' url='+$url+' evidence='+$evidence)
    $nextInspect=[DateTime]::UtcNow
    $inspectErrors=0
    while([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath (Join-Path $private 'close.request'))){
        if($script:operator.process.HasExited){throw 'Native Operator exited before fixture close request.'}
        PollCommands
        if([DateTime]::UtcNow -ge $nextInspect){
            try{CaptureKnownChildren;RefreshPublicConnection;$inspectErrors=0}catch{$inspectErrors++;if($inspectErrors -ge 3){throw 'Repeated private ownership/configuration inspection failure.'}}
            WriteFixtureState 'READY'
            $nextInspect=[DateTime]::UtcNow.AddSeconds(1)
        }
        Start-Sleep -Milliseconds 200
    }
    $timedOut=[DateTime]::UtcNow -ge $deadline
}catch{
    $failure=$_.Exception.Message
    Write-Output ('FRAMEWORK_UI_FIXTURE_FAILURE '+$failure)
}finally{
    foreach($entry in $script:clients){try{CloseClient $entry}catch{$cleanupFailed=$true;Write-Output ('CLEANUP '+$_.Exception.Message);try{EndExact $entry}catch{Write-Output ('CLEANUP '+$_.Exception.Message)}}}
    if($null -ne $script:operator){
        if(-not $script:operator.process.HasExited){
            try{CaptureKnownChildren}catch{$cleanupFailed=$true;Write-Output ('CLEANUP '+$_.Exception.Message)}
            [IO.File]::WriteAllText((Join-Path $private 'operator-stop.request'),'stop',$utf8)
            if(-not (WaitOwned $script:operator 60)){
                $forcedCleanup=$true
                try{CaptureKnownChildren}catch{$cleanupFailed=$true;Write-Output ('CLEANUP '+$_.Exception.Message)}
                try{EndExact $script:operator}catch{$cleanupFailed=$true;Write-Output ('CLEANUP '+$_.Exception.Message)}
            }
        }
        foreach($entry in @($script:nativeOwned|Sort-Object {$_.kind -eq 'host'})){
            if(-not $entry.process.HasExited){$forcedCleanup=$true;try{EndExact $entry}catch{$cleanupFailed=$true;Write-Output ('CLEANUP '+$_.Exception.Message)}}
        }
    }
    foreach($name in $publicSaved.Keys){
        $path=Join-Path $publicDirectory $name
        try{if($publicSaved[$name].exists){[IO.File]::WriteAllBytes($path,$publicSaved[$name].bytes)}elseif(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}}catch{$cleanupFailed=$true;Write-Output ('CLEANUP public file restore failed: '+$name)}
    }
    $live=0
    foreach($entry in @($script:clients)+@($script:nativeOwned)+@($script:operator)){
        if($null -ne $entry){if(-not $entry.process.HasExited){$live++;$cleanupFailed=$true};$entry.process.Dispose()}
    }
    SaveJson (Join-Path $evidence 'fixture-result.json') @{ready=$ready;failure=$failure;timed_out=$timedOut;cleanup_failed=$cleanupFailed;forced_cleanup=$forcedCleanup;live_owned_processes=$live;client_count=$script:clients.Count;captured_native_children=$script:nativeOwned.Count;ui_actions='performed externally, not asserted by fixture'}
    Write-Output ('FRAMEWORK_UI_FIXTURE_STOPPED cleanup_failed='+$cleanupFailed+' forced_cleanup='+$forcedCleanup+' live_owned='+$live+' evidence='+$evidence)
}
if($failure -or $cleanupFailed -or $forcedCleanup){exit 1}
exit 0
