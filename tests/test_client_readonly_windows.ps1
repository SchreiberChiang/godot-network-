param([string]$Godot='D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
# Only a fresh, owned fixture is ACL-restricted. Restore its exact ACL in finally.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$isolation=Join-Path $project ('data/test-client-readonly-'+[Guid]::NewGuid().ToString('N'))
$readonly=Join-Path $isolation 'readonly'
$cursor=$isolation
while($cursor){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked fixture ancestor.'}
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
if(Test-Path -LiteralPath $isolation){throw 'Fixture already exists.'}
[void][IO.Directory]::CreateDirectory($readonly)
$original=Get-Acl -LiteralPath $readonly
$restricted=Get-Acl -LiteralPath $readonly
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
$rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,[Security.AccessControl.FileSystemRights]::Write,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Deny)
$restricted.AddAccessRule($rule)
$process=$null;$code=1
try {
    Set-Acl -LiteralPath $readonly -AclObject $restricted
    $argsList=@('--headless','--path',('"'+$project+'"'),'--log-file',('"'+(Join-Path $isolation 'engine.log')+'"'),'--script','res://tests/run_client_journal_readonly.gd','--',('"--data-root='+$readonly.Replace('\','/')+'"'))
    $process=Start-Process -FilePath $Godot -ArgumentList $argsList -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $isolation 'readonly.stdout') -RedirectStandardError (Join-Path $isolation 'readonly.stderr')
    $null=$process.Handle
    if(-not $process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();$code=124}else{$code=$process.ExitCode}
} finally {
    if($process -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
    Set-Acl -LiteralPath $readonly -AclObject $original
}
# Confirm cleanup did not leave even this test folder unwritable.
[IO.File]::WriteAllText((Join-Path $readonly 'acl-restored.txt'),'test-only')
Get-Content -LiteralPath (Join-Path $isolation 'readonly.stdout') -Encoding UTF8
[IO.File]::WriteAllText((Join-Path $isolation 'result.json'),('{"exit_code":'+$code+',"acl_restored":true}'))
Write-Output ('CLIENT_READONLY_WINDOWS evidence='+$isolation+' exit='+$code)
exit $code
