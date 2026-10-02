param([string]$EvidenceDirectory='')
# No engine/export, account service or real player directory. These are the
# generator's actual functions, loaded from its AST without executing its entry.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$run=[Guid]::NewGuid().ToString('N')
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $repository ('logs/player-rebuild-'+$run)}
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $evidence.StartsWith((Join-Path $repository 'logs')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $evidence)){throw 'Fresh project logs evidence required.'}
[void][IO.Directory]::CreateDirectory($evidence)
$project=Join-Path $evidence 'fixture';[void][IO.Directory]::CreateDirectory($project)
$utf8=New-Object Text.UTF8Encoding($false)
. (Join-Path $repository 'tools/artifact_retention.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'tools/prepare_player_client.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($node in $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] }) { . ([scriptblock]::Create($node.Extent.Text)) }
$script:passed=0;$script:failed=0
$TestFailAt='';$script:preserveStaging=$false
function Check([bool]$Condition,[string]$Name){if($Condition){$script:passed++;Write-Output ('PASS '+$Name)}else{$script:failed++;Write-Output ('FAIL '+$Name)}}
function WriteText([string]$Path,[string]$Text){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Tree([string]$Directory){
    if(-not(Test-Path -LiteralPath $Directory)){return '<missing>'}
    $items=@(Get-ChildItem -LiteralPath $Directory -Recurse -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Directory.Length+1).Replace('\','/')+'='+$(if($_.PSIsContainer){'<directory>'}else{(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) })
    return $items -join "`n"
}
function Client([string]$Name,[string]$Build){
    $directory=Join-Path $project $Name
    foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd','README.md')){WriteText (Join-Path $directory $name) ($Build+'-'+$name)}
    WriteVersion $directory ([ordered]@{format=2;build_id=$Build})
    return $directory
}
function AddRuntimeData([string]$Directory){
    WriteText (Join-Path $Directory 'client-data/settings.json') '{"volume":0.4,"muted":true}'
    WriteText (Join-Path $Directory 'client-data/diagnostics/session.jsonl') '{"session":"synthetic","rtt_ms":42}'
    WriteText (Join-Path $Directory 'client-data/client-operations/server/account/game/pending.json') '{"operation_id":"original-operation-123"}'
    [void][IO.Directory]::CreateDirectory((Join-Path $Directory 'client-data/empty'))
}
function Refuses([scriptblock]$Action,[string]$Pattern,[string]$Name){
    $failure='';try{& $Action | Out-Null}catch{$failure=$_.Exception.Message}
    Check ($failure -match $Pattern) ($Name+' ['+$failure+']')
}
function MakePair([string]$Name){
    $script:id=[Guid]::NewGuid().ToString('N')
    return @{target=(Client ($Name+'/old') 'old');stage=(Client ($Name+'/stage') 'new');backup=(Join-Path $project ($Name+'/previous'))}
}

# Chinese/space fixture and unrelated cwd: neither runtime data nor paths depend
# on the shell directory. UTF-8 BOM preserves the path in Windows PowerShell 5.1.
$pair=MakePair '玩家 更新 安全';AddRuntimeData $pair.target
$before=Tree (Join-Path $pair.target 'client-data')
$manifest=Get-Content (Join-Path $pair.target 'client-version.json') -Raw | ConvertFrom-Json
Check (-not @($manifest.generated_files | Where-Object path -match 'client-data').Count) 'runtime files are absent from generated_files'
$cwd=Join-Path $project 'unrelated';[void][IO.Directory]::CreateDirectory($cwd)
Push-Location $cwd
try{$backup=SafeReplace $pair.target $pair.stage $pair.backup}finally{Pop-Location}
Check ((Tree (Join-Path $pair.target 'client-data')) -ceq $before) 'successful rebuild preserves settings logs pending operation IDs and empty directories'
Check ((Get-Content (Join-Path $pair.target 'Client.pck') -Raw) -eq 'new-Client.pck') 'new client published'
Check ((Get-Content (Join-Path $backup 'Client.pck') -Raw) -eq 'old-Client.pck' -and -not(Test-Path (Join-Path $backup 'client-data'))) 'previous generation retains old program but no runtime data'
Check (-not(Test-Path $pair.stage)) 'stage consumed only on success'

foreach($failure in @('swap','swap-published','data-move','data-commit')){
    $pair=MakePair ('failure-'+$failure);AddRuntimeData $pair.target
    $oldTree=Tree $pair.target;$stageTree=Tree $pair.stage;$TestFailAt=$failure
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'TEST_INJECTED_' ($failure+' injection reports failure')
    Check ((Tree $pair.target) -ceq $oldTree) ($failure+' restores complete original client and data')
    Check ((Tree $pair.stage) -ceq $stageTree -and @(Get-ChildItem -LiteralPath $pair.backup -Force).Count -eq 0) ($failure+' restores clean stage and consumes rollback backup')
    Check (-not $script:preserveStaging) ($failure+' rollback finishes without recovery-required state')
}
$TestFailAt=''
foreach($unknown in @('unexpected.txt','data/client-operations/pending.json','logs/session.jsonl','client-data-other/private.json')){
    $pair=MakePair ('unknown-'+[Guid]::NewGuid().ToString('N'));AddRuntimeData $pair.target
    WriteText (Join-Path $pair.target $unknown) 'untouched';$before=Tree $pair.target
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} '新增|CLIENT_LEGACY_' ('unknown runtime file refused: '+$unknown)
    Check ((Tree $pair.target) -ceq $before -and -not(Test-Path $pair.backup)) 'refusal leaves original client and data untouched'
}
$pair=MakePair 'empty-unknown';[void][IO.Directory]::CreateDirectory((Join-Path $pair.target 'other-empty'))
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} '新增目录' 'unknown empty directory refused'
$pair=MakePair 'runtime-file';WriteText (Join-Path $pair.target 'client-data') 'not a directory'
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_EXPECTED_DIRECTORY' 'client-data must be a directory'
$pair=MakePair 'modified';AddRuntimeData $pair.target;WriteText (Join-Path $pair.target 'Client.pck') 'user changed';$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} '已改动' 'modified program still refused with runtime data'
Check ((Tree $pair.target) -ceq $before) 'modified program and runtime data not mutated'

