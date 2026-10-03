param([string]$Source = '', [string]$ReportEmail = '')
# 把服务器主机提供的公开连接文件（connection.json + server.crt）放进本客户端目录。
# 用法：把包含这两个文件的文件夹拖到 SetServer.cmd 上；或把两个文件放进本目录的
# server-config 文件夹后双击 SetServer.cmd。只接受公开证书，拒绝私钥和凭据。
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$utf8=New-Object Text.UTF8Encoding($false)
if($Source -eq '') { $Source=Join-Path $directory 'server-config' }
$Source=[IO.Path]::GetFullPath($Source).TrimEnd('\','/')
if(Test-Path -LiteralPath $Source -PathType Leaf) { $Source=[IO.Path]::GetDirectoryName($Source) }
$configuration=Join-Path $Source 'connection.json'
$certificate=Join-Path $Source 'server.crt'
if(-not (Test-Path -LiteralPath $configuration -PathType Leaf) -or -not (Test-Path -LiteralPath $certificate -PathType Leaf)) {
    throw ('在 '+$Source+' 中没有同时找到 connection.json 和 server.crt。请向服务器主机索取这两个文件（服务器端运行 PublishClients.cmd 后位于 clients\shooter）。')
}
$text=[IO.File]::ReadAllText($configuration)
try { $connection=$text | ConvertFrom-Json } catch { throw 'connection.json 不是有效的 JSON。' }
if($connection -isnot [PSCustomObject]) { throw 'connection.json 格式错误。' }
$allowed=@('url','ca_certificate','server_hostname','managed','secure_enet','report_email')
foreach($property in $connection.PSObject.Properties) {
    if($property.Name -notin $allowed) { throw ('connection.json 含有客户端不应接收的字段：'+$property.Name) }
}
# Optional PUBLIC contact address; used only for an explicitly opened local draft.
if($ReportEmail -ne '') { $connection | Add-Member -NotePropertyName report_email -NotePropertyValue $ReportEmail -Force }
if($connection.PSObject.Properties['report_email']) {
    $address=$connection.report_email
    if($address -isnot [string] -or $address.Length -gt 254 -or $address -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._+-]{0,63}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\z') { throw 'report_email must be one mailbox address, without spaces, newlines or mail parameters.' }
}
if([string]$connection.url -notmatch '^wss://[A-Za-z0-9.-]+:[0-9]{1,5}/?$') { throw 'connection.json 的 url 必须是 wss://主机:端口。' }
$pem=[IO.File]::ReadAllText($certificate)
if($pem -match 'PRIVATE KEY') { throw 'server.crt 含有私钥，已拒绝。不要把服务器私钥发给玩家。' }
if($pem -notmatch '-----BEGIN CERTIFICATE-----') { throw 'server.crt 不是 PEM 证书。' }
$connection | Add-Member -NotePropertyName ca_certificate -NotePropertyValue 'server.crt' -Force
if(-not ([IO.Path]::GetFullPath($Source) -ieq $directory)) {
    Copy-Item -LiteralPath $certificate -Destination (Join-Path $directory 'server.crt') -Force
}
[IO.File]::WriteAllText((Join-Path $directory 'connection.json'),($connection | ConvertTo-Json -Depth 4),$utf8)
Write-Output ('SHOOTER_SERVER_SET '+$connection.url)
Write-Output '已设置目标服务器。现在双击 StartGame.cmd 启动游戏。'
