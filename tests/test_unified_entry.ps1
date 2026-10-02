param([string]$TestRoot)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $TestRoot){$TestRoot=Join-Path $root ('data/test-u1/fixture-'+[Guid]::NewGuid().ToString('N'))}
. (Join-Path $root 'tools/roomkit_entry.ps1')
$script:passed=0
$script:skipped=0
$windowsHost=[Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$chinese=([string][char]0x4e2d)+[char]0x6587
function Test([string]$Name,[scriptblock]$Body){& $Body; $script:passed++;Write-Output ('PASS '+$Name)}
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body){$rejected=$false;try{& $Body | Out-Null}catch{$rejected=$true};Assert $rejected 'Expected rejection'}
function File([string]$Path,[string]$Text='fixture'){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text)}
function Invoke-RoomKitDelegate([string]$File,[object[]]$Arguments,[bool]$Shell){$script:call=@{File=$File;Arguments=$Arguments;Shell=$Shell}}
function Invoke-RoomKitWindowsDelegate([string]$File,[hashtable]$Parameters){$script:call=@{File=$File;Parameters=$Parameters}}
function Dispatch([string]$Folder,[string]$Platform,[string[]]$A){$script:call=$null;Invoke-RoomKit $Folder $Platform $A | Out-Null}
$source=Join-Path $TestRoot ('source space '+$chinese)
foreach($name in @('project.godot','host/operator.gd','host/managed_host.gd','sdk/roomkit/shared/json_wire.gd','tools/build_framework.ps1','examples/framework/services.json','tools/roomkit.ps1','tools/roomkit_entry.ps1','tools/roomkit_linux.sh','tools/runtime_paths.sh','tools/prepare_environment.sh','tools/run_framework.ps1','tools/check_environment.ps1','tools/roomkit_status.ps1')){File (Join-Path $source $name)}
Test 'no args help never delegates or creates data' {Dispatch $source Linux @();Assert ($null -eq $script:call) 'delegated';Assert (-not(Test-Path (Join-Path $source 'data'))) 'data created'}
Test 'Linux default start retains delegate defaults' {Dispatch $source Linux @('start');Assert (($script:call.Arguments -join '|') -eq 'start') 'defaults changed'}
Test 'Linux exact argument forwarding' {Dispatch $source Linux @('start','--instance','test-u1','--panel-port','29191','--lobby-port','29200','--control-port','29201','--udp-range','29340-29347','--bind','127.0.0.1');Assert (($script:call.Arguments -join '|') -eq 'start|--instance|test-u1|--panel-port|29191|--lobby-port|29200|--control-port|29201|--udp-range|29340-29347|--bind|127.0.0.1') 'args changed'}
foreach($action in @('status','stop')) {Test ('Linux '+$action) {Dispatch $source Linux @($action,'--instance','test-u1');Assert (($script:call.Arguments -join '|') -eq ($action+'|--instance|test-u1')) 'wrong action'}}
Test 'check only preparation check' {Dispatch $source Linux @('check');Assert ($script:call.File -eq 'tools/prepare_environment.sh' -and $script:call.Arguments[0] -eq 'check') 'not check'}
foreach($bad in @(
 @('start','--instance','x','--instance','y'),@('start','--panel-port','29191','--panel-port','29192'),@('start','--instance','../x'),@('start','--instance','UPPER'),@('start','--instance'),@('start','--panel-port','0'),@('start','--panel-port','65536'),@('start','--panel-port','029191'),@('start','--panel-port','29200','--lobby-port','29200'),@('start','--udp-range','29000-29300'),@('start','--udp-range','29347-29340'),@('start','--panel-port','29340','--udp-range','29340-29347'),@('start','--bind','300.1.2.3'),@('start','--bind','::1'),@('status','--panel-port','29191'),@('check','--instance','x'),@('help','--instance','x'),@('start','--unknown','x'),@('start','--instance','x/../../a'),@('start','--godot','/tmp/nope'),@('oops')
)){ $label=$bad -join ' ';Test ('reject '+$label) {Reject {Get-RoomKitOptions $bad Linux}} }
Test 'unsupported OS rejected without dispatch' {Reject {Dispatch $source Other @('help')}}
Test 'empty/misleading layout rejected' {Reject {Get-RoomKitLayout $TestRoot Linux}}
Test 'Windows source defaults preserved' {Dispatch $source Windows @('start');Assert ($script:call.Parameters.Mode -eq 'panel' -and $script:call.Parameters.Instance -eq 'framework' -and $script:call.Parameters.Count -eq 2) 'default mapping'}
Test 'Windows explicit options mapped without rewriting' {Dispatch $source Windows @('start','--instance','test-u1','--panel-port','29191','--lobby-port','29200','--control-port','29201','--udp-range','29340-29347','--bind','127.0.0.1','--no-browser');$p=$script:call.Parameters;Assert ($p.Instance -eq 'test-u1' -and $p.PanelPort -eq '29191' -and $p.LobbyPort -eq '29200' -and $p.ControlPort -eq '29201' -and $p.UdpRange -eq '29340-29347' -and $p.Bind -eq '127.0.0.1' -and $p.NoBrowser) 'mapping'}
Test 'Windows stop default' {Dispatch $source Windows @('stop');Assert ($script:call.Parameters.Mode -eq 'stop' -and $script:call.Parameters.Instance -eq 'framework') 'mapping'}
Test 'Windows status read-only adapter' {Dispatch $source Windows @('status');Assert ($script:call.File.EndsWith('roomkit_status.ps1') -and $script:call.Parameters.DataRoot -eq (Join-Path $source 'data/framework')) 'mapping'}
Test 'Windows custom status same data path' {Dispatch $source Windows @('status','--instance','test-u1');Assert ($script:call.Parameters.DataRoot -eq (Join-Path $source 'data/instance-test-u1/data')) 'mapping'}
Test 'Windows check source' {Dispatch $source Windows @('check');Assert ($script:call.File.EndsWith('check_environment.ps1')) 'mapping'}
$package=Join-Path $TestRoot ('Linux package '+$chinese)
foreach($name in @('project.godot','tools/roomkit_entry.ps1','tools/roomkit.ps1','Operator.x86_64','Operator.pck','ManagedHost.x86_64','ManagedHost.pck','games.json','SHA256SUMS.txt','tools/roomkit_linux.sh','tools/runtime_paths.sh','tools/prepare_environment.sh')){File (Join-Path $package $name)}
File (Join-Path $package 'linux-package.json') '{"format":1,"engine":"4.7.2.stable.official.ed1daf0bf"}'
Test 'Linux package dispatch' {Dispatch $package Linux @('start');Assert ($script:call.File -eq 'tools/roomkit_linux.sh') 'mapping'}
Test 'Linux package rejected on Windows' {Reject {Dispatch $package Windows @('start')}}
Test 'ambiguous layout fails closed' {File (Join-Path $source 'linux-package.json') '{}';Reject {Dispatch $source Linux @('status')};Remove-Item -LiteralPath (Join-Path $source 'linux-package.json')}
$win=Join-Path $TestRoot ('Windows package '+$chinese)
foreach($name in @('project.godot','tools/roomkit_entry.ps1','tools/roomkit.ps1','tools/roomkit_status.ps1','RunFramework.ps1','Operator.exe','Operator.pck','ManagedHost.exe','ManagedHost.pck','artifacts/framework-games.json')){File (Join-Path $win $name)}
File (Join-Path $win 'checksums.json') '{"engine":"4.7.2.stable.official.ed1daf0bf","files":[{"path":"Operator.exe","sha256":"fixture"}]}'
Test 'Windows package start' {Dispatch $win Windows @('start','--instance','test-u1','--panel-port','29191');Assert ($script:call.File.EndsWith('RunFramework.ps1') -and $script:call.Parameters.Operation -eq 'panel' -and $script:call.Parameters.Instance -eq 'test-u1' -and $script:call.Parameters.PanelPort -eq '29191') 'mapping'}
Test 'Windows package check verifies manifest' {Dispatch $win Windows @('check');Assert ($script:call.Parameters.Operation -eq 'verify') 'mapping'}
Test 'Windows package rejected on Linux' {Reject {Dispatch $win Linux @('start')}}
Test 'Windows package stop delegates' {Dispatch $win Windows @('stop');Assert ($script:call.Parameters.Operation -eq 'stop') 'mapping'}
Test 'Windows package status uses adapter' {Dispatch $win Windows @('status');Assert ($script:call.File.EndsWith('roomkit_status.ps1')) 'mapping'}
# Directory junctions need no elevation on Windows; file symlinks remain a
# separately reported Linux-only case instead of silently skipping the suite.
$directoryLink=if($windowsHost){'Junction'}else{'SymbolicLink'}
Test 'linked instance rejected' {
 [void][IO.Directory]::CreateDirectory((Join-Path $source 'data'));$link=Join-Path $source 'data/instance-link'
 New-Item -ItemType $directoryLink -Path $link -Target $TestRoot | Out-Null
 try {Reject {Dispatch $source Linux @('status','--instance','link')}} finally {[IO.Directory]::Delete($link)}
}
if($windowsHost){$script:skipped++;Write-Output 'SKIP file symlink fixture: requires Linux or Windows elevation; no elevation requested'}else{
 Test 'linked nested runtime leaf rejected before stop' {
  File (Join-Path $source 'data/instance-nested/data/config.json');$link=Join-Path $source 'data/instance-nested/data/operator-stop.request'
  New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $source 'project.godot')|Out-Null
  try {Reject {Dispatch $source Linux @('stop','--instance','nested')}} finally {Remove-Item -LiteralPath $link}
 }
}
Test 'linked installation rejected' {
 $link=Join-Path $TestRoot 'root-link';New-Item -ItemType $directoryLink -Path $link -Target $source|Out-Null
 try {Reject {Dispatch $link Linux @('status')}} finally {[IO.Directory]::Delete($link)}
}
Test 'PowerShell syntax including generated Windows launcher' {
 foreach($file in @('tools/roomkit.ps1','tools/roomkit_entry.ps1','tools/roomkit_status.ps1','tools/run_framework.ps1','tools/build_framework_release.ps1','tools/build_linux_server.ps1')){
  $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$t,[ref]$e);Assert ($e.Count -eq 0) ($file+': '+($e|Out-String))
  if($file -eq 'tools/build_framework_release.ps1'){$assignment=$ast.Find({param($a)$a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -eq '$launcher'},$true);$launcher=$assignment.Right.Expression.Value;[void][Management.Automation.Language.Parser]::ParseInput($launcher,[ref]$t,[ref]$e);Assert ($e.Count -eq 0) 'generated launcher syntax';File (Join-Path $TestRoot 'RunFramework.generated.ps1') $launcher}
 }
}
Set-Location -LiteralPath $root
Write-Output ('UNIFIED_ENTRY_TESTS passed='+$script:passed+' failed=0 skipped='+$script:skipped+' Windows=fixtures-only')
