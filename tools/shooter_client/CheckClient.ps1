param()
# 检查本目录文件是否完整、与 client-version.json 一致，以及是否已设置服务器。
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'public_config.ps1')
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$version=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $directory 'client-version.json') | ConvertFrom-Json
$problems=0
# Runtime data is deliberately absent from generated_files and hashes. Validate
# its shape without reading/reporting its private contents or changing anything.
$data=Join-Path $directory 'client-data'
if(@(Get-ChildItem -LiteralPath $directory -Force | Where-Object Name -eq 'client-data').Count) {
    try {
        if(-not (Get-Item -LiteralPath $data -Force).PSIsContainer) { throw 'not_directory' }
        $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($data)
        while($pending.Count) {
            $path=$pending.Pop();$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType)) { throw 'linked_data' }
            if($item.PSIsContainer) { foreach($child in Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop) { $pending.Push($child.FullName) } }
        }
        Write-Output 'CLIENT_DATA_PRESENT private_local_state_do_not_distribute'
    } catch { Write-Output 'CLIENT_DATA_UNSAFE expected_plain_directory_without_links';$problems++ }
}
if($version.PSObject.Properties['generated_files'] -and @($version.generated_files | Where-Object { $_.path -match '(^|[\\/])client-data([\\/]|$)' }).Count) {
    Write-Output 'CLIENT_RUNTIME_IN_GENERATED_MANIFEST';$problems++
}
foreach($file in $version.files) {
    $path=Join-Path $directory $file.path
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Output ('缺少 '+$file.path+($(if($file.path -eq 'Client.exe'){'：双击 FetchClient.cmd 下载，或从 Release 页面手动下载'}else{''}))); $problems++; continue }
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256) { Write-Output ('文件不一致 '+$file.path); $problems++ }
}
$server=$false
$configuration=Join-Path $directory 'connection.json'
$certificate=Join-Path $directory 'server.crt'
$hasConfiguration=Test-Path -LiteralPath $configuration
$hasCertificate=Test-Path -LiteralPath $certificate
# A clean repository/unconfigured player copy intentionally has neither file.
# Partial or invalid settings must never be reported as configured/valid.
$expectsServer=($version.PSObject.Properties['configured'] -and $version.configured -eq $true) -or ($version.PSObject.Properties['server_configured'] -and $version.server_configured -eq $true)
if($hasConfiguration -or $hasCertificate -or $expectsServer) {
    try {
        if(-not (Test-Path -LiteralPath $configuration -PathType Leaf) -or -not (Test-Path -LiteralPath $certificate -PathType Leaf)) { throw 'PUBLIC_CONFIG_MISSING_FILES' }
        $connection=ReadPublicClientConnection $configuration
        AssertPublicClientConnection $connection
        AssertPublicConfigPlainPath $certificate
        AssertPublicClientCertificate ([IO.File]::ReadAllText($certificate))
        $server=$true
    } catch { Write-Output ('SHOOTER_SERVER_CONFIG_INVALID '+$_.Exception.Message); $problems++ }
}
Write-Output ('版本 '+$version.build_id+'；目标服务器：'+$(if($server){'已设置'}else{'未设置，运行 SetServer.cmd'}))
if($problems) { Write-Output ('SHOOTER_CLIENT_INCOMPLETE problems='+$problems); exit 1 }
Write-Output ('SHOOTER_CLIENT_VALID files='+@($version.files).Count+' server_configured='+$server)
exit 0
