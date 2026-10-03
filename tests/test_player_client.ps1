param([switch]$Visual,[string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Isolated acceptance for PreparePlayerClient. The test-owned operator has its own
# data root, ports, game index and public-client directory, so the normal
# artifacts\client and artifacts\framework-games.json are never written. Covers
# controlled output replacement, the shared local/GitHub generation source, and
# two exported Client.exe processes that register, log in and join one real room
# through the normal version-checked admission path, plus a refused mismatch.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $project ('logs\player-client-'+$runId)
$out=Join-Path $evidence 'out'
$repoCopy=Join-Path $out 'repository-copy'
# A sibling fixture stays outside the repository even when TMP/TEMP are in logs/.
$externalParent=[IO.Path]::GetDirectoryName($project)
$externalRoot=Join-Path $externalParent ('RoomKit-player-client-test-'+$runId)
$externalOwned=$false
$fresh=Join-Path $externalRoot 'RoomKit 玩家 客户端'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
$script:passed=0; $script:failed=0
function Check([bool]$condition,[string]$name) { if($condition){$script:passed++;Write-Output ('PASS '+$name)}else{$script:failed++;Write-Output ('FAIL '+$name)} }
function Quote($values) { foreach($value in $values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'} }
function Tree([string]$Directory) {
    if(-not (Test-Path -LiteralPath $Directory)) { return '' }
    return ((Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Directory.Length)+'='+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function AssertExternalFixture {
    $full=[IO.Path]::GetFullPath($externalRoot).TrimEnd('\','/')
    $expected=Join-Path $externalParent ('RoomKit-player-client-test-'+$runId)
    if($runId -notmatch '^[0-9a-f]{32}$' -or $full -ine $expected -or $full -ieq $project -or $full.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe external player-client fixture boundary.' }
    $probe=$full
    while($probe) {
        if((Test-Path -LiteralPath $probe) -and ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('External fixture has a linked ancestor: '+$probe) }
        $probe=[IO.Path]::GetDirectoryName($probe)
    }
    if(Test-Path -LiteralPath $full) {
        if(Get-ChildItem -LiteralPath $full -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'External fixture contains a link; cleanup refused.' }
    }
}
$script:prepareRun=0
function Prepare([string[]]$Extra) {
    $script:prepareRun++
    $log=Join-Path $evidence ('prepare-'+$script:prepareRun+'.log')
    # Set both ends explicitly: PowerShell 5.1 native capture otherwise uses the
    # console code page and can corrupt Chinese diagnostics before log writing.
    $parameters=@{Godot=$Godot}
    for($i=0;$i -lt $Extra.Count;$i++) {
        if($Extra[$i] -notmatch '^-[A-Za-z][A-Za-z0-9]*$') { throw ('Invalid Prepare parameter: '+$Extra[$i]) }
        $name=$Extra[$i].Substring(1)
        if($i+1 -lt $Extra.Count -and $Extra[$i+1] -notmatch '^-[A-Za-z][A-Za-z0-9]*$') { $i++; $parameters[$name]=$Extra[$i] }
        else { $parameters[$name]=$true }
    }
    $payload=@{script=(Join-Path $project 'tools\prepare_player_client.ps1');parameters=$parameters} | ConvertTo-Json -Compress
    $encodedPayload=[Convert]::ToBase64String($utf8.GetBytes($payload))
    $command='$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); $OutputEncoding=[Console]::OutputEncoding; $payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$encodedPayload+'")) | ConvertFrom-Json; $parameters=@{}; foreach($property in $payload.parameters.PSObject.Properties) { $parameters[$property.Name]=$property.Value }; try { $global:LASTEXITCODE=0; & $payload.script @parameters; exit $LASTEXITCODE } catch { [Console]::Error.WriteLine(($_ | Out-String)); exit 1 }'
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName='powershell.exe'
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.WorkingDirectory=$project
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=$utf8; $info.StandardErrorEncoding=$utf8
    $process=[Diagnostics.Process]::Start($info)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text=$stdout.Result+"`n"+$stderr.Result
        [IO.File]::WriteAllText($log,$text,$utf8)
        return @{code=$process.ExitCode;text=$text}
    } finally { $process.Dispose() }
}

$sharedPublic=Join-Path $project 'artifacts\client'
$sharedIndex=Join-Path $project 'artifacts\framework-games.json'
$sharedBefore=(Tree $sharedPublic)+'|'+$(if(Test-Path $sharedIndex){(Get-FileHash $sharedIndex).Hash})
$gamesIndex=Join-Path $evidence 'framework-games.json'
& (Join-Path $project 'tools\build_framework.ps1') -IndexPath $gamesIndex | Out-Null
. (Join-Path $project 'tools\content_digest.ps1')
. (Join-Path $project 'tools\prepared_input.ps1')
$builtIndex=Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesIndex | ConvertFrom-Json
$secondIndex=Join-Path $evidence 'framework-games-second.json'
& (Join-Path $project 'tools\build_framework.ps1') -IndexPath $secondIndex | Out-Null
$secondBuilt=Get-Content -Encoding UTF8 -Raw -LiteralPath $secondIndex | ConvertFrom-Json
$roomManifest=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $builtIndex.shooter.project 'game\game_manifest.json') | ConvertFrom-Json
Check ($builtIndex.shooter.manifest.build_id -match '^shooter-dev-002-src-[0-9a-f]{12}$' -and $builtIndex.shooter.manifest.build_id -eq ('shooter-dev-002-src-'+(ContentDigest $builtIndex.shooter.project)) -and $roomManifest.build_id -eq $builtIndex.shooter.manifest.build_id) ('build_id is bound to the prepared project content ('+$builtIndex.shooter.manifest.build_id+')')
Check ($secondBuilt.shooter.manifest.build_id -eq $builtIndex.shooter.manifest.build_id -and $secondBuilt.turns.manifest.build_id -eq $builtIndex.turns.manifest.build_id) 'rebuilding unchanged sources gives the same build_id'
$publicDir=Join-Path $evidence 'public-client'
$pointer=Join-Path $project 'run\operator-test-context.json'
$started=[DateTime]::UtcNow
$operatorTest=Start-Process -FilePath 'powershell.exe' -ArgumentList (Quote @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'test_operator.ps1'),'-HoldForIntegration','-GamesIndex',$gamesIndex,'-PublicClientDir',$publicDir,'-Godot',$Godot)) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'operator-test.log') -RedirectStandardError (Join-Path $evidence 'operator-test-stderr.log')
$operatorHandle=$operatorTest.Handle
$ctx=$null; $clients=@()
try {
    $deadline=[DateTime]::UtcNow.AddSeconds(150)
    while($null -eq $ctx -and [DateTime]::UtcNow -lt $deadline -and -not $operatorTest.HasExited) {
        Start-Sleep -Milliseconds 500
        if((Test-Path -LiteralPath $pointer) -and (Get-Item -LiteralPath $pointer).LastWriteTimeUtc -gt $started) {
            $path=(Get-Content -Encoding UTF8 -Raw -LiteralPath $pointer | ConvertFrom-Json).path
            if(Test-Path -LiteralPath $path) { $ctx=Get-Content -Encoding UTF8 -Raw -LiteralPath $path | ConvertFrom-Json }
        }
    }
    if($null -eq $ctx) { throw 'Isolated operator did not become ready; see operator-test.log' }
    Check $true 'isolated operator, host, READY shooter room and invite'
    Check ((Test-Path (Join-Path $publicDir 'connection.json')) -and (Test-Path (Join-Path $publicDir 'server.crt'))) 'isolated operator publishes to its own public-client directory'
    $common=@('-IndexPath',$gamesIndex,'-ConnectionDirectory',$publicDir)

    # Controlled output range.
    AssertExternalFixture
    if(Test-Path -LiteralPath $externalRoot) { throw 'Unique external fixture already exists; refusing to reuse it.' }
    New-Item -ItemType Directory -Path $externalRoot | Out-Null
    $externalOwned=$true
    $outside=Join-Path $externalRoot 'refused-output'
    $r=Prepare ($common+@('-OutputRoot',$outside))
    $refused=$r.code -ne 0
    $nothingCreated=-not (Test-Path -LiteralPath $outside)
    $rangeDiagnostic=$r.text -match '受控范围'
    Check $refused 'output outside artifacts/logs returns a refusal exit code'
    Check $nothingCreated 'output outside artifacts/logs creates nothing'
    Check $rangeDiagnostic 'output refusal preserves the Chinese controlled-range diagnostic'
    $r=Prepare ($common+@('-OutputRoot',$out,'-RepositoryCopy','-RepositoryDestination',(Join-Path $project 'docs\evil')))
    $repositoryRefused=$r.code -ne 0
    $repositoryNothingCreated=-not (Test-Path -LiteralPath (Join-Path $project 'docs\evil'))
    Check ($repositoryRefused -and $repositoryNothingCreated) 'repository copy outside its fixed location is refused'

    # First generation: local + repository copy from one export.
    $r=Prepare ($common+@('-OutputRoot',$out,'-RepositoryCopy','-RepositoryDestination',$repoCopy))
    $local=Join-Path $out 'shooter-windows'
    Check ($r.code -eq 0 -and $r.text -match 'PLAYER_CLIENT_READY' -and $r.text -match 'REPOSITORY_CLIENT_READY') 'one export produces local and repository copies'
    $lv=Get-Content -Encoding UTF8 -Raw (Join-Path $local 'client-version.json') | ConvertFrom-Json
    $rv=Get-Content -Encoding UTF8 -Raw (Join-Path $repoCopy 'client-version.json') | ConvertFrom-Json
    $idx=Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesIndex | ConvertFrom-Json
    $lp=@($lv.files|Where-Object path -eq 'Client.pck')[0].sha256; $rp=@($rv.files|Where-Object path -eq 'Client.pck')[0].sha256
    Check ($lv.build_id -eq $idx.shooter.manifest.build_id -and $rv.build_id -eq $lv.build_id -and $lp -eq $rp -and $rv.release_tag -eq $lv.release_tag -and $lv.release_tag -match $lp.Substring(0,8)) 'local and GitHub copies share build, Client.pck hash and release tag'
    Check (-not (Test-Path (Join-Path $repoCopy 'connection.json')) -and -not (Test-Path (Join-Path $repoCopy 'server.crt')) -and (Test-Path (Join-Path $repoCopy 'FetchClient.ps1'))) 'repository copy has no server files and has FetchClient'
    $releaseDir=Join-Path $out ('release-'+$rv.release_tag)
    $releaseList=$(if(Test-Path ($releaseDir+'.json')){Get-Content -Encoding UTF8 -Raw ($releaseDir+'.json') | ConvertFrom-Json})
    $releaseOk=$null -ne $releaseList -and $releaseList.tag -eq $rv.release_tag -and $releaseList.build_id -eq $rv.build_id
    if($releaseOk) {
        $repoNames=@(Get-ChildItem -LiteralPath $repoCopy -File | ForEach-Object Name | Sort-Object)
        $releaseOk=((@($releaseList.assets.name) | Sort-Object) -join '|') -eq ($repoNames -join '|') -and (@($releaseList.assets.name) -contains 'Client.exe') -and -not (@($releaseList.assets.name) | Where-Object { $_ -in @('connection.json','server.crt') })
        foreach($asset in $releaseList.assets) { $releaseOk=$releaseOk -and (Get-FileHash (Join-Path $releaseDir $asset.name)).Hash -ieq $asset.sha256 -and (Get-FileHash (Join-Path $repoCopy $asset.name)).Hash -ieq $asset.sha256 }
        $sums=@(Get-Content -Encoding UTF8 ($releaseDir+'-SHA256SUMS.txt') | Where-Object { $_ })
        $releaseOk=$releaseOk -and $sums.Count -eq @($releaseList.assets).Count
    }
    Check $releaseOk ('Release attachment folder, list and SHA256SUMS match the repository copy incl. Client.exe ('+@($releaseList.assets).Count+' files)')
    $names=@(Get-ChildItem -LiteralPath $local -Recurse -File | ForEach-Object Name)
    Check (-not ($names | Where-Object { $_ -match '\.(key|sqlite|db)$' }) -and -not ((Get-Content -Raw (Join-Path $local 'server.crt')) -match 'PRIVATE KEY')) 'local directory has no private key or database'

    # Used player data must move to the new client, never into retention history.
    $runtimeData=Join-Path $local 'client-data'
    [void][IO.Directory]::CreateDirectory((Join-Path $runtimeData 'client-operations/server/account/game'))
    [IO.File]::WriteAllText((Join-Path $runtimeData 'settings.json'),'{"volume":0.5}', $utf8)
    [IO.File]::WriteAllText((Join-Path $runtimeData 'client-operations/server/account/game/pending.json'),'{"operation_id":"original-pending-id"}', $utf8)
    $runtimeBefore=Tree $runtimeData
    # Regeneration keeps the previous program directory without runtime data.
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -eq 0 -and $r.text -match 'PLAYER_CLIENT_PREVIOUS' -and @(Get-ChildItem (Join-Path $out 'previous') -Directory).Count -eq 1) 'regeneration moves the old directory to previous/'
    Check ((Tree $runtimeData) -ceq $runtimeBefore -and -not @(Get-ChildItem (Join-Path $out 'previous') -Recurse -Directory | Where-Object Name -eq 'client-data').Count) 'regeneration preserves original client data in new client only'
    $regenerated=Get-Content -Encoding UTF8 -Raw (Join-Path $local 'client-version.json') | ConvertFrom-Json
    Check (-not @($regenerated.generated_files | Where-Object path -match 'client-data').Count) 'runtime data never enters generated_files'

    # User-added and user-modified files block replacement; nothing changes.
    $before=Tree $local
    [IO.File]::WriteAllText((Join-Path $local 'my-notes.txt'),'keep me',$utf8)
    $before=Tree $local
    $r=Prepare ($common+@('-OutputRoot',$out))
    $addedRefused=$r.code -ne 0
    $addedDiagnostic=$r.text -match 'my-notes.txt'
    $addedTreeUnchanged=(Tree $local) -eq $before
    Check ($addedRefused -and $addedDiagnostic -and $addedTreeUnchanged) 'user-added file blocks replacement and directory is untouched'
    Remove-Item (Join-Path $local 'my-notes.txt')
    Add-Content -LiteralPath (Join-Path $local 'README.md') -Value 'edited'
    $before=Tree $local
    $r=Prepare ($common+@('-OutputRoot',$out))
    $modifiedRefused=$r.code -ne 0
    $modifiedDiagnostic=$r.text -match 'README.md'
    $modifiedTreeUnchanged=(Tree $local) -eq $before
    Check ($modifiedRefused -and $modifiedDiagnostic -and $modifiedTreeUnchanged) 'user-modified file blocks replacement and directory is untouched'
    # Restore the generated README by regenerating into a clean state via previous copy.
    Remove-Item -LiteralPath $local -Recurse -Force
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -eq 0) 'regeneration after removing the edited directory'

    # Injected failure during swap rolls back, including runtime data.
    [void][IO.Directory]::CreateDirectory((Join-Path $local 'client-data'))
    [IO.File]::WriteAllText((Join-Path $local 'client-data/settings.json'),'{"volume":0.5}', $utf8)
    $before=Tree $local
    $previousCount=@(Get-ChildItem (Join-Path $out 'previous') -Directory).Count
    $r=Prepare ($common+@('-OutputRoot',$out,'-TestFailAt','swap'))
    $swapRefused=$r.code -ne 0
    $rollbackDiagnostic=$r.text -match '已恢复旧目录'
    $oldTreeRestored=(Tree $local) -eq $before
    $previousCountUnchanged=@(Get-ChildItem (Join-Path $out 'previous') -Directory).Count -eq $previousCount
    $noStaging=-not (Get-ChildItem $out -Force -Filter '.staging-*')
    Check $swapRefused 'injected swap failure returns a refusal exit code'
    Check $rollbackDiagnostic 'swap failure preserves the Chinese restored-directory diagnostic'
    Check $oldTreeRestored 'swap failure restores the complete old directory tree'
    Check $previousCountUnchanged 'swap failure leaves the previous directory count unchanged'
    Check $noStaging 'swap failure leaves no staging'

    # Real login/join from a fresh copy outside the repository.
    AssertExternalFixture
    Copy-Item -LiteralPath $local -Destination $fresh -Recurse
    $check=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fresh 'CheckClient.ps1')
    Check ($LASTEXITCODE -eq 0 -and ($check -match 'server_configured=True')) 'CheckClient in fresh directory'
    foreach($name in @('a','b')) {
        $plan=Join-Path $ctx.test_root ('player-plan-'+$name+'.json')
        $report=Join-Path $evidence ('report-'+$name+'.json')
        [IO.File]::WriteAllText($plan,(@{username=('pc_'+$name+'_'+$runId.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('player_'+$name);invite_code=$ctx.invite_code;register=$true;room_id=$ctx.room_id;expect_players=2;hold_ms=4000;timeout_ms=120000;report_path=$report}|ConvertTo-Json),$utf8)
        # Player a: no --game and no --connection-config, started from an unrelated
        # working directory, so Client.exe must find connection.json beside itself.
        # It also leaves the room afterwards. Player b keeps the explicit arguments.
        if($name -eq 'a') {
            $arguments=@('--',('--autoplay='+$plan))
            $workingDirectory=[IO.Path]::GetTempPath()
            $planData=Get-Content -Encoding UTF8 -Raw $plan | ConvertFrom-Json
            $planData | Add-Member -NotePropertyName after -NotePropertyValue 'leave'
            [IO.File]::WriteAllText($plan,($planData|ConvertTo-Json),$utf8)
        } else {
            $arguments=@('--','--game=shooter',('--connection-config='+(Join-Path $fresh 'connection.json')),('--autoplay='+$plan))
            $workingDirectory=$fresh
        }
        if(-not $Visual) { $arguments=@('--headless')+$arguments }
        $process=Start-Process -FilePath (Join-Path $fresh 'Client.exe') -ArgumentList (Quote $arguments) -WorkingDirectory $workingDirectory -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence ('client-'+$name+'.log')) -RedirectStandardError (Join-Path $evidence ('client-'+$name+'-stderr.log'))
        $clients+=@{name=$name;process=$process;handle=$process.Handle;report=$report;plan=$plan}
    }
    foreach($client in $clients) {
        if(-not $client.process.WaitForExit(150000)) { $client.process.Kill(); $client.process.WaitForExit(); Check $false ('client '+$client.name+' finished in time') }
        Remove-Item -LiteralPath $client.plan -Force
    }
    $reports=@{}
    foreach($client in $clients) {
        $rep=$null
        if(Test-Path -LiteralPath $client.report) { $rep=Get-Content -Encoding UTF8 -Raw -LiteralPath $client.report | ConvertFrom-Json }
        $reports[$client.name]=$rep
        $expected=$(if($client.name -eq 'a'){'left_room'}else{'in_room_synced'})
        Check ($null -ne $rep -and $rep.ok -and $rep.stage -eq $expected -and $rep.room_id -eq $ctx.room_id -and $rep.build_id -eq $idx.shooter.manifest.build_id) ('exported client '+$client.name+' registered, logged in, joined'+$(if($client.name -eq 'a'){' and left'})+' the room (stage='+$(if($rep){$rep.stage}else{'none'})+')')
    }
    Check ($reports.a -and $reports.a.ok) 'Client.exe without arguments, from another working directory and a Chinese/space path, uses connection.json beside itself'

    $networkReports=Join-Path $fresh 'client-data/reports'
    $networkFiles=@(Get-ChildItem -LiteralPath $networkReports -Filter '*.jsonl' -File)
    $networkText=($networkFiles | ForEach-Object {[IO.File]::ReadAllText($_.FullName)}) -join "`n"
    $networkRows=@($networkText -split "`r?`n" | Where-Object {$_} | ForEach-Object {$_ | ConvertFrom-Json})
    Check ($networkFiles.Count -eq 2 -and $networkRows.Count -gt 0) 'two real exported clients keep bounded independent reports beside Client.exe'
    Check (@($networkRows | Where-Object {$_.phase -eq 'IN_ROOM'}).Count -gt 0) 'exported reports include actual in-room network samples'
    Check ($networkText -notmatch '"(password|token|ticket|username|user_id|invite_code)"\s*:' -and $networkText -notmatch [regex]::Escape($ctx.invite_code) -and $networkText -notmatch [regex]::Escape('pc_a_'+$runId.Substring(0,8))) 'exported reports omit account and invitation secrets'

    # Explorer double-click: explorer.exe starts Client.exe with no arguments and no
    # console parent. The window must appear and the game must not own a console.
    $before=@(Get-CimInstance Win32_Process -Filter "Name='Client.exe'" | ForEach-Object ProcessId)
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+(Join-Path $fresh 'Client.exe')+'"')
    $opened=$null; $d=[DateTime]::UtcNow.AddSeconds(30)
    do { Start-Sleep -Milliseconds 300; $opened=Get-CimInstance Win32_Process -Filter "Name='Client.exe'" | Where-Object { $_.ProcessId -notin $before -and $_.ExecutablePath -ieq (Join-Path $fresh 'Client.exe') } | Select-Object -First 1 } while($null -eq $opened -and [DateTime]::UtcNow -lt $d)
    Check ($null -ne $opened) 'explorer double-click starts Client.exe'
    if($opened) {
        $game=Get-Process -Id ([int]$opened.ProcessId)
        $d=[DateTime]::UtcNow.AddSeconds(30); do { Start-Sleep -Milliseconds 300; $game.Refresh() } while($game.MainWindowHandle -eq [IntPtr]::Zero -and -not $game.HasExited -and [DateTime]::UtcNow -lt $d)
        Check ($game.MainWindowHandle -ne [IntPtr]::Zero) ('double-clicked Client.exe shows its window ('+$game.MainWindowTitle+')')
        # Use the actual production guard against an actual exported process.
        . (Join-Path $project 'tools/artifact_retention.ps1')
        $guardTokens=$null;$guardErrors=$null
        $guardAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'tools/prepare_player_client.ps1'),[ref]$guardTokens,[ref]$guardErrors)
        if($guardErrors.Count){throw 'Generator parse failure during active-client check.'}
        $guard=$guardAst.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'AssertClientStopped'}
        . ([scriptblock]::Create($guard.Extent.Text))
        $runningRefusal=''
        try {AssertClientStopped $fresh} catch {$runningRefusal=$_.Exception.Message}
        Check ($runningRefusal -match 'CLIENT_RUNNING_CLOSE_FIRST' -and -not $game.HasExited) 'real active Client.exe blocks replacement without ending the game'
        # A separate probe process: AttachConsole(pid) succeeds only if the game owns a console.
        $probe='Add-Type -Namespace P -Name K -MemberDefinition ''[DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint p);''; [void][P.K]::FreeConsole(); if([P.K]::AttachConsole('+$game.Id+')){ exit 10 } else { exit 0 }'
        $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))) -PassThru -WindowStyle Hidden -Wait
        Check ($p.ExitCode -eq 0) ('double-clicked Client.exe has no console (probe exit '+$p.ExitCode+')')
        if(-not $game.HasExited -and $game.Path -ieq (Join-Path $fresh 'Client.exe')) { $game.CloseMainWindow() | Out-Null; if(-not $game.WaitForExit(8000)) { $game.Kill(); [void]$game.WaitForExit(5000) } }
    }
    if($reports.a -and $reports.b -and $reports.a.ok -and $reports.b.ok) {
        Check (@($reports.a.players) -contains $reports.b.user_id -and @($reports.b.players) -contains $reports.a.user_id) 'both players see each other in the room snapshot'
    }

    # Negative: a client built from changed code (one comment line in client.gd)
    # gets a different content-bound build_id, exactly as build_framework.ps1
    # would assign, and the unchanged server refuses it.
    $mismatchProject=Join-Path $evidence 'mismatch-project'
    Copy-Item -LiteralPath $idx.shooter.project -Destination $mismatchProject -Recurse
    Add-Content -LiteralPath (Join-Path $mismatchProject 'client.gd') -Value '# changed client code'
    $baseId=$idx.shooter.manifest.build_id -replace '-src-[0-9a-f]{12}$',''
    $changedId=$baseId+'-src-'+(ContentDigest $mismatchProject)
    Check ($changedId -ne $idx.shooter.manifest.build_id) ('changed client code yields a new build_id ('+$changedId+')')
    foreach($relative in @('game_manifest.json','game\game_manifest.json')) {
        $file=Join-Path $mismatchProject $relative
        $m=Get-Content -Encoding UTF8 -Raw -LiteralPath $file | ConvertFrom-Json
        $m.build_id=$changedId
        [IO.File]::WriteAllText($file,($m|ConvertTo-Json -Depth 20),$utf8)
    }
    $mismatchIndex=Join-Path $evidence 'mismatch-index.json'
    $alt=Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesIndex | ConvertFrom-Json
    $alt.shooter.project=$mismatchProject
    $alt.shooter.manifest.build_id=$changedId
    $alt.shooter.prepared_input_receipt=GetPreparedInputReceipt $mismatchProject
    [IO.File]::WriteAllText($mismatchIndex,($alt|ConvertTo-Json -Depth 30),$utf8)
    $mismatchOut=Join-Path $evidence 'mismatch-out'
    [void](Prepare @('-IndexPath',$mismatchIndex,'-ConnectionDirectory',$publicDir,'-OutputRoot',$mismatchOut))
    $mismatchClient=Join-Path $mismatchOut 'shooter-windows'
    $plan=Join-Path $ctx.test_root 'player-plan-c.json'
    $report=Join-Path $evidence 'report-c.json'
    [IO.File]::WriteAllText($plan,(@{username=('pc_c_'+$runId.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name='player_c';invite_code=$ctx.invite_code;register=$true;room_id=$ctx.room_id;expect_players=1;timeout_ms=30000;report_path=$report}|ConvertTo-Json),$utf8)
    $process=Start-Process -FilePath (Join-Path $mismatchClient 'Client.exe') -ArgumentList (Quote @('--headless','--','--game=shooter',('--connection-config='+(Join-Path $mismatchClient 'connection.json')),('--autoplay='+$plan))) -WorkingDirectory $mismatchClient -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'client-c.log') -RedirectStandardError (Join-Path $evidence 'client-c-stderr.log')
    $clients+=@{name='c';process=$process;handle=$process.Handle;report=$report;plan=$plan}
    if(-not $process.WaitForExit(90000)) { $process.Kill(); $process.WaitForExit() }
    Remove-Item -LiteralPath $plan -Force
    $rep=$null; if(Test-Path -LiteralPath $report) { $rep=Get-Content -Encoding UTF8 -Raw -LiteralPath $report | ConvertFrom-Json }
    Check ($null -ne $rep -and -not $rep.ok -and $rep.stage -ne 'in_room_synced' -and $rep.stage -ne 'in_room') ('mismatched build is refused (stage='+$(if($rep){$rep.stage+'; '+$rep.join_message}else{'none'})+')')
} finally {
    foreach($client in $clients) { if(-not $client.process.HasExited) { $client.process.Kill(); $client.process.WaitForExit() } }
    foreach($client in $clients) { if(Test-Path -LiteralPath $client.plan) { Remove-Item -LiteralPath $client.plan -Force } }
    if($null -ne $ctx) { [IO.File]::WriteAllText((Join-Path $ctx.test_root 'integration-done.request'),'done') }
    if(-not $operatorTest.WaitForExit(240000)) { Check $false 'isolated operator test finished' } else { Check ($operatorTest.ExitCode -eq 0) 'isolated operator shut down cleanly' }
    $sharedAfter=(Tree $sharedPublic)+'|'+$(if(Test-Path $sharedIndex){(Get-FileHash $sharedIndex).Hash})
    Check ($sharedAfter -eq $sharedBefore) 'shared artifacts/client and game index were never modified'
    if($externalOwned) {
        AssertExternalFixture
        if(Test-Path -LiteralPath $externalRoot) { Remove-Item -LiteralPath $externalRoot -Recurse -Force }
    }
    Write-Output ('PLAYER_CLIENT_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
if($script:failed) { exit 1 }
exit 0
