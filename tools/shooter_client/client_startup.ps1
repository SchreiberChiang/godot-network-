param([string]$StartupRequest='')
# A hidden console intermediary owns the native process handle for the entire
# observation. Godot may attach to that console without attaching to StartGame.
# Passing observation means only that the process survived this bounded interval.
$ErrorActionPreference='Stop'
function Quote-ClientStartupArguments($Values) {
    foreach($value in $Values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
}
function Assert-ClientStartupPlainPath([string]$Path) {
    for($cursor=[IO.Path]::GetFullPath($Path);$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)) {
        $item=$null
        try {$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop}
        catch [Management.Automation.ItemNotFoundException] {continue}
        if($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType))) {throw ('CLIENT_STARTUP_LINKED_PATH: '+$cursor)}
    }
}
if($StartupRequest -ne '') {
    Assert-ClientStartupPlainPath $StartupRequest
    $request=Get-Content -LiteralPath $StartupRequest -Encoding UTF8 -Raw | ConvertFrom-Json
    $native=$null
    $receipt=[ordered]@{format=1;request_id=$request.request_id;status='launch_failed';launcher_exit_code=1;native_exit_code=$null;pid=$null;start_time_utc=$null;observation_ms=[int]$request.observation_ms;stdout=$request.stdout;stderr=$request.stderr;error=''}
    try {
        foreach($path in @($request.directory,$request.file_path,$request.stdout,$request.stderr,$request.receipt,($request.receipt+'.tmp'))){Assert-ClientStartupPlainPath $path}
        $native=Start-Process -FilePath $request.file_path -ArgumentList (Quote-ClientStartupArguments $request.arguments) -WorkingDirectory $request.directory -PassThru -RedirectStandardOutput $request.stdout -RedirectStandardError $request.stderr
        # Keep the actual created process handle. No process scans or PID adoption.
        $ownedHandle=$native.Handle
        $receipt.pid=$native.Id
        $receipt.start_time_utc=$native.StartTime.ToUniversalTime().ToString('o')
        $exited=$native.WaitForExit([int]$request.observation_ms)
        $native.Refresh()
        if($exited -or $native.HasExited) {
            $native.WaitForExit()
            $receipt.status='exited'
            $receipt.native_exit_code=$native.ExitCode
            # A clean, short exit is still not an active client. Preserve every
            # nonzero OS code; map early exit 0 to a launcher failure with code 1.
            $receipt.launcher_exit_code=1
            if($native.ExitCode -ne 0){$receipt.launcher_exit_code=$native.ExitCode}
        } else {
            $receipt.status='observed'
            $receipt.launcher_exit_code=0
        }
    } catch {$receipt.error=$_.Exception.Message}
    finally {if($null -ne $native){$native.Dispose()}}
    $temporary=$request.receipt+'.tmp'
    Assert-ClientStartupPlainPath $temporary
    Assert-ClientStartupPlainPath $request.receipt
    [IO.File]::WriteAllText($temporary,($receipt | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
    [IO.File]::Move($temporary,$request.receipt)
    exit $receipt.launcher_exit_code
}
function Start-ClientObserved {
    param([Parameter(Mandatory=$true)][string]$FilePath,[string[]]$Arguments=@(),[Parameter(Mandatory=$true)][string]$Directory,[ValidateRange(100,10000)][int]$ObservationMilliseconds=2000)
    $directoryPath=[IO.Path]::GetFullPath($Directory)
    $executable=[IO.Path]::GetFullPath($FilePath)
    Assert-ClientStartupPlainPath $directoryPath
    Assert-ClientStartupPlainPath $executable
    if(-not(Test-Path -LiteralPath $executable -PathType Leaf)){throw ('CLIENT_STARTUP_MISSING_EXECUTABLE: '+$executable)}
    $logs=Join-Path $directoryPath 'client-data/startup'
    Assert-ClientStartupPlainPath $logs
    [void][IO.Directory]::CreateDirectory($logs)
    Assert-ClientStartupPlainPath $logs
    $id=[Guid]::NewGuid().ToString('N')
    $request=Join-Path $logs ($id+'.request.json')
    $receipt=Join-Path $logs ($id+'.receipt.json')
    $payload=@{request_id=$id;file_path=$executable;arguments=@($Arguments);directory=$directoryPath;observation_ms=$ObservationMilliseconds;stdout=(Join-Path $logs ($id+'.stdout.log'));stderr=(Join-Path $logs ($id+'.stderr.log'));receipt=$receipt}
    Assert-ClientStartupPlainPath $request
    [IO.File]::WriteAllText($request,($payload | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
    $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $worker=$null
    $removeRequest=$false
    try {
        $worker=Start-Process -FilePath $shell -WindowStyle Hidden -PassThru -ArgumentList (Quote-ClientStartupArguments @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'client_startup.ps1'),'-StartupRequest',$request)) -RedirectStandardOutput (Join-Path $logs ($id+'.worker-stdout.log')) -RedirectStandardError (Join-Path $logs ($id+'.worker-stderr.log'))
        $ownedWorkerHandle=$worker.Handle
        $workerId=$worker.Id
        $workerStart=$worker.StartTime.ToUniversalTime().ToString('o')
        if(-not $worker.WaitForExit($ObservationMilliseconds+8000)) {
            $cleanupError=''
            try {
                # This exact worker was created above and its handle is still
                # held. Never kill a native client, descendant tree or scanned PID.
                if(-not $worker.HasExited){$worker.Kill()}
                if(-not $worker.WaitForExit(3000)){throw 'Owned worker exit was not confirmed within 3000ms.'}
            } catch {$cleanupError=$_.Exception.Message}
            $recovery=Join-Path $logs ($id+'.recovery.json')
            $recoveryRecord=@{format=1;request_id=$id;request_path=$request;worker_pid=$workerId;worker_start_time_utc=$workerStart;worker_executable=$shell;created_utc=[DateTime]::UtcNow.ToString('o');reason='receipt_timeout';worker_exit_confirmed=($cleanupError -eq '');cleanup_error=$cleanupError;native_state='unknown; no native process was terminated';request_preserved=($cleanupError -ne '')}
            Assert-ClientStartupPlainPath $recovery
            [IO.File]::WriteAllText($recovery,($recoveryRecord | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
            if($cleanupError -ne ''){throw ('CLIENT_STARTUP_WORKER_CLEANUP_FAILED: request='+$request+' recovery='+$recovery+' error='+$cleanupError)}
            $removeRequest=$true
            throw ('CLIENT_STARTUP_RECEIPT_TIMEOUT: owned worker ended; recovery='+$recovery)
        }
        if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){throw ('CLIENT_STARTUP_RECEIPT_MISSING: '+$logs)}
        $record=Get-Content -LiteralPath $receipt -Encoding UTF8 -Raw | ConvertFrom-Json
        if($record.request_id -cne $id -or $record.status -notin @('observed','exited','launch_failed') -or [int]$record.launcher_exit_code -ne $worker.ExitCode){throw ('CLIENT_STARTUP_RECEIPT_INVALID: '+$logs)}
        if($record.status -eq 'observed' -and ([int]$record.launcher_exit_code -ne 0 -or [int]$record.pid -le 0 -or -not $record.start_time_utc)){throw ('CLIENT_STARTUP_RECEIPT_INVALID: '+$logs)}
        $record | Add-Member -NotePropertyName receipt_path -NotePropertyValue $receipt
        $removeRequest=$true
        return $record
    } finally {
        if($null -ne $worker){$worker.Dispose()}
        # Failed cleanup keeps the request and recovery identity for manual review.
        if($removeRequest -and (Test-Path -LiteralPath $request -PathType Leaf)){Assert-ClientStartupPlainPath $request;Remove-Item -LiteralPath $request -Force}
    }
}
