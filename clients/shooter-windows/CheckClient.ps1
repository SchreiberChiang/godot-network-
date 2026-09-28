param()
# 检查本目录文件是否完整、与 client-version.json 一致，以及是否已设置服务器。
$ErrorActionPreference='Stop'
$directory=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$version=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $directory 'client-version.json') | ConvertFrom-Json
$problems=0
foreach($file in $version.files) {
    $path=Join-Path $directory $file.path
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Output ('缺少 '+$file.path+($(if($file.path -eq 'Client.exe'){'：双击 FetchClient.cmd 下载，或从 Release 页面手动下载'}else{''}))); $problems++; continue }
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256) { Write-Output ('文件不一致 '+$file.path); $problems++ }
}
$server=(Test-Path -LiteralPath (Join-Path $directory 'connection.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $directory 'server.crt') -PathType Leaf)
Write-Output ('版本 '+$version.build_id+'；目标服务器：'+$(if($server){'已设置'}else{'未设置，运行 SetServer.cmd'}))
if($problems) { Write-Output ('SHOOTER_CLIENT_INCOMPLETE problems='+$problems); exit 1 }
Write-Output ('SHOOTER_CLIENT_VALID files='+@($version.files).Count+' server_configured='+$server)
exit 0
