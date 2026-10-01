param([string]$Root='')
# Immutable delivery check only; no engine/service invocation or installation.
$ErrorActionPreference='Stop'
if($Root -eq ''){$Root=$PSScriptRoot}
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
function SafePath([string]$Relative){
    if($Relative -eq '' -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Invalid deployment file path.'}
    $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if(-not $full.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment file is outside its directory.'}
    $cursor=$full
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked deployment path.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    return $full
}
$manifestPath=SafePath 'deployment.json'
$m=Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw|ConvertFrom-Json
if($m.format -ne 1 -or $m.server.platform -notin @('linux-x86_64','windows-x86_64') -or $m.client.platform -ne 'windows-x86_64'){throw 'Unsupported deployment format or platform.'}
$seen=@{}
foreach($file in $m.files){
    if($seen.ContainsKey([string]$file.path)){throw 'Duplicate file in deployment manifest.'};$seen[[string]$file.path]=$true
    $path=SafePath ([string]$file.path)
    if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$file.sha256){throw ('Deployment checksum mismatch: '+$file.path)}
}
foreach($descriptor in @(@{base=$m.server.path;value=$m.server.identity},@{base=$m.server.path;value=$m.server.checksums},@{base=$m.client.path;value=$m.client.manifest})){
    $path=SafePath ($descriptor.base+'/'+$descriptor.value.path)
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$descriptor.value.sha256){throw 'Deployment identity checksum mismatch.'}
}
$client=Get-Content -LiteralPath (SafePath ($m.client.path+'/'+$m.client.manifest.path)) -Encoding UTF8 -Raw|ConvertFrom-Json
$serverIndex=Get-Content -LiteralPath (SafePath ($m.server.path+'/'+$m.server.identity.path)) -Encoding UTF8 -Raw|ConvertFrom-Json
foreach($game in @('shooter','turns')){
    if($m.server.platform -eq 'linux-x86_64'){
        if([string]$serverIndex.games.$game -ne [string]$m.server.games.$game.build_id){throw 'Actual Linux server identity differs from deployment pairing.'}
    }else{
        foreach($field in @('game_id','build_id','compatibility_id','game_protocol')){if([string]$serverIndex.$game.manifest.$field -ne [string]$m.server.games.$game.$field){throw 'Actual Windows server identity differs from deployment pairing.'}}
    }
}
$native=if($m.server.platform -eq 'linux-x86_64'){'x86_64'}else{'exe'}
$required=@(($m.server.path+'/Operator.'+$native),($m.server.path+'/Operator.pck'),($m.server.path+'/ManagedHost.'+$native),($m.server.path+'/ManagedHost.pck'),($m.client.path+'/Client.exe'),($m.client.path+'/Client.pck'))
foreach($relative in $required){if(-not $seen.ContainsKey($relative)){throw ('Deployment omits a required runtime file: '+$relative)}}
foreach($file in $client.files){
    $relative=$m.client.path+'/'+$file.path
    $path=SafePath $relative
    if(-not $seen.ContainsKey($relative) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine [string]$file.sha256){throw 'Player executable/pack is missing from verified delivery files.'}
}
foreach($field in @('game_id','build_id','compatibility_id','game_protocol')){if([string]$client.$field -ne [string]$m.server.games.shooter.$field -or [string]$client.$field -ne [string]$m.client.games.shooter.$field){throw ('Deployment server/client mismatch: '+$field)}}
if(@($m.files).Count -lt 1){throw 'Deployment manifest has no files.'}
Write-Output ('DEPLOYMENT_VALID files='+@($m.files).Count+' platform='+$m.server.platform+' shooter='+$client.build_id)
