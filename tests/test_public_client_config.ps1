param([string]$Project='', [string]$OutputDirectory='', [string]$PowerShell='powershell.exe')
$ErrorActionPreference='Stop'
if(-not $Project) { $Project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
if(-not $OutputDirectory) { $OutputDirectory=Join-Path $Project ('data/public-client-config-'+[Guid]::NewGuid().ToString('N')) }
$base=[IO.Path]::GetFullPath((Join-Path $Project 'data')).TrimEnd('\','/')
$work=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(-not $work.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $work)) { throw 'Require a fresh directory beneath project data.' }
for($cursor=$work;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)) { if(Test-Path -LiteralPath $cursor) { if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked test path' } } }
$utf8=New-Object Text.UTF8Encoding($false)
$source=Join-Path $work 'source'; $target=Join-Path $work 'fakeClient'
New-Item -ItemType Directory -Path $source,$target -Force | Out-Null
foreach($name in @('SetServer.ps1','CheckClient.ps1','public_config.ps1')) {
    $path=Join-Path $Project ('tools/shooter_client/'+$name)
    if(Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $target }
}
# Fixed public audit certificate only. No certificate store, private key, TLS,
# server, Godot process, mail client or network is used by this fixture.
$pem=[IO.File]::ReadAllText((Join-Path $Project 'tests/support/public-test-certificate.crt'))
$script:checks=New-Object 'Collections.Generic.List[object]'
$script:commands=New-Object 'Collections.Generic.List[object]'
function Config { return [ordered]@{url='wss://example.invalid:28300';ca_certificate='server.crt';server_hostname='localhost';managed=$true;secure_enet=$true;report_email='contact@example.invalid'} }
function Save([string]$Path,[object]$Value) { [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 6),$utf8) }
function Reset {
    Save (Join-Path $source 'connection.json') (Config)
    [IO.File]::WriteAllText((Join-Path $source 'server.crt'),$pem,$utf8)
    Save (Join-Path $target 'connection.json') (Config)
    [IO.File]::WriteAllText((Join-Path $target 'server.crt'),$pem,$utf8)
    Save (Join-Path $target 'client-version.json') @{build_id='fixture';files=@();generated_files=@()}
}
function Snapshot {
    return (((Get-FileHash -LiteralPath (Join-Path $target 'connection.json')).Hash)+':'+((Get-FileHash -LiteralPath (Join-Path $target 'server.crt')).Hash))
}
function Run([string]$Script,[string[]]$Arguments=@()) {
    $args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $target $Script))+$Arguments
    $oldPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { $output=@(& $PowerShell @args 2>&1); $code=$LASTEXITCODE } finally { $ErrorActionPreference=$oldPreference }
    $name='command-'+($script:commands.Count+1)+'.txt'
    $output | Out-File -LiteralPath (Join-Path $work $name) -Encoding utf8
    $script:commands.Add([ordered]@{script=$Script;arguments=$Arguments;exit_code=$code;output=$name})
    return [pscustomobject]@{code=$code;text=($output -join "`n")}
}
function Check([bool]$Ok,[string]$Name) {
    $script:checks.Add([ordered]@{name=$Name;passed=$Ok})
    Write-Output ((@('FAIL','PASS')[[int]$Ok])+' '+$Name)
}
function RejectConfig([string]$Name,[object]$Value) {
    Reset; Save (Join-Path $source 'connection.json') $Value
    $before=Snapshot; $result=Run 'SetServer.ps1' @('-Source',$source)
    Check ($result.code -ne 0 -and (Snapshot) -ceq $before) ('SetServer rejects '+$Name+' without writing')
    Save (Join-Path $target 'connection.json') $Value
    $before=Snapshot; $result=Run 'CheckClient.ps1'
    Check ($result.code -ne 0 -and $result.text -notmatch 'SHOOTER_CLIENT_VALID' -and (Snapshot) -ceq $before) ('CheckClient rejects '+$Name+' without writing')
}
function RejectCertificate([string]$Name,[string]$Value) {
    Reset; [IO.File]::WriteAllText((Join-Path $source 'server.crt'),$Value,$utf8)
    $before=Snapshot; $result=Run 'SetServer.ps1' @('-Source',$source)
    Check ($result.code -ne 0 -and (Snapshot) -ceq $before) ('SetServer rejects '+$Name+' without writing')
    [IO.File]::WriteAllText((Join-Path $target 'server.crt'),$Value,$utf8)
    $before=Snapshot; $result=Run 'CheckClient.ps1'
    Check ($result.code -ne 0 -and $result.text -notmatch 'SHOOTER_CLIENT_VALID' -and (Snapshot) -ceq $before) ('CheckClient rejects '+$Name+' without writing')
}
Reset
$result=Run 'SetServer.ps1' @('-Source',$source)
Check ($result.code -eq 0) 'valid public self-signed certificate and config accepted'
$result=Run 'CheckClient.ps1'
Check ($result.code -eq 0 -and $result.text -match 'server_configured=True') 'valid public config checked'
foreach($url in @('wss://localhost:1','wss://127.0.0.1:65535/','wss://my-host.example.invalid:28300')) {
    Reset; $config=Config; $config.url=$url; Save (Join-Path $source 'connection.json') $config
    $result=Run 'SetServer.ps1' @('-Source',$source)
    Check ($result.code -eq 0) ('valid URI '+$url)
}
foreach($url in @('WSS://localhost:28300','WsS://localhost:28300','wss://localhost:0','wss://localhost:65536','wss://localhost:99999','wss://:28300','wss://bad..invalid:28300','wss://-bad.invalid:28300','wss://bad-.invalid:28300','wss://bad_host.invalid:28300','wss://999.1.1.1:28300','wss://localhost:28300/path','wss://user:password@localhost:28300','wss://localhost:28300?secret=value','wss://localhost:28300#fragment','ws://localhost:28300','wss://localhost','wss://localhost:28300\','wss://local%68ost:28300')) {
    $config=Config; $config.url=$url; RejectConfig ('URI '+$url) $config
}
RejectCertificate 'truncated PEM' '-----BEGIN CERTIFICATE-----'
RejectCertificate 'invalid base64' "-----BEGIN CERTIFICATE-----`n!!!!`n-----END CERTIFICATE-----"
RejectCertificate 'non-X509 base64' "-----BEGIN CERTIFICATE-----`nZmFrZQ==`n-----END CERTIFICATE-----"
RejectCertificate 'truncated DER' ($pem -replace 'MIIC0D','AAAAAA')
RejectCertificate 'private key' ($pem+"`n-----BEGIN PRIVATE KEY-----`nZmFrZQ==`n-----END PRIVATE KEY-----")
RejectCertificate 'multiple certificates' ($pem+$pem)
RejectCertificate 'extra PEM text' ($pem+'extra')
# A PKCS12 container mislabeled as CERTIFICATE must be refused before import.
# This fixture exports only the fixed public certificate, with no private key.
$body=($pem -replace '-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s','')
$publicCertificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($body))
try { $container=[Convert]::ToBase64String($publicCertificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12)) }
finally { $publicCertificate.Dispose() }
RejectCertificate 'PKCS12 disguised as certificate' ("-----BEGIN CERTIFICATE-----`n"+$container+"`n-----END CERTIFICATE-----`n")
$config=Config; $config.password='fixture_secret'; RejectConfig 'secret field' $config
$config=Config; $config.unrecognized='fixture'; RejectConfig 'unknown field' $config
$config=Config; $config.managed='true'; RejectConfig 'managed string' $config
$config=Config; $config.secure_enet=$false; RejectConfig 'insecure ENet' $config
$config=Config; $config.ca_certificate='../server.key'; RejectConfig 'certificate path escape' $config
$config=Config; $config.server_hostname='localhost?secret=value'; RejectConfig 'invalid server_hostname' $config
$config=Config; $config.server_hostname=@('localhost'); RejectConfig 'hostname array' $config
$config=Config; $config.Remove('server_hostname'); RejectConfig 'missing required hostname' $config
RejectConfig 'non-object JSON' @('fixture')
RejectConfig 'singleton object array JSON' @([pscustomobject](Config))
RejectConfig 'numeric JSON' 1
RejectConfig 'null JSON' $null
$config=Config; $config.url=@('wss://localhost:28300'); RejectConfig 'URL array' $config
$config=Config; $config.managed=1; RejectConfig 'managed integer' $config
foreach($address in @('x@qq.com?bcc=bad@qq.com',"x@qq.com`r`nBcc:bad@qq.com",'a@qq.com,b@qq.com','mailto:a@qq.com','a@qq.com&body=secret','a@bad..invalid','a@-bad.invalid','',@('a@qq.com'))) {
    $config=Config; $config.report_email=$address; RejectConfig 'malicious report_email' $config
}
Reset; $config=Config; $config.Remove('report_email'); Save (Join-Path $source 'connection.json') $config
$result=Run 'SetServer.ps1' @('-Source',$source,'-ReportEmail','owner@qq.com')
$saved=Get-Content -LiteralPath (Join-Path $target 'connection.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($result.code -eq 0 -and $saved.report_email -ceq 'owner@qq.com') 'explicit public report_email accepted'
Reset; $before=Snapshot; $result=Run 'SetServer.ps1' @('-Source',$source,'-ReportEmail','owner@qq.com?bcc=bad@qq.com')
Check ($result.code -ne 0 -and (Snapshot) -ceq $before) 'invalid report_email override does not write'
foreach($name in @('connection.json','server.crt')) {
    Reset; Remove-Item -LiteralPath (Join-Path $target $name)
    $result=Run 'CheckClient.ps1'
    Check ($result.code -ne 0 -and $result.text -notmatch 'SHOOTER_CLIENT_VALID') ('one missing public file '+$name+' fails')
}
Reset; [IO.File]::WriteAllText((Join-Path $target 'connection.json'),'{bad',$utf8)
$result=Run 'CheckClient.ps1'; Check ($result.code -ne 0 -and $result.text -notmatch 'SHOOTER_CLIENT_VALID') 'malformed JSON fails CheckClient'
Reset; Remove-Item -LiteralPath (Join-Path $target 'connection.json'),(Join-Path $target 'server.crt')
$result=Run 'CheckClient.ps1'; Check ($result.code -eq 0 -and $result.text -match 'server_configured=False') 'both files absent is explicitly unconfigured'
foreach($flag in @('configured','server_configured')) {
    $version=@{build_id='fixture';files=@();generated_files=@()}; $version[$flag]=$true
    Save (Join-Path $target 'client-version.json') $version
    $result=Run 'CheckClient.ps1'; Check ($result.code -ne 0 -and $result.text -notmatch 'SHOOTER_CLIENT_VALID') ($flag+' true cannot hide missing files')
}
$failed=@($script:checks|Where-Object {-not $_.passed}).Count
$report=[ordered]@{powershell=$PowerShell;passed=($script:checks.Count-$failed);failed=$failed;checks=@($script:checks.ToArray());commands=@($script:commands.ToArray());not_run=@('certificate time validation','certificate hostname matching','TLS handshake','Godot or exported client','network or mail delivery')}
Save (Join-Path $work 'result.json') $report
Write-Output ('PUBLIC_CLIENT_CONFIG_RESULT passed='+$report.passed+' failed='+$report.failed)
exit ([int]($failed -ne 0))
