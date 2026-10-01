param(
    [ValidateSet('Start','Stop','Check')][string]$Action='Start',
    [switch]$NoBrowser,
    [ValidateRange(0,3600)][int]$HoldSeconds=0
)
# Local convenience entry for one explicitly prepared, isolated Linux package.
# The ignored pointer contains paths/identities only, never credentials.
# Start opens the private notes/client folder and forwards the panel. Closing
# that window disconnects SSH; Stop requests the exact package instance to exit.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
function SafePath([string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Refused path outside the prepared project.'}
    $full=[IO.Path]::GetFullPath((Join-Path $project $Relative))
    if(-not $full.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Refused path outside the prepared project.'}
    $cursor=$full
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked playtest path.'}
        $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
    }
    return $full
}
$pointer=SafePath 'artifacts/linux-package-playtest.json'
if(-not (Test-Path -LiteralPath $pointer -PathType Leaf)){throw 'Linux package playtest is not prepared on this computer. See docs/17 (linux-package-playtest).'}
$meta=Get-Content -Encoding UTF8 -Raw -LiteralPath $pointer | ConvertFrom-Json
if($meta.build -notmatch '\A[0-9]{14}-[0-9a-f]{8}\z' -or $meta.instance -cne ('export-'+$meta.build.Substring(15)) -or
   $meta.server -cne '192.168.10.105' -or $meta.user -cne 'zhao' -or $meta.panel -ne 28691){throw 'Refused unprepared Linux package identity.'}
$package=SafePath ('artifacts/RoomKit-0.5.0-linux-x86_64-'+$meta.build)
$packageInfo=SafePath ('artifacts/RoomKit-0.5.0-linux-x86_64-'+$meta.build+'/linux-package.json')
$manifest=SafePath ('artifacts/RoomKit-0.5.0-linux-x86_64-'+$meta.build+'/SHA256SUMS.txt')
$packageMeta=Get-Content -Encoding UTF8 -Raw -LiteralPath $packageInfo | ConvertFrom-Json
if($packageMeta.build -cne $meta.build -or $packageMeta.engine -cne '4.7.2.stable.official.ed1daf0bf'){throw 'Local package differs from its prepared identity.'}
$gamesPath=SafePath ('artifacts/RoomKit-0.5.0-linux-x86_64-'+$meta.build+'/games.json')
$game=(Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesPath | ConvertFrom-Json).shooter.manifest
$remote='roomkit/releases/linux-'+$meta.build
$target='zhao@192.168.10.105'
function Remote([string]$Command) {
    $output=@(& ssh.exe -o BatchMode=yes -o ConnectTimeout=10 $target $Command 2>&1)
    if($LASTEXITCODE -ne 0){throw 'Prepared Linux package operation failed. No other instance was stopped.'}
    return ($output -join "`n")
}
$manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteInstance=$remote+'/data/instance-'+$meta.instance
$safeRemotePaths=@('roomkit','roomkit/releases',$remote,($remote+'/SHA256SUMS.txt'),($remote+'/data'),$remoteInstance,
    ($remoteInstance+'/data'),($remoteInstance+'/instance.json'),($remoteInstance+'/data/operator-stop.request'))
$guards=foreach($path in $safeRemotePaths){'test ! -L '+$path}
$verify=($guards -join ' && ')+' && test "$(sha256sum '+$remote+'/SHA256SUMS.txt | cut -d '' '' -f1)" = '+$manifestHash+
    ' && (cd '+$remote+' && sha256sum -c SHA256SUMS.txt >/dev/null)'
if($Action -eq 'Stop'){
    $result=Remote ($verify+' && bash '+$remote+'/RoomKit.sh stop --instance '+$meta.instance)
    if($result -notmatch ('(?m)^ROOMKIT_(STOPPED|NOT_RUNNING) instance='+[regex]::Escape($meta.instance)+'$')){throw 'Unexpected package stop response.'}
    Write-Output $result
    exit 0
}
if($meta.client -cne ('artifacts/linux-package-player-'+$meta.build+'/shooter-windows') -or
   $meta.notes -notmatch ('\Adata/codex-linux-package-'+[regex]::Escape($meta.build)+'-[0-9a-f]{8}/PLAYTEST\.md\z')){throw 'Refused client or private notes path.'}
$client=SafePath $meta.client
$notes=SafePath $meta.notes
if(-not(Test-Path -LiteralPath $notes -PathType Leaf)){throw 'Private playtest instructions are missing.'}
$versionPath=SafePath ($meta.client+'/client-version.json')
$version=Get-Content -Encoding UTF8 -Raw -LiteralPath $versionPath | ConvertFrom-Json
$connectionPath=SafePath ($meta.client+'/connection.json')
$connection=Get-Content -Encoding UTF8 -Raw -LiteralPath $connectionPath | ConvertFrom-Json
foreach($field in @('game_id','build_id','compatibility_id','game_protocol')){
    if($null -eq $game.$field -or $version.$field -cne $game.$field){throw 'Player client does not match the prepared package game.'}
}
if($version.build_id -cne $packageMeta.games.shooter -or $connection.url -cne 'wss://192.168.10.105:28700' -or
   $connection.managed -ne $true -or $connection.secure_enet -ne $true -or $connection.server_hostname -cne 'localhost' -or
   $connection.ca_certificate -cne 'server.crt'){throw 'Player client does not match the prepared encrypted package connection.'}
foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd','connection.json','server.crt')){
    $path=SafePath ($meta.client+'/'+$name)
    $entry=@($version.generated_files | Where-Object {$_.path -ceq $name})
    if($entry.Count -ne 1 -or $entry[0].sha256 -notmatch '\A[0-9a-f]{64}\z' -or
       -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry[0].sha256){throw ('Prepared client file is missing or changed: '+$name)}
}
if($Action -eq 'Check'){Write-Output 'LINUX_PACKAGE_PLAYTEST_READY';exit 0}
# Refuse occupied local panel ports before any remote startup; never adopt or
# close another SSH tunnel. The tunnel helper checks ownership again afterwards.
$reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,28691)
try{$reservation.Start()}catch{throw 'Local panel port 28691 is occupied. Use the existing playtest window; nothing was stopped.'}finally{$reservation.Stop()}
# Values below are restricted above to digits, lowercase hexadecimal and fixed
# path segments. Verify the remote manifest before executing package scripts.
$command=$verify+' && bash '+$remote+'/CheckPackage.sh && bash '+$remote+'/RoomKit.sh start --instance '+$meta.instance
$result=Remote $command
if($result -notmatch ('(?m)^ROOMKIT_(PANEL http://127\.0\.0\.1:28691/ instance='+[regex]::Escape($meta.instance)+' pid=[0-9]+|RUNNING instance='+[regex]::Escape($meta.instance)+' pid=[0-9]+ panel=http://127\.0\.0\.1:28691/)$')){throw 'Package did not report the prepared instance and panel port.'}
$certificateHash=(Get-FileHash -LiteralPath (SafePath ($meta.client+'/server.crt')) -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteCertificate=$remote+'/data/instance-'+$meta.instance+'/public/server.crt'
$certificateResult=Remote ('test ! -L '+$remoteCertificate+' && sha256sum '+$remoteCertificate)
if($certificateResult -notmatch ('^'+$certificateHash+'  '+[regex]::Escape($remoteCertificate)+'$')){throw 'The Linux certificate differs from this prepared client. Regenerate the matching client before playing.'}
Write-Output 'LINUX_PACKAGE_PLAYTEST_STARTED'
if(-not $NoBrowser){
    Start-Process -FilePath notepad.exe -ArgumentList ('"'+$notes+'"') -WindowStyle Normal
    Start-Process -FilePath explorer.exe -ArgumentList ('"'+$client+'"') -WindowStyle Normal
}
& (Join-Path $PSScriptRoot 'open_linux_management.ps1') -Server $meta.server -User $meta.user -PanelPort 28691 -NoBrowser:$NoBrowser -HoldSeconds $HoldSeconds
exit $LASTEXITCODE
