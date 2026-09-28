param()
# 启动本目录的射击客户端。连接配置和证书必须与 Client.exe 在同一目录。
# Godot 会挂到父进程的控制台上；为免关闭 StartGame 的黑色窗口时连带结束游戏，
# 由一个隐藏的中转 PowerShell 启动 Client.exe，游戏因此挂在无人能关闭的隐藏控制台上。
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$configuration=Join-Path $directory 'connection.json'
$client=Join-Path $directory 'Client.exe'
if(-not (Test-Path -LiteralPath $client -PathType Leaf)) { throw '缺少 Client.exe。请向发给你目录的人要完整目录，或运行 FetchClient.cmd（如果有）。' }
if(-not (Test-Path -LiteralPath $configuration -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $directory 'server.crt') -PathType Leaf)) { throw '缺少 connection.json 或 server.crt。请让服务器主机运行 PreparePlayerClient.cmd 重新生成目录，或用 SetServer.cmd 设置。' }
function SingleQuoted([string]$Value) { return "'"+$Value.Replace("'","''")+"'" }
$arguments=@('--','--game=shooter',('--connection-config='+$configuration))
$quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
$inner='Start-Process -FilePath '+(SingleQuoted $client)+' -WorkingDirectory '+(SingleQuoted $directory)+' -ArgumentList @('+(($quoted | ForEach-Object { SingleQuoted $_ }) -join ',')+')'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
