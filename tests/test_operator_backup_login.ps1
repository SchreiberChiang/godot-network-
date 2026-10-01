param([string]$ProjectRoot='', [string]$GamesIndex='', [string]$Godot='', [switch]$VerboseEngine)
# Real isolated Operator/host, WSS client and SQLite backup. Each trial is one
# separately started login, never an automatic replay. Up to three trials only
# to establish an actual overlap between backup and login; a login failure is
# always a failure. No production directory or shared public file is written.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
if(-not $ProjectRoot){$ProjectRoot=Join-Path $PSScriptRoot '..'}
$project=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('/','\')
. (Join-Path $project 'tests/support/portable.ps1')
. (Join-Path $project 'tests/support/client_harness.ps1')
$Godot=Rk-Godot $Godot
if(-not $GamesIndex){$GamesIndex=Join-Path $project 'artifacts/framework-games.json'}
$id=[Guid]::NewGuid().ToString('N')
$root=Join-Path $project ('data/test-backup-login-'+$id)
Rk-ProtectData $project $root
Rk-ProtectRuntime $project
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Path $evidence|Out-Null
if($script:RkPosix){[IO.File]::SetUnixFileMode($evidence,[IO.UnixFileMode]'UserRead,UserWrite,UserExecute')}
function FreePort {
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    $listener.Start(); $port=$listener.LocalEndpoint.Port; $listener.Stop(); return $port
}
$panel=FreePort
$public=Join-Path $root 'public'
$index=Join-Path $root 'games.json'
Rk-SaveJson $index (Rk-ReadJson $GamesIndex)
$games=Rk-ReadJson $index
Rk-SaveJson (Join-Path $root 'config.json') @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=(FreePort);control_port=(FreePort);game_bind='127.0.0.1';udp_first=28740;udp_last=28755;max_rooms=2;asset_spaces=@{shooter='shooter';turns='turns'}}
$script:RkApiUrl='http://127.0.0.1:'+$panel
$console=Join-Path $evidence 'console.log'
$stderr=Join-Path $evidence 'stderr.log'
$passed=0; $failed=0; $observed=0; $client=$null; $http=$null
function Check([bool]$Value,[string]$Label) {
    if($Value){$script:passed++; Write-Output ('PASS '+$Label)}else{$script:failed++; Write-Output ('FAIL '+$Label); throw $Label}
}
function WaitOffline {
    $until=[DateTime]::UtcNow.AddSeconds(25)
    do {
        $state=Rk-Api 'status'
        if($state.ok -and @($state.payload.players).Count -eq 0 -and
           $state.payload.session_cleanup.pending -eq 0 -and
           $state.payload.session_cleanup.running -eq 0 -and
           $state.payload.session_cleanup.failed -eq 0){return $true}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $until)
    return $false
}
function ReadConsole {
    $stream=New-Object IO.FileStream($console,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
    try {return $reader.ReadToEnd()} finally {$reader.Dispose()}
}
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $evidence 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$root),('--games='+$index),('--public-client-dir='+$public),('--panel-port='+$panel),('--operator-log-path='+(Join-Path $evidence 'operator.log')))
if($VerboseEngine){$arguments=@('--verbose')+$arguments}
$operator=Rk-StartHidden $Godot $arguments $console $stderr
try {
    Check (Rk-WaitApi 90) 'new isolated Operator is ready'
    $admin=Rk-Api 'setup.create' @{username=('backupadmin_'+$id.Substring(0,8));password=('Admin!'+[Guid]::NewGuid().ToString('N'))} -Anonymous
    Check $admin.ok 'new administrator created without using real credentials'
    $script:RkToken=$admin.payload.token
    Check (Rk-Api 'server.start').ok 'real managed host starts'
    $invitation=Rk-Api 'invite.create' @{uses=1;expires_hours=1;reason='backup login overlap test'}
    Check $invitation.ok 'one isolated invitation created'
    $account=@{username=('backupplayer_'+$id.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name='BackupProbe'}
    $connection=Rk-Connection $public
    $credentials=$account.Clone(); $credentials.register=$true; $credentials.invite_code=$invitation.payload.invite_code
    $client=Rk-StartClient $Godot $project $evidence 'register' 'turns' $connection $games.turns.manifest $credentials
    $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
    Check ($null -ne $ready) 'real WSS player registers and logs in'
    Check (Rk-StopClient $client) 'registration client closes with exit code zero'
    $client=$null
    Check (WaitOffline) 'previous session is cleaned before the overlap trial'
    Add-Type -AssemblyName System.Net.Http
    $http=New-Object System.Net.Http.HttpClient
    $http.Timeout=[TimeSpan]::FromSeconds(65)
    $http.DefaultRequestHeaders.ExpectContinue=$false
    for($trial=1;$trial -le 3 -and $observed -eq 0;$trial++) {
        $before=(ReadConsole).Length
        $request=New-Object System.Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($script:RkApiUrl+'/api'))
        $request.Headers.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$script:RkToken)
        $request.Content=New-Object Net.Http.StringContent('{"action":"backup.create","payload":{"reason":"backup login overlap test"}}',[Text.Encoding]::UTF8,'application/json')
        $task=$http.SendAsync($request)
        $until=[DateTime]::UtcNow.AddSeconds(10)
        do { $tail=(ReadConsole).Substring($before); if($tail.Contains('event=backup_begin')){break}; Start-Sleep -Milliseconds 10 }while([DateTime]::UtcNow -lt $until)
        Check ($tail.Contains('event=backup_begin')) ('trial '+$trial+' real backup window began')
        $credentials=$account.Clone(); $credentials.register=$false
        $client=Rk-StartClient $Godot $project $evidence ('login-'+$trial) 'turns' $connection $games.turns.manifest $credentials
        $ready=Rk-WaitReport $client {param($r) $r.phase -eq 'LOBBY' -and $r.ok} 90
        Check ($null -ne $ready) ('trial '+$trial+' original login completes without client retry')
        $reply=$task.GetAwaiter().GetResult()
        $body=$reply.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
        Check ($reply.IsSuccessStatusCode -and $body.ok) ('trial '+$trial+' real SQLite backup succeeds')
        $tail=(ReadConsole).Substring($before)
        $waits=@([regex]::Matches($tail,'OPERATOR_BACKUP_WAIT t=\d+ event=finished code=OK ms=(\d+) waiting=\d+'))
        if($waits.Count -gt 0){$observed++; Write-Output ('BACKUP_LOGIN_WAIT trial='+$trial+' ms='+$waits[0].Groups[1].Value)}else{Write-Output ('BACKUP_LOGIN_NO_OVERLAP trial='+$trial)}
        Check (Rk-StopClient $client) ('trial '+$trial+' login client closes with exit code zero')
        $client=$null
        Check (WaitOffline) ('trial '+$trial+' new session is cleaned')
        $reply.Dispose(); $request.Dispose()
    }
    Check ($observed -gt 0) 'at least one real account request waited through a real backup'
} catch {
    if($failed -eq 0){$failed++}
    Write-Output ('FAIL backup login probe: '+$_.Exception.Message)
} finally {
    if($null -ne $client){try{if(-not (Rk-StopClient $client)){$failed++}}catch{$failed++}}
    if($null -ne $http){$http.Dispose()}
    try{
        $stop=Rk-Api 'server.stop' @{immediate=$true;reason='backup login cleanup'}
        if(-not $stop.ok){$failed++; Write-Output 'FAIL probe host stop request was refused'}
        $stopped=Rk-WaitHost 'STOPPED' 45
        if($null -eq $stopped -or $stopped.host.state -ne 'STOPPED'){$failed++; Write-Output 'FAIL probe host did not confirm STOPPED'}
    }catch{$failed++; Write-Output 'FAIL probe host stop could not be confirmed'}
    [IO.File]::WriteAllText((Join-Path $root 'operator-stop.request'),'stop')
    if($script:RkPosix){[IO.File]::SetUnixFileMode((Join-Path $root 'operator-stop.request'),[IO.UnixFileMode]'UserRead,UserWrite')}
    if(-not $operator.WaitForExit(60000)){$operator.Kill();[void]$operator.WaitForExit(10000);$failed++}
    if($operator.ExitCode -ne 0){$failed++}
    if((Get-Item $stderr).Length -gt 0){$failed++; Write-Output 'FAIL isolated Operator stderr is not empty'}
    Rk-SaveJson (Join-Path $evidence 'result.json') @{passed=$passed;failed=$failed;observed=$observed}
    Write-Output ('OPERATOR_BACKUP_LOGIN_RESULT passed='+$passed+' failed='+$failed+' observed='+$observed+' operator_exit='+$operator.ExitCode+' evidence='+$evidence)
}
if($failed -gt 0){exit 1}; exit 0
