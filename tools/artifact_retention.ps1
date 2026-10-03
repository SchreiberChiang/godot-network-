# Dot-source from generators. PowerShell 5.1/7, no services or external runtime.
# Only registered immutable output snapshots are eligible. Old unregistered
# directories are deliberately not adopted. Full results/hashes survive pruning.
function Get-RoomKitRetentionPath {
    param([string]$ProjectRoot,[string]$Path,[switch]$Ledger)
    $root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $comparison=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,$comparison)){throw 'RETENTION_OUTSIDE_PROJECT'}
    $relative=$full.Substring($root.Length+1).Replace('\','/')
    if($relative -match '(^|/)(\.git|worktrees)(/|$)' -or $relative -match '^(PlayerClient|clients|host|sdk|tests|tools)(/|$)'){throw 'RETENTION_PROTECTED_PATH'}
    if($Ledger){if($relative -notmatch '^artifacts/retention-ledger(/|$)'){throw 'RETENTION_INVALID_LEDGER'}}
    elseif($relative -notmatch '^(artifacts|logs)/[^/]+(/|$)' -and $relative -notmatch '^data/(test-|isolated-|acceptance-|retention-test-)[^/]+(/|$)'){throw 'RETENTION_UNMANAGED_ROOT'}
    if(-not $Ledger -and $relative -match '^artifacts/retention-ledger(/|$)'){throw 'RETENTION_PROTECTED_LEDGER'}
    $cursor=$full
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'RETENTION_LINKED_PATH'}
        $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
    }
    return $full
}

