param(
    [Parameter(Mandatory=$true)][ValidateSet('prepare','persist','after-restart','fault','after-fault')][string]$Phase,
    [Parameter(Mandatory=$true)][string]$Instance,
    [Parameter(Mandatory=$true)][int]$PanelPort,
    [string]$Godot=''
)
# Same-machine acceptance of one instance started by tools/roomkit_linux.sh
# (work packages 3 and 4). Phases, run in this order by tools/linux_l3_slice.sh:
#   prepare        administrator setup, real managed host, shooter room, invitation
#                  and the context tests/test_framework_clients.ps1 reads;
#   persist        a further player registers, buys and selects an item; snapshot of
#                  every account's assets; with the host stopped: backup, a change,
#                  restore (the change is gone, nothing else is) -- then the slice
#                  stops and restarts the service with the official entry;
#   after-restart  the snapshot is unchanged and the player logs in again;
#   fault          this script starts the Operator itself (its own child, same
#                  instance), with host, room and a seated player, kills exactly that
#                  child, and checks that host and room leave by themselves and no
#                  credential is left in logs, runtime files or command lines;
#   after-fault    the official entry started the Operator again: read-only recovery
#                  clears the old marker and journal, the host and a room start, data
#                  is unchanged.
# Only fake accounts; credentials stay in 600 files of <instance>/acceptance.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
. (Join-Path $PSScriptRoot 'support/portable.ps1')
. (Join-Path $PSScriptRoot 'support/client_harness.ps1')
$Godot=Rk-Godot $Godot
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('/','\')
$Instance=[IO.Path]::GetFullPath($Instance).TrimEnd('/','\')
if (-not (Rk-Inside $Instance (Join-Path $project 'data'))) { throw 'Instance outside the project data folder.' }
$data=Join-Path $Instance 'data'
$state=Join-Path $Instance 'acceptance'
$evidence=Join-Path $state ('phase-'+$Phase+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
Rk-ProtectData $project $state
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$script:RkApiUrl='http://127.0.0.1:'+$PanelPort
$games=Rk-ReadJson (Join-Path $Instance 'games.json')
$adminFile=Join-Path $state 'admin.json'
$persistFile=Join-Path $state 'persist.json'
$snapshotFile=Join-Path $state 'snapshot.json'
$script:passed=0
$script:failed=0
$clients=New-Object Collections.ArrayList
function Check([bool]$Condition,[string]$Name) {
    if ($Condition) { $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) }
}
function Require([bool]$Condition,[string]$Name) { Check $Condition $Name; if (-not $Condition) { throw ('Prerequisite failed: '+$Name) } }
function NewSecret([string]$Prefix) { return $Prefix+[Guid]::NewGuid().ToString('N') }
function Client([string]$Name,[string]$Game,[hashtable]$Settings) {
    $client=Rk-StartClient $Godot $project $evidence $Name $Game (Rk-Connection (Join-Path $Instance 'public')) $games.$Game.manifest $Settings
    [void]$clients.Add($client)
    return $client
}
function AccountList {
    $reply=Rk-Api 'account.list' @{query='';offset=0;limit=200}
    if (-not $reply.ok) { throw ('account.list refused '+$reply.code) }
    return $reply.payload
}
function Snapshot {
    $rows=@{}
    foreach($account in @((AccountList).accounts)) {
        if ($account.role -ne 'player') { continue }
        $entry=@{}
        foreach($game in @('shooter','turns')) { $s=Rk-Coins $account.user_id $game; $entry[$game]=@{credits=[long]$s.credits;revision=[long]$s.revision;owned=@($s.owned | Sort-Object)} }
        $rows[$account.user_id]=$entry
    }
    return $rows
}
function SameSnapshot($Saved,$Now) {
    $names=@($Saved.PSObject.Properties.Name)
    if ($names.Count -ne @($Now.Keys).Count) { return $false }
    foreach($user in $names) {
        if (-not $Now.ContainsKey($user)) { return $false }
        foreach($game in @('shooter','turns')) {
            $a=$Saved.$user.$game; $b=$Now[$user][$game]
            if ([long]$a.credits -ne $b.credits -or [long]$a.revision -ne $b.revision -or (@($a.owned) -join ',') -ne (@($b.owned) -join ',')) { return $false }
        }
    }
    return $true
}
## Processes whose command line names this project (pid -> start time), from /proc.
function ProjectProcesses {
    $found=@{}
    foreach($entry in Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction SilentlyContinue) {
        if ($entry.Name -notmatch '^[0-9]+$' -or [int]$entry.Name -eq $PID) { continue }
        try {
            $command=([IO.File]::ReadAllText('/proc/'+$entry.Name+'/cmdline')).Replace([char]0,' ')
            if (-not $command.Contains($project)) { continue }
            $stat=[IO.File]::ReadAllText('/proc/'+$entry.Name+'/stat')
            $fields=$stat.Substring($stat.LastIndexOf(')')+2).Split(' ')
            $found[[int]$entry.Name]=@{start=$fields[19];command=$command;state=$fields[0]}
        } catch { }
    }
    return $found
}
function StillThere($Recorded) {
    $now=ProjectProcesses
    return @($Recorded.Keys | Where-Object { $now.ContainsKey($_) -and $now[$_].start -eq $Recorded[$_].start -and $now[$_].state -ne 'Z' })
}
## Files under the given folders and process command lines that contain any secret.
function SecretHits([string[]]$Secrets,[string[]]$Folders) {
    $hits=New-Object Collections.ArrayList
    foreach($folder in $Folders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach($file in Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue) {
            if ($file.Name -like '*.sqlite*' -or $file.FullName.StartsWith($state)) { continue }
            if ($file.Length -gt 20MB) { continue }
            $text=[IO.File]::ReadAllText($file.FullName)
            foreach($secret in $Secrets) { if ($secret -and $text.Contains($secret)) { [void]$hits.Add($file.FullName.Substring($project.Length+1)); break } }
        }
    }
    foreach($entry in (ProjectProcesses).Values) { foreach($secret in $Secrets) { if ($secret -and $entry.command.Contains($secret)) { [void]$hits.Add('command line'); break } } }
    return $hits
}

$operator=$null
try {
    # In the fault phase no Operator runs yet: this script starts its own below.
    if ($Phase -ne 'fault') { Require (Rk-WaitApi 90) 'the Operator panel answers' }
    switch ($Phase) {
        'prepare' {
            if ((Rk-Api 'setup.status' @{} -Anonymous).payload.initialized) { throw 'This instance already has an administrator; prepare needs a new instance.' }
            $admin=@{username=('l3admin_'+[Guid]::NewGuid().ToString('N').Substring(0,6));password=(NewSecret 'Adm!')}
            Rk-SaveJson $adminFile $admin
            $setup=Rk-Api 'setup.create' $admin -Anonymous
            Require ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'administrator created through the panel API'
            $script:RkToken=$setup.payload.token
            $start=Rk-Api 'server.start'
            Require $start.ok ('the real managed host starts ('+$start.code+')')
            $room=Rk-Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=4}
            Require $room.ok 'a shooter room is created'
            $row=Rk-WaitRoom $room.payload.room_id
            Require ($null -ne $row -and $row.state -eq 'READY') 'the shooter room is READY (its UDP port bound)'
            $invite=Rk-Api 'invite.create' @{uses=12;expires_hours=2;reason='linux same-machine acceptance'}
            Require $invite.ok 'invitation created'
            $context=@{url=$script:RkApiUrl;panel_port=$PanelPort;test_root=$state;evidence=$evidence;token=$script:RkToken;invite_code=$invite.payload.invite_code;room_id=$room.payload.room_id;connection=(Rk-Connection (Join-Path $Instance 'public'))}
            Rk-SaveJson (Join-Path $state 'test-context.json') $context
            Rk-SaveJson (Join-Path (Join-Path $project 'run') 'operator-test-context.json') @{path=(Join-Path $state 'test-context.json')}
        }
        'persist' {
            Require (Rk-AdminLogin $adminFile) 'administrator logs in again'
            Remove-Item -LiteralPath (Join-Path (Join-Path $project 'run') 'operator-test-context.json') -ErrorAction SilentlyContinue
            $invite=Rk-Api 'invite.create' @{uses=1;expires_hours=1;reason='persistence player'}
            $player=@{username=('l3keep_'+[Guid]::NewGuid().ToString('N').Substring(0,6));password=(NewSecret 'Keep!');display_name='KeepPlayer'}
            $client=Client 'keeper' 'turns' @{username=$player.username;password=$player.password;display_name=$player.display_name;invite_code=$invite.payload.invite_code;register=$true}
            $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
            Require ($null -ne $ready -and $ready.user_id) 'a further player registers and logs in through the real lobby'
            $player.user_id=$ready.user_id
            Rk-SaveJson $persistFile $player
            Require (Rk-Api 'asset.adjust' @{user_id=$player.user_id;game_id='turns';coins_delta=120;xp_delta=5;operation_id=[Guid]::NewGuid().ToString('N');reason='persistence funding'}).ok 'administrator funds the player'
            [void](Rk-Command $client 'read')
            $key='jade_'+[Guid]::NewGuid().ToString('N')
            $bought=Rk-Command $client 'purchase' @{item_id='jade';operation_id=$key}
            Require ($null -ne $bought -and $bought.ok -and 'jade' -in $bought.state.owned) 'the player buys an item in the lobby'
            $replay=Rk-Command $client 'purchase' @{item_id='jade';operation_id=$key}
            Check ($null -ne $replay -and $replay.ok -and [long]$replay.state.credits -eq [long]$bought.state.credits) 'repeating the same purchase returns the original receipt (no second debit)'
            $chosen=Rk-Command $client 'select' @{slot='theme';item_id='jade';operation_id=('theme_'+[Guid]::NewGuid().ToString('N'))}
            Require ($null -ne $chosen -and $chosen.ok -and $chosen.state.profiles.turns.theme -eq 'jade') 'the player selects the item'
            Check (Rk-StopClient $client) 'the client closes by itself'
            Require (Rk-Api 'server.stop' @{immediate=$true;reason='backup and restore'}).ok 'host stop requested'
            Require ((Rk-WaitHost 'STOPPED').host.state -eq 'STOPPED') 'host stopped'
            $before=Snapshot
            $total=[long](AccountList).total
            Check ($before.Count -ge 3) ('assets of every player are read ('+$before.Count+' players)')
            $backup=Rk-Api 'backup.create' @{reason='linux acceptance'}
            Require $backup.ok 'backup created'
            Require (Rk-Api 'asset.adjust' @{user_id=$player.user_id;game_id='turns';coins_delta=77;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='change to be undone'}).ok 'a change after the backup'
            Check ([long](Rk-Coins $player.user_id 'turns').credits -eq $before[$player.user_id].turns.credits+77) 'the change is visible'
            $restored=Rk-Api 'backup.restore' @{backup_id=$backup.payload.backup_id;reason='linux acceptance restore'}
            Require $restored.ok ('backup restored ('+$restored.code+')')
            Require (Rk-AdminLogin $adminFile) 'the administrator logs in after the restore (sessions were revoked)'
            $after=Snapshot
            Check ([long](AccountList).total -eq $total) 'the restore kept every account (it is not an emptied database)'
            Check (SameSnapshot ($before | ConvertTo-Json -Depth 10 | ConvertFrom-Json) $after) 'the restore undid exactly the later change; every other asset is unchanged'
            Rk-SaveJson $snapshotFile @{players=$after;keeper=$after[$player.user_id].turns;theme='jade'}
        }
        'after-restart' {
            Require (Rk-AdminLogin $adminFile) 'administrator logs in after the service restart'
            $saved=Rk-ReadJson $snapshotFile
            Check (SameSnapshot $saved.players (Snapshot)) 'after the restart every player asset equals the snapshot'
            $start=Rk-Api 'server.start'
            Require $start.ok ('the host starts again ('+$start.code+')')
            $player=Rk-ReadJson $persistFile
            $client=Client 'keeper-again' 'turns' @{username=$player.username;password=$player.password;register=$false}
            $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
            Require ($null -ne $ready) 'the player logs in again with the same password'
            $read=Rk-Command $client 'read'
            Check ($null -ne $read -and $read.ok -and [long]$read.state.credits -eq [long]$saved.keeper.credits -and 'jade' -in $read.state.owned -and $read.state.profiles.turns.theme -eq 'jade') 'the player sees the same credits, item and selection'
            Check (Rk-StopClient $client) 'the client closes by itself'
            Require (Rk-Api 'server.stop' @{immediate=$true;reason='after restart'}).ok 'host stop requested'
            Check ((Rk-WaitHost 'STOPPED').host.state -eq 'STOPPED') 'host stopped'
        }
        'fault' { throw 'fault is started below' }
        'after-fault' {
            Require (Rk-AdminLogin $adminFile) 'administrator logs in to the restarted Operator'
            $deadline=[DateTime]::UtcNow.AddSeconds(60)
            do { $host_=(Rk-Api 'status').payload.host; if ($host_.state -eq 'STOPPED' -and -not (Test-Path -LiteralPath (Join-Path $data 'host-running.json'))) { break }; Start-Sleep -Milliseconds 500 } while ([DateTime]::UtcNow -lt $deadline)
            Check ($host_.state -eq 'STOPPED' -and -not (Test-Path -LiteralPath (Join-Path $data 'host-running.json'))) 'read-only recovery found the old host gone and cleared its marker'
            $start=Rk-Api 'server.start'
            Check $start.ok ('a new host starts after the old room journal was checked ('+$start.code+')')
            $journal=Rk-ReadJson (Join-Path $data 'processes.json')
            Check ($null -ne $journal -and @($journal.entries.PSObject.Properties).Count -eq 0) 'the old room entries left the journal only after their exit and port were confirmed'
            $room=Rk-Api 'room.create' @{game_id='turns';mode='sandbox';map='table';capacity=4}
            Check ($room.ok -and (Rk-WaitRoom $room.payload.room_id).state -eq 'READY') 'a new room becomes READY'
            $saved=Rk-ReadJson $snapshotFile
            Check (SameSnapshot $saved.players (Snapshot)) 'player assets are unchanged by the fault'
            Require (Rk-Api 'server.stop' @{immediate=$true;reason='after fault'}).ok 'host stop requested'
            Check ((Rk-WaitHost 'STOPPED').host.state -eq 'STOPPED') 'host stopped'
        }
    }
} catch {
    if ($_.Exception.Message -ne 'fault is started below') { $script:failed++; Write-Output ('ACCEPTANCE_ERROR '+$_.Exception.Message) }
} finally {
    foreach($client in $clients) { try { [void](Rk-StopClient $client) } catch { } }
}

if ($Phase -eq 'fault') {
    $logs=Join-Path $Instance 'logs'
    $secrets=@()
    try {
        $arguments=@('--headless','--path',$project,'--log-file',(Join-Path $logs 'operator-fault.log'),'--script','res://host/operator.gd','--',('--data-root='+$data),('--games='+(Join-Path $Instance 'games.json')),('--public-client-dir='+(Join-Path $Instance 'public')),('--operator-log-path='+(Join-Path $logs 'operator-fault.log')),('--panel-port='+$PanelPort))
        $operator=Rk-StartHidden $Godot $arguments (Join-Path $logs 'console-fault.log') (Join-Path $logs 'stderr-fault.log')
        Require (Rk-WaitApi 90) 'this test started its own Operator for the fault (its direct child)'
        Require (Rk-AdminLogin $adminFile) 'administrator logs in'
        $secrets=@((Rk-ReadJson $adminFile).password,(Rk-ReadJson $persistFile).password,$script:RkToken)
        Require (Rk-Api 'server.start').ok 'host started'
        $room=Rk-Api 'room.create' @{game_id='turns';mode='sandbox';map='table';capacity=4}
        Require ($room.ok -and (Rk-WaitRoom $room.payload.room_id).state -eq 'READY') 'a room is READY'
        $player=Rk-ReadJson $persistFile
        $client=Client 'keeper-fault' 'turns' @{username=$player.username;password=$player.password;register=$false;room_id=$room.payload.room_id}
        $seated=Rk-WaitReport $client {param($r) $r.phase -eq 'IN_ROOM'} 90
        Require ($null -ne $seated) 'a player is seated in the room'
        $tree=ProjectProcesses
        $children=@{}
        foreach($id in $tree.Keys) { if ($id -ne $operator.Id -and ($tree[$id].command.Contains('managed_host') -or $tree[$id].command.Contains('--launch-id='))) { $children[$id]=$tree[$id] } }
        Check ($children.Count -ge 2) ('the host and its room are running ('+$children.Count+' processes)')
        $own=$tree[$operator.Id]
        Require ($null -ne $own -and $own.command.Contains('--data-root='+$data)) 'the Operator to be killed is this test''s own child with this instance''s data root'
        $operator.Kill()
        Require ($operator.WaitForExit(15000)) 'the Operator was killed and its exit confirmed'
        Write-Output ('INFO operator_exit_code='+$operator.ExitCode)
        $deadline=[DateTime]::UtcNow.AddSeconds(60)
        while ((StillThere $children).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
        $left=StillThere $children
        Check ($left.Count -eq 0) ('host and room left by themselves after losing their controller ('+$left.Count+' still running)')
        $report=Rk-WaitReport $client {param($r) $r.phase -ne 'IN_ROOM'} 30
        Check ($null -ne $report -and $report.phase -ne 'IN_ROOM') 'the seated player reported losing the room (a timeout is not evidence)'
        foreach($c in $clients) { Check (Rk-StopClient $c) 'the fault-test client closes normally with exit code zero' }
        Check (Test-Path -LiteralPath (Join-Path $data 'host-running.json')) 'the host marker of the killed Operator is kept for the next start'
        $hits=SecretHits $secrets @($logs,(Join-Path $project 'run'),$data,$evidence)
        Check ($hits.Count -eq 0) ('no password or session token in logs, runtime files, data JSON or command lines ('+(@($hits | Select-Object -Unique) -join ', ')+')')
        $runLeft=@(Get-ChildItem -LiteralPath (Join-Path $project 'run') -Filter '*.json' -File -ErrorAction SilentlyContinue)
        Write-Output ('INFO runtime files left by the killed Operator: '+$runLeft.Count)
    } catch {
        $script:failed++
        Write-Output ('ACCEPTANCE_ERROR '+$_.Exception.Message)
    } finally {
        foreach($client in $clients) { try { [void](Rk-StopClient $client) } catch { } }
        if ($null -ne $operator -and -not $operator.HasExited) {
            # Only reached when the test failed before the kill: ask it to stop.
            [IO.File]::WriteAllText((Join-Path $data 'operator-stop.request'),'stop')
            if (-not $operator.WaitForExit(90000)) { $operator.Kill(); [void]$operator.WaitForExit(10000); $script:failed++; Write-Output 'FAIL the Operator of this test did not stop on request' }
        }
    }
}
Write-Output ('L3_ACCEPTANCE_RESULT phase='+$Phase+' passed='+$script:passed+' failed='+$script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
