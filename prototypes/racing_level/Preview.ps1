param([ValidateSet('Preview','Validate','Capture')][string]$Mode = 'Preview')
$ErrorActionPreference = 'Stop'
$engine = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$project = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Required Godot 4.7.2 missing: $engine" }
if (-not $project.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) { throw 'This preview requires an F: project directory.' }
if (-not (Test-Path -LiteralPath (Join-Path $project 'project.godot'))) { throw 'Standalone project missing.' }
# Keep only the latest two completed runs per purpose. Summaries/logs survive.
function Remove-OlderOwnedRuns {
    param([string]$Purpose)
    $artifactRoot = [IO.Path]::GetFullPath((Join-Path $project 'artifacts'))
    $prefix = $artifactRoot.TrimEnd('\') + '\'
    $runs = @(Get-ChildItem -LiteralPath $artifactRoot -Directory | Where-Object { $_.Name -match ('^' + $Purpose.ToLowerInvariant() + '-\d{8}-\d{6}-\d{3}$') } | Sort-Object Name -Descending)
    foreach ($old in @($runs | Select-Object -Skip 2)) {
        $absolute = [IO.Path]::GetFullPath($old.FullName)
        if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Retention path outside preview artifacts.' }
        $receiptPath = Join-Path $absolute 'run.json'
        if (-not (Test-Path -LiteralPath $receiptPath)) { Write-Warning "Retaining incomplete/unowned run: $absolute"; continue }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($receipt.project -ne $project -or $receipt.engine -ne $engine -or $receipt.mode -ne $Purpose) { throw "Run ownership mismatch: $absolute" }
        $entries = @($old) + @(Get-ChildItem -LiteralPath $absolute -Recurse -Force)
        if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -ne 0) { throw "Retention refuses linked path: $absolute" }
        $active = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $engine -and $_.CommandLine -and $_.CommandLine.Contains($absolute) })
        if ($active.Count -ne 0) { Write-Warning "Retaining active run: $absolute"; continue }
        $history = Join-Path $artifactRoot ('history\' + $old.Name)
        [IO.Directory]::CreateDirectory($history) | Out-Null
        $manifest = @(Get-ChildItem -LiteralPath $absolute -Recurse -File | ForEach-Object { [ordered]@{path=$_.FullName.Substring($absolute.Length+1); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $history 'removed-files.json') -Encoding UTF8
        foreach ($name in @('run.json','stdout.txt','stderr.txt','engine.log','validation.json')) {
            $source = Join-Path $absolute $name
            if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $history $name) }
        }
        # All needed lightweight evidence is now under history/<run>/.
        Remove-Item -LiteralPath $absolute -Recurse -Force
        Write-Output "RETAINED_SUMMARY=$history"
    }
}
$runRoot = Join-Path $project ('artifacts\' + $Mode.ToLowerInvariant() + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $engine
$psi.WorkingDirectory = $project
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
foreach ($entry in @{APPDATA='roaming'; LOCALAPPDATA='local'; TEMP='temp'; TMP='temp'; USERPROFILE='profile'; HOME='profile'; XDG_CONFIG_HOME='config'; XDG_DATA_HOME='data'; XDG_CACHE_HOME='cache'}.GetEnumerator()) {
    $dir = Join-Path $runRoot $entry.Value
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $psi.EnvironmentVariables[$entry.Key] = $dir
}
$log = Join-Path $runRoot 'engine.log'
$arguments = '--path "' + $project + '" --log-file "' + $log + '" '
if ($Mode -eq 'Validate') { $arguments += '--headless --script res://validate.gd -- --out="' + $runRoot + '"' }
elseif ($Mode -eq 'Capture') { $arguments += '-- --out="' + $runRoot + '"' }
$psi.Arguments = $arguments
$process = New-Object Diagnostics.Process
$process.StartInfo = $psi
if (-not $process.Start()) { throw 'Godot start failed.' }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = $false
if ($Mode -eq 'Preview') { $process.WaitForExit() }
elseif (-not $process.WaitForExit(120000)) {
    $timedOut = $true
    # This exact Process handle was created above, never a name-based kill.
    $process.Kill()
    $process.WaitForExit()
}
$code = $process.ExitCode
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
[IO.File]::WriteAllText((Join-Path $runRoot 'stdout.txt'), $stdout)
[IO.File]::WriteAllText((Join-Path $runRoot 'stderr.txt'), $stderr)
$record = [ordered]@{mode=$Mode; engine=$engine; project=$project; arguments=$arguments; exit_code=$code; timed_out=$timedOut; process_id=$process.Id; run_directory=$runRoot; stderr_empty=($stderr.Length -eq 0); isolated_environment=@{APPDATA=$psi.EnvironmentVariables['APPDATA']; LOCALAPPDATA=$psi.EnvironmentVariables['LOCALAPPDATA']; TEMP=$psi.EnvironmentVariables['TEMP']; USERPROFILE=$psi.EnvironmentVariables['USERPROFILE']}}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'run.json') -Encoding UTF8
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
Write-Output "RUN_DIRECTORY=$runRoot"
Write-Output "ENGINE_EXIT_CODE=$code"
Remove-OlderOwnedRuns -Purpose $Mode
if ($code -eq 0 -and ($stdout -match 'SCRIPT ERROR:|ERROR:' -or $stderr -match 'SCRIPT ERROR:|ERROR:')) { exit 3 }
exit $code
