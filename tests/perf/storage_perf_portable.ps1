param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Work,
    [ValidateRange(1,10)][int]$Rounds=3,
    [int]$Reads=200,
    [int]$Commits=100,
    [int]$Sessions=200
)
# Repeated cost measurement of option P (the production PowerShell storage
# helpers of $Source) on new fake data. Same script for Windows PowerShell 5.1
# and PowerShell 7 on Linux. Each round separates:
#   shell start, binding compile, PBKDF2, one-shot helper calls, resident worker
#   first reply, warm p50/p95, and memory sampled while BOTH workers are alive.
# Memory metrics are not equivalent across systems: Linux reports RSS, PSS and
# private pages from /proc/<pid>/smaps_rollup; Windows reports working set and
# private bytes. A metric that cannot be read is printed as "unavailable".
$ErrorActionPreference='Stop'
$Source=[IO.Path]::GetFullPath($Source); $Work=[IO.Path]::GetFullPath($Work)
if(Test-Path -LiteralPath $Work) { if(@(Get-ChildItem -LiteralPath $Work -Force).Count) { throw 'Work directory must be empty.' } } else { [void][IO.Directory]::CreateDirectory($Work) }
$windows=[IO.Path]::DirectorySeparatorChar -eq '\'
$tools=[IO.Path]::Combine($Source,'tools')
$shell=(Get-Process -Id $PID).Path
$utf8=New-Object Text.UTF8Encoding($false)
$keepText=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
function FromJson([string]$Text) { if($keepText) { return ConvertFrom-Json -InputObject $Text -DateKind String }; return ConvertFrom-Json -InputObject $Text }
$script:problems=0
function Quote($values) { foreach($value in $values){ '"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
function StartShell([string[]]$Arguments) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$shell
    $prefix=@('-NoProfile','-NonInteractive'); if($windows) { $prefix+=@('-ExecutionPolicy','Bypass') }
    $info.Arguments=(Quote ($prefix+$Arguments)) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    if($windows) { try { [Console]::InputEncoding=$utf8 } catch {} }
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info; [void]$process.Start()
    return $process
}
function Timed([string[]]$Arguments,[string]$InputLine='') {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $process=StartShell $Arguments
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if($InputLine) { $process.StandardInput.WriteLine($InputLine) }
        $process.StandardInput.Close()
        if(-not $process.WaitForExit(180000)) { $process.Kill(); $script:problems++; return @{ms=-1;text=''} }
        $watch.Stop()
        return @{ms=[int]$watch.ElapsedMilliseconds;text=$stdout.Result.Trim()}
    } finally { $process.Dispose() }
}
function Line($Request) { return [Convert]::ToBase64String($utf8.GetBytes((ConvertTo-Json -InputObject $Request -Compress -Depth 8))) }
function OneShot([string]$Helper,[string]$Database,$Request) {
    $r=Timed @('-File',[IO.Path]::Combine($tools,$Helper),'-Database',$Database) (Line $Request)
    $reply=if($r.text.StartsWith('{')) { FromJson $r.text } else { $null }
    if(-not $reply -or $reply.ok -ne $true) { $script:problems++ }
    return @{ms=$r.ms;reply=$reply}
}
function Percentile([double[]]$Values,[double]$Fraction) { if(-not $Values.Count) { return -1 }; $sorted=@($Values | Sort-Object); return [math]::Round($sorted[[math]::Min($sorted.Count-1,[int][math]::Ceiling($sorted.Count*$Fraction)-1)],1) }
function Memory([Diagnostics.Process]$Process) {
    $Process.Refresh()
    if($windows) { return ('working_set_mb='+[math]::Round($Process.WorkingSet64/1MB,1)+' private_mb='+[math]::Round($Process.PrivateMemorySize64/1MB,1)) }
    $path='/proc/'+$Process.Id+'/smaps_rollup'
    try {
        $values=@{}
        foreach($row in [IO.File]::ReadAllLines($path)) { if($row -match '^(Rss|Pss|Private_Clean|Private_Dirty):\s+(\d+) kB') { $values[$Matches[1]]=[double]$Matches[2] } }
        return ('rss_mb='+[math]::Round($values['Rss']/1024,1)+' pss_mb='+[math]::Round($values['Pss']/1024,1)+' private_mb='+[math]::Round(($values['Private_Clean']+$values['Private_Dirty'])/1024,1))
    } catch { return 'memory=unavailable' }
}
function Load { if($windows) { try { return 'cpu_load_percent='+((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average) } catch { return 'load=unavailable' } }; try { return 'loadavg='+(([IO.File]::ReadAllText('/proc/loadavg') -split ' ')[0..2] -join '/') } catch { return 'load=unavailable' } }

# ---- fake data ----
$data=[IO.Path]::Combine($Work,'data'); [void][IO.Directory]::CreateDirectory($data)
$accountsDb=[IO.Path]::Combine($data,'accounts.sqlite'); $assetsDb=[IO.Path]::Combine($data,'assets.sqlite')
$password='Perf-Test-Pass-01'
[void](OneShot 'account_store.ps1' $accountsDb @{op='init'})
[void](OneShot 'account_store.ps1' $accountsDb @{op='setup.admin';username='perf_admin';password=$password;display_name='perf'})
[void](OneShot 'sqlite_store.ps1' $assetsDb @{op='init'})
function Body([int]$Revision,[int]$Credits) { return (ConvertTo-Json -Compress -Depth 5 -InputObject ([ordered]@{revision=$Revision;credits=$Credits;experience=0;owned=@('rifle');profiles=@{shooter=@{primary='rifle'}}})) }
function CommitRequest([int]$Expected) { return [ordered]@{op='asset.commit';user_id='user_perf';space_id='shooter';request_id=('req_'+$Expected);fingerprint=('fp_'+$Expected);expected_revision=$Expected;body=(Body ($Expected+1) (100000-$Expected));actor_id='admin:perf';command='{}'} }
[void](OneShot 'sqlite_store.ps1' $assetsDb (CommitRequest 0))
$revision=1
$probe=[IO.Path]::Combine($Work,'compile_probe.ps1')
[IO.File]::WriteAllText($probe,@'
param([string]$Tools)
$watch=[Diagnostics.Stopwatch]::StartNew()
$source=[IO.File]::ReadAllText([IO.Path]::Combine($Tools,'sqlite_store.ps1'))
Add-Type -TypeDefinition ([regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value)
$sqlite=$watch.ElapsedMilliseconds
$account=[IO.File]::ReadAllText([IO.Path]::Combine($Tools,'account_store.ps1'))
$block=[regex]::Matches($account,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@") | Where-Object { $_.Groups[1].Value.Contains('RoomKitPasswords') } | Select-Object -First 1
Add-Type -TypeDefinition $block.Groups[1].Value
$both=$watch.ElapsedMilliseconds
$watch.Restart()
[void][RoomKitPasswords]::Derive('Perf-Test-Pass-01','AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',600000)
Write-Output ('compile_sqlite_ms='+$sqlite+' compile_both_ms='+$both+' pbkdf2_600000_ms='+$watch.ElapsedMilliseconds)
'@,$utf8)
Write-Output ('INFO platform='+[Environment]::OSVersion.Platform+' ps='+$PSVersionTable.PSVersion+' runtime='+[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription+' rounds='+$Rounds)

for($round=1;$round -le $Rounds;$round++) {
    Write-Output ('ROUND '+$round+' load_before '+(Load))
    $bare=Timed @('-Command','exit')
    $compile=Timed @('-File',$probe,'-Tools',$tools)
    Write-Output ('ROUND '+$round+' shell_start_ms='+$bare.ms+' compile_probe_total_ms='+$compile.ms+' '+$compile.text)
    $read=OneShot 'sqlite_store.ps1' $assetsDb @{op='asset.read';user_id='user_perf';space_id='shooter'}
    $commit=OneShot 'sqlite_store.ps1' $assetsDb (CommitRequest $revision); $revision++
    $login=OneShot 'account_store.ps1' $accountsDb @{op='account.login';username='perf_admin';password=$password;client_ip='192.0.2.20'}
    $token=[string]$login.reply.token
    $check=OneShot 'account_store.ps1' $accountsDb @{op='session.authenticate';token=$token}
    Write-Output ('ROUND '+$round+' oneshot_ms asset_read='+$read.ms+' asset_commit='+$commit.ms+' session_authenticate='+$check.ms+' login_with_pbkdf2='+$login.ms)

    # Both resident workers alive at the same time.
    $assetWorker=StartShell @('-File',[IO.Path]::Combine($tools,'storage_worker.ps1'),'-Helper','sqlite_store.ps1','-Database',$assetsDb,'-IdleSeconds','120')
    $accountWorker=StartShell @('-File',[IO.Path]::Combine($tools,'storage_worker.ps1'),'-Helper','account_store.ps1','-Database',$accountsDb,'-IdleSeconds','120')
    try {
        function Ask([Diagnostics.Process]$Process,$Request) {
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $Process.StandardInput.WriteLine((Line $Request)); $Process.StandardInput.Flush()
            $task=$Process.StandardOutput.ReadLineAsync()
            if(-not $task.Wait(60000)) { $script:problems++; return -1 }
            $watch.Stop()
            if(-not $task.Result -or (FromJson $task.Result).ok -ne $true) { $script:problems++ }
            return [double]$watch.Elapsed.TotalMilliseconds
        }
        $firstAsset=Ask $assetWorker @{op='asset.read';user_id='user_perf';space_id='shooter'}
        $firstAccount=Ask $accountWorker @{op='session.authenticate';token=$token}
        $readTimes=@(); $commitTimes=@(); $sessionTimes=@()
        $count=[math]::Max($Reads,[math]::Max($Commits,$Sessions))
        for($i=0;$i -lt $count;$i++) {
            if($i -lt $Reads) { $readTimes+=Ask $assetWorker @{op='asset.read';user_id='user_perf';space_id='shooter'} }
            if($i -lt $Sessions) { $sessionTimes+=Ask $accountWorker @{op='session.authenticate';token=$token} }
            if($i -lt $Commits) { $commitTimes+=Ask $assetWorker (CommitRequest $revision); $revision++ }
        }
        Write-Output ('ROUND '+$round+' worker_first_reply_ms asset='+[int]$firstAsset+' account='+[int]$firstAccount)
        Write-Output ('ROUND '+$round+' worker_warm_ms read_p50='+(Percentile $readTimes 0.5)+' read_p95='+(Percentile $readTimes 0.95)+' commit_p50='+(Percentile $commitTimes 0.5)+' commit_p95='+(Percentile $commitTimes 0.95)+' session_p50='+(Percentile $sessionTimes 0.5)+' session_p95='+(Percentile $sessionTimes 0.95)+' n='+$Reads+'/'+$Commits+'/'+$Sessions)
        Write-Output ('ROUND '+$round+' memory_both_alive asset_worker '+(Memory $assetWorker)+' | account_worker '+(Memory $accountWorker))
    } finally {
        foreach($worker in @($assetWorker,$accountWorker)) { try { $worker.StandardInput.Close() } catch {}; if(-not $worker.WaitForExit(10000)) { $worker.Kill(); $script:problems++ }; $worker.Dispose() }
    }
    [void](OneShot 'account_store.ps1' $accountsDb @{op='session.logout';token=$token})
    Write-Output ('ROUND '+$round+' workers_exited=true load_after '+(Load))
}
$final=OneShot 'sqlite_store.ps1' $assetsDb @{op='asset.read';user_id='user_perf';space_id='shooter'}
$state=FromJson $final.reply.body
if([int]$state.revision -ne $revision) { $script:problems++ }
Write-Output ('STORAGE_PERF_RESULT rounds='+$Rounds+' final_revision='+$state.revision+' expected_revision='+$revision+' problems='+$script:problems)
exit $(if($script:problems -eq 0){0}else{1})
