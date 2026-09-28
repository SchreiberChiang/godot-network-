param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',[switch]$Inner,[string]$Evidence='')
# Regression for the reported operator exit: Godot joins its parent's console, so
# closing the StartManagement window (a console control event) terminated the
# operator without _shutdown ("Thread destroyed", static-string/RID leaks, stale
# operator.json). Operator, host, room and the player client must now survive a
# control event on the launcher's console, and the operator must still stop
# cleanly. Isolated data root/ports; the test re-runs itself on its own hidden
# console because it sends Ctrl+C to that console.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $Inner) {
    $Evidence=Join-Path $project ('logs\detached-launch-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
    $log=Join-Path $Evidence 'test.log'
    $p=Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Inner','-Evidence',('"'+$Evidence+'"'),'-Godot',('"'+$Godot+'"'))
    $h=$p.Handle
    if(-not $p.WaitForExit(420000)) { $p.Kill(); Write-Output 'FAIL test timed out' }
    if(Test-Path $log) { Get-Content -Encoding UTF8 $log }
    exit $p.ExitCode
}
$log=Join-Path $Evidence 'test.log'
function Out([string]$Text) { Add-Content -Encoding UTF8 -LiteralPath $log -Value $Text }
$script:passed=0; $script:failed=0
function Check([bool]$c,[string]$n) { if($c){$script:passed++;Out ('PASS '+$n)}else{$script:failed++;Out ('FAIL '+$n)} }
Add-Type -Namespace RK -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList(uint[] list, uint count);
[DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint ev, uint group);
[DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(System.IntPtr h, bool add);
'@
function OnConsole([int]$ProcessId) { $l=New-Object uint32[] 128; $n=[RK.Con]::GetConsoleProcessList($l,128); return @($l[0..([Math]::Max(0,$n-1))]) -contains [uint32]$ProcessId }
function CtrlC { [void][RK.Con]::SetConsoleCtrlHandler([IntPtr]::Zero,$true); [void][RK.Con]::GenerateConsoleCtrlEvent(0,0); Start-Sleep -Seconds 3 }
function FreePort { $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); return $p }
. (Join-Path $project 'tools\detached_process.ps1')
[Net.ServicePointManager]::Expect100Continue=$false
$root=Join-Path $project ('data\test-detached-'+[IO.Path]::GetFileName($Evidence))
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $root | Out-Null
$gamesIndex=Join-Path $Evidence 'framework-games.json'
& (Join-Path $project 'tools\build_framework.ps1') -IndexPath $gamesIndex | Out-Null
$panel=FreePort
[IO.File]::WriteAllText((Join-Path $root 'config.json'),(@{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=(FreePort);game_bind='127.0.0.1';control_port=(FreePort);udp_first=28700;udp_last=28710;max_rooms=4;asset_spaces=@{shooter='shooter';turns='turns'}}|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
$base='http://127.0.0.1:'+$panel; $script:token=''
function Api($action,$payload=@{},[switch]$Anonymous) { $h=@{}; if($script:token -and -not $Anonymous){$h.Authorization='Bearer '+$script:token}; return Invoke-RestMethod -Uri ($base+'/api') -Method Post -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 10 -Compress))) -TimeoutSec 65 }
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $Evidence 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$root),('--panel-port='+$panel),('--games='+$gamesIndex),('--public-client-dir='+(Join-Path $Evidence 'public')))
$client=$null
$operator=Start-Detached $Godot $arguments $project (Join-Path $Evidence 'operator-console.log') (Join-Path $Evidence 'operator-stderr.log')
$operatorHandle=$operator.Handle
try {
    $d=[DateTime]::UtcNow.AddSeconds(45); $ready=$false
    while(-not $ready -and [DateTime]::UtcNow -lt $d -and -not $operator.HasExited) { try { $ready=(Api 'setup.status' @{} -Anonymous).ok } catch { Start-Sleep -Milliseconds 300 } }
    Check $ready 'operator started through Start-Detached is ready'
    Check (-not (OnConsole $operator.Id)) 'operator is not attached to the launcher console'
    $script:token=(Api 'setup.create' @{username='admin_detach';password=('Test!'+[Guid]::NewGuid().ToString('N'))} -Anonymous).payload.token
    Check (Api 'server.start').ok 'host start'
    $room=(Api 'room.create' @{game_id='shooter';mode='ffa';map='depot';capacity=2}).payload.room_id
    $d=[DateTime]::UtcNow.AddSeconds(45); do { Start-Sleep -Milliseconds 300; $r=@((Api 'status').payload.rooms|Where-Object room_id -eq $room)[0] } while(($null -eq $r -or $r.state -ne 'READY') -and [DateTime]::UtcNow -lt $d)
    Check ($r.state -eq 'READY') 'room READY'

    # Player launcher: StartGame -> RunGame.ps1 must also leave the game off this console.
    $source=Get-ChildItem -LiteralPath (Join-Path $project 'logs') -Directory -Filter 'room-exit-*' | ForEach-Object { Join-Path $_.FullName 'out\shooter-windows' } | Where-Object { Test-Path (Join-Path $_ 'Client.exe') } | Select-Object -First 1
    if($source) {
        $clientDir=Join-Path $Evidence 'client'
        Copy-Item -LiteralPath $source -Destination $clientDir -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'tools\shooter_client\RunGame.ps1') -Destination $clientDir -Force
        $before=@(Get-CimInstance Win32_Process -Filter "Name='Client.exe'" | ForEach-Object ProcessId)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $clientDir 'RunGame.ps1')
        $d=[DateTime]::UtcNow.AddSeconds(20)
        do { Start-Sleep -Milliseconds 300; $client=Get-CimInstance Win32_Process -Filter "Name='Client.exe'" | Where-Object { $_.ProcessId -notin $before -and $_.ExecutablePath -ieq (Join-Path $clientDir 'Client.exe') } | Select-Object -First 1 } while($null -eq $client -and [DateTime]::UtcNow -lt $d)
        Check ($null -ne $client) 'RunGame.ps1 starts this directory''s Client.exe'
        if($client) { Check (-not (OnConsole ([int]$client.ProcessId))) 'player client is not attached to the StartGame console' }
    } else { Out 'NOTE no exported client found under logs/room-exit-*; player launcher part not run' }

    CtrlC
    Check (-not $operator.HasExited) 'operator survives Ctrl+C on the launcher console'
    Check ((Api 'status').payload.host.state -eq 'RUNNING') 'host keeps running after Ctrl+C'
    Check (@((Api 'status').payload.rooms|Where-Object { $_.room_id -eq $room -and $_.state -eq 'READY' }).Count -eq 1) 'room keeps running after Ctrl+C'
    if($client) { Check ($null -ne (Get-Process -Id ([int]$client.ProcessId) -ErrorAction SilentlyContinue)) 'player client survives Ctrl+C' }
} finally {
    if($client) { $own=Get-Process -Id ([int]$client.ProcessId) -ErrorAction SilentlyContinue; if($own -and $own.Path -ieq (Join-Path $Evidence 'client\Client.exe')) { $own.Kill(); [void]$own.WaitForExit(5000) } }
    if(-not $operator.HasExited) {
        [IO.File]::WriteAllText((Join-Path $root 'operator-stop.request'),'stop')
        if(-not $operator.WaitForExit(90000)) { Check $false 'operator stops within 90 s' }
    }
    Check ($operator.HasExited -and $operator.ExitCode -eq 0) ('operator exit code '+$operator.ExitCode)
    Check (-not (Test-Path (Join-Path $root 'operator.json'))) 'operator.json removed by normal shutdown'
    $errors=@(Get-Content -Encoding UTF8 (Join-Path $Evidence 'operator-stderr.log') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ERROR|WARNING)' })
    Check ($errors.Count -eq 0) ('operator stderr has no ERROR/WARNING ('+$errors.Count+')')
    Out ('DETACHED_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$Evidence)
}
if($script:failed) { exit 1 }
exit 0
