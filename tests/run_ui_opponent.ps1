[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ContextFile)
# Source SDK opponent for a human-operated, genuinely exported Client.exe.
# This helper never runs an admin request or generates gameplay commands.
# Before starting, place {game_id,room_id,invite_code} in opponent-request.json
# beside the UI fixture's private context. Write normal driver commands only to
# the control_directory printed after READY. Either fixture close.request or
# opponent-close.request requests an orderly close. Maximum lifetime: 15 minutes.
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$utf8 = New-Object Text.UTF8Encoding($false)
$child = $null
$heldHandle = [IntPtr]::Zero
$bootstrapPath = ''
$controlDirectory = ''
$evidence = ''
$ready = $false
$forced = $false
$failure = ''

function ProjectPath([string]$Value, [string]$Label) {
    if (-not [IO.Path]::IsPathRooted($Value)) { throw ($Label + ' must be an absolute project path.') }
    $resolved = [IO.Path]::GetFullPath($Value).TrimEnd('\','/')
    if (-not $resolved.StartsWith($project + '\', [StringComparison]::OrdinalIgnoreCase)) { throw ($Label + ' is outside this repository.') }
    $cursor = $resolved
    while ($cursor.Length -ge $project.Length) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ($Label + ' contains a reparse point.') }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $resolved
}

function ReadJson([string]$Path, [int]$Limit = 65536) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -gt $Limit) { throw 'Required fixture JSON is missing or too large.' }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'Fixture JSON is invalid; contents suppressed.' }
}

function SaveJson([string]$Path, $Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40 -Compress), $utf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Report {
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        try { return ReadJson $reportPath 1048576 } catch { return $null }
    }
    return $null
}

function CloseRequested {
    return (Test-Path -LiteralPath $fixtureClose) -or (Test-Path -LiteralPath $opponentClose)
}

function WaitChild([int]$Milliseconds) {
    $end = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    do { if ($child.WaitForExit(100)) { return $true } } while ([DateTime]::UtcNow -lt $end)
    return $false
}

function TerminateExactChild {
    if ($child.HasExited) { return }
    if ($heldHandle -eq [IntPtr]::Zero) { throw 'No captured child process handle; termination refused.' }
    if ($null -eq ('RoomKitUiOpponentProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoomKitUiOpponentProcess {
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TerminateProcess(IntPtr handle, uint exitCode);
}
'@
    }
    # This retained Windows HANDLE identifies only the process started below.
    # Never look up, reopen or terminate a process by a journal or numeric PID.
    if (-not [RoomKitUiOpponentProcess]::TerminateProcess($heldHandle, 72) -or -not (WaitChild 3000)) { throw 'Exact source-opponent cleanup failed.' }
}

