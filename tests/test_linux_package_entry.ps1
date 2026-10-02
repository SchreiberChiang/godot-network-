param()
# Pure launcher guards in a new fake project. No engine or remote service is
# started: Start/Stop use a substitute SSH function and management entry.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $project ('data/linux-package-entry-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$fake=Join-Path $root 'fake-project'
$build='20200101000000-abcdef12'
$client='artifacts/linux-package-player-'+$build+'/shooter-windows'
$package='artifacts/RoomKit-0.5.0-linux-x86_64-'+$build
$notes='data/codex-linux-package-'+$build+'-12345678/PLAYTEST.md'
foreach($folder in @('tools',$client,$package,[IO.Path]::GetDirectoryName($notes))){[void][IO.Directory]::CreateDirectory((Join-Path $fake $folder))}
Copy-Item -LiteralPath (Join-Path $project 'tools/open_linux_package.ps1') -Destination (Join-Path $fake 'tools/open_linux_package.ps1')
$utf8=New-Object Text.UTF8Encoding($false)
# Inject a substitute only into the disposable launcher copy. Production code
# still calls ssh.exe directly; the substitute records every command and reads
# small JSON fixtures instead of contacting a host.
$sshFixture=@'
function ssh.exe {
    $command=[string]$args[-1]
    [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'ssh-commands.txt'),$command+"`n")
    $global:LASTEXITCODE=0
    if($command -match ' && bash roomkit/releases/linux-[0-9]{14}-[a-f0-9]{8}/UpdateRoomKit.sh status --new-package /home/zhao/roomkit/releases/linux-[0-9]{14}-[a-f0-9]{8} --instance export-[a-f0-9]{8}$'){
        $statusPath=Join-Path $PSScriptRoot 'remote-update-status.json'
        if(-not [IO.File]::Exists($statusPath)){$global:LASTEXITCODE=99;return 'Missing substitute update journal.'}
        return ('ROOMKIT_UPDATE '+([IO.File]::ReadAllText($statusPath)|ConvertFrom-Json|ConvertTo-Json -Compress -Depth 12))
    }
    if($command -match ' && cat roomkit/releases/linux-[0-9-]+[a-f0-9]*/data/instance-export-[a-f0-9]+/data/config.json$'){
        return [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'remote-network.json'))
    }
    if($command -match '/RoomKit.sh start --instance '){return ('ROOMKIT_PANEL http://127.0.0.1:28691/ instance='+$meta.instance+' pid=12345')}
    if($command -match '/RoomKit.sh stop --instance '){return ('ROOMKIT_STOPPED instance='+$meta.instance)}
    if($command -match '^test ! -L (roomkit/releases/linux-[^ ]+/data/instance-export-[^ ]+/public/server.crt) && sha256sum '){
        $hash=(Get-FileHash -LiteralPath (Join-Path $project ($meta.client+'/server.crt')) -Algorithm SHA256).Hash.ToLowerInvariant()
        return ($hash+'  '+$matches[1])
    }
    $global:LASTEXITCODE=99
    return 'Unexpected substitute SSH command.'
}
'@
$launcherPath=Join-Path $fake 'tools/open_linux_package.ps1'
$launcherText=[IO.File]::ReadAllText($launcherPath)
$fixtureMarker="# Local convenience entry"
if(-not $launcherText.Contains($fixtureMarker)){throw 'Launcher fixture insertion point missing.'}
[IO.File]::WriteAllText($launcherPath,$launcherText.Replace($fixtureMarker,$sshFixture+"`n"+$fixtureMarker),$utf8)
[IO.File]::WriteAllText((Join-Path $fake 'tools/open_linux_management.ps1'),"param(`$Server,`$User,`$PanelPort,[switch]`$NoBrowser,`$HoldSeconds)`nWrite-Output 'SUBSTITUTE_MANAGEMENT_READY'`nexit 0`n",$utf8)
function Json([string]$Relative,$Value){[IO.File]::WriteAllText((Join-Path $fake $Relative),($Value|ConvertTo-Json -Depth 12),$utf8)}
function ReadJson([string]$Relative){return (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $fake $Relative)|ConvertFrom-Json)}
[IO.File]::WriteAllText((Join-Path $fake $notes),'fake private instructions',$utf8)
[IO.File]::WriteAllText((Join-Path $fake ($package+'/SHA256SUMS.txt')),'not executed',$utf8)
$manifest=@{game_id='shooter';build_id='shooter-test';compatibility_id='shooter-v2';game_protocol=2}
Json ($package+'/linux-package.json') @{build=$build;engine='4.7.2.stable.official.ed1daf0bf';games=@{shooter='shooter-test'}}
Json ($package+'/games.json') @{shooter=@{manifest=$manifest}}
Json ($client+'/connection.json') @{url='wss://192.168.10.105:28700';managed=$true;secure_enet=$true;server_hostname='localhost';ca_certificate='server.crt'}
foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd','server.crt')){[IO.File]::WriteAllText((Join-Path $fake ($client+'/'+$name)),'fake '+$name,$utf8)}
$entries=foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd','connection.json','server.crt')){@{path=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $fake ($client+'/'+$name)) -Algorithm SHA256).Hash.ToLowerInvariant()}}
$version=@{game_id='shooter';build_id='shooter-test';compatibility_id='shooter-v2';game_protocol=2;generated_files=@($entries)}
Json ($client+'/client-version.json') $version
$valid=@{build=$build;instance='export-abcdef12';server='192.168.10.105';user='zhao';panel=28691;client=$client;notes=$notes}
$count=0
function Run([string]$Label,[bool]$Accept,[string]$Reason,[string]$Action='Check'){
    $script:count++
    $out=Join-Path $root ($script:count.ToString()+'-out.txt');$err=Join-Path $root ($script:count.ToString()+'-err.txt')
    $process=Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $fake 'tools/open_linux_package.ps1')+'"'),'-Action',$Action,'-NoBrowser','-HoldSeconds','1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    [void]$process.Handle
    try{
        if(-not $process.WaitForExit(10000)){$process.Kill();throw 'Pure entry check did not return in ten seconds.'}
        $text=(Get-Content -Encoding UTF8 -Raw -LiteralPath $out)+(Get-Content -Encoding UTF8 -Raw -LiteralPath $err)
        $acceptedOutput=switch($Action){'Start'{'LINUX_PACKAGE_PLAYTEST_STARTED'};'Stop'{'ROOMKIT_STOPPED'};default{'LINUX_PACKAGE_PLAYTEST_READY'}}
        if(($Accept -and ($process.ExitCode -ne 0 -or $text -notmatch $acceptedOutput)) -or
           (-not $Accept -and ($process.ExitCode -eq 0 -or $text -notmatch $Reason))){throw ('Unexpected check result: '+$Label)}
        Write-Output ('PASS '+$Label)
    }finally{$process.Dispose()}
}
$pointer='artifacts/linux-package-playtest.json'
$remote='roomkit/releases/linux-'+$build
$remoteInstance=$remote+'/data/instance-export-abcdef12'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $fake 'tools/open_linux_package.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Launcher parse failed.'}
$assignment=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'safeRemotePaths'},$true)
if($null -eq $assignment){throw 'Remote path guard list is missing.'}
# Evaluate this single literal-array assignment from the launcher, never its
# functions or entry flow. This catches PowerShell comma/concatenation binding.
$actualPaths=@(& ([scriptblock]::Create($assignment.Extent.Text+'; $safeRemotePaths')))
$expectedPaths=@('roomkit','roomkit/releases',$remote,"$remote/SHA256SUMS.txt","$remote/data",$remoteInstance,
    "$remoteInstance/data","$remoteInstance/instance.json","$remoteInstance/data/operator-stop.request")
