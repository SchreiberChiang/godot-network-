param([switch]$SkipRealProject)
# Determinism and sensitivity of tools/content_digest.ps1 (roomkit-content-digest-v2).
# Everything happens under logs\content-digest-<id>; the shared game index, the
# user's PlayerClient and the repository client copy are never written.
# On Windows this simulates checkout forms; it is NOT a Linux run. The golden
# value below must also be reproduced on a real Linux machine before the digest
# is called cross-platform verified.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $project 'tools\content_digest.ps1')
$work=Join-Path $project ('logs\content-digest-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$script:passed=0; $script:failed=0; $script:notRun=0
function Check([bool]$Condition,[string]$Name) { if($Condition){ $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) } }
$latin=[Text.Encoding]::GetEncoding(28591)
$golden='05f794ef76f0'

# Logical content: text uses LF here; binaries are explicit bytes.
$textFiles=[ordered]@{
    'project.godot'="config_version=5`n[application]`nconfig/name=`"RoomKit Game`"`n"
    'client.gd'="extends SceneTree`nvar state := `"LOBBY`"`n`nfunc _initialize() -> void:`n`tprint(state)`n"
    'sdk/roomkit/shared/wire.gd'="extends RefCounted`nstatic func uid() -> String:`n`treturn `"x`"`n"
    'sdk/README.md'="# SDK`n`nTwo lines.`n"
    'game/game.gd'="extends Node`nconst SPEED := 235.0`n"
    'game/game_config.json'="{`n  `"version`": 1,`n  `"respawn_ms`": 3000`n}`n"
    'schemas/state.schema.json'="{`n  `"type`": `"object`",`n  `"required`": [`"tick`"]`n}`n"
    'B.gd'="# upper`n"
    'a-b.gd'="# dash`n"
    'a.gd'="# plain`n"
    'a_b.gd'="# underscore`n"
    'game_manifest.json'="{`"build_id`": `"will-be-replaced`"}`n"
    'game/game_manifest.json'="{`"build_id`": `"will-be-replaced`"}`n"
}
$binaryFiles=[ordered]@{
    'assets/icon.png'=[byte[]](137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,13,10,255)
    'assets/blob.bin'=[byte[]](1,2,13,10,3,4,13,10,5)
}
function WriteTree([string]$Name,[string]$Form,[switch]$Reverse,[hashtable]$TextOverride=@{},[hashtable]$BinaryOverride=@{},[string[]]$Skip=@()) {
    $root=Join-Path $work $Name
    $names=@($textFiles.Keys)+@($binaryFiles.Keys)
    if($Reverse) { [Array]::Reverse($names) }
    $index=0
    foreach($relative in $names) {
        if($Skip -contains $relative) { continue }
        $path=Join-Path $root ($relative.Replace('/','\'))
        New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($path)) | Out-Null
        if($binaryFiles.Contains($relative)) {
            $bytes=if($BinaryOverride.ContainsKey($relative)){ [byte[]]$BinaryOverride[$relative] } else { [byte[]]$binaryFiles[$relative] }
            [IO.File]::WriteAllBytes($path,$bytes)
        } else {
            $text=if($TextOverride.ContainsKey($relative)){ [string]$TextOverride[$relative] } else { [string]$textFiles[$relative] }
            $crlf=($Form -eq 'crlf') -or ($Form -eq 'mixed' -and $index % 2 -eq 0)
            if($crlf) { $text=$text.Replace("`n","`r`n") }
            [IO.File]::WriteAllBytes($path,$latin.GetBytes($text))
        }
        $index++
    }
    return $root
}
function Changed([string]$Name,[hashtable]$TextOverride=@{},[hashtable]$BinaryOverride=@{}) { return ContentDigest (WriteTree $Name 'lf' -TextOverride $TextOverride -BinaryOverride $BinaryOverride) }

# 1. Same logical input, different checkout forms and creation order.
$lfRoot=WriteTree 'lf' 'lf'
$base=ContentDigest $lfRoot
Check ($base -match '^[0-9a-f]{12}$') ('digest format ('+$base+')')
Check ($base -eq $golden) ('LF tree matches the pinned golden value '+$golden)
$crlfRoot=WriteTree 'crlf' 'crlf'
Check ((ContentDigest $crlfRoot) -eq $base) 'CRLF checkout gives the same digest'
Check ((ContentDigest (WriteTree 'mixed' 'mixed')) -eq $base) 'mixed LF/CRLF checkout gives the same digest'
Check ((ContentDigest (WriteTree 'reversed' 'crlf' -Reverse)) -eq $base) 'file creation order does not matter'

# 2. Independent implementation in another runtime.
$node=Get-Command node -ErrorAction SilentlyContinue
if($node) {
    $reference=Join-Path $project 'tests\content_digest_reference.cjs'
    Check ((& node $reference $lfRoot) -eq $base) 'independent Node reference agrees on the LF tree'
    Check ((& node $reference $crlfRoot) -eq $base) 'independent Node reference agrees on the CRLF tree'
} else { $script:notRun+=2; Write-Output 'NOT RUN independent Node reference (node not found)' }

# 3. Engine cache and the manifest copies are outside the identity.
$cacheRoot=WriteTree 'cache' 'lf'
foreach($relative in @('.godot\editor\cache.bin','.godot\imported\a.md5','sdk\.godot\x.cfg')) {
    $path=Join-Path $cacheRoot $relative
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllBytes($path,[byte[]](9,9,9))
}
Check ((ContentDigest $cacheRoot) -eq $base) '.godot cache directories (root and nested) are ignored'
Check ((Changed 'manifest' @{'game_manifest.json'="{`"build_id`": `"other`"}`n";'game/game_manifest.json'="{}`n"}) -eq $base) 'the two manifest copies that receive the id are ignored'
$nested=WriteTree 'nested-manifest' 'lf'
New-Item -ItemType Directory -Force -Path (Join-Path $nested 'other') | Out-Null
[IO.File]::WriteAllBytes((Join-Path $nested 'other\game_manifest.json'),$latin.GetBytes("{}`n"))
Check ((ContentDigest $nested) -ne $base) 'a manifest-named file elsewhere is content'
foreach($case in @(@('.godot\a.bin',$false),@('.godot/a.bin',$false),@('x\.godot\y.gd',$false),@('x/.godot/y.gd',$false),@('game\game_manifest.json',$false),@('game/game_manifest.json',$false),@('project.godot',$true),@('a.godot/x.gd',$true),@('.godotx/a.gd',$true),@('x/.godot',$true),@('.Godot/a.gd',$true))) {
    Check ((ContentDigestIncludes $case[0]) -eq $case[1]) ('path rule: '+$case[0]+' included='+$case[1])
}

# 4. Path separators and ordering.
$sample=$latin.GetBytes("a`r`nb`n")
Check ((ContentDigestEntry 'sdk\roomkit\a.gd' $sample) -ceq (ContentDigestEntry 'sdk/roomkit/a.gd' $sample)) 'backslash and slash paths give the same entry'
Check ((ContentDigestEntry 'sdk\roomkit\a.gd' $sample).StartsWith('sdk/roomkit/a.gd=')) 'entries always use forward slashes'
$entries=ContentDigestEntries $lfRoot
$shuffled=@($entries); [Array]::Reverse($shuffled)
Check ((ContentDigestOfEntries $shuffled) -eq $base) 'entry enumeration order does not matter'
$sortedNames=[string[]]@('a_b.gd','a.gd','sub/z.gd','B.gd','a-b.gd','Z.gd','sub.gd'); [Array]::Sort($sortedNames,[StringComparer]::Ordinal)
Check (($sortedNames -join ',') -ceq 'B.gd,Z.gd,a-b.gd,a.gd,a_b.gd,sub.gd,sub/z.gd') ('ordering is ordinal, not culture based ('+($sortedNames -join ',')+')')
$manual=New-Object Collections.Generic.List[string]
$manual.Add('roomkit-content-digest-v2'); foreach($line in $entries) { $manual.Add($line) }
$ordered=[string[]]$manual.ToArray(); $head=$ordered[0]; $tail=[string[]]@($ordered[1..($ordered.Length-1)]); [Array]::Sort($tail,[StringComparer]::Ordinal)
$sha=[Security.Cryptography.SHA256]::Create()
$expected=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((@($head)+$tail) -join "`n"))) -replace '-','').Substring(0,12).ToLowerInvariant()
$sha.Dispose()
Check ($expected -eq $base) 'digest equals the documented formula computed by hand'

