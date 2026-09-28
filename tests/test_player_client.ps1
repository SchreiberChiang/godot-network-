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
$fresh=Join-Path ([IO.Path]::GetTempPath()) ('RoomKit-player-client-'+$runId)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0; $script:failed=0
function Check([bool]$condition,[string]$name) { if($condition){$script:passed++;Write-Output ('PASS '+$name)}else{$script:failed++;Write-Output ('FAIL '+$name)} }
function Quote($values) { foreach($value in $values){'"'+([string]$value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'} }
function Tree([string]$Directory) {
    if(-not (Test-Path -LiteralPath $Directory)) { return '' }
    return ((Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Directory.Length)+'='+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
$script:prepareRun=0
function Prepare([string[]]$Extra) {
    $script:prepareRun++
    $log=Join-Path $evidence ('prepare-'+$script:prepareRun+'.log')
    $ErrorActionPreference='Continue' # expected refusals arrive on stderr
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'tools\prepare_player_client.ps1') -Godot $Godot @Extra 2>&1 | ForEach-Object { [string]$_ }
    $code=$LASTEXITCODE
    $output | Set-Content -Encoding UTF8 $log
    return @{code=$code;text=($output -join "`n")}
}

$sharedPublic=Join-Path $project 'artifacts\client'
$sharedIndex=Join-Path $project 'artifacts\framework-games.json'
$sharedBefore=(Tree $sharedPublic)+'|'+$(if(Test-Path $sharedIndex){(Get-FileHash $sharedIndex).Hash})
$gamesIndex=Join-Path $evidence 'framework-games.json'
& (Join-Path $project 'tools\build_framework.ps1') -IndexPath $gamesIndex | Out-Null
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
    $outside=Join-Path ([IO.Path]::GetTempPath()) ('RoomKit-outside-'+$runId)
    $r=Prepare ($common+@('-OutputRoot',$outside))
    Check ($r.code -ne 0 -and -not (Test-Path $outside) -and $r.text -match '受控范围') 'output outside artifacts/logs is refused and nothing is created'
    $r=Prepare ($common+@('-OutputRoot',$out,'-RepositoryCopy','-RepositoryDestination',(Join-Path $project 'docs\evil')))
    Check ($r.code -ne 0 -and -not (Test-Path (Join-Path $project 'docs\evil'))) 'repository copy outside its fixed location is refused'

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
    $names=@(Get-ChildItem -LiteralPath $local -Recurse -File | ForEach-Object Name)
    Check (-not ($names | Where-Object { $_ -match '\.(key|sqlite|db)$' }) -and -not ((Get-Content -Raw (Join-Path $local 'server.crt')) -match 'PRIVATE KEY')) 'local directory has no private key or database'

    # Regeneration keeps the previous directory.
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -eq 0 -and $r.text -match 'PLAYER_CLIENT_PREVIOUS' -and @(Get-ChildItem (Join-Path $out 'previous') -Directory).Count -eq 1) 'regeneration moves the old directory to previous/'

    # User-added and user-modified files block replacement; nothing changes.
    $before=Tree $local
    [IO.File]::WriteAllText((Join-Path $local 'my-notes.txt'),'keep me',$utf8)
    $before=Tree $local
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -ne 0 -and $r.text -match 'my-notes.txt' -and (Tree $local) -eq $before) 'user-added file blocks replacement and directory is untouched'
    Remove-Item (Join-Path $local 'my-notes.txt')
    Add-Content -LiteralPath (Join-Path $local 'README.md') -Value 'edited'
    $before=Tree $local
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -ne 0 -and $r.text -match 'README.md' -and (Tree $local) -eq $before) 'user-modified file blocks replacement and directory is untouched'
    # Restore the generated README by regenerating into a clean state via previous copy.
    Remove-Item -LiteralPath $local -Recurse -Force
    $r=Prepare ($common+@('-OutputRoot',$out))
    Check ($r.code -eq 0) 'regeneration after removing the edited directory'

    # Injected failure during swap rolls back.
    $before=Tree $local
    $previousCount=@(Get-ChildItem (Join-Path $out 'previous') -Directory).Count
    $r=Prepare ($common+@('-OutputRoot',$out,'-TestFailAt','swap'))
    Check ($r.code -ne 0 -and $r.text -match '已恢复旧目录' -and (Tree $local) -eq $before -and @(Get-ChildItem (Join-Path $out 'previous') -Directory).Count -eq $previousCount -and -not (Get-ChildItem $out -Force -Filter '.staging-*')) 'swap failure restores the old directory and leaves no staging'

    # Real login/join from a fresh copy outside the repository.
    Copy-Item -LiteralPath $local -Destination $fresh -Recurse
    $check=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fresh 'CheckClient.ps1')
    Check ($LASTEXITCODE -eq 0 -and ($check -match 'server_configured=True')) 'CheckClient in fresh directory'
    foreach($name in @('a','b')) {
        $plan=Join-Path $ctx.test_root ('player-plan-'+$name+'.json')
        $report=Join-Path $evidence ('report-'+$name+'.json')
        [IO.File]::WriteAllText($plan,(@{username=('pc_'+$name+'_'+$runId.Substring(0,8));password=('Player!'+[Guid]::NewGuid().ToString('N'));display_name=('player_'+$name);invite_code=$ctx.invite_code;register=$true;room_id=$ctx.room_id;expect_players=2;hold_ms=4000;timeout_ms=120000;report_path=$report}|ConvertTo-Json),$utf8)
        $arguments=@('--','--game=shooter',('--connection-config='+(Join-Path $fresh 'connection.json')),('--autoplay='+$plan))
        if(-not $Visual) { $arguments=@('--headless')+$arguments }
        $process=Start-Process -FilePath (Join-Path $fresh 'Client.exe') -ArgumentList (Quote $arguments) -WorkingDirectory $fresh -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence ('client-'+$name+'.log')) -RedirectStandardError (Join-Path $evidence ('client-'+$name+'-stderr.log'))
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
        Check ($null -ne $rep -and $rep.ok -and $rep.stage -eq 'in_room_synced' -and $rep.room_id -eq $ctx.room_id -and $rep.build_id -eq $idx.shooter.manifest.build_id) ('exported client '+$client.name+' registered, logged in and joined the room (stage='+$(if($rep){$rep.stage}else{'none'})+')')
    }
    if($reports.a -and $reports.b -and $reports.a.ok -and $reports.b.ok) {
        Check (@($reports.a.players) -contains $reports.b.user_id -and @($reports.b.players) -contains $reports.a.user_id) 'both players see each other in the room snapshot'
    }

    # Negative: a client exported from a copy whose build_id differs is refused.
    $mismatchProject=Join-Path $evidence 'mismatch-project'
    Copy-Item -LiteralPath $idx.shooter.project -Destination $mismatchProject -Recurse
    foreach($relative in @('game_manifest.json','game\game_manifest.json')) {
        $file=Join-Path $mismatchProject $relative
        $m=Get-Content -Encoding UTF8 -Raw -LiteralPath $file | ConvertFrom-Json
        $m.build_id=$m.build_id+'-mismatch'
        [IO.File]::WriteAllText($file,($m|ConvertTo-Json -Depth 20),$utf8)
    }
    $mismatchIndex=Join-Path $evidence 'mismatch-index.json'
    $alt=Get-Content -Encoding UTF8 -Raw -LiteralPath $gamesIndex | ConvertFrom-Json
    $alt.shooter.project=$mismatchProject
    $alt.shooter.manifest.build_id=$alt.shooter.manifest.build_id+'-mismatch'
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
    if(Test-Path -LiteralPath $fresh) { Remove-Item -LiteralPath $fresh -Recurse -Force }
    Write-Output ('PLAYER_CLIENT_RESULT passed='+$script:passed+' failed='+$script:failed+' evidence='+$evidence)
}
if($script:failed) { exit 1 }
exit 0