if($actualPaths.Count -ne 9 -or ($actualPaths -join '|') -cne ($expectedPaths -join '|')){throw 'Remote guard paths must be nine complete prepared-instance paths.'}
$count++;Write-Output 'PASS exact nine remote link guard paths'
Json $pointer $valid;Run 'prepared local identity accepted without SSH' $true ''
foreach($case in @(
    @{name='different instance without update evidence';field='instance';value='export-ffffffff';reason='Prepared Linux package operation failed'},
    @{name='instance traversal';field='instance';value='export-../ffffffff';reason='unprepared Linux package identity'},
    @{name='instance newline';field='instance';value="export-ffffffff`n";reason='unprepared Linux package identity'},
    @{name='different server';field='server';value='192.168.10.1';reason='unprepared Linux package identity'},
    @{name='different panel';field='panel';value=28491;reason='unprepared Linux package identity'},
    @{name='client traversal';field='client';value='artifacts/../PlayerClient';reason='client or private notes path'},
    @{name='notes outside private directory';field='notes';value='README.md';reason='client or private notes path'},
    @{name='build injection';field='build';value='20200101000000-abcdef12;echo BAD';reason='unprepared Linux package identity'},
    @{name='build newline';field='build';value="20200101000000-abcdef12`n";reason='unprepared Linux package identity'}
)){
    $copy=@{};foreach($key in $valid.Keys){$copy[$key]=$valid[$key]};$copy[$case.field]=$case.value;Json $pointer $copy
    Run $case.name $false $case.reason
}
Json $pointer $valid
$bad=ReadJson ($client+'/client-version.json');$bad.game_protocol=99;Json ($client+'/client-version.json') $bad
Run 'game protocol mismatch' $false 'prepared package game'
Json ($client+'/client-version.json') $version
[IO.File]::AppendAllText((Join-Path $fake ($client+'/Client.pck')),'changed',$utf8)
Run 'changed client file' $false 'missing or changed: Client.pck'
[IO.File]::WriteAllText((Join-Path $fake ($client+'/Client.pck')),'fake Client.pck',$utf8)
$badConnection=ReadJson ($client+'/connection.json');$badConnection.secure_enet=$false;Json ($client+'/connection.json') $badConnection
Run 'unencrypted room connection' $false 'encrypted package connection'
Json ($client+'/connection.json') @{url='wss://192.168.10.105:28700';managed=$true;secure_enet=$true;server_hostname='localhost';ca_certificate='server.crt'}
$junction=Join-Path $fake 'artifacts/linked';New-Item -ItemType Junction -Path $junction -Target (Join-Path $fake $client) | Out-Null
# A link at the exact expected directory must be rejected before reading files.
$realClient=Join-Path $fake $client
Move-Item -LiteralPath $realClient -Destination ($realClient+'-saved')
New-Item -ItemType Junction -Path $realClient -Target ($realClient+'-saved') | Out-Null
Run 'linked client directory' $false 'linked playtest path'
[IO.Directory]::Delete($realClient)
Move-Item -LiteralPath ($realClient+'-saved') -Destination $realClient
[IO.Directory]::Delete($junction)
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,28691)
try{$listener.Start();Run 'occupied port refused before remote operation' $false 'port 28691 is occupied' 'Start'}finally{$listener.Stop()}

