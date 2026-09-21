param(
    [ValidateSet('panel','stop','client')][string]$Mode='panel',
    [ValidateSet('shooter','turns')][string]$Game='shooter',
    [string]$ConnectionConfig='',
    [switch]$NoBrowser,
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dataRoot=Join-Path $project 'data\framework'
$metadata=Join-Path $dataRoot 'operator.json'
function Quote-Arguments($arguments) { foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
if($Mode -eq 'stop') {
    if(-not (Test-Path -LiteralPath $metadata)) { Write-Output 'No running operator descriptor.'; exit 0 }
    [IO.File]::WriteAllText((Join-Path $dataRoot 'operator-stop.request'),'stop')
    $deadline=[DateTime]::UtcNow.AddSeconds(70)
    while((Test-Path -LiteralPath $metadata) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
    if(Test-Path -LiteralPath $metadata) { throw 'Operator has not confirmed shutdown. Inspect data/framework/logs; no unverified process was killed.' }
    Write-Output 'FRAMEWORK_STOPPED'; exit 0
}
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw ('Godot executable not found: '+$Godot) }
if($Mode -eq 'client') {
    $indexPath=Join-Path $project 'artifacts\framework-games.json'
    if(-not (Test-Path -LiteralPath $indexPath)) { & (Join-Path $PSScriptRoot 'build_framework.ps1') }
    $index=Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $gameRoot=$index.$Game.project
    if(-not $ConnectionConfig) { $ConnectionConfig=Join-Path $project 'artifacts\client\connection.json' }
    if(-not (Test-Path -LiteralPath $ConnectionConfig)) { throw 'Start the operator first to generate the public connection configuration.' }
    $arguments=@('--path',$gameRoot,'--script','res://client.gd','--',('--game='+$Game),('--connection-config='+[IO.Path]::GetFullPath($ConnectionConfig)))
    $process=Start-Process -FilePath $Godot -ArgumentList (Quote-Arguments $arguments) -PassThru -WindowStyle Hidden
    Write-Output ('FRAMEWORK_CLIENT_STARTED game='+$Game+' pid='+$process.Id)
    exit 0
}
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
& (Join-Path $PSScriptRoot 'build_framework.ps1')
& (Join-Path $PSScriptRoot 'protect_data.ps1') -ProjectRoot $project -DataRoot $dataRoot | Out-Null
$logs=Join-Path $dataRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$arguments=@('--headless','--path',$project,'--log-file',(Join-Path $logs 'operator.log'),'--script','res://host/operator.gd','--',('--data-root='+$dataRoot))
$process=Start-Process -FilePath $Godot -ArgumentList (Quote-Arguments $arguments) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'console.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
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
