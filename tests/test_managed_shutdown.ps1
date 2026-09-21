param([string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$testId = [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $project ('data\test-managed-shutdown-' + $testId)
$evidence = Join-Path $project ('logs\managed-shutdown-' + $testId)
New-Item -ItemType Directory -Path $evidence | Out-Null
& (Join-Path $project 'tools\protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot | Out-Null
$games = Get-Content -LiteralPath (Join-Path $project 'artifacts\framework-games.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$source = [IO.Path]::GetFullPath($games.shooter.project).TrimEnd('\')
$artifactRoot = Join-Path $project 'artifacts'
if (-not $source.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Only this project artifact can be copied.' }
$cursor = $source
while ($cursor.Length -ge $project.Length) {
    if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Artifact reparse point refused.' }
    $cursor = [IO.Path]::GetDirectoryName($cursor)
}
$files = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
if (@($files | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Artifact descendant reparse point refused.' }
# Each test owns its copied room project and server.log. Never launch into the
# generated artifact's shared log or overwrite public connection configuration.
$roomProject = Join-Path $testRoot 'shooter'
New-Item -ItemType Directory -Path $roomProject | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
    if ($item.Name -notin @('.godot', 'server.log')) { Copy-Item -LiteralPath $item.FullName -Destination $roomProject -Recurse }
}
$entry = @{project=$roomProject; manifest=$games.shooter.manifest}
$contextPath = Join-Path $testRoot 'test-context.json'
$context = @{root=$testRoot; evidence=$evidence; game=$entry}
[IO.File]::WriteAllText($contextPath, ($context | ConvertTo-Json -Depth 40 -Compress), (New-Object Text.UTF8Encoding($false)))
$arguments = @('--headless', '--path', $project, '--log-file', (Join-Path $evidence 'godot.log'), '--script', 'res://tests/run_managed_shutdown.gd', '--', ('--test-config=' + $contextPath))
$quoted = foreach ($argument in $arguments) { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
$process = Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'console.log') -RedirectStandardError (Join-Path $evidence 'stderr.log')
$ownedHandle = $process.Handle
if (-not $process.WaitForExit(180000)) {
    # Only the exact parent process HANDLE belongs to this harness. Its test has
    # an earlier shutdown deadline for its own managed host and room children.
    $process.Kill()
    $process.WaitForExit()
    throw 'Managed shutdown test watchdog expired; inspect retained evidence.'
}
$process.Refresh()
Get-Content -LiteralPath (Join-Path $evidence 'console.log') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $evidence 'stderr.log') -Encoding UTF8
Write-Output ('MANAGED_SHUTDOWN_EVIDENCE=' + $evidence)
Write-Output ('MANAGED_SHUTDOWN_EXIT=' + $process.ExitCode)
exit $process.ExitCode