function SetConnection([string]$HostName,[int]$Port){
    Json ($client+'/connection.json') @{url=('wss://'+$HostName+':'+$Port);managed=$true;secure_enet=$true;server_hostname='localhost';ca_certificate='server.crt'}
    $current=ReadJson ($client+'/client-version.json')
    foreach($entry in $current.generated_files){if($entry.path -ceq 'connection.json'){$entry.sha256=(Get-FileHash -LiteralPath (Join-Path $fake ($client+'/connection.json')) -Algorithm SHA256).Hash.ToLowerInvariant()}}
    Json ($client+'/client-version.json') $current
}
$deployment='artifacts/deployments/friends-20261002-test/Server'
[void][IO.Directory]::CreateDirectory((Join-Path $fake $deployment))
foreach($name in @('linux-package.json','games.json','SHA256SUMS.txt')){Copy-Item -LiteralPath (Join-Path $fake ($package+'/'+$name)) -Destination (Join-Path $fake ($deployment+'/'+$name))}
$public=@{};foreach($key in $valid.Keys){$public[$key]=$valid[$key]}
$public.package=$deployment;$public.public_host='60.163.23.141';$public.lobby_port=28700
SetConnection $public.public_host $public.lobby_port
Json $pointer $public;Run 'public deployment identity accepted without SSH' $true ''
foreach($case in @(
    @{name='package traversal';field='package';value='artifacts/deployments/../Server';reason='deployment package path'},
    @{name='package nested directory';field='package';value='artifacts/deployments/valid/extra/Server';reason='deployment package path'},
    @{name='package newline';field='package';value="artifacts/deployments/friends/Server`n";reason='deployment package path'},
    @{name='package injection';field='package';value='artifacts/deployments/friends;echo/Server';reason='deployment package path'},
    @{name='package arbitrary old location';field='package';value='artifacts/elsewhere';reason='deployment package path'},
    @{name='wildcard public address';field='public_host';value='0.0.0.0';reason='public IPv4 address'},
    @{name='IPv4 octet overflow';field='public_host';value='60.163.23.256';reason='public IPv4 address'},
    @{name='IPv4 abbreviated';field='public_host';value='127.1';reason='public IPv4 address'},
    @{name='IPv4 leading zero';field='public_host';value='060.163.23.141';reason='public IPv4 address'},
    @{name='public hostname';field='public_host';value='server.example.test';reason='public IPv4 address'},
    @{name='public injection';field='public_host';value='60.163.23.141;echo';reason='public IPv4 address'},
    @{name='string lobby port';field='lobby_port';value='28700';reason='lobby port'},
    @{name='floating lobby port';field='lobby_port';value=28700.5;reason='lobby port'},
    @{name='low lobby port';field='lobby_port';value=1023;reason='lobby port'},
    @{name='high lobby port';field='lobby_port';value=65536;reason='lobby port'}
)){
    $copy=@{};foreach($key in $public.Keys){$copy[$key]=$public[$key]};$copy[$case.field]=$case.value;Json $pointer $copy
    Run $case.name $false $case.reason
}
Json $pointer $public
SetConnection '192.168.10.105' 28700;Run 'public pointer rejects old LAN player URL' $false 'encrypted package connection'
SetConnection $public.public_host 28701;Run 'public pointer rejects wrong lobby URL port' $false 'encrypted package connection'
SetConnection $public.public_host $public.lobby_port

