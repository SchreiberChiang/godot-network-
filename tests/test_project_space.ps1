# Boundary checks for the read-only inventory. Tiny fixtures only; no engine/services.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/project_space.ps1')
$testRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('logs/space-check-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$passed = 0; $failed = 0
function Check([string]$Name,[bool]$Pass) {
    if ($Pass) { $script:passed++; Write-Output "PASS $Name" }
    else { $script:failed++; Write-Output "FAIL $Name" }
}
function Rejects([scriptblock]$Action,[string]$Expected) {
    try { & $Action | Out-Null; return $false }
    catch { return $_.Exception.Message.StartsWith($Expected) }
}
try {
    # No Chinese literal: this driver runs in Windows PowerShell 5.1 as well as pwsh.
    $unicodeName = ([string][char]0x6d4b) + ([string][char]0x8bd5) + ' space'
    $repo = Join-Path $testRoot $unicodeName
    $nested = Join-Path $repo 'nested'
    [void][IO.Directory]::CreateDirectory($nested)
    $first = Join-Path $repo 'small.dat'; $second = Join-Path $nested 'large.dat'
    [IO.File]::WriteAllBytes($first, (New-Object byte[] 11))
    [IO.File]::WriteAllBytes($second, (New-Object byte[] 43))
    $before = (Get-FileHash -LiteralPath $second).Hash
    $stamp = (Get-Item -LiteralPath $second).LastWriteTimeUtc
    $report = Get-RoomKitSpaceReport $repo
    Check 'exact bytes, files and Unicode path' ($report.project.logical_bytes -eq 54 -and $report.project.files -eq 2 -and $report.project.path -ceq $repo)
    Check 'largest file and nested totals' ($report.project.areas[0].largest_files[0].path -ceq $second -and $report.project.areas[0].logical_bytes -eq 43)
    Check 'read-only hash and modification time' ((Get-FileHash -LiteralPath $second).Hash -eq $before -and (Get-Item -LiteralPath $second).LastWriteTimeUtc -eq $stamp)
    Check 'JSON round trip and explicit units' (($report | ConvertTo-Json -Depth 12 | ConvertFrom-Json).size_kind -eq 'logical_file_lengths_not_allocated_disk_blocks')
    Check 'missing root rejected' (Rejects { Get-RoomKitSpaceReport (Join-Path $testRoot 'absent') } 'SPACE_ROOT_MISSING')

    $metadata = Join-Path $repo '.git/worktrees/candidate'
    $tree = Join-Path $testRoot 'candidate'
    [void][IO.Directory]::CreateDirectory($metadata)
    [void][IO.Directory]::CreateDirectory($tree)
    [IO.File]::WriteAllText((Join-Path $metadata 'gitdir'), (Join-Path $tree '.git'))
    [IO.File]::WriteAllText((Join-Path $tree '.git'), ('gitdir: '+$metadata))
    [IO.File]::WriteAllText((Join-Path $metadata 'commondir'), '../..')
    [IO.File]::WriteAllBytes((Join-Path $tree 'copy.dat'), (New-Object byte[] 31))
    $report = Get-RoomKitSpaceReport $repo
    Check 'registered external tree found by matching backlinks' ($report.complete -and $report.related_roots.Count -eq 1 -and $report.related_roots[0].measurement.path -ceq $tree)
    $fromTree = Get-RoomKitSpaceReport $tree
    Check 'linked checkout includes main tree without counting itself' ($fromTree.related_roots.Count -eq 1 -and $fromTree.related_roots[0].measurement.path -ceq $repo)
    if ($env:OS -eq 'Windows_NT') {
        [IO.File]::WriteAllText((Join-Path $tree '.git'), ('gitdir: '+$metadata.ToLowerInvariant()))
        Check 'Windows backlink casing accepted' ((Get-RoomKitSpaceReport $repo).complete)
        [IO.File]::WriteAllText((Join-Path $tree '.git'), ('gitdir: '+$metadata))
        $savedTemp = $env:TEMP
        try {
            $env:TEMP = $nested
            [void][IO.Directory]::CreateDirectory((Join-Path $nested 'roomkit-copy'))
            $withUserData = Get-RoomKitSpaceReport $repo -UserData
            Check 'TEMP inside project is not counted again' (@($withUserData.related_roots | Where-Object {$_.measurement.path -like ($nested+'*')}).Count -eq 0)
        } finally { $env:TEMP = $savedTemp }
    }
    [IO.File]::WriteAllText((Join-Path $tree '.git'), ('gitdir: '+(Join-Path $repo 'not-our-registry')))
    $report = Get-RoomKitSpaceReport $repo
    Check 'mismatched tree is reported incomplete without scanning target' (-not $report.complete -and $report.related_roots.Count -eq 0 -and $report.errors[0] -eq 'SPACE_WORKTREE_BACKLINK_MISMATCH')
    [IO.File]::WriteAllText((Join-Path $tree '.git'), ('gitdir: '+$metadata))

    $outside = Join-Path $testRoot 'outside'
    [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllBytes((Join-Path $outside 'canary.dat'), (New-Object byte[] 9001))
    $link = Join-Path $nested 'linked'
    if ($env:OS -eq 'Windows_NT') { [void](New-Item -ItemType Junction -Path $link -Target $outside) }
    else { [void](New-Item -ItemType SymbolicLink -Path $link -Target $outside) }
    $measurement = Measure-RoomKitSpacePath $nested
    Check 'nested link is skipped and outside bytes excluded' ($measurement.logical_bytes -eq 43 -and $measurement.skipped_links -eq 1)
    Check 'root via linked ancestor rejected' (Rejects { Measure-RoomKitSpacePath (Join-Path $link 'canary.dat') } 'SPACE_LINKED_ROOT')
    Check 'linked root rejected' (Rejects { Get-RoomKitSpaceReport $link } 'SPACE_LINKED_ROOT')
    [IO.Directory]::Delete($link) # Delete this junction itself, never traverse its target.
    Check 'outside canary survives unlink' ((Get-Item -LiteralPath (Join-Path $outside 'canary.dat')).Length -eq 9001)
} catch {
    $failed++
    Write-Output ('FAIL driver: ' + $_.Exception.Message)
} finally {
    # Keep the tiny fixture and output location as evidence; never recursively delete it.
    Write-Output ('Fixture: '+$testRoot)
}
Write-Output ("RESULT {0}/{1}" -f $passed,$failed)
if ($failed) { exit 1 }
