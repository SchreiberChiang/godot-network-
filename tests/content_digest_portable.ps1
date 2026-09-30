param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Work,
    [string]$ExpectShooter='',
    [string]$ExpectTurns=''
)
# Portable driver for the production digest (tools/content_digest.ps1 of $Source).
# Runs unchanged under Windows PowerShell 5.1 and PowerShell 7 on Linux: no
# Windows paths, no build scripts, no engine. It does not replace
# tests/test_content_digest.ps1; it carries the subset that must agree across
# platforms:
#  A. the synthetic fixture of that test (same logical content) must reproduce
#     the pinned golden value in every checkout form;
#  B. a prepared game tree assembled from an explicit source file list (the list
#     tools/build_framework.ps1 copies) must give the digest the other platform
#     computed for the same commit (-ExpectShooter / -ExpectTurns).
$ErrorActionPreference='Stop'
$Source=[IO.Path]::GetFullPath($Source)
$Work=[IO.Path]::GetFullPath($Work)
. ([IO.Path]::Combine($Source,'tools','content_digest.ps1'))
if(Test-Path -LiteralPath $Work) { if(@(Get-ChildItem -LiteralPath $Work -Force).Count) { throw 'Work directory must be empty.' } } else { [void][IO.Directory]::CreateDirectory($Work) }
$script:passed=0; $script:failed=0; $script:notRun=0
function Check([bool]$Condition,[string]$Name) { if($Condition){ $script:passed++; Write-Output ('PASS '+$Name) } else { $script:failed++; Write-Output ('FAIL '+$Name) } }
function Rooted([string]$Root,[string]$Relative) { $path=$Root; foreach($part in $Relative.Split('/')) { $path=[IO.Path]::Combine($path,$part) }; return $path }
function PutBytes([string]$Root,[string]$Relative,[byte[]]$Bytes) { $path=Rooted $Root $Relative; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)); [IO.File]::WriteAllBytes($path,$Bytes) }
$latin=[Text.Encoding]::GetEncoding(28591)
$golden='05f794ef76f0'
Write-Output ('INFO platform='+[Environment]::OSVersion.Platform+' ps='+$PSVersionTable.PSVersion+' separator='+[IO.Path]::DirectorySeparatorChar)

