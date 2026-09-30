param(
    [ValidateSet('start','player','stop')][string]$Action='start',
    [string]$Invite='',
    [string]$Username='',
    # Optional: reproduce a LAN/public style configuration (listen on all
    # interfaces, advertise another address). Ports stay private to the fixture.
    [ValidateSet('127.0.0.1','0.0.0.0')][string]$Bind='127.0.0.1',
    [string]$AdvertisedHost='127.0.0.1',
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
# Isolated source operator for browser acceptance of host/admin.html. Own data
# root, ports, game index and public-client directory; the user's data/framework,
# artifacts/client and artifacts/framework-games.json are never touched. It does
# not create an administrator: the browser performs first-time setup.
#   start  - launch the operator and print its URL (context in run/admin-ui-fixture.json)
#   player - register one test player through an exported client (-Invite from the panel)
#   stop   - normal operator shutdown through operator-stop.request
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$contextPath=Join-Path $project 'run\admin-ui-fixture.json'
$utf8=New-Object Text.UTF8Encoding($false)
function Quote($values) { foreach($value in $values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'} }
function FreePort { $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); return $p }

if($Action -eq 'start') {
    if(Test-Path -LiteralPath $contextPath) { throw 'A fixture context already exists; run -Action stop first.' }
    $runId=[Guid]::NewGuid().ToString('N')
    $evidence=Join-Path $project ('logs\admin-ui-'+$runId)
    $root=Join-Path $project ('data\test-admin-ui-'+$runId)
    New-Item -ItemType Directory -Force -Path $evidence,(Join-Path $project 'run') | Out-Null
    & (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $root | Out-Null
    $gamesIndex=Join-Path $evidence 'framework-games.json'
    & (Join-Path $project 'tools\build_framework.ps1') -IndexPath $gamesIndex | Out-Null
    $panel=FreePort
    [IO.File]::WriteAllText((Join-Path $root 'config.json'),(@{lobby_bind=$Bind;advertised_host=$AdvertisedHost;lobby_port=(FreePort);game_bind=$Bind;control_port=(FreePort);udp_first=28720;udp_last=28735;max_rooms=8;asset_spaces=@{shooter='shooter';turns='turns'}}|ConvertTo-Json -Compress),$utf8)
    . (Join-Path $project 'tools\detached_process.ps1')
    $publicDir=Join-Path $evidence 'public-client'
    $arguments=@('--headless','--path',$project,'--log-file',(Join-Path $evidence 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$root),('--panel-port='+$panel),('--games='+$gamesIndex),('--public-client-dir='+$publicDir))
    $operator=Start-Detached $Godot $arguments $project (Join-Path $evidence 'operator-console.log') (Join-Path $evidence 'operator-stderr.log')
    $url='http://127.0.0.1:'+$panel
    $deadline=[DateTime]::UtcNow.AddSeconds(45); $ready=$false
    while(-not $ready -and [DateTime]::UtcNow -lt $deadline -and -not $operator.HasExited) { try { $ready=(Invoke-RestMethod -Uri ($url+'/api') -Method Post -ContentType 'application/json' -Body '{"action":"setup.status","payload":{}}' -TimeoutSec 3).ok } catch { Start-Sleep -Milliseconds 300 } }
    if(-not $ready) { throw 'Isolated operator did not become ready; see '+$evidence }
    [IO.File]::WriteAllText($contextPath,(@{url=$url;root=$root;evidence=$evidence;pid=$operator.Id;games_index=$gamesIndex;public_dir=$publicDir}|ConvertTo-Json),$utf8)
    Write-Output ('ADMIN_UI_FIXTURE_READY '+$url+' evidence='+$evidence)
    exit 0
}
if(-not (Test-Path -LiteralPath $contextPath)) { throw 'No fixture is running.' }
$ctx=Get-Content -Encoding UTF8 -Raw -LiteralPath $contextPath | ConvertFrom-Json
if($Action -eq 'player') {
    if($Invite -eq '') { throw 'Pass -Invite with a code generated in the panel.' }
    if($Username -eq '') { $Username='ui_'+[Guid]::NewGuid().ToString('N').Substring(0,6) }
    $client=Join-Path $ctx.evidence 'out\shooter-windows'
    if(-not (Test-Path -LiteralPath (Join-Path $client 'Client.exe'))) {
        if(-not (Test-Path -LiteralPath (Join-Path $ctx.public_dir 'connection.json'))) { throw 'Start the game server in the panel first; it publishes the public connection file.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\prepare_player_client.ps1') -Godot $Godot -IndexPath $ctx.games_index -ConnectionDirectory $ctx.public_dir -OutputRoot (Join-Path $ctx.evidence 'out') | Out-Null
        if($LASTEXITCODE -ne 0) { throw 'Client preparation failed.' }
    }
    $plan=Join-Path $ctx.root ('player-'+$Username+'.json'); $report=Join-Path $ctx.evidence ('player-'+$Username+'.json')
    [IO.File]::WriteAllText($plan,(@{username=$Username;password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('界面测试_'+$Username.Substring(3));invite_code=$Invite;register=$true;room_id='r_fixture_no_such_room';timeout_ms=8000;report_path=$report}|ConvertTo-Json),$utf8)
    try {
        $p=Start-Process -FilePath (Join-Path $client 'Client.exe') -ArgumentList (Quote @('--headless','--',('--autoplay='+$plan))) -WorkingDirectory $client -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $ctx.evidence ('player-'+$Username+'-console.log')) -RedirectStandardError (Join-Path $ctx.evidence ('player-'+$Username+'-stderr.log'))
        $h=$p.Handle
        if(-not $p.WaitForExit(90000)) { $p.Kill(); $p.WaitForExit(); throw 'Client timed out.' }
    } finally { Remove-Item -LiteralPath $plan -Force -ErrorAction SilentlyContinue }
    # The client's test driver registers, logs in, then waits for a room that does
    # not exist and gives up; reaching that stage proves the account was created.
    # (No client change: client code is part of the content-bound build_id.)
    $r=Get-Content -Encoding UTF8 -Raw -LiteralPath $report | ConvertFrom-Json
    if($r.stage -notin @('join_failed','in_room','in_room_synced')) { throw ('Registration failed: stage='+$r.stage+' '+$r.register_message+' / '+$r.login_message) }
    Write-Output ('ADMIN_UI_PLAYER_READY username='+$Username)
    exit 0
}
if($Action -eq 'stop') {
    [IO.File]::WriteAllText((Join-Path $ctx.root 'operator-stop.request'),'stop')
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    while((Test-Path -LiteralPath (Join-Path $ctx.root 'operator.json')) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
    if(Test-Path -LiteralPath (Join-Path $ctx.root 'operator.json')) { throw 'Operator has not confirmed shutdown; nothing was killed. Inspect '+$ctx.evidence }
    Remove-Item -LiteralPath $contextPath -Force
    $errors=@(Get-Content -Encoding UTF8 (Join-Path $ctx.evidence 'operator-stderr.log') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(ERROR|WARNING)' })
    Write-Output ('ADMIN_UI_FIXTURE_STOPPED stderr_errors='+$errors.Count+' evidence='+$ctx.evidence)
    exit 0
}