# 5. Real changes must change the digest.
Check ((Changed 'code' @{'game/game.gd'="extends Node`nconst SPEED := 236.0`n"}) -ne $base) 'one character of game code changes the digest'
Check ((Changed 'sdk' @{'sdk/roomkit/shared/wire.gd'="extends RefCounted`nstatic func uid() -> String:`n`treturn `"y`"`n"}) -ne $base) 'an SDK change changes the digest'
Check ((Changed 'schema' @{'schemas/state.schema.json'="{`n  `"type`": `"object`",`n  `"required`": [`"tick`", `"phase`"]`n}`n"}) -ne $base) 'a schema change changes the digest'
Check ((Changed 'config' @{'game/game_config.json'="{`n  `"version`": 1,`n  `"respawn_ms`": 3001`n}`n"}) -ne $base) 'a game config change changes the digest'
Check ((Changed 'settings' @{'project.godot'="config_version=5`n[application]`nconfig/name=`"Other`"`n"}) -ne $base) 'project.godot is content'
Check ((Changed 'space' @{'a.gd'="# plain `n"}) -ne $base) 'a trailing space is content'
Check ((Changed 'lonecr' @{'a.gd'="# plain`r"}) -ne $base) 'a lone CR is not treated as a line ending'
Check ((Changed 'final' @{'a.gd'="# plain"}) -ne $base) 'a missing final newline is content'
Check ((Changed 'bom' @{'a.gd'=([string][char]0xEF+[char]0xBB+[char]0xBF+"# plain`n")}) -ne $base) 'a byte order mark is content'
$added=WriteTree 'added' 'lf'; [IO.File]::WriteAllBytes((Join-Path $added 'extra.gd'),$latin.GetBytes("# new`n"))
Check ((ContentDigest $added) -ne $base) 'an added file changes the digest'
Check ((ContentDigest (WriteTree 'removed' 'lf' -Skip @('sdk/README.md'))) -ne $base) 'a removed file changes the digest'
$renamed=WriteTree 'renamed' 'lf'; Rename-Item -LiteralPath (Join-Path $renamed 'a.gd') -NewName 'c.gd'
Check ((ContentDigest $renamed) -ne $base) 'a renamed file changes the digest'
$recased=WriteTree 'recased' 'lf'; Rename-Item -LiteralPath (Join-Path $recased 'a.gd') -NewName 'a.tmp'; Rename-Item -LiteralPath (Join-Path $recased 'a.tmp') -NewName 'A.gd'
Check ((ContentDigest $recased) -ne $base) 'a change of file name case changes the digest'

# 6. Binaries are never normalized.
Check ((Changed 'binary' @{} @{'assets/icon.png'=[byte[]](137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,13,10,254)}) -ne $base) 'one byte of a binary changes the digest'
Check ((Changed 'binary-eol' @{} @{'assets/icon.png'=[byte[]](137,80,78,71,10,26,10,0,0,0,13,73,72,68,82,10,255)}) -ne $base) 'CR LF inside a binary is data (known binary type)'
Check ((Changed 'unknown-eol' @{} @{'assets/blob.bin'=[byte[]](1,2,10,3,4,10,5)}) -ne $base) 'CR LF inside an unknown file type is data'
$nulCrlf=WriteTree 'nul-crlf' 'lf'; [IO.File]::WriteAllBytes((Join-Path $nulCrlf 'data.json'),[byte[]](123,0,13,10,125))
$nulLf=WriteTree 'nul-lf' 'lf'; [IO.File]::WriteAllBytes((Join-Path $nulLf 'data.json'),[byte[]](123,0,10,125))
Check ((ContentDigest $nulCrlf) -ne (ContentDigest $nulLf)) 'a text-named file containing NUL is hashed as binary'
Check ((ContentDigestIsText 'x/a.GD' $sample) -and -not (ContentDigestIsText 'x/a.pck' $sample) -and -not (ContentDigestIsText 'x/noextension' $sample)) 'text classification is by the fixed extension list'

# 7. The real prepared project: build from the working tree into a private index,
#    then re-create it as a pure LF and a pure CRLF checkout.
if(-not $SkipRealProject) {
    $index=Join-Path $work 'framework-games.json'
    $sharedIndex=Join-Path $project 'artifacts\framework-games.json'
    $sharedBefore=if(Test-Path -LiteralPath $sharedIndex){ (Get-FileHash -LiteralPath $sharedIndex).Hash } else { '' }
    & (Join-Path $project 'tools\build_framework.ps1') -IndexPath $index | Out-Null
    $built=Get-Content -Encoding UTF8 -Raw -LiteralPath $index | ConvertFrom-Json
    foreach($game in @('shooter','turns')) {
        $source=[string]$built.$game.project
        $id=[string]$built.$game.manifest.build_id
        $real=ContentDigest $source
        Check ($id.EndsWith('-src-'+$real)) ($game+' build_id carries the digest ('+$id+')')
        $forms=@{}
        foreach($form in @('lf','crlf')) {
            $copy=Join-Path $work ($game+'-'+$form)
            Copy-Item -LiteralPath $source -Destination $copy -Recurse
            $converted=0
            foreach($file in Get-ChildItem -LiteralPath $copy -Recurse -File -Force) {
                $bytes=[IO.File]::ReadAllBytes($file.FullName)
                if(-not (ContentDigestIsText $file.Name $bytes)) { continue }
                $text=$latin.GetString($bytes).Replace("`r`n","`n")
                if($form -eq 'crlf') { $text=$text.Replace("`n","`r`n") }
                [IO.File]::WriteAllBytes($file.FullName,$latin.GetBytes($text)); $converted++
            }
            $forms[$form]=ContentDigest $copy
            Check ($forms[$form] -eq $real) ($game+' as a pure '+$form.ToUpper()+' checkout keeps the digest ('+$converted+' text files)')
            if($node) { Check ((& node (Join-Path $project 'tests\content_digest_reference.cjs') $copy) -eq $real) ($game+' '+$form.ToUpper()+' copy: Node reference agrees') } else { $script:notRun++ }
        }
        $nonText=@(Get-ChildItem -LiteralPath $source -Recurse -File -Force | Where-Object { (ContentDigestIncludes $_.FullName.Substring($source.Length+1)) -and -not (ContentDigestIsText $_.Name ([IO.File]::ReadAllBytes($_.FullName))) } | ForEach-Object { $_.Name })
        Write-Output ('INFO '+$game+' files hashed as binary: '+$(if($nonText.Count){ $nonText -join ', ' } else { 'none' }))
    }
    $sharedAfter=if(Test-Path -LiteralPath $sharedIndex){ (Get-FileHash -LiteralPath $sharedIndex).Hash } else { '' }
    Check ($sharedBefore -eq $sharedAfter) 'the shared game index was not modified'
} else { Write-Output 'NOT RUN real prepared project (-SkipRealProject)'; $script:notRun++ }

Write-Output ('CONTENT_DIGEST_RESULT passed='+$script:passed+' failed='+$script:failed+' not_run='+$script:notRun+' golden='+$base+' evidence='+$work)
exit $(if($script:failed -eq 0){0}else{1})
