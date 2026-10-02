param([string]$Project = '')
# Refusal rules of tools/run_isolated_test.ps1, checked with a STAND-IN engine
# (a .cmd that only records its arguments). No real engine and no service entry
# point is ever started here. Temporary probe scripts live in a new folder under
# tests/ and a junction is created for the link cases; both are removed at the
# end. Exit code: 0 when every case behaves as expected.
$ErrorActionPreference = 'Stop'
if (-not $Project) { $Project = Split-Path -Parent $PSScriptRoot }
$Project = [IO.Path]::GetFullPath($Project).TrimEnd('\')
$runner = Join-Path $Project 'tools\run_isolated_test.ps1'
$id = [guid]::NewGuid().ToString('N').Substring(0, 10)
$probeDir = Join-Path $Project "tests\.runner-probe-$id"
$work = Join-Path $Project "data\runner-test-$id"
$standIn = Join-Path $work 'stand-in-engine.cmd'
$invoked = Join-Path $work 'stand-in-invoked.txt'
$junctions = @()
$script:passed = 0; $script:failed = 0
function Check([bool]$Condition, [string]$Name) { if ($Condition) { $script:passed++; Write-Output "PASS $Name" } else { $script:failed++; Write-Output "FAIL $Name" } }
function Probe([string]$Name, [string]$Text) { $path = Join-Path $probeDir $Name; [IO.File]::WriteAllText($path, $Text); return "res://tests/.runner-probe-$id/$Name" }
# One runner call; returns @{code; out; invoked}.
function Run([string]$Script, [string]$Isolation, [string]$Log, [string]$TestArgs = '', [string]$CopyIn = '',[int]$TimeoutSeconds=1800) {
    Remove-Item -LiteralPath $invoked -ErrorAction SilentlyContinue
    $call = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-Script', $Script, '-Isolation', $Isolation, '-Log', $Log, '-Godot', $standIn, '-Project', $Project)
    if ($TestArgs) { $call += @('-TestArgs', $TestArgs) }
    if ($CopyIn) { $call += @('-CopyIn', $CopyIn) }
    if($TimeoutSeconds -ne 1800){$call+=@('-TimeoutSeconds',[string]$TimeoutSeconds)}
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & powershell @call 2>&1
    $ErrorActionPreference = $previous
    return @{ code = $LASTEXITCODE; out = ($out -join ' '); invoked = (Test-Path -LiteralPath $invoked) }
}
$counter = 0
function Fresh() { $script:counter++; return (Join-Path $work ("iso-" + $script:counter)) }
# Refused before anything started, and for the expected reason.
function Refused([hashtable]$Result, [string]$Why = '') { return $Result.code -eq 64 -and -not $Result.invoked -and $Result.out -match 'REFUSED' -and (-not $Why -or $Result.out -match $Why) }

try {
    [void][IO.Directory]::CreateDirectory($work)
    [void][IO.Directory]::CreateDirectory($probeDir)
    [IO.File]::WriteAllText($standIn, "@echo off`r`necho %* > `"$invoked`"`r`necho FAKE_RESULT passed=3 failed=0`r`nexit /b 0`r`n")

    # ---- probe scripts (never run by a real engine) ----
    $plain = Probe 'plain.gd' "extends SceneTree`n"
    $direct = Probe 'direct.gd' "extends `"res://host/operator.gd`"`n"
    $level1 = Probe 'level1.gd' "extends `"res://host/operator.gd`"`n"
    $level2 = Probe 'level2.gd' "extends `"res://tests/.runner-probe-$id/level1.gd`"`n"
    $level3 = Probe 'level3.gd' "extends `"level2.gd`"`n"
    $namedBase = Probe 'named_base.gd' "class_name RunnerProbeBase$id`nextends `"res://host/managed_host.gd`"`n"
    $named = Probe 'named_child.gd' "extends RunnerProbeBase$id`n"
    $helper = Probe 'helper.gd' "extends RefCounted`nconst Entry := `"res://host/operator.gd`"`n"
    $preloads = Probe 'preloads.gd' "extends SceneTree`nconst Helper = preload(`"res://tests/.runner-probe-$id/helper.gd`")`n"
    $spawns = Probe 'spawns.gd' "extends SceneTree`nfunc _initialize() -> void:`n`tOS.create_process(OS.get_executable_path(), [`"--script`", `"res://host/main.gd`"])`n"
    $unknown = Probe 'unknown_base.gd' "extends SomeUnresolvedBase$id`n"
    $traversingExtends = Probe 'traversing_extends.gd' "extends `"res://tests/../host/operator.gd`"`n"

    # ---- script paths ----
    $r = Run 'host/operator.gd' (Fresh) ((Fresh) + '\log'); Check (Refused $r 'not a test script') 'a service entry point is refused (only syntax-checked elsewhere)'
    $iso = Fresh; $r = Run 'res://tests/../host/operator.gd' $iso "$iso\log"; Check (Refused $r "'\.\.' segment") 'res://tests/../host/operator.gd (traversal) is refused'
    $iso = Fresh; $r = Run 'tests\..\host\operator.gd' $iso "$iso\log"; Check (Refused $r "'\.\.' segment") 'tests\..\host\operator.gd (Windows-style traversal) is refused'
    $iso = Fresh; $r = Run 'res://tests/./../tools/check_scripts.ps1' $iso "$iso\log"; Check (Refused $r "'\.\.' segment") 'a traversal to a non-test file is refused'
    # A junction inside tests/ that points at host/.
    $link = Join-Path $probeDir 'linked-host'
    New-Item -ItemType Junction -Path $link -Target (Join-Path $Project 'host') | Out-Null
    $junctions += $link
    $iso = Fresh; $r = Run "res://tests/.runner-probe-$id/linked-host/operator.gd" $iso "$iso\log"; Check (Refused $r 'link or junction') 'a script reached through a junction under tests/ is refused'

    # ---- service detection ----
    $iso = Fresh; $r = Run $direct $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'a test that directly extends the Operator needs isolated arguments'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'two levels of quoted extends are followed to the Operator'
    $iso = Fresh; $r = Run $level3 $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'a relative extends path is followed'
    $iso = Fresh; $r = Run $named $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'an extends by class_name is followed to the managed host'
    $iso = Fresh; $r = Run $preloads $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'a preloaded helper that names the Operator makes the test service-like'
    $iso = Fresh; $r = Run $spawns $iso "$iso\log"; Check (Refused $r 'needs --data-root') 'a test that starts host/main.gd itself is service-like'
    $iso = Fresh; $r = Run $unknown $iso "$iso\log"; Check (Refused $r -and $r.out -match 'cannot resolve') 'an unresolvable base class is refused'
    $iso = Fresh; $r = Run $traversingExtends $iso "$iso\log"; Check (Refused $r "'\.\.' segment") 'an extends path with a .. segment is refused'

    # ---- isolation folder, log and arguments of a service-like test ----
    $good = { param($iso) "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391" }
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" (& $good $iso); Check ($r.code -eq 0 -and $r.invoked -and $r.out -match 'service_like=True') 'with every path inside a new isolation folder and an explicit port the stand-in engine is started'
    $recorded = if (Test-Path -LiteralPath $invoked) { [IO.File]::ReadAllText($invoked) } else { '' }
    Check ($recorded -match [regex]::Escape("--isolation=$iso") -and $recorded -match '--script res://tests/') 'the stand-in received the test script and the isolation folder'
    $r = Run $level2 $iso "$iso\log2" (& $good $iso); Check (Refused $r 'already exists') 'an isolation folder that already exists is refused (no sharing between runs)'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=res://artifacts/framework-games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'games.*outside the isolation') 'a shared game index outside the isolation folder is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=res://data/framework;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'data-root.*outside the isolation') 'the real data root is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\..\public;--panel-port=28391"; Check (Refused $r "'\.\.' segment") 'a public folder that climbs out with .. is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=res://artifacts/client;--panel-port=28391"; Check (Refused $r 'public-client-dir.*outside the isolation') 'the real public client folder is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391;--operator-log-path=$work\elsewhere.log"; Check (Refused $r 'operator-log-path.*outside the isolation') 'a log path outside the isolation folder is refused'
    $iso = Fresh; $r = Run $level2 $iso "$work\outside" (& $good $iso); Check (Refused $r 'log .* is outside') 'a runner log outside the isolation folder is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28291"; Check (Refused $r 'panel-port') 'the production panel port 28291 is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public"; Check (Refused $r 'panel-port') 'a missing panel port is refused'
    $r = Run $level2 (Join-Path $Project 'data\framework\x') "$Project\data\framework\x\log" ''; Check (Refused $r 'data/framework') 'an isolation folder inside data/framework is refused'
    $r = Run $level2 (Join-Path $Project 'logs\iso-outside-data') "$Project\logs\iso-outside-data\log" ''; Check (Refused $r 'inside data/') 'an isolation folder outside data/ is refused'
    # An isolation folder whose parent is a junction.
    $linkedData = Join-Path $work 'linked-data'
    [void][IO.Directory]::CreateDirectory((Join-Path $work 'real-data'))
    New-Item -ItemType Junction -Path $linkedData -Target (Join-Path $work 'real-data') | Out-Null
    $junctions += $linkedData
    $r = Run $level2 "$linkedData\iso" "$linkedData\iso\log" ''; Check (Refused $r 'link or junction') 'an isolation folder reached through a junction is refused'

    # ---- duplicated and name-based path arguments ----
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--games=res://artifacts/framework-games.json;--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'more than once') 'a shared --games followed by an isolated --games is refused (no argument may repeat)'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391;--panel-port=28392"; Check (Refused $r 'more than once') 'a repeated non-path argument is refused as well'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'games is empty') 'an empty --games is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'absolute or res://') 'a bare file name for --games is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=data;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'absolute or res://') 'a relative --data-root without a slash is refused'
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso;--games=$iso\games.json;--public-client-dir=$iso\public;--panel-port=28391"; Check (Refused $r 'outside the isolation') 'the isolation folder itself as --data-root is refused'
    $iso = Fresh; $r = Run $plain $iso "$iso\log" "--games=games.json"; Check (Refused $r 'absolute or res://') 'path arguments are checked by name for ordinary tests too'
    $iso = Fresh; $r = Run $plain $iso "$iso\log" "--isolation=$work\other"; Check (Refused $r 'set by this script') 'a caller-supplied --isolation is refused'

    # ---- files copied into the isolation folder ----
    $seed = Join-Path $work 'seed-index.json'
    [IO.File]::WriteAllText($seed, '{}')
    $iso = Fresh; $r = Run $level2 $iso "$iso\log" "--data-root=$iso\data;--games=$iso\seed-index.json;--public-client-dir=$iso\public;--panel-port=28391" $seed
    Check ($r.code -eq 0 -and $r.invoked -and (Test-Path -LiteralPath "$iso\seed-index.json")) 'a game index copied in with -CopyIn lands inside the new isolation folder and the run starts'
    $iso = Fresh; $r = Run $plain $iso "$iso\log" '' "$work\no-such-file.json"; Check ((Refused $r 'does not exist') -and -not (Test-Path -LiteralPath $iso)) 'a missing file to copy is refused before the isolation folder is created'
    $iso = Fresh; $r = Run $plain $iso "$iso\log" '' "$work\..\framework\operator.json"; Check (Refused $r "'\.\.' segment") 'a file to copy given with a .. segment is refused'

    # ---- ordinary tests ----
    $iso = Fresh; $r = Run $plain $iso "$iso\log"; Check ($r.code -eq 0 -and $r.invoked -and $r.out -match 'service_like=False') 'an ordinary test runs with only a new isolation folder and log'
    Check ($r.out -match 'ARTIFACT_RETENTION_UNMANAGED' -and -not(Test-Path -LiteralPath (Join-Path $iso '.roomkit-test-owner.json'))) 'legacy nested isolation naming remains compatible and is explicitly unmanaged'
    $iso = Fresh; $r = Run 'res://tests/run_posix_operator.gd' $iso "$iso\log"; Check (Refused $r -and $r.out -match 'needs --data-root') 'the real Linux Operator test is service-like and refused without isolated arguments'

    # ---- managed direct test roots and bounded evidence ----
    $managed=@()
    foreach($number in 1..3){
        $iso=Join-Path $Project ("data/test-isolated-runner-$id-$number")
        $managed+=$iso;$r=Run $plain $iso "$iso\log"
        Check ($r.code -eq 0 -and $r.invoked -and -not($r.out -match 'RETENTION_SKIPPED')) ("managed stand-in run $number completes normally")
    }
    Check (-not(Test-Path -LiteralPath $managed[0]) -and (Test-Path -LiteralPath $managed[1]) -and (Test-Path -LiteralPath $managed[2])) 'managed test directories keep only the latest two runs'
    $ledger=Join-Path $Project 'artifacts/retention-ledger'
    $records=@(Get-ChildItem -LiteralPath $ledger -Filter '*.json' -File|ForEach-Object {Get-Content -LiteralPath $_.FullName -Encoding UTF8 -Raw|ConvertFrom-Json}|Where-Object {@($_.paths) -contains $managed[0]})
    $archived=$records|Select-Object -First 1
    Check ($archived.state -eq 'pruned' -and $archived.summary.exit_code -eq 0 -and $archived.summary.counts[0].passed -eq 3 -and $archived.summary.counts[0].failed -eq 0) 'pruned run preserves exit and structured counts in the ledger'
    Check (@($archived.snapshot|Where-Object {$_.path.EndsWith('log.stdout') -and $_.sha256.Length -eq 64}).Count -eq 1 -and @($archived.snapshot|Where-Object {$_.path.EndsWith('log.stderr') -and $_.sha256.Length -eq 64}).Count -eq 1) 'stdout and stderr original hashes survive pruning'
    Check ((Test-Path -LiteralPath (Join-Path $managed[2] '.roomkit-test-owner.json')) -and (Test-Path -LiteralPath (Join-Path $managed[2] 'log.stdout'))) 'retained run keeps owned marker and original output files'

    $failedProbe=Probe 'failed.gd' "extends SceneTree`n"
    [IO.File]::WriteAllText($standIn,"@echo off`r`necho %* > `"$invoked`"`r`necho FAKE_RESULT passed=3 failed=1`r`nexit /b 7`r`n")
    $failureRoot=Join-Path $Project "data/test-isolated-runner-failure-$id"
    $r=Run $failedProbe $failureRoot "$failureRoot\log"
    $failureRecord=@(Get-ChildItem -LiteralPath $ledger -Filter '*.json' -File|ForEach-Object {Get-Content -LiteralPath $_.FullName -Encoding UTF8 -Raw|ConvertFrom-Json}|Where-Object {@($_.paths) -contains $failureRoot})|Select-Object -First 1
    Check ($r.code -eq 7 -and $failureRecord.outcome -eq 'failure' -and $failureRecord.summary.exit_code -eq 7 -and $failureRecord.summary.counts[0].failed -eq 1) 'nonzero test exit is preserved and registered as failure'

    $timeoutProbe=Probe 'timeout.gd' "extends SceneTree`n"
    [IO.File]::WriteAllText($standIn,"@echo off`r`necho %* > `"$invoked`"`r`n:waiting`r`ngoto waiting`r`n")
    $timeoutRoot=Join-Path $Project "data/test-isolated-runner-timeout-$id"
    $r=Run $timeoutProbe $timeoutRoot "$timeoutRoot\log" '' '' 1
    $timeoutRecord=@(Get-ChildItem -LiteralPath $ledger -Filter '*.json' -File|ForEach-Object {Get-Content -LiteralPath $_.FullName -Encoding UTF8 -Raw|ConvertFrom-Json}|Where-Object {@($_.paths) -contains $timeoutRoot})|Select-Object -First 1
    Check ($r.code -eq 124 -and $timeoutRecord.outcome -eq 'failure' -and $timeoutRecord.summary.exit_code -eq 124 -and $timeoutRecord.summary.timed_out -and $timeoutRecord.summary.process_confirmed_stopped) 'timeout returns 124 and is registered only after the stand-in process exits'
} finally {
    # Remove the junctions themselves first (never their targets), then make sure
    # no link is left before anything is removed recursively.
    foreach ($junction in $junctions) { if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) } }
    $left = @(foreach ($folder in @($probeDir, $work)) { if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue } })
    if ($left.Count) {
        Write-Output ("FAIL links remain, nothing removed recursively: " + ($left.FullName -join ', '))
        $script:failed++
    } else {
        if (Test-Path -LiteralPath $probeDir) { Remove-Item -LiteralPath $probeDir -Recurse -Force }
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
}
Check (-not (Test-Path -LiteralPath $probeDir) -and -not (Test-Path -LiteralPath $work) -and (Test-Path -LiteralPath (Join-Path $Project 'host\operator.gd'))) 'probe scripts, junctions and the work folder are removed; the junction targets are intact'
Write-Output "ISOLATED_RUNNER_RESULT passed=$script:passed failed=$script:failed engine=stand-in"
exit ([int]($script:failed -ne 0))
