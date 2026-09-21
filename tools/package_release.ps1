$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$index=Get-Content -Encoding UTF8 -Raw (Join-Path $root 'artifacts/release.json') | ConvertFrom-Json
$bundle=$index.bundle
& (Join-Path $bundle 'Manage.ps1') -Operation verify
if($LASTEXITCODE -ne 0) { throw 'Bundle verification failed' }
$id=[Guid]::NewGuid().ToString('N')
$clean=Join-Path $root ('artifacts/package-'+$id)
New-Item -ItemType Directory -Path $clean | Out-Null
$manifest=Get-Content -Encoding UTF8 -Raw (Join-Path $bundle 'checksums.json') | ConvertFrom-Json
foreach($entry in $manifest.files) {
    # Copy the immutable build allowlist, never the live directory tree.
    if($entry.path -match '^(data|run|logs|artifacts)/' -or $entry.path -match '\.(key|pem)$') { throw 'Runtime/private file in build manifest' }
    $destination=Join-Path $clean $entry.path
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($destination)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $bundle $entry.path) -Destination $destination
}
Copy-Item -LiteralPath (Join-Path $bundle 'checksums.json') -Destination $clean
$zip=Join-Path $root ('artifacts/RoomKit-0.1.0-windows-'+$id+'.zip')
Compress-Archive -Path (Join-Path $clean '*') -DestinationPath $zip -CompressionLevel Optimal
& (Join-Path $PSScriptRoot 'new_game.ps1') -GameId 'starter_game'
$template=Get-Content -Encoding UTF8 -Raw (Join-Path $root 'artifacts/template.json') | ConvertFrom-Json
$sdkZip=Join-Path $root ('artifacts/RoomKit-SDK-0.4.0-template-'+$id+'.zip')
Compress-Archive -Path (Join-Path $template.project '*') -DestinationPath $sdkZip -CompressionLevel Optimal
$unpacked=Join-Path $root ('artifacts/unpacked-'+$id)
Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
& (Join-Path $unpacked 'Manage.ps1') -Operation verify
$delivery=@{bundle=$bundle;zip=$zip;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;template_zip=$sdkZip;template_sha256=(Get-FileHash -LiteralPath $sdkZip -Algorithm SHA256).Hash;unpacked=$unpacked}
[IO.File]::WriteAllText((Join-Path $root 'artifacts/delivery.json'),($delivery | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
Write-Output ('PACKAGE_OK '+$zip)
Write-Output ('TEMPLATE_PACKAGE_OK '+$sdkZip)
