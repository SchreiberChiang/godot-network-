param(
    [ValidateSet('Play','Physics','Render')][string]$Mode = 'Play',
    [ValidateSet('dev','final')][string]$Round = 'dev',
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifactRoot = Join-Path $projectRoot 'artifacts'
$root = if($Mode -eq 'Play') { Join-Path $artifactRoot 'racing-driving-play' } else { Join-Path $artifactRoot ('racing-driving-tests/' + $Round) }
if([IO.Path]::GetPathRoot($root) -ne 'F:\') { throw 'Driving lab output must remain on F drive.' }
function NoLinks([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while($cursor) {
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -Force -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Link refused: $cursor" }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}
NoLinks $root
function OutputPath([string]$Relative) {
    $target = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if(-not $target.StartsWith($root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Output escapes isolation: $target" }
    NoLinks $target
    return $target
}
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Godot is missing. Supply -Godot with the existing 4.7.2 executable.' }
[void][IO.Directory]::CreateDirectory($root)
$lease = [IO.File]::Open((OutputPath 'run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $sourceFiles = @('project.godot','main.tscn','main.gd','vehicle.gd','arena.gd','hud.gd','tests/acceptance.gd')
    $stage = Join-Path $root 'project'
    NoLinks $stage
    $encoding = New-Object Text.UTF8Encoding($false)
    $previousPath = OutputPath 'staged-sources.json'
    if(Test-Path -LiteralPath $previousPath) {
        $previousItems = Get-Content -LiteralPath $previousPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($item in $previousItems) {
            $oldFile = Join-Path $stage $item.path
            if(-not ([IO.Path]::GetFullPath($oldFile)).StartsWith($stage + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes staged project.' }
            NoLinks $oldFile
            if(-not (Test-Path -LiteralPath $oldFile -PathType Leaf) -or (Get-FileHash -LiteralPath $oldFile -Algorithm SHA256).Hash -ne $item.sha256) { throw "Staged source was modified; refusing overwrite: $oldFile" }
        }
    } elseif(Test-Path -LiteralPath $stage) { throw 'Unowned staged project exists.' }
    $hashes = @()
    foreach($relative in $sourceFiles) {
        $source = Join-Path $PSScriptRoot $relative
        $destination = Join-Path $stage $relative
        NoLinks $source
        NoLinks $destination
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $hashes += [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}
    }
    [IO.File]::WriteAllText($previousPath,($hashes | ConvertTo-Json -Depth 4),$encoding)
    $attempt = 1
    while(Test-Path -LiteralPath (Join-Path $root ('attempt-{0:d2}.json' -f $attempt))) { $attempt++ }
    $tag = 'attempt-{0:d2}' -f $attempt
    $evidence = OutputPath 'evidence'
    [void][IO.Directory]::CreateDirectory($evidence)
    foreach($name in @('report.json','circle.png','ramp.png')) { [void](OutputPath ('evidence/' + $name)) }
    # Preserve lightweight prior results, not another generated project/cache.
    $priorReport = Join-Path $evidence 'report.json'
    if(Test-Path -LiteralPath $priorReport) {
        Copy-Item -LiteralPath $priorReport -Destination (OutputPath ($tag + '.prior-report.json'))
    }
    $envDirs = @{HOME='home';USERPROFILE='home';APPDATA='appdata';LOCALAPPDATA='localappdata';TEMP='tmp';TMP='tmp';XDG_CONFIG_HOME='xdg-config';XDG_DATA_HOME='xdg-data';XDG_CACHE_HOME='xdg-cache'}
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Item -LiteralPath $Godot).FullName
    $info.Arguments = '--path "' + $stage + '"'
    if($Mode -eq 'Physics') { $info.Arguments = '--headless --fixed-fps 60 ' + $info.Arguments }
    if($Mode -ne 'Play') { $info.Arguments += ' -- --test=' + $Mode.ToLowerInvariant() + ' --evidence-dir="' + $evidence + '"' }
    $info.WorkingDirectory = $stage
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach($key in $envDirs.Keys) {
        $value = Join-Path $root $envDirs[$key]
        NoLinks $value
        [void][IO.Directory]::CreateDirectory($value)
        $info.EnvironmentVariables[$key] = $value
    }
    $info.EnvironmentVariables['RACING_DRIVING_ISOLATION'] = $root
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $childId = $process.Id
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timeout = $false
    if($Mode -eq 'Play') { $process.WaitForExit() }
    elseif(-not $process.WaitForExit(120000)) { $timeout=$true; $process.Kill(); $process.WaitForExit() }
    $engineExit = $process.ExitCode
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $process.Dispose()
    [IO.File]::WriteAllText((OutputPath ($tag+'.stdout.log')),$stdout,$encoding)
    [IO.File]::WriteAllText((OutputPath ($tag+'.stderr.log')),$stderr,$encoding)
    $success = -not $timeout -and $engineExit -eq 0 -and [string]::IsNullOrWhiteSpace($stderr) -and $stdout -notmatch '(?im)ERROR:|WARNING:|SCRIPT ERROR'
    if($Mode -ne 'Play') { $success = $success -and $stdout -match '(?m)^DRIVING_RESULT passed=[1-9]\d* failed=0\s*$' }
    $receipt = [ordered]@{mode=$Mode;round=$Round;success=$success;engine_exit=$engineExit;timed_out=$timeout;process_id=$childId;executable=$info.FileName;arguments=$info.Arguments;stderr_bytes=[Text.Encoding]::UTF8.GetByteCount($stderr);sources=$hashes;launcher_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;engine_sha256=(Get-FileHash -LiteralPath $info.FileName -Algorithm SHA256).Hash}
    [IO.File]::WriteAllText((OutputPath ($tag+'.json')),($receipt | ConvertTo-Json -Depth 6),$encoding)
    Write-Output $stdout.TrimEnd()
    if($stderr) { Write-Output $stderr.TrimEnd() }
    Write-Output "DRIVING_EVIDENCE=$root ENGINE_EXIT=$engineExit SUCCESS=$success"
    if(-not $success) { exit 1 }
} finally { $lease.Dispose() }
exit 0
