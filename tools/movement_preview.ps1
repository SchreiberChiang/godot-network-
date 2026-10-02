param(
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [ValidateRange(0, 86400)][double]$Seconds = 0,
    [string]$Screenshot = '',
    [ValidateSet('stable', 'jitter', 'outage')][string]$Scenario = 'stable',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$revision = 'bc4f75f77e5521795becc20d3f277a44fb279d97'
$previewRoot = Join-Path $project 'data\preview-movement'
$baselineRoot = Join-Path $previewRoot ('baseline-' + $revision.Substring(0, 12))
$runtimeRoot = Join-Path $previewRoot 'runtime'

function Assert-LocalPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($project + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Preview output escapes project: $absolute"
    }
    $current = $absolute
    while ($current -and $current -ne $project) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Preview output follows a link: $current" }
        }
        $current = Split-Path -Parent $current
    }
}

function Ensure-LocalDirectory([string]$Path) {
    Assert-LocalPath $Path
    $null = [IO.Directory]::CreateDirectory($Path)
}

function Read-GitBlob([string]$Source) {
    # Capture raw bytes: text redirection in Windows PowerShell would change
    # encoding and newlines, so the baseline would no longer match the commit.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command git -ErrorAction Stop).Source
    $info.Arguments = 'show ' + $revision + ':' + $Source
    $info.WorkingDirectory = $project
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $buffer = New-Object IO.MemoryStream
    try {
        $null = $process.Start()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $process.WaitForExit()
        $gitError = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Fixed baseline unavailable: $Source $gitError" }
        return ,$buffer.ToArray()
    } finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Quote-PreviewArguments($Values) {
    # Windows command-line quoting preserves Unicode/spaces, embedded quotes
    # and trailing backslashes; PowerShell 5.1 has no ProcessStartInfo.ArgumentList.
    foreach ($value in $Values) {
        '"' + ([string]$value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }
}

# One immutable baseline plus one reused runtime directory. There are no
# per-run builds/copies or growing histories, and no deletion of prior data.
Ensure-LocalDirectory $baselineRoot
$hashes = @{}
foreach ($name in @('game.gd', 'game_config.json')) {
    $bytes = Read-GitBlob ('examples/shooter/' + $name)
    $expected = Get-BytesHash $bytes
    $destination = Join-Path $baselineRoot $name
    Assert-LocalPath $destination
    if (-not (Test-Path -LiteralPath $destination)) { [IO.File]::WriteAllBytes($destination, $bytes) }
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Baseline hash mismatch; preserving existing file: $destination" }
    $hashes[$name] = $actual
}
$baselineResource = 'res://data/preview-movement/baseline-' + $revision.Substring(0, 12) + '/game.gd'
$manifest = [ordered]@{
    revision = $revision
    scope = 'offline_synthetic_snapshots_no_network'
    baseline_script = $baselineResource
    baseline_sha256 = $hashes['game.gd']
    baseline_config_sha256 = $hashes['game_config.json']
    candidate_sha256 = (Get-FileHash -LiteralPath (Join-Path $project 'examples\shooter\game.gd') -Algorithm SHA256).Hash.ToLowerInvariant()
}
Write-Output ('MOVEMENT_PREVIEW_PREPARED ' + ($manifest | ConvertTo-Json -Compress))
if ($PrepareOnly) { exit 0 }
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot development engine not found: $Godot" }

$arguments = @('--path', $project, '--script', 'res://tests/run_movement_preview.gd', '--',
    ('--baseline-script=' + $baselineResource), ('--baseline-sha256=' + $hashes['game.gd']),
    ('--baseline-config-sha256=' + $hashes['game_config.json']), ('--scenario=' + $Scenario))
if ($Seconds -gt 0) { $arguments += '--seconds=' + $Seconds.ToString([Globalization.CultureInfo]::InvariantCulture) }
if ($Screenshot) {
    if (-not [IO.Path]::IsPathRooted($Screenshot)) { $Screenshot = Join-Path $project $Screenshot }
    $Screenshot = [IO.Path]::GetFullPath($Screenshot)
    Assert-LocalPath $Screenshot
    Ensure-LocalDirectory (Split-Path -Parent $Screenshot)
    $arguments += '--screenshot=' + $Screenshot
}
$savedEnvironment = @{}
$engineProcess = $null
$engineExit = 1
try {
    foreach ($key in @('APPDATA', 'LOCALAPPDATA', 'TMP', 'TEMP', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        $path = Join-Path $runtimeRoot $key.ToLowerInvariant()
        Ensure-LocalDirectory $path
        [Environment]::SetEnvironmentVariable($key, $path, 'Process')
    }
    $quotedArguments = @(Quote-PreviewArguments $arguments)
    # This process is the requested interactive preview, so its window is visible.
    $engineProcess = Start-Process -FilePath $Godot -WorkingDirectory $project -ArgumentList $quotedArguments -WindowStyle Normal -PassThru
    # Retain the handle immediately, including for a very short-lived GUI process.
    $null = $engineProcess.Handle
    $engineProcess.WaitForExit()
    $engineExit = $engineProcess.ExitCode
} finally {
    if ($null -ne $engineProcess) { $engineProcess.Dispose() }
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process') }
}
exit $engineExit
