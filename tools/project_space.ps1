# Read-only metadata inventory. Never opens databases, removes files, or starts services.
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$IncludeUserData,
    [switch]$Json
)

# Resolve after parameter binding: Windows PowerShell -File may not yet expose
# PSScriptRoot while evaluating a default parameter expression.
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }

function Assert-RoomKitSpacePath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "SPACE_LINKED_ROOT: $Path"
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}

function Measure-RoomKitSpacePath {
    param([string]$Path)
    $full = Assert-RoomKitSpacePath $Path
    $result = [ordered]@{ path=$full; logical_bytes=[long]0; files=0; directories=0; skipped_links=0; complete=$true; errors=@(); largest_files=@() }
    $stack = New-Object 'Collections.Generic.Stack[System.IO.FileSystemInfo]'
    $largest = New-Object Collections.ArrayList
    $errors = New-Object Collections.ArrayList
    $stack.Push((Get-Item -LiteralPath $full -Force -ErrorAction Stop))
    while ($stack.Count) {
        $item = $stack.Pop()
        $next = $item.FullName
        try {
            $item.Refresh()
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $result.skipped_links++
                continue
            }
            if (-not $item.Exists) { throw 'SPACE_ITEM_DISAPPEARED' }
            if ($item -is [IO.DirectoryInfo]) {
                $result.directories++
                foreach ($child in $item.GetFileSystemInfos()) { $stack.Push($child) }
            } else {
                $result.logical_bytes += $item.Length
                $result.files++
                [void]$largest.Add([pscustomobject]@{path=$item.FullName; bytes=$item.Length})
                if ($largest.Count -gt 32) {
                    $keep = @($largest | Sort-Object bytes -Descending | Select-Object -First 10)
                    $largest.Clear()
                    foreach ($entry in $keep) { [void]$largest.Add($entry) }
                }
            }
        } catch {
            $result.complete = $false
            if ($errors.Count -lt 20) { [void]$errors.Add([pscustomobject]@{path=$next; reason=$_.Exception.GetType().Name}) }
        }
    }
    $result.errors = @($errors)
    $result.largest_files = @($largest | Sort-Object bytes -Descending | Select-Object -First 10)
    return [pscustomobject]$result
}

function Resolve-RoomKitSpacePointer {
    param([string]$Base, [string]$Pointer)
    if ([IO.Path]::IsPathRooted($Pointer)) { return Assert-RoomKitSpacePath $Pointer }
    return Assert-RoomKitSpacePath (Join-Path $Base $Pointer)
}

function Get-RoomKitSpaceWorktrees {
    # Read this repository's Git pointers, not the user's entire .codex directory.
    param([string]$Root)
    $git = Assert-RoomKitSpacePath (Join-Path $Root '.git')
    if (-not (Test-Path -LiteralPath $git)) { return }
    if (Test-Path -LiteralPath $git -PathType Leaf) {
        $pointer = [IO.File]::ReadAllText($git).Trim()
        if ($pointer -notmatch '^gitdir: (.+)$') { throw 'SPACE_INVALID_GIT_POINTER' }
        $git = Resolve-RoomKitSpacePointer $Root $Matches[1]
        $common = Assert-RoomKitSpacePath (Join-Path $git 'commondir')
        if (Test-Path -LiteralPath $common -PathType Leaf) {
            $git = Resolve-RoomKitSpacePointer $git ([IO.File]::ReadAllText($common).Trim())
        }
    }
    # In an ordinary checkout, the common .git directory identifies the main tree.
    # A linked checkout must include it too; separate/bare Git directories do not.
    if ([IO.Path]::GetFileName($git) -eq '.git' -and (Test-Path -LiteralPath $git -PathType Container)) {
        [IO.Path]::GetDirectoryName($git)
    }
    $registry = Assert-RoomKitSpacePath (Join-Path $git 'worktrees')
    if (-not (Test-Path -LiteralPath $registry -PathType Container)) { return }
    foreach ($entry in Get-ChildItem -LiteralPath $registry -Directory -Force) {
        $pointer = Assert-RoomKitSpacePath (Join-Path $entry.FullName 'gitdir')
        if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) { throw 'SPACE_MISSING_WORKTREE_POINTER' }
        $target = [IO.File]::ReadAllText($pointer).Trim()
        if (-not [IO.Path]::IsPathRooted($target)) { throw 'SPACE_INVALID_WORKTREE_POINTER' }
        $target = Assert-RoomKitSpacePath $target
        if ([IO.Path]::GetFileName($target) -ne '.git') { throw 'SPACE_INVALID_WORKTREE_POINTER' }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'SPACE_STALE_WORKTREE_POINTER' }
        $back = [IO.File]::ReadAllText($target).Trim()
        if ($back -notmatch '^gitdir: (.+)$') { throw 'SPACE_INVALID_WORKTREE_BACKLINK' }
        $backPath = Resolve-RoomKitSpacePointer ([IO.Path]::GetDirectoryName($target)) $Matches[1]
        $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if (-not $backPath.Equals($entry.FullName,$comparison)) { throw 'SPACE_WORKTREE_BACKLINK_MISMATCH' }
        [IO.Path]::GetDirectoryName($target)
    }
}