# Plain-directory exemption never follows a link. Remove only the test-created
# link itself before later fixture inspection; never recurse into its target.
$linkType=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){'Junction'}else{'SymbolicLink'}
$canary=Join-Path $project 'canary';WriteText (Join-Path $canary 'keep.txt') 'untouched-canary'
foreach($relative in @('client-data','client-data/linked')){
    $pair=MakePair ('link-'+[Guid]::NewGuid().ToString('N'))
    $link=Join-Path $pair.target $relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($link))
    New-Item -ItemType $linkType -Path $link -Target $canary | Out-Null
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LINKED_CONTENT' ('linked runtime directory refused: '+$relative)
    Check (-not(Test-Path $pair.backup)) 'linked runtime refused before exchange'
    [IO.Directory]::Delete($link)
}
$pair=MakePair 'hardlink';AddRuntimeData $pair.target
$link=Join-Path $pair.target 'client-data/hardlink.txt'
New-Item -ItemType HardLink -Path $link -Target (Join-Path $canary 'keep.txt') | Out-Null
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LINKED_CONTENT' 'hard-linked runtime file refused'
Remove-Item -LiteralPath $link
Check ((Get-Content (Join-Path $canary 'keep.txt') -Raw) -eq 'untouched-canary') 'link target bytes remain intact'