$network=@{lobby_bind='0.0.0.0';game_bind='0.0.0.0';advertised_host=$public.public_host;lobby_port=$public.lobby_port}
Json 'tools/remote-network.json' $network
Run 'public Start checks saved network then uses exact instance' $true '' 'Start'
foreach($case in @(
    @{name='loopback lobby bind';field='lobby_bind';value='127.0.0.1'},
    @{name='loopback room bind';field='game_bind';value='127.0.0.1'},
    @{name='different advertised address';field='advertised_host';value='192.168.10.105'},
    @{name='different saved lobby port';field='lobby_port';value=28701},
    @{name='string saved lobby port';field='lobby_port';value='28700'}
)){
    $copy=@{};foreach($key in $network.Keys){$copy[$key]=$network[$key]};$copy[$case.field]=$case.value
    Json 'tools/remote-network.json' $copy
    [IO.File]::WriteAllText((Join-Path $fake 'tools/ssh-commands.txt'),'',$utf8)
    Run $case.name $false 'network configuration differs' 'Start'
    if([IO.File]::ReadAllText((Join-Path $fake 'tools/ssh-commands.txt')) -match '/RoomKit.sh start'){throw 'Rejected network still started a package.'}
}
Run 'Stop remains available with mismatched network' $true '' 'Stop'

