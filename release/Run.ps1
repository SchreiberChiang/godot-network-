param([ValidateSet('blocks','turns')][string]$Game='turns',[switch]$Test,[switch]$Smoke,[switch]$Panel,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$bundle=$PSScriptRoot
$logs=Join-Path $bundle 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$arguments=@('--headless','--',('--game='+$Game))
if($Test) { $arguments+='--automated=true' }
if($Smoke) { $arguments+='--smoke=true' }
if($Panel) { $arguments+='--panel=true' }
$quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
$process=Start-Process -FilePath (Join-Path $bundle 'RoomHost.exe') -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'host-console.log') -RedirectStandardError (Join-Path $logs 'host-stderr.log')
$handle=$process.Handle
if($Panel) { & (Join-Path $bundle 'tools/open_panel.ps1') -ExpectedPid $process.Id -NoBrowser:$NoBrowser }
$timeout=if($Test -or $Smoke) { 240000 } else { 1900000 }
if(-not $process.WaitForExit($timeout)) { $process.Kill(); $process.WaitForExit(); throw 'Host timeout; owned host stopped, child watchdogs will exit.' }
Get-Content -Encoding UTF8 (Join-Path $logs 'host-console.log')
Get-Content -Encoding UTF8 (Join-Path $logs 'host-stderr.log')
$code=$process.ExitCode
Write-Output "RELEASE_EXIT code=$code"
if($code -ne 0) { exit $code }
if(Select-String -LiteralPath (Join-Path $logs 'host-stderr.log') -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Release script error' }
if(-not(Select-String -LiteralPath (Join-Path $logs 'host-console.log') -Pattern 'GAMES_RESULT passed=\d+ failed=0' -Quiet)) { throw 'Missing release success marker' }
exit 0
