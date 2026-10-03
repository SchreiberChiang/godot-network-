param([string]$Source = '', [string]$ReportEmail = '')
# 把服务器主机提供的公开连接文件（connection.json + server.crt）放进本客户端目录。
# 用法：把包含这两个文件的文件夹拖到 SetServer.cmd 上；或把两个文件放进本目录的
# server-config 文件夹后双击 SetServer.cmd。只接受公开证书，拒绝私钥和凭据。
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'public_config.ps1')
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
AssertPublicConfigPlainPath $directory
$utf8=New-Object Text.UTF8Encoding($false)
if($Source -eq '') { $Source=Join-Path $directory 'server-config' }
$Source=[IO.Path]::GetFullPath($Source).TrimEnd('\','/')
AssertPublicConfigPlainPath $Source
if(Test-Path -LiteralPath $Source -PathType Leaf) { $Source=[IO.Path]::GetDirectoryName($Source) }
$configuration=Join-Path $Source 'connection.json'
$certificate=Join-Path $Source 'server.crt'
if(-not (Test-Path -LiteralPath $configuration -PathType Leaf) -or -not (Test-Path -LiteralPath $certificate -PathType Leaf)) {
    throw ('在 '+$Source+' 中没有同时找到 connection.json 和 server.crt。请向服务器主机索取这两个文件（服务器端运行 PublishClients.cmd 后位于 clients\shooter）。')
}
$connection=ReadPublicClientConnection $configuration
# Optional PUBLIC contact address; used only for an explicitly opened local draft.
if($ReportEmail -ne '') { $connection | Add-Member -NotePropertyName report_email -NotePropertyValue $ReportEmail -Force }
AssertPublicClientConnection $connection
AssertPublicConfigPlainPath $certificate
$pem=[IO.File]::ReadAllText($certificate)
AssertPublicClientCertificate $pem
AssertPublicConfigPlainPath (Join-Path $directory 'server.crt')
AssertPublicConfigPlainPath (Join-Path $directory 'connection.json')
if(-not ([IO.Path]::GetFullPath($Source) -ieq $directory)) {
    [IO.File]::WriteAllText((Join-Path $directory 'server.crt'),$pem,$utf8)
}
[IO.File]::WriteAllText((Join-Path $directory 'connection.json'),($connection | ConvertTo-Json -Depth 4),$utf8)
Write-Output ('SHOOTER_SERVER_SET '+$connection.url)
Write-Output '已设置目标服务器。现在双击 StartGame.cmd 启动游戏。'
