# Real launcher code, fake layouts and directory links; never starts an engine.
param([string]$SourceRoot='')
$ErrorActionPreference='Stop'
if(-not $SourceRoot){$SourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
$test=Join-Path $SourceRoot ('data/test-u1/paths-'+[Guid]::NewGuid().ToString('N'))
$script:passed=0
$links=New-Object 'System.Collections.Generic.List[string]'
$isWindowsHost=[Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$linkType=if($isWindowsHost){'Junction'}else{'SymbolicLink'}
function Put($Path,$Text='fixture'){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text)}
function Check($Name,[scriptblock]$Body){& $Body;$script:passed++;Write-Output ('PASS '+$Name)}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action){$errorText='';try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message};Assert ($errorText -like '*Linked*refused*') ('Expected link refusal, got: '+$errorText)}
function Link($Path,$Target){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));New-Item -ItemType $linkType -Path $Path -Target $Target|Out-Null;$links.Add($Path)}
try {
 $source=Join-Path $test 'source'
 foreach($name in @('roomkit_entry.ps1','roomkit_status.ps1','run_framework.ps1')){Put (Join-Path $source ('tools/'+$name)) ([IO.File]::ReadAllText((Join-Path $SourceRoot ('tools/'+$name))))}
 Put (Join-Path $source 'tools/detached_process.ps1') '# No process creation is permitted in this fixture.'
 foreach($name in @('project.godot','host/operator.gd','host/managed_host.gd','sdk/roomkit/shared/json_wire.gd','examples/framework/services.json','tools/roomkit.ps1','tools/build_framework.ps1','tools/check_environment.ps1')){Put (Join-Path $source $name)}
 $target=Join-Path $test 'canary';Put (Join-Path $target 'keep.txt') 'unchanged'
 Link (Join-Path $source 'artifacts/history-link') $target
 Link (Join-Path $source 'artifacts/client') $target
 Link (Join-Path $source 'run') $target
 Link (Join-Path $source 'data/instance-test-u1/build/history-link') $target
 Link (Join-Path $source 'data/instance-test-u1/public') $target
 $launcher=Join-Path $source 'tools/run_framework.ps1'
 Check 'source default stop ignores unrelated artifacts public and run' {& $launcher -Mode stop;Assert ($LASTEXITCODE -eq 0) 'stop failed'}
 Check 'source default status ignores unrelated artifacts public and run' {& $launcher -Mode status;Assert ($LASTEXITCODE -eq 0) 'status failed'}
 Check 'source custom stop ignores build history' {& $launcher -Mode stop -Instance test-u1;Assert ($LASTEXITCODE -eq 0) 'stop failed'}
 . (Join-Path $source 'tools/roomkit_entry.ps1')
 function Invoke-RoomKitWindowsDelegate([string]$File,[hashtable]$Parameters){$script:delegated=$Parameters}
 function Invoke-RoomKitDelegate([string]$File,[object[]]$Arguments,[bool]$Shell){$script:delegated=$Arguments}
 foreach($platform in @('Windows','Linux')){foreach($action in @('stop','status','check')){
  Check ($platform+' dispatch '+$action+' ignores unrelated runtime history') {
   $script:delegated=$null
   foreach($name in @('roomkit_linux.sh','runtime_paths.sh','prepare_environment.sh')){Put (Join-Path $source ('tools/'+$name))}
   $a=@($action);if($action -ne 'check'){$a+=@('--instance','test-u1')}
   Invoke-RoomKit $source $platform $a|Out-Null;Assert ($null -ne $script:delegated) 'did not delegate'
  }
 }}
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'tools/build_framework_release.ps1'),[ref]$tokens,[ref]$errors)
 Assert ($errors.Count -eq 0) 'builder parse failed'
 $assignment=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$launcher'},$true)
 $package=Join-Path $test 'package';Put (Join-Path $package 'RunFramework.ps1') $assignment.Right.Expression.Value
 Put (Join-Path $package 'tools/detached_process.ps1') '# No process creation is permitted in this fixture.'
 foreach($name in @('roomkit_entry.ps1','roomkit_status.ps1')){Put (Join-Path $package ('tools/'+$name)) ([IO.File]::ReadAllText((Join-Path $SourceRoot ('tools/'+$name))))}
 [void][IO.Directory]::CreateDirectory((Join-Path $package 'data/framework'))
 Link (Join-Path $package 'artifacts/client') $target
 Link (Join-Path $package 'run') $target
 $packageLauncher=Join-Path $package 'RunFramework.ps1'
 Check 'package stop ignores unrelated public and run' {& $packageLauncher -Operation stop;Assert ($LASTEXITCODE -eq 0) 'stop failed';Assert ([IO.File]::ReadAllText((Join-Path $package 'data/framework/operator-stop.request')) -eq 'stop') 'missing signal'}
 Check 'package status ignores unrelated public and run' {& $packageLauncher -Operation status;Assert ($LASTEXITCODE -eq 0) 'status failed'}
 Link (Join-Path $source 'data/framework/operator.json') $target
 Check 'source client does not inspect unrelated operator record' {
  $message='';try {& $launcher -Mode client -Godot (Join-Path $source 'missing-engine.exe')|Out-Null}catch{$message=$_.Exception.Message}
  Assert ($message -like 'Godot executable not found:*') ('Wrong action boundary: '+$message)
 }
 if($isWindowsHost){
  Put (Join-Path $package 'immutable.txt') 'package'
  $hash=(Get-FileHash -LiteralPath (Join-Path $package 'immutable.txt') -Algorithm SHA256).Hash
  Put (Join-Path $package 'checksums.json') (@{files=@(@{path='immutable.txt';sha256=$hash})}|ConvertTo-Json -Depth 4)
  Link (Join-Path $package 'data/framework/operator.json') $target
  Check 'package verification ignores unrelated operator record' {& $packageLauncher -Operation verify;Assert ($LASTEXITCODE -eq 0) 'verify failed'}
 } else {Write-Output 'SKIP Windows native package checksum path rule on Linux'}
 # Restore only the source descriptor link before stop-specific assertions.
 $recordLink=Join-Path $source 'data/framework/operator.json';[IO.Directory]::Delete($recordLink);[void]$links.Remove($recordLink)
 if($isWindowsHost){$recordLink=Join-Path $package 'data/framework/operator.json';[IO.Directory]::Delete($recordLink);[void]$links.Remove($recordLink)}
 Link (Join-Path $source 'data/framework/operator-stop.request') $target
 Check 'source stop rejects actual linked signal' {Reject {& $launcher -Mode stop}}
 Check 'dispatcher rejects actual linked signal' {Reject {Invoke-RoomKit $source Windows @('stop')}}
 Link (Join-Path $source 'data/instance-linked') $target
 Check 'source stop rejects linked data ancestor' {Reject {& $launcher -Mode stop -Instance linked}}
 Link (Join-Path $source 'data/instance-test-u1/instance.json') $target
 Check 'Linux status rejects linked identity record' {Reject {Invoke-RoomKit $source Linux @('status','--instance','test-u1')}}
 Remove-Item -LiteralPath (Join-Path $package 'data/framework/operator-stop.request')
 Link (Join-Path $package 'data/framework/operator-stop.request') $target
 Check 'package stop rejects actual linked signal' {Reject {& $packageLauncher -Operation stop}}
 Check 'canary unchanged and no descriptor written' {Assert ([IO.File]::ReadAllText((Join-Path $target 'keep.txt')) -eq 'unchanged') 'canary changed';Assert (@(Get-ChildItem -LiteralPath $target).Count -eq 1) 'wrote through link'}
 Write-Output ('UNIFIED_ACTION_PATHS passed='+$script:passed+' failed=0 engine=NOT-STARTED')
} finally {
 Set-Location -LiteralPath $SourceRoot
 # Remove only our recorded directory links, never recurse through them.
 foreach($link in $links){$item=Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){[IO.Directory]::Delete($link)}}
}
