param(
    [Parameter(Mandatory=$true)][ValidateSet('sqlite_store.ps1','account_store.ps1')][string]$Helper,
    [Parameter(Mandatory=$true)][string]$Database,
    [ValidateRange(1,86400)][int]$IdleSeconds=300
)
# Resident storage worker: one long-lived process serves ONE database through ONE
# existing helper, run in-process so PowerShell start-up and the helper's C#
# compile (identical Add-Type source is reused) are paid once. The Godot host owns
# this process through execute_with_pipe, holds its handle, serialises requests,
# enforces the deadline and kills it on timeout.
# Protocol: one base64 UTF-8 JSON request per stdin line -> one JSON reply line on
# stdout. Requests stay in memory (-RequestJson); nothing is written to disk here.
# Only operations that are safe to repeat are accepted, because the host retries a
# failed call through the one-shot path. EOF, an empty line or idle time ends it.
$ErrorActionPreference='Stop'
$allowed=@{
    'sqlite_store.ps1'=@('asset.read','asset.snapshot','asset.commit')
    'account_store.ps1'=@('session.authenticate')
}[$Helper]
$script=Join-Path $PSScriptRoot $Helper
$refused='{"ok":false,"code":"WORKER_FAILED"}'  # internal: host falls back to the one-shot path
$utf8=New-Object Text.UTF8Encoding($false)
$stdout=New-Object IO.StreamWriter([Console]::OpenStandardOutput(),$utf8)
$stdout.AutoFlush=$true
$stdin=New-Object IO.StreamReader([Console]::OpenStandardInput(),[Text.Encoding]::ASCII)
while($true) {
    $pending=$stdin.ReadLineAsync()
    if(-not $pending.Wait($IdleSeconds*1000)) { break }
    $line=$pending.Result
    if([string]::IsNullOrEmpty($line)) { break }
    $reply=$refused
    try {
        if($line.Length -le 262144 -and $line.Length % 4 -eq 0 -and $line -match '^[A-Za-z0-9+/]*={0,2}$') {
            $json=$utf8.GetString([Convert]::FromBase64String($line))
            $request=$json | ConvertFrom-Json
            if($request -is [PSCustomObject] -and [string]$request.op -in $allowed) {
                $text=(@(& $script -Database $Database -RequestJson $json) -join '').Trim()
                if($text.StartsWith('{')) { $reply=$text }
            }
        }
    } catch {
        $reply=$refused
    }
    # Replies from both helpers are ASCII (non-ASCII is escaped); one line each.
    $stdout.WriteLine($reply.Replace("`r",'').Replace("`n",''))
}
