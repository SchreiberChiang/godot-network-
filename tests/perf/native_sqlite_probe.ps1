param(
    [Parameter(Mandatory=$true)][string]$Addons,
    [Parameter(Mandatory=$true)][string]$Work,
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [ValidateRange(1,10)][int]$Rounds=3
)
# Windows side of the option G evaluation (prototypes/native_sqlite). Copies the
# prototype and the unpacked godot-sqlite addon into $Work\project, so neither
# the repository nor the main project receives binaries, then runs correctness
# and repeated cost measurements on new fake data. -Addons is the folder that
# contains "godot-sqlite" (from the official addons.zip).
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Work=[IO.Path]::GetFullPath($Work)
if(Test-Path -LiteralPath $Work) { if(@(Get-ChildItem -LiteralPath $Work -Force).Count) { throw 'Work directory must be empty.' } } else { New-Item -ItemType Directory -Force -Path $Work | Out-Null }
$run=Join-Path $Work 'project'
New-Item -ItemType Directory -Force -Path (Join-Path $run 'addons'),(Join-Path $Work 'data') | Out-Null
foreach($name in @('project.godot','proto.gd')) { Copy-Item -LiteralPath (Join-Path $project ('prototypes\native_sqlite\'+$name)) -Destination $run }
Copy-Item -LiteralPath (Join-Path $Addons 'godot-sqlite') -Destination (Join-Path $run 'addons') -Recurse
$script:problems=0
function Quote($values) { foreach($value in $values){ '"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' } }
function Engine([string[]]$Arguments,[string]$Name,[int]$SampleAtHold=0) {
    $out=Join-Path $Work ($Name+'.out'); $err=Join-Path $Work ($Name+'.err')
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $process=Start-Process -FilePath $Godot -ArgumentList (Quote (@('--headless','--path',$run)+$Arguments)) -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    $handle=$process.Handle
    $memory=''
    if($SampleAtHold) {
        $deadline=[DateTime]::UtcNow.AddSeconds(120)
        while(-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline -and -not (Select-String -LiteralPath $out -Pattern 'PROTO_HOLD' -Quiet -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 100 }
        Start-Sleep -Milliseconds ([int]($SampleAtHold/2))
        if(-not $process.HasExited) { $process.Refresh(); $memory='working_set_mb='+[math]::Round($process.WorkingSet64/1MB,1)+' private_mb='+[math]::Round($process.PrivateMemorySize64/1MB,1) } else { $memory='memory=unavailable' }
    }
    if(-not $process.WaitForExit(300000)) { $process.Kill(); $script:problems++ }
    $watch.Stop()
    return @{code=$process.ExitCode;ms=[int]$watch.ElapsedMilliseconds;text=@(Get-Content -Encoding UTF8 -LiteralPath $out);memory=$memory}
}
$version=(& $Godot --version | Select-Object -First 1)
Write-Output ('INFO engine='+$version+' addon_files='+@(Get-ChildItem -Recurse -File (Join-Path $run 'addons')).Count)
# The editor import registers the extension (.godot/extension_list.cfg). Both runs
# are reported: a crash on the first import is a defect of this option even when
# the second import and normal runs succeed.
$import=Engine @('--import') 'import-first'
$again=Engine @('--import') 'import-second'
$list=Join-Path $run '.godot\extension_list.cfg'
Write-Output ('INFO import first_exit='+$import.code+' first_ms='+$import.ms+' second_exit='+$again.code+' extension_list='+(Test-Path -LiteralPath $list))
if($import.code -ne 0) { $script:problems++; Write-Output 'FAIL first editor import with the extension exits cleanly' } else { Write-Output 'PASS first editor import with the extension exits cleanly' }
if($again.code -ne 0 -or -not (Test-Path -LiteralPath $list)) { $script:problems++; Write-Output 'FAIL second editor import exits cleanly and the extension list exists' } else { Write-Output 'PASS second editor import exits cleanly and the extension list exists' }
$verifyWork=Join-Path $Work 'data\verify'; New-Item -ItemType Directory -Force $verifyWork | Out-Null
$verify=Engine @('--script','res://proto.gd','--','--mode=verify',('--work='+$verifyWork)) 'verify'
$verify.text | Where-Object { $_ -match '^(PASS|FAIL|INFO|PROTO_)' } | Write-Output
if($verify.code -ne 0) { $script:problems++ }
$leak=@(Get-ChildItem -LiteralPath $Work -File | Where-Object { $_.Extension -in @('.out','.err') } | Select-String -Pattern 'SECRET_PARAM_7731').Count
Write-Output ('INFO secret_marker_lines_in_engine_output='+$leak)
if($leak -ne 0) { $script:problems++ }
for($round=1;$round -le $Rounds;$round++) {
    $load=try { (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average } catch { 'unavailable' }
    $start=Engine @('--script','res://proto.gd','--','--mode=baseline','--hold-ms=0') ('start-'+$round)
    $baseline=Engine @('--script','res://proto.gd','--','--mode=baseline','--hold-ms=3000') ('baseline-'+$round) 3000
    $perfWork=Join-Path $Work ('data\perf-'+$round); New-Item -ItemType Directory -Force $perfWork | Out-Null
    $perf=Engine @('--script','res://proto.gd','--','--mode=perf',('--work='+$perfWork),'--reads=200','--commits=100','--hold-ms=3000') ('perf-'+$round) 3000
    if($perf.code -ne 0) { $script:problems++ }
    Write-Output ('ROUND '+$round+' cpu_load_percent='+$load+' engine_start_and_quit_ms='+$start.ms)
    Write-Output ('ROUND '+$round+' baseline_engine '+$baseline.memory)
    Write-Output ('ROUND '+$round+' engine_with_database '+$perf.memory)
    $perf.text | Where-Object { $_ -match '^INFO' } | ForEach-Object { Write-Output ('ROUND '+$round+' '+$_.Substring(5)) }
}
Write-Output ('NATIVE_SQLITE_RESULT rounds='+$Rounds+' verify_exit='+$verify.code+' problems='+$script:problems)
exit $(if($script:problems -eq 0){0}else{1})
