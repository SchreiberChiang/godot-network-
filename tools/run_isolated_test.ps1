param(
    [Parameter(Mandatory = $true)][string]$Script,
    # A NEW folder for this run, inside the project's data folder. It must not
    # exist yet; this script creates it. Test data, game index, public client
    # configuration and the log must all be inside it.
    [Parameter(Mandatory = $true)][string]$Isolation,
    # Log file prefix (<Log>.stdout / <Log>.stderr), inside -Isolation.
    [Parameter(Mandatory = $true)][string]$Log,
    # Arguments for the test after '--', separated by ';' (one string, so that
    # values like --data-root=... pass intact through powershell -File).
    [string]$TestArgs = '',
    # Files copied (read-only source) into the new isolation folder before the
    # run, separated by ';' (for example a game index the test must not share).
    [string]$CopyIn = '',
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$Project = '',
    [int]$TimeoutSeconds = 1800
)
# Runs ONE test script with the engine, refusing anything that could start a
# service against real data. Exit 64 = refused before anything was started.
#  - Every path is normalised first (res:// mapped to the project, '.' and '..'
#    resolved); a path that contains a '..' segment, or whose existing part
#    passes through a symbolic link or junction, is refused.
#  - Only scripts under res://tests/ run. Service entry points are only
#    syntax-checked, by tools/check_scripts.ps1.
#  - A script is "service-like" when the script, anything it extends (quoted
#    path, relative path or class_name, followed to the end) or anything those
#    preload/load, mentions a service entry point (host/operator.gd,
#    host/managed_host.gd, host/main.gd, Operator.exe, ManagedHost.exe). An
#    extends target that cannot be resolved and is not a known engine class is
#    refused. Service-like tests need --data-root, --games and
#    --public-client-dir inside -Isolation and an explicit --panel-port other
#    than 28291; every path-like argument of theirs must be inside -Isolation.
$ErrorActionPreference = 'Stop'
if (-not $Project) { $Project = Split-Path -Parent $PSScriptRoot }
$Project = [IO.Path]::GetFullPath($Project).TrimEnd('\')
$ServicePattern = 'host/operator\.gd|host/managed_host\.gd|host/main\.gd|host/main\.tscn|Operator\.exe|ManagedHost\.exe'
$EngineClasses = @('SceneTree', 'MainLoop', 'Object', 'RefCounted', 'Reference', 'Resource', 'Node', 'Node2D', 'Node3D', 'Control', 'CanvasItem', 'CanvasLayer')

function Refuse([string]$Reason) { $script:runnerExitCode=64; Write-Output ('REFUSED ' + $Reason); exit 64 }

# res://... or a plain path -> normalised absolute path; refuses '..' segments.
function Resolve-Checked([string]$Value, [string]$What) {
    $raw = $Value -replace '\\', '/'
    if ($raw -match '(^|/)\.\.(/|$)') { Refuse "$What '$Value' contains a '..' segment" }
    $mapped = if ($raw.StartsWith('res://')) { Join-Path $Project ($raw.Substring(6)) } else { $raw }
    return [IO.Path]::GetFullPath($mapped).TrimEnd('\')
}
function Test-Inside([string]$Path, [string]$Root) {
    return $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)
}
# Every existing component from the drive root down must be a plain folder/file.
function Assert-NoLink([string]$Path, [string]$What) {
    $cursor = $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { Refuse "$What passes through a link or junction ($cursor)" }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

# ---- the script ----
$scriptPath = Resolve-Checked $Script 'script'
$tests = Join-Path $Project 'tests'
if (-not (Test-Inside $scriptPath $tests) -or -not $scriptPath.EndsWith('.gd')) { Refuse "$Script is not a test script under res://tests/ (service entry points are only syntax-checked by tools/check_scripts.ps1)" }
Assert-NoLink $scriptPath 'script'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { Refuse "$Script does not exist" }
$resource = 'res://' + ($scriptPath.Substring($Project.Length + 1) -replace '\\', '/')

# ---- the isolation folder ----
$dataRoot = Join-Path $Project 'data'
$isolationPath = Resolve-Checked $Isolation 'isolation folder'
if (-not (Test-Inside $isolationPath $dataRoot) -or $isolationPath -eq $dataRoot -or (Test-Inside $isolationPath (Join-Path $dataRoot 'framework'))) { Refuse "isolation folder must be a new folder inside data/ (not data/ itself or data/framework)" }
Assert-NoLink $isolationPath 'isolation folder'
if (Test-Path -LiteralPath $isolationPath) { Refuse "isolation folder already exists (it must be new for this run, nothing shared)" }
$logPath = Resolve-Checked $Log 'log'
if (-not (Test-Inside $logPath $isolationPath)) { Refuse "log '$Log' is outside the isolation folder" }

# ---- service detection: extends chain and preload/load closure ----
$classMap = @{}
foreach ($top in Get-ChildItem -LiteralPath $Project -Directory -Force) {
    if ($top.Name -in @('.godot', 'data', 'run', 'logs', 'artifacts', 'release', 'PlayerClient', 'prototypes') -or ($top.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $top.FullName -Recurse -Filter '*.gd' -File -Force -ErrorAction SilentlyContinue) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($file.FullName), '(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)')) { $classMap[$match.Groups[1].Value] = $file.FullName }
    }
}
$seen = @{}
$queue = New-Object Collections.Queue
$queue.Enqueue($scriptPath)
$serviceLike = $false
$reasons = @()
while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    if ($seen.ContainsKey($current.ToLowerInvariant())) { continue }
    $seen[$current.ToLowerInvariant()] = $true
    if ($seen.Count -gt 400) { Refuse "dependency closure of $resource is too large to check" }
    if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { Refuse "dependency '$current' of $resource does not exist" }
    Assert-NoLink $current 'dependency'
    $text = [IO.File]::ReadAllText($current)
    if ($text -match $ServicePattern) { $serviceLike = $true; $reasons += ($current.Substring($Project.Length + 1)) }
    $base = [IO.Path]::GetDirectoryName($current)
    foreach ($match in [regex]::Matches($text, '(?m)^\s*extends\s+(?:"([^"]+)"|''([^'']+)''|([A-Za-z_][A-Za-z0-9_\.]*))')) {
        $quoted = if ($match.Groups[1].Success) { $match.Groups[1].Value } elseif ($match.Groups[2].Success) { $match.Groups[2].Value } else { '' }
        if ($quoted) {
            $target = if ($quoted.StartsWith('res://')) { Resolve-Checked $quoted 'extends target' } else { if ($quoted -match '(^|/)\.\.(/|$)') { Refuse "extends target '$quoted' contains a '..' segment" }; [IO.Path]::GetFullPath((Join-Path $base $quoted)) }
            if (-not (Test-Inside $target $Project)) { Refuse "extends target '$quoted' is outside the project" }
            $queue.Enqueue($target)
        } else {
            $name = $match.Groups[3].Value.Split('.')[0]
            if ($classMap.ContainsKey($name)) { $queue.Enqueue($classMap[$name]) }
            elseif ($EngineClasses -notcontains $name) { Refuse "cannot resolve the base class '$name' of $($current.Substring($Project.Length + 1)); it is neither a project class_name nor a known engine class" }
        }
    }
    foreach ($match in [regex]::Matches($text, '(?:preload|load)\(\s*"(res://[^"]+\.gd)"\s*\)')) {
        $queue.Enqueue((Resolve-Checked $match.Groups[1].Value 'preloaded script'))
    }
}

