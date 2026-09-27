param([string]$Request='',[ValidateRange(100,30000)][int]$TimeoutMs=10000)
$ErrorActionPreference='Stop'
$process=$null
$started=$false
try {
    if($Request) {
        $job=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        # Stdin mode: one line of base64 UTF-8 JSON. Nothing touches disk, and the
        # ASCII line cannot be altered by console code pages (paths may be Chinese).
        $line=[Console]::In.ReadLine()
        if([string]::IsNullOrEmpty($line) -or $line.Length -gt 65536) { throw 'Invalid job' }
        $job=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line)) | ConvertFrom-Json
    }
    $helper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $job.helper))
    if([IO.Path]::GetDirectoryName($helper) -ne $PSScriptRoot -or [IO.Path]::GetFileName($helper) -notin @('process_identity.ps1','sqlite_store.ps1','account_store.ps1','operator_maintenance.ps1')) { throw 'Invalid helper' }
    # Optional request body forwarded to the helper's stdin as the same kind of
    # base64 line; it never appears in arguments or files.
    $payload=$job.PSObject.Properties['input']
    if($payload -and ($payload.Value -isnot [string] -or $payload.Value -notmatch '^[A-Za-z0-9+/]*={0,2}$')) { throw 'Invalid input' }
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper)+@($job.arguments)
    $quoted=foreach($argument in $arguments) { '"'+([string]$argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments=$quoted -join ' '
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.RedirectStandardInput=[bool]$payload
    # Windows PowerShell 5.1 chooses the child stdin writer encoding from this
    # process's console input encoding. Its default UTF-8 writer may add a BOM.
    if($payload) { [Console]::InputEncoding=New-Object Text.UTF8Encoding($false) }
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    [void]$process.Start()
    $started=$true
    $heldHandle=$process.Handle
    $stdout=$process.StandardOutput.ReadToEndAsync()
    $stderr=$process.StandardError.ReadToEndAsync()
    if($payload) {
        $process.StandardInput.WriteLine([string]$payload.Value)
        $process.StandardInput.Close()
    }
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
    # A helper still waiting for input must not outlive this bounded call; the
    # held handle identifies exactly the child this script started.
    if($started -and -not $process.HasExited) { try { $process.Kill(); [void]$process.WaitForExit(5000) } catch {} }
    Write-Output '{"ok":false,"code":"HELPER_FAILED","state":"unknown"}'
    exit 1
} finally { if($process) { $process.Dispose() } }
