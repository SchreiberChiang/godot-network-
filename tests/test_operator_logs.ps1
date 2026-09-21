param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$id=[Guid]::NewGuid().ToString('N')
$private=Join-Path $project ('data/test-operator-logs-'+$id)
$evidence=Join-Path $project ('logs/operator-logs-'+$id)
& (Join-Path $project 'tools/protect_data.ps1') -ProjectRoot $project -DataRoot $private|Out-Null
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
$locked=Join-Path $private 'locked.log'
[IO.File]::WriteAllText($locked,'real lock fixture')
$lock=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$actualLog=Join-Path $evidence 'actual-engine.log'
$stdout=Join-Path $evidence 'console.log'
$stderr=Join-Path $evidence 'stderr.log'
$arguments=@('--headless','--path',$project,'--log-file',$actualLog,'--script','res://tests/run_operator_logs.gd','--',('--test-root='+$private),('--expected-log='+$actualLog),('--operator-log-path='+$actualLog))
$quoted=foreach($argument in $arguments){'"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
$process=$null
try{
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $heldHandle=$process.Handle
    if(-not $process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();throw 'Operator log test timed out.'}
    Get-Content -LiteralPath $stdout -Encoding UTF8
    Get-Content -LiteralPath $stderr -Encoding UTF8
    if($process.ExitCode -ne 0 -or -not (Select-String -LiteralPath $stdout -Pattern 'OPERATOR_LOG_RESULT passed=14 failed=0' -Quiet) -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|FAIL|ERROR:' -Quiet)){throw ('Operator log test failed; evidence='+$evidence)}
    Write-Output ('OPERATOR_LOG_TEST_PASS evidence='+$evidence)
}finally{$lock.Dispose();if($null -ne $process){$process.Dispose()}}
