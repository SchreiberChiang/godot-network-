param(
    [switch]$HoldForIntegration,
    [switch]$Lifecycle,
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::Expect100Continue = $false
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testId = [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $project ('data\test-operator-' + $testId)
$evidence = Join-Path $project ('logs\operator-' + $testId)
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot | Out-Null
& (Join-Path $project 'tools\protect_runtime.ps1') -ProjectRoot $project | Out-Null
function Free-TcpPort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    $listener.Start()
    $number = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $number
}
function Save-Json($path,$value) {
    [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 40 -Compress),(New-Object Text.UTF8Encoding($false)))
}
$panelPort = Free-TcpPort
$settings = @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=(Free-TcpPort);game_bind='127.0.0.1';control_port=(Free-TcpPort);udp_first=28600;udp_last=28631;max_rooms=16;asset_spaces=@{shooter='shooter';turns='turns'}}
Save-Json (Join-Path $testRoot 'config.json') $settings
$baseUrl = 'http://127.0.0.1:' + $panelPort
$script:adminToken = ''
$script:passed = 0
$script:failed = 0
function Api($action,$payload=@{},[switch]$Anonymous) {
    $headers = @{}
    if ($script:adminToken -and -not $Anonymous) { $headers.Authorization = 'Bearer ' + $script:adminToken }
    $body = [Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload} | ConvertTo-Json -Depth 20 -Compress))
    try { return Invoke-RestMethod -Uri ($baseUrl + '/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65 }
    catch { throw ('API '+$action+' failed: '+$_.Exception.Message) }
}
function Check($condition,$name) {
    if ($condition) { $script:passed++; Write-Output ('PASS ' + $name) }
    else { $script:failed++; Write-Output ('FAIL ' + $name) }
}
$arguments = @('--headless','--path',$project,'--log-file',(Join-Path $evidence 'operator.log'),'--script','res://host/operator.gd','--',('--data-root=' + $testRoot),('--panel-port=' + $panelPort))
$quoted = foreach ($argument in $arguments) { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'console.log') -RedirectStandardError (Join-Path $evidence 'stderr.log')
$ownedHandle = $process.Handle
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $ready = $false
    while (-not $ready -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        try { $ready = (Api 'setup.status' @{} -Anonymous).ok } catch { $lastReadyError = $_.Exception.Message; Start-Sleep -Milliseconds 300 }
    }
    if (-not $ready) { throw ('Operator did not become ready: ' + $lastReadyError) }
    Check $ready 'independent operator HTTP ready'
    $username = 'admin_' + $testId.Substring(0,8)
    $password = 'Test!' + [Guid]::NewGuid().ToString('N')
    $setup = Api 'setup.create' @{username=$username;password=$password} -Anonymous
    Check ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'administrator setup and login'
    if (-not $setup.ok) { throw ('Setup failed: ' + $setup.code) }
    $script:adminToken = $setup.payload.token
    $initial = Api 'status'
    Check ($initial.payload.host.state -eq 'STOPPED') 'operator starts without game host'
    $start = Api 'server.start'
    Check $start.ok 'real managed host start'
    if (-not $start.ok) { throw ('Managed host failed: ' + $start.code) }
    $created = Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=4}
    Check $created.ok 'admin creates real shooter room'
    $roomId = $created.payload.room_id
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $room = $null
    do {
        Start-Sleep -Milliseconds 300
        $status = Api 'status'
        $room = @($status.payload.rooms | Where-Object room_id -eq $roomId)[0]
    } while (($null -eq $room -or $room.state -eq 'STARTING') -and [DateTime]::UtcNow -lt $deadline)
    Check ($null -ne $room -and $room.state -eq 'READY') 'room actual UDP bind and READY'
    $invite = Api 'invite.create' @{uses=12;expires_hours=24;reason='isolated integration'}
    Check $invite.ok 'invite creation'
    $context = @{url=$baseUrl;panel_port=$panelPort;test_root=$testRoot;evidence=$evidence;operator_pid=$process.Id;username=$username;password=$password;token=$script:adminToken;invite_code=$invite.payload.invite_code;room_id=$roomId;connection=@{url=('wss://127.0.0.1:' + $settings.lobby_port);ca_certificate=(Join-Path $testRoot 'server.crt');server_hostname='localhost';secure_enet=$true;managed=$true}}
    Save-Json (Join-Path $testRoot 'test-context.json') $context
    Save-Json (Join-Path $project 'run\operator-test-context.json') @{path=(Join-Path $testRoot 'test-context.json')}
    Write-Output ('OPERATOR_INTEGRATION_READY context=' + (Join-Path $testRoot 'test-context.json'))
    if ($HoldForIntegration) {
        $deadline = [DateTime]::UtcNow.AddMinutes(40)
        while (-not (Test-Path -LiteralPath (Join-Path $testRoot 'integration-done.request')) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 500 }
    }
    # Browser login may rotate the admin session. Renew this test driver's session.
    $login = Api 'admin.login' @{username=$username;password=$password} -Anonymous
    if ($login.ok) { $script:adminToken = $login.payload.token }
    $stop = Api 'server.stop' @{immediate=$true;reason='integration shutdown'}
    Check $stop.ok 'immediate host stop accepted'
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 300
        $status = Api 'status'
    } while ($status.payload.host.state -ne 'STOPPED' -and [DateTime]::UtcNow -lt $deadline)
    Check ($status.payload.host.state -eq 'STOPPED' -and -not (Test-Path -LiteralPath (Join-Path $testRoot 'host-running.json'))) 'host exit and owned room reclamation'
    Check ((Api 'status').ok -and -not $process.HasExited) 'panel remains alive after host stops'
    $backup = Api 'backup.create' @{reason='integration backup'}
    Check $backup.ok 'real operator coordinated backup'
    if($Lifecycle) {
        $target=$setup.payload.identity.user_id
        $configured=Api 'config.set' @{config=@{lobby_bind=$settings.lobby_bind;advertised_host=$settings.advertised_host;lobby_port=$settings.lobby_port;max_rooms=$settings.max_rooms;asset_spaces=@{shooter='shared';turns='shared'}};reason='test shared spaces'}
        Check $configured.ok 'stopped host permits asset space switch'
        $funded=Api 'asset.adjust' @{user_id=$target;game_id='shooter';coins_delta=345;xp_delta=150;operation_id=('ops_'+$testId);reason='test wallet audit'}
        Check $funded.ok 'administrator funds named shared space'
        $shared=Api 'asset.read' @{user_id=$target;game_id='turns'}
        Check ($shared.payload.state.credits -eq 345 -and $shared.payload.state.profiles.turns.theme -eq 'classic') 'shared wallet and isolated game profiles'
        $audit=Api 'audit.list' @{limit=100}
        Check (@($audit.payload.entries | Where-Object { $_.action -eq 'asset.adjust' -and $null -ne $_.after -and $_.after.credits -eq 345 }).Count -ge 1) 'panel asset audit contains real committed before and after state'
        $restored=Api 'backup.restore' @{backup_id=$backup.payload.backup_id;reason='test stopped restoration'}
        Check $restored.ok 'restore replaces databases after pre-restore backup'
        $rejected=$false
        try { [void](Api 'status') } catch { $rejected=$true }
        Check $rejected 'restore revoked old administrator session'
        $login=Api 'admin.login' @{username=$username;password=$password} -Anonymous
        $script:adminToken=$login.payload.token
        $config=Api 'config.get'
        Check ($config.payload.config.asset_spaces.shooter -eq 'shooter' -and $config.payload.config.asset_spaces.turns -eq 'turns') 'restored configuration reloads in live operator'
        Check (Api 'server.start').ok 'start restored host'
        $before=(Api 'status').payload.host.pid
        Check (Api 'server.restart' @{immediate=$false;reason='test full grace period'}).ok 'sixty second graceful restart accepted'
        $draining=(Api 'status').payload.host
        Check ($draining.state -eq 'DRAINING' -and $draining.countdown -gt 40 -and $draining.maintenance) 'grace period has live announcement and admission maintenance'
        $deadline=[DateTime]::UtcNow.AddSeconds(85)
        $restartStatus=$null
        do {
            Start-Sleep -Milliseconds 500
            $restartStatus=(Api 'status').payload.host
        } while(($restartStatus.state -ne 'RUNNING' -or $restartStatus.pid -eq $before) -and [DateTime]::UtcNow -lt $deadline)
        Check ($restartStatus.state -eq 'RUNNING' -and $restartStatus.pid -ne $before) 'graceful restart confirmed old process exit and started new child'
        $crashRoom=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=2}
        Check $crashRoom.ok 'create actual room for crash isolation'
        $deadline=[DateTime]::UtcNow.AddSeconds(40)
        do { Start-Sleep -Milliseconds 500; $crashRow=@((Api 'status').payload.rooms | Where-Object room_id -eq $crashRoom.payload.room_id)[0] } while($crashRow.state -ne 'READY' -and [DateTime]::UtcNow -lt $deadline)
        Check ($crashRow.state -eq 'READY') 'crash test room is actually bound and ready'
        $record=Get-Content -Raw -Encoding UTF8 (Join-Path $testRoot 'host-running.json') | ConvertFrom-Json
        $sameExecutable=[string]::Equals([IO.Path]::GetFullPath($record.executable),[IO.Path]::GetFullPath($Godot),[StringComparison]::OrdinalIgnoreCase)
        if(-not $record.verified -or $record.parent_pid -ne $process.Id -or -not $sameExecutable) { throw 'Refuse crash injection without this test parent, executable and captured ownership.' }
        $crashed=& (Join-Path $project 'tools/process_identity.ps1') -Mode terminate -ProcessId $record.pid -ExpectedParentPid $record.parent_pid -ExpectedExecutable $record.executable -LaunchId $record.launch_id -ExpectedCreationFileTime $record.created_filetime | ConvertFrom-Json
        Check ($crashed.state -eq 'exited') 'terminate only this verified test-owned host for real crash injection'
        $deadline=[DateTime]::UtcNow.AddSeconds(75)
        do { Start-Sleep -Milliseconds 500; $recovery=(Api 'status').payload.host } while(($recovery.state -ne 'RUNNING' -or $recovery.pid -eq $record.pid) -and [DateTime]::UtcNow -lt $deadline)
        Check ($recovery.state -eq 'RUNNING' -and $recovery.pid -ne $record.pid) 'actual host crash reclaims orphan room then restarts'
        $journal=Get-Content -Raw -Encoding UTF8 (Join-Path $testRoot 'processes.json') | ConvertFrom-Json
        Check (@($journal.entries.PSObject.Properties).Count -eq 0) 'restarted host clears confirmed exited room journal'
        Check (Api 'server.stop' @{immediate=$true;reason='final lifecycle cleanup'}).ok 'final lifecycle host stop requested'
        $deadline=[DateTime]::UtcNow.AddSeconds(65)
        do { Start-Sleep -Milliseconds 500; $last=(Api 'status').payload.host } while($last.state -ne 'STOPPED' -and [DateTime]::UtcNow -lt $deadline)
        Check ($last.state -eq 'STOPPED') 'lifecycle host fully stopped'
    }
    Save-Json (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;test_root=$testRoot;panel_port=$panelPort;room_id=$roomId}
} catch {
    $script:failed++
    throw
} finally {
    if (-not $process.HasExited) {
        [IO.File]::WriteAllText((Join-Path $testRoot 'operator-stop.request'),'stop')
        if (-not $process.WaitForExit(65000)) { $process.Kill(); $process.WaitForExit(); $script:failed++; Write-Output 'FAIL operator graceful shutdown watchdog' }
    }
    Write-Output ('OPERATOR_PROCESS_EXIT=' + $process.ExitCode)
    if ($process.ExitCode -ne 0) { $script:failed++ }
    Get-Content -Encoding UTF8 (Join-Path $evidence 'stderr.log')
    Write-Output ('OPERATOR_RESULT passed=' + $script:passed + ' failed=' + $script:failed)
}
if ($script:failed -gt 0) { exit 1 }
exit 0