function Get-RoomKitArtifactSnapshot {
    param([string]$ProjectRoot,[string[]]$Paths)
    $entries=New-Object Collections.ArrayList
    foreach($path in $Paths){
        $full=Get-RoomKitRetentionPath $ProjectRoot $path
        $root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
        $relative=$full.Substring($root.Length+1).Replace('\','/')
        if($relative -match '^data/'){
            $testRoot=Join-Path $root ($relative.Split('/')[0]+'/'+$relative.Split('/')[1])
            $marker=Join-Path $testRoot '.roomkit-test-owner.json'
            Get-RoomKitRetentionPath $root $marker|Out-Null
            if(-not(Test-Path -LiteralPath $marker -PathType Leaf)){throw 'RETENTION_UNPROVEN_TEST_ROOT'}
            $owner=Get-Content -LiteralPath $marker -Encoding UTF8 -Raw|ConvertFrom-Json
            if($owner.format -ne 1 -or $owner.purpose -ne 'generated-test' -or $owner.id -notmatch '^[a-f0-9]{32}$'){throw 'RETENTION_INVALID_TEST_OWNER'}
            $proof=Join-Path $root ('artifacts/retention-ledger/test-owners/'+$owner.id+'.json')
            Get-RoomKitRetentionPath $root $proof -Ledger|Out-Null
            if(-not(Test-Path -LiteralPath $proof -PathType Leaf) -or (Get-FileHash -LiteralPath $marker).Hash -ne (Get-FileHash -LiteralPath $proof).Hash){throw 'RETENTION_UNPROVEN_TEST_ROOT'}
            if([string]$owner.directory -cne $testRoot){throw 'RETENTION_TEST_OWNER_MISMATCH'}
        }
        if(-not(Test-Path -LiteralPath $full)){throw 'RETENTION_OUTPUT_MISSING'}
        $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($full)
        while($pending.Count){
            $name=$pending.Pop();$item=Get-Item -LiteralPath $name -Force -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RETENTION_LINKED_CONTENT'}
            $relative=$item.FullName.Substring([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/').Length+1).Replace('\','/')
            if($relative -match '(^|/)\.git(/|$)'){throw 'RETENTION_EMBEDDED_REPOSITORY'}
            # Runtime player state is never an immutable generated artifact, even
            # if an old ledger mistakenly recorded its exact current bytes.
            if($relative -match '(^|/)client-data(/|$)' -or $relative -match '(^|/)data/(client-operations|client-local)(/|$)'){throw 'RETENTION_CLIENT_RUNTIME_DATA'}
            if($item.PSIsContainer){
                [void]$entries.Add([ordered]@{path=$relative;kind='directory';size=0;sha256=''})
                foreach($child in Get-ChildItem -LiteralPath $name -Force -ErrorAction Stop){$pending.Push($child.FullName)}
            }else{
                [void]$entries.Add([ordered]@{path=$relative;kind='file';size=$item.Length;sha256=(Get-FileHash -LiteralPath $name -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()})
            }
        }
    }
    return @($entries|Sort-Object @{Expression={$_.path}})
}

function New-RoomKitArtifactTestRoot {
    # Establish ownership BEFORE any generated test data is written. Existing
    # data is never adopted by inventing a marker afterwards.
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,[Parameter(Mandatory=$true)][string]$Path)
    $full=Get-RoomKitRetentionPath $ProjectRoot $Path
    $root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    if($full.Substring($root.Length+1).Replace('\','/') -notmatch '^data/(test-|isolated-|acceptance-|retention-test-)[^/]+$'){throw 'RETENTION_INVALID_TEST_ROOT'}
    if(Test-Path -LiteralPath $full){throw 'RETENTION_EXISTING_TEST_ROOT'}
    $lock=Open-RoomKitRetentionLock $ProjectRoot
    try{
        if(Test-Path -LiteralPath $full){throw 'RETENTION_EXISTING_TEST_ROOT'}
        [void][IO.Directory]::CreateDirectory($full)
        $id=[Guid]::NewGuid().ToString('N')
        $owner=[ordered]@{format=1;purpose='generated-test';id=$id;directory=$full}
        $proofDirectory=Get-RoomKitRetentionPath $root (Join-Path $root 'artifacts/retention-ledger/test-owners') -Ledger
        [void][IO.Directory]::CreateDirectory($proofDirectory)
        Write-RoomKitRetentionJson (Join-Path $full '.roomkit-test-owner.json') $owner
        Write-RoomKitRetentionJson (Join-Path $proofDirectory ($id+'.json')) $owner
        return $full
    }finally{$lock.Dispose()}
}

function Write-RoomKitRetentionJson {
    param([string]$Path,$Value)
    $tmp=$Path+'.tmp'
    foreach($candidate in @($Path,$tmp)){
        $item=Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'RETENTION_LINKED_LEDGER'}
    }
    [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Open-RoomKitRetentionLock {
    param([string]$ProjectRoot)
    $ledger=Get-RoomKitRetentionPath $ProjectRoot (Join-Path $ProjectRoot 'artifacts/retention-ledger') -Ledger
    [void][IO.Directory]::CreateDirectory($ledger)
    $lock=Get-RoomKitRetentionPath $ProjectRoot (Join-Path $ledger 'ledger.lock') -Ledger
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        try{return [IO.File]::Open($lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch{if($timer.ElapsedMilliseconds -ge 5000){throw 'RETENTION_LEDGER_BUSY'};Start-Sleep -Milliseconds 50}
    }
}

function Register-RoomKitArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,
          [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9.-]{0,63}$')][string]$Category,
          [Parameter(Mandatory=$true)][string[]]$Paths,
          [ValidateSet('success','failure')][string]$Outcome='success',
          [hashtable]$Summary=@{},[string[]]$References=@())
    if(-not $Paths.Count){throw 'RETENTION_NO_PATHS'}
    $lock=Open-RoomKitRetentionLock $ProjectRoot
    try{
        $fullPaths=@($Paths|ForEach-Object {Get-RoomKitRetentionPath $ProjectRoot $_}|Sort-Object -Unique)
        for($i=0;$i -lt $fullPaths.Count;$i++){
            for($j=0;$j -lt $fullPaths.Count;$j++){
                if($i -ne $j -and $fullPaths[$j].StartsWith($fullPaths[$i]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RETENTION_OVERLAPPING_PATHS'}
            }
        }
        # A tracked path is source, even if it happens to reside under artifacts.
        foreach($full in $fullPaths){
            if(Test-RoomKitRetentionTrackedPath $ProjectRoot $full){throw 'RETENTION_TRACKED_SOURCE'}
        }
        $snapshot=@(Get-RoomKitArtifactSnapshot $ProjectRoot $fullPaths)
        $id=[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfffffff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
        $record=[ordered]@{format=1;id=$id;category=$Category;created_utc=[DateTime]::UtcNow.ToString('o');outcome=$Outcome;summary=$Summary;paths=$fullPaths;references=$References;snapshot=$snapshot;state='retained';pruned_utc='';last_skip=''}
        $recordPath=Join-Path $ProjectRoot ('artifacts/retention-ledger/'+$id+'.json')
        Write-RoomKitRetentionJson $recordPath $record
        return $id
    }finally{$lock.Dispose()}
}

function Test-RoomKitRetentionTrackedPath {
    param([string]$ProjectRoot,[string]$Path)
    $relative=$Path.Substring([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/').Length+1).Replace('\','/')
    $tracked=@(& git -C $ProjectRoot ls-files -- $relative 2>$null)
    if($LASTEXITCODE -ne 0){throw 'RETENTION_GIT_CHECK_FAILED'}
    return ($tracked.Count -gt 0)
}

function Get-RoomKitRetentionProcesses {
    # Failure to inspect ownership/activity prevents deletion. Never terminates.
    $result=New-Object Collections.ArrayList
    if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){
        foreach($process in Get-CimInstance Win32_Process -ErrorAction Stop){[void]$result.Add(([string]$process.ExecutablePath)+' '+([string]$process.CommandLine))}
    }else{
        foreach($directory in Get-ChildItem -LiteralPath '/proc' -Directory -ErrorAction Stop|Where-Object Name -match '^\d+$'){
            try{[void]$result.Add([IO.File]::ReadAllText((Join-Path $directory.FullName 'cmdline')).Replace([char]0,' '))}
            catch{if(Test-Path -LiteralPath $directory.FullName){throw 'RETENTION_PROCESS_SCAN_FAILED'}}
        }
    }
    return @($result)
}

function Test-RoomKitRetentionRelatedPath {
    param([string]$Target,[string]$Reference)
    if(-not $Reference){return $false}
    $targetFull=[IO.Path]::GetFullPath($Target).TrimEnd('\','/')
    $referenceFull=[IO.Path]::GetFullPath($Reference).TrimEnd('\','/')
    $comparison=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    return ($targetFull.Equals($referenceFull,$comparison) -or $referenceFull.StartsWith($targetFull+[IO.Path]::DirectorySeparatorChar,$comparison) -or $targetFull.StartsWith($referenceFull+[IO.Path]::DirectorySeparatorChar,$comparison))
}

function Get-RoomKitRetentionPointerPaths {
    param([string]$ProjectRoot)
    $paths=New-Object Collections.ArrayList
    foreach($name in @('deployment-latest.json','framework-release.json','linux-server-latest.json','framework-games.json')){
        $pointer=Join-Path $ProjectRoot ('artifacts/'+$name)
        if(-not(Test-Path -LiteralPath $pointer)){continue}
        $item=Get-Item -LiteralPath $pointer -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RETENTION_LINKED_POINTER'}
        $json=Get-Content -LiteralPath $pointer -Encoding UTF8 -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
        $pending=New-Object Collections.Queue;$pending.Enqueue($json)
        while($pending.Count){
            $value=$pending.Dequeue()
            if($value -is [string]){
                if($value -notmatch '^([A-Za-z]:[\\/]|/|artifacts[\\/]|logs[\\/]|data[\\/])'){continue}
                $candidate=if([IO.Path]::IsPathRooted($value)){$value}else{Join-Path $ProjectRoot $value}
                if(Test-Path -LiteralPath $candidate){[void]$paths.Add([IO.Path]::GetFullPath($candidate))}
            }elseif($null -ne $value -and $value -is [Collections.IEnumerable] -and $value -isnot [string]){
                foreach($child in $value){$pending.Enqueue($child)}
            }elseif($null -ne $value -and $value -is [pscustomobject]){
                foreach($property in $value.PSObject.Properties){$pending.Enqueue($property.Value)}
            }
        }
    }
    return @($paths)
}

function Invoke-RoomKitArtifactRetention {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,
          [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9.-]{0,63}$')][string]$Category,
          [ValidateRange(1,10)][int]$Keep=2,[string[]]$ProtectedPaths=@())
    $lock=Open-RoomKitRetentionLock $ProjectRoot
    try{
        $ledger=Join-Path $ProjectRoot 'artifacts/retention-ledger'
        $records=@(Get-ChildItem -LiteralPath $ledger -Filter '*.json' -File|ForEach-Object {
            if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'RETENTION_LINKED_LEDGER'}
            $record=Get-Content -LiteralPath $_.FullName -Encoding UTF8 -Raw|ConvertFrom-Json
            if($record.format -ne 1 -or $record.id -ne $_.BaseName){throw 'RETENTION_INVALID_RECORD'}
            [pscustomobject]@{file=$_.FullName;record=$record}
        })
        $candidates=@($records|Where-Object {$_.record.category -eq $Category -and $_.record.state -eq 'retained'}|Sort-Object {$_.record.id} -Descending|Select-Object -Skip $Keep)
        if(-not $candidates.Count){return [pscustomobject]@{removed=0;skipped=0;bytes=0;keep=$Keep}}
        try{$processes=@(Get-RoomKitRetentionProcesses);$protected=@($ProtectedPaths)+@(Get-RoomKitRetentionPointerPaths $ProjectRoot)}
        catch{Write-Warning 'ARTIFACT_RETENTION_SKIPPED activity_or_pointer_check_failed';return [pscustomobject]@{removed=0;skipped=$candidates.Count;bytes=0;keep=$Keep}}
        # Protect both current outputs and their inputs. A reused path may also
        # appear in old metadata; pruning that record must not delete a kept run.
        foreach($group in @($records|Where-Object {$_.record.state -eq 'retained'}|Group-Object {$_.record.category})){
            foreach($current in @($group.Group|Sort-Object {$_.record.id} -Descending|Select-Object -First $Keep)){$protected+=@($current.record.paths);$protected+=@($current.record.references)}
            # Two failed generations must not evict the last usable delivery.
            $usable=@($group.Group|Where-Object {$_.record.outcome -eq 'success'}|Sort-Object {$_.record.id} -Descending|Select-Object -First 1)
            foreach($current in $usable){$protected+=@($current.record.paths);$protected+=@($current.record.references)}
        }
        $removed=0;$skipped=0;[long]$bytes=0
        foreach($candidate in $candidates){
            $record=$candidate.record;$reason=''
            try{
                foreach($path in $record.paths){
                    $full=Get-RoomKitRetentionPath $ProjectRoot $path
                    if(Test-RoomKitRetentionTrackedPath $ProjectRoot $full){$reason='tracked_source';break}
                    foreach($reference in $protected){if(Test-RoomKitRetentionRelatedPath $full $reference){$reason='referenced';break}}
                    foreach($command in $processes){if($command.IndexOf($full,[StringComparison]::OrdinalIgnoreCase) -ge 0){$reason='active_process';break}}
                    if($reason){break}
                }
                if(-not $reason){
                    $actual=@(Get-RoomKitArtifactSnapshot $ProjectRoot @($record.paths))
                    if(($actual|ConvertTo-Json -Depth 8 -Compress) -cne (@($record.snapshot)|ConvertTo-Json -Depth 8 -Compress)){$reason='changed_content'}
                }
            }catch{$reason='unsafe_or_unavailable'}
            if($reason){$record.last_skip=$reason;Write-RoomKitRetentionJson $candidate.file $record;$skipped++;Write-Warning ('ARTIFACT_RETENTION_SKIPPED '+$record.id+' '+$reason);continue}
            try{
                # Full path and complete tree were checked above. Recheck immediately
                # before each native deletion; no shell composition or globbing.
                foreach($path in $record.paths){
                    $full=Get-RoomKitRetentionPath $ProjectRoot $path
                    $verified=@(Get-RoomKitArtifactSnapshot $ProjectRoot @($full))
                    $expected=@($record.snapshot|Where-Object {$_.path -eq $full.Substring([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/').Length+1).Replace('\','/') -or $_.path.StartsWith($full.Substring([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/').Length+1).Replace('\','/')+'/',[StringComparison]::Ordinal)})
                    if(($verified|ConvertTo-Json -Depth 8 -Compress) -cne ($expected|ConvertTo-Json -Depth 8 -Compress)){throw 'RETENTION_CHANGED_BEFORE_DELETE'}
                    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
                }
                $record.state='pruned';$record.pruned_utc=[DateTime]::UtcNow.ToString('o');$record.last_skip=''
                Write-RoomKitRetentionJson $candidate.file $record
                $removed++;$bytes+=[long](($record.snapshot|Measure-Object size -Sum).Sum)
                Write-Output ('ARTIFACT_PRUNED '+$record.id+' evidence='+$candidate.file)
            }catch{$record.last_skip='delete_failed';Write-RoomKitRetentionJson $candidate.file $record;$skipped++;Write-Warning ('ARTIFACT_RETENTION_SKIPPED '+$record.id+' delete_failed')}
        }
        return [pscustomobject]@{removed=$removed;skipped=$skipped;bytes=$bytes;keep=$Keep}
    }finally{$lock.Dispose()}
}