# Actual owned sleeping shell references this directory. No process is killed
# except this test's own child, held by its original Process object.
$pair=MakePair 'running';AddRuntimeData $pair.target;$before=Tree $pair.target
$childScript=Join-Path $project 'held.ps1';WriteText $childScript 'param([string]$HeldDirectory) Start-Sleep -Seconds 30'
$arguments=@('-NoProfile','-NonInteractive','-File',$childScript,'-HeldDirectory',$pair.target)
$quoted=foreach($argument in $arguments){'"'+$argument.Replace('"','\"')+'"'}
$start=@{FilePath=(Get-Process -Id $PID).Path;ArgumentList=$quoted;PassThru=$true}
if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){$start.WindowStyle='Hidden'}
$child=Start-Process @start;$handle=$child.Handle
try{
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_RUNNING_CLOSE_FIRST' 'running client directory refused'
    Check ((Tree $pair.target) -ceq $before -and -not(Test-Path $pair.backup)) 'running-client refusal does not change program or data'
}finally{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)};$child.Dispose()}
$backup=SafeReplace $pair.target $pair.stage $pair.backup
Check (Test-Path (Join-Path $pair.target 'client-data/settings.json')) 'stopped process permits safe replacement'

$used=Client 'used-repository' 'release';AddRuntimeData $used
WriteText (Join-Path $used 'unlisted-secret.txt') 'synthetic-not-for-release'
$release=Join-Path $project 'clean-release';CopyGeneratedClient $used $release
$manifest=Get-Content (Join-Path $used 'client-version.json') -Raw | ConvertFrom-Json
$expected=@('client-version.json')+@($manifest.generated_files.path)
$actual=@(Get-ChildItem $release -File | ForEach-Object Name)
Check (((@($expected | Sort-Object)) -join '|') -ceq ((@($actual | Sort-Object)) -join '|')) 'release contains exactly generated whitelist and manifest'
Check (-not(Test-Path (Join-Path $release 'client-data')) -and -not(Test-Path (Join-Path $release 'unlisted-secret.txt'))) 'runtime and unlisted files cannot enter release'
Refuses {WriteVersion $used ([ordered]@{format=2;build_id='bad'})} 'CLIENT_RUNTIME_IN_DISTRIBUTION' 'used directory cannot become a generated manifest'
$manifest.generated_files+=@{path='client-data';sha256='not-used'}
WriteText (Join-Path $used 'client-version.json') ($manifest|ConvertTo-Json -Depth 10)
Refuses {CopyGeneratedClient $used (Join-Path $project 'bad-release')} 'CLIENT_INVALID_GENERATED_PATH' 'runtime path in a forged release whitelist is refused'
Check (-not(Test-Path (Join-Path $project 'bad-release'))) 'invalid whitelist creates no release directory'
$pair=MakePair 'unclean-stage';AddRuntimeData $pair.stage;$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_RUNTIME_IN_DISTRIBUTION' 'stage containing runtime data refused'
Check ((Tree $pair.target) -ceq $before) 'unclean stage leaves target intact'

$pair=MakePair 'used-release-target';AddRuntimeData $pair.target;$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup -CleanDistribution} 'CLIENT_RUNTIME_IN_RELEASE_TARGET' 'used release target refuses migration into clean distribution'
Check ((Tree $pair.target) -ceq $before -and -not(Test-Path $pair.backup)) 'used release refusal preserves full original client and data'

