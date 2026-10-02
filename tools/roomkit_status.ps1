param([Parameter(Mandatory=$true)][string]$DataRoot)
$ErrorActionPreference='Stop'
$descriptor=Join-Path $DataRoot 'operator.json'
# No engine execution, HTTP request, build, mkdir, stale cleanup or stop signal.
try {
    . (Join-Path $PSScriptRoot 'roomkit_entry.ps1')
    Assert-RoomKitPath $descriptor
    if(-not(Test-Path -LiteralPath $descriptor -PathType Leaf)){Write-Output ('ROOMKIT_NOT_RUNNING data='+$DataRoot);exit 0}
    $record=Get-Content -LiteralPath $descriptor -Raw -Encoding UTF8 | ConvertFrom-Json
    if($record.pid -isnot [int] -and $record.pid -isnot [long]){throw 'Invalid descriptor'}
    if($record.pid -le 0 -or $record.pid -gt [int]::MaxValue){throw 'Invalid PID'}
    $process=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$record.pid) -OperationTimeoutSec 3 -ErrorAction Stop
    if($null -eq $process){Write-Output ('ROOMKIT_STALE data='+$DataRoot);exit 3}
    # Legacy operator.json records no launch identifier or creation timestamp.
    # Even matching executable/port is insufficient to rule out PID reuse.
    Write-Output ('ROOMKIT_UNKNOWN reason=legacy_identity_incomplete data='+$DataRoot)
    exit 3
} catch {Write-Output ('ROOMKIT_UNKNOWN reason=identity_unavailable data='+$DataRoot);exit 3}
