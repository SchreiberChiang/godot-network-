param([string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$testRoot = Join-Path $project ('data\test-operator-schedules-' + [Guid]::NewGuid().ToString('N'))
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot | Out-Null
function FreeTcpPort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function FreeUdpBlock {
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $first = Get-Random -Minimum 38000 -Maximum 44000
        $held = New-Object Collections.ArrayList
        $free = $true
        try {
            foreach ($port in $first..($first + 3)) {
                $socket = New-Object Net.Sockets.UdpClient
                [void]$held.Add($socket)
                $socket.Client.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, $port)))
            }
        } catch { $free = $false } finally { foreach ($socket in $held) { $socket.Dispose() } }
        if ($free) { return $first }
    }
    throw 'No free isolated UDP block.'
}
$panelPort = FreeTcpPort
do { $lobbyPort = FreeTcpPort } while ($lobbyPort -eq $panelPort)
do { $controlPort = FreeTcpPort } while ($controlPort -in @($panelPort, $lobbyPort))
$udp = FreeUdpBlock
$config = @{lobby_bind='127.0.0.1';advertised_host='127.0.0.1';lobby_port=$lobbyPort;game_bind='127.0.0.1';control_port=$controlPort;udp_first=$udp;udp_last=($udp+3);max_rooms=4;asset_spaces=@{shooter='shooter';turns='turns'}}
[IO.File]::WriteAllText((Join-Path $testRoot 'config.json'), ($config | ConvertTo-Json -Depth 10 -Compress), (New-Object Text.UTF8Encoding($false)))
$arguments = @('--headless','--path',$project,'--log-file',(Join-Path $testRoot 'operator-test.log'),'--script','res://tests/run_operator_schedules.gd','--',('--data-root=' + $testRoot),('--panel-port=' + $panelPort))
$quoted = @($arguments | ForEach-Object { '"' + ([string]$_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' })
$child = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testRoot 'console.log') -RedirectStandardError (Join-Path $testRoot 'stderr.log')
$heldHandle = $child.Handle
function EndExactHandle([IntPtr]$Handle, $Process) {
    if ($Process.HasExited) { return }
    if ($null -eq ('RoomKitScheduleTestProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoomKitScheduleTestProcess {
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TerminateProcess(IntPtr handle, uint exitCode);
}
'@
    }
    if (-not [RoomKitScheduleTestProcess]::TerminateProcess($Handle, 73) -or -not $Process.WaitForExit(5000)) { throw 'Exact schedule-test process cleanup failed.' }
}
function EmergencyCleanup {
    # No rooms are created by this test. On an abnormal watchdog path, capture
    # only this Operator's current, private-journal host before stopping parent.
    $marker = Join-Path $testRoot 'host-running.json'
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $owned = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedExecutable = [IO.Path]::GetFullPath($Godot)
        if (-not $owned.verified -or [int]$owned.parent_pid -ne $child.Id -or
            [string]$owned.launch_id -cnotmatch '^[a-f0-9]{32}$' -or [string]$owned.created_filetime -notmatch '^\d+$' -or
            [IO.Path]::GetFullPath([string]$owned.executable) -ine $expectedExecutable) { throw 'Refuse unverified schedule-test child cleanup.' }
        $hostProcess = $null
        try { $hostProcess = [Diagnostics.Process]::GetProcessById([int]$owned.pid) } catch [ArgumentException] { }
        if ($null -ne $hostProcess) {
            try {
                $hostHandle = $hostProcess.Handle
                if (-not $hostProcess.HasExited) {
                    if ($hostProcess.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -ne [string]$owned.created_filetime -or $hostProcess.MainModule.FileName -ine $expectedExecutable) { throw 'Schedule-test child creation identity mismatch.' }
                    $verified = & (Join-Path $project 'tools\process_identity.ps1') -Mode inspect -ProcessId $owned.pid -ExpectedParentPid $owned.parent_pid -ExpectedExecutable $owned.executable -LaunchId $owned.launch_id -ExpectedCreationFileTime $owned.created_filetime | ConvertFrom-Json
                    if ($verified.state -ne 'running' -and -not $hostProcess.HasExited) { throw 'Schedule-test child marker could not be verified.' }
                    EndExactHandle $hostHandle $hostProcess
                }
            } finally { $hostProcess.Dispose() }
        }
    }
    EndExactHandle $heldHandle $child
}
try {
    if (-not $child.WaitForExit(310000)) {
        # Ask this isolated test to clean up its own verified children first.
        [IO.File]::WriteAllText((Join-Path $testRoot 'operator-stop.request'), 'stop')
        if (-not $child.WaitForExit(65000)) {
            EmergencyCleanup
            throw 'Isolated schedule test watchdog required exact owned-process cleanup.'
        }
        throw 'Schedule test exceeded its normal time budget.'
    }
    $child.Refresh()
    Get-Content -LiteralPath (Join-Path $testRoot 'console.log') -Encoding UTF8
    Get-Content -LiteralPath (Join-Path $testRoot 'stderr.log') -Encoding UTF8
    Write-Output ('OPERATOR_SCHEDULE_EXIT=' + $child.ExitCode)
    Write-Output ('OPERATOR_SCHEDULE_EVIDENCE=' + $testRoot)
    exit $child.ExitCode
} finally {
    if (-not $child.HasExited) {
        [IO.File]::WriteAllText((Join-Path $testRoot 'operator-stop.request'), 'stop')
        if (-not $child.WaitForExit(65000)) { EmergencyCleanup }
    }
    # Successful tests have confirmed/released every host internally before exit.
    $child.Dispose()
}
