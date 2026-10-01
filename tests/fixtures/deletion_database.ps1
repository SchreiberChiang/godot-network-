param([Parameter(Mandatory=$true)][string]$Directory,[ValidateSet('scan','backup','rate_limits')][string]$Mode,[string]$Needles='',[string]$Copy='')
$ErrorActionPreference='Stop'
# Test-only inspection of an isolated account-deletion test directory. scan counts,
# per table of both databases, the rows in which any column contains any needle;
# backup takes online SQLite copies of both databases (a stand-in for an older
# backup); rate_limits counts login rate-limit keys. Never touches other data.
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\','/')
$target=[IO.Path]::GetFullPath($Directory)
if ([IO.Path]::GetDirectoryName($target) -ne (Join-Path $project 'data') -or [IO.Path]::GetFileName($target) -notmatch '^test-account-deletion-[a-f0-9]{32}$') { throw 'Test fixture directory refused' }
if ($Copy -and $Copy -notmatch '^[a-z]{1,16}$') { throw 'Copy name refused' }
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $project 'tools/sqlite_store.ps1')
$binding=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
Add-Type -TypeDefinition $binding.Groups[1].Value
$root=if ($Copy) { Join-Path $target $Copy } else { $target }
$result=@{ok=$true}
if ($Mode -eq 'backup') {
    New-Item -ItemType Directory -Force -Path (Join-Path $target 'backup') | Out-Null
    foreach($name in @('accounts.sqlite','assets.sqlite')) {
        $db=New-Object RoomKitSqlite((Join-Path $target $name))
        try { $db.Backup((Join-Path (Join-Path $target 'backup') $name)) } finally { $db.Dispose() }
    }
} elseif ($Mode -eq 'rate_limits') {
    $db=New-Object RoomKitSqlite((Join-Path $root 'accounts.sqlite'))
    try { $result.user_keys=[long]$db.Query('SELECT count(*) AS total FROM rate_limits WHERE rate_key LIKE ''user:%''',@())[0]['total'] } finally { $db.Dispose() }
} else {
    $list=@($Needles -split ',' | Where-Object { $_ })
    if (-not $list.Count) { throw 'No needles' }
    $tables=@{}
    foreach($name in @('accounts.sqlite','assets.sqlite')) {
        $db=New-Object RoomKitSqlite((Join-Path $root $name))
        try {
            foreach($table in $db.Query('SELECT name FROM sqlite_master WHERE type=''table'' AND name NOT LIKE ''sqlite_%''',@())) {
                $hits=0
                foreach($row in $db.Query('SELECT * FROM "'+$table['name']+'"',@())) {
                    $text=($row.Values -join "`n").ToLowerInvariant()
                    foreach($needle in $list) { if ($text.Contains($needle.ToLowerInvariant())) { $hits++; break } }
                }
                $tables[$name+':'+$table['name']]=$hits
            }
        } finally { $db.Dispose() }
    }
    $result.tables=$tables
    $result.total=[long]($tables.Values | Measure-Object -Sum).Sum
}
$result | ConvertTo-Json -Compress -Depth 5
