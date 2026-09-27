param([int]$Clients=3,[string]$Label='run',[string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Client-perceived asset latency through a real, already running test Operator.
# Start tests/test_operator.ps1 -HoldForIntegration first (same as the full client
# test), then run this script, then create integration-done.request as usual.
# Each client registers, is funded by the administrator API, and times its own
# read/purchase/select calls (tests/perf/run_asset_e2e.gd). Headless, lobby only.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pointer=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'run/operator-test-context.json') | ConvertFrom-Json
$ctx=Get-Content -Encoding UTF8 -Raw -LiteralPath $pointer.path | ConvertFrom-Json
$builds=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $project 'artifacts/framework-games.json') | ConvertFrom-Json
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $ctx.evidence ('asset-e2e-'+$runId)
$private=Join-Path $ctx.test_root ('asset-e2e-'+$runId)
foreach($candidate in @($evidence,$private)) {
    $resolved=[IO.Path]::GetFullPath($candidate)
    if(-not $resolved.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Test directory outside project'}
    New-Item -ItemType Directory -Path $resolved -Force | Out-Null
}
$utf8=New-Object Text.UTF8Encoding($false)
function Api([string]$action,$payload=@{}) {
    $headers=@{Authorization='Bearer '+$ctx.token}
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$action;payload=$payload}|ConvertTo-Json -Depth 25 -Compress))
    return Invoke-RestMethod -Uri ($ctx.url+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 65
}
function Report($path) { if(Test-Path -LiteralPath $path){try{return Get-Content -Encoding UTF8 -Raw -LiteralPath $path|ConvertFrom-Json}catch{return $null}}; return $null }
$invitation=Api 'invite.create' @{uses=($Clients+1);expires_hours=1;reason='asset latency measurement'}
if(-not $invitation.ok){throw 'Invitation failed'}
$all=@{}
$failures=0
for($index=0;$index -lt $Clients;$index++) {
    $name='perf_'+$index
    $directory=Join-Path $evidence $name
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $report=Join-Path $directory 'report.json'
    $bootstrap=Join-Path $private ($name+'.json')
    $connection=@{url=$ctx.connection.url;ca_certificate=$ctx.connection.ca_certificate;server_hostname=$ctx.connection.server_hostname;game_id='shooter'}
    $settings=@{connection=$connection;manifest=$builds.shooter.manifest;game_id='shooter';username=('perf_'+$runId.Substring(0,8)+'_'+$index);password=('Perf!'+[Guid]::NewGuid().ToString('N'));display_name=$name;invite_code=$invitation.payload.invite_code;register=$true;report_path=$report;control_directory=$directory;timeout_ms=600000}
    [IO.File]::WriteAllText($bootstrap,($settings|ConvertTo-Json -Depth 50 -Compress),$utf8)
    $arguments=@('--headless','--path',$project,'--script','res://tests/perf/run_asset_e2e.gd','--',('--test-config='+$bootstrap))
    $quoted=foreach($argument in $arguments){'"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'console.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $null=$process.Handle
    $deadline=(Get-Date).AddSeconds(90)
    $ready=$null
    while((Get-Date) -lt $deadline -and -not $process.HasExited) {
        $r=Report $report
        if($null -ne $r -and $r.ok -and $r.user_id -ne '' -and $r.phase -eq 'LOBBY'){$ready=$r;break}
        Start-Sleep -Milliseconds 200
    }
    if($null -eq $ready){ $failures++; Write-Output ('ASSET_E2E_CLIENT_NOT_READY '+$name); if(-not $process.HasExited){$process.Kill()}; continue }
    $funded=Api 'asset.adjust' @{user_id=$ready.user_id;game_id='shooter';coins_delta=1000;xp_delta=0;operation_id=[Guid]::NewGuid().ToString('N');reason='asset latency measurement'}
    if(-not $funded.ok){ $failures++; Write-Output ('ASSET_E2E_FUNDING_FAILED '+$name) }
    [IO.File]::WriteAllText((Join-Path $directory 'funded.flag'),'1',$utf8)
    if(-not $process.WaitForExit(300000)){ $process.Kill(); $failures++; Write-Output ('ASSET_E2E_CLIENT_TIMEOUT '+$name); continue }
    if($process.ExitCode -ne 0){ $failures++; Write-Output ('ASSET_E2E_CLIENT_EXIT '+$name+' code='+$process.ExitCode) }
    $perf=Get-Content -Encoding UTF8 -Raw -LiteralPath ($report+'.perf.json') | ConvertFrom-Json
    foreach($property in $perf.samples.PSObject.Properties) {
        if(-not $all.ContainsKey($property.Name)){$all[$property.Name]=New-Object Collections.ArrayList}
        foreach($value in $property.Value){[void]$all[$property.Name].Add([double]$value)}
    }
}
$summary=[ordered]@{label=$Label;clients=$Clients;failures=$failures;evidence=$evidence;operations=[ordered]@{}}
foreach($operation in ($all.Keys | Sort-Object)) {
    $values=@($all[$operation] | Sort-Object)
    $summary.operations[$operation]=[ordered]@{count=$values.Count;min_ms=$values[0];median_ms=$values[[int][Math]::Floor($values.Count/2)];max_ms=$values[-1];samples_ms=@($all[$operation])}
    Write-Output ('ASSET_E2E {0} count={1} median={2}ms min={3}ms max={4}ms' -f $operation,$values.Count,$values[[int][Math]::Floor($values.Count/2)],$values[0],$values[-1])
}
[IO.File]::WriteAllText((Join-Path $project ('logs/asset-e2e-'+$Label+'.json')),($summary|ConvertTo-Json -Depth 10),$utf8)
Remove-Item -LiteralPath $private -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ('ASSET_E2E_RESULT clients='+$Clients+' failures='+$failures)
if($failures){exit 1}
