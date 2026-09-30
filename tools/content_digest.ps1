# Build identity digest for a prepared game project (used by build_framework.ps1
# and its tests). The same logical content gives the same digest on Windows and
# Linux checkouts; any real change to code, schemas, data or binaries changes it.
#
# Rules (version roomkit-content-digest-v2; tests/test_content_digest.ps1 and the
# independent reference tests/content_digest_reference.cjs pin them):
#  1. Every file under the root is included, except the two manifest copies that
#     receive the resulting id (game_manifest.json, game/game_manifest.json) and
#     anything inside a directory named exactly ".godot" (engine cache).
#  2. Relative paths use "/" whatever the platform separator is; names keep their
#     exact case.
#  3. Text files are those with an extension in $ContentDigestTextExtensions and
#     no NUL byte. Only for them, each CR LF pair is replaced by LF before
#     hashing (the one difference between checkout forms). A lone CR, trailing
#     spaces, a BOM or a final newline are content and stay significant.
#  4. Every other file is binary and hashed byte for byte.
#  5. Entries "path=SHA256HEX" are sorted ordinally (UTF-16 code units), joined
#     with LF after the version line, hashed with SHA256 over UTF-8; the digest
#     is the first 12 lowercase hex characters.
$script:ContentDigestVersion='roomkit-content-digest-v2'
$script:ContentDigestTextExtensions=@('.gd','.json','.godot','.tscn','.tres','.cfg','.md','.txt','.gdshader','.csv','.svg')

function ContentDigestIncludes([string]$Relative) {
    $path=$Relative.Replace('\','/')
    if($path -ceq 'game_manifest.json' -or $path -ceq 'game/game_manifest.json') { return $false }
    $segments=$path.Split('/')
    for($index=0; $index -lt $segments.Length-1; $index++) { if($segments[$index] -ceq '.godot') { return $false } }
    return $true
}

function ContentDigestIsText([string]$Relative,[byte[]]$Bytes) {
    $extension=[IO.Path]::GetExtension($Relative).ToLowerInvariant()
    return ($script:ContentDigestTextExtensions -contains $extension) -and ([Array]::IndexOf($Bytes,[byte]0) -lt 0)
}

function ContentDigestHex([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-','') } finally { $sha.Dispose() }
}

function ContentDigestEntry([string]$Relative,[byte[]]$Bytes) {
    $path=$Relative.Replace('\','/')
    if(ContentDigestIsText $path $Bytes) {
        # ISO-8859-1 maps every byte to one character and back, so this edits
        # bytes exactly without decoding the file's real encoding.
        $latin=[Text.Encoding]::GetEncoding(28591)
        $Bytes=$latin.GetBytes($latin.GetString($Bytes).Replace("`r`n","`n"))
    }
    return $path+'='+(ContentDigestHex $Bytes)
}

function ContentDigestOfEntries([string[]]$Entries) {
    $lines=[string[]]@($Entries)
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $text=(@($script:ContentDigestVersion)+$lines) -join "`n"
    return (ContentDigestHex ([Text.Encoding]::UTF8.GetBytes($text))).Substring(0,12).ToLowerInvariant()
}

function ContentDigestEntries([string]$Root) {
    $Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $entries=New-Object Collections.Generic.List[string]
    foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $relative=$file.FullName.Substring($Root.Length+1)
        if(-not (ContentDigestIncludes $relative)) { continue }
        $entries.Add((ContentDigestEntry $relative ([IO.File]::ReadAllBytes($file.FullName))))
    }
    return ,$entries.ToArray()
}

function ContentDigest([string]$Root) {
    return ContentDigestOfEntries (ContentDigestEntries $Root)
}
