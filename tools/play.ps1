param(
    [ValidateSet('blocks','turns')][string]$Game = 'blocks',
    [switch]$Smoke,
    [switch]$Panel,
    [switch]$NoBrowser,
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Missing Godot: $Godot" }
& (Join-Path $PSScriptRoot 'build_games.ps1')
$logs = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$arguments = @('--headless','--path',$projectRoot,'--log-file',(Join-Path $logs 'play-host.log'),'--script','res://examples/showcase/host.gd','--',('--game=' + $Game))
if ($Smoke) { $arguments += '--smoke=true' }
if ($Panel) { $arguments += @('--panel=true','--managed=true') }
$quoted = foreach ($argument in $arguments) { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'play-console.log') -RedirectStandardError (Join-Path $logs 'play-stderr.log')
$ownedHandle = $process.Handle
if ($Panel) { & (Join-Path $PSScriptRoot 'open_panel.ps1') -ExpectedPid $process.Id -NoBrowser:$NoBrowser }
Write-Output 'Opening two game windows. Close both windows to finish. Local session limit: 30 minutes.'
if (-not $process.WaitForExit(1900000)) {
    $process.Kill()
    $process.WaitForExit()
    throw 'Demo host timed out; room watchdogs will stop the owned rooms. Inspect logs.'
}
Get-Content -Encoding UTF8 -LiteralPath (Join-Path $logs 'play-console.log')
Get-Content -Encoding UTF8 -LiteralPath (Join-Path $logs 'play-stderr.log')
$code = $process.ExitCode
Write-Output "ROOMKIT_PLAY_EXIT game=$Game code=$code"
if ($code -ne 0) { exit $code }
if (Select-String -LiteralPath (Join-Path $logs 'play-stderr.log') -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Game demo script error' }
if (-not (Select-String -LiteralPath (Join-Path $logs 'play-console.log') -Pattern 'GAMES_RESULT passed=\d+ failed=0' -Quiet)) { throw 'Missing game demo success marker' }
exit 0