try {
    $contextPath = ProjectPath $ContextFile 'Context'
    $ctx = ReadJson $contextPath
    $private = ProjectPath ([IO.Path]::GetDirectoryName($contextPath)) 'Private directory'
    $bundle = ProjectPath ([string]$ctx.bundle) 'Bundle'
    if ((ProjectPath ([string]$ctx.privateRoot) 'Context private root') -ine $private -or
        -not $private.StartsWith((Join-Path $bundle 'data') + '\ui-test-', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($private) -notmatch '^ui-test-[a-f0-9]{32}$') { throw 'Context does not belong to an isolated UI fixture in this bundle.' }
    $fixtureClose = ProjectPath ([string]$ctx.closeRequest) 'Fixture close request'
    if ($fixtureClose -ine (Join-Path $private 'close.request')) { throw 'Unexpected UI fixture close-request path.' }
    $opponentClose = ProjectPath (Join-Path $private 'opponent-close.request') 'Opponent close request'
    if (CloseRequested) { throw 'This UI fixture already has a close request.' }
    $requestPath = ProjectPath (Join-Path $private 'opponent-request.json') 'Opponent request'
    $request = ReadJson $requestPath 4096
    $names = @($request.PSObject.Properties.Name)
    if ($names.Count -ne 3 -or @($names | Where-Object { $_ -notin @('game_id','room_id','invite_code') }).Count -ne 0) { throw 'Opponent request must contain only game_id, room_id and invite_code.' }
    $game = [string]$request.game_id
    if ($game -notin @('shooter','turns') -or [string]$request.room_id -cnotmatch '^r_[a-f0-9]{32}$' -or [string]$request.invite_code -cnotmatch '^[a-f0-9]{32}$') { throw 'Opponent request game, room ID or invitation is invalid.' }
    $connectionPath = ProjectPath ([string]$ctx.publicConnectionPath) 'Public connection'
    if ($connectionPath -ine (Join-Path $private 'connection-public.json')) { throw 'Unexpected UI fixture public-connection path.' }
    $connection = ReadJson $connectionPath 8192
    $endpoint = $null
    if (-not [Uri]::TryCreate([string]$connection.url, [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -ne 'wss' -or $endpoint.Host -notin @('127.0.0.1','localhost') -or $endpoint.Port -lt 1 -or
        $endpoint.UserInfo -ne '' -or $endpoint.AbsolutePath -ne '/' -or $endpoint.Query -ne '' -or $endpoint.Fragment -ne '') { throw 'UI fixture must use its loopback WSS endpoint.' }
    $certificate = ProjectPath ([string]$connection.ca_certificate) 'Public certificate'
    if ($certificate -ine (Join-Path $private 'server.crt') -or -not (Test-Path -LiteralPath $certificate -PathType Leaf) -or [string]$connection.server_hostname -ne 'localhost') { throw 'Unexpected fixture TLS certificate or hostname.' }
    $manifestPath = ProjectPath (Join-Path $bundle 'artifacts\framework-games.json') 'Bundle manifest'
    $games = ReadJson $manifestPath
    $manifest = $games.$game.manifest
    if ($null -eq $manifest -or [string]$manifest.game_id -ne $game -or [string]$manifest.sdk_version -ne '0.5.0') { throw 'Expected SDK 0.5 game manifest is missing from the bundle.' }
    $playerName = $game + '_two'
    $player = $ctx.players.$playerName
    if ($null -eq $player -or [string]$player.username -notmatch '^ui_(shooter|turns)_two_[a-f0-9]{8}$' -or
        [string]$player.password -notmatch '^Player![a-f0-9]{32}$' -or [string]$player.display_name -eq '') { throw 'The UI fixture second-player account is missing or invalid.' }
    $engine = ReadJson (Join-Path $project 'config\development.json')
    $godot = [string]$engine.godot_executable
    if (-not [IO.Path]::IsPathRooted($godot) -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { throw 'Configured local Godot executable is unavailable.' }
    $runId = [Guid]::NewGuid().ToString('N')
    $controlDirectory = ProjectPath (Join-Path $private ('source-opponent-' + $game + '-' + $runId)) 'Opponent control directory'
    New-Item -ItemType Directory -Path $controlDirectory | Out-Null
    # All generated secrets inherit the already-protected UI fixture data ACL.
    $bootstrapPath = Join-Path $controlDirectory 'bootstrap.json'
    $reportPath = Join-Path $controlDirectory 'report.json'
    $evidence = $controlDirectory
    $public = @{url=[string]$connection.url;ca_certificate=$certificate;server_hostname='localhost';game_id=$game}
    SaveJson $bootstrapPath @{connection=$public;manifest=$manifest;game_id=$game;username=[string]$player.username;password=[string]$player.password;display_name=[string]$player.display_name;invite_code=[string]$request.invite_code;register=$true;room_id=[string]$request.room_id;report_path=$reportPath;control_directory=$controlDirectory;timeout_ms=900000}
    $arguments = @('--headless','--path',$project,'--log-file',(Join-Path $evidence 'godot.log'),'--script','res://tests/run_framework_clients.gd','--',('--test-config=' + $bootstrapPath))
    $quoted = @($arguments | ForEach-Object { '"' + ([string]$_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' })
    $child = Start-Process -FilePath $godot -ArgumentList $quoted -WorkingDirectory $project -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'console.log') -RedirectStandardError (Join-Path $evidence 'stderr.log')
    $heldHandle = $child.Handle
    $stopAt = [DateTime]::UtcNow.AddSeconds(885) # Reserve the final 15 seconds for close/cleanup.
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(120)
    do {
        if (CloseRequested) { break }
        $report = Report
        if ($null -ne $report) {
            if ($report.phase -eq 'FAILED') { throw ('Source opponent failed: ' + [string]$report.code) }
            $ready = $report.ok -and $report.registration.ok -and $report.initial_join_ok -and $report.phase -eq 'IN_ROOM' -and
                [string]$report.user_id -ne '' -and @($report.world.players | Where-Object { $_.user_id -eq $report.user_id }).Count -eq 1
        }
        if (-not $ready -and -not $child.HasExited) { Start-Sleep -Milliseconds 100 }
    } while (-not $ready -and -not $child.HasExited -and [DateTime]::UtcNow -lt $startupDeadline)
    if (-not $ready -and -not (CloseRequested)) { throw 'Source opponent did not complete registration, login and real room admission.' }
    if ($ready) {
        # Paths are non-secret; never print credentials, invitations or context contents.
        Write-Output ('UI_SOURCE_OPPONENT_READY game=' + $game + ' report=' + $reportPath + ' control_directory=' + $controlDirectory)
        while (-not $child.HasExited -and -not (CloseRequested) -and [DateTime]::UtcNow -lt $stopAt) { Start-Sleep -Milliseconds 200 }
    }
} catch {
    $failure = $_.Exception.Message
    Write-Output ('UI_SOURCE_OPPONENT_FAILED ' + $failure)
} finally {
    if ($null -ne $child) {
        if (-not $child.HasExited) {
            try {
                SaveJson (Join-Path $controlDirectory 'close.command.json') @{id=('ui_close_' + [Guid]::NewGuid().ToString('N'));action='close'}
                if (-not (WaitChild 10000)) { $forced = $true; TerminateExactChild }
            } catch {
                $forced = $true
                if ($failure -eq '') { $failure = 'Source opponent required exact-handle cleanup.' }
                try { TerminateExactChild } catch { $failure = 'Source opponent exact-handle cleanup failed.' }
            }
        }
        if ($child.HasExited) {
            $child.Refresh()
            $exitCode = $child.ExitCode
            if ($exitCode -ne 0 -and $failure -eq '') { $failure = 'Source opponent exited unsuccessfully.' }
            Write-Output ('UI_SOURCE_OPPONENT_STOPPED ready=' + $ready + ' forced_cleanup=' + $forced + ' exit=' + $exitCode + ' evidence=' + $evidence)
        } else { $failure = 'Source opponent remains alive; exact-handle cleanup failed.' }
        $child.Dispose()
    }
    if ($bootstrapPath -ne '' -and (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
        # Remove only this helper's unused, private bootstrap. The driver normally consumes it.
        $verifiedBootstrap = ProjectPath $bootstrapPath 'Own unused bootstrap'
        if ($verifiedBootstrap -eq (Join-Path $controlDirectory 'bootstrap.json')) { Remove-Item -LiteralPath $verifiedBootstrap -Force }
    }
}
if ($failure -ne '' -or $forced) { exit 1 }
exit 0