# A. Synthetic fixture: keep identical to tests/test_content_digest.ps1.
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
function WriteTree([string]$Name,[string]$Form,[switch]$Reverse,[hashtable]$TextOverride=@{},[hashtable]$BinaryOverride=@{}) {
    $root=Rooted $Work ('fixture/'+$Name)
    $names=@($textFiles.Keys)+@($binaryFiles.Keys)
    if($Reverse) { [Array]::Reverse($names) }
    $index=0
    foreach($relative in $names) {
        if($binaryFiles.Contains($relative)) {
            $bytes=if($BinaryOverride.ContainsKey($relative)){ [byte[]]$BinaryOverride[$relative] } else { [byte[]]$binaryFiles[$relative] }
            PutBytes $root $relative $bytes
        } else {
            $text=if($TextOverride.ContainsKey($relative)){ [string]$TextOverride[$relative] } else { [string]$textFiles[$relative] }
            $crlf=($Form -eq 'crlf') -or ($Form -eq 'mixed' -and $index % 2 -eq 0)
            if($crlf) { $text=$text.Replace("`n","`r`n") }
            PutBytes $root $relative $latin.GetBytes($text)
        }
        $index++
    }
    return $root
}
$lfRoot=WriteTree 'lf' 'lf'
$base=ContentDigest $lfRoot
Check ($base -eq $golden) ('LF fixture reproduces the golden value '+$golden+' (got '+$base+')')
Check ((ContentDigest (WriteTree 'crlf' 'crlf')) -eq $golden) 'CRLF fixture reproduces the golden value'
Check ((ContentDigest (WriteTree 'mixed' 'mixed')) -eq $golden) 'mixed LF/CRLF fixture reproduces the golden value'
Check ((ContentDigest (WriteTree 'reversed' 'crlf' -Reverse)) -eq $golden) 'reversed creation order reproduces the golden value'
$cacheRoot=WriteTree 'cache' 'lf'
foreach($relative in @('.godot/editor/cache.bin','.godot/imported/a.md5','sdk/.godot/x.cfg')) { PutBytes $cacheRoot $relative ([byte[]](9,9,9)) }
Check ((ContentDigest $cacheRoot) -eq $golden) '.godot cache directories are ignored'
Check ((ContentDigest (WriteTree 'code' 'lf' -TextOverride @{'game/game.gd'="extends Node`nconst SPEED := 236.0`n"})) -ne $golden) 'a code change changes the digest'
Check ((ContentDigest (WriteTree 'binary' 'lf' -BinaryOverride @{'assets/icon.png'=[byte[]](137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,13,10,254)})) -ne $golden) 'a binary change changes the digest'
Check ((ContentDigest (WriteTree 'binary-eol' 'lf' -BinaryOverride @{'assets/blob.bin'=[byte[]](1,2,10,3,4,10,5)})) -ne $golden) 'CR LF inside a binary is data'
$entries=ContentDigestEntries $lfRoot
Check (@($entries | Where-Object { $_.Contains('\') }).Count -eq 0 -and @($entries | Where-Object { $_.StartsWith('sdk/roomkit/shared/wire.gd=') }).Count -eq 1) 'entries use forward slashes on this platform'

# B. Prepared game trees from the explicit list tools/build_framework.ps1 copies.
$settings=@'
config_version=5
[application]
config/name="RoomKit Game"
[display]
window/size/viewport_width=1100
window/size/viewport_height=780
[rendering]
renderer/rendering_method="gl_compatibility"
[debug]
file_logging/enable_file_logging=false
'@
function CopyFile([string]$From,[string]$To) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($To)); [IO.File]::Copy($From,$To) }
function Prepare([string]$Id,[string]$Example) {
    $destination=Rooted $Work ('prepared/'+$Id)
    $sdk=Rooted $Source 'sdk'
    foreach($file in Get-ChildItem -LiteralPath $sdk -Recurse -File -Force) { CopyFile $file.FullName (Rooted $destination ('sdk/'+$file.FullName.Substring($sdk.Length+1).Replace('\','/'))) }
    foreach($name in @('game.gd','adapter.gd','room.gd','asset_policy.gd','rewards.gd','game_config.json')) {
        $from=Rooted $Source ('examples/'+$Example+'/'+$name)
        if(Test-Path -LiteralPath $from -PathType Leaf) { CopyFile $from (Rooted $destination ('game/'+$name)) }
    }
    CopyFile (Rooted $Source ('examples/'+$Example+'/game_manifest.json')) (Rooted $destination 'game_manifest.json')
    foreach($name in @('client.gd','view.gd','sound.gd')) { CopyFile (Rooted $Source ('examples/framework/'+$name)) (Rooted $destination $name) }
    foreach($file in Get-ChildItem -LiteralPath (Rooted $Source 'schemas') -Filter '*.json' -File) { CopyFile $file.FullName (Rooted $destination ('schemas/'+$file.Name)) }
    PutBytes $destination 'project.godot' ((New-Object Text.UTF8Encoding($false)).GetBytes($settings))
    return $destination
}
foreach($case in @(@('shooter','shooter',$ExpectShooter),@('turns','turn_based',$ExpectTurns))) {
    $tree=Prepare $case[0] $case[1]
    $files=@(Get-ChildItem -LiteralPath $tree -Recurse -File -Force)
    $crlf=@($files | Where-Object { $latin.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains("`r`n") }).Count
    $digest=ContentDigest $tree
    Write-Output ('INFO '+$case[0]+' prepared files='+$files.Count+' files_with_crlf='+$crlf+' digest='+$digest)
    if($case[2]) { Check ($digest -eq $case[2]) ($case[0]+' prepared tree gives the expected digest '+$case[2]+' (got '+$digest+')') }
    else { $script:notRun++; Write-Output ('NOT RUN '+$case[0]+' expected digest not supplied') }
}
Write-Output ('CONTENT_DIGEST_PORTABLE passed='+$script:passed+' failed='+$script:failed+' not_run='+$script:notRun)
exit $(if($script:failed -eq 0){0}else{1})
