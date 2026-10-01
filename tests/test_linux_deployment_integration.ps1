param(
    [Parameter(Mandatory=$true)][ValidateSet('Seed','Verify')][string]$Stage,
    [Parameter(Mandatory=$true)][string]$ContextPath
)
# Explicit, new exported-package fixtures only; no production instance adoption.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$ctx=Rk-ReadJson $ContextPath
if($null -eq $ctx -or $ctx.remote -notmatch '^roomkit/releases/deployment-stage-[0-9a-f]{12}$' -or
   $ctx.instance -notmatch '^update-[0-9a-f]{8}$' -or $ctx.panel -ne 28991 -or
   $ctx.server -ne '192.168.10.105' -or $ctx.ssh_target -ne 'zhao@192.168.10.105') { throw 'An explicit isolated deployment context is required.' }
$root=[IO.Path]::GetFullPath([string]$ctx.evidence)
if([IO.Path]::GetDirectoryName($root) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($root) -notmatch '^deployment-update-[0-9a-f]{12}$' -or -not(Test-Path -LiteralPath $root -PathType Container)) { throw 'Private isolated evidence directory required.' }
$package=[IO.Path]::GetFullPath([string]$ctx.new_package)
if(-not(Rk-Inside $package (Join-Path $project 'artifacts'))) { throw 'Isolated package required.' }
foreach($path in @([IO.Path]::GetFullPath($ContextPath),$root,$package)){
    $cursor=$path
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked acceptance path rejected.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
}
Rk-ProtectData $project $root
$phase=if($Stage -eq 'Seed'){'old'}else{'new'}
$remote=$ctx.remote+'/'+$phase
$instance=$remote+'/data/instance-'+$ctx.instance
$passed=0;$failed=0;$tunnel=$null;$client=$null;$owned=$false
function Check([bool]$Value,[string]$Label) { if($Value){$script:passed++;Write-Output ('PASS '+$Label)}else{$script:failed++;throw $Label} }
function Remote([string]$Command) {
    $output=@(& ssh.exe -o BatchMode=yes -o ConnectTimeout=10 $ctx.ssh_target $Command 2>&1)
    if($LASTEXITCODE -ne 0){throw 'Scoped deployment operation failed (credentials suppressed).'}
    return ($output -join "`n")
}
try {
    $reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,28991)
    try{$reservation.Start()}finally{$reservation.Stop()}
    $status=Remote ('bash '+$remote+'/RoomKit.sh status --instance '+$ctx.instance)
    Check ($status -match 'ROOMKIT_NOT_RUNNING') 'explicit new fixture is stopped before test'
    $options=if($Stage -eq 'Seed'){' --panel-port 28991 --lobby-port 28900 --control-port 28901 --udp-range 29040-29055 --bind 192.168.10.105'}else{''}
    $owned=$true
    $started=Remote ('timeout 180s bash '+$remote+'/RoomKit.sh start --instance '+$ctx.instance+$options)
    Check ($started -match 'ROOMKIT_PANEL http://127.0.0.1:28991/') 'native package starts with preserved isolated ports'
    $tunnel=Rk-StartHidden ssh.exe @('-N','-T','-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=10','-L','127.0.0.1:28991:127.0.0.1:28991',$ctx.ssh_target) (Join-Path $root ($phase+'-ssh.out')) (Join-Path $root ($phase+'-ssh.err'))
    $heldTunnel=$tunnel.Handle
    $script:RkApiUrl='http://127.0.0.1:28991'
    Check (Rk-WaitApi 25) 'management responds through test-owned SSH tunnel'
    $listeners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 28991 -State Listen)
    Check ($listeners.Count -eq 1 -and $listeners[0].OwningProcess -eq $tunnel.Id -and -not $tunnel.HasExited) 'local panel listener belongs to this test SSH'
    $adminFile=Join-Path $root 'admin.json'
    $playerFile=Join-Path $root 'player.json'
    $stateFile=Join-Path $root 'seed-state.json'
    if($Stage -eq 'Seed'){
        Check ((Rk-Api 'setup.status' @{} -Anonymous).payload.initialized -eq $false) 'old fixture has no pre-existing administrator'
        Rk-SaveJson $adminFile @{username=('upadmin_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Admin!'+[Guid]::NewGuid().ToString('N'))}
        $admin=Rk-ReadJson $adminFile
        Check (Rk-Api 'setup.create' @{username=$admin.username;password=$admin.password} -Anonymous).ok 'old package creates an isolated administrator'
    }
    Check (Rk-AdminLogin $adminFile) 'same administrator can log in'
    Check (Rk-Api 'server.start').ok 'bundled host accepts start'
    Check ((Rk-WaitHost RUNNING).host.state -eq 'RUNNING') 'native host reaches RUNNING'
    $public=Join-Path $root ($phase+'-public');[void][IO.Directory]::CreateDirectory($public)
    foreach($name in @('connection.json','server.crt')){
        & scp.exe -o BatchMode=yes ($ctx.ssh_target+':'+$instance+'/public/'+$name) (Join-Path $public $name)
        if($LASTEXITCODE){throw 'Public fixture connection transfer failed.'}
    }
    $connection=Rk-Connection $public
    Check ($connection.url -eq 'wss://192.168.10.105:28900') 'player connection retains chosen lobby and address'
    if($Stage -eq 'Seed'){
        $invite=Rk-Api 'invite.create' @{uses=3;expires_hours=1;reason='isolated deployment acceptance'}
        Check $invite.ok 'isolated invitation created'
        $settings=@{username=('upplayer_'+[Guid]::NewGuid().ToString('N').Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name='Update player';register=$true;invite_code=$invite.payload.invite_code}
        Rk-SaveJson $playerFile $settings
    }else{
        $settings=@{};$saved=Rk-ReadJson $playerFile
        foreach($key in @('username','password','display_name')){$settings[$key]=$saved.$key}
        $settings.register=$false
        Check ((Get-FileHash -LiteralPath (Join-Path $public 'server.crt')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'old-public/server.crt')).Hash) 'server certificate retained exactly'
    }
    $index=Rk-ReadJson (Join-Path $package 'games.json')
    $client=Rk-StartClient (Rk-Godot '') $project $root ($phase+'-client') shooter $connection $index.shooter.manifest $settings
    $report=Rk-WaitReport $client {param($r)$r.ok -and $r.phase -eq 'LOBBY'} 55
    Check ($null -ne $report) 'same player registers or logs into the native lobby'
    $client.user_id=$report.user_id
    if($Stage -eq 'Seed'){
        Check (Rk-Api 'asset.adjust' @{user_id=$report.user_id;game_id='shooter';coins_delta=500;xp_delta=0;reason='isolated upgrade';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'test balance funded'
        Check (Rk-Command $client 'read').ok 'SDK reads funded balance'
        Check (Rk-Command $client 'purchase' @{item_id='smg';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'test player buys a weapon'
        Check (Rk-Command $client 'select' @{slot='primary';item_id='smg';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'test default weapon saved'
        Rk-SaveJson $stateFile @{user_id=$report.user_id;credits=(Rk-Coins $report.user_id shooter).credits}
    }else{
        $before=Rk-ReadJson $stateFile;$after=Rk-Coins $report.user_id shooter
        Check ($before.user_id -eq $report.user_id) 'player identity retained through update'
        Check ($after.credits -eq $before.credits -and @($after.owned) -contains 'smg' -and $after.profiles.shooter.primary -eq 'smg') 'balance ownership and selection retained through update'
    }
    $room=Rk-Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=2;rules=@{duration_seconds=300;kill_limit=0;respawn_seconds=3}}
    Check $room.ok 'native room creation accepted'
    Check ($null -ne (Rk-WaitRoom $room.payload.room_id)) 'native room reaches READY'
    Check (Rk-Command $client 'join' @{room_id=$room.payload.room_id} 30).ok 'real SDK player enters DTLS room'
    Check (Rk-Command $client 'leave').ok 'player leaves updated or previous room'
    Check (Rk-StopClient $client) 'test client exits cleanly'
    $client=$null
    Check (Rk-Api 'room.stop' @{room_id=$room.payload.room_id;reason='update acceptance'}).ok 'test room stop accepted'
    Check (Rk-Api 'server.stop' @{immediate=$true;reason='update acceptance'}).ok 'native host stop accepted'
    Check ((Rk-WaitHost STOPPED).host.state -eq 'STOPPED') 'host exits before offline package copy'
    if($Stage -eq 'Seed'){
        $backup=Rk-Api 'backup.create' @{reason='isolated update snapshot'}
        Check $backup.ok 'backup created before package update'
        $seed=Rk-ReadJson $stateFile;$seed | Add-Member -NotePropertyName backup_id -NotePropertyValue $backup.payload.backup_id
        Rk-SaveJson $stateFile $seed
    }else{
        $backups=Rk-Api 'backup.list';$seed=Rk-ReadJson $stateFile
        Check ($backups.ok -and @($backups.payload.backups | Where-Object backup_id -eq $seed.backup_id).Count -eq 1) 'previous backup remains listed after update'
        Check (Rk-Api 'asset.adjust' @{user_id=$seed.user_id;game_id='shooter';coins_delta=7;xp_delta=0;reason='post-update backup check';operation_id=[Guid]::NewGuid().ToString('N')}).ok 'isolated post-update balance change succeeds'
        Check (Rk-Api 'backup.restore' @{backup_id=$seed.backup_id;reason='isolated migrated backup restore'}).ok 'backup copied from old package can actually restore'
        Check (Rk-AdminLogin $adminFile) 'administrator can reauthenticate after copied backup restore'
        $restored=Rk-Coins $seed.user_id shooter
        Check ($restored.credits -eq $seed.credits -and @($restored.owned) -contains 'smg' -and $restored.profiles.shooter.primary -eq 'smg') 'migrated backup restores original balance ownership and selection'
    }
    Check ((Remote ('timeout 150s bash '+$remote+'/RoomKit.sh stop --instance '+$ctx.instance)) -match 'ROOMKIT_STOPPED') 'package official entry exits without forced signals'
    $owned=$false
    & scp.exe -o BatchMode=yes ($ctx.ssh_target+':'+$instance+'/logs/stderr.log') (Join-Path $root ($phase+'-server.err'))
    if($LASTEXITCODE){throw 'Server log collection failed.'}
    Check (-not(Select-String -LiteralPath (Join-Path $root ($phase+'-server.err')) -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|ERROR:|ObjectDB instances leaked' -Quiet)) 'native server exit log has no runtime errors'
}catch{
    if($failed -eq 0){$failed++};Write-Output ('UPDATE_ACCEPTANCE_ERROR '+$_.Exception.Message);Write-Output $Stage;Write-Output $_.ScriptStackTrace
}finally{
    if($null -ne $client){try{[void](Rk-StopClient $client)}catch{$failed++}}
    if($owned){try{[void](Remote ('timeout 150s bash '+$remote+'/RoomKit.sh stop --instance '+$ctx.instance))}catch{$failed++}}
    if($null -ne $tunnel){if(-not $tunnel.HasExited){$tunnel.Kill();[void]$tunnel.WaitForExit(5000)};$tunnel.Dispose()}
    Rk-SaveJson (Join-Path $root ($phase+'-result.json')) @{stage=$Stage;passed=$passed;failed=$failed;native_server=$true;business_client='Windows SDK driver'}
    Write-Output ('DEPLOYMENT_UPDATE_RESULT stage='+$Stage+' passed='+$passed+' failed='+$failed+' evidence='+$root)
}
exit $(if($failed){1}else{0})