function Get-RoomKitSpaceReport {
    param([string]$Root, [switch]$UserData)
    $rootPath = Assert-RoomKitSpacePath $Root
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw 'SPACE_ROOT_MISSING' }
    $areas = New-Object Collections.ArrayList
    $roots = New-Object Collections.ArrayList
    $errors = New-Object Collections.ArrayList
    [long]$bytes = 0; $files = 0; $links = 0; $complete = $true
    foreach ($entry in Get-ChildItem -LiteralPath $rootPath -Force -ErrorAction Stop) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { $links++; continue }
        $measurement = Measure-RoomKitSpacePath $entry.FullName
        $bytes += $measurement.logical_bytes; $files += $measurement.files; $links += $measurement.skipped_links
        if (-not $measurement.complete) { $complete = $false }
        [void]$areas.Add($measurement)
    }
    try {
        foreach ($tree in @(Get-RoomKitSpaceWorktrees $rootPath | Select-Object -Unique)) {
            # Trees inside the root have already been counted; never add them twice.
            $separator = [IO.Path]::DirectorySeparatorChar
            $compare = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            if ($tree.Equals($rootPath,$compare) -or $tree.StartsWith($rootPath.TrimEnd($separator)+$separator,$compare)) { continue }
            $measurement = Measure-RoomKitSpacePath $tree
            [void]$roots.Add([pscustomobject]@{kind='registered_worktree'; measurement=$measurement})
            if (-not $measurement.complete) { $complete = $false }
        }
    } catch { $complete = $false; [void]$errors.Add($_.Exception.Message) }
    if ($UserData -and $env:OS -eq 'Windows_NT') {
        $userPaths = New-Object Collections.ArrayList
        if ($env:APPDATA) { [void]$userPaths.Add((Join-Path $env:APPDATA 'Godot/app_userdata/RoomKit Game')) }
        if ($env:TEMP -and (Test-Path -LiteralPath $env:TEMP -PathType Container)) {
            try {
                $tempPath = Assert-RoomKitSpacePath $env:TEMP
                foreach ($entry in Get-ChildItem -LiteralPath $tempPath -Force -ErrorAction Stop) {
                    if ($entry.Name -like 'roomkit-*') { [void]$userPaths.Add($entry.FullName) }
                }
            } catch { $complete = $false; [void]$errors.Add($_.Exception.Message) }
        }
        foreach ($userPath in @($userPaths | Select-Object -Unique)) {
            if (-not (Test-Path -LiteralPath $userPath)) { continue }
            try {
                $userPath = Assert-RoomKitSpacePath $userPath
                $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                $covered = $false
                foreach ($countedRoot in (@($rootPath) + @($roots | ForEach-Object {$_.measurement.path}))) {
                    if ($userPath.Equals($countedRoot,$comparison) -or $userPath.StartsWith($countedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,$comparison)) { $covered = $true; break }
                }
                if ($covered) { continue }
                $measurement = Measure-RoomKitSpacePath $userPath
                [void]$roots.Add([pscustomobject]@{kind='roomkit_named_user_data'; measurement=$measurement})
                if (-not $measurement.complete) { $complete = $false }
            } catch { $complete = $false; [void]$errors.Add($_.Exception.Message) }
        }
    }
    $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
        [pscustomobject]@{name=$_.Name; free_bytes=$_.AvailableFreeSpace; total_bytes=$_.TotalSize}
    })
    return [pscustomobject][ordered]@{
        format=1; measured_at=[DateTimeOffset]::Now.ToString('o'); complete=$complete
        size_kind='logical_file_lengths_not_allocated_disk_blocks'; read_only=$true
        project=[pscustomobject]@{path=$rootPath; logical_bytes=$bytes; files=$files; skipped_links=$links; areas=@($areas | Sort-Object logical_bytes -Descending)}
        related_roots=@($roots); errors=@($errors); drives=$drives
        note='Live metadata snapshot; links excluded. Sizes do not imply permission to delete. Shared Codex data is not counted as RoomKit.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $report = Get-RoomKitSpaceReport -Root $ProjectRoot -UserData:$IncludeUserData
        if ($Json) { $report | ConvertTo-Json -Depth 12 }
        else {
            Write-Output 'RoomKit space check (READ ONLY, logical GiB; links excluded)'
            Write-Output ('Project: {0:N2} GiB / {1} files' -f ($report.project.logical_bytes/1GB),$report.project.files)
            $report.project.areas | Select-Object @{n='GiB';e={[Math]::Round($_.logical_bytes/1GB,3)}},files,path | Format-Table -AutoSize
            Write-Output 'Registered worktrees / opted-in RoomKit-named user data:'
            $report.related_roots | Select-Object kind,@{n='GiB';e={[Math]::Round($_.measurement.logical_bytes/1GB,3)}},@{n='path';e={$_.measurement.path}} | Format-Table -AutoSize
            Write-Output 'Largest project files:'
            $report.project.areas.largest_files | Sort-Object bytes -Descending | Select-Object -First 10 @{n='MiB';e={[Math]::Round($_.bytes/1MB,1)}},path | Format-Table -AutoSize
            $report.drives | Select-Object name,@{n='free_GiB';e={[Math]::Round($_.free_bytes/1GB,2)}} | Format-Table -AutoSize
            Write-Output $report.note
            if (-not $report.complete) { Write-Output 'INCOMPLETE: unreadable, missing, or invalid metadata. Use -Json for details.' }
        }
        if (-not $report.complete) { exit 2 }
        exit 0
    } catch { Write-Error $_; exit 2 }
}
