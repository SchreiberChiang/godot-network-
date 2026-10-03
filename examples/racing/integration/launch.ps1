param(
    [ValidateSet('Play','Verify')][string]$Mode='Play',
    [string]$RunName='',
    [string]$OutputRoot='',
    [string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
# Worktrees share a Git common directory. Keep generated output in the main
# checkout so reclaiming this source worktree cannot discard accepted evidence.
$common=@(& git -C $repo rev-parse --path-format=absolute --git-common-dir)
if($LASTEXITCODE -ne 0 -or $common.Count -ne 1){throw 'Git project root unavailable'}
$storageRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$common[0]))
$allowedOutput=Join-Path $storageRoot 'artifacts/racing-offline'
if($OutputRoot -eq ''){$OutputRoot=$allowedOutput}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(-not $OutputRoot.TrimEnd('\','/').Equals($allowedOutput.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be this project artifacts/racing-offline directory'}
function NoLinks([string]$p){
    $cursor=[IO.Path]::GetFullPath($p)
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked run path refused'};$next=[IO.Path]::GetDirectoryName($cursor);if($next -eq $cursor){break};$cursor=$next}
}
NoLinks $OutputRoot
NoLinks $repo
. (Join-Path $repo 'tools/artifact_retention.ps1')
if($RunName -eq ''){$RunName=$Mode.ToLowerInvariant()+'-'+(Get-Date -Format 'yyyyMMddHHmmssfff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)}
if($RunName -notmatch '\A[a-zA-Z0-9][a-zA-Z0-9-]{0,63}\z'){throw 'Invalid run name'}
if($RunName -ieq 'runtime'){throw 'Reserved run name'}
$run=Join-Path $OutputRoot $RunName
if(Test-Path -LiteralPath $run){throw 'Run directory already exists; choose a new name'}
$engineDir=Join-Path $OutputRoot 'runtime'
NoLinks $engineDir
[void][IO.Directory]::CreateDirectory($engineDir)
$engine=Join-Path $engineDir 'Godot.exe'
NoLinks $engine
NoLinks (Join-Path $engineDir '._sc_')
NoLinks (Join-Path $engineDir 'editor_data')
NoLinks (Join-Path $engineDir 'running.lock')
$lease=[IO.File]::Open((Join-Path $engineDir 'running.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
$sourceHash=(Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash
if(-not(Test-Path -LiteralPath $engine)){Copy-Item -LiteralPath $Godot -Destination $engine}
if((Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash -ne $sourceHash){throw 'Isolated engine differs'}
[IO.File]::WriteAllText((Join-Path $engineDir '._sc_'),'')
[void][IO.Directory]::CreateDirectory($run)
Write-Output ('RACING_OFFLINE_EVIDENCE='+$run)
$project=Join-Path $run 'project'
[void][IO.Directory]::CreateDirectory($project)
$utf8=New-Object Text.UTF8Encoding($false)
$sources=@{
    'project.godot'='examples/racing/integration/project.godot';'main.tscn'='examples/racing/integration/main.tscn';
    'main.gd'='examples/racing/integration/main.gd';'vehicle.gd'='examples/racing/integration/vehicle.gd';
    'vehicle_base.gd'='examples/racing/prototype/vehicle.gd';'acceptance.gd'='examples/racing/integration/acceptance.gd';
    'track/harbor.gd'='prototypes/racing_level/harbor.gd';'track/track_data.gd'='prototypes/racing_level/track_data.gd';
    'models/street_car_v2.glb'='prototypes/racing_visual/v2/models/street_car_v2.glb'
}
$hashes=@()
foreach($relative in $sources.Keys){
    $inputFile=Join-Path $repo $sources[$relative];NoLinks $inputFile
    $out=Join-Path $project $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out))
    if($relative -eq 'track/harbor.gd'){$text=[IO.File]::ReadAllText($inputFile).Replace('res://track_data.gd','res://track/track_data.gd');[IO.File]::WriteAllText($out,$text,$utf8)}
    else{Copy-Item -LiteralPath $inputFile -Destination $out}
    $hashes += [ordered]@{source=$sources[$relative];target=$relative;source_sha256=(Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash;staged_sha256=(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash}
}
[IO.File]::WriteAllText((Join-Path $run 'sources.json'),($hashes|ConvertTo-Json -Depth 5),$utf8)
function InvokeEngine([string]$Phase,[string]$Arguments,[int]$Timeout){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$engine;$info.WorkingDirectory=$project;$info.Arguments=$Arguments
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($k in @('HOME','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME')){
        $dir=Join-Path $run ('env/'+$k);[void][IO.Directory]::CreateDirectory($dir);$info.EnvironmentVariables[$k]=$dir
    }
    $child=New-Object Diagnostics.Process;$child.StartInfo=$info;$started=$false
    try {
        $started=$child.Start();if(-not $started){throw 'Engine did not start'}
        $out=$child.StandardOutput.ReadToEndAsync();$err=$child.StandardError.ReadToEndAsync()
        $timedOut=$false
        if($Timeout -eq 0){$child.WaitForExit()}elseif(-not $child.WaitForExit($Timeout)){$timedOut=$true;$child.Kill();$child.WaitForExit()}
        $exit=$child.ExitCode;$stdout=$out.Result;$stderr=$err.Result
    } finally {
        if($started -and -not $child.HasExited){$child.Kill();$child.WaitForExit()}
        $child.Dispose()
    }
    [IO.File]::WriteAllText((Join-Path $run ($Phase+'.stdout.txt')),$stdout,$utf8)
    [IO.File]::WriteAllText((Join-Path $run ($Phase+'.stderr.txt')),$stderr,$utf8)
    $ok=-not $timedOut -and $exit -eq 0 -and $stderr.Length -eq 0 -and $stdout -notmatch '(?im)SCRIPT ERROR|ERROR:|WARNING:'
    [IO.File]::WriteAllText((Join-Path $run ($Phase+'.json')),([ordered]@{phase=$Phase;exit=$exit;ok=$ok;timed_out=$timedOut;engine_sha256=$sourceHash;stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($stderr);arguments=$Arguments}|ConvertTo-Json),$utf8)
    Write-Output $stdout.TrimEnd();if($stderr){Write-Output $stderr.TrimEnd()}
    if(-not $ok){throw ('Phase failed: '+$Phase+' exit='+$exit)}
    if($Phase -eq 'version' -and $stdout.Trim() -notmatch '\A4\.7\.2\.stable\.(steam|official)\.ed1daf0bf\z'){throw 'Only tested Godot 4.7.2 ed1daf0bf is accepted'}
}
$outcome='failure'
try {
    InvokeEngine 'version' '--version' 30000
    # A failed first cold import stops this run; never warm-import it into a pass.
    InvokeEngine 'cold-import' ('--headless --editor --import --path "'+$project+'"') 120000
    foreach($script in @('main.gd','vehicle.gd','vehicle_base.gd','acceptance.gd','track/harbor.gd','track/track_data.gd')){
        InvokeEngine ('parse-'+$script.Replace('/','-').Replace('.gd','')) ('--headless --path "'+$project+'" --check-only --script "res://'+$script+'"') 30000
    }
    if($Mode -eq 'Verify'){
        InvokeEngine 'physics' ('--headless --fixed-fps 60 --path "'+$project+'" -- --test=physics --evidence-dir="'+$run+'"') 120000
        InvokeEngine 'render' ('--path "'+$project+'" -- --test=render --evidence-dir="'+$run+'"') 120000
    }else{InvokeEngine 'play' ('--path "'+$project+'"') 0}
    $outcome='success'
} finally {
    # Immutable completed runs only; live runs and changed files cannot be pruned.
    # Keep receipts and full test result values in the light retention ledger.
    $summary=@{mode=$Mode;run=$RunName;sources=$hashes;results=@()}
    foreach($file in Get-ChildItem -LiteralPath $run -File -Filter '*.json'){
        if($file.Name -ne 'sources.json'){$summary.results+=@{file=$file.Name;value=(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Raw|ConvertFrom-Json)}}
    }
    $category='racing-offline-'+$Mode.ToLowerInvariant()
    Register-RoomKitArtifact -ProjectRoot $storageRoot -Category $category -Paths @($run) -Outcome $outcome -Summary $summary|Out-Null
    Invoke-RoomKitArtifactRetention -ProjectRoot $storageRoot -Category $category -Keep 2
}
} finally {$lease.Dispose()}
