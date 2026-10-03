param([ValidatePattern('^[a-z0-9-]+$')][string]$RunName='final',[switch]$Resume)
# Real generator + disposable native exporter. No service, real template or pack.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $repository ('logs/release-guards-20261003/identity/'+$RunName)
if(Test-Path -LiteralPath $run){
    if(-not $Resume){throw 'Preserve previous evidence; choose another run name.'}
    $prior=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($prior.scope -ne 'native fixture + actual generator; not real Godot export'){throw 'Unknown prior fixture, refused resume'}
    $history=Join-Path $run ('previous-'+$prior.passed+'-'+$prior.failed)
    if(Test-Path -LiteralPath $history){$history+='-interrupted-'+[Guid]::NewGuid().ToString('N').Substring(0,8)}
    [void][IO.Directory]::CreateDirectory($history)
    foreach($file in Get-ChildItem -LiteralPath $run -File){Copy-Item -LiteralPath $file.FullName -Destination $history}
    Copy-Item -LiteralPath (Join-Path $run 'generator space/tools') -Destination (Join-Path $history 'generator-tools') -Recurse
}elseif($Resume){throw 'Resume requires an existing recognized fixture'}
$utf8=New-Object Text.UTF8Encoding($false)
$passed=0;$failed=0;$results=New-Object Collections.ArrayList;$commands=New-Object Collections.ArrayList
function Put([string]$Path,[string]$Value){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Value,$utf8)}
function Check([bool]$Value,[string]$Name){if($Value){$script:passed++;Write-Output ('PASS '+$Name)}else{$script:failed++;Write-Output ('FAIL '+$Name)};[void]$results.Add(@{name=$Name;passed=$Value})}
function ReferenceReceipt([string]$Folder){
    # Independent fixed fixture list: none of its four resources may disappear.
    $names=@('client.gd','game/game_manifest.json','game_manifest.json','project.godot')
    if(Test-Path -LiteralPath (Join-Path $Folder 'client.gd.uid')){$names+=@('client.gd.uid')}
    $names=[string[]]$names;[Array]::Sort($names,[StringComparer]::Ordinal)
    $files=$names | ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $Folder $_) -Algorithm SHA256).Hash.ToLowerInvariant()}}
    $text='roomkit-prepared-input-v1'+"`n"+(($files | ForEach-Object {$_.path+'='+$_.sha256}) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$digest=([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($text))) -replace '-','').ToLowerInvariant()}finally{$sha.Dispose()}
    return @{format=1;algorithm='roomkit-prepared-input-v1';sha256=$digest;files=@($files)}
}
function InvokeGenerator([string]$Name,[string]$Source,[string]$Index,[string]$Engine){
    $out=Join-Path $generator ('artifacts/output-'+$Name)
    $parameters=@{Godot=$Engine;IndexPath=$Index;OutputRoot=$out;Unconfigured=$true}
    $payload=[Convert]::ToBase64String($utf8.GetBytes((@{script=(Join-Path $generator 'tools/prepare_player_client.ps1');parameters=$parameters}|ConvertTo-Json -Compress)))
    $command='$ErrorActionPreference="Stop";$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$payload+'"))|ConvertFrom-Json;$a=@{};foreach($f in $p.parameters.PSObject.Properties){$a[$f.Name]=$f.Value};try{& $p.script @a;exit 0}catch{[Console]::Error.WriteLine(($_|Out-String));exit 1}'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName='powershell.exe';$start.Arguments='-NoProfile -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $p=[Diagnostics.Process]::Start($start)
    try{$so=$p.StandardOutput.ReadToEndAsync();$se=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(60000)){$p.Kill();$p.WaitForExit();throw 'Owned fixture generator timeout'};$text=$so.Result+"`n"+$se.Result;Put (Join-Path $run ($Name+'.stdout.txt')) $so.Result;Put (Join-Path $run ($Name+'.stderr.txt')) $se.Result;return @{code=$p.ExitCode;text=$text;published=(Test-Path -LiteralPath (Join-Path $out 'shooter-windows/client-version.json'));out=$out}}finally{$p.Dispose()}
}
[void][IO.Directory]::CreateDirectory($run)
$generator=Join-Path $run 'generator space'
foreach($name in @('prepare_player_client.ps1','artifact_retention.ps1','content_digest.ps1','prepared_input.ps1')){
    $path=Join-Path $repository ('tools/'+$name)
    if(Test-Path -LiteralPath $path){[void][IO.Directory]::CreateDirectory((Join-Path $generator 'tools'));Copy-Item -LiteralPath $path -Destination (Join-Path $generator ('tools/'+$name))}
}
$helperDestination=Join-Path $generator 'tools/shooter_client'
[void][IO.Directory]::CreateDirectory($helperDestination)
foreach($helper in Get-ChildItem -LiteralPath (Join-Path $repository 'tools/shooter_client') -File){
    Copy-Item -LiteralPath $helper.FullName -Destination (Join-Path $helperDestination $helper.Name)
}
$engine=Join-Path $run 'native/Fixture.exe'
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try{$env:TEMP=Join-Path $run 'compiler-temp';$env:TMP=$env:TEMP;[void][IO.Directory]::CreateDirectory($env:TEMP);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($engine));if(-not $Resume){Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/prepared_exporter.cs'))) -OutputAssembly $engine -OutputType WindowsApplication}}finally{$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'editor_data/export_templates/4.7.2.stable/windows_release_x86_64.exe') 'FAKE_TEMPLATE_NEVER_RUN'
$cases=@('consistent','changed-code','added-resource','deleted-resource','missing-receipt','wrong-algorithm','wrong-hash','room-manifest','root-manifest','private-runtime','random-release-id','mutate-frozen','mutate-original','generated-uids','existing-uid','orphan-uid','export-failure')
foreach($name in $cases){
    $source=Join-Path $generator ('artifacts/prepared-'+$name)
    $build=if($name -eq 'random-release-id'){'shooter-framework-win-test'}else{'shooter-src-fixed-fixture'}
    $manifest=@{game_id='shooter';build_id=$build;compatibility_id='shooter-v3';game_protocol=3}
    Put (Join-Path $source 'project.godot') "config_version=5`n[application]`nconfig/name=`"Fixture`"`n"
    Put (Join-Path $source 'client.gd') "extends SceneTree`nconst VALUE=1`n"
    foreach($path in @('game_manifest.json','game/game_manifest.json')){Put (Join-Path $source $path) ($manifest|ConvertTo-Json)}
    if($name -eq 'existing-uid'){Put (Join-Path $source 'client.gd.uid') 'uid://original'}
    $receipt=ReferenceReceipt $source
    $entry=@{project=$source;manifest=$manifest;prepared_input_receipt=$receipt}
    switch($name){
        'changed-code'{Put (Join-Path $source 'client.gd') "extends SceneTree`nconst VALUE=2`n"}
        'added-resource'{Put (Join-Path $source 'game/new.json') '{"added":true}'}
        'deleted-resource'{Remove-Item -LiteralPath (Join-Path $source 'client.gd')}
        'missing-receipt'{$entry.Remove('prepared_input_receipt')}
        'wrong-algorithm'{$receipt.algorithm='unknown'}
        'wrong-hash'{$receipt.sha256=('0'*64)}
        'room-manifest'{Put (Join-Path $source 'game/game_manifest.json') '{"game_id":"shooter","build_id":"other","compatibility_id":"shooter-v3","game_protocol":3}'}
        'root-manifest'{Put (Join-Path $source 'game_manifest.json') '{"game_id":"shooter","build_id":"other","compatibility_id":"shooter-v3","game_protocol":3}'}
        'private-runtime'{Put (Join-Path $source 'data/secret.json') '{"private":"fixture"}';Put (Join-Path $source 'sdk/client-data/settings.json') '{}';Put (Join-Path $source '.godot/cache.txt') 'cache'}
        'mutate-frozen'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'mutate-frozen.txt') 'mutate'}
        'mutate-original'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'mutate-original.txt') (Join-Path $source 'client.gd')}
        'generated-uids'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'generate-uids.txt') 'uids'}
        'existing-uid'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'change-existing-uid.txt') 'change'}
        'orphan-uid'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'orphan-uid.txt') 'orphan'}
        'export-failure'{Put (Join-Path ([IO.Path]::GetDirectoryName($engine)) 'fail-export.txt') 'fail'}
    }
    $index=Join-Path $generator ('artifacts/index-'+$name+'.json');Put $index (@{shooter=$entry}|ConvertTo-Json -Depth 12)
    $r=InvokeGenerator $name $source $index $engine
    [void]$commands.Add([ordered]@{name=$name;exit_code=$r.code;published=$r.published;stdout=($name+'.stdout.txt');stderr=($name+'.stderr.txt');expected_receipt=$receipt.sha256})
    $success=$name -in @('consistent','private-runtime','random-release-id','generated-uids')
    Check $(if($success){$r.code -eq 0 -and $r.published}else{$r.code -ne 0 -and -not $r.published}) $name
    if($success){Check ((ReferenceReceipt $source).sha256 -ceq $receipt.sha256) ($name+'-original-preserved')}
    if($name -eq 'private-runtime' -and $r.published){$leak=@(Get-ChildItem -LiteralPath $r.out -Recurse -File | Where-Object {$_.FullName -match '[\\/](data|client-data)[\\/]'});Check ($leak.Count -eq 0) 'private-state-not-copied'}
    foreach($marker in @('mutate-frozen.txt','mutate-original.txt','generate-uids.txt','change-existing-uid.txt','orphan-uid.txt','fail-export.txt')){$p=Join-Path ([IO.Path]::GetDirectoryName($engine)) $marker;if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p}}
}
if(Test-Path -LiteralPath (Join-Path $repository 'tools/prepared_input.ps1')){
    . (Join-Path $repository 'tools/prepared_input.ps1')
    $origin=Join-Path $generator 'artifacts/prepared-consistent'
    $original=ReferenceReceipt $origin
    $work=Join-Path $run ('bootstrap-window-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
    CopyPreparedInput $origin $work;AssertPreparedInputReceipt $work $original
    Put (Join-Path $work 'main.gd') "extends `"res://client.gd`"`n"
    Put (Join-Path $work 'empty.tscn') '[gd_scene format=3]'
    Put (Join-Path $work 'export_presets.cfg') '[preset.0]'
    $bootstrapHashes=@{'main.gd'=(PreparedInputHash $utf8.GetBytes("extends `"res://client.gd`"`n"));'empty.tscn'=(PreparedInputHash $utf8.GetBytes('[gd_scene format=3]'));'export_presets.cfg'=(PreparedInputHash $utf8.GetBytes('[preset.0]'));'project.godot'=@($original.files|Where-Object {$_.path -ceq 'project.godot'})[0].sha256}
    # A changed resource must never become trusted by re-baselining after bootstrap.
    Put (Join-Path $work 'client.gd') "extends SceneTree`nconst VALUE=99`n"
    $refused=$false;try{[void](NewPreparedExportReceipt $work $original $bootstrapHashes)}catch{$refused=$_.Exception.Message -like '*PREPARED_INPUT_CHANGED*'}
    Check $refused 'bootstrap-window-change-rejected'
    Copy-Item -LiteralPath (Join-Path $origin 'client.gd') -Destination (Join-Path $work 'client.gd')
    $first=NewPreparedExportReceipt $work $original $bootstrapHashes
    AssertPreparedInputReceipt $work $first -ExportWork
    Put (Join-Path $work 'client.gd') "extends SceneTree`nconst VALUE=100`n"
    $refused=$false;try{[void](NewPreparedExportReceipt $work $original $bootstrapHashes)}catch{$refused=$_.Exception.Message -like '*PREPARED_INPUT_CHANGED*'}
    Check $refused 'between-export-change-rejected'
    Copy-Item -LiteralPath (Join-Path $origin 'client.gd') -Destination (Join-Path $work 'client.gd')
    Put (Join-Path $work 'main.gd') "extends `"res://changed.gd`"`n"
    $refused=$false;try{[void](NewPreparedExportReceipt $work $original $bootstrapHashes)}catch{$refused=$_.Exception.Message -like '*PREPARED_INPUT_CHANGED*'}
    Check $refused 'bootstrap-entry-change-rejected'
    Put (Join-Path $work 'main.gd') "extends `"res://client.gd`"`n"
    Put (Join-Path $work 'export_presets.cfg') '[preset.666]'
    $refused=$false;try{[void](NewPreparedExportReceipt $work $original $bootstrapHashes)}catch{$refused=$_.Exception.Message -like '*PREPARED_INPUT_CHANGED*'}
    Check $refused 'bootstrap-preset-change-rejected'
    # Case-preserving paths are part of receipt; not an OS-insensitive identity.
    $caseRoot=Join-Path $run ('case-rename-'+[Guid]::NewGuid().ToString('N').Substring(0,8));CopyPreparedInput $origin $caseRoot
    Rename-Item -LiteralPath (Join-Path $caseRoot 'client.gd') -NewName 'temporary.gd'
    Rename-Item -LiteralPath (Join-Path $caseRoot 'temporary.gd') -NewName 'CLIENT.gd'
    $refused=$false;try{AssertPreparedInputReceipt $caseRoot $original}catch{$refused=$_.Exception.Message -like '*PREPARED_INPUT_CHANGED*'}
    Check $refused 'case-only-rename-rejected'
}
Put (Join-Path $run 'result.json') (@{passed=$passed;failed=$failed;checks=@($results);commands=@($commands);scope='native fixture + actual generator; not real Godot export';source_commit=(git -C $repository rev-parse HEAD).Trim()}|ConvertTo-Json -Depth 7)
Write-Output ('PREPARED_IDENTITY_RESULT '+$passed+'/'+$failed)
if($failed){exit 1}
exit 0
