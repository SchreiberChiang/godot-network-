param([int]$Rounds=5)
# Evaluation only: cost of one asset.read through lighter variants of the CURRENT
# one-shot model, measured from a parent process as Godot would see it.
#   current     Godot-style call: bounded_helper.ps1 -> sqlite_store.ps1 (two PowerShell starts)
#   direct      sqlite_store.ps1 started directly (outer bounded helper removed)
#   direct_dll  direct, with the SQLite binding loaded from a DLL compiled once
# The DLL variant runs a modified COPY of sqlite_store.ps1 inside the private test
# directory; production files are not changed.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$tools=Join-Path $project 'tools'
$work=Join-Path $project ('data\test-oneshot-variants-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$database=Join-Path $work 'assets.sqlite'
function Request($body) { $path=Join-Path $work ('request-'+[Guid]::NewGuid().ToString('N')+'.json'); [IO.File]::WriteAllText($path,($body|ConvertTo-Json -Compress),$utf8); return $path }
function Run([string[]]$Arguments) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $output=& $powershell @Arguments
    $ms=[math]::Round($clock.Elapsed.TotalMilliseconds,1)
    if($LASTEXITCODE -ne 0 -or ($output -join '') -notmatch '"ok":true') { throw ('Variant call failed: '+($output -join ' ')) }
    return $ms
}
$init=Request @{op='init'}
[void](Run @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $tools 'sqlite_store.ps1'),'-Database',$database,'-Request',$init))
# Build the DLL variant from the production source.
$source=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $tools 'sqlite_store.ps1')
$match=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
$dll=Join-Path $work 'RoomKitSqlite.dll'
Add-Type -TypeDefinition $match.Groups[1].Value -OutputAssembly $dll -OutputType Library
$variant=Join-Path $work 'sqlite_store_dll.ps1'
# Relative path keeps the generated script ASCII; Windows PowerShell 5.1 reads
# BOM-less scripts in the system code page and would garble a Chinese path.
[IO.File]::WriteAllText($variant,$source.Substring(0,$match.Index)+"Add-Type -Path (Join-Path `$PSScriptRoot 'RoomKitSqlite.dll')"+$source.Substring($match.Index+$match.Length),$utf8)
$results=[ordered]@{current=@();direct=@();direct_dll=@()}
for($i=0;$i -lt $Rounds;$i++) {
    $read=@{op='asset.read';user_id='variant-user';space_id='shooter'}
    $job=Join-Path $work ('helper-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($job,(@{helper='sqlite_store.ps1';arguments=@('-Database',$database,'-Request',(Request $read))}|ConvertTo-Json -Compress),$utf8)
    $results.current+=Run @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $tools 'bounded_helper.ps1'),'-Request',$job,'-TimeoutMs','10000')
    $results.direct+=Run @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $tools 'sqlite_store.ps1'),'-Database',$database,'-Request',(Request $read))
    $results.direct_dll+=Run @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$variant,'-Database',$database,'-Request',(Request $read))
}
$summary=[ordered]@{rounds=$Rounds;work=$work}
foreach($name in $results.Keys) {
    $sorted=@($results[$name] | Sort-Object)
    $summary[$name]=[ordered]@{median_ms=$sorted[[int][Math]::Floor($sorted.Count/2)];min_ms=$sorted[0];max_ms=$sorted[-1];samples_ms=$results[$name]}
    Write-Output ('ONESHOT {0} median={1}ms min={2}ms max={3}ms' -f $name,$sorted[[int][Math]::Floor($sorted.Count/2)],$sorted[0],$sorted[-1])
}
[IO.File]::WriteAllText((Join-Path $project 'logs\storage-oneshot-variants.json'),($summary|ConvertTo-Json -Depth 6),$utf8)
Write-Output 'ONESHOT_VARIANTS_RESULT ok=true'
