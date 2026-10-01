[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('capture', 'inspect', 'terminate')][string]$Mode,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$ProcessId,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$ExpectedParentPid,
    [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{16,64}$')][string]$LaunchId,
    [string]$ExpectedCreationFileTime = ''
)

# Output is deliberately restricted to identity metadata. Never emit command lines.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ownedProcess = $null
$result = @{ state = 'unknown'; code = 'PROCESS_IDENTITY_UNVERIFIED' }
$stage = 'arguments'
try {
    if ($Mode -ne 'capture' -and $ExpectedCreationFileTime -notmatch '^\d+$') {
        throw 'Expected creation time required.'
    }
    $stage = 'lookup'
    try {
        $ownedProcess = [System.Diagnostics.Process]::GetProcessById($ProcessId)
    } catch [System.ArgumentException] {
        $result = @{ state = 'exited'; code = '' }
        $result | ConvertTo-Json -Compress
        exit 0
    }
    # Pin the actual Windows process object BEFORE any identity inspection.
    # All subsequent termination uses this HANDLE, never a fresh PID lookup.
    $heldHandle = $ownedProcess.Handle
    if ($ownedProcess.HasExited) {
        $result = @{ state = 'exited'; code = '' }
    } else {
        $stage = 'start_time'
        $creation = $ownedProcess.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
        $stage = 'main_module'
        $actualExecutable = [System.IO.Path]::GetFullPath($ownedProcess.MainModule.FileName)
        $expectedPath = [System.IO.Path]::GetFullPath($ExpectedExecutable)
        $stage = 'cim'
        $metadata = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -OperationTimeoutSec 3
        $stage = 'compare'
        $marker = '(?<!\S)"?--launch-id=' + [regex]::Escape($LaunchId) + '"?(?=\s|$)'
        $matchesIdentity = $null -ne $metadata `
            -and [string]::Equals($actualExecutable, $expectedPath, [StringComparison]::OrdinalIgnoreCase) `
            -and [int]$metadata.ParentProcessId -eq $ExpectedParentPid `
            -and [regex]::IsMatch([string]$metadata.CommandLine, $marker) `
            -and ($Mode -eq 'capture' -or $creation -eq $ExpectedCreationFileTime)
        if ($ownedProcess.HasExited) {
            $result = @{ state = 'exited'; code = '' }
        } elseif (-not $matchesIdentity) {
            $result.stage = 'mismatch'
            $result.error = (@(
                $(if ($null -eq $metadata) { 'no_metadata' }),
                $(if (-not [string]::Equals($actualExecutable, $expectedPath, [StringComparison]::OrdinalIgnoreCase)) { 'executable' }),
                $(if ($null -ne $metadata -and [int]$metadata.ParentProcessId -ne $ExpectedParentPid) { 'parent' }),
                $(if ($null -ne $metadata -and -not [regex]::IsMatch([string]$metadata.CommandLine, $marker)) { 'marker' })
            ) | Where-Object { $_ }) -join '+'
        } elseif ($matchesIdentity) {
            $result = @{ state = 'running'; code = ''; created_filetime = $creation }
            if ($Mode -eq 'inspect') {
                $result.working_set_bytes = $ownedProcess.WorkingSet64
                $result.cpu_ms = [int64]$ownedProcess.TotalProcessorTime.TotalMilliseconds
            }
            if ($Mode -eq 'terminate') {
                Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoomKitOwnedProcess {
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TerminateProcess(IntPtr processHandle, uint exitCode);
}
'@
                if ([RoomKitOwnedProcess]::TerminateProcess($heldHandle, 70)) {
                    if ($ownedProcess.WaitForExit(2000)) {
                        $result = @{ state = 'exited'; code = '' }
                    } else {
                        $result = @{ state = 'unknown'; code = 'PROCESS_EXIT_UNCONFIRMED' }
                    }
                } elseif ($ownedProcess.HasExited) {
                    $result = @{ state = 'exited'; code = '' }
                } else {
                    $result = @{ state = 'unknown'; code = 'PROCESS_TERMINATION_FAILED' }
                }
            }
        }
    }
} catch {
    # Fail closed. An inaccessible or unverified process is never killed.
    $result = @{ state = 'unknown'; code = 'PROCESS_IDENTITY_UNVERIFIED'; stage = $stage; error = $_.Exception.GetType().Name }
} finally {
    if ($null -ne $ownedProcess) { $ownedProcess.Dispose() }
}
$result | ConvertTo-Json -Compress
exit 0
