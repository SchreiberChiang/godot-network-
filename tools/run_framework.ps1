param(
    [ValidateSet('panel','stop','status','client')][string]$Mode='panel',
    [ValidateSet('shooter','turns')][string]$Game='shooter',
    [string]$ConnectionConfig='',
    [switch]$NoBrowser,
    [ValidatePattern('^[a-z0-9-]{1,32}$')][string]$Instance='framework',
    [ValidateRange(1024,65535)][int]$PanelPort=28291,
    [ValidateRange(1024,65535)][int]$LobbyPort=28300,
    [ValidateRange(1024,65535)][int]$ControlPort=28301,
    [ValidatePattern('^[1-9][0-9]{3,4}-[1-9][0-9]{3,4}$')][string]$UdpRange='28400-28431',
    [string]$Bind='0.0.0.0',
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dataRoot=Join-Path $project 'data\framework'
$instanceRoot=Join-Path $project ('data/instance-'+$Instance)
$indexPath=Join-Path $project 'artifacts/framework-games.json'
$publicRoot=Join-Path $project 'artifacts/client'
$buildRoot=Join-Path $project 'artifacts'
if($Instance -ne 'framework') {
    $dataRoot=Join-Path $instanceRoot 'data'
    $indexPath=Join-Path $instanceRoot 'games.json'
    $publicRoot=Join-Path $instanceRoot 'public'
    $buildRoot=Join-Path $instanceRoot 'build'
}
. (Join-Path $PSScriptRoot 'roomkit_entry.ps1')
$metadata=Join-Path $dataRoot 'operator.json'
if($Mode -ne 'client'){Assert-RoomKitPath $metadata}
if($Mode -eq 'status'){& (Join-Path $PSScriptRoot 'roomkit_status.ps1') -DataRoot $dataRoot;exit $LASTEXITCODE}
function Quote-Arguments($arguments) { foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
. (Join-Path $PSScriptRoot 'detached_process.ps1')
if($Mode -eq 'stop') {
    Assert-RoomKitPath (Join-Path $dataRoot 'operator-stop.request')
    if(-not (Test-Path -LiteralPath $metadata)) { Write-Output 'No running operator descriptor.'; exit 0 }
    [IO.File]::WriteAllText((Join-Path $dataRoot 'operator-stop.request'),'stop')
    $deadline=[DateTime]::UtcNow.AddSeconds(70)
    while((Test-Path -LiteralPath $metadata) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
    if(Test-Path -LiteralPath $metadata) { throw 'Operator has not confirmed shutdown. Inspect data/framework/logs; no unverified process was killed.' }
    Write-Output 'FRAMEWORK_STOPPED'; exit 0
}
Assert-RoomKitPath $buildRoot
Assert-RoomKitPath $indexPath
Assert-RoomKitPath (Join-Path $project 'logs/detached-start')
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw ('Godot executable not found: '+$Godot) }
if($Mode -eq 'client') {
    if(-not (Test-Path -LiteralPath $indexPath)) { & (Join-Path $PSScriptRoot 'build_framework.ps1') -IndexPath $indexPath -BuildRoot $buildRoot }
    $index=Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $gameRoot=$index.$Game.project
    if(-not $gameRoot -or -not (Test-Path -LiteralPath (Join-Path $gameRoot 'project.godot') -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $gameRoot 'client.gd') -PathType Leaf)) { throw 'Client project is missing. Start StartManagement.cmd to rebuild it.' }
    if(-not $ConnectionConfig) { $ConnectionConfig=Join-Path $publicRoot 'connection.json' }
    Assert-RoomKitTree $gameRoot
    Assert-RoomKitPath $ConnectionConfig
    if(-not (Test-Path -LiteralPath $ConnectionConfig)) { throw 'Start the operator first to generate the public connection configuration.' }
    $clientLogs=Join-Path $project ('logs\client-starts\'+$Game+'-'+[Guid]::NewGuid().ToString('N'))
    Assert-RoomKitPath $clientLogs
    New-Item -ItemType Directory -Path $clientLogs -Force | Out-Null
    $stderr=Join-Path $clientLogs 'stderr.log'
    $arguments=@('--path',$gameRoot,'--log-file',(Join-Path $clientLogs 'engine.log'),'--script','res://client.gd','--',('--game='+$Game),('--connection-config='+[IO.Path]::GetFullPath($ConnectionConfig)))
    # This is the player's interactive window. Hidden is only for background services.
    try { $process=Start-Detached $Godot $arguments $project (Join-Path $clientLogs 'console.log') $stderr 'Normal' }
    catch { if($_.Exception.Message -like 'DETACHED_PROCESS_EXITED*') { throw ('Client exited before its window was ready. See '+$clientLogs) }; throw }
    $ownedHandle=$process.Handle
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    $visibleSince=$null
    while(-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if($process.HasExited) { break }
        if(Test-Path -LiteralPath $stderr) {
            if(Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' -Quiet) { break }
        }
        if($process.MainWindowHandle -ne [IntPtr]::Zero) {
            if($null -eq $visibleSince) { $visibleSince=[DateTime]::UtcNow }
            if(([DateTime]::UtcNow-$visibleSince).TotalSeconds -ge 1) {
                if($process.HasExited) { break }
                Write-Output ('FRAMEWORK_CLIENT_STARTED game='+$Game+' pid='+$process.Id+' window_ready=true logs='+$clientLogs)
                $process.Dispose()
                exit 0
            }
        } else { $visibleSince=$null }
        Start-Sleep -Milliseconds 100
    }
    if($process.HasExited) {
        $clientExit=$process.ExitCode
        $process.Dispose()
        throw ('Client exited before its window was ready (exit '+$clientExit+'). See '+$clientLogs)
    }
    # Only the exact client created above can be stopped by this startup watchdog.
    try {
        $process.Kill()
        if(-not $process.WaitForExit(5000)) { throw ('Client startup failed and its exit was not confirmed. See '+$clientLogs) }
    } catch {
        if(-not $process.HasExited) { throw }
    } finally { $process.Dispose() }
    throw ('Client did not show a usable window. See '+$clientLogs)
}
Assert-RoomKitTree $dataRoot
Assert-RoomKitTree $publicRoot
Assert-RoomKitTree (Join-Path $project 'run')
Assert-RoomKitPath (Join-Path $project 'data/.gdignore')
if(Test-Path -LiteralPath $metadata) {
    $descriptor=Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
    $url='http://127.0.0.1:'+$descriptor.port+'/'
    $reachable=$false
    try { $page=Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 3; $reachable=$page.StatusCode -eq 200 } catch { }
    if($reachable) {
        if(-not $NoBrowser) { Start-Process $url }
        Write-Output ('FRAMEWORK_PANEL '+$url)
        exit 0
    }
    if($descriptor.pid -isnot [int] -and $descriptor.pid -isnot [long]) { throw 'Invalid operator descriptor PID.' }
    $absent=$false
    try { $oldProcess=[Diagnostics.Process]::GetProcessById([int]$descriptor.pid); $oldProcess.Dispose() }
    catch [ArgumentException] { $absent=$true }
    if(-not $absent) { throw 'Existing operator descriptor is unreachable and its PID still exists. Inspect logs before starting another operator.' }
    Remove-Item -LiteralPath $metadata
    $staleStop=Join-Path $dataRoot 'operator-stop.request'
    if(Test-Path -LiteralPath $staleStop){Remove-Item -LiteralPath $staleStop}
}
& (Join-Path $PSScriptRoot 'build_framework.ps1') -IndexPath $indexPath -BuildRoot $buildRoot
& (Join-Path $PSScriptRoot 'protect_data.ps1') -ProjectRoot $project -DataRoot $dataRoot | Out-Null
$logs=Join-Path $dataRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $logs 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$dataRoot),('--games='+$indexPath),('--public-client-dir='+$publicRoot),('--panel-port='+$PanelPort),('--operator-log-path='+(Join-Path $logs 'operator.log')))
if($PSBoundParameters.ContainsKey('Bind')){$arguments+=('--initial-bind='+$Bind)}
if($PSBoundParameters.ContainsKey('LobbyPort') -or $PSBoundParameters.ContainsKey('ControlPort') -or $PSBoundParameters.ContainsKey('UdpRange')){$arguments+=('--initial-ports='+$LobbyPort+','+$ControlPort+','+$UdpRange.Replace('-',','))}
$process=Start-Detached $Godot $arguments $project (Join-Path $logs 'console.log') (Join-Path $logs 'stderr.log')
$ownedHandle=$process.Handle
$deadline=[DateTime]::UtcNow.AddSeconds(45)
while(-not (Test-Path -LiteralPath $metadata) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
if(-not (Test-Path -LiteralPath $metadata)) { throw 'Operator did not become ready. Inspect data/framework/logs. The launcher did not kill any process.' }
$descriptor=Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
if($descriptor.pid -ne $process.Id) { throw 'Operator identity mismatch.' }
$url='http://127.0.0.1:'+$descriptor.port+'/'
if(-not $NoBrowser) { Start-Process $url }
Write-Output ('FRAMEWORK_PANEL '+$url)
exit 0
