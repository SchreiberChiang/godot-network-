param(
    [ValidateSet('inspect','recover','backup')][string]$Operation = 'inspect',
    [string]$Store = 'res://data/showcase-results',
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logs=Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$arguments=@('--headless','--path',$projectRoot,'--script','res://tools/results.gd','--',('--operation='+$Operation),('--store='+$Store))
$quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
$stdout=Join-Path $logs 'results-console.log'
$stderr=Join-Path $logs 'results-stderr.log'
$process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$ownedHandle=$process.Handle
if(-not $process.WaitForExit(60000)) { $process.Kill(); $process.WaitForExit(); throw 'Results tool timed out; owned process stopped.' }
Get-Content -Encoding UTF8 -LiteralPath $stdout
Get-Content -Encoding UTF8 -LiteralPath $stderr
$code=$process.ExitCode
Write-Output "ROOMKIT_RESULTS_EXIT code=$code"
if($code -ne 0) { exit $code }
if(Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Results tool script error' }
if(-not (Select-String -LiteralPath $stdout -Pattern 'RESULTS_TOOL ok=true' -Quiet)) { throw 'Missing results success marker' }
exit 0