# Resource staging from a previously played generated project: privacy must
# hold before exporting the PCK, not merely in the outer player directory.
$source=Join-Path $project 'played-source';$work=Join-Path $project 'export-work'
foreach($name in @('project.godot','game_manifest.json','client.gd','view.gd','sound.gd','client_journal.gd','game/game.gd','game/game_config.json','sdk/roomkit/client/room_client.gd','schemas/public.json')) { WriteText (Join-Path $source $name) ('public-'+$name) }
foreach($name in @('data/client-local/source/settings.json','data/client-operations/pending.json','client-data/diagnostics/session.jsonl','logs/private.json','run/credentials.json','backups/account.json','connection.json','unknown-root.json','game/client-data/private.json','sdk/data/private.json')) { WriteText (Join-Path $source $name) 'PRIVATE_SYNTHETIC_CREDENTIAL_DO_NOT_EXPORT' }
CopyPlayerProject $source $work
Check ((Test-Path (Join-Path $work 'client_journal.gd')) -and (Test-Path (Join-Path $work 'sdk/roomkit/client/room_client.gd')) -and (Test-Path (Join-Path $work 'schemas/public.json'))) 'staged project keeps code modules SDK and schemas'
Check (-not @((Get-ChildItem $work -Recurse -File) | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('PRIVATE_SYNTHETIC_CREDENTIAL_DO_NOT_EXPORT') }).Count) 'source settings pending operations logs and unknown JSON never enter export work'
Check (-not @(Get-ChildItem $work -Recurse -Directory | Where-Object Name -in @('data','client-data','logs','run','backups')).Count) 'runtime directories excluded at every export-work depth'
$pair=MakePair 'check-client';AddRuntimeData $pair.target
Copy-Item -LiteralPath (Join-Path $repository 'tools/shooter_client/CheckClient.ps1') -Destination $pair.target
$checkOutput=& (Join-Path $pair.target 'CheckClient.ps1')
Check ($LASTEXITCODE -eq 0 -and ($checkOutput -join ' ') -match 'CLIENT_DATA_PRESENT') 'player selfcheck reports private runtime data without hashing it'
$link=Join-Path $pair.target 'client-data/link';New-Item -ItemType $linkType -Path $link -Target $canary | Out-Null
$checkOutput=& (Join-Path $pair.target 'CheckClient.ps1')
Check ($LASTEXITCODE -ne 0 -and ($checkOutput -join ' ') -match 'CLIENT_DATA_UNSAFE') 'player selfcheck refuses linked runtime data'
[IO.Directory]::Delete($link)

# Recognized pre-N1 pending receipts are migration inputs, never a broad data/
# exemption. Keep exact raw bytes/tree and defer server association to the client.
function AddLegacy([string]$Directory,[string]$Identity='n1-upgrade-account:shooter') {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $name=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Identity)))).Replace('-','').ToLowerInvariant()+'.json' } finally { $sha.Dispose() }
    $file=Join-Path $Directory ('data/client-operations/'+$name)
    WriteText $file ('{ "slot": "", "item_id": "smg", "operation_id": "0123456789abcdef0123456789abcdef", "kind": "purchase" }'+"`r`n")
    return $file
}
foreach($mixed in @($false,$true)) {
    $pair=MakePair ('legacy-success-'+$mixed);$receipt=AddLegacy $pair.target
    $legacyBefore=Tree (Join-Path $pair.target 'data')
    if($mixed) { AddRuntimeData $pair.target }
    $runtimeBefore=if($mixed){Tree (Join-Path $pair.target 'client-data')}else{''}
    $backup=SafeReplace $pair.target $pair.stage $pair.backup
    $quarantine=Join-Path $pair.target 'client-data/legacy-client-operations'
    Check ((Tree $quarantine) -ceq $legacyBefore) ('legacy '+$mixed+' preserves original receipt bytes IDs and directory tree')
    Check (-not(Test-Path (Join-Path $pair.target 'data')) -and -not(Test-Path (Join-Path $backup 'data')) -and -not(Test-Path (Join-Path $backup 'client-data'))) ('legacy '+$mixed+' leaves no runtime data in previous generation')
    if($mixed) {
        $now=((Tree (Join-Path $pair.target 'client-data')).Split("`n") | Where-Object { -not $_.StartsWith('legacy-client-operations',[StringComparison]::Ordinal) }) -join "`n"
        Check ($now -ceq $runtimeBefore) 'existing client-data and legacy receipts both survive upgrade'
    }
    $version=Get-Content (Join-Path $pair.target 'client-version.json') -Raw | ConvertFrom-Json
    Check (-not @($version.generated_files | Where-Object path -match 'data|legacy').Count) 'legacy quarantine never enters generated manifest'
}
$pair=MakePair 'legacy-empty';[void][IO.Directory]::CreateDirectory((Join-Path $pair.target 'data/client-operations'))
$backup=SafeReplace $pair.target $pair.stage $pair.backup
Check ((Test-Path (Join-Path $pair.target 'client-data/legacy-client-operations/client-operations') -PathType Container) -and @(Get-ChildItem (Join-Path $pair.target 'client-data/legacy-client-operations/client-operations') -Force).Count -eq 0) 'empty recognized legacy directory is preserved, not discarded'

