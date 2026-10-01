param(
    [Parameter(Mandatory=$true)][ValidateSet('prepare','verify')][string]$Phase,
    [Parameter(Mandatory=$true)][string]$ContextPath,
    [string]$Godot='',
    [string]$PlayerDirectory=''
)
# Windows -> Linux acceptance. Only the administrator HTTP API is SSH-forwarded;
# player WSS and DTLS/UDP go directly to the Linux LAN address. No sudo/firewall,
# installation, shared game index, production data or shared context pointer.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('/','\')
. (Join-Path $project 'tests/support/portable.ps1')
. (Join-Path $project 'tests/support/client_harness.ps1')
$Godot=Rk-Godot $Godot
$ctx=Rk-ReadJson $ContextPath
if($null -eq $ctx -or $ctx.ssh_target -ne 'zhao@192.168.10.105' -or
   $ctx.server -ne '192.168.10.105' -or $ctx.source_id -notmatch '^[0-9a-f]{12}-lan-[0-9a-f]{6}$' -or
   $ctx.instance -notmatch '^lan-[0-9a-f]{6}$' -or $ctx.panel -ne 28491 -or $ctx.forward -ne 28491 -or $ctx.lobby -ne 28500) {
    throw 'This LAN fixture requires its explicit, scoped preparation manifest.'
}
$root=[IO.Path]::GetFullPath([string]$ctx.local_root).TrimEnd('/','\')
if(-not (Rk-Inside $root (Join-Path $project 'data')) -or $root -match '(^|[\\/])\.\.([\\/]|$)' -or
   [IO.Path]::GetFileName($root) -notmatch '^codex-linux-lan-[0-9]{14}-[0-9a-f]{6}$') {throw 'Refused LAN data folder.'}
function AssertNoLink([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'LAN target passes through a link.'}
        $parent=[IO.Path]::GetDirectoryName($cursor); if($parent -eq $cursor){break}; $cursor=$parent
    }
}
AssertNoLink $root
Rk-ProtectData $project $root
$evidence=Join-Path $root ('evidence-'+$Phase+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $evidence | Out-Null
$adminFile=Join-Path $root 'admin.json'
$public=Join-Path $root 'public'
$linuxIndex=Join-Path $root 'games-linux.json'
foreach($path in @($adminFile,$public,$linuxIndex,(Join-Path $public 'connection.json'),(Join-Path $public 'server.crt'),(Join-Path $root 'source'),(Join-Path $root 'games-windows.json'))){AssertNoLink $path}
if($PlayerDirectory){
    $PlayerDirectory=[IO.Path]::GetFullPath($PlayerDirectory)
    if(-not (Rk-Inside $PlayerDirectory (Join-Path $project 'artifacts'))){throw 'Exported client must be in its separate artifacts folder.'}
    foreach($item in Get-ChildItem -LiteralPath $PlayerDirectory -Recurse -Force){AssertNoLink $item.FullName}
    AssertNoLink $PlayerDirectory
}
$passed=0; $failed=0; $pending=$false; $tunnel=$null; $room=$null
$clients=New-Object Collections.ArrayList
$exports=New-Object Collections.ArrayList
function Check([bool]$Value,[string]$Label) {
    if($Value){$script:passed++;Write-Output ('PASS '+$Label)}else{$script:failed++;Write-Output ('FAIL '+$Label);throw $Label}
}
function DirectTcp {
    $socket=New-Object Net.Sockets.TcpClient
    try {
        $task=$socket.ConnectAsync([string]$ctx.server,[int]$ctx.lobby)
        if(-not $task.Wait(3000)){return $false}
        return $socket.Connected
    } catch {return $false} finally {$socket.Dispose()}
}
try {
    $reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,[int]$ctx.forward)
    try{$reservation.Start()}finally{$reservation.Stop()}
    $tunnel=Rk-StartHidden 'ssh.exe' @('-N','-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=10','-L',('127.0.0.1:'+ $ctx.forward +':127.0.0.1:'+ $ctx.panel),$ctx.ssh_target) (Join-Path $evidence 'ssh.out') (Join-Path $evidence 'ssh.err')
    $heldHandle=$tunnel.Handle
    Start-Sleep -Milliseconds 700
    Check (-not $tunnel.HasExited) 'own SSH tunnel stays up; panel remains loopback-only'
    $script:RkApiUrl='http://127.0.0.1:'+$ctx.forward
    Check (Rk-WaitApi 15) 'Linux Operator responds through SSH'
    if(-not (Rk-Api 'setup.status' @{} -Anonymous).payload.initialized) {
        if($Phase -ne 'prepare'){throw 'Run prepare first.'}
        $admin=@{username=('lanadmin_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Adm!'+[Guid]::NewGuid().ToString('N'))}
        Rk-SaveJson $adminFile $admin
        Check (Rk-Api 'setup.create' $admin -Anonymous).ok 'new isolated Linux administrator created'
    }
    Check (Rk-AdminLogin $adminFile) 'isolated administrator logs in'
    $state=Rk-Api 'status'
    Check $state.ok 'real server status is available'
    if($state.payload.host.state -ne 'RUNNING'){Check (Rk-Api 'server.start').ok 'Linux managed host starts'}
    $hostState=Rk-WaitHost 'RUNNING'
    Check ($null -ne $hostState -and $hostState.host.state -eq 'RUNNING') 'real Linux lobby is running'
    $remote=('roomkit/src/'+$ctx.source_id+'/data/instance-'+$ctx.instance)
    foreach($name in @('connection.json','server.crt')) {
        & scp -o BatchMode=yes ($ctx.ssh_target+':'+$remote+'/public/'+$name) (Join-Path $public $name)
        if($LASTEXITCODE -ne 0){throw 'Public connection transfer failed.'}
    }
    & scp -o BatchMode=yes ($ctx.ssh_target+':'+$remote+'/games.json') $linuxIndex
    if($LASTEXITCODE -ne 0){throw 'Linux game manifest transfer failed.'}
    $connection=Rk-Connection $public
    Check ($connection.url -eq ('wss://'+$ctx.server+':'+$ctx.lobby)) 'player WSS targets the Linux LAN IP directly'
    $reachable=DirectTcp
    Rk-SaveJson (Join-Path $root 'network-gate.json') @{direct_lobby_tcp=$reachable;server=$ctx.server;port=$ctx.lobby;phase=$Phase}
    if(-not $reachable){
        $pending=$true
        Write-Output 'PENDING direct LAN TCP 28500 is unreachable; WSS/UDP gameplay not tested; firewall unchanged'
    } elseif($Phase -eq 'verify') {
        $index=Rk-ReadJson $linuxIndex
        $localIndex=Rk-ReadJson (Join-Path $root 'games-windows.json')
        foreach($entry in @($index,$localIndex)){
            Check ($null -ne $entry -and $null -ne $entry.shooter.manifest -and $entry.shooter.manifest.game_id -eq 'shooter' -and [string]$entry.shooter.manifest.build_id -match '^shooter-dev-002-src-[0-9a-f]{12}$' -and [string]$entry.shooter.manifest.compatibility_id -ne '' -and [int]$entry.shooter.manifest.game_protocol -gt 0) 'game manifest is present and valid'
        }
        Check (Rk-Inside $localIndex.shooter.project (Join-Path $root 'source')) 'prepared Windows game stays inside this snapshot'
        AssertNoLink $localIndex.shooter.project
        $prepared=Rk-ReadJson (Join-Path $localIndex.shooter.project 'game_manifest.json')
        Check ($null -ne $prepared -and $prepared.build_id -eq $localIndex.shooter.manifest.build_id) 'prepared game manifest matches Windows index'
        foreach($key in @('game_id','build_id','compatibility_id','game_protocol')){Check ([string]$index.shooter.manifest.$key -eq [string]$localIndex.shooter.manifest.$key) ('two platforms agree on '+$key)}
        $invite=Rk-Api 'invite.create' @{uses=2;expires_hours=1;reason='isolated Windows to Linux LAN test'}
        Check $invite.ok 'invitation for two isolated LAN test accounts created'
        for($n=0;$n -lt 2;$n++) {
            $settings=@{username=('lanplayer_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Play!'+[Guid]::NewGuid().ToString('N'));display_name=('LAN '+$n);invite_code=$invite.payload.invite_code;register=$true}
            $client=Rk-StartClient $Godot (Join-Path $root 'source') $evidence ('player-'+$n) 'shooter' $connection $index.shooter.manifest $settings
            [void]$clients.Add($client)
            $report=Rk-WaitReport $client {param($r) $r.ok -and $r.phase -eq 'LOBBY'} 45
            Check ($null -ne $report) ('Windows player '+$n+' registers and logs into Linux over WSS')
            $client.user_id=$report.user_id
        }
        Check (Rk-Api 'asset.adjust' @{user_id=$clients[0].user_id;game_id='shooter';coins_delta=500;xp_delta=0;reason='LAN purchase test';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'test player receives 500 credits'
        Check (Rk-Command $clients[0] 'read').ok 'player refreshes assets after administrator funding'
        $purchaseId=[Guid]::NewGuid().ToString('N')
        $purchase=Rk-Command $clients[0] 'purchase' @{item_id='smg';operation_id=$purchaseId}
        Check ($null -ne $purchase -and $purchase.ok -and $purchase.state.credits -eq 400) 'real player purchase debits catalog price of 100 credits'
        $replay=Rk-Command $clients[0] 'purchase' @{item_id='smg';operation_id=$purchaseId}
        Check ($null -ne $replay -and $replay.ok -and $replay.state.credits -eq 400) 'repeated purchase does not debit twice'
        $selected=Rk-Command $clients[0] 'select' @{slot='primary';item_id='smg';operation_id=[Guid]::NewGuid().ToString('N')}
        Check ($null -ne $selected -and $selected.ok) 'real player weapon selection succeeds'
        $room=Rk-Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=4}
        Check $room.ok 'Linux shooter room is created'
        $ready=Rk-WaitRoom $room.payload.room_id
        Check ($null -ne $ready -and $ready.state -eq 'READY') 'Linux room binds its allocated UDP port before READY'
        foreach($client in $clients){$joined=Rk-Command $client 'join' @{room_id=$room.payload.room_id} 25;Check ($null -ne $joined -and $joined.ok) ('Windows '+$client.name+' joins over direct DTLS/UDP')}
        foreach($client in $clients){$report=Rk-WaitReport $client {param($r) $ids=@($r.world.players.user_id);$r.phase -eq 'IN_ROOM' -and $ids -contains $clients[0].user_id -and $ids -contains $clients[1].user_id} 15;Check ($null -ne $report) ('Windows '+$client.name+' sees both registered players')}
        foreach($client in $clients){$left=Rk-Command $client 'leave' @{} 15;Check ($null -ne $left -and $left.ok) ('Windows '+$client.name+' returns to lobby')}
        if($PlayerDirectory){
            $version=Rk-ReadJson (Join-Path $PlayerDirectory 'client-version.json')
            Check ($null -ne $version -and $version.build_id -eq $index.shooter.manifest.build_id) 'exported Client.exe directory matches Linux build'
            $fresh=Join-Path $evidence 'fresh-client'
            Copy-Item -LiteralPath $PlayerDirectory -Destination $fresh -Recurse
            $invite=Rk-Api 'invite.create' @{uses=2;expires_hours=1;reason='exported Windows LAN clients'}
            Check $invite.ok 'two exported-client invitations created'
            for($n=0;$n -lt 2;$n++){
                $plan=Join-Path $evidence ('export-'+$n+'.plan.json')
                $report=Join-Path $evidence ('export-'+$n+'.report.json')
                Rk-SaveJson $plan @{username=('lanexe_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Play!'+[Guid]::NewGuid().ToString('N'));display_name=('LAN EXE '+$n);invite_code=$invite.payload.invite_code;register=$true;room_id=$room.payload.room_id;expect_players=2;hold_ms=4000;after='leave';timeout_ms=90000;report_path=$report}
                $process=Rk-StartHidden (Join-Path $fresh 'Client.exe') @('--headless','--',('--autoplay='+$plan)) (Join-Path $evidence ('export-'+$n+'.out')) (Join-Path $evidence ('export-'+$n+'.err'))
                [void]$exports.Add(@{process=$process;plan=$plan;report=$report;n=$n})
            }
            $deadline=[DateTime]::UtcNow.AddSeconds(120)
            while(@($exports|Where-Object {-not $_.process.HasExited}).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
            foreach($export in $exports){
                $reply=Rk-ReadJson $export.report
                Check ($export.process.HasExited -and $export.process.ExitCode -eq 0 -and $null -ne $reply -and $reply.ok -and $reply.stage -eq 'left_room' -and $reply.left_state -eq 'LOBBY') ('exported Windows client '+$export.n+' registers, joins and leaves Linux')
                Check (-not (Select-String -LiteralPath (Join-Path $evidence ('export-'+$export.n+'.err')) -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) ('exported client '+$export.n+' has no runtime script errors')
            }
            $one=Rk-ReadJson $exports[0].report;$two=Rk-ReadJson $exports[1].report
            Check ($one.players -contains $two.user_id -and $two.players -contains $one.user_id) 'exported clients see each other over direct LAN UDP'
        }
    }
} catch {if($failed -eq 0){$failed++};Write-Output ('LAN_ERROR '+$_.Exception.Message)} finally {
    foreach($export in $exports){if(-not $export.process.HasExited){$export.process.Kill();[void]$export.process.WaitForExit(5000);$failed++};Remove-Item -LiteralPath $export.plan -ErrorAction SilentlyContinue}
    foreach($client in $clients){try{if(-not (Rk-StopClient $client)){$failed++}}catch{$failed++}}
    foreach($client in $clients){if(Select-String -LiteralPath (Join-Path $client.directory 'stderr.log') -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet){$failed++;Write-Output ('FAIL '+$client.name+' runtime script errors')}}
    if($null -ne $room -and $room.ok){try{
        if(-not (Rk-Api 'room.stop' @{room_id=$room.payload.room_id;reason='LAN test cleanup'}).ok){throw 'Room stop rejected.'}
        $end=[DateTime]::UtcNow.AddSeconds(40)
        do{$status=Rk-Api 'status';if(-not $status.ok){throw 'Cleanup status unavailable.'};$rooms=@($status.payload.rooms|Where-Object {$_.room_id -eq $room.payload.room_id -and -not $_.cleaned});$cleanup=$status.payload.session_cleanup;if($rooms.Count -eq 0 -and $null -ne $cleanup -and $cleanup.pending -eq 0 -and $cleanup.running -eq 0){break};Start-Sleep -Milliseconds 300}while([DateTime]::UtcNow -lt $end)
        Rk-SaveJson (Join-Path $evidence 'cleanup.json') @{rooms=@($status.payload.rooms|Where-Object room_id -eq $room.payload.room_id);cleanup=$cleanup}
        if($rooms.Count -ne 0 -or $null -eq $cleanup -or $cleanup.pending -ne 0 -or $cleanup.running -ne 0 -or $cleanup.failed -ne 0){throw 'Room/session cleanup incomplete.'}
        Write-Output 'PASS own room resources reclaimed and all session cleanups confirmed';$passed++
    }catch{$failed++;Write-Output ('CLEANUP_ERROR '+$_.Exception.Message)}}
    if($null -ne $tunnel){if(-not $tunnel.HasExited){$tunnel.Kill();if(-not $tunnel.WaitForExit(5000)){$failed++}};$tunnel.Dispose()}
    Rk-SaveJson (Join-Path $evidence 'result.json') @{phase=$Phase;passed=$passed;failed=$failed;pending=$pending}
    Write-Output ('LINUX_LAN_RESULT phase='+$Phase+' passed='+$passed+' failed='+$failed+' pending='+$pending+' evidence='+$evidence)
}
if($failed -gt 0){exit 1};if($pending){exit 2};exit 0
