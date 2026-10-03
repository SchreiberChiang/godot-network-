# Frozen export inputs. Separate from the established content-digest-v2 build ID.
# Receipt v1 hashes ordinal paths and raw bytes, including both manifest copies.
$script:PreparedInputAlgorithm='roomkit-prepared-input-v1'
function PreparedInputHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function AssertPreparedPlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType))) { throw 'PREPARED_INPUT_LINKED' }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor) { break }; $cursor=$parent
    }
}
function GetPreparedInputFiles([string]$Root,[switch]$ExportWork) {
    $Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    AssertPreparedPlainPath $Root
    if(-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'PREPARED_INPUT_MISSING' }
    $queue=New-Object Collections.Queue
    foreach($item in Get-ChildItem -LiteralPath $Root -Force) {
        $allowed=if($item.PSIsContainer){$item.Name -in @('game','sdk','schemas')}else{$item.Name -in @('project.godot','game_manifest.json') -or $item.Extension -in @('.gd','.uid') -or ($ExportWork -and $item.Name -in @('empty.tscn','export_presets.cfg'))}
        if($allowed){$queue.Enqueue($item.FullName)}
    }
    $paths=New-Object Collections.Generic.List[string]
    $caseNames=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    while($queue.Count) {
        $path=[string]$queue.Dequeue();$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.Name -in @('.godot','data','client-data','logs','run','backup','backups')){continue}
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType)){throw 'PREPARED_INPUT_LINKED'}
        $relative=$item.FullName.Substring($Root.Length+1).Replace('\','/')
        if(-not $caseNames.Add($relative)){throw 'PREPARED_INPUT_CASE_COLLISION'}
        if($item.PSIsContainer){foreach($child in Get-ChildItem -LiteralPath $path -Force){$queue.Enqueue($child.FullName)}}else{$paths.Add($relative)}
    }
    $sorted=[string[]]$paths.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    return ,$sorted
}
function PreparedInputReceiptOfFiles($Files) {
    $lines=@($Files | ForEach-Object {[string]$_.path+'='+[string]$_.sha256})
    return PreparedInputHash ([Text.Encoding]::UTF8.GetBytes($script:PreparedInputAlgorithm+"`n"+($lines -join "`n")))
}
function GetPreparedInputReceipt([string]$Root,[switch]$ExportWork) {
    $files=@(GetPreparedInputFiles $Root -ExportWork:$ExportWork | ForEach-Object { $_ } | ForEach-Object {
        [ordered]@{path=$_;sha256=(PreparedInputHash ([IO.File]::ReadAllBytes((Join-Path $Root $_))))}
    })
    return [ordered]@{format=1;algorithm=$script:PreparedInputAlgorithm;sha256=(PreparedInputReceiptOfFiles $files);files=$files}
}
function NewPreparedExportReceipt([string]$Root,$Original,$BootstrapHashes) {
    # Derive from the frozen receipt, not from a newly trusted scan of all code.
    # Only these four files are replaced by our export bootstrap/preset writer.
    $bootstrap=@('project.godot','main.gd','empty.tscn','export_presets.cfg')
    $expected=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach($file in $Original.files){if([string]$file.path -cnotin $bootstrap){$expected[[string]$file.path]=[string]$file.sha256}}
    foreach($path in $bootstrap){
        if($null -eq $BootstrapHashes -or [string]$BootstrapHashes[$path] -cnotmatch '^[0-9a-f]{64}$'){throw 'PREPARED_BOOTSTRAP_RECEIPT_REQUIRED'}
        $expected[$path]=[string]$BootstrapHashes[$path]
    }
    $paths=[string[]]@($expected.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal)
    $files=@($paths | ForEach-Object {[ordered]@{path=$_;sha256=$expected[$_]}})
    $receipt=[ordered]@{format=1;algorithm=$script:PreparedInputAlgorithm;sha256=(PreparedInputReceiptOfFiles $files);files=$files}
    AssertPreparedInputReceipt $Root $receipt -ExportWork -AllowGeneratedUids
    return $receipt
}
function AssertPreparedInputReceipt([string]$Root,$Expected,[switch]$ExportWork,[switch]$AllowGeneratedUids) {
    if($null -eq $Expected -or [string]$Expected.format -cne '1' -or [string]$Expected.algorithm -cne $script:PreparedInputAlgorithm -or [string]$Expected.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not @($Expected.files).Count) { throw 'PREPARED_INPUT_RECEIPT_REQUIRED rebuild_the_prepared_index' }
    if((PreparedInputReceiptOfFiles $Expected.files) -cne [string]$Expected.sha256){throw 'PREPARED_INPUT_RECEIPT_INVALID'}
    $actual=GetPreparedInputReceipt $Root -ExportWork:$ExportWork
    if($AllowGeneratedUids) {
        $expectedPaths=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($file in $Expected.files){[void]$expectedPaths.Add([string]$file.path)}
        # A cold import may create a sidecar only for an input already frozen.
        # Existing UID files and all other input additions/changes remain strict.
        $actual.files=@($actual.files | Where-Object { $p=[string]$_.path; $expectedPaths.Contains($p) -or -not($p.EndsWith('.uid',[StringComparison]::Ordinal) -and $expectedPaths.Contains($p.Substring(0,$p.Length-4))) })
        $actual.sha256=PreparedInputReceiptOfFiles $actual.files
    }
    if([string]$actual.sha256 -cne [string]$Expected.sha256){throw 'PREPARED_INPUT_CHANGED rebuild_the_prepared_index'}
}
function CopyPreparedInput([string]$Source,[string]$Destination) {
    $Source=[IO.Path]::GetFullPath($Source).TrimEnd('\','/')
    AssertPreparedPlainPath $Destination
    foreach($relative in (GetPreparedInputFiles $Source)) {
        $target=Join-Path $Destination $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath (Join-Path $Source $relative) -Destination $target
    }
}
