param([string]$EvidenceDirectory='')
# Small file fixtures only; no engine, server, live data or network.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
. (Join-Path $project 'tools/artifact_retention.ps1')
$run=[Guid]::NewGuid().ToString('N')
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $project ('logs/artifact-retention-test-'+$run)}
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $evidence.StartsWith($project+'\logs\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $evidence)){throw 'Fresh project logs evidence required.'}
[void][IO.Directory]::CreateDirectory($evidence)
$fixture=Join-Path $evidence 'project';[void][IO.Directory]::CreateDirectory($fixture)
& git -C $fixture init -q
if($LASTEXITCODE){throw 'Fixture git initialization failed.'}
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++;Write-Output ('PASS '+$Name)}else{$script:failed++;Write-Output ('FAIL '+$Name)}}
function WriteText([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Output([string]$Name){$directory=Join-Path $fixture ('artifacts/'+$Name);WriteText (Join-Path $directory 'payload.bin') ('payload-'+$Name);return $directory}
function Register([string]$Category,[string[]]$Paths,[string[]]$References=@(),[string]$Outcome='success'){return Register-RoomKitArtifact -ProjectRoot $fixture -Category $Category -Paths $Paths -References $References -Outcome $Outcome -Summary @{checks='small fixtures';result=$Outcome}}
function Prune([string]$Category,[string[]]$References=@()){return Invoke-RoomKitArtifactRetention -ProjectRoot $fixture -Category $Category -ProtectedPaths $References -WarningVariable warning -WarningAction SilentlyContinue|Where-Object {$_ -isnot [string]}}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Check $rejected $Name}
function RemoveFixtureLink([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($fixture+'\',[StringComparison]::OrdinalIgnoreCase) -or -not((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid fixture link cleanup.'}
    [IO.Directory]::Delete($full) # Remove this junction only; never recurse into its target.
}
function Three([string]$Category){$first=Output ($Category+'-1');Register $Category @($first)|Out-Null;$second=Output ($Category+'-2');Register $Category @($second)|Out-Null;$third=Output ($Category+'-3');Register $Category @($third)|Out-Null;return @($first,$second,$third)}

$unregistered=Output 'unregistered-old'
$a=Output 'same-purpose-1';$record=Register 'same-purpose' @($a) @() 'failure'
$b=Output 'same-purpose-2';Register 'same-purpose' @($b)|Out-Null
$c=Output 'same-purpose-3';Register 'same-purpose' @($c)|Out-Null
$result=Prune 'same-purpose'
Check ($result.removed -eq 1 -and -not(Test-Path $a) -and (Test-Path $b) -and (Test-Path $c)) 'only latest two same-purpose groups remain'
Check (Test-Path $unregistered) 'unregistered historical output is untouched'
$summary=Get-Content -LiteralPath (Join-Path $fixture ('artifacts/retention-ledger/'+$record+'.json')) -Encoding UTF8 -Raw|ConvertFrom-Json
Check ($summary.state -eq 'pruned' -and $summary.outcome -eq 'failure' -and $summary.snapshot[1].sha256.Length -eq 64) 'failure summary and original payload hash survive removal'

$paths=Three 'changed';WriteText (Join-Path $paths[0] 'payload.bin') 'user edited bytes';$result=Prune 'changed'
Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'modified bytes protect old output'
$paths=Three 'added';WriteText (Join-Path $paths[0] 'user-note.txt') 'keep me';$result=Prune 'added'
Check ($result.skipped -eq 1 -and (Test-Path (Join-Path $paths[0] 'user-note.txt'))) 'user added file protects old output'
$paths=Three 'empty-directory';[void][IO.Directory]::CreateDirectory((Join-Path $paths[0] 'new-empty'));$result=Prune 'empty-directory'
Check ($result.skipped -eq 1) 'new empty directory is also a content change'
$paths=Three 'missing-file';Remove-Item -LiteralPath (Join-Path $paths[0] 'payload.bin');$result=Prune 'missing-file'
Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'missing generated file refuses cleanup'

Reject {Register 'invalid' @((Join-Path $fixture 'data/framework'))} 'real account root rejected'
Reject {Register 'invalid' @((Join-Path $fixture 'PlayerClient'))} 'current local player folder rejected'
Reject {Register 'invalid' @((Join-Path $fixture 'artifacts/worktrees/checkout'))} 'worktrees rejected'
Reject {Register 'invalid' @((Join-Path $fixture 'host'))} 'source root rejected'
Reject {Register 'invalid' @((Join-Path $evidence 'outside'))} 'outside project rejected'
$tracked=Output 'tracked';& git -C $fixture add -- artifacts/tracked/payload.bin
Reject {Register 'tracked' @($tracked)} 'tracked artifact is treated as source'
$paths=Three 'newly-tracked';$relative=$paths[0].Substring($fixture.Length+1).Replace('\','/')+'/payload.bin';& git -C $fixture add -- $relative
$result=Prune 'newly-tracked';Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'file newly added to Git is protected at deletion time'
$embedded=Output 'embedded';WriteText (Join-Path $embedded '.git/HEAD') 'ref: refs/heads/main'
Reject {Register 'embedded' @($embedded)} 'embedded repository rejected'
$fakeData=Join-Path $fixture 'data/test-unproven';WriteText (Join-Path $fakeData 'database.sqlite') 'fake'
Reject {Register 'unproven' @($fakeData)} 'data name alone cannot prove test ownership'
Reject {New-RoomKitArtifactTestRoot -ProjectRoot $fixture -Path $fakeData} 'existing data cannot be adopted'
$testPaths=@()
foreach($number in 1..3){$new=New-RoomKitArtifactTestRoot -ProjectRoot $fixture -Path (Join-Path $fixture ('data/test-owned-'+$number));WriteText (Join-Path $new 'database.sqlite') 'test fake data';Register 'owned-data' @($new)|Out-Null;$testPaths+=$new}
$result=Prune 'owned-data'
Check ($result.removed -eq 1 -and -not(Test-Path $testPaths[0]) -and (Test-Path $testPaths[2])) 'new test ownership proof permits same-purpose retention'

$canary=Output 'canary'
$linked=Output 'linked-content';$link=Join-Path $linked 'junction'
New-Item -ItemType Junction -Path $link -Target $canary|Out-Null
Reject {Register 'links' @($linked)} 'linked descendant refused during registration'
RemoveFixtureLink $link
$paths=Three 'later-link';$link=Join-Path $paths[0] 'junction';New-Item -ItemType Junction -Path $link -Target $canary|Out-Null
$result=Prune 'later-link'
Check ($result.skipped -eq 1 -and (Test-Path (Join-Path $canary 'payload.bin'))) 'link introduced later never traversed or removed'
RemoveFixtureLink $link
$link=Join-Path $fixture 'artifacts/linked-parent';New-Item -ItemType Junction -Path $link -Target $canary|Out-Null
Reject {Register 'parent-link' @((Join-Path $link 'payload.bin'))} 'linked ancestor refused'
RemoveFixtureLink $link

$paths=Three 'explicit-protection';$result=Prune 'explicit-protection' @($paths[0])
Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'caller explicit reference protects old output'
$old=Output 'dependency-old';Register 'dependency' @($old)|Out-Null
$next=Output 'dependency-second';Register 'dependency' @($next)|Out-Null
$latest=Output 'dependency-latest';Register 'dependency' @($latest) @((Join-Path $old 'payload.bin'))|Out-Null
$result=Prune 'dependency'
Check ($result.skipped -eq 1 -and (Test-Path $old)) 'latest generation dependency remains usable'
$usable=Output 'usable-before-failures';Register 'failure-history' @($usable)|Out-Null
foreach($number in 1..3){$bad=Output ('failed-'+$number);Register 'failure-history' @($bad) @() 'failure'|Out-Null}
$result=Prune 'failure-history'
Check ($result.skipped -eq 1 -and $result.removed -eq 1 -and (Test-Path $usable)) 'latest successful delivery survives repeated failed generations'
$paths=Three 'latest-pointer'
WriteText (Join-Path $fixture 'artifacts/deployment-latest.json') (@{format=1;directory=$paths[0].Substring($fixture.Length+1).Replace('\','/')}|ConvertTo-Json)
$result=Prune 'latest-pointer'
Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'current successful deployment pointer protects output'
Remove-Item -LiteralPath (Join-Path $fixture 'artifacts/deployment-latest.json')

$paths=Three 'active'
$childScript=Join-Path $evidence 'child.ps1';WriteText $childScript 'param([string]$HeldDirectory) Start-Sleep -Seconds 30'
$shell=(Get-Process -Id $PID).Path
$arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$childScript,'-HeldDirectory',$paths[0])
$quoted=foreach($argument in $arguments){'"'+$argument.Replace('"','\"')+'"'}
$child=Start-Process -FilePath $shell -ArgumentList $quoted -WindowStyle Hidden -PassThru
$handle=$child.Handle
try{
    $result=Prune 'active';Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'running process protects referenced directory'
}finally{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)};$child.Dispose()}
$result=Prune 'active';Check ($result.removed -eq 1) 'stopped process no longer blocks immutable cleanup'

$paths=Three 'invalid-pointer';WriteText (Join-Path $fixture 'artifacts/deployment-latest.json') '{broken'
$result=Prune 'invalid-pointer'
Check ($result.skipped -eq 1 -and (Test-Path $paths[0])) 'unreadable current pointer fails closed'
Remove-Item -LiteralPath (Join-Path $fixture 'artifacts/deployment-latest.json')
$paths=Three 'independent-purpose';$result=Prune 'independent-purpose'
Check ($result.removed -eq 1 -and (Test-Path $b)) 'purpose groups do not evict other outputs'
Check ((Get-Content -LiteralPath (Join-Path $canary 'payload.bin') -Raw) -eq 'payload-canary') 'link canary remains byte-for-byte intact'

$result=[ordered]@{passed=$script:passed;failed=$script:failed;runtime=$PSVersionTable.PSVersion.ToString();scope='small file fixtures and one owned sleeping shell; no engine/services';evidence=$evidence}
WriteText (Join-Path $evidence 'result.json') ($result|ConvertTo-Json)
Write-Output ('ARTIFACT_RETENTION_TEST '+$script:passed+'/'+$script:failed+' evidence='+$evidence)
if($script:failed){exit 1};exit 0
