param([switch]$CheckOnly)
# Opens only a locally prepared, verified clean delivery. No service or SSH.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
function Local([string]$Relative){
    if(-not $Relative.StartsWith('artifacts/') -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Refused deployment pointer path.'}
    $full=[IO.Path]::GetFullPath((Join-Path $project $Relative))
    if(-not $full.StartsWith($project+'\artifacts\',[StringComparison]::OrdinalIgnoreCase)){throw 'Refused deployment path.'}
    $cursor=$full
    while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked deployment path.'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent}
    return $full
}
$pointer=Local 'artifacts/deployment-latest.json'
if(-not(Test-Path -LiteralPath $pointer -PathType Leaf)){throw 'PrepareDeployment.cmd has not prepared a delivery on this computer.'}
$saved=Get-Content -LiteralPath $pointer -Encoding UTF8 -Raw|ConvertFrom-Json
if($saved.format -ne 1 -or $saved.manifest_sha256 -notmatch '^[0-9a-f]{64}$'){throw 'Invalid deployment pointer.'}
$directory=Local ([string]$saved.directory)
$manifest=Local ($saved.directory+'/deployment.json')
if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine $saved.manifest_sha256){throw 'Prepared delivery identity changed.'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_deployment.ps1') -Root $directory
if($LASTEXITCODE){throw 'Delivery files changed; refused to open it as a verified clean package.'}
Write-Output ('DEPLOYMENT_DIRECTORY '+$directory)
if(-not $CheckOnly){Invoke-Item -LiteralPath $directory}
