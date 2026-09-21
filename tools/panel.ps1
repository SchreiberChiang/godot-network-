param([ValidateSet('blocks','turns')][string]$Game='turns',[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(Test-Path -LiteralPath (Join-Path $root 'run/panel-access.json')) {
    try { & (Join-Path $PSScriptRoot 'open_panel.ps1') -NoBrowser:$NoBrowser; return } catch { }
}
& (Join-Path $PSScriptRoot 'play.ps1') -Game $Game -Panel -NoBrowser:$NoBrowser
exit $LASTEXITCODE
