# Shared by tools/run_framework.ps1 and tests: start a program on a hidden console
# the user cannot close, and return its verified Process object.
function Quote-DetachedArguments($arguments) { foreach($argument in $arguments) { '"'+([string]$argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
function Start-Detached([string]$FilePath,$Arguments,[string]$Directory,[string]$Stdout,[string]$Stderr,[string]$WindowStyle='Hidden') {
    # Godot attaches to its parent's console; closing that window used to end the
    # operator without its shutdown routine. Start through a hidden intermediary
    # so the program sits on a console the user cannot close (tools/detached_start.ps1).
    $requests=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) 'logs\detached-start'
    New-Item -ItemType Directory -Force -Path $requests | Out-Null
    $id=[Guid]::NewGuid().ToString('N')
    $request=Join-Path $requests ($id+'.json'); $result=Join-Path $requests ($id+'.result.json')
    [IO.File]::WriteAllText($request,(@{file_path=$FilePath;arguments=@($Arguments);working_directory=$Directory;stdout=$Stdout;stderr=$Stderr;window_style=$WindowStyle;result=$result}|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList (Quote-DetachedArguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'detached_start.ps1'),'-Request',$request)) | Out-Null
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    while(-not (Test-Path -LiteralPath $result) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if(-not (Test-Path -LiteralPath $result)) { throw 'Detached start did not report a process.' }
    $record=Get-Content -Encoding UTF8 -Raw -LiteralPath $result | ConvertFrom-Json
    Remove-Item -LiteralPath $request,$result -Force
    if(-not $record.ok) { throw ('Start failed: '+$record.error) }
    try { $started=[Diagnostics.Process]::GetProcessById([int]$record.pid) } catch { throw 'DETACHED_PROCESS_EXITED: the started program exited immediately.' }
    # Only accept the process created above: same start time and executable.
    if($started.StartTime.ToUniversalTime().ToString('o') -ne $record.start_time_utc -or -not ($started.Path -ieq $FilePath)) { throw 'Detached process identity mismatch.' }
    return $started
}
