param()
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot=Join-Path $project ('data\test-asset-audit-'+[Guid]::NewGuid().ToString('N'))
$database=Join-Path $testRoot 'assets.sqlite'
$utf8=New-Object Text.UTF8Encoding($false)
$passed=0
$failed=0
function Check([bool]$Value,[string]$Label) {
    if ($Value) { $script:passed++; Write-Output ('PASS asset audit: '+$Label) }
    else { $script:failed++; Write-Output ('FAIL asset audit: '+$Label) }
}
function Store($Object) {
    $requestPath=Join-Path $testRoot ('request-'+[Guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText($requestPath,($Object | ConvertTo-Json -Compress -Depth 12),$utf8)
    try { return ((& (Join-Path $project 'tools/sqlite_store.ps1') -Database $database -Request $requestPath) | ConvertFrom-Json) }
    finally { [IO.File]::Delete($requestPath) }
}
try {
    $ready=& (Join-Path $project 'tools/protect_data.ps1') -ProjectRoot $project -DataRoot $testRoot
    if ($ready -notcontains 'PRIVATE_DATA_READY') { throw 'Private fixture failed' }
    Write-Output ('ASSET_AUDIT_EVIDENCE_DIR='+$testRoot)
    Check (Store @{op='init'}).ok 'real SQLite initializes'
    $empty=Store @{op='asset.audit_all'}
    Check ($empty.ok -and $empty.rows -is [Array] -and $empty.rows.Count -eq 0) 'empty global audit is an array'
    $first='{"revision":1,"credits":100,"experience":0,"owned":[],"profiles":{}}'
    $second='{"revision":2,"credits":200,"experience":0,"owned":[],"profiles":{}}'
    $auditReason=-join [char[]]@(0x5BA1,0x8BA1,0x6D4B,0x8BD5)
    $command=@{kind='adjust';credits=100;experience=0;reason=$auditReason;request_id='first'} | ConvertTo-Json -Compress
    Check (Store @{op='asset.commit';user_id='first_user';space_id='shooter';request_id='first';fingerprint='private-fingerprint';actor_id='admin_fixture';command=$command;expected_revision=0;body=$first}).ok 'actual first transition commits'
    Check (Store @{op='asset.commit';user_id='first_user';space_id='shooter';request_id='second';fingerprint='private-fingerprint';actor_id='admin_fixture';command=$command;expected_revision=1;body=$second}).ok 'actual second transition commits'
    $before=Store @{op='asset.audit_all'}
    Check ($before.ok -and $before.rows.Count -eq 2 -and $before.rows[0].request_id -eq 'second') 'newest row returned first'
    Check ($before.rows[0].previous_body -eq $first -and $before.rows[0].body -eq $second) 'before and after state preserved exactly'
    Check (($before.rows[0].command | ConvertFrom-Json).reason -eq $auditReason) 'bound Unicode reason is intact'
    $required=@('user_id','request_id','space_id','actor_id','command','previous_body','body','created_at') | Sort-Object
    Check ((@($before.rows[0].PSObject.Properties.Name | Sort-Object) -join ',') -eq ($required -join ',')) 'only eight documented audit fields returned'
    Check (($before | ConvertTo-Json -Depth 10) -notmatch 'private-fingerprint|password|token_hash') 'response omits receipt fingerprint and account secret fields'
    $db=New-Object RoomKitSqlite($database)
    try {
        [void]$db.Query('WITH RECURSIVE fill(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM fill WHERE n<103) INSERT INTO asset_receipts(user_id,request_id,fingerprint,space_id,actor_id,command,previous_body,body) SELECT ''user_''||(n%2),''fill_''||n,''private-fixture-fingerprint'',''turns'',''test'',''{}'','''',''{}'' FROM fill',@())
    } finally { $db.Dispose() }
    $limited=Store @{op='asset.audit_all'}
    Check ($limited.ok -and $limited.rows.Count -eq 100 -and $limited.rows[0].request_id -eq 'fill_103' -and $limited.rows[99].request_id -eq 'fill_4') '105 persisted rows yield exactly newest 100'
    Check ((@($limited.rows.user_id | Sort-Object -Unique)).Count -eq 2) 'fixed global query includes different users'
    $injected=Store @{op='asset.audit_all';sql='DELETE FROM asset_states';limit=999999;user_id='first_user'}
    Check (-not $injected.ok -and $injected.code -eq 'INVALID_ASSET_COMMAND') 'SQL limit and filter inputs are refused'
    $state=Store @{op='asset.read';user_id='first_user';space_id='shooter'}
    Check ($state.ok -and $state.body -eq $second) 'audit and refused payload preserve live state'
    $db=New-Object RoomKitSqlite($database)
    try { Check ($db.Query('SELECT count(*) AS total FROM asset_receipts',@())[0]['total'] -eq '105') 'audit queries do not mutate receipt count' }
    finally { $db.Dispose() }
} catch {
    $failed++
    Write-Output ('FAIL asset audit: '+$_.Exception.Message)
}
Write-Output ('ASSET_AUDIT_RESULT passed='+$passed+' failed='+$failed)
if ($failed -gt 0) { exit 1 }
exit 0
