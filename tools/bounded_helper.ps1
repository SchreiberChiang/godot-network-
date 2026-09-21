param([Parameter(Mandatory=$true)][string]$Request,[ValidateRange(100,30000)][int]$TimeoutMs=10000)
$ErrorActionPreference='Stop'
$process=$null
try {
    $job=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
    $helper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $job.helper))
    if([IO.Path]::GetDirectoryName($helper) -ne $PSScriptRoot -or [IO.Path]::GetFileName($helper) -notin @('process_identity.ps1','sqlite_store.ps1')) { throw 'Invalid helper' }
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper)+@($job.arguments)
    $quoted=foreach($argument in $arguments) { '"'+([string]$argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments=$quoted -join ' '
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    [void]$process.Start()
    $heldHandle=$process.Handle
    $stdout=$process.StandardOutput.ReadToEndAsync()
    $stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit($TimeoutMs)) {
        $process.Kill()
        $process.WaitForExit()
        Write-Output '{"ok":false,"code":"HELPER_TIMEOUT","state":"unknown"}'
        exit 1
    }
    $text=$stdout.Result
    if($process.ExitCode -ne 0) { throw 'Helper failed' }
    Write-Output $text.Trim()
} catch {
    Write-Output '{"ok":false,"code":"HELPER_FAILED","state":"unknown"}'
    exit 1
} finally { if($process) { $process.Dispose() } }
