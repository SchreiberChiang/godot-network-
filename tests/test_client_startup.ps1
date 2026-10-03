param([ValidateSet('before','after')][string]$RunName='after',[switch]$BaselineOnly,[switch]$ResumeHarnessFailure,[ValidateSet('before','after')][string]$GuardsStage='',[switch]$Recheck)
# Native substitutes only: no engine, services, network, real data or scanned process termination.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runs=Join-Path $root 'artifacts/client-startup-tests'
$run=Join-Path $runs $RunName
if($Recheck){if($RunName -ne 'after' -or $BaselineOnly -or $GuardsStage -ne ''){throw 'Recheck is a separate lightweight phase under after only'};$run=Join-Path $run 'guards-recheck'}
$shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$checks=New-Object Collections.ArrayList
$commands=New-Object Collections.ArrayList
$utf8=New-Object Text.UTF8Encoding($true)
if($GuardsStage -ne '') {
    # Lightweight phase under the existing after tree; original results stay intact.
    $phase=Join-Path $runs ('after/guards-'+$GuardsStage)
    if(Test-Path -LiteralPath $phase){throw 'Guard phase exists; preserve its evidence'}
    [void][IO.Directory]::CreateDirectory($phase)
    $guardChecks=New-Object Collections.ArrayList
    function GuardCheck([string]$Name,[bool]$Passed,$Observed){[void]$guardChecks.Add(@{name=$Name;passed=$Passed;observed=$Observed});Write-Output ((@('FAIL','PASS')[[int]$Passed])+' '+$Name)}
    function GuardPut([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
    . (Join-Path $root 'tools/shooter_client/client_startup.ps1')
    $native=Join-Path $runs 'after/NativeFixture.exe'
    if(-not(Test-Path -LiteralPath $native)){throw 'Run native startup suite before guard phase'}
    foreach($kind in @('directory','ancestor','client-data','startup')) {
        $fixture=Join-Path $phase $kind
        $target=Join-Path $phase ($kind+'-target')
        [void][IO.Directory]::CreateDirectory($target)
        $directory=Join-Path $fixture 'client'
        $junction=$directory
        if($kind -eq 'ancestor'){$junction=$fixture;$directory=Join-Path $fixture 'client';[void][IO.Directory]::CreateDirectory((Join-Path $target 'client'))}
        if($kind -eq 'client-data'){$junction=Join-Path $directory 'client-data'}
        if($kind -eq 'startup'){$junction=Join-Path $directory 'client-data/startup'}
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($junction))
        New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
        GuardPut (Join-Path $directory 'fixture.txt') '0,23'
        $before=@(Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}) | ConvertTo-Json -Compress
        $rejected=$false;$errorText=''
        try{Start-ClientObserved -FilePath $native -Arguments @('guard') -Directory $directory -ObservationMilliseconds 2000 | Out-Null}catch{$errorText=$_.Exception.Message;$rejected=$errorText -match 'CLIENT_STARTUP_LINKED_PATH'}
        $after=@(Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}) | ConvertTo-Json -Compress
        GuardCheck ($kind+'-junction-rejected-zero-writes') ($rejected -and $before -ceq $after) @{error=$errorText;target_changed=($before -cne $after)}
        # Delete only this exact new junction, nonrecursively, with target verified.
        $link=Get-Item -LiteralPath $junction -Force
        if(-not($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -or [IO.Path]::GetFullPath([string]$link.Target[0]) -ine $target){throw 'Fixture junction identity mismatch'}
        [IO.Directory]::Delete($junction)
    }
    # Real slow workers. The wrapper retains the creating handle for test cleanup.
    Add-Type -TypeDefinition @'
using System; using System.Diagnostics;
public class StartupGuardOwnedWorker {
 public Process Actual; public bool DenyKill;
 public StartupGuardOwnedWorker(Process p, bool deny) {Actual=p;DenyKill=deny;}
 public IntPtr Handle {get{return Actual.Handle;}}
 public bool HasExited {get{return Actual.HasExited;}}
 public int ExitCode {get{return Actual.ExitCode;}}
 public int Id {get{return Actual.Id;}}
 public DateTime StartTime {get{return Actual.StartTime;}}
 public bool WaitForExit(int ms){return Actual.WaitForExit(ms);}
 public void Kill(){if(DenyKill)throw new InvalidOperationException("INJECTED_OWNED_WORKER_KILL_DENIED");Actual.Kill();}
 public void Dispose(){} // Test harness retains the actual process until cleanup.
}
'@
    foreach($mode in @('timeout','kill-denied')) {
        $directory=Join-Path $phase $mode
        GuardPut (Join-Path $directory 'slow-worker.ps1') 'param([string]$StartupRequest) Start-Sleep -Seconds 14'
        $script:guardWorker=$null;$script:guardDenyKill=$mode -eq 'kill-denied';$script:guardSlow=Join-Path $directory 'slow-worker.ps1'
        function Start-Process {
            param([string]$FilePath,$ArgumentList,[string]$WindowStyle,[switch]$PassThru,[string]$RedirectStandardOutput,[string]$RedirectStandardError)
            $values=@($ArgumentList)
            for($i=0;$i -lt $values.Count;$i++){if($values[$i] -match 'client_startup\.ps1"$'){$values[$i]='"'+$script:guardSlow+'"'}}
            $p=Microsoft.PowerShell.Management\Start-Process -FilePath $FilePath -ArgumentList $values -WindowStyle $WindowStyle -PassThru -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError
            $script:guardWorker=New-Object StartupGuardOwnedWorker($p,$script:guardDenyKill)
            [void]$script:guardWorker.Handle
            return $script:guardWorker
        }
        $errorText=''
        try{Start-ClientObserved -FilePath $native -Arguments @('guard') -Directory $directory -ObservationMilliseconds 100 | Out-Null}catch{$errorText=$_.Exception.Message}
        finally{Remove-Item -LiteralPath Function:\Start-Process}
        $worker=$script:guardWorker.Actual
        $request=@(Get-ChildItem -LiteralPath (Join-Path $directory 'client-data/startup') -Filter '*.request.json')
        $recovery=@(Get-ChildItem -LiteralPath (Join-Path $directory 'client-data/startup') -Filter '*.recovery.json')
        if($mode -eq 'timeout'){
            GuardCheck 'timed-out-owned-worker-ended' ($worker.HasExited -and $errorText -match 'CLIENT_STARTUP_RECEIPT_TIMEOUT') @{worker_alive=(-not $worker.HasExited);error=$errorText}
        }else{
            GuardCheck 'kill-failure-preserves-request-and-recovery' (-not $worker.HasExited -and $request.Count -eq 1 -and $recovery.Count -eq 1 -and $errorText -match 'CLIENT_STARTUP_WORKER_CLEANUP_FAILED') @{worker_alive=(-not $worker.HasExited);request_count=$request.Count;recovery_count=$recovery.Count;error=$errorText}
        }
        # Only the real process this test just created, held by its original handle.
        if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(3000)}
        $worker.Dispose()
    }
    $result=@{scope='Startup path guards and owned-worker timeout only';checks=@($guardChecks);passed=@($guardChecks|Where-Object passed).Count;failed=@($guardChecks|Where-Object {-not $_.passed}).Count}
    GuardPut (Join-Path $phase 'result.json') ($result|ConvertTo-Json -Depth 8)
    Write-Output ('CLIENT_STARTUP_GUARDS passed='+$result.passed+' failed='+$result.failed)
    if($result.failed){exit 1};exit 0
}
if(Test-Path -LiteralPath $run){
    if(-not $ResumeHarnessFailure){throw 'Run exists; preserve evidence. Only before and after runs are allowed.'}
    $prior=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $prior.harness_error -and $prior.failed -eq 0){throw 'Only a failed run may be resumed after reviewing its saved result'}
    [IO.File]::Copy((Join-Path $run 'result.json'),(Join-Path $run ('harness-failure-'+[Guid]::NewGuid().ToString('N')+'.json')))
}
for($cursor=$run;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
    $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
    if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked fixture path refused'}
}
[void][IO.Directory]::CreateDirectory($run)
function Put([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Check([string]$Name,[bool]$Passed,$Observed){[void]$checks.Add(@{name=$Name;passed=$Passed;observed=$Observed});Write-Output ((@('FAIL','PASS')[[int]$Passed])+' '+$Name)}
function Quote($Values){foreach($value in $Values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}}
function ReadLive([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=New-Object IO.StreamReader($stream)
    try{$reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Execute([string]$Name,[string]$File,[string[]]$Arguments){
    $out=Join-Path $run ($Name+'.stdout.txt');$err=Join-Path $run ($Name+'.stderr.txt')
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $File -ArgumentList (Quote $Arguments) -WorkingDirectory $run -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $owned=$p.Handle
    if(-not $p.WaitForExit(15000)){throw ('Owned test entry did not return in 15 seconds: '+$Name)}
    $code=$p.ExitCode;$clock.Stop();$p.Dispose()
    $record=@{name=$Name;file=$File;arguments=$Arguments;exit_code=$code;elapsed_ms=$clock.ElapsedMilliseconds;stdout=$out;stderr=$err}
    [void]$commands.Add($record)
    return @{code=$code;elapsed=$clock.ElapsedMilliseconds;text=((ReadLive $out)+(ReadLive $err))}
}
function RunPS([string]$Name,[string]$File,[string[]]$Arguments=@()){Execute $Name $shell (@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$File)+$Arguments)}
function Literal([string]$Variable){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/build_framework_release.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Builder parse failed'}
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq ('$'+$Variable)}.GetNewClosure(),$true)
    if(-not $node -or $node.Right.Expression -isnot [Management.Automation.Language.StringConstantExpressionAst]){throw 'Generated launcher literal missing'}
    $node.Right.Expression.Value
}
function Fixture([string]$Name,[string]$Route,[int]$Delay,[int]$Code){
    $dir=Join-Path $run ($Name+' 中文 space '' path')
    if($Route -eq 'framework'){$dir=Join-Path $run ($Name+' package 中文 space/clients/shooter')}
    Put (Join-Path $dir 'fixture.txt') ($Delay.ToString()+','+$Code)
    foreach($marker in @('pid.txt','arguments.txt','completed.txt')){
        $path=Join-Path $dir $marker
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    }
    [IO.File]::Copy($native,(Join-Path $dir 'Client.exe'),$true)
    Put (Join-Path $dir 'Client.pck') 'NOT_A_GODOT_PACK'
    Put (Join-Path $dir 'connection.json') '{}';Put (Join-Path $dir 'server.crt') 'SYNTHETIC'
    if($Route -eq 'standalone'){
        [IO.File]::Copy((Join-Path $root 'tools/shooter_client/RunGame.ps1'),(Join-Path $dir 'RunGame.ps1'),$true)
    }else{Put (Join-Path $dir 'RunGame.ps1') ((Literal 'playerLauncher').Replace('__GAME__','shooter'))}
    $helper=Join-Path $root 'tools/shooter_client/client_startup.ps1'
    if(Test-Path -LiteralPath $helper){[IO.File]::Copy($helper,(Join-Path $dir 'client_startup.ps1'),$true)}
    return $dir
}
function AwaitFile([string]$Path){$deadline=[DateTime]::UtcNow.AddSeconds(8);while(-not(Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50};if(-not(Test-Path -LiteralPath $Path)){throw ('Native fixture marker missing: '+$Path)}}
$fatal=''
try{
    $native=if($Recheck){Join-Path $runs 'after/NativeFixture.exe'}else{Join-Path $run 'NativeFixture.exe'}
    $savedTemp=$env:TEMP;$savedTmp=$env:TMP
    try{
        $env:TEMP=Join-Path $run 'compiler-temp';$env:TMP=$env:TEMP;[void][IO.Directory]::CreateDirectory($env:TEMP)
        if(-not (Test-Path -LiteralPath $native)){Add-Type -OutputAssembly $native -OutputType ConsoleApplication -TypeDefinition @'
using System; using System.IO; using System.Diagnostics; using System.Text; using System.Threading;
public class ClientStartupNative {
 public static int Main(string[] args) {
  string dir=Environment.CurrentDirectory;
  string[] config=File.ReadAllText(Path.Combine(dir,"fixture.txt")).Trim('\uFEFF').Split(',');
  File.WriteAllText(Path.Combine(dir,"pid.txt"),Process.GetCurrentProcess().Id.ToString());
  string[] encoded=Array.ConvertAll(args,a=>Convert.ToBase64String(Encoding.UTF8.GetBytes(a)));
  File.WriteAllLines(Path.Combine(dir,"arguments.txt"),encoded);
  Console.Error.WriteLine("NATIVE_FIXTURE_STDERR");
  Thread.Sleep(Int32.Parse(config[0]));
  File.WriteAllText(Path.Combine(dir,"completed.txt"),"normal exit");
  return Int32.Parse(config[1]);
 }
}
'@
        }
    }finally{$env:TEMP=$savedTemp;$env:TMP=$savedTmp}
    Put (Join-Path $run 'fixture.txt') '0,23'
    $r=Execute 'control-native-23' $native @('native control')
    Check 'native-os-exit-23' ($r.code -eq 23) $r
    $routes=@('standalone','generated','framework')
    $cases=@(@{name='early-nonzero';delay=0;code=23;expected=23})
    if(-not $BaselineOnly){$cases+=@(@{name='early-zero';delay=50;code=0;expected=1},@{name='persistent';delay=6000;code=0;expected=0})}
    foreach($case in $cases){foreach($route in $routes){
        $label=$route+'-'+$case.name
        $dir=Fixture $label $route $case.delay $case.code
        $entry=Join-Path $dir 'RunGame.ps1';$entryArgs=@()
        if($route -eq 'framework'){
            $package=Join-Path $run ($label+' package 中文 space');[void][IO.Directory]::CreateDirectory((Join-Path $package 'clients'))
            $dir=Join-Path $package 'clients/shooter'
            Put (Join-Path $package 'RunFramework.ps1') (Literal 'launcher')
            foreach($file in @('roomkit_entry.ps1','detached_process.ps1')){[void][IO.Directory]::CreateDirectory((Join-Path $package 'tools'));[IO.File]::Copy((Join-Path $root ('tools/'+$file)),(Join-Path $package ('tools/'+$file)),$true)}
            Put (Join-Path $package 'artifacts/client/connection.json') '{"ca_certificate":"server.crt"}';Put (Join-Path $package 'artifacts/client/server.crt') 'SYNTHETIC'
            [void][IO.Directory]::CreateDirectory((Join-Path $package 'clients/turns'))
            $entry=Join-Path $package 'RunFramework.ps1';$entryArgs=@('-Operation','client','-Game','shooter')
        }
        $r=RunPS $label $entry $entryArgs
        Check ($label+'-exit') ($r.code -eq $case.expected) $r
        AwaitFile (Join-Path $dir 'arguments.txt')
        $actual=@([IO.File]::ReadAllLines((Join-Path $dir 'arguments.txt')) | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))})
        Check ($label+'-arguments') ($actual.Count -eq 3 -and $actual[0] -ceq '--' -and $actual[1] -ceq '--game=shooter' -and $actual[2] -ceq ('--connection-config='+(Join-Path $dir 'connection.json'))) $actual
        if($case.name -eq 'persistent'){
            $nativePid=[int][IO.File]::ReadAllText((Join-Path $dir 'pid.txt'))
            $ownedNative=Get-Process -Id $nativePid -ErrorAction SilentlyContinue
            $same=$ownedNative -and $ownedNative.Path -ieq (Join-Path $dir 'Client.exe')
            Check ($label+'-bounded-alive') ($r.elapsed -ge 1900 -and $r.elapsed -lt 5500 -and $same -and $r.text -match 'CLIENT_STARTUP_OBSERVED') $r
        }
        AwaitFile (Join-Path $dir 'completed.txt')
        Check ($label+'-normal-completion') $true 'The native process outlived the intermediary and entry, then exited normally.'
        if(-not $BaselineOnly){
            $receipt=Get-ChildItem -LiteralPath (Join-Path $dir 'client-data/startup') -Filter '*.receipt.json' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            $record=Get-Content -LiteralPath $receipt.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $state=if($case.name -eq 'persistent'){'observed'}else{'exited'}
            Check ($label+'-receipt') ($record.status -eq $state -and $record.launcher_exit_code -eq $case.expected -and ($case.name -eq 'persistent' -or $record.native_exit_code -eq $case.code)) $record
            Check ($label+'-stderr') ((ReadLive $record.stderr) -match 'NATIVE_FIXTURE_STDERR') $record.stderr
        }
    }}
    if(-not $BaselineOnly){
        $sentinelDirectory=Fixture 'unrelated-sentinel' 'standalone' 6000 0
        $sentinel=Start-Process -FilePath (Join-Path $sentinelDirectory 'Client.exe') -WorkingDirectory $sentinelDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $sentinelDirectory 'sentinel.stdout.txt') -RedirectStandardError (Join-Path $sentinelDirectory 'sentinel.stderr.txt')
        $ownedSentinelHandle=$sentinel.Handle
        # Invoke the reusable helper with Windows quoting edge cases and a shorter observation boundary.
        foreach($pair in @(@{name='inside-boundary';delay=50;expected=23},@{name='after-boundary';delay=2500;expected=0})){
            $dir=Fixture $pair.name 'standalone' $pair.delay 23
            $driver=@'
param([string]$Directory)
. (Join-Path $Directory 'client_startup.ps1')
$values=@('', 'space value', 'quote"value', 'backslash\"value', 'tail slash\', '中文')
$r=Start-ClientObserved -FilePath (Join-Path $Directory 'Client.exe') -Arguments $values -Directory $Directory -ObservationMilliseconds 1000
$values | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Directory 'expected.json') -Encoding UTF8
$r | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Directory 'driver-result.json') -Encoding UTF8
exit $r.launcher_exit_code
'@
            Put (Join-Path $dir 'driver.ps1') $driver
            $r=RunPS $pair.name (Join-Path $dir 'driver.ps1') @('-Directory',$dir)
            Check ($pair.name+'-exit') ($r.code -eq $pair.expected) $r
            AwaitFile (Join-Path $dir 'arguments.txt')
            $expected=Get-Content -LiteralPath (Join-Path $dir 'expected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $actual=@([IO.File]::ReadAllLines((Join-Path $dir 'arguments.txt')) | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))})
            Check ($pair.name+'-quoting') (($expected | ConvertTo-Json -Compress) -ceq ($actual | ConvertTo-Json -Compress)) $actual
            if($pair.name -eq 'inside-boundary'){$sentinel.Refresh();Check 'unrelated-process-still-running' (-not $sentinel.HasExited) @{pid=$sentinel.Id}}
            AwaitFile (Join-Path $dir 'completed.txt')
        }
        AwaitFile (Join-Path $sentinelDirectory 'completed.txt')
        [void]$sentinel.WaitForExit(3000)
        Check 'unrelated-process-normal-exit' ($sentinel.HasExited -and $sentinel.ExitCode -eq 0) @{pid=$sentinel.Id;exit_code=$sentinel.ExitCode}
        $sentinel.Dispose()
        $allPs=@((Join-Path $root 'tools/shooter_client/RunGame.ps1'),(Join-Path $root 'tools/shooter_client/client_startup.ps1'),(Join-Path $root 'tools/build_framework_release.ps1'),$PSCommandPath)
        foreach($path in $allPs){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors);Check ('parse-'+[IO.Path]::GetFileName($path)) ($errors.Count -eq 0) @($errors | ForEach-Object Message)}
    }
}catch{$fatal=$_.Exception.ToString();Write-Output $fatal}
$result=@{scope='Windows PowerShell 5.1 + native substitutes; no network readiness claim';checks=@($checks);commands=@($commands);harness_error=$fatal;passed=@($checks | Where-Object passed).Count;failed=@($checks | Where-Object {-not $_.passed}).Count}
Put (Join-Path $run 'result.json') ($result | ConvertTo-Json -Depth 10)
Write-Output ('CLIENT_STARTUP_TESTS passed='+$result.passed+' failed='+$result.failed)
if($fatal){exit 2};if($result.failed){exit 1};exit 0
