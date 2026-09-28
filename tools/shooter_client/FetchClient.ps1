param([string]$BaseUrl = '')
# 从 GitHub Release 下载与本目录版本匹配的 Client.exe（原文件，不是压缩包），
# 并按 client-version.json 校验大小和 SHA256。校验失败不会留下 Client.exe。
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$version=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $directory 'client-version.json') | ConvertFrom-Json
$expected=@($version.files | Where-Object { $_.path -eq 'Client.exe' })[0]
$target=Join-Path $directory 'Client.exe'
if((Test-Path -LiteralPath $target -PathType Leaf) -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ieq $expected.sha256) {
    Write-Output 'SHOOTER_CLIENT_EXE_OK 已有正确的 Client.exe，无需下载。'
    exit 0
}
if($BaseUrl -eq '') { $BaseUrl=[string]$version.release_url }
if($BaseUrl -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/[A-Za-z0-9_.-]+/$') { throw '下载地址必须是本项目 GitHub Release 的附件地址。' }
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$temporary=$target+'.partial'
Write-Output ('正在下载 Client.exe（约 '+[math]::Round($expected.size/1MB)+' MB）：'+$BaseUrl+'Client.exe')
$ProgressPreference='SilentlyContinue'
try { Invoke-WebRequest -Uri ($BaseUrl+'Client.exe') -OutFile $temporary -UseBasicParsing }
catch { if(Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }; throw ('下载失败：'+$_.Exception.Message.TrimEnd('。','.')+'。也可在 Release 页面手动下载 Client.exe 放进本目录。') }
$item=Get-Item -LiteralPath $temporary
$hash=(Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
if($item.Length -ne [int64]$expected.size -or $hash -ine $expected.sha256) { Remove-Item -LiteralPath $temporary -Force; throw 'Client.exe 校验失败，已删除下载的文件。请确认 Release 版本与本目录一致。' }
Move-Item -LiteralPath $temporary -Destination $target -Force
Write-Output 'SHOOTER_CLIENT_EXE_OK Client.exe 下载并校验完成。'
