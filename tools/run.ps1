param(
    [ValidateSet('unit','launcher','integration','demo','players','games','persistence','secure','stress','load','recovery','limits','template','all')][string]$Mode = 'demo',
    [switch]$Visual,
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot executable missing: $Godot" }
$logs = Join-Path $project 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$modes = if ($Mode -eq 'all') { @('unit','launcher','integration','demo','players','games','persistence','secure','stress','load','recovery','limits','template') } else { @($Mode) }
foreach ($entry in $modes) {
    if ($entry -in @('games','load','recovery')) { & (Join-Path $PSScriptRoot 'build_games.ps1') }
    if ($entry -eq 'template') { & (Join-Path $PSScriptRoot 'new_game.ps1') -GameId 'template_probe' }
    $arguments = @('--headless','--path',$project,'--log-file',(Join-Path $logs "$entry-godot.log"))
    if ($entry -eq 'launcher') { $arguments += @('--script','res://tests/test_launcher_real.gd') }
    elseif ($entry -ne 'demo') { $arguments += @('--script',"res://tests/run_$entry.gd") }
    if ($entry -eq 'games' -and $Visual) { $arguments += @('--','--visual=true') }
    # This Godot binary uses Windows GUI subsystem: explicitly wait for its exit.
    $quoted = foreach ($argument in $arguments) { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    $stdout = Join-Path $logs "$entry-console.log"
    $stderr = Join-Path $logs "$entry-stderr.log"
    $process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Retain this exact process handle; watchdog never kills by an enumerated PID.
    $ownedHandle = $process.Handle
    $limit = if ($entry -eq 'stress') { 900000 } else { 240000 }
    if (-not $process.WaitForExit($limit)) {
        $process.Kill()
        $process.WaitForExit()
        throw "RoomKit $entry timed out; original host handle stopped; child watchdogs will exit. Inspect logs."
    }
    $code = $process.ExitCode
    Get-Content -Encoding UTF8 -LiteralPath $stdout
    Get-Content -Encoding UTF8 -LiteralPath $stderr
    Write-Output "ROOMKIT_EXIT mode=$entry code=$code"
    if ($code -ne 0) { exit $code }
    if (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw "Godot script error in $entry" }
    $marker = switch ($entry) { 'unit' { 'UNIT_RESULT passed=\d+ failed=0' }; 'launcher' { 'REAL_LAUNCHER_RESULT passed=\d+ failed=0' }; 'integration' { 'INTEGRATION_RESULT passed=\d+ failed=0' }; 'players' { 'PLAYERS_RESULT passed=\d+ failed=0' }; 'games' { 'GAMES_RESULT passed=\d+ failed=0' }; 'persistence' { 'PERSISTENCE_RESULT passed=\d+ failed=0' }; 'secure' { 'SECURE_RESULT passed=\d+ failed=0' }; 'stress' { 'STRESS_RESULT passed=\d+ failed=0 cycles=100' }; 'load' { 'LOAD_RESULT passed=\d+ failed=0' }; 'recovery' { 'RECOVERY_RESULT passed=\d+ failed=0' }; 'limits' { 'LIMITS_RESULT passed=\d+ failed=0' }; 'template' { 'TEMPLATE_RESULT passed=\d+ failed=0' }; 'demo' { 'DEMO_PASS' } }
    if (-not (Select-String -LiteralPath (Join-Path $logs "$entry-console.log") -Pattern $marker -Quiet)) { throw "Missing success marker for $entry" }
}
exit 0
