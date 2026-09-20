param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $root 'project.godot'))) { throw 'Not a RoomKit project root' }
$path = Join-Path $root 'run'
if (Test-Path -LiteralPath $path) {
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime reparse point refused' }
} else { New-Item -ItemType Directory -Path $path | Out-Null }
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$sections = [System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner
$acl = [IO.Directory]::GetAccessControl($path, $sections)
if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]) -ne $sid) { throw 'Runtime directory owner mismatch' }
# Change only the DACL. Set-Acl on a fresh descriptor may request SACL privileges.
$acl.SetAccessRuleProtection($true, $false)
foreach ($existing in $acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])) { $acl.RemoveAccessRuleSpecific($existing) }
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
[IO.Directory]::SetAccessControl($path, $acl)
[IO.File]::WriteAllText((Join-Path $path '.gdignore'), '')
Write-Output 'PRIVATE_RUNTIME_READY'
