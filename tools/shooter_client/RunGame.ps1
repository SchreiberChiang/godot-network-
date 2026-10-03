param()
# 启动本目录的射击客户端。连接配置和证书必须与 Client.exe 在同一目录。
# 隐藏中转持有自己启动的原生进程，观察 2 秒；通过仅说明进程仍在运行。
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$configuration=Join-Path $directory 'connection.json'
$client=Join-Path $directory 'Client.exe'
if(-not (Test-Path -LiteralPath $client -PathType Leaf)) { throw '缺少 Client.exe。请向发给你目录的人要完整目录，或运行 FetchClient.cmd（如果有）。' }
if(-not (Test-Path -LiteralPath $configuration -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $directory 'server.crt') -PathType Leaf)) { throw '缺少 connection.json 或 server.crt。请让服务器主机运行 PreparePlayerClient.cmd 重新生成目录，或用 SetServer.cmd 设置。' }
. (Join-Path $directory 'client_startup.ps1')
$arguments=@('--','--game=shooter',('--connection-config='+$configuration))
$result=Start-ClientObserved -FilePath $client -Arguments $arguments -Directory $directory
if($result.status -eq 'observed') { Write-Output ('CLIENT_STARTUP_OBSERVED pid='+$result.pid+' observation_ms='+$result.observation_ms+' receipt='+$result.receipt_path) }
else { Write-Output ('CLIENT_STARTUP_FAILED status='+$result.status+' native_exit_code='+$result.native_exit_code+' stderr='+$result.stderr+' receipt='+$result.receipt_path) }
exit $result.launcher_exit_code