foreach($mixed in @($false,$true)) {
    $points=if($mixed){@('swap','swap-published','data-move','data-commit','legacy-move','legacy-commit')}else{@('swap','swap-published','legacy-move','legacy-commit')}
    foreach($point in $points) {
        $pair=MakePair ('legacy-failure-'+$mixed+'-'+$point);$receipt=AddLegacy $pair.target
        if($mixed){AddRuntimeData $pair.target}
        $before=Tree $pair.target;$staged=Tree $pair.stage;$TestFailAt=$point
        Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'TEST_INJECTED_' ('legacy '+$mixed+' '+$point+' injection fails')
        Check ((Tree $pair.target) -ceq $before -and (Tree $pair.stage) -ceq $staged -and @(Get-ChildItem $pair.backup -Force).Count -eq 0 -and -not $script:preserveStaging) ('legacy '+$mixed+' '+$point+' reverse journal restores exact original client/data and stage')
    }
}
$TestFailAt=''
$invalidReceipts=@(
    '{"kind":"purchase","item_id":"smg","slot":"","operation_id":"short"}',
    '{"kind":"purchase","kind":"purchase","item_id":"smg","slot":"","operation_id":"0123456789abcdef0123456789abcdef"}',
    '{"kind":"purchase","item_id":"smg","slot":"","operation_id":"0123456789abcdef0123456789abcdef","token":"unrecognized"}',
    '{"kind":"PURCHASE","item_id":"smg","slot":"","operation_id":"0123456789abcdef0123456789abcdef"}',
    '{"kind":"purchase","item_id":{},"slot":"","operation_id":"0123456789abcdef0123456789abcdef"}',
    '{"kind":"purchase","item_id":"smg","slot":"","operation_id":"0123456789abcdef0123456789abcdef"',
    ('{"kind":"purchase","item_id":"'+('x'*129)+'","slot":"","operation_id":"0123456789abcdef0123456789abcdef"}')
)
foreach($bad in $invalidReceipts) {
    $pair=MakePair ('legacy-invalid-'+[Guid]::NewGuid().ToString('N'));$receipt=AddLegacy $pair.target;WriteText $receipt $bad;$before=Tree $pair.target
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LEGACY_INVALID_RECEIPT' 'malformed unknown duplicate or unbounded legacy receipt refused'
    Check ((Tree $pair.target) -ceq $before -and -not(Test-Path $pair.backup)) 'invalid legacy receipt refusal preserves complete original tree'
}
foreach($unknown in @('data/unknown-empty','data/client-operations/nested-empty')) {
    $pair=MakePair ('legacy-unknown-'+[Guid]::NewGuid().ToString('N'));$receipt=AddLegacy $pair.target
    [void][IO.Directory]::CreateDirectory((Join-Path $pair.target $unknown));$before=Tree $pair.target
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LEGACY_UNKNOWN_CONTENT' ('unknown legacy empty directory refused: '+$unknown)
    Check ((Tree $pair.target) -ceq $before) 'unknown empty directory not discarded'
}
$pair=MakePair 'legacy-wrong-name';$receipt=AddLegacy $pair.target
Move-Item -LiteralPath $receipt -Destination (Join-Path ([IO.Path]::GetDirectoryName($receipt)) 'not-a-hash.json');$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LEGACY_UNKNOWN_CONTENT' 'unrecognized legacy receipt filename refused'
Check ((Tree $pair.target) -ceq $before) 'wrong filename remains unchanged'
$pair=MakePair 'legacy-linked';$receipt=AddLegacy $pair.target
$link=Join-Path $pair.target 'data/client-operations/linked';New-Item -ItemType $linkType -Path $link -Target $canary | Out-Null
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LINKED_CONTENT' 'legacy linked descendant refused'
[IO.Directory]::Delete($link)
$pair=MakePair 'legacy-collision';$receipt=AddLegacy $pair.target
$existing=Join-Path $pair.target 'client-data/legacy-client-operations';[void][IO.Directory]::CreateDirectory($existing)
$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_LEGACY_QUARANTINE_COLLISION' 'existing quarantine collision refused even when empty'
Check ((Tree $pair.target) -ceq $before -and -not(Test-Path $pair.backup)) 'quarantine collision preserves both sources'
$pair=MakePair 'legacy-distribution';$receipt=AddLegacy $pair.target;$before=Tree $pair.target
Refuses {SafeReplace $pair.target $pair.stage $pair.backup -CleanDistribution} 'CLIENT_RUNTIME_IN_RELEASE_TARGET' 'legacy migration never writes into a clean release target'
Check ((Tree $pair.target) -ceq $before) 'used distribution preserved on legacy refusal'

