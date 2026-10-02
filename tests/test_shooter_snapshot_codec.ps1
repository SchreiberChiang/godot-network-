param([string]$Godot='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'support/portable.ps1')
$Godot=Rk-Godot $Godot
$taskProject=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskEvidence=Join-Path $taskProject ('artifacts/codec-test/pure-'+[Guid]::NewGuid().ToString('N'))
$taskIsolated=Join-Path $taskEvidence 'project'
foreach($taskFolder in @('project/examples/shooter','project/sdk/roomkit/shared','project/schemas','project/tests','private')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $taskEvidence $taskFolder) | Out-Null
}
foreach($taskPath in @('examples/shooter/snapshot_codec.gd','sdk/roomkit/shared/schema_validator.gd','schemas/shooter_state.schema.json','schemas/shooter_result.schema.json','schemas/shooter_snapshot_header.schema.json','tests/test_shooter_snapshot_codec.gd','tests/run_shooter_snapshot_codec.gd')) {
    Copy-Item -LiteralPath (Join-Path $taskProject $taskPath) -Destination (Join-Path $taskIsolated $taskPath)
}
$taskSettings=@'
config_version=5
[application]
config/name="RoomKit snapshot codec pure test"
[rendering]
renderer/rendering_method="gl_compatibility"
[debug]
file_logging/enable_file_logging=false
'@
[IO.File]::WriteAllText((Join-Path $taskIsolated 'project.godot'),$taskSettings,(New-Object Text.UTF8Encoding($false)))
$taskEnvNames=@('APPDATA','LOCALAPPDATA','TEMP','TMP','HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME','XDG_STATE_HOME','XDG_RUNTIME_DIR','TMPDIR')
$taskSaved=@{}
foreach($taskName in $taskEnvNames) { $taskSaved[$taskName]=[Environment]::GetEnvironmentVariable($taskName,'Process') }
try {
    foreach($taskName in $taskEnvNames) { [Environment]::SetEnvironmentVariable($taskName,(Join-Path $taskEvidence 'private'),'Process') }
    $taskProcess=Rk-StartHidden $Godot @('--headless','--path',$taskIsolated,'--script','res://tests/run_shooter_snapshot_codec.gd') (Join-Path $taskEvidence 'stdout.log') (Join-Path $taskEvidence 'stderr.log')
    $taskProcess.WaitForExit()
    $taskExit=$taskProcess.ExitCode
    [IO.File]::WriteAllText((Join-Path $taskEvidence 'exit.txt'),[string]$taskExit)
} finally {
    foreach($taskName in $taskSaved.Keys) { [Environment]::SetEnvironmentVariable($taskName,$taskSaved[$taskName],'Process') }
}
Get-Content -LiteralPath (Join-Path $taskEvidence 'stdout.log') -Encoding UTF8
# Expected malicious-Zstd native errors are retained, never erased or hidden.
Get-Content -LiteralPath (Join-Path $taskEvidence 'stderr.log') -Encoding UTF8
$taskStdout=Get-Content -LiteralPath (Join-Path $taskEvidence 'stdout.log') -Encoding UTF8 -Raw
if ((Get-Item -LiteralPath (Join-Path $taskEvidence 'stderr.log')).Length -gt 0 -or $taskStdout -notmatch 'SHOOTER_SNAPSHOT_CODEC_RESULT passed=\d+ failed=0 ' -or $taskStdout -match 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:') {
    # On this Godot version, malformed compressed packets return empty without
    # stderr. A platform that emits native errors needs explicit evidence review;
    # the test driver cannot convert those errors into a silent success.
    $taskExit=1
    Write-Output 'FAIL pure codec runner had error output or no successful result'
}
[IO.File]::WriteAllText((Join-Path $taskEvidence 'driver-exit.txt'),[string]$taskExit)
Write-Output ('SHOOTER_SNAPSHOT_CODEC_DRIVER exit='+$taskExit+' evidence='+$taskEvidence)
exit $taskExit
