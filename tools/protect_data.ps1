param([Parameter(Mandatory=$true)][string]$ProjectRoot,[Parameter(Mandatory=$true)][string]$DataRoot)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
$data=[IO.Path]::GetFullPath((Join-Path $project 'data'))
$target=[IO.Path]::GetFullPath($DataRoot).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath (Join-Path $project 'project.godot'))) { throw 'Invalid project root' }
if ($target -ne $data -and -not $target.StartsWith($data+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Data path outside project data directory' }
$cursor=$target
while ($cursor.Length -ge $data.Length) {
    if (Test-Path -LiteralPath $cursor) {
        if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point refused' }
    }
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
New-Item -ItemType Directory -Force -Path $data | Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$sections=[Security.AccessControl.AccessControlSections]::Access -bor [Security.AccessControl.AccessControlSections]::Owner
$acl=[IO.Directory]::GetAccessControl($data,$sections)
if ($acl.GetOwner([Security.Principal.SecurityIdentifier]) -ne $sid) { throw 'Data owner mismatch' }
$acl.SetAccessRuleProtection($true,$false)
foreach ($rule in $acl.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])) { $acl.RemoveAccessRuleSpecific($rule) }
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
[IO.Directory]::SetAccessControl($data,$acl)
New-Item -ItemType Directory -Force -Path $target | Out-Null
[IO.File]::WriteAllText((Join-Path $data '.gdignore'),'')
Write-Output 'PRIVATE_DATA_READY'
