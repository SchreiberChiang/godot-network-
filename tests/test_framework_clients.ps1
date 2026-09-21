param([switch]$Visual,[string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pointer=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'run/operator-test-context.json') | ConvertFrom-Json
$ctx=Get-Content -Encoding UTF8 -Raw -LiteralPath $pointer.path | ConvertFrom-Json
$builds=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'artifacts/framework-games.json') | ConvertFrom-Json
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $ctx.evidence ('clients-'+$runId)
$private=Join-Path $ctx.test_root ('clients-'+$runId)
foreach($candidate in @($evidence,$private)) {
    $resolved=[IO.Path]::GetFullPath($candidate)
    if(-not $resolved.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Test directory outside project'}
    New-Item -ItemType Directory -Path $resolved -Force | Out-Null
}
$utf8=New-Object Text.UTF8Encoding($false)
$script:token=$ctx.token
$script:passed=0
$script:failed=0
$script:results=New-Object Collections.ArrayList
$script:clients=New-Object Collections.ArrayList
$script:commandNumber=0
$turnsRoom=''
$ownInvite=''
function Save-Json($path,$value) {
    $temporary=$path+'.tmp'
    [IO.File]::WriteAllText($temporary,($value|ConvertTo-Json -Depth 50 -Compress),$utf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
}
function Check([bool]$condition,[string]$name) {
    [void]$script:results.Add(@{name=$name;passed=$condition})
    if($condition){$script:passed++;Write-Host ('PASS '+$name)}else{$script:failed++;Write-Host ('FAIL '+$name)}
}
function Require([bool]$condition,[string]$name) { Check $condition $name; if(-not $condition){throw ('Prerequisite failed: '+$name)} }
function Api([string]$action,$payload=@{}) {
    $headers=@{Authorization='Bearer '+$script:token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 25 -Compress))
    try{return Invoke-RestMethod -Uri ($ctx.url+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65}
    catch { throw ('Administrator request failed: '+$action+'; HTTP transport failed (credentials suppressed)') }
}
function Report($client) {
    if(Test-Path -LiteralPath $client.report){try{return Get-Content -Encoding UTF8 -Raw -LiteralPath $client.report|ConvertFrom-Json}catch{return $null}}
    return $null
}
function Wait-Report($client,[scriptblock]$predicate,[int]$seconds=65) {
    $deadline=[DateTime]::UtcNow.AddSeconds($seconds)
    do {
        $r=Report $client
        if($null -ne $r -and (& $predicate $r)){return $r}
        if($client.process.HasExited){throw ('Client exited before expected state: '+$client.name+' code='+$client.process.ExitCode)}
        Start-Sleep -Milliseconds 100
    } while([DateTime]::UtcNow -lt $deadline)
    throw ('Client state timeout: '+$client.name)
}
function Start-Client([string]$name,[string]$game,$credentials=$null,[bool]$register=$true) {
    $directory=Join-Path $evidence $name
    New-Item -ItemType Directory -Force -Path $directory|Out-Null
    if($null -eq $credentials){$credentials=@{username=('p_'+$name+'_'+$runId.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=([string][char]0x6D4B+[char]0x8BD5+'_'+$name)}}
    $bootstrap=Join-Path $private ($name+'.json')
    $report=Join-Path $directory 'report.json'
    $connection=@{url=$ctx.connection.url;ca_certificate=$ctx.connection.ca_certificate;server_hostname=$ctx.connection.server_hostname;game_id=$game}
    Save-Json $bootstrap @{connection=$connection;manifest=$builds.$game.manifest;game_id=$game;username=$credentials.username;password=$credentials.password;display_name=$credentials.display_name;invite_code=$ctx.invite_code;register=$register;report_path=$report;control_directory=$directory;timeout_ms=1000000}
    $arguments=@('--path',$project,'--script','res://tests/run_framework_clients.gd','--',('--test-config='+$bootstrap))
    if(-not $Visual){$arguments=@('--headless')+$arguments}
    $quoted=foreach($argument in $arguments){'"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'console.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $ownedHandle=$process.Handle
    $client=@{name=$name;game=$game;directory=$directory;report=$report;process=$process;handle=$ownedHandle;credentials=$credentials;user_id=''}
    [void]$script:clients.Add($client)
    return $client
}
function Command($client,[string]$action,$payload=@{},[int]$seconds=65) {
    $script:commandNumber++
    $id='c'+$script:commandNumber.ToString('D6')
    $value=@{id=$id;action=$action}
    foreach($key in $payload.Keys){$value[$key]=$payload[$key]}
    Save-Json (Join-Path $client.directory ($id+'.command.json')) $value
    $result=Wait-Report $client {param($r) @($r.results|Where-Object id -eq $id).Count -gt 0} $seconds
    return @($result.results|Where-Object id -eq $id)[-1]
}
function Player($report,[string]$user) {return @($report.world.players|Where-Object user_id -eq $user)[0]}
function Coins($client) { $reply=Api 'asset.read' @{user_id=$client.user_id;game_id=$client.game}; if(-not $reply.ok){throw ('Asset inspection failed: '+$reply.code)}; return [long]$reply.payload.state.credits }
function Fund($client,[int]$amount) {return Api 'asset.adjust' @{user_id=$client.user_id;game_id=$client.game;coins_delta=$amount;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='isolated real client acceptance'}}
function Join($client,[string]$room) {
    $joined=Command $client 'join' @{room_id=$room}
    Require $joined.ok ($client.name+' actual ENet admission')
    [void](Wait-Report $client {param($r) $r.phase -eq 'IN_ROOM' -and $null -ne (Player $r $client.user_id)})
}
function Stop-Client($client) {
    if(-not $client.process.HasExited){try{[void](Command $client 'close' @{} 6)}catch{}}
    if(-not $client.process.WaitForExit(3500)){$client.process.Kill();$client.process.WaitForExit()}
}
try {
    $status=Api 'status'
    Require ($status.ok -and @($status.payload.rooms|Where-Object {$_.room_id -eq $ctx.room_id -and $_.state -eq 'READY'}).Count -eq 1) 'parent-owned operator and shooter room are live READY'
    $invitation=Api 'invite.create' @{uses=12;expires_hours=1;reason='isolated client acceptance'}
    Require ($invitation.ok -and ([string]$invitation.payload.invite_code).Length -eq 32) 'real registration invitation supplied'
    $ctx.invite_code=$invitation.payload.invite_code
    $ownInvite=$invitation.payload.invite_id
    $one=Start-Client 'shooter_one' 'shooter'
    $two=Start-Client 'shooter_two' 'shooter'
    foreach($client in @($one,$two)) {
        $ready=Wait-Report $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok}
        $client.user_id=$ready.user_id
        Require ($ready.registration.ok -and $client.user_id -ne '' -and $ready.assets.credits -eq 0 -and 'rifle' -in $ready.assets.owned) ($client.name+' invitation registration/login and free rifle')
        Require (Fund $client 300).ok ($client.name+' administrator test funding')
        [void](Command $client 'read')
        Join $client $ctx.room_id
    }
    $roundStart=Wait-Report $one {param($r) $r.world.phase -eq 'active' -and $r.world.players.Count -eq 2}
    $firstRound=[int]$roundStart.world.round
    Write-Host 'CLIENT_TEST_PROGRESS phase=real_five_minute_round_started'
    Check (-not (Command $one 'inventory').ok) 'living UI cannot open inventory'
    $denied=Command $one 'purchase' @{item_id='smg';operation_id='alive_purchase_'+$runId}
    Check (-not $denied.ok -and $denied.code -eq 'ASSET_OPERATION_DENIED') 'forged live purchase rejected by server'
    $denied=Command $one 'select' @{slot='primary';item_id='rifle';operation_id='alive_select_'+$runId}
    Check (-not $denied.ok -and $denied.code -eq 'ASSET_OPERATION_DENIED') 'forged live selection rejected by server'
    [void](Command $one 'input' @{move=1;duration_ms=1100})
    $moved=Wait-Report $one {param($r) (Player $r $one.user_id).x -gt 325} 6
    [void](Command $one 'input' @{move=0;duration_ms=0})
    Check ((Player $moved $one.user_id).x -gt 325) 'real server movement reaches open firing lane'
    $killDeadline=[DateTime]::UtcNow.AddSeconds(35)
    $jumpClock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $r=Report $one
        $source=Player $r $one.user_id
        $target=Player $r $two.user_id
        if($target.life_state -eq 'dead'){break}
        $dx=[double]$target.x-[double]$source.x
        $dy=[double]$target.y-[double]$source.y
        $length=[Math]::Max(0.001,[Math]::Sqrt($dx*$dx+$dy*$dy))
        [void](Command $one 'input' @{move=0;aim_x=($dx/$length);aim_y=($dy/$length);jump=(($jumpClock.ElapsedMilliseconds%1200)-lt 500);fire=$true;duration_ms=400})
        Start-Sleep -Milliseconds 80
    }while([DateTime]::UtcNow -lt $killDeadline)
    [void](Command $one 'input' @{move=0;jump=$false;fire=$false;duration_ms=0})
    $dead=Wait-Report $two {param($r) (Player $r $two.user_id).life_state -eq 'dead'} 5
    Require ((Player $dead $one.user_id).kills -eq 1 -and (Player $dead $two.user_id).hp -eq 0) 'real hitscan combat kills and authoritative score replicate'
    $earlyWait=[int](Player $dead $two.user_id).respawn_wait_ms
    [void](Command $two 'respawn')
    if($earlyWait -gt 500){Start-Sleep -Milliseconds 120; Check ((Player (Report $two) $two.user_id).life_state -eq 'dead') 'early manual respawn rejected before three seconds'}
    if($Visual){[void](Command $two 'capture' @{name='dead.png'})}
    Require (Command $two 'inventory').ok 'dead UI can open inventory'
    Require (Command $two 'read').ok 'dead player receives persistent assets'
    $purchaseKey='unlock_'+$runId
    $purchase=Command $two 'purchase' @{item_id='smg';operation_id=$purchaseKey}
    Require ($purchase.ok -and $purchase.state.credits -eq 200 -and 'smg' -in $purchase.state.owned -and $purchase.state.profiles.shooter.primary -eq 'rifle') 'dead purchase debits once and does not implicitly select'
    $replay=Command $two 'purchase' @{item_id='smg';operation_id=$purchaseKey}
    Check ($replay.ok -and $replay.state.credits -eq 200) 'repeated purchase operation returns original receipt'
    $select=Command $two 'select' @{slot='primary';item_id='smg';operation_id=('choose_'+$runId)}
    Require ($select.ok -and $select.state.profiles.shooter.primary -eq 'smg') 'dead selection persists independently'
    if($Visual){[void](Command $two 'capture' @{name='inventory.png'})}
    [void](Command $two 'respawn')
    $respawn=Wait-Report $two {param($r) (Player $r $two.user_id).life_state -eq 'alive'} 15
    Require ((Player $respawn $two.user_id).weapon -eq 'smg') 'manual respawn uses newly confirmed saved weapon'
    if($Visual){[void](Command $two 'capture' @{name='respawn.png'})}
    Require (Command $two 'leave').ok 'player leaves room back to authenticated lobby'
    Join $two $ctx.room_id
    $rejoined=Wait-Report $two {param($r) (Player $r $two.user_id).weapon -eq 'smg'}
    Check ($rejoined.user_id -eq $two.user_id) 'same account and persistent default survive room re-entry'
    $duplicate=Start-Client 'duplicate' 'shooter' $one.credentials $false
    $duplicateResult=Wait-Report $duplicate {param($r) $r.phase -eq 'FAILED'} 30
    Check ($duplicateResult.code -eq 'ALREADY_LOGGED_IN' -and (Report $one).phase -eq 'IN_ROOM') 'duplicate login rejects newcomer and preserves original player'
    Stop-Client $duplicate

    # The shooter round stays live while an independent non-shooter game proves reuse.
    $created=Api 'room.create' @{game_id='turns';mode='sandbox';map='table';capacity=4}
    Require $created.ok 'administrator creates independent non-shooter room'
    $turnsRoom=$created.payload.room_id
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do{Start-Sleep -Milliseconds 300;$status=Api 'status';$readyRoom=@($status.payload.rooms|Where-Object room_id -eq $turnsRoom)[0]}while($readyRoom.state -ne 'READY' -and [DateTime]::UtcNow -lt $deadline)
    Require ($readyRoom.state -eq 'READY') 'non-shooter room actual process READY'
    $turnOne=Start-Client 'turns_one' 'turns'
    $turnTwo=Start-Client 'turns_two' 'turns'
    foreach($client in @($turnOne,$turnTwo)){$r=Wait-Report $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok};$client.user_id=$r.user_id}
    Require (Fund $turnOne 100).ok 'same asset service funds non-shooter account'
    Require (Command $turnOne 'purchase' @{item_id='jade';operation_id=('jade_'+$runId)}).ok 'non-shooter lobby buys theme through same asset SDK'
    Require (Command $turnOne 'select' @{slot='theme';item_id='jade';operation_id=('theme_'+$runId)}).ok 'non-shooter lobby saves independent theme slot'
    Join $turnOne $turnsRoom
    Join $turnTwo $turnsRoom
    $jade=Wait-Report $turnOne {param($r) (Player $r $turnOne.user_id).theme -eq 'jade'}
    Check ((Player $jade $turnOne.user_id).theme -eq 'jade') 'non-shooter adapter receives and renders confirmed theme'
    $noTheme=Command $turnOne 'select' @{slot='theme';item_id='classic';operation_id=('seated_'+$runId)}
    Check (-not $noTheme.ok -and $noTheme.code -eq 'ASSET_OPERATION_DENIED') 'non-shooter room applies lobby-only policy without death rules'
    for($i=0;$i-lt 6;$i++){
        $r=Report $turnOne
        $active=if($r.world.active_user -eq $turnOne.user_id){$turnOne}else{$turnTwo}
        [void](Command $active 'choose' @{take=2})
        Start-Sleep -Milliseconds 120
    }
    [void](Wait-Report $turnOne {param($r) $r.world.round -ge 2} 10)
    Check $true 'real non-shooter turns complete a round through separate gameplay protocol'
    if($Visual){[void](Command $turnOne 'capture' @{name='jade-turns.png'})}
    Stop-Client $turnOne
    Stop-Client $turnTwo
    [void](Api 'room.stop' @{room_id=$turnsRoom;reason='non-shooter acceptance complete'})
    $turnsRoom=''

    $beforeOne=Coins $one
    $beforeTwo=Coins $two
    $roundDeadline=[DateTime]::UtcNow.AddMinutes(6)
    $nextProgress=[DateTime]::UtcNow
    do {
        $r=Report $one
        if([int]$r.world.round -gt $firstRound){break}
        if($one.process.HasExited -or $two.process.HasExited){throw 'Real player exited before completed round'}
        if([DateTime]::UtcNow -ge $nextProgress){Write-Host ('CLIENT_TEST_PROGRESS phase=waiting_full_round remaining_s='+[int]($r.world.remaining_ms/1000));$nextProgress=[DateTime]::UtcNow.AddSeconds(30)}
        Start-Sleep -Milliseconds 250
    }while([DateTime]::UtcNow -lt $roundDeadline)
    Require ([int]$r.world.round -gt $firstRound) 'full real five-minute shooter round completed without shortened rules'
    $scoreOne=@($r.world.last_results|Where-Object user_id -eq $one.user_id)[0]
    $scoreTwo=@($r.world.last_results|Where-Object user_id -eq $two.user_id)[0]
    Check ($scoreOne.participation_ms -ge 60000 -and $scoreTwo.participation_ms -ge 60000) 'actual participation exceeds production reward eligibility'
    $awardDeadline=[DateTime]::UtcNow.AddSeconds(45)
    do{$afterOne=Coins $one;$afterTwo=Coins $two;if($afterOne -eq ($beforeOne+20+5*$scoreOne.kills) -and $afterTwo -eq ($beforeTwo+20+5*$scoreTwo.kills)){break};Start-Sleep -Milliseconds 400}while([DateTime]::UtcNow -lt $awardDeadline)
    Check ($afterOne -eq ($beforeOne+20+5*$scoreOne.kills) -and $afterTwo -eq ($beforeTwo+20+5*$scoreTwo.kills)) 'authenticated completed result atomically credits exact persistent reward'
    Require (Api 'account.ban' @{user_id=$two.user_id;hours=1;reason='isolated acceptance ban'}).ok 'administrator ban accepted'
    [void](Wait-Report $two {param($r) $r.phase -eq 'CLOSED'} 15)
    Check ((Report $two).phase -eq 'CLOSED') 'ban revokes existing lobby and game membership'
    $banned=Command $two 'login'
    Check (-not $banned.ok -and $banned.code -eq 'ACCOUNT_BANNED') 'banned account cannot log back in'
    Require (Api 'account.unban' @{user_id=$two.user_id;reason='isolated acceptance complete'}).ok 'administrator unban accepted'
    Check (Command $two 'login').ok 'unbanned account can log in again'
} catch {
    $script:failed++
    Write-Host ('FRAMEWORK_CLIENT_TEST_ERROR '+$_.Exception.Message)
} finally {
    foreach($client in $script:clients){try{Stop-Client $client}catch{if(-not $client.process.HasExited){$client.process.Kill();$client.process.WaitForExit()}}}
    if($turnsRoom){try{[void](Api 'room.stop' @{room_id=$turnsRoom;reason='test client cleanup'})}catch{}}
    if($ownInvite){try{[void](Api 'invite.revoke' @{invite_id=$ownInvite;reason='client acceptance cleanup'})}catch{}}
    foreach($client in $script:clients){$stderr=Join-Path $client.directory 'stderr.log';if(Test-Path -LiteralPath $stderr){Check (-not (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) ($client.name+' no runtime script errors')}}
    Save-Json (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;checks=@($script:results);visual=[bool]$Visual;full_round_seconds=300}
    Write-Host ('FRAMEWORK_CLIENTS_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
exit $(if($script:failed-eq 0){0}else{1})
