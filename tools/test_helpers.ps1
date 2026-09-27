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
# Stdin mode: the job and request body arrive as base64 lines, never as files.
$echo=@'
param([string]$Tag)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$line=[Console]::In.ReadLine()
$text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line))
$hash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','')
Write-Output ('{"ok":true,"tag":"'+$Tag+'","sha256":"'+$hash+'"}')
'@
[IO.File]::WriteAllText((Join-Path $fixture 'account_store.ps1'),$echo,$utf8)
$zh=-join @([char]0x4E2D,[char]0x6587)  # two CJK characters, kept ASCII-only in source
function StdinJob($Job) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Job | ConvertTo-Json -Compress))) }
$body='{"op":"account.login","password":"'+$zh+' with \"quotes\""}'
$expected=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($body))).Replace('-','')
$before=@(Get-ChildItem -LiteralPath $fixture -File).Count
$result=StdinJob @{helper='account_store.ps1';arguments=@('-Tag',$zh);input=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))} | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'bounded_helper.ps1') -TimeoutMs 10000
$parsed=$result | ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or -not $parsed.ok -or $parsed.sha256 -ne $expected -or $parsed.tag -ne $zh) { throw 'Stdin body was not forwarded byte for byte' }
if(@(Get-ChildItem -LiteralPath $fixture -File).Count -ne $before) { throw 'Stdin mode created a file' }
Remove-Item -LiteralPath $evidence
$result=StdinJob @{helper='sqlite_store.ps1';arguments=@('-Evidence',$evidence);input='e30='} | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'bounded_helper.ps1') -TimeoutMs 2000
if($LASTEXITCODE -ne 1 -or ($result | ConvertFrom-Json).code -ne 'HELPER_TIMEOUT') { throw 'Stdin helper deadline assertion failed' }
$record=Get-Content -Raw $evidence | ConvertFrom-Json
$live=Get-Process -Id $record.pid -ErrorAction SilentlyContinue
if($live -and $live.StartTime.ToFileTimeUtc() -eq $record.start) { throw 'Stdin slow helper survived timeout' }
$result=StdinJob @{helper='account_store.ps1';arguments=@();input='not base64!'} | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'bounded_helper.ps1')
if($LASTEXITCODE -ne 1 -or ($result | ConvertFrom-Json).code -ne 'HELPER_FAILED') { throw 'Invalid stdin body accepted' }
Write-Output 'HELPER_RESULT passed=6 failed=0'
