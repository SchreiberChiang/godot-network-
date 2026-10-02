param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
# A tiny cross-runtime fixture: actual generator transaction, then Godot consumes
# its quarantined receipt with run_client_upgrade_receipt.gd. No Windows export.
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $evidence.StartsWith((Join-Path $repository 'logs')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $evidence)){throw 'Fresh project-local evidence directory required.'}
[void][IO.Directory]::CreateDirectory($evidence)
$project=Join-Path $evidence 'fixture';[void][IO.Directory]::CreateDirectory($project)
$utf8=New-Object Text.UTF8Encoding($false)
. (Join-Path $repository 'tools/artifact_retention.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'tools/prepare_player_client.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($node in $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] }) { . ([scriptblock]::Create($node.Extent.Text)) }
function WriteFixture([string]$Path,[string]$Text) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8) }
function NewFixtureClient([string]$Path,[string]$Build) {
    foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd','README.md')){WriteFixture (Join-Path $Path $name) ($Build+'-'+$name)}
    WriteVersion $Path ([ordered]@{format=2;build_id=$Build})
}
$target=Join-Path $project 'upgraded-player';$stage=Join-Path $project 'stage'
NewFixtureClient $target 'old';NewFixtureClient $stage 'new'
$sha=[Security.Cryptography.SHA256]::Create()
try {$filename=([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes('n1-upgrade-account:shooter')))).Replace('-','').ToLowerInvariant()+'.json'} finally {$sha.Dispose()}
$receipt='{"kind":"purchase","item_id":"smg","slot":"","operation_id":"0123456789abcdef0123456789abcdef"}'
WriteFixture (Join-Path $target ('data/client-operations/'+$filename)) $receipt
WriteFixture (Join-Path $target 'client-data/settings/existing.json') '{"volume":0.4,"muted":false}'
$id=[Guid]::NewGuid().ToString('N');$TestFailAt='';$script:preserveStaging=$false
$backup=SafeReplace $target $stage (Join-Path $project 'previous')
$quarantine=Join-Path $target ('client-data/legacy-client-operations/client-operations/'+$filename)
if(-not(Test-Path -LiteralPath $quarantine) -or [IO.File]::ReadAllText($quarantine) -cne $receipt){throw 'Legacy receipt bytes changed during actual generator transaction.'}
if(Test-Path -LiteralPath (Join-Path $target 'data')){throw 'Legacy data not unified under client-data.'}
if(Test-Path -LiteralPath (Join-Path $backup 'data')){throw 'Legacy data left in deletable previous directory.'}
if(-not(Test-Path -LiteralPath (Join-Path $target 'client-data/settings/existing.json'))){throw 'Existing local data lost.'}
$result=[ordered]@{passed=4;failed=0;target=$target;data_root=(Join-Path $target 'client-data');quarantined_sha256=(Get-FileHash -LiteralPath $quarantine -Algorithm SHA256).Hash.ToLowerInvariant();scope='actual SafeReplace tiny files; no Windows export'}
[IO.File]::WriteAllText((Join-Path $evidence 'fixture.json'),($result|ConvertTo-Json -Depth 4),$utf8)
Write-Output ('CLIENT_UPGRADE_FIXTURE_RESULT '+($result|ConvertTo-Json -Compress))
