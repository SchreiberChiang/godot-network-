param([Parameter(Mandatory=$true)][string]$ContextPath,[switch]$FullRound,[string]$PreparedPlayer='')
# A scoped exported-server fixture. Never adopts the existing source/LAN service.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$ctx=Rk-ReadJson $ContextPath
if($null -eq $ctx -or $ctx.build -notmatch '^[0-9]{14}-[0-9a-f]{8}$' -or $ctx.release -ne ('linux-'+$ctx.build) -or
   $ctx.instance -notmatch '^export-[0-9a-f]{8}$' -or $ctx.ssh_target -ne 'zhao@192.168.10.105' -or
   $ctx.server -ne '192.168.10.105'){throw 'Explicit isolated exported-package context required.'}
$legacyPorts=($ctx.panel -eq 28691 -and $ctx.lobby -eq 28700 -and $ctx.control -eq 28701)
$reviewPorts=($ctx.panel -eq 28991 -and $ctx.lobby -eq 28900 -and $ctx.control -eq 28901)
$publicGamePorts=($ctx.panel -eq 28991 -and $ctx.lobby -eq 28300 -and $ctx.control -eq 28301)
if(-not($legacyPorts -or $reviewPorts -or $publicGamePorts)){throw 'Only reserved acceptance port sets are supported.'}
$pointerPath=Join-Path $project 'artifacts/linux-package-playtest.json'
$livePointer=Rk-ReadJson $pointerPath
if((Test-Path -LiteralPath $pointerPath) -and $null -eq $livePointer){throw 'Active playtest pointer cannot be read safely.'}
if($null -ne $livePointer -and ($ctx.instance -eq $livePointer.instance -or $ctx.panel -eq $livePointer.panel)){throw 'Acceptance must not use the active playtest instance or panel.'}
$panelUrl='http://127.0.0.1:'+([int]$ctx.panel)
$package=[IO.Path]::GetFullPath([string]$ctx.package)
if(-not(Rk-Inside $package (Join-Path $project 'artifacts'))){throw 'Package must be an ignored build in this repository.'}
$metadata=Rk-ReadJson (Join-Path $package 'linux-package.json')
if($null -eq $metadata -or $metadata.build -ne $ctx.build){throw 'Package build differs from context.'}
$sourceIndex=[IO.Path]::GetFullPath([string]$ctx.source_index)
$expectedIndex=Join-Path $project ('artifacts/linux-server-build-'+$ctx.build+'/games-source.json')
if($sourceIndex -ne [IO.Path]::GetFullPath($expectedIndex)){throw 'Prepared source index must belong to this exact package build.'}
foreach($path in @($package,$sourceIndex)){
    $cursor=$path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked acceptance input rejected.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
}
if($PreparedPlayer){
    $prepared=[IO.Path]::GetFullPath($PreparedPlayer).TrimEnd('\','/')
    $paired=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($package)) 'PlayerClient')).TrimEnd('\','/')
    if($prepared -ne $paired -or -not(Rk-Inside $prepared (Join-Path $project 'artifacts/deployments'))){throw 'Prepared client must be paired with this exact server directory.'}
    $cursor=$prepared
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked prepared client rejected.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    $versionPath=Join-Path $prepared 'client-version.json'
    if((Get-Item -LiteralPath $versionPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked client version rejected.'}
    $preparedVersion=Rk-ReadJson $versionPath
    if($null -eq $preparedVersion -or $preparedVersion.build_id -cne $metadata.games.shooter){throw 'Prepared client build does not match server.'}
    foreach($name in @('Client.exe','Client.pck')){
        $entry=@($preparedVersion.generated_files | Where-Object {$_.path -ceq $name})
        $source=Join-Path $prepared $name
        if($entry.Count -ne 1 -or $entry[0].sha256 -cnotmatch '^[0-9a-f]{64}$' -or ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $entry[0].sha256){throw 'Prepared client checksum mismatch.'}
    }
}
$root=Join-Path $project ('data/codex-linux-package-'+$ctx.build+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
Rk-ProtectData $project $root
$public=Join-Path $root 'public';[void][IO.Directory]::CreateDirectory($public)
$adminFile=Join-Path $root 'admin.json'
$remote='roomkit/releases/'+$ctx.release
$remoteInstance=$remote+'/data/instance-'+$ctx.instance
$passed=0;$failed=0;$tunnel=$null;$started=$false;$ownedFixture=$false
$clients=New-Object Collections.ArrayList
$exports=New-Object Collections.ArrayList
$rooms=New-Object Collections.ArrayList
function Check([bool]$Value,[string]$Label){if($Value){$script:passed++;Write-Output ('PASS '+$Label)}else{$script:failed++;throw $Label}}
function Remote([string]$Command){$output=& ssh -o BatchMode=yes -o ConnectTimeout=10 $ctx.ssh_target $Command 2>&1;if($LASTEXITCODE -ne 0){throw 'Scoped SSH operation failed.'};return @($output)}
function FreshSetup($Reply){return ($null -ne $Reply -and $Reply.ok -is [bool] -and $Reply.ok -eq $true -and $Reply.payload.initialized -is [bool] -and $Reply.payload.initialized -eq $false)}
function WaitClean {
    $end=[DateTime]::UtcNow.AddSeconds(45)
    do{$state=Rk-Api 'status';if(-not $state.ok){throw 'Cleanup status rejected.'};$cleanup=$state.payload.session_cleanup;if($null -ne $cleanup -and $cleanup.pending -eq 0 -and $cleanup.running -eq 0){break};Start-Sleep -Milliseconds 300}while([DateTime]::UtcNow -lt $end)
    Check ($null -ne $cleanup -and $cleanup.pending -eq 0 -and $cleanup.running -eq 0 -and $cleanup.failed -eq 0) 'all player sessions confirmed cleaned'
}
function SaveServerLogs([string]$Phase){
    $folder=Join-Path $root ('server-'+$Phase);[void][IO.Directory]::CreateDirectory($folder)
    foreach($entry in @(@{path=$remoteInstance+'/logs/console.log';name='console.log'},@{path=$remoteInstance+'/logs/stderr.log';name='stderr.log'},@{path=$remoteInstance+'/logs/operator.log';name='operator.log'},@{path=$remoteInstance+'/data/logs/managed-host.log';name='host.log'},@{path=$remote+'/games/shooter/server.log';name='shooter.log'},@{path=$remote+'/games/turns/server.log';name='turns.log'})){
        & scp -o BatchMode=yes ($ctx.ssh_target+':'+$entry.path) (Join-Path $folder $entry.name)
        if($LASTEXITCODE -ne 0){throw 'Native server log collection failed.'}
    }
    $errors=@(Get-ChildItem -LiteralPath $folder -File | Where-Object {Select-String -LiteralPath $_.FullName -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:|ObjectDB instances leaked|resources still in use' -Quiet})
    Check ($errors.Count -eq 0) ($Phase+' native server logs have no runtime/exit errors')
}
try{
    if($publicGamePorts){
        # Reuse only the already-authorized game firewall ports while the old
        # release is stopped. The launcher checks conflicts before binding.
        Check ($null -ne $livePointer -and $livePointer.instance -cne $ctx.instance) 'old playtest has an independent identity'
        $old=Remote ('bash roomkit/releases/linux-'+$livePointer.build+'/RoomKit.sh status --instance '+$livePointer.instance)
        Check (($old -join "`n") -match 'ROOMKIT_NOT_RUNNING') 'old playtest is stopped before shared game-port acceptance'
    }
    $status=Remote ('bash '+$remote+'/RoomKit.sh status --instance '+$ctx.instance)
    Check (($status -join "`n") -match ('ROOMKIT_RUNNING.*panel='+[regex]::Escape($panelUrl+'/'))) 'fresh exported Operator is running on its isolated panel'
    $reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,[int]$ctx.panel)
    try{$reservation.Start()}finally{$reservation.Stop()}
    $tunnel=Rk-StartHidden ssh.exe @('-N','-T','-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=10','-L',('127.0.0.1:'+([int]$ctx.panel)+':127.0.0.1:'+([int]$ctx.panel)),$ctx.ssh_target) (Join-Path $root 'ssh.out') (Join-Path $root 'ssh.err')
    $heldTunnel=$tunnel.Handle
    $script:RkApiUrl=$panelUrl
    Check (Rk-WaitApi 20) 'exported management HTTP responds through SSH only'
    $listeners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort ([int]$ctx.panel) -State Listen)
    Check ($listeners.Count -eq 1 -and $listeners[0].OwningProcess -eq $tunnel.Id) 'forwarded panel belongs to this test SSH process'
    $setup=Rk-Api 'setup.status' @{} -Anonymous
    Check (FreshSetup $setup) 'fixture contains no previous administrator/data'
    $ownedFixture=$true
    $admin=@{username=('packadmin_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Admin!'+[Guid]::NewGuid().ToString('N'))}
    Rk-SaveJson $adminFile $admin
    Check (Rk-Api 'setup.create' $admin -Anonymous).ok 'exported server initializes new administrator'
    Check (Rk-AdminLogin $adminFile) 'administrator logs into native Linux package'
    Check (Rk-Api 'server.start').ok 'Operator starts the bundled ManagedHost program'
    $started=$true
    $hostState=Rk-WaitHost RUNNING
    Check ($hostState.host.state -eq 'RUNNING') 'native managed host reaches RUNNING'
    $metricsEnd=[DateTime]::UtcNow.AddSeconds(20)
    do{$metrics=(Rk-Api 'status').payload.metrics;if($metrics.available){break};Start-Sleep -Milliseconds 300}while([DateTime]::UtcNow -lt $metricsEnd)
    Check ([bool]$metrics.available) 'exported maintenance helper supplies actual metrics'
    foreach($name in @('connection.json','server.crt')){& scp -o BatchMode=yes ($ctx.ssh_target+':'+$remoteInstance+'/public/'+$name) (Join-Path $public $name);if($LASTEXITCODE){throw 'Public configuration transfer failed.'}}
    $connection=Rk-Connection $public
    Check ($connection.url -eq ('wss://192.168.10.105:'+([int]$ctx.lobby))) 'players connect directly to isolated Linux LAN lobby'
    $index=Rk-ReadJson (Join-Path $package 'games.json')
    foreach($game in @('shooter','turns')){Check ($index.$game.manifest.build_id -eq $metadata.games.$game) ($game+' identity preserved in exported package')}
    $invite=Rk-Api 'invite.create' @{uses=4;expires_hours=1;reason='exported Linux package acceptance'}
    Check $invite.ok 'invitation issued by native account storage'
    for($n=0;$n -lt 2;$n++){
        $credentials=@{username=('packplayer_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('Package '+$n);invite_code=$invite.payload.invite_code;register=$true}
        $client=Rk-StartClient (Rk-Godot '') $project $root ('source-'+$n) shooter $connection $index.shooter.manifest $credentials
        $client.credentials=$credentials;[void]$clients.Add($client)
        $report=Rk-WaitReport $client {param($r)$r.ok -and $r.phase -eq 'LOBBY'} 50
        Check ($null -ne $report) ('Windows SDK client '+$n+' registers/logs into exported Linux server')
        $client.user_id=$report.user_id
    }
    Check (Rk-Api 'asset.adjust' @{user_id=$clients[0].user_id;game_id='shooter';coins_delta=500;xp_delta=0;reason='package test';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'native asset store funds first player'
    Check (Rk-Command $clients[0] read).ok 'client refreshes persistent assets'
    $purchaseId=[Guid]::NewGuid().ToString('N')
    $purchase=Rk-Command $clients[0] purchase @{item_id='smg';operation_id=$purchaseId}
    Check ($purchase.ok -and $purchase.state.credits -eq 400) 'SDK purchase debits catalog price once'
    $replay=Rk-Command $clients[0] purchase @{item_id='smg';operation_id=$purchaseId}
    Check ($replay.ok -and $replay.state.credits -eq 400) 'SDK duplicate purchase returns original receipt'
    Check (Rk-Command $clients[0] select @{slot='primary';item_id='smg';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'SDK selection persists through native asset store'
    foreach($game in @('shooter','turns')){
        $params=if($game -eq 'shooter'){@{game_id=$game;mode='ffa';map='depot';capacity=4;rules=@{duration_seconds=300;kill_limit=0;respawn_seconds=3}}}else{@{game_id=$game;mode='sandbox';map='table';capacity=4}}
        $room=Rk-Api room.create $params;Check $room.ok ($game+' native room created');[void]$rooms.Add($room.payload.room_id)
        $ready=Rk-WaitRoom $room.payload.room_id
        Check ($null -ne $ready -and $ready.state -eq 'READY') ($game+' native room binds UDP before READY')
        if($game -eq 'shooter'){$shooterRoom=$room.payload.room_id}else{Check (Rk-Api room.stop @{room_id=$room.payload.room_id;reason='package turns lifecycle'}).ok 'second native game room stops'}
    }
    foreach($client in $clients){Check (Rk-Command $client join @{room_id=$shooterRoom} 25).ok ($client.name+' joins native room over direct DTLS/UDP')}
    foreach($client in $clients){$report=Rk-WaitReport $client {param($r)$r.phase -eq 'IN_ROOM' -and @($r.world.players.user_id) -contains $clients[0].user_id -and @($r.world.players.user_id) -contains $clients[1].user_id} 15;Check ($null -ne $report) ($client.name+' sees both players')}
    if($FullRound){
        $firstWorld=(Rk-Report $clients[0]).world
        Check ($firstWorld.remaining_ms -ge 290000 -and $firstWorld.kill_limit -eq 0) 'real room starts a five-minute round without kill limit'
        $firstRound=[int]$firstWorld.round;$roundClock=[Diagnostics.Stopwatch]::StartNew()
        $before=@((Rk-Coins $clients[0].user_id shooter).credits,(Rk-Coins $clients[1].user_id shooter).credits)
        Check (Rk-Command $clients[0] input @{move=1;duration_ms=1100}).ok 'first player sends real movement input'
        Check ($null -ne (Rk-WaitReport $clients[0] {param($r)@($r.world.players|Where-Object {$_.user_id -eq $clients[0].user_id -and $_.x -gt 325}).Count -eq 1} 6)) 'server movement reaches the open firing lane before shooting'
        $killEnd=[DateTime]::UtcNow.AddSeconds(90)
        do{
            $combat=(Rk-Report $clients[0]).world;$source=@($combat.players|Where-Object user_id -eq $clients[0].user_id)[0];$target=@($combat.players|Where-Object user_id -eq $clients[1].user_id)[0]
            if($target.life_state -eq 'dead'){break}
            $dx=[double]$target.x-[double]$source.x;$dy=[double]$target.y-[double]$source.y;$distance=[Math]::Max(0.001,[Math]::Sqrt($dx*$dx+$dy*$dy))
            [void](Rk-Command $clients[0] input @{move=0;aim_x=($dx/$distance);aim_y=($dy/$distance);jump=(($roundClock.ElapsedMilliseconds%1200)-lt 500);fire=$true;duration_ms=400})
            Start-Sleep -Milliseconds 80
        }while([DateTime]::UtcNow -lt $killEnd)
        [void](Rk-Command $clients[0] input @{move=0;jump=$false;fire=$false;duration_ms=0})
        Check ($target.life_state -eq 'dead' -and $target.hp -eq 0 -and $source.kills -eq 1) 'native room authoritative shooting kills the second player once'
        $end=[DateTime]::UtcNow.AddSeconds(10)
        do{$target=@((Rk-Report $clients[1]).world.players|Where-Object user_id -eq $clients[1].user_id)[0];if($target.respawn_wait_ms -eq 0){break};Start-Sleep -Milliseconds 150}while([DateTime]::UtcNow -lt $end)
        Check (Rk-Command $clients[1] respawn).ok 'second player requests manual respawn after countdown'
        Check ($null -ne (Rk-WaitReport $clients[1] {param($r)@($r.world.players|Where-Object {$_.user_id -eq $clients[1].user_id -and $_.life_state -eq 'alive'}).Count -eq 1} 15)) 'authoritative respawn restores second player'
        $end=[DateTime]::UtcNow.AddMinutes(6);$progress=[DateTime]::UtcNow
        do{$report=Rk-Report $clients[0];if([int]$report.world.round -gt $firstRound){break};if(@($clients|Where-Object {$_.process.HasExited}).Count){throw 'Player exited during full round'};if([DateTime]::UtcNow -ge $progress){Write-Output ('PACKAGE_PROGRESS full_round_remaining_s='+[int]($report.world.remaining_ms/1000));$progress=[DateTime]::UtcNow.AddSeconds(30)};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow -lt $end)
        Check ([int]$report.world.round -gt $firstRound -and $roundClock.Elapsed.TotalSeconds -ge 290) 'native Linux room completes real 300-second shooter round'
        Rk-SaveJson (Join-Path $root 'full-round.json') @{elapsed_ms=$roundClock.ElapsedMilliseconds;initial_world=$firstWorld;completed_world=$report.world}
        $score=@();foreach($client in $clients){$row=@($report.world.last_results|Where-Object user_id -eq $client.user_id)[0];Check ($null -ne $row -and $row.participation_ms -ge 60000) ($client.name+' meets production reward eligibility');$score+=@($row)}
        $end=[DateTime]::UtcNow.AddSeconds(45)
        do{$balances=@((Rk-Coins $clients[0].user_id shooter).credits,(Rk-Coins $clients[1].user_id shooter).credits);if($balances[0] -eq ($before[0]+20+5*$score[0].kills) -and $balances[1] -eq ($before[1]+20+5*$score[1].kills)){break};Start-Sleep -Milliseconds 400}while([DateTime]::UtcNow -lt $end)
        Check ($balances[0] -eq ($before[0]+20+5*$score[0].kills) -and $balances[1] -eq ($before[1]+20+5*$score[1].kills)) 'signed completed result credits exact permanent rewards'
    }
    foreach($client in $clients){Check (Rk-Command $client leave).ok ($client.name+' returns to lobby')}
    foreach($client in $clients){Check (Rk-StopClient $client) ($client.name+' closes normally')}
    WaitClean
    # Export actual production Client.exe from the same prepared game manifest.
    $playerRoot=Join-Path $project ('artifacts/linux-package-player-'+$ctx.build)
    if($PreparedPlayer){
        $prepared=[IO.Path]::GetFullPath($PreparedPlayer)
        if(-not(Rk-Inside $prepared (Join-Path $project 'artifacts/deployments'))){throw 'Prepared client must come from a local paired deployment.'}
        $cursor=$prepared
        while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked prepared client rejected.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
        $player=Join-Path $root 'prepared-player'
        [void][IO.Directory]::CreateDirectory($player)
        foreach($name in @('Client.exe','Client.pck','client-version.json')){
            $source=Join-Path $prepared $name
            if((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked prepared client file rejected.'}
            Copy-Item -LiteralPath $source -Destination (Join-Path $player $name)
            Check ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath (Join-Path $player $name)).Hash) ('final prepared '+$name+' copied byte-for-byte')
        }
        foreach($name in @('connection.json','server.crt')){Copy-Item -LiteralPath (Join-Path $public $name) -Destination (Join-Path $player $name)}
    }else{
        & (Join-Path $project 'tools/prepare_player_client.ps1') -IndexPath $ctx.source_index -ConnectionDirectory $public -OutputRoot $playerRoot | Out-File -LiteralPath (Join-Path $root 'player-export.out') -Encoding utf8
        $player=Join-Path $playerRoot 'shooter-windows'
    }
    $version=Rk-ReadJson (Join-Path $player 'client-version.json')
    Check ($version.build_id -eq $index.shooter.manifest.build_id) 'actual Windows Client.exe matches Linux package build'
    $invite=Rk-Api invite.create @{uses=2;expires_hours=1;reason='actual Windows exports against Linux package'}
    Check $invite.ok 'two export invitations created'
    for($n=0;$n -lt 2;$n++){
        $plan=Join-Path $root ('export-'+$n+'.plan.json');$report=Join-Path $root ('export-'+$n+'.report.json')
        Rk-SaveJson $plan @{username=('packexe_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('Package EXE '+$n);register=$true;invite_code=$invite.payload.invite_code;room_id=$shooterRoom;expect_players=2;hold_ms=4000;after='leave';timeout_ms=90000;report_path=$report}
        $process=Rk-StartHidden (Join-Path $player 'Client.exe') @('--headless','--',('--autoplay='+$plan)) (Join-Path $root ('export-'+$n+'.out')) (Join-Path $root ('export-'+$n+'.err'))
        [void]$exports.Add(@{process=$process;plan=$plan;report=$report;n=$n})
    }
    $end=[DateTime]::UtcNow.AddSeconds(120);while(@($exports|Where-Object {-not $_.process.HasExited}).Count -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 200}
    foreach($item in $exports){$report=Rk-ReadJson $item.report;Check ($item.process.HasExited -and $item.process.ExitCode -eq 0 -and $report.ok -and $report.stage -eq 'left_room' -and $report.left_state -eq 'LOBBY') ('actual exported client '+$item.n+' registers, joins and leaves')}
    $one=Rk-ReadJson $exports[0].report;$two=Rk-ReadJson $exports[1].report
    $expectedIds=@([string]$one.user_id,[string]$two.user_id | Sort-Object)
    $oneIds=@($one.players | Sort-Object);$twoIds=@($two.players | Sort-Object)
    Check ($expectedIds.Count -eq 2 -and $expectedIds[0] -cne $expectedIds[1] -and
        $one.room_id -ceq $shooterRoom -and $two.room_id -ceq $shooterRoom -and
        $one.build_id -ceq $index.shooter.manifest.build_id -and $two.build_id -ceq $index.shooter.manifest.build_id -and
        $oneIds.Count -eq 2 -and $twoIds.Count -eq 2 -and
        ($oneIds -join '|') -ceq ($expectedIds -join '|') -and ($twoIds -join '|') -ceq ($expectedIds -join '|')) 'actual exported clients have exact distinct identities in the same DTLS room and build'
    if($PreparedPlayer){
        $reports=@(Get-ChildItem -LiteralPath (Join-Path $player 'client-data/reports') -Filter '*.jsonl' -File)
        Check ($reports.Count -eq 2) 'two actual exported clients keep separate local network reports'
        $sessionIds=@()
        foreach($journal in $reports){
            $journalText=[IO.File]::ReadAllText($journal.FullName)
            $samples=@($journalText -split "`r?`n" | Where-Object {$_} | ForEach-Object { $_ | ConvertFrom-Json })
            $roomSamples=@($samples | Where-Object { $_.phase -eq 'IN_ROOM' -and $_.kind -eq 'sample' })
            Check ($roomSamples.Count -ge 2) 'exported local report contains multiple real Linux room samples'
            Check (@($roomSamples | Where-Object { $_.snapshot_interval_ms -is [ValueType] -and $_.snapshot_interval_ms -ge 0 -and $_.snapshot_age_ms -is [ValueType] -and $_.snapshot_age_ms -ge 0 -and $_.rx_bytes_per_sec -is [ValueType] -and $_.rx_bytes_per_sec -gt 0 }).Count -ge 2) 'actual exported client observes continuing snapshot and receive metrics'
            $ids=@($samples.session_id | Select-Object -Unique)
            Check ($ids.Count -eq 1 -and $ids[0] -and @($samples | Where-Object {$_.build -cne $index.shooter.manifest.build_id}).Count -eq 0) 'report session and build identify the tested client'
            $sessionIds+=$ids
            Check ($journalText -notmatch '"(password|token|ticket|username|user_id|invite_code)"\s*:' -and $journalText -notmatch [regex]::Escape($invite.payload.invite_code)) 'network report omits account and invitation secrets'
        }
        Check (@($sessionIds | Select-Object -Unique).Count -eq 2) 'simultaneous clients have distinct report sessions'
    }
    WaitClean
    Check (Rk-Api server.stop @{immediate=$true;reason='package persistence acceptance'}).ok 'native managed host accepts immediate stop'
    Check ((Rk-WaitHost STOPPED).host.state -eq 'STOPPED') 'native host stops while panel remains available'
    $backup=Rk-Api backup.create @{reason='package isolated backup'};Check $backup.ok 'native maintenance helper makes backup'
    $saved=(Rk-Coins $clients[0].user_id shooter).credits
    Check (Rk-Api asset.adjust @{user_id=$clients[0].user_id;game_id='shooter';coins_delta=7;xp_delta=0;reason='after backup';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'isolated post-backup adjustment applied'
    Check (Rk-Api backup.restore @{backup_id=$backup.payload.backup_id;reason='package isolated restore'}).ok 'native maintenance helper restores backup'
    Check (Rk-AdminLogin $adminFile) 'administrator reauthenticates after restore invalidates sessions'
    Check ((Rk-Coins $clients[0].user_id shooter).credits -eq $saved) 'restore rolls back only post-backup change'
    Check (((Remote ('bash '+$remote+'/RoomKit.sh stop --instance '+$ctx.instance)) -join "`n") -match 'ROOMKIT_STOPPED') 'official exported entry stops its own Operator without signals'
    SaveServerLogs 'first-stop'
    # No repeated ports: this checks persisted panel + config preflight on restart.
    Check (((Remote ('bash '+$remote+'/RoomKit.sh start --instance '+$ctx.instance)) -join "`n") -match ('ROOMKIT_PANEL '+[regex]::Escape($panelUrl+'/'))) 'official entry restarts with saved ports without disturbing old service'
    Check (Rk-WaitApi 20) 'restarted native panel is available'
    Check (Rk-AdminLogin $adminFile) 'administrator survives native Operator restart'
    $after=Rk-Coins $clients[0].user_id shooter
    Check ($after.credits -eq $saved -and @($after.owned) -contains 'smg' -and $after.profiles.shooter.primary -eq 'smg') 'balance, owned item and default selection survive restart'
}catch{if($failed -eq 0){$failed++};Write-Output ('PACKAGE_ERROR '+$_.Exception.Message);Write-Output ('PACKAGE_ERROR_LOCATION '+$_.ScriptStackTrace)}finally{
    foreach($item in $exports){if(-not $item.process.HasExited){$item.process.Kill();[void]$item.process.WaitForExit(5000);$failed++};Remove-Item -LiteralPath $item.plan -ErrorAction SilentlyContinue}
    foreach($client in $clients){try{if(-not $client.process.HasExited){[void](Rk-StopClient $client)}}catch{$failed++}}
    # PowerShell 5.1 ignores -Include with some -LiteralPath/-Recurse forms.
    # Select log names explicitly: Client.exe contains engine error messages as data.
    foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -eq '.err' -or $_.Name -eq 'stderr.log'}){if(Select-String -LiteralPath $file.FullName -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet){$failed++;Write-Output ('FAIL client runtime script error: '+$file.Name)}}
    try{if($ownedFixture){[void](Remote ('bash '+$remote+'/RoomKit.sh stop --instance '+$ctx.instance));if($started -and $rooms.Count -eq 2){SaveServerLogs 'final-stop'}}}catch{$failed++;Write-Output ('FAIL scoped package shutdown/log collection: '+$_.Exception.Message)}
    if($null -ne $tunnel){if(-not $tunnel.HasExited){$tunnel.Kill();[void]$tunnel.WaitForExit(5000)};$tunnel.Dispose()}
    Rk-SaveJson (Join-Path $root 'result.json') @{passed=$passed;failed=$failed;full_round=[bool]$FullRound;exported_server=$true;business_clients='source SDK fixture';native_clients='production Client.exe autoplay'}
    Write-Output ('LINUX_SERVER_PACKAGE_RESULT passed='+$passed+' failed='+$failed+' evidence='+$root)
}
exit $(if($failed -eq 0){0}else{1})
