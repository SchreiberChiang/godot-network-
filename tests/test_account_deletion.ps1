param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Test-stage account deletion through a real, isolated Operator (docs/17 section 7):
# a real managed host and room, two real WSS clients (the victim sits in the room),
# admin protection, typed confirmation, online kick, old credentials, other player
# untouched, audit and journal de-identification, backup marking, restoring an older
# backup brings the account back, an Operator audit write failure that is reported as
# incomplete and finished by a retry, administrator reasons that name the account, and
# deletions interrupted before and after the database steps finished on Operator start-up. Only fake accounts in data\test-account-deletion-<id> are touched.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testId=[Guid]::NewGuid().ToString('N')
$testRoot=Join-Path $project ('data\test-account-deletion-'+$testId)
$evidence=Join-Path $project ('logs\account-deletion-'+$testId)
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot | Out-Null
& (Join-Path $project 'tools\protect_runtime.ps1') -ProjectRoot $project | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
function Free-TcpPort { $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start(); $n=$l.LocalEndpoint.Port; $l.Stop(); return $n }
function Save-Json($path,$value) { [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 40 -Compress),$utf8) }
function Read-Json($path) { if (Test-Path -LiteralPath $path) { try { return Get-Content -Encoding UTF8 -Raw -LiteralPath $path | ConvertFrom-Json } catch { return $null } }; return $null }
$panelPort=Free-TcpPort
$settings=@{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=(Free-TcpPort);game_bind='127.0.0.1';control_port=(Free-TcpPort);udp_first=28640;udp_last=28671;max_rooms=16;asset_spaces=@{shooter='shooter';turns='turns'}}
Save-Json (Join-Path $testRoot 'config.json') $settings
$baseUrl='http://127.0.0.1:'+$panelPort
$script:adminToken=''
$script:passed=0
$script:failed=0
function Api($action,$payload=@{},[switch]$Anonymous) {
    $headers=@{}
    if ($script:adminToken -and -not $Anonymous) { $headers.Authorization='Bearer '+$script:adminToken }
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload} | ConvertTo-Json -Depth 20 -Compress))
    try { return Invoke-RestMethod -Uri ($baseUrl+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65 }
    catch { throw ('API '+$action+' failed: '+$_.Exception.Message) }
}
function Check($condition,$name) {
    if ($condition) { $script:passed++; Write-Output ('PASS '+$name) } else { $script:failed++; Write-Output ('FAIL '+$name) }
}
function Start-Operator([string]$Label) {
    $arguments=@('--headless','--path',$project,'--log-file',(Join-Path $evidence ('operator-'+$Label+'.log')),'--script','res://host/operator.gd','--',('--data-root='+$testRoot),('--panel-port='+$panelPort))
    $quoted=foreach($a in $arguments) { '"'+($a -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $p=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence ('console-'+$Label+'.log')) -RedirectStandardError (Join-Path $evidence ('stderr-'+$Label+'.log'))
    $null=$p.Handle
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    $ready=$false
    while (-not $ready -and [DateTime]::UtcNow -lt $deadline -and -not $p.HasExited) {
        try { $ready=(Api 'setup.status' @{} -Anonymous).ok } catch { Start-Sleep -Milliseconds 300 }
    }
    if (-not $ready) { throw ('Operator '+$Label+' did not become ready') }
    return $p
}
function Stop-Operator($p) {
    if ($null -eq $p -or $p.HasExited) { return }
    [IO.File]::WriteAllText((Join-Path $testRoot 'operator-stop.request'),'stop')
    if (-not $p.WaitForExit(65000)) { $p.Kill(); $p.WaitForExit(); $script:failed++; Write-Output 'FAIL operator graceful shutdown watchdog' }
    Write-Output ('OPERATOR_PROCESS_EXIT='+$p.ExitCode)
    if ($p.ExitCode -ne 0) { $script:failed++ }
}
function Wait-HostState([string]$State) {
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    do { Start-Sleep -Milliseconds 300; $s=(Api 'status').payload } while ($s.host.state -ne $State -and [DateTime]::UtcNow -lt $deadline)
    return $s
}
function Online([string]$UserId) { return @((Api 'status').payload.players | Where-Object user_id -eq $UserId).Count -gt 0 }
function Offline-Helper([hashtable]$Config) {
    $private=Join-Path $testRoot ('offline-'+[Guid]::NewGuid().ToString('N')+'.json')
    $Config.data_root=$testRoot
    Save-Json $private $Config
    $arguments=@('--headless','--path',$project,'--script','res://tests/fixtures/deletion_offline.gd','--',('--config='+$private))
    $quoted=foreach($a in $arguments) { '"'+($a -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $log=Join-Path $evidence ('offline-'+$Config.mode+'.log')
    $p=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError ($log+'.stderr')
    $null=$p.Handle
    if (-not $p.WaitForExit(120000)) { $p.Kill(); return $null }
    Remove-Item -LiteralPath $private -ErrorAction SilentlyContinue
    $line=Select-String -Path $log -Pattern '^DELETION_OFFLINE (.+)$' | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return $line.Matches[0].Groups[1].Value | ConvertFrom-Json
}
function Start-Client([string]$Name,[hashtable]$Extra) {
    $directory=Join-Path $evidence $Name
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $bootstrap=Join-Path $testRoot ('client-'+$Name+'.json')
    $builds=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'artifacts/framework-games.json') | ConvertFrom-Json
    $connection=@{url=('wss://127.0.0.1:'+$settings.lobby_port);ca_certificate=(Join-Path $testRoot 'server.crt');server_hostname='localhost';game_id='shooter'}
    $config=@{connection=$connection;manifest=$builds.shooter.manifest;game_id='shooter';report_path=(Join-Path $directory 'report.json');control_directory=$directory;timeout_ms=600000;register=$true}
    foreach($k in $Extra.Keys) { $config[$k]=$Extra[$k] }
    Save-Json $bootstrap $config
    $arguments=@('--headless','--path',$project,'--script','res://tests/run_deletion_client.gd','--',('--test-config='+$bootstrap))
    $quoted=foreach($a in $arguments) { '"'+($a -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $p=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'console.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $null=$p.Handle
    return @{process=$p;directory=$directory;report=(Join-Path $directory 'report.json')}
}
function Wait-Report($client,[scriptblock]$Condition,[int]$Seconds) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $r=Read-Json $client.report
        if ($null -ne $r -and (& $Condition $r)) { return $r }
        if ($client.process.HasExited) { return (Read-Json $client.report) }
        Start-Sleep -Milliseconds 200
    }
    return (Read-Json $client.report)
}
$operator=$null
$clients=@()
try {
    $operator=Start-Operator 'first'
    $adminName='dqadmin_'+$testId.Substring(0,6)
    $adminPassword='Test!'+[Guid]::NewGuid().ToString('N')
    $setup=Api 'setup.create' @{username=$adminName;password=$adminPassword} -Anonymous
    Check ($setup.ok -and $setup.payload.identity.role -eq 'admin') 'isolated administrator setup'
    $script:adminToken=$setup.payload.token
    $adminId=$setup.payload.identity.user_id
    Check (Api 'server.start').ok 'real managed host start'
    $room=Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=4}
    $roomId=$room.payload.room_id
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    do { Start-Sleep -Milliseconds 300; $row=@((Api 'status').payload.rooms | Where-Object room_id -eq $roomId)[0] } while (($null -eq $row -or $row.state -ne 'READY') -and [DateTime]::UtcNow -lt $deadline)
    Check ($null -ne $row -and $row.state -eq 'READY') 'real shooter room READY'
    $invite=(Api 'invite.create' @{uses=6;expires_hours=1;reason='deletion acceptance'}).payload.invite_code
    $victimName='dqvictim_'+$testId.Substring(0,6)
    $keeperName='dqkeeper_'+$testId.Substring(0,6)
    $victimPassword='Del!'+[Guid]::NewGuid().ToString('N')
    $victim=Start-Client 'victim' @{username=$victimName;password=$victimPassword;display_name='DeletionVictim';invite_code=$invite;join_room_id=$roomId;expect_deleted=$true}
    $keeper=Start-Client 'keeper' @{username=$keeperName;password=('Keep!'+[Guid]::NewGuid().ToString('N'));display_name='DeletionKeeper';invite_code=$invite;expect_deleted=$false}
    $clients=@($victim,$keeper)
    $v=Wait-Report $victim {param($r) $r.ok -and $r.user_id -and $r.phase -eq 'LOBBY'} 120
    $k=Wait-Report $keeper {param($r) $r.ok -and $r.user_id -and $r.phase -eq 'LOBBY'} 120
    Check ($null -ne $v -and $v.phase -eq 'LOBBY') 'victim client signed in'
    Check ($null -ne $k -and $k.phase -eq 'LOBBY') 'keeper client signed in'
    if ($null -eq $v -or $null -eq $k -or -not $v.user_id -or -not $k.user_id) { throw 'Clients not ready' }
    $victimId=$v.user_id; $keeperId=$k.user_id
    foreach($pair in @(@($victimId,'shooter',1000),@($victimId,'turns',50),@($keeperId,'shooter',1000))) {
        Check (Api 'asset.adjust' @{user_id=$pair[0];game_id=$pair[1];coins_delta=$pair[2];xp_delta=10;operation_id=[Guid]::NewGuid().ToString('N');reason='deletion acceptance funding'}).ok ('funded '+$pair[1])
    }
    foreach($c in $clients) { [IO.File]::WriteAllText((Join-Path $c.directory 'funded.flag'),'1',$utf8) }
    $v=Wait-Report $victim {param($r) $null -ne $r.joined} 90
    $k=Wait-Report $keeper {param($r) $null -ne $r.purchase_ok} 60
    Check ($v.purchase_ok -and $k.purchase_ok) ('both players bought an item through the real lobby ('+$v.purchase_code+'/'+$k.purchase_code+')')
    Check ($v.joined -and $v.phase -eq 'IN_ROOM') 'victim then seated in the real room'
    $keeperBefore=(Api 'asset.read' @{user_id=$keeperId;game_id='shooter'}).payload.state
    # Administrator free text elsewhere that names the victim (username in another case, user_id).
    Check (Api 'asset.adjust' @{user_id=$keeperId;game_id='turns';coins_delta=7;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason=('gift from '+$victimName.ToUpperInvariant()+' '+$victimId)}).ok 'keeper adjustment whose reason names the victim'
    $olderBackup=(Api 'backup.create' @{reason=('before deleting '+$victimName)}).payload.backup_id
    Check ($olderBackup -ne $null) 'older backup created while the victim exists (reason names the victim)'
    Check (Online $victimId) 'victim listed online before deletion'

    $self=Api 'account.delete' @{user_id=$adminId;confirm_username=$adminName;reason='acceptance'}
    Check ((-not $self.ok) -and $self.code -eq 'ADMIN_SELF_PROTECTION') 'administrator account cannot be deleted'
    $wrong=Api 'account.delete' @{user_id=$victimId;confirm_username=$keeperName;reason='acceptance'}
    Check ((-not $wrong.ok) -and $wrong.code -eq 'DELETE_CONFIRMATION_MISMATCH') 'wrong typed username refused'
    Check ((Online $victimId) -and (Api 'account.get' @{user_id=$victimId}).ok) 'refusals left the victim untouched'
    # Operator audit write failure during the close-out: incomplete, then a retry finishes.
    $auditPath=Join-Path $testRoot 'operator-audit.jsonl'
    Set-ItemProperty -LiteralPath $auditPath -Name IsReadOnly -Value $true
    $sensitive='cleanup of '+$victimName.ToUpperInvariant()+' ('+$victimId+')'
    $first=Api 'account.delete' @{user_id=$victimId;confirm_username=$victimName.ToUpperInvariant();reason=$sensitive}
    Save-Json (Join-Path $evidence 'delete-response-incomplete.json') $first
    Check ((-not $first.ok) -and $first.code -eq 'ACCOUNT_DELETION_INCOMPLETE' -and $first.payload.stage -eq 'operator' -and $first.payload.cause -eq 'AUDIT_WRITE_FAILED') ('operator audit write failure reported as incomplete ('+$first.code+'/'+$first.payload.stage+'/'+$first.payload.cause+')')
    Check ((Api 'account.get' @{user_id=$victimId}).code -eq 'ACCOUNT_ALREADY_DELETED' -and [IO.File]::ReadAllText($auditPath).Contains($victimId)) 'both databases done but the operator audit still pending'
    Set-ItemProperty -LiteralPath $auditPath -Name IsReadOnly -Value $false
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $deleted=Api 'account.delete' @{user_id=$victimId;confirm_username=$victimName;reason=$sensitive}
    $clock.Stop()
    Save-Json (Join-Path $evidence 'delete-response.json') $deleted
    Check ($deleted.ok -and $deleted.payload.state -eq 'done' -and $deleted.payload.resumed) ('retry finished the close-out and only then reported done ('+[int]$clock.Elapsed.TotalMilliseconds+' ms)')
    Check ($first.payload.was_online -and -not $first.payload.still_online) 'online victim kicked from lobby and room'
    Check (@($deleted.payload.backups_may_restore | Where-Object backup_id -eq $olderBackup).Count -eq 1) 'reply names the older backup that can restore the account'
    Check (-not (ConvertTo-Json $deleted -Depth 20 -Compress).Contains($victimId)) 'reply carries only the pseudonym'
    foreach($c in $clients) { [IO.File]::WriteAllText((Join-Path $c.directory 'check.flag'),'1',$utf8) }
    $v=Wait-Report $victim {param($r) $r.phase -eq 'DONE'} 60
    $k=Wait-Report $keeper {param($r) $r.phase -eq 'DONE'} 60
    Check ($v.socket_closed -and $v.state_after -ne 'IN_ROOM') 'victim client connection closed by the host'
    Check ((-not $v.read_after_ok) -and (-not $v.relogin_ok) -and $v.relogin_code -eq 'AUTH_FAILED') ('victim old session and credentials refused (relogin '+$v.relogin_code+')')
    Check ($k.read_after_ok -and -not $k.socket_closed) 'keeper stays connected and can read assets'
    $gone=Api 'account.get' @{user_id=$victimId}
    Check ((-not $gone.ok) -and $gone.code -eq 'ACCOUNT_ALREADY_DELETED') 'deleted account not readable'
    foreach($space in @('shooter','turns')) {
        $empty=(Api 'asset.read' @{user_id=$victimId;game_id=$space}).payload.state
        Check ([int]$empty.revision -eq 0 -and [int]$empty.credits -eq 0) ('victim asset state empty in '+$space)
    }
    $write=Api 'asset.adjust' @{user_id=$victimId;game_id='shooter';coins_delta=5;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='after deletion'}
    Check ((-not $write.ok) -and $write.code -eq 'ACCOUNT_DELETED') 'admin asset write for the deleted account refused'
    $keeperAfter=(Api 'asset.read' @{user_id=$keeperId;game_id='shooter'}).payload.state
    Check ((ConvertTo-Json $keeperAfter -Compress -Depth 10) -eq (ConvertTo-Json $keeperBefore -Compress -Depth 10)) 'keeper assets unchanged'
    $again=Api 'account.delete' @{user_id=$victimId;confirm_username=$victimName;reason=('again '+$victimName+' '+$victimId)}
    Check ((-not $again.ok) -and $again.code -eq 'ACCOUNT_ALREADY_DELETED') 'repeated deletion refused'
    $auditText=(ConvertTo-Json (Api 'audit.list' @{limit=100}).payload -Depth 20 -Compress).ToLowerInvariant()
    Check ($auditText.Contains('account.delete') -and -not $auditText.Contains($victimId) -and -not $auditText.Contains($victimName)) 'merged audit keeps the deletion without the user_id or username, reasons included'
    $backups=(Api 'backup.list').payload.backups
    Check (@($backups | Where-Object { $_.backup_id -eq $olderBackup -and $_.deleted_accounts -eq 1 }).Count -eq 1) 'backup list marks the older backup'
    $files=([IO.File]::ReadAllText((Join-Path $testRoot 'account-deletions.jsonl'))+[IO.File]::ReadAllText($auditPath)+[IO.File]::ReadAllText((Join-Path $testRoot 'maintenance-audit.jsonl'))).ToLowerInvariant()
    Check ($files.Contains('"event":"done"') -and $files.Contains('account.delete') -and -not $files.Contains($victimId) -and -not $files.Contains($victimName)) 'journal, operator audit and maintenance audit free of the user_id and username'
    $scan=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'tests\fixtures\deletion_database.ps1') -Directory $testRoot -Mode scan -Needles ($victimId+','+$victimName) | ConvertFrom-Json
    Check ($scan.ok -and $scan.total -eq 0) ('no row in either current database mentions the victim, reasons included ('+(ConvertTo-Json $scan.tables -Compress)+')')

    # Interruptions while the Operator is stopped: one job after the account step only,
    # one after both databases (before the Operator close-out). Start-up finishes both.
    $thirdName='dqthird_'+$testId.Substring(0,6)
    $third=Offline-Helper @{mode='register';username=$thirdName;password=('Third!'+[Guid]::NewGuid().ToString('N'));invite_code=$invite}
    $fourthName='dqfourth_'+$testId.Substring(0,6)
    $fourth=Offline-Helper @{mode='register';username=$fourthName;password=('Fourth!'+[Guid]::NewGuid().ToString('N'));invite_code=$invite}
    Check ($null -ne $third -and $third.ok -and $null -ne $fourth -and $fourth.ok) 'third and fourth fake players registered'
    $thirdId=$third.user_id; $fourthId=$fourth.user_id
    Check (Api 'asset.adjust' @{user_id=$thirdId;game_id='turns';coins_delta=30;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='resume fixture'}).ok 'third player funded'
    Check (Api 'asset.adjust' @{user_id=$fourthId;game_id='turns';coins_delta=40;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason=('resume fixture for '+$fourthName)}).ok 'fourth player funded (operator audit names it)'
    Check (Api 'server.stop' @{immediate=$true;reason='resume fixture'}).ok 'host stop accepted'
    Check ((Wait-HostState 'STOPPED').host.state -eq 'STOPPED') 'host stopped'
    Stop-Operator $operator
    $begun=Offline-Helper @{mode='begin';admin_username=$adminName;admin_password=$adminPassword;user_id=$thirdId;username=$thirdName}
    Check ($null -ne $begun -and $begun.ok -and $begun.state -eq 'assets_pending') 'third deletion interrupted after the account step'
    $finished=Offline-Helper @{mode='finish';admin_username=$adminName;admin_password=$adminPassword;user_id=$fourthId;username=$fourthName}
    Check ($null -ne $finished -and $finished.ok -and $finished.state -eq 'operator_pending') 'fourth deletion interrupted after both databases, before the Operator close-out'
    Check ([IO.File]::ReadAllText($auditPath).Contains($fourthId)) 'fourth player still named in the operator audit before restart'
    $operator=Start-Operator 'second'
    Check (@(Select-String -Path (Join-Path $evidence 'console-second.log') -Pattern 'OPERATOR_DELETION_RESUMED').Count -eq 2) 'operator start-up finished both open deletions'
    $login=Api 'admin.login' @{username=$adminName;password=$adminPassword} -Anonymous
    $script:adminToken=$login.payload.token
    Check ((Api 'account.get' @{user_id=$thirdId}).code -eq 'ACCOUNT_ALREADY_DELETED' -and (Api 'account.get' @{user_id=$fourthId}).code -eq 'ACCOUNT_ALREADY_DELETED') 'resumed accounts deleted'
    Check ([int](Api 'asset.read' @{user_id=$thirdId;game_id='turns'}).payload.state.credits -eq 0 -and [int](Api 'asset.read' @{user_id=$fourthId;game_id='turns'}).payload.state.credits -eq 0) 'resumed accounts assets deleted'
    $afterRestart=([IO.File]::ReadAllText($auditPath)+[IO.File]::ReadAllText((Join-Path $testRoot 'account-deletions.jsonl'))).ToLowerInvariant()
    Check (-not $afterRestart.Contains($thirdId) -and -not $afterRestart.Contains($fourthId) -and -not $afterRestart.Contains($fourthName)) 'start-up close-out de-identified the operator audit'
    $sha=[Security.Cryptography.SHA256]::Create()
    $fourthSubject='deleted_'+[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fourthId))).Replace('-','').ToLowerInvariant().Substring(0,32)
    Check ($afterRestart.Contains('"subject":"'+$fourthSubject+'"') -and $afterRestart.Contains($olderBackup)) 'journal entry for the resumed close-out lists the older backup'
    $scan=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'tests\fixtures\deletion_database.ps1') -Directory $testRoot -Mode scan -Needles ($thirdId+','+$thirdName+','+$fourthId+','+$fourthName) | ConvertFrom-Json
    Check ($scan.ok -and $scan.total -eq 0) ('no row in either current database mentions the resumed accounts ('+(ConvertTo-Json $scan.tables -Compress)+')')

    # Restoring the older backup brings the deleted account back, as the page warns.
    $restored=Api 'backup.restore' @{backup_id=$olderBackup;reason='show backup residue'}
    Check $restored.ok 'older backup restored with the host stopped'
    $login=Api 'admin.login' @{username=$adminName;password=$adminPassword} -Anonymous
    $script:adminToken=$login.payload.token
    $back=Api 'account.get' @{user_id=$victimId}
    Check ($back.ok -and [int](Api 'asset.read' @{user_id=$victimId;game_id='turns'}).payload.state.credits -eq 50) 'restoring the older backup brings the account and its assets back'
    Check (@((Api 'backup.list').payload.backups | Where-Object { $_.backup_id -eq $olderBackup -and $_.deleted_accounts -ge 1 }).Count -eq 1) 'backup mark survives the restore'
    Save-Json (Join-Path $evidence 'result.json') @{passed=$script:passed;failed=$script:failed;test_root=$testRoot}
} catch {
    $script:failed++
    Write-Output ('ACCOUNT_DELETION_TEST_ERROR '+$_.Exception.Message)
} finally {
    foreach($c in $clients) { if (-not $c.process.HasExited) { $c.process.Kill() } }
    Stop-Operator $operator
    Get-ChildItem -LiteralPath $testRoot -Filter 'client-*.json' -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
    Write-Output ('ACCOUNT_DELETION_E2E_RESULT passed='+$script:passed+' failed='+$script:failed)
}
if ($script:failed -gt 0) { exit 1 }
exit 0
