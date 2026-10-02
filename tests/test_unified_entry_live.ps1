# One native Windows management-service cycle; explicit fresh test instance only.
param(
 [string]$TargetRoot='',
 [ValidatePattern('^test-u1-[a-z0-9-]+$')][string]$Instance=('test-u1-'+[Guid]::NewGuid().ToString('N').Substring(0,8)),
 [int]$PanelPort=36191,[int]$LobbyPort=36200,[int]$ControlPort=36201,
 [int]$UdpFirst=36340,[int]$UdpLast=36347
)
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Windows live check only'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not $TargetRoot){$TargetRoot=$repo}
$target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\','/')
if($target -ne $repo -and -not $target.StartsWith($repo+'\artifacts\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target must be this isolated checkout or one of its artifact packages'}
. (Join-Path $repo 'tools/roomkit_entry.ps1')
Assert-RoomKitPath $target
$instanceRoot=Join-Path $target ('data/instance-'+$Instance)
if(Test-Path -LiteralPath $instanceRoot){throw 'Test instance already exists'}
foreach($p in @($PanelPort,$LobbyPort,$ControlPort,$UdpFirst,$UdpLast)){if($p -lt 30000 -or $p -gt 60000){throw 'Test ports must stay in 30000..60000'}}
if($UdpLast -lt $UdpFirst -or $UdpLast-$UdpFirst -gt 16){throw 'Invalid test UDP range'}
$held=New-Object 'System.Collections.Generic.List[System.Net.Sockets.Socket]'
try {
 foreach($p in @($PanelPort,$LobbyPort,$ControlPort)){$s=New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Stream,[Net.Sockets.ProtocolType]::Tcp);$held.Add($s);$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$p)))}
 for($p=$UdpFirst;$p -le $UdpLast;$p++){$s=New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp);$held.Add($s);$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Loopback,$p)))}
} finally {foreach($s in $held){$s.Dispose()}}
$log=Join-Path $repo ('logs/u1-review/live-'+$Instance)
[void][IO.Directory]::CreateDirectory($log)
$entry=Join-Path $target 'RoomKit.cmd'
$descriptor=Join-Path $instanceRoot 'data/operator.json'
$passed=0
function Check($Condition,$Label){if(-not $Condition){throw $Label};$script:passed++;Write-Output ('PASS '+$Label)}
function Call($Name,[string[]]$Arguments){
 $output=& $entry @Arguments 2>&1;$code=$LASTEXITCODE
 [IO.File]::WriteAllText((Join-Path $log ($Name+'.txt')),($output -join "`r`n"))
 return @{Code=$code;Text=($output -join "`n")}
}
$stopConfirmed=$false
$oldLocation=(Get-Location).Path
try {
 Set-Location -LiteralPath $env:TEMP
 $r=Call before @('status','--instance',$Instance)
 Check ($r.Code -eq 0 -and $r.Text.Contains('ROOMKIT_NOT_RUNNING')) 'fresh status is read-only and not running'
 Check (-not(Test-Path -LiteralPath $instanceRoot)) 'status creates no instance'
 $r=Call start @('start','--instance',$Instance,'--panel-port',"$PanelPort",'--lobby-port',"$LobbyPort",'--control-port',"$ControlPort",'--udp-range',"$UdpFirst-$UdpLast",'--bind','127.0.0.1','--no-browser')
 Check ($r.Code -eq 0 -and (Test-Path -LiteralPath $descriptor)) 'native entry starts the selected isolated instance'
 $record=Get-Content -LiteralPath $descriptor -Raw -Encoding UTF8|ConvertFrom-Json
 Check ([int]$record.port -eq $PanelPort) 'descriptor uses explicit panel port'
 $url='http://127.0.0.1:'+$PanelPort+'/api'
 [Net.ServicePointManager]::Expect100Continue=$false
 $reply=Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body '{"action":"setup.status","payload":{}}' -TimeoutSec 10
 Check ($reply.ok -eq $true) 'real management API responds'
 $r=Call during @('status','--instance',$Instance)
 Check ($r.Code -eq 3 -and $r.Text.Contains('ROOMKIT_UNKNOWN')) 'legacy identity remains explicitly unknown'
 $r=Call stop @('stop','--instance',$Instance)
 Check ($r.Code -eq 0) 'stop command succeeds'
 $deadline=[DateTime]::UtcNow.AddSeconds(90)
 while((Test-Path -LiteralPath $descriptor) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
 Check (-not(Test-Path -LiteralPath $descriptor)) 'operator confirms normal shutdown'
 $stopConfirmed=$true
 $r=Call after @('status','--instance',$Instance)
 Check ($r.Code -eq 0 -and $r.Text.Contains('ROOMKIT_NOT_RUNNING')) 'final status is not running'
 $processes=@(Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%' OR Name='Operator.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object {$_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($instanceRoot)})
 Check ($processes.Count -eq 0) 'no process remains for this instance'
 Check (@(Get-NetTCPConnection -State Listen -LocalPort $PanelPort -ErrorAction SilentlyContinue).Count -eq 0) 'panel listener released'
 Write-Output ('UNIFIED_LIVE passed='+$passed+' failed=0 instance='+$Instance+' data='+$instanceRoot)
} finally {
 if(-not $stopConfirmed -and (Test-Path -LiteralPath $descriptor)){[void](Call cleanup @('stop','--instance',$Instance))}
 Set-Location -LiteralPath $oldLocation
}