foreach($relative in @('data/client-operations','data/client-local')) {
    $pair=MakePair ('unclean-'+$relative.Replace('/','-'));WriteText (Join-Path $pair.stage ($relative+'/private.json')) '{"private":true}'
    $before=Tree $pair.target
    Refuses {WriteVersion $pair.stage ([ordered]@{format=2;build_id='invalid'})} 'CLIENT_RUNTIME_IN_DISTRIBUTION' ('known runtime path cannot become generated manifest: '+$relative)
    Refuses {SafeReplace $pair.target $pair.stage $pair.backup} 'CLIENT_RUNTIME_IN_DISTRIBUTION' ('known runtime path cannot become first or replacement distribution: '+$relative)
    Check ((Tree $pair.target) -ceq $before) 'dirty runtime stage does not mutate original'
}

if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    # Real NTFS handle, not a synthetic TestFailAt. Read sharing permits validation
    # but denies delete sharing required by replacement. Preserve all old bytes.
    $pair=MakePair 'native-file-lock';AddRuntimeData $pair.target
    $before=Tree $pair.target;$staged=Tree $pair.stage
    $locked=[IO.File]::Open((Join-Path $pair.target 'Client.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $lockFailure=''
    try { try {SafeReplace $pair.target $pair.stage $pair.backup | Out-Null} catch {$lockFailure=$_.Exception.Message} }
    finally {$locked.Dispose()}
    Check ($lockFailure -ne '') 'real NTFS file lock refuses replacement'
    Check ((Tree $pair.target) -ceq $before -and (Tree $pair.stage) -ceq $staged) 'real locked replacement preserves target and staging bytes'
}

# Retain an exact tiny successful output for the lead's real Godot module check.
$pair=MakePair 'legacy-end-to-end';$receipt=AddLegacy $pair.target
$backup=SafeReplace $pair.target $pair.stage $pair.backup
$integration=[ordered]@{target=$pair.target;account='n1-upgrade-account';game='shooter';operation_id='0123456789abcdef0123456789abcdef';quarantine='client-data/legacy-client-operations/client-operations';network_actions=0}
WriteText (Join-Path $evidence 'integration-fixture.json') ($integration|ConvertTo-Json)
Write-Output ('LEGACY_INTEGRATION_TARGET '+$pair.target)

$result=[ordered]@{passed=$script:passed;failed=$script:failed;runtime=$PSVersionTable.PSVersion.ToString();scope='actual generator functions; small fixtures and one owned sleeping shell; no Godot or exported client';evidence=$evidence}
WriteText (Join-Path $evidence 'result.json') ($result|ConvertTo-Json)
Write-Output ('PLAYER_REBUILD_TEST '+$script:passed+'/'+$script:failed+' evidence='+$evidence)
if($script:failed){exit 1};exit 0
