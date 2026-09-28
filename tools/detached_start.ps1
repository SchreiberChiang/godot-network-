param(
    [Parameter(Mandatory=$true)][string]$Request
)
# Starts one program so it is not attached to the caller's visible console.
# Godot's Windows build attaches to its parent's console; when the user closed
# the StartManagement window, Windows sent a console control event and the
# operator was terminated without its shutdown routine. The caller launches
# this script with Start-Process -WindowStyle Hidden (a new, hidden console
# that nobody can close); the program started here inherits that console.
# The request JSON holds file_path, arguments[], working_directory, stdout,
# stderr, optional window_style (default Hidden) and result (where the child's pid and start time are written).
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
$spec=Get-Content -Encoding UTF8 -Raw -LiteralPath $Request | ConvertFrom-Json
$quoted=foreach($argument in @($spec.arguments)) { '"'+([string]$argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
$options=@{FilePath=[string]$spec.file_path;ArgumentList=$quoted;WorkingDirectory=[string]$spec.working_directory;PassThru=$true;WindowStyle=$(if($spec.window_style){[string]$spec.window_style}else{'Hidden'})}
if($spec.stdout) { $options.RedirectStandardOutput=[string]$spec.stdout }
if($spec.stderr) { $options.RedirectStandardError=[string]$spec.stderr }
try {
    $process=Start-Process @options
    $result=@{ok=$true;pid=$process.Id;start_time_utc=$process.StartTime.ToUniversalTime().ToString('o')}
} catch {
    $result=@{ok=$false;error=$_.Exception.Message}
}
$temporary=[string]$spec.result+'.tmp'
[IO.File]::WriteAllText($temporary,($result|ConvertTo-Json -Compress),$utf8)
Move-Item -LiteralPath $temporary -Destination ([string]$spec.result) -Force
