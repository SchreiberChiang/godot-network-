[CmdletBinding()]
param()
# Failure-path checks run an isolated copy of the launcher. The only substitute
# executable is Windows where.exe; no Godot, account, host or room is started.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$evidence=Join-Path $project ('logs\client-launcher-'+[Guid]::NewGuid().ToString('N'))
$powershell=Join-Path $PSHOME 'powershell.exe'
$substitute=Join-Path $env:WINDIR 'System32\where.exe'
if(-not (Test-Path -LiteralPath $powershell -PathType Leaf) -or -not (Test-Path -LiteralPath $substitute -PathType Leaf)) { throw 'This test requires Windows PowerShell and Windows where.exe.' }
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0
$script:failed=0
$script:checks=New-Object Collections.ArrayList
$failure=''
New-Item -ItemType Directory -Path $evidence | Out-Null

function SaveText([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,$utf8) }
function Check([bool]$Condition,[string]$Name) {
    [void]$script:checks.Add(@{name=$Name;passed=$Condition})
    if(-not $Condition) { $script:failed++;throw ('FAIL '+$Name) }
    $script:passed++;Write-Host ('PASS '+$Name)
}
function QuoteArguments($Arguments) {
    foreach($argument in $Arguments) { '"'+([string]$argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
}
function RunFailureCase([string]$Name,[string]$Expected) {
    # Spaces exercise quoting without relying on the user's connection files.
    $fixture=Join-Path $evidence ($Name+' fixture')
    $toolsRoot=Join-Path $fixture 'tools'
    $artifacts=Join-Path $fixture 'artifacts'
    $gameRoot=Join-Path $fixture 'game project'
    $public=Join-Path $artifacts 'client'
    New-Item -ItemType Directory -Path $toolsRoot,$artifacts,$gameRoot,$public | Out-Null
    Copy-Item -LiteralPath (Join-Path $project 'tools\run_framework.ps1') -Destination (Join-Path $toolsRoot 'run_framework.ps1')
    SaveText (Join-Path $gameRoot 'project.godot') "config_version=5`n"
    if($Name -ne 'missing-client') { SaveText (Join-Path $gameRoot 'client.gd') "extends SceneTree`n" }
    if($Name -ne 'missing-connection') { SaveText (Join-Path $public 'connection.json') '{}' }
    SaveText (Join-Path $artifacts 'framework-games.json') (@{shooter=@{project=$gameRoot}} | ConvertTo-Json -Depth 4)
    $executable=$substitute
    if($Name -eq 'missing-engine') { $executable=Join-Path $fixture 'missing-engine.exe' }
    $stdout=Join-Path $fixture 'launcher-stdout.log'
    $stderr=Join-Path $fixture 'launcher-stderr.log'
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $toolsRoot 'run_framework.ps1'),'-Mode','client','-Game','shooter','-Godot',$executable)
    $process=Start-Process -FilePath $powershell -ArgumentList (QuoteArguments $arguments) -WorkingDirectory $fixture -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $ownedHandle=$process.Handle
    try {
        if(-not $process.WaitForExit(30000)) {
            # Only this test's own PowerShell process, retained by its handle.
            if(-not $process.HasExited) { $process.Kill();[void]$process.WaitForExit(5000) }
            throw ('Launcher failure test timed out: '+$Name)
        }
        $exitCode=$process.ExitCode
    } finally { $process.Dispose() }
    $output=[IO.File]::ReadAllText($stdout)+[IO.File]::ReadAllText($stderr)
    Check ($exitCode -ne 0) ($Name+' returns failure')
    Check (-not $output.Contains('FRAMEWORK_CLIENT_STARTED')) ($Name+' never reports a ready client')
    Check ($output.Contains($Expected)) ($Name+' explains the startup failure')
    if($Name -eq 'early-exit') {
        $clientLogs=@(Get-ChildItem -LiteralPath (Join-Path $fixture 'logs\client-starts') -Directory)
        Check ($clientLogs.Count -eq 1) 'early-exit keeps one isolated diagnostic directory'
        $engineError=Join-Path $clientLogs[0].FullName 'stderr.log'
        Check ((Test-Path -LiteralPath $engineError -PathType Leaf) -and (Get-Item -LiteralPath $engineError).Length -gt 0) 'early-exit retains the failed executable diagnostic'
    }
}

try {
    RunFailureCase 'missing-engine' 'Godot executable not found'
    RunFailureCase 'missing-client' 'Client project is missing'
    RunFailureCase 'missing-connection' 'Start the operator first'
    # where.exe rejects Godot arguments immediately. This tests early-exit
    # reporting only, not engine behavior, a visible window or multiplayer.
    RunFailureCase 'early-exit' 'Client exited before its window was ready'
} catch {
    $failure=$_.Exception.Message
    if($script:failed -eq 0) { $script:failed++ }
    Write-Host ('CLIENT_LAUNCHER_ERROR '+$failure)
}
$report=@{passed=$script:passed;failed=$script:failed;checks=@($script:checks);error=$failure;evidence=$evidence;scope='Windows launcher failure paths with where.exe; no Godot or multiplayer verification'}
SaveText (Join-Path $evidence 'result.json') ($report | ConvertTo-Json -Depth 8)
Write-Output ('CLIENT_LAUNCHER_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
if($script:failed -gt 0) { exit 1 }
exit 0
