param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Read-only Windows source dependency check. Keeps system Windows PowerShell 5.1;
# installs nothing, starts no service, and changes no configuration or data.
$ErrorActionPreference='Stop'
try {
    if($env:OS -ne 'Windows_NT'){throw 'This entry checks Windows; Linux uses PrepareEnvironment.sh check.'}
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Run CheckEnvironment.cmd with system Windows PowerShell 5.1.'}
    if(-not(Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32/winsqlite3.dll') -PathType Leaf)){throw 'System winsqlite3.dll is missing; no installation was attempted.'}
    if(-not[IO.Path]::IsPathRooted($Godot) -or -not(Test-Path -LiteralPath $Godot -PathType Leaf)){throw 'Godot 4.7.2 was not found; pass -Godot with its absolute executable path.'}
    $version=(& $Godot --headless --version | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable\.(steam|official)\.ed1daf0bf$'){throw 'Godot must be the tested 4.7.2 ed1daf0bf build.'}
    Write-Output ('FOUND godot='+$version)
    Write-Output 'FOUND powershell=5.1 sqlite=system-winsqlite3.dll'
    Write-Output 'ROOMKIT_ENVIRONMENT_READY kind=windows-source (no service started)'
    exit 0
} catch {
    Write-Output ('ROOMKIT_ENVIRONMENT_FAILED '+$_.Exception.Message)
    exit 2
}