Json $pointer $valid;SetConnection '192.168.10.105' 28700
foreach($binding in @('0.0.0.0','192.168.10.105')){
    Json 'tools/remote-network.json' @{lobby_bind=$binding;game_bind=$binding;advertised_host='192.168.10.105';lobby_port=28700}
    Run ('old pointer Start remains compatible with '+$binding) $true '' 'Start'
}

# The updater keeps the original instance name in a newer immutable package.
# Exercise its validated, non-secret status output rather than a pointer flag.
$migrated=@{};foreach($key in $valid.Keys){$migrated[$key]=$valid[$key]}
$migrated.instance='export-ffffffff'
$absoluteRemote='/home/zhao/'+$remote
$oldPackage='/home/zhao/roomkit/releases/linux-20190101000000-ffffffff'
$sealed=@{ok=$true;state='SEALED';instance=$migrated.instance;new_package=$absoluteRemote;
    new_instance=($absoluteRemote+'/data/instance-'+$migrated.instance);
    journal=($absoluteRemote+'/data/update-'+$migrated.instance+'/journal.json');
    old_package=$oldPackage;old_instance=($oldPackage+'/data/instance-'+$migrated.instance);rollback_allowed=$false;code=''}
Json $pointer $migrated;Json 'tools/remote-update-status.json' $sealed
foreach($action in @('Check','Start','Stop')){
    [IO.File]::WriteAllText((Join-Path $fake 'tools/ssh-commands.txt'),'',$utf8)
    Run ('sealed migration preserves old instance for '+$action) $true '' $action
    $commands=[IO.File]::ReadAllText((Join-Path $fake 'tools/ssh-commands.txt'))
    $expected='bash '+$remote+'/UpdateRoomKit.sh status --new-package '+$absoluteRemote+' --instance '+$migrated.instance
    if(-not $commands.Contains($expected) -or -not $commands.Contains('sha256sum -c SHA256SUMS.txt >/dev/null) && '+$expected)){
        throw 'Migrated identity was accepted without the checksummed official status command.'
    }
}
foreach($case in @(
    @{name='unsealed migration';field='state';value='VERIFIED'},
    @{name='failed migration status';field='ok';value=$false},
    @{name='string success flag';field='ok';value='true'},
    @{name='different migration instance';field='instance';value='export-12345678'},
    @{name='forged new package';field='new_package';value='/home/zhao/roomkit/releases/linux-20200101000000-12345678'},
    @{name='forged instance data path';field='new_instance';value=($absoluteRemote+'/data/../instance-export-ffffffff')},
    @{name='forged journal outside update directory';field='journal';value=($absoluteRemote+'/journal.json')},
    @{name='arbitrary old package';field='old_package';value='/tmp/other-package'},
    @{name='old package traversal';field='old_package';value='/home/zhao/roomkit/releases/../linux-20190101000000-ffffffff'},
    @{name='mismatched old instance path';field='old_instance';value=($oldPackage+'/data/instance-export-12345678')}
)){
    $copy=@{};foreach($key in $sealed.Keys){$copy[$key]=$sealed[$key]};$copy[$case.field]=$case.value
    Json 'tools/remote-update-status.json' $copy
    [IO.File]::WriteAllText((Join-Path $fake 'tools/ssh-commands.txt'),'',$utf8)
    Run $case.name $false 'update status does not match the sealed prepared instance' 'Start'
    if([IO.File]::ReadAllText((Join-Path $fake 'tools/ssh-commands.txt')) -match '/RoomKit.sh (start|stop)'){
        throw 'Rejected migration still issued a service operation.'
    }
}
Write-Output ('LINUX_PACKAGE_ENTRY_TEST passed='+$count+' failed=0 evidence='+$root)
