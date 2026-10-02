# Runs the actual source/generated Windows launchers with process/build stubs.
# It does NOT execute Windows binaries or validate native Windows behavior.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$test=Join-Path $root ('data/test-u1/windows-launchers-'+[Guid]::NewGuid().ToString('N'))
function Put($Path,$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text)}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$chinese=([string][char]0x4e2d)+[char]0x6587
$source=Join-Path $test ('source space '+$chinese)
Put (Join-Path $source 'engine.exe') 'NOT AN ENGINE'
foreach($name in @('run_framework.ps1','roomkit_entry.ps1')){Put (Join-Path $source ('tools/'+$name)) ([IO.File]::ReadAllText((Join-Path $root ('tools/'+$name))))}
Put (Join-Path $source 'tools/build_framework.ps1') 'param($IndexPath,$BuildRoot)'
Put (Join-Path $source 'tools/protect_data.ps1') 'param($ProjectRoot,$DataRoot)'
Put (Join-Path $source 'tools/detached_process.ps1') @'
function Start-Detached($FilePath,$Arguments,$Directory,$Stdout,$Stderr) {
 $data=($Arguments | Where-Object {$_ -like '--data-root=*'}).Substring(12)
 [void][IO.Directory]::CreateDirectory($data)
 [IO.File]::WriteAllText((Join-Path $Directory 'captured.json'),(ConvertTo-Json -InputObject @($Arguments)))
 [IO.File]::WriteAllText((Join-Path $data 'operator.json'),' {"pid":43210,"port":29191}')
 return [pscustomobject]@{Handle=0;Id=43210;HasExited=$false}
}
'@
$launcher=Join-Path $source 'tools/run_framework.ps1'
& $launcher -NoBrowser -Godot (Join-Path $source 'engine.exe')
Assert ($LASTEXITCODE -eq 0) 'source default failed'
$a=Get-Content -LiteralPath (Join-Path $source 'captured.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert (($a -contains ('--data-root='+(Join-Path $source 'data/framework'))) -and ($a -contains '--panel-port=28291') -and @($a|Where-Object {$_ -like '--initial-*'}).Count -eq 0) 'source default changed'
Write-Output 'PASS source actual launcher default data/port/network preserved (fake process)'
& $launcher -NoBrowser -Godot (Join-Path $source 'engine.exe') -Instance test-u1 -PanelPort 29191 -LobbyPort 29200 -ControlPort 29201 -UdpRange 29340-29347 -Bind 127.0.0.1
Assert ($LASTEXITCODE -eq 0) 'source explicit failed'
$a=Get-Content -LiteralPath (Join-Path $source 'captured.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert (($a -contains ('--data-root='+(Join-Path $source 'data/instance-test-u1/data'))) -and ($a -contains '--panel-port=29191') -and ($a -contains '--initial-ports=29200,29201,29340,29347') -and ($a -contains '--initial-bind=127.0.0.1') -and ($a -contains ('--games='+(Join-Path $source 'data/instance-test-u1/games.json'))) -and ($a -contains ('--public-client-dir='+(Join-Path $source 'data/instance-test-u1/public')))) 'source explicit args changed'
Write-Output 'PASS source actual launcher explicit instance/network/index/public (fake process)'
$package=Join-Path $test ('package space '+$chinese)
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/build_framework_release.ps1'),[ref]$t,[ref]$e)
$assignment=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$launcher'},$true)
Put (Join-Path $package 'RunFramework.ps1') $assignment.Right.Expression.Value
Put (Join-Path $package 'tools/protect_runtime.ps1') 'param($ProjectRoot)'
Put (Join-Path $package 'tools/roomkit_entry.ps1') ([IO.File]::ReadAllText((Join-Path $root 'tools/roomkit_entry.ps1')))
foreach($game in @('shooter','turns')){[void][IO.Directory]::CreateDirectory((Join-Path $package ('clients/'+$game)))}
function Start-Process($FilePath,$ArgumentList,$WorkingDirectory,[switch]$PassThru,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError) {
 $all=$ArgumentList -join ' '
 $data=[regex]::Match($all,'"--data-root=([^"\r\n]+)"').Groups[1].Value
 $public=[regex]::Match($all,'"--public-client-dir=([^"\r\n]+)"').Groups[1].Value
 Assert ($data -and $public) 'missing explicit runtime paths'
 Put (Join-Path $data 'operator.json') '{"pid":43210,"port":29191}'
 Put (Join-Path $public 'connection.json') '{"ca_certificate":"fixture"}'
 Put (Join-Path $public 'server.crt') 'FAKE CERTIFICATE'
 Put (Join-Path $WorkingDirectory 'captured.txt') $all
 $p=[pscustomobject]@{Handle=0;Id=43210;HasExited=$false}
 $p|Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
 return $p
}
$launcher=Join-Path $package 'RunFramework.ps1'
& $launcher -NoBrowser
$a=Get-Content -LiteralPath (Join-Path $package 'captured.txt') -Raw -Encoding UTF8
Assert ($a.Contains('--data-root='+(Join-Path $package 'data/framework')) -and $a.Contains('--panel-port=28291') -and -not $a.Contains('--initial-')) 'package defaults changed'
Write-Output 'PASS generated package launcher defaults (fake process)'
& $launcher -NoBrowser -Instance test-u1 -PanelPort 29191 -LobbyPort 29200 -ControlPort 29201 -UdpRange 29340-29347 -Bind 127.0.0.1
$a=Get-Content -LiteralPath (Join-Path $package 'captured.txt') -Raw -Encoding UTF8
Assert ($a.Contains('--data-root='+(Join-Path $package 'data/instance-test-u1/data')) -and $a.Contains('--initial-ports=29200,29201,29340,29347') -and $a.Contains('--initial-bind=127.0.0.1') -and $a.Contains('--panel-port=29191')) 'package explicit changed'
Write-Output 'PASS generated package launcher explicit instance/network/public (fake process)'
Write-Output 'WINDOWS_LAUNCHER_FIXTURES passed=4 failed=0 native-Windows=NOT-TESTED'
