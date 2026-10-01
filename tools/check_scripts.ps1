param(
    # Scripts: one or more paths, separated by ';' (a single string, so that it
    # passes intact through powershell -File).
    [Parameter(Mandatory = $true)][string]$Scripts,
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$Project = ''
)
# Syntax check of GDScript files WITHOUT running them: Godot is started with
# --check-only, which parses the script and quits before _initialize. Service
# entry points (host/operator.gd, host/managed_host.gd, host/main.gd, ...) can be
# checked this way safely; this script never starts them for real.
# Exit code: 0 when every script parses, 1 otherwise.
$ErrorActionPreference = 'Stop'
if (-not $Project) { $Project = Split-Path -Parent $PSScriptRoot }
$Project = [IO.Path]::GetFullPath($Project)
if (-not (Test-Path -LiteralPath (Join-Path $Project 'project.godot'))) { throw 'Not a Godot project root.' }
$list = @($Scripts -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$failed = 0
foreach ($script in $list) {
    $resource = if ($script.StartsWith('res://')) { $script } else { 'res://' + ($script -replace '\\', '/').TrimStart('/') }
    $out = [IO.Path]::GetTempFileName()
    $err = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $Project, '--check-only', '--script', $resource) -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
        $null = $process.Handle
        if (-not $process.WaitForExit(60000)) { $process.Kill(); $code = 'TIMEOUT' } else { $code = $process.ExitCode }
        $errors = @(Get-Content $out, $err | Select-String -Pattern 'Parse Error|SCRIPT ERROR|Failed to load script')
        if ($code -ne 0 -or $errors.Count) {
            $failed++
            Write-Output ("FAIL {0} exit={1} {2}" -f $resource, $code, (($errors | Select-Object -First 3) -join ' | '))
        } else {
            Write-Output ("PASS {0} parses" -f $resource)
        }
    } finally {
        Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
    }
}
Write-Output ("CHECK_SCRIPTS_RESULT checked={0} failed={1} mode=check-only" -f $list.Count, $failed)
exit ([int]($failed -ne 0))
