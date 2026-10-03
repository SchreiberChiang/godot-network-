param([string]$Project='', [string]$OutputDirectory='')
$ErrorActionPreference='Stop'
if(-not $Project) { $Project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
if(-not $OutputDirectory) { $OutputDirectory=Join-Path $Project ('data/report-recipient-'+[Guid]::NewGuid().ToString('N')) }
$base=[IO.Path]::GetFullPath((Join-Path $Project 'data')).TrimEnd('\','/')
$work=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(-not $work.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $work)) { throw 'Require a fresh directory beneath project data.' }
for($cursor=$work;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)) { if(Test-Path -LiteralPath $cursor) { if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked test path' } } }
$utf8=New-Object Text.UTF8Encoding($false)
$source=Join-Path $work 'source'; $target=Join-Path $work 'client'
New-Item -ItemType Directory -Path $source,$target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Project 'tools/shooter_client/SetServer.ps1') -Destination $target
# Shared offline validation uses a fixed PUBLIC test certificate; no TLS/game/mail.
Copy-Item -LiteralPath (Join-Path $Project 'tools/shooter_client/public_config.ps1') -Destination $target
Copy-Item -LiteralPath (Join-Path $Project 'tests/support/public-test-certificate.crt') -Destination (Join-Path $source 'server.crt')
$script:passed=0; $script:failed=0
function Check([bool]$Ok,[string]$Name) { if($Ok){$script:passed++}else{$script:failed++}; Write-Output ((@('FAIL','PASS')[[int]$Ok])+' '+$Name) }
function Run([object]$Address,[bool]$WithField=$true,[string]$Override='') {
    $config=[ordered]@{url='wss://example.invalid:28300';ca_certificate='server.crt';server_hostname='localhost';managed=$true;secure_enet=$true}
    if($WithField){$config.report_email=$Address}
    [IO.File]::WriteAllText((Join-Path $source 'connection.json'),($config|ConvertTo-Json -Depth 4),$utf8)
    $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $target 'SetServer.ps1'),'-Source',$source)
    if($Override){$args+=@('-ReportEmail',$Override)}
    $oldPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try {$output=@(& powershell.exe @args 2>&1); $code=$LASTEXITCODE} finally {$ErrorActionPreference=$oldPreference}
    $output | Out-File -FilePath (Join-Path $work ('run-'+[Guid]::NewGuid().ToString('N').Substring(0,6)+'.txt')) -Encoding utf8
    return $code
}
Check ((Run 'contact@example.invalid') -eq 0) 'public recipient accepted'
$path=Join-Path $target 'connection.json'
$before=(Get-FileHash -LiteralPath $path).Hash
$rejected=@("x@qq.com?bcc=bad@qq.com","x@qq.com`r`nBcc:bad@qq.com",'a@qq.com,b@qq.com','mailto:a@qq.com','a@qq.com&body=secret',@('a@qq.com'),'','a@bad..invalid','a@-bad.invalid')
foreach($value in $rejected) {
    Check ((Run $value) -ne 0 -and (Get-FileHash -LiteralPath $path).Hash -eq $before) 'bad recipient refused without rewriting player config'
}
Check ((Run $null $false) -eq 0) 'legacy config without report address still accepted'
Check ((Run $null $false 'owner@qq.com') -eq 0) 'host can set an explicit public recipient'
$last=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($last.report_email -ceq 'owner@qq.com' -and $last.url -ceq 'wss://example.invalid:28300' -and $last.secure_enet -eq $true) 'connection transport remains unchanged'
Write-Output ('REPORT_RECIPIENT_RESULT passed='+$script:passed+' failed='+$script:failed)
exit ([int]($script:failed -ne 0))
