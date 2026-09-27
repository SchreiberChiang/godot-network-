param([Parameter(Mandatory=$true)][string]$Database,[Parameter(Mandatory=$true)][string]$Scratch)
# Resident storage PROBE for evaluation only; not wired into any production path.
# One long-lived Windows PowerShell process runs the unchanged production helper
# tools/sqlite_store.ps1 in-process for every request, so PowerShell start-up and
# the C# compile (identical Add-Type source is reused after the first call) are
# paid once. Protocol: one base64 UTF-8 JSON request per stdin line, one JSON reply
# per stdout line; an empty line or EOF ends the process.
# The probe still hands each request to sqlite_store.ps1 through a short-lived file
# in $Scratch (a private test directory) because that helper's stdin belongs to
# this loop; a production design would pass the request in memory instead.
$ErrorActionPreference='Stop'
$store=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools\sqlite_store.ps1'
$utf8=New-Object Text.UTF8Encoding($false)
$stdout=New-Object IO.StreamWriter([Console]::OpenStandardOutput(),$utf8)
$stdout.AutoFlush=$true
$stdin=New-Object IO.StreamReader([Console]::OpenStandardInput(),[Text.Encoding]::ASCII)
while($true) {
    $line=$stdin.ReadLine()
    if([string]::IsNullOrEmpty($line)) { break }
    $reply='{"ok":false,"code":"PROBE_FAILED"}'
    $path=Join-Path $Scratch ('probe-'+[Guid]::NewGuid().ToString('N')+'.json')
    try {
        [IO.File]::WriteAllText($path,$utf8.GetString([Convert]::FromBase64String($line)),$utf8)
        $output=& $store -Database $Database -Request $path
        $text=(@($output) -join '').Trim()
        if($text) { $reply=$text }
    } catch {
        $reply='{"ok":false,"code":"PROBE_EXCEPTION"}'
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $stdout.WriteLine($reply)
}
