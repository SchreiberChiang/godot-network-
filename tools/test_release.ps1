param([Parameter(Mandatory=$true)][string]$Bundle)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Bundle=[IO.Path]::GetFullPath($Bundle)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Manage.ps1') -Operation verify
if($LASTEXITCODE -ne 0) { throw 'Package verification failed' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Run.ps1') -Test
if($LASTEXITCODE -ne 0) { throw 'Native two-game test failed' }
$stdout=Join-Path $root 'logs/release-stop-console.log'
$stderr=Join-Path $root 'logs/release-stop-stderr.log'
$process=Start-Process -FilePath (Join-Path $Bundle 'RoomHost.exe') -ArgumentList @('--headless','--','--game=turns') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$handle=$process.Handle
try {
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    while([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        $lines=@(Select-String -LiteralPath $stdout -Pattern 'PASS games: verified client launch')
        if($lines.Count -ge 2) { break }
        Start-Sleep -Milliseconds 200
    }
    if($lines.Count -lt 2) { throw 'Interactive clients did not start' }
    # Give both clients time to complete encrypted admission, then exercise stop.
    Start-Sleep -Seconds 3
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Manage.ps1') -Operation stop
    if($LASTEXITCODE -ne 0) { throw 'Operator stop failed' }
    if(-not $process.WaitForExit(45000)) { throw 'Operator stop did not finish' }
    if($process.ExitCode -ne 0 -or -not(Select-String -LiteralPath $stdout -Pattern 'GAMES_RESULT passed=\d+ failed=0' -Quiet)) { throw 'Interactive shutdown failed' }
    if(Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Interactive script error' }
} finally {
    if(-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Manage.ps1') -Operation results
if($LASTEXITCODE -ne 0) { throw 'Result inspection failed' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Manage.ps1') -Operation backup
if($LASTEXITCODE -ne 0) { throw 'Online backup failed' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Bundle 'Manage.ps1') -Operation status
Write-Output 'NATIVE_RELEASE_RESULT failed=0 (two games, operator stop, results, backup)'
