$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture=Join-Path $root ('logs/helper-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bounded_helper.ps1') -Destination $fixture
$utf8=New-Object Text.UTF8Encoding($false)
$script=@'
param([string]$Evidence)
$owned=Get-Process -Id $PID
[IO.File]::WriteAllText($Evidence,(@{pid=$PID;start=$owned.StartTime.ToFileTimeUtc()} | ConvertTo-Json))
Start-Sleep -Seconds 15
'@
[IO.File]::WriteAllText((Join-Path $fixture 'sqlite_store.ps1'),$script,$utf8)
$evidence=Join-Path $fixture 'child.json'
$request=Join-Path $fixture 'request.json'
[IO.File]::WriteAllText($request,(@{helper='sqlite_store.ps1';arguments=@('-Evidence',$evidence)} | ConvertTo-Json),$utf8)
$watch=[Diagnostics.Stopwatch]::StartNew()
$result=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'bounded_helper.ps1') -Request $request -TimeoutMs 2000
$code=$LASTEXITCODE
if($code -ne 1 -or ($result | ConvertFrom-Json).code -ne 'HELPER_TIMEOUT' -or $watch.ElapsedMilliseconds -gt 10000) { throw 'Helper deadline assertion failed' }
if(-not(Test-Path -LiteralPath $evidence)) { throw 'Slow helper never started; timeout test is inconclusive' }
$record=Get-Content -Raw $evidence | ConvertFrom-Json
$live=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
if($live -and $live.StartTime.ToFileTimeUtc() -eq $record.start) { throw 'Original slow helper survived timeout' }
[IO.File]::WriteAllText($request,(@{helper='../unexpected.ps1';arguments=@()} | ConvertTo-Json),$utf8)
$result=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'bounded_helper.ps1') -Request $request
if($LASTEXITCODE -ne 1 -or ($result | ConvertFrom-Json).code -ne 'HELPER_FAILED') { throw 'Helper path allowlist failed' }
Write-Output 'HELPER_RESULT passed=3 failed=0'