# ---- arguments ----
$arguments = @($TestArgs -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$values = @{}
foreach ($argument in $arguments) {
    $pair = $argument -split '=', 2
    # A test may read every occurrence of an argument (for example write one file
    # per --games), so a second occurrence is refused, never "last one wins".
    if ($values.ContainsKey($pair[0])) { Refuse "argument $($pair[0]) is given more than once" }
    $values[$pair[0]] = if ($pair.Count -eq 2) { $pair[1] } else { $null }
}
if ($values.ContainsKey('--isolation')) { Refuse 'argument --isolation is set by this script from -Isolation, not by the caller' }
# Path arguments are checked by NAME, whatever their value looks like: empty,
# relative or bare file names are refused, others must be inside -Isolation.
foreach ($key in '--data-root', '--games', '--public-client-dir', '--operator-log-path') {
    if (-not $values.ContainsKey($key)) { continue }
    $value = [string]$values[$key]
    if ($value -eq '') { Refuse "argument $key is empty" }
    if (-not ($value.StartsWith('res://') -or ($value -match '^[A-Za-z]:[\\/]'))) { Refuse "argument $key='$value' must be an absolute or res:// path" }
    $path = Resolve-Checked $value "argument $key"
    if (-not (Test-Inside $path $isolationPath) -or $path -eq $isolationPath) { Refuse "argument $key='$value' is outside the isolation folder" }
}
if ($serviceLike) {
    foreach ($key in '--data-root', '--games', '--public-client-dir') {
        if (-not $values.ContainsKey($key)) { Refuse "$resource runs the Operator or a managed host (via $($reasons -join ', ')) and needs $key inside the isolation folder" }
    }
    if (-not $values.ContainsKey('--panel-port') -or $values['--panel-port'] -notmatch '^\d{4,5}$' -or [int]$values['--panel-port'] -eq 28291 -or [int]$values['--panel-port'] -gt 65535) { Refuse "$resource needs an explicit --panel-port (1000-65535) other than the production 28291" }
    foreach ($key in @($values.Keys)) {
        $value = [string]$values[$key]
        if ($value -match '[\\/]' -or $value.StartsWith('res://')) {
            $path = Resolve-Checked $value "argument $key"
            if (-not (Test-Inside $path $isolationPath)) { Refuse "argument $key='$value' is outside the isolation folder" }
        }
    }
}

# ---- run ----
$copies = @($CopyIn -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($source in $copies) {
    $from = Resolve-Checked $source 'copied file'
    Assert-NoLink $from 'copied file'
    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { Refuse "file to copy '$source' does not exist" }
}
$retentionManaged=([IO.Path]::GetDirectoryName($isolationPath) -ieq $dataRoot -and [IO.Path]::GetFileName($isolationPath) -match '^(test-|isolated-|acceptance-|retention-test-).+')
if($retentionManaged){
    . (Join-Path $PSScriptRoot 'artifact_retention.ps1')
    New-RoomKitArtifactTestRoot -ProjectRoot $Project -Path $isolationPath|Out-Null
}else{
    [void][IO.Directory]::CreateDirectory($isolationPath)
    Write-Output 'ARTIFACT_RETENTION_UNMANAGED legacy_or_nested_isolation_name'
}
$script:runnerExitCode=1
$process=$null;$confirmedStopped=$true;$timedOut=$false
try{
    foreach ($source in $copies) {
        $from = Resolve-Checked $source 'copied file'
        $to = Join-Path $isolationPath ([IO.Path]::GetFileName($from))
        if (Test-Path -LiteralPath $to) { Refuse "two files to copy share the name $([IO.Path]::GetFileName($from))" }
        Copy-Item -LiteralPath $from -Destination $to
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($logPath))
    $argumentList = @('--headless', '--path', $Project, '--script', $resource, '--', ('--isolation=' + $isolationPath)) + $arguments
    Write-Output ("RUN {0} service_like={1} isolation={2}" -f $resource, $serviceLike, $isolationPath)
    # Keep the established argument behavior; this retention change does not
    # change command-line encoding or the test's arguments.
    $process = Start-Process -FilePath $Godot -ArgumentList $argumentList -RedirectStandardOutput ($logPath + '.stdout') -RedirectStandardError ($logPath + '.stderr') -NoNewWindow -PassThru
    $null = $process.Handle
    $confirmedStopped=$false
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut=$true;$script:runnerExitCode=124
        try{$process.Kill();$confirmedStopped=$process.WaitForExit(3000)}catch{$confirmedStopped=$process.HasExited}
        Write-Output 'exit=TIMEOUT'
    }else{
        $confirmedStopped=$true;$script:runnerExitCode=$process.ExitCode
        Write-Output ('exit=' + $script:runnerExitCode)
    }
}finally{
    if($null -ne $process){
        try{if($process.HasExited){$confirmedStopped=$true}}catch{}
        $process.Dispose()
    }
    if($retentionManaged -and $confirmedStopped){
        try{
            $counts=@()
            if(Test-Path -LiteralPath ($logPath+'.stdout') -PathType Leaf){
                $text=[IO.File]::ReadAllText($logPath+'.stdout')
                foreach($match in [regex]::Matches($text,'(?m)\b([A-Z][A-Z0-9_]*_RESULT)\s+passed=(\d+)\s+failed=(\d+)')){
                    $counts+=@{suite=$match.Groups[1].Value;passed=[int]$match.Groups[2].Value;failed=[int]$match.Groups[3].Value}
                    if($counts.Count -gt 32){$counts=@($counts|Select-Object -Last 32)}
                }
            }
            $name=[IO.Path]::GetFileNameWithoutExtension($scriptPath).ToLowerInvariant() -replace '[^a-z0-9.-]','-'
            $category='isolated-test-'+$name
            if($category.Length -gt 64){$category=$category.Substring(0,64)}
            $outcome=if($script:runnerExitCode -eq 0){'success'}else{'failure'}
            $summary=@{script=$resource;exit_code=$script:runnerExitCode;timed_out=$timedOut;process_confirmed_stopped=$confirmedStopped;counts=$counts;stdout=($logPath+'.stdout');stderr=($logPath+'.stderr');failure_code=$(if($timedOut){'TEST_TIMEOUT'}elseif($script:runnerExitCode -ne 0){'TEST_NONZERO_EXIT'}else{''})}
            Register-RoomKitArtifact -ProjectRoot $Project -Category $category -Paths @($isolationPath) -Outcome $outcome -Summary $summary|Out-Null
            Invoke-RoomKitArtifactRetention -ProjectRoot $Project -Category $category|Out-Null
        }catch{Write-Warning 'ARTIFACT_RETENTION_SKIPPED test_registration_or_cleanup_failed'}
    }elseif($retentionManaged){Write-Warning 'ARTIFACT_RETENTION_SKIPPED test_process_not_confirmed_stopped'}
}
exit $script:runnerExitCode
