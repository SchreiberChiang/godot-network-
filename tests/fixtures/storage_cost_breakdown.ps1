param([int]$Rounds=3)
$ErrorActionPreference='Stop'
# Measures in-process costs that every account helper call pays after PowerShell
# has started: compiling the SQLite binding, compiling the password class and one
# PBKDF2 derivation at the production iteration count. The C# is extracted from
# the production helpers so this fixture cannot drift into a different version.
$tools=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools'
$sqliteSource=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $tools 'sqlite_store.ps1')
$accountSource=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $tools 'account_store.ps1')
$sqlite=[regex]::Match($sqliteSource,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
$passwords=[regex]::Match($accountSource,"(?s)Add-Type -TypeDefinition @'\r?\n(using System;\r?\nusing System\.Security\.Cryptography;.*?)\r?\n'@")
$iterations=[regex]::Match($accountSource,'\$iterations=(\d+)')
if(-not $sqlite.Success -or -not $passwords.Success -or -not $iterations.Success) { throw 'Production helper source not recognized' }
$clock=[Diagnostics.Stopwatch]::StartNew()
Add-Type -TypeDefinition $sqlite.Groups[1].Value
$sqliteMs=$clock.Elapsed.TotalMilliseconds
$clock.Restart()
Add-Type -TypeDefinition $passwords.Groups[1].Value
$passwordMs=$clock.Elapsed.TotalMilliseconds
$salt=[RoomKitPasswords]::Salt()
$derive=@()
for($i=0;$i -lt $Rounds;$i++) {
    $clock.Restart()
    [void][RoomKitPasswords]::Derive('storage-cost-breakdown',$salt,[int]$iterations.Groups[1].Value)
    $derive+=[math]::Round($clock.Elapsed.TotalMilliseconds,1)
}
ConvertTo-Json -Compress -InputObject @{ok=$true;iterations=[int]$iterations.Groups[1].Value;add_type_sqlite_ms=[math]::Round($sqliteMs,1);add_type_passwords_ms=[math]::Round($passwordMs,1);pbkdf2_ms=$derive}
