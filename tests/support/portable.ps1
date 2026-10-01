# Shared by the PowerShell test drivers so one driver runs under Windows
# PowerShell 5.1 and under pwsh on Linux (dot-source it). Only platform plumbing
# lives here: default engine path, private test folders, hidden child processes
# and the PowerShell used for fixture scripts. No test logic.
$script:RkPosix=[IO.Path]::DirectorySeparatorChar -eq '/'

## The engine for this platform: -Godot when given, else ROOMKIT_GODOT on Linux
## (the Linux scripts always set it) or the Windows development install.
function Rk-Godot([string]$Requested) {
    if ($Requested) { return $Requested }
    if ($script:RkPosix) {
        if (-not $env:ROOMKIT_GODOT) { throw 'Set ROOMKIT_GODOT to the installed Linux engine.' }
        return $env:ROOMKIT_GODOT
    }
    return 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
}

## PowerShell for fixture scripts: this same pwsh on Linux, powershell.exe on Windows.
function Rk-PowerShell {
    if ($script:RkPosix) { return (Get-Process -Id $PID).Path }
    return 'powershell.exe'
}

## A private test data folder inside <project>/data. Windows: tools/protect_data.ps1
## (owner-only ACL). Linux: every folder from data down to it becomes 700.
function Rk-ProtectData([string]$Project,[string]$Root) {
    if (-not $script:RkPosix) { & (Join-Path $Project 'tools/protect_data.ps1') -ProjectRoot $Project -DataRoot $Root | Out-Null; return }
    $data=[IO.Path]::GetFullPath((Join-Path $Project 'data')).TrimEnd('/')
    $full=[IO.Path]::GetFullPath($Root).TrimEnd('/')
    if (-not $full.StartsWith($data+'/',[StringComparison]::Ordinal)) { throw 'Test data folder outside the project data folder.' }
    $folders=@($data)
    foreach($segment in $full.Substring($data.Length+1).Split('/')) { $folders+=($folders[-1]+'/'+$segment) }
    foreach($folder in $folders) {
        if ((Test-Path -LiteralPath $folder) -and $null -ne (Get-Item -LiteralPath $folder -Force).LinkTarget) { throw 'Test data folder passes through a link.' }
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::SetUnixFileMode($folder,[IO.UnixFileMode]'UserRead,UserWrite,UserExecute')
    }
}

## res://run for launch files. Windows: tools/protect_runtime.ps1. Linux: 700
## with its .gdignore marker 600 (the Operator applies the same on start).
function Rk-ProtectRuntime([string]$Project) {
    if (-not $script:RkPosix) { & (Join-Path $Project 'tools/protect_runtime.ps1') -ProjectRoot $Project | Out-Null; return }
    $runtime=Join-Path $Project 'run'
    [void][IO.Directory]::CreateDirectory($runtime)
    [IO.File]::SetUnixFileMode($runtime,[IO.UnixFileMode]'UserRead,UserWrite,UserExecute')
    $marker=Join-Path $runtime '.gdignore'
    if (-not [IO.File]::Exists($marker)) { [IO.File]::WriteAllText($marker,'') }
    [IO.File]::SetUnixFileMode($marker,[IO.UnixFileMode]'UserRead,UserWrite')
}

## Starts a background child with redirected output and returns the Process.
## Windows hides its window; Linux has none (-WindowStyle is Windows only).
function Rk-StartHidden([string]$FilePath,$Arguments,[string]$Stdout,[string]$Stderr) {
    $quoted=foreach($argument in $Arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    # Linux: bash opens the two files and execs the program (same pid). pwsh's own
    # redirection copies the output through a pipe on a thread pool handler; when
    # a killed child's descendants still hold that pipe, the handler writes to a
    # closed writer and the whole pwsh process aborts (seen in the L3 fault test).
    if ($script:RkPosix) {
        # ArgumentList passes each argument as is (no command-line quoting).
        $info=New-Object Diagnostics.ProcessStartInfo '/bin/bash'
        $info.UseShellExecute=$false
        foreach($argument in @('-c','out=$1; err=$2; shift 2; exec "$@" > "$out" 2> "$err" < /dev/null','rk-start',$Stdout,$Stderr,$FilePath)+@($Arguments)) { $info.ArgumentList.Add([string]$argument) }
        return [Diagnostics.Process]::Start($info)
    }
    else { $process=Start-Process -FilePath $FilePath -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr }
    $null=$process.Handle
    return $process
}

## True when $Path lies inside $Parent (platform case rules).
function Rk-Inside([string]$Path,[string]$Parent) {
    $sep=[string][IO.Path]::DirectorySeparatorChar
    $comparison=if ($script:RkPosix) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
    return ([IO.Path]::GetFullPath($Path)).StartsWith(([IO.Path]::GetFullPath($Parent)).TrimEnd('\','/')+$sep,$comparison)
}
