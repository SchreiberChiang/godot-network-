param([switch]$CheckOnly)
# Opens the separately prepared LAN client, never the shared PlayerClient.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$pointer=Join-Path $project 'artifacts/linux-lan-client.json'
if(-not (Test-Path -LiteralPath $pointer -PathType Leaf)){throw 'Linux LAN client not prepared. See docs/17 (linux-lan).'}
$meta=Get-Content -Encoding UTF8 -Raw -LiteralPath $pointer | ConvertFrom-Json
if([string]$meta.directory -notmatch '^artifacts/linux-lan-[0-9]{14}-[0-9a-f]{6}/shooter-windows$'){throw 'Refused client directory.'}
$client=Join-Path $project $meta.directory
foreach($path in @($pointer,$client,(Join-Path $client 'client-version.json'),(Join-Path $client 'Client.exe'),(Join-Path $client 'connection.json'))){
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked client path.'}
        $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
    }
}
$version=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $client 'client-version.json') | ConvertFrom-Json
$connection=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $client 'connection.json') | ConvertFrom-Json
if($version.build_id -ne $meta.build_id -or $connection.url -ne $meta.url){throw 'LAN client does not match its prepared snapshot.'}
if(-not (Test-Path -LiteralPath (Join-Path $client 'Client.exe') -PathType Leaf)){throw 'Client.exe is missing.'}
if($CheckOnly){Write-Output 'LINUX_PLAYER_CLIENT_READY';exit 0}
Start-Process -FilePath explorer.exe -ArgumentList ('"'+$client+'"') -WindowStyle Normal
