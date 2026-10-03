param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',[switch]$CheckOnly,[switch]$CapacityOnly,[switch]$Dtls,[switch]$FixedPollOrder)
# One real loopback ENet process, with one server and eight independent
# SceneMultiplayer subtrees. -Dtls performs real DTLS setup and handshakes.
# No storage, host service, accounts, exported client or public-network fixture.
# -FixedPollOrder is a diagnostic control for shared-process decoder starvation.
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw 'Run this driver with pwsh 7.'}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$evidenceRoot=Join-Path $project 'logs/shooter-snapshot-nettest/runs'
$run=Join-Path $evidenceRoot ('snapshot-network-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
foreach($relative in @('','logs','logs/shooter-snapshot-nettest','logs/shooter-snapshot-nettest/runs')){
    $path=if($relative){Join-Path $project $relative}else{$project}
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Isolated project/evidence must not be a link.'}
}
if(Test-Path -LiteralPath $run){throw 'Fresh isolated run directory required.'}
[void][IO.Directory]::CreateDirectory($run)
$environment=@{HOME='home';USERPROFILE='home';APPDATA='appdata';LOCALAPPDATA='localappdata';XDG_CONFIG_HOME='xdg/config';XDG_CACHE_HOME='xdg/cache';XDG_DATA_HOME='xdg/data';XDG_STATE_HOME='xdg/state';XDG_RUNTIME_DIR='xdg/runtime';TMP='tmp';TEMP='tmp';TMPDIR='tmp'}
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
if($CapacityOnly){[void]$info.ArgumentList.Add('--capacity-only')}
if($Dtls){[void]$info.ArgumentList.Add('--dtls')}
if($FixedPollOrder){[void]$info.ArgumentList.Add('--fixed-poll-order')}
$sources=@{}
foreach($relative in @('tests/run_shooter_snapshot_network.gd','tests/test_shooter_snapshot_network.ps1','tests/support/linux_snapshot_network.sh','sdk/roomkit/shared/secure_transport.gd','examples/shooter/game.gd','examples/shooter/snapshot_codec.gd','examples/shooter/snapshot_sender.gd')){
    $path=Join-Path $project $relative
    $sources[$relative]=if(Test-Path -LiteralPath $path){(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash}else{'MISSING'}
}
[IO.File]::WriteAllText((Join-Path $run 'source-hashes.json'),($sources|ConvertTo-Json -Depth 5))
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
        $groups=if($CapacityOnly){@('eight_players','maximal_legal')}else{@('eight_players','maximal_legal','fault_recovery','slow_scheduler_recovery')}
        $valid=$saved.failed -eq 0 -and $saved.clients -eq 8 -and $saved.period_ms -eq 50 -and $saved.terminal_timeout_ms -eq 5000 -and [bool]$saved.capacity_only -eq [bool]$CapacityOnly
        $transport=if($Dtls){'loopback ENet DTLS'}else{'loopback ENet, no DTLS'}
        $valid=$valid -and $saved.dtls -is [bool] -and $saved.dtls -eq [bool]$Dtls -and $saved.transport -ceq $transport
        $valid=$valid -and $saved.fixed_poll_order -is [bool] -and $saved.fixed_poll_order -eq [bool]$FixedPollOrder -and $saved.server_relay -eq $false
        if($Dtls){
            $security=$saved.dtls_evidence
            $valid=$valid -and $null -ne $security.server_setup -and $security.server_setup -eq 0 -and $security.certificate_sha256 -cmatch '^[0-9a-f]{64}$'
            $valid=$valid -and @($security.client_setup).Count -eq 8 -and (@($security.client_setup.client|Sort-Object -Unique) -join ',') -eq '0,1,2,3,4,5,6,7'
            foreach($row in $security.client_setup){$valid=$valid -and $null -ne $row.code -and $row.code -eq 0}
            $valid=$valid -and @($security.handshakes).Count -eq 8 -and (@($security.handshakes.client|Sort-Object -Unique) -join ',') -eq '0,1,2,3,4,5,6,7'
            $valid=$valid -and @($security.handshakes.peer_id|Sort-Object -Unique).Count -eq 8
            foreach($row in $security.handshakes){$valid=$valid -and $row.peer_id -gt 1 -and $row.status -eq 2 -and $row.authority_observed -eq $true -and $row.observed_after_ms -ge 0 -and $row.observed_after_ms -lt 5000}
        }else{
            $valid=$valid -and $null -eq $saved.dtls_evidence.server_setup -and @($saved.dtls_evidence.client_setup).Count -eq 0 -and @($saved.dtls_evidence.handshakes).Count -eq 0
        }
        $valid=$valid -and @($saved.observed).Count -eq $groups.Count -and @($saved.reception).Count -eq (8*$groups.Count)
        $valid=$valid -and @($saved.checks|Where-Object {-not $_.ok}).Count -eq 0 -and @($saved.checks|Where-Object {$_.ok}).Count -eq $saved.passed
        $valid=$valid -and @($saved.process_reception).Count -eq 8 -and (@($saved.process_reception.client|Sort-Object -Unique) -join ',') -eq '0,1,2,3,4,5,6,7'
        foreach($row in $saved.process_reception){$valid=$valid -and $row.valid -and @($row.ticks).Count -ge 2}
        foreach($group in $groups){
            $summary=@($saved.observed|Where-Object {$_.group -eq $group})
            $rows=@($saved.reception|Where-Object {$_.group -eq $group})
            $valid=$valid -and $summary.Count -eq 1 -and $rows.Count -eq 8 -and (@($rows.client|Sort-Object -Unique) -join ',') -eq '0,1,2,3,4,5,6,7'
            foreach($row in $rows){
                $valid=$valid -and $row.valid -and $row.complete -and @($row.serials).Count -gt 0 -and @($row.identity_set).Count -eq $summary[0].players
                for($index=1;$index -lt @($row.ticks).Count;$index++){$valid=$valid -and $row.ticks[$index] -gt $row.ticks[$index-1]}
                for($index=1;$index -lt @($row.serials).Count;$index++){$valid=$valid -and $row.serials[$index] -gt $row.serials[$index-1]}
                if($group -eq 'eight_players'){
                    $expectedIds=@(0..7|ForEach-Object {'net-player-{0:00}' -f $_})
                    $valid=$valid -and (@($row.identity_set) -join ',') -eq ($expectedIds -join ',') -and @($row.windows).Count -eq 3 -and @($row.windows|Where-Object {-not $_}).Count -eq 0
                }
            }
        }
        $ordinary=@($saved.observed|Where-Object {$_.group -eq 'eight_players'})[0]
        $large=@($saved.observed|Where-Object {$_.group -eq 'maximal_legal'})[0]
        $valid=$valid -and $ordinary.duration_ms -ge 3000 -and $ordinary.published -ge 40 -and $large.duration_ms -ge 5000 -and $large.published -ge 50
        $valid=$valid -and $large.players -eq 16 -and $large.shots -eq 192 -and $large.last_results -eq 256 -and $large.codec_fragments -ge 87 -and $large.max_rpc_payload_bytes -le 1000
        $valid=$valid -and @($large.sustained_complete_frames).Count -eq 8 -and @($large.sustained_complete_frames|Where-Object {$_ -lt 1}).Count -eq 0
        if(-not $CapacityOnly){
            $recovery=@($saved.observed|Where-Object {$_.group -eq 'fault_recovery'})[0]
            $slow=@($saved.observed|Where-Object {$_.group -eq 'slow_scheduler_recovery'})[0]
            $valid=$valid -and @($recovery.saw_partial).Count -eq 8 -and @($recovery.saw_partial|Where-Object {-not $_}).Count -eq 0 -and $slow.flush_pause_ms -ge 600 -and $slow.active_fragments_before_pause -ge 87
        }
    }
    if(-not $valid -and $code -eq 0){$code=1}
    $dtlsResult=if(-not $Dtls){'NOTRUN'}elseif($CheckOnly){'NOTRUN_CHECK_ONLY'}elseif($valid){'PASSED'}else{'FAILED'}
    [IO.File]::WriteAllText((Join-Path $run 'driver-result.json'),(ConvertTo-Json -InputObject @{exit=$code;engine_exit=$process.ExitCode;stderr_bytes=(Get-Item -LiteralPath (Join-Path $run 'stderr.log')).Length;source=$project;evidence=$run;engine=$Godot;passed=$valid;check_only=[bool]$CheckOnly;capacity_only=[bool]$CapacityOnly;fixed_poll_order=[bool]$FixedPollOrder;source_hashes=$sources;dtls_requested=[bool]$Dtls;dtls=$dtlsResult} -Depth 5))
}finally{
    if($null -ne $process){$process.Dispose()}
}
Write-Output ('SHOOTER_SNAPSHOT_NETWORK_DRIVER exit='+$code+' evidence='+$run)
exit $code
