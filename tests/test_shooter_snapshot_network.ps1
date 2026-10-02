param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',[switch]$CheckOnly)
# One real Windows loopback ENet process, with one server and eight independent
# SceneMultiplayer subtrees. No storage, host service, account or DTLS fixture.
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw 'Run this driver with pwsh 7.'}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$run=Join-Path $project ('data/snapshot-network-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
foreach($path in @($project,(Join-Path $project 'data'))){
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Isolated project/data must not be a link.'}
}
if(Test-Path -LiteralPath $run){throw 'Fresh isolated run directory required.'}
[void][IO.Directory]::CreateDirectory($run)
$environment=@{HOME='home';USERPROFILE='home';APPDATA='appdata';LOCALAPPDATA='localappdata';XDG_CONFIG_HOME='xdg/config';XDG_CACHE_HOME='xdg/cache';XDG_DATA_HOME='xdg/data';TMP='tmp';TEMP='tmp';TMPDIR='tmp'}
foreach($folder in @($environment.Values | Select-Object -Unique)){[void][IO.Directory]::CreateDirectory((Join-Path $run $folder))}
$info=[Diagnostics.ProcessStartInfo]::new($Godot)
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.WorkingDirectory=$run
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
foreach($key in $environment.Keys){$info.Environment[$key]=Join-Path $run $environment[$key]}
$report=Join-Path $run 'result.json'
foreach($arg in @('--headless','--path',$project,'--log-file',(Join-Path $run 'engine.log'),'--script','res://tests/run_shooter_snapshot_network.gd','--',('--evidence='+$report))){[void]$info.ArgumentList.Add($arg)}
if($CheckOnly){$info.ArgumentList.Insert(0,'--check-only')}
$process=$null
$code=1
$ownedStart=$null
try{
    $process=[Diagnostics.Process]::Start($info)
    $ownedStart=$process.StartTime.ToUniversalTime().Ticks
    $stdout=$process.StandardOutput.ReadToEndAsync()
    $stderr=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(45000)){
        if($process.StartTime.ToUniversalTime().Ticks -ne $ownedStart){throw 'Owned process identity changed; no signal sent.'}
        $process.Kill()
        [void]$process.WaitForExit(5000)
        $code=124
    }else{$code=$process.ExitCode}
    [IO.File]::WriteAllText((Join-Path $run 'stdout.log'),$stdout.Result)
    [IO.File]::WriteAllText((Join-Path $run 'stderr.log'),$stderr.Result)
    Write-Output $stdout.Result
    if($stderr.Result){Write-Output $stderr.Result}
    $valid=$code -eq 0 -and $stderr.Result.Length -eq 0
    if(-not $CheckOnly){$valid=$valid -and $stdout.Result -match 'SHOOTER_SNAPSHOT_NETWORK_RESULT passed=\d+ failed=0' -and (Test-Path -LiteralPath $report)}
    if($valid -and -not $CheckOnly){
        $saved=Get-Content -Encoding UTF8 -Raw -LiteralPath $report | ConvertFrom-Json
        $valid=$saved.failed -eq 0 -and $saved.clients -eq 8 -and @($saved.observed).Count -eq 7
    }
    if(-not $valid -and $code -eq 0){$code=1}
    [IO.File]::WriteAllText((Join-Path $run 'driver-result.json'),(ConvertTo-Json -InputObject @{exit=$code;engine_exit=$process.ExitCode;stderr_bytes=(Get-Item -LiteralPath (Join-Path $run 'stderr.log')).Length;source=$project;evidence=$run;engine=$Godot;passed=$valid;check_only=[bool]$CheckOnly;dtls='NOTRUN'} -Depth 5))
}finally{
    if($null -ne $process){$process.Dispose()}
}
Write-Output ('SHOOTER_SNAPSHOT_NETWORK_DRIVER exit='+$code+' evidence='+$run)
exit $code
