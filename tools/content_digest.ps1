# Build identity digest for a prepared game project (used by build_framework.ps1
# and its tests). Deterministic: sorted relative paths plus each file's SHA256.
# The two manifest copies are excluded because they receive the resulting id.
function ContentDigest([string]$Root) {
    $Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $lines=foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.godot\\' }) {
        $relative=$file.FullName.Substring($Root.Length+1).Replace('\','/')
        if($relative -in @('game_manifest.json','game/game_manifest.json')) { continue }
        $relative+'='+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $text=(@($lines) | Sort-Object -CaseSensitive) -join "`n"
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-','').Substring(0,12).ToLowerInvariant() } finally { $sha.Dispose() }
}
