param()
# Pure launcher guards in a new fake project. No engine or remote service is
# started: every case uses Check, except a Start rejected by a held local port.
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
        if(($Accept -and ($process.ExitCode -ne 0 -or $text -notmatch 'LINUX_PACKAGE_PLAYTEST_READY')) -or
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
    @{name='wrong instance';field='instance';value='export-ffffffff';reason='unprepared Linux package identity'},
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
Write-Output ('LINUX_PACKAGE_ENTRY_TEST passed='+$count+' failed=0 evidence='+$root)
