param([string]$DeploymentDirectory='', [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# No service runs here. Real exports are checked separately from admission tests.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$run=Join-Path $project ('artifacts/deployment-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($run)
$passed=0;$failed=0
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++;Write-Output ('PASS '+$Name)}else{$script:failed++;Write-Output ('FAIL '+$Name)}}
function InvokeTool([string]$Name,[string[]]$Arguments){
    $ErrorActionPreference='Continue'
    $output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project ('tools/'+$Name)) @Arguments 2>&1|ForEach-Object {[string]$_})
    $code=$LASTEXITCODE
    return @{code=$code;text=($output -join "`n")}
}
if($DeploymentDirectory -eq ''){
    $DeploymentDirectory=Join-Path $run 'linux'
    $r=InvokeTool 'prepare_deployment.ps1' @('-ServerPlatform','Linux','-Godot',$Godot,'-OutputDirectory',$DeploymentDirectory)
    $r.text|Set-Content -LiteralPath (Join-Path $run 'build.log') -Encoding UTF8
    Check ($r.code -eq 0 -and $r.text -match 'DEPLOYMENT_READY') 'real Linux server and Windows player export'
}
$DeploymentDirectory=[IO.Path]::GetFullPath($DeploymentDirectory)
if(-not $DeploymentDirectory.StartsWith($project+'\artifacts\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment tests only accept this worktree artifacts output.'}
if(Test-Path -LiteralPath (Join-Path $DeploymentDirectory 'Server/data')){throw 'Deployment tests refuse a server directory that has been run.'}
for($cursor=$DeploymentDirectory;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Deployment tests refuse linked directories.'}}
$r=InvokeTool 'check_deployment.ps1' @('-Root',$DeploymentDirectory)
Check ($r.code -eq 0 -and $r.text -match 'DEPLOYMENT_VALID') 'all immutable hashes and game pairing'
$manifest=Get-Content -LiteralPath (Join-Path $DeploymentDirectory 'deployment.json') -Encoding UTF8 -Raw|ConvertFrom-Json
$client=Join-Path $DeploymentDirectory $manifest.client.path
Check (-not(Test-Path -LiteralPath (Join-Path $client 'connection.json')) -and -not(Test-Path -LiteralPath (Join-Path $client 'server.crt'))) 'fresh player has no invented connection or certificate'
Check ([IO.File]::ReadAllText((Join-Path $client 'README.md')) -match 'server not configured yet') 'player instructions clearly require actual target public configuration'
Check ((Test-Path -LiteralPath (Join-Path $client 'Client.exe')) -and (Test-Path -LiteralPath (Join-Path $client 'SetServer.cmd')) -and (Test-Path -LiteralPath (Join-Path $client 'CheckClient.cmd'))) 'player is a complete ordinary Windows folder'
$r=InvokeTool 'prepare_deployment.ps1' @('-OutputDirectory',$DeploymentDirectory)
Check ($r.code -ne 0 -and $r.text -match 'already exists') 'existing delivery refused before export'
$outside=Join-Path $project ('data/deployment-test-denied-'+[Guid]::NewGuid().ToString('N'))
$r=InvokeTool 'prepare_deployment.ps1' @('-OutputDirectory',$outside)
Check ($r.code -ne 0 -and $r.text -match 'inside this project artifacts' -and -not(Test-Path -LiteralPath $outside)) 'outside artifacts refused with no writes'
$missing=Join-Path $run 'no-engine'
$r=InvokeTool 'prepare_deployment.ps1' @('-Godot',(Join-Path $run 'missing.exe'),'-OutputDirectory',$missing)
Check ($r.code -ne 0 -and -not(Test-Path -LiteralPath $missing)) 'missing editor refused before output creation'
$r=InvokeTool 'prepare_deployment.ps1' @('-ServerPlatform','ARM','-OutputDirectory',(Join-Path $run 'arm'))
Check ($r.code -ne 0 -and -not(Test-Path -LiteralPath (Join-Path $run 'arm'))) 'unsupported server platform refused'
$r=InvokeTool 'check_deployment.ps1' @('-Root',(Join-Path $run 'missing'))
Check ($r.code -ne 0) 'missing deployment refused'
$link=Join-Path $run 'linked-output';$real=Join-Path $run 'real-output'
[void][IO.Directory]::CreateDirectory($real)
try{
    New-Item -ItemType Junction -Path $link -Target $real|Out-Null
    $linkedOutput=Join-Path $link 'deployment'
    $r=InvokeTool 'prepare_deployment.ps1' @('-OutputDirectory',$linkedOutput)
    Check ($r.code -ne 0 -and $r.text -match 'linked deployment output' -and -not(Test-Path -LiteralPath (Join-Path $real 'deployment'))) 'linked output refused without changing target'
}finally{if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}}
$link=Join-Path $run 'linked-delivery'
try{
    New-Item -ItemType Junction -Path $link -Target $DeploymentDirectory|Out-Null
    $r=InvokeTool 'check_deployment.ps1' @('-Root',$link)
    Check ($r.code -ne 0 -and $r.text -match 'linked deployment path') 'linked delivery rejected by checksum entry'
}finally{if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}}
# Tamper a small player helper in the newly generated test-owned directory only.
$helper=Join-Path $client 'CheckClient.cmd'
$original=[IO.File]::ReadAllBytes($helper)
try{
    [IO.File]::AppendAllText($helper,"`r`nrem TEST_TAMPER`r`n")
    $r=InvokeTool 'check_deployment.ps1' @('-Root',$DeploymentDirectory)
    Check ($r.code -ne 0 -and $r.text -match 'checksum mismatch') 'changed player file refused'
}finally{[IO.File]::WriteAllBytes($helper,$original)}
$manifestPath=Join-Path $DeploymentDirectory 'deployment.json'
$original=[IO.File]::ReadAllBytes($manifestPath)
try{
    $bad=Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw|ConvertFrom-Json
    $bad.server.games.shooter.build_id+='-mismatch'
    [IO.File]::WriteAllText($manifestPath,($bad|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
    $r=InvokeTool 'check_deployment.ps1' @('-Root',$DeploymentDirectory)
    Check ($r.code -ne 0 -and $r.text -match 'server/client mismatch|server identity differs') 'inconsistent server and player build refused'
    $bad=Get-Content -LiteralPath (Join-Path $DeploymentDirectory 'deployment.json') -Encoding UTF8 -Raw|ConvertFrom-Json
    $bad.files[0].path='../README.md'
    [IO.File]::WriteAllText($manifestPath,($bad|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
    $r=InvokeTool 'check_deployment.ps1' @('-Root',$DeploymentDirectory)
    Check ($r.code -ne 0 -and $r.text -match 'Invalid deployment file path') 'manifest path traversal refused'
}finally{[IO.File]::WriteAllBytes($manifestPath,$original)}
$r=InvokeTool 'check_deployment.ps1' @('-Root',$DeploymentDirectory)
Check ($r.code -eq 0) 'test tampering restored byte-for-byte'
Write-Output ('DEPLOYMENT_PAIR_TEST_RESULT passed='+$passed+' failed='+$failed+' evidence='+$run)
if($failed){exit 1}
exit 0
