param(
    [string]$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$IndexPath = '',
    [string]$ConnectionDirectory = '',
    [string]$OutputRoot = '',
    [switch]$Unconfigured,
    [switch]$RepositoryCopy,
    [string]$RepositoryDestination = '',
    [string]$Repository = 'SchreiberChiang/godot-network-',
    [ValidateSet('','swap')][string]$TestFailAt = ''
)
# 从 StartManagement.cmd 当前服务器所用的射击工程导出独立客户端，并附上该服务器的
# 公开 connection.json/server.crt。版本校验保持原样：客户端清单就是服务器自己的清单。
# 同一次导出同时供本地分发（含连接配置）和 GitHub 仓库副本（-RepositoryCopy，不含连接配置）。
# 输出只写入受控目录；替换前核对清单，发现用户新增或改动的文件就拒绝；旧目录移入 previous\ 保留，失败时自动回退。
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$utf8=New-Object Text.UTF8Encoding($false)
$helpers=Join-Path $PSScriptRoot 'shooter_client'
if($IndexPath -eq '') { $IndexPath=Join-Path $project 'artifacts\framework-games.json' }
if($ConnectionDirectory -eq '') { $ConnectionDirectory=Join-Path $project 'artifacts\client' }
$defaultPlayerOutput=($OutputRoot -eq '')
if($defaultPlayerOutput) { $OutputRoot=Join-Path $project 'artifacts\player-clients' }
$repositoryDefault=Join-Path $project 'clients\shooter-windows'
if($RepositoryDestination -eq '') { $RepositoryDestination=$repositoryDefault }

function Controlled([string]$Path,[string]$Label) {
    # Only Git-ignored artifacts\ or logs\ (or the fixed repository copy) may be written.
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $ok=$false
    foreach($root in @('artifacts','logs')) { if($full.StartsWith($project+'\'+$root+'\',[StringComparison]::OrdinalIgnoreCase)) { $ok=$true } }
    if($Label -eq 'repository' -and $full -ieq $repositoryDefault) { $ok=$true }
    if($Label -eq 'player' -and $full -ieq (Join-Path $project 'PlayerClient')) { $ok=$true }
    if(-not $ok) { throw ('拒绝写入受控范围以外的目录（'+$Label+'）：'+$full) }
    $probe=$full
    while($probe.Length -gt $project.Length) {
        if((Test-Path -LiteralPath $probe) -and ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('拒绝写入链接目录：'+$probe) }
        $probe=[IO.Path]::GetDirectoryName($probe)
    }
    return $full
}
function FileTable([string]$Directory) {
    $table=[ordered]@{}
    foreach($file in Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | Sort-Object FullName) {
        $relative=$file.FullName.Substring($Directory.Length+1).Replace('\','/')
        if($relative -eq 'client-version.json') { continue }
        $table[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $table
}
function WriteVersion([string]$Directory,$Base) {
    $version=[ordered]@{}
    foreach($key in $Base.Keys) { $version[$key]=$Base[$key] }
    $core=@()
    foreach($name in @('Client.exe','Client.pck','RunGame.ps1','StartGame.cmd')) {
        $path=Join-Path $Directory $name
        $core+=[ordered]@{path=$name;size=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $version.files=$core
    $generated=FileTable $Directory
    $version.generated_files=@($generated.Keys | ForEach-Object { [ordered]@{path=$_;sha256=$generated[$_]} })
    [IO.File]::WriteAllText((Join-Path $Directory 'client-version.json'),($version | ConvertTo-Json -Depth 6),$utf8)
}
function SafeReplace([string]$Target,[string]$Stage,[string]$BackupRoot) {
    if(-not (Test-Path -LiteralPath $Target)) { Move-Item -LiteralPath $Stage -Destination $Target; return '' }
    $versionFile=Join-Path $Target 'client-version.json'
    if(-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) { throw ('目标目录不是本工具生成的客户端，拒绝覆盖：'+$Target) }
    $old=Get-Content -Encoding UTF8 -Raw -LiteralPath $versionFile | ConvertFrom-Json
    $known=@{}
    if($old.PSObject.Properties['generated_files']) { foreach($entry in $old.generated_files) { $known[$entry.path]=$entry.sha256 } }
    else {
        # Earlier format: core files with hashes plus the fixed helper/config names.
        foreach($entry in $old.files) { $known[$entry.path]=$entry.sha256 }
        foreach($name in @('README.md','SetServer.ps1','SetServer.cmd','CheckClient.ps1','CheckClient.cmd','FetchClient.ps1','FetchClient.cmd','connection.json','server.crt')) { if(-not $known.ContainsKey($name)) { $known[$name]='*' } }
    }
    $problems=@()
    $actual=FileTable $Target
    foreach($path in $actual.Keys) {
        if(-not $known.ContainsKey($path)) { $problems+=('新增 '+$path) }
        elseif($known[$path] -ne '*' -and $known[$path] -ne $actual[$path]) { $problems+=('已改动 '+$path) }
    }
    if($problems.Count) { throw ('目标目录里有不是本工具生成的内容，为避免丢失已停止，旧目录未改动：'+$Target+'；'+($problems -join '，')+'。请先把这些文件移走，或换一个目录保存。') }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $backup=Join-Path $BackupRoot ([IO.Path]::GetFileName($Target)+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id.Substring(0,6))
    Move-Item -LiteralPath $Target -Destination $backup
    try {
        if($TestFailAt -eq 'swap') { throw 'TEST_INJECTED_SWAP_FAILURE' }
        Move-Item -LiteralPath $Stage -Destination $Target
    } catch {
        if(Test-Path -LiteralPath $Target) { throw ('替换失败且无法自动回退；旧目录保存在 '+$backup) }
        Move-Item -LiteralPath $backup -Destination $Target
        throw ('替换失败，已恢复旧目录：'+$_.Exception.Message)
    }
    return $backup
}

$OutputRoot=Controlled $OutputRoot 'output'
$target=Join-Path $OutputRoot 'shooter-windows'
if($defaultPlayerOutput) { $target=Controlled (Join-Path $project 'PlayerClient') 'player' }
if($RepositoryCopy) { $RepositoryDestination=Controlled $RepositoryDestination 'repository' }
$template=Join-Path ([IO.Path]::GetDirectoryName($Godot)) 'editor_data\export_templates\4.7.2.stable\windows_release_x86_64.exe'
if(-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw ('Godot editor not found: '+$Godot) }
if(-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw 'The Godot 4.7.2 Windows release export template is missing.' }
if(-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) { throw '缺少游戏索引，请先运行 StartManagement.cmd。' }
foreach($name in $(if($Unconfigured){@()}else{@('connection.json','server.crt')})) {
    if(-not (Test-Path -LiteralPath (Join-Path $ConnectionDirectory $name) -PathType Leaf)) { throw ('缺少公开连接文件 '+$name+'，请先运行 StartManagement.cmd，由管理服务发布。') }
}
$index=Get-Content -Encoding UTF8 -Raw -LiteralPath $IndexPath | ConvertFrom-Json
$source=[string]$index.shooter.project
$manifest=$index.shooter.manifest
if(-not $source -or -not (Test-Path -LiteralPath (Join-Path $source 'client.gd') -PathType Leaf)) { throw '缺少已准备的射击工程，请先运行 StartManagement.cmd。' }
$onDisk=Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $source 'game_manifest.json') | ConvertFrom-Json
foreach($key in @('game_id','build_id','compatibility_id','game_protocol')) {
    if([string]$onDisk.$key -ne [string]$manifest.$key) { throw ('Prepared project manifest differs from the server index: '+$key) }
}

$id=[Guid]::NewGuid().ToString('N')
$staging=Join-Path $OutputRoot ('.staging-'+$id)
$work=Join-Path $staging 'project'
$stage=Join-Path $staging 'shooter-windows'
$repoStage=Join-Path $staging 'repository'
New-Item -ItemType Directory -Force -Path $work,$stage,(Join-Path $project 'logs') | Out-Null
try {
    foreach($item in Get-ChildItem -LiteralPath $source -Force) {
        if($item.Name -eq '.godot') { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $work -Recurse
    }
    [IO.File]::WriteAllText((Join-Path $work 'main.gd'),"class_name PlayerClientMain`nextends `"res://client.gd`"`n",$utf8)
    [IO.File]::WriteAllText((Join-Path $work 'empty.tscn'),"[gd_scene format=3]`n[node name=`"Bootstrap`" type=`"Node`"]`n",$utf8)
    $settingsFile=Join-Path $work 'project.godot'
    $text=[IO.File]::ReadAllText($settingsFile) -replace '(?m)^run/main_scene=.*\r?\n','' -replace '(?m)^run/main_loop_type=.*\r?\n',''
    [IO.File]::WriteAllText($settingsFile,$text.Replace('[application]',"[application]`nrun/main_loop_type=`"PlayerClientMain`"`nrun/main_scene=`"res://empty.tscn`""),$utf8)
    $preset=@'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
export_filter="all_resources"
include_filter="*.json,*.gd,*.tscn"
exclude_filter="**/preview.gd,**/test_runner.gd"
export_path=""
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'@
    [IO.File]::WriteAllText((Join-Path $work 'export_presets.cfg'),$preset,$utf8)
    $pack=Join-Path $stage 'Client.pck'
    $stdout=Join-Path $project ('logs\player-client-export-'+$id+'.log')
    $stderr=Join-Path $project ('logs\player-client-export-'+$id+'-stderr.log')
    $arguments=@('--headless','--path',$work,'--export-pack','Windows Desktop',$pack)
    $quoted=foreach($argument in $arguments) { '"'+($argument -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"' }
    $process=Start-Process -FilePath $Godot -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $ownedHandle=$process.Handle
    if(-not $process.WaitForExit(180000)) { $process.Kill(); $process.WaitForExit(); throw 'Client export timed out.' }
    if($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack -PathType Leaf) -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' -Quiet)) { throw ('Client export failed; see '+$stderr) }
    Copy-Item -LiteralPath $template -Destination (Join-Path $stage 'Client.exe')
    foreach($name in @('RunGame.ps1','StartGame.cmd','SetServer.ps1','SetServer.cmd','CheckClient.ps1','CheckClient.cmd')) { Copy-Item -LiteralPath (Join-Path $helpers $name) -Destination $stage }

    $pckHash=(Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash.ToLowerInvariant()
    $tag='shooter-client-'+(([string]$manifest.build_id) -replace '[^A-Za-z0-9.-]','-')+'-'+$pckHash.Substring(0,8)
    $base=[ordered]@{format=2;source=$(if($Unconfigured){'PreparedIndex'}else{'StartManagement'});game_id=$manifest.game_id;build_id=$manifest.build_id;compatibility_id=$manifest.compatibility_id;game_protocol=$manifest.game_protocol;engine_template='4.7.2.stable windows_release_x86_64';prepared_at=[DateTime]::UtcNow.ToString('o');release_tag=$tag;release_url=('https://github.com/'+$Repository+'/releases/download/'+$tag+'/')}

    # Repository copy: identical export, no server-specific files, plus GitHub fetch helpers.
    if($RepositoryCopy) {
        Copy-Item -LiteralPath $stage -Destination $repoStage -Recurse
        foreach($name in @('FetchClient.ps1','FetchClient.cmd')) { Copy-Item -LiteralPath (Join-Path $helpers $name) -Destination $repoStage }
        Copy-Item -LiteralPath (Join-Path $helpers 'README.md') -Destination (Join-Path $repoStage 'README.md')
        WriteVersion $repoStage $base
    }
    Copy-Item -LiteralPath (Join-Path $helpers 'PLAYER_README.md') -Destination (Join-Path $stage 'README.md')
    if($Unconfigured) {
        [IO.File]::WriteAllText((Join-Path $stage 'README.md'),@'
# RoomKit shooter player - server not configured yet

This is a complete Windows player program; no Godot editor is required.
It deliberately does NOT contain connection.json or server.crt. The build
machine has not started your target server or created a certificate for it.

1. Ask the actual server host for its PUBLIC connection.json and server.crt.
2. Drag their containing folder onto SetServer.cmd. Never accept a private key.
3. Double-click Client.exe (StartGame.cmd is also available), then register with
   an invitation from the host, log in, and create/join a shooter room.

Keep the whole folder together when giving it to a player. CheckClient.cmd
checks the executable/pack hashes and reports whether a server is configured.
client-version.json must match the server build; admission checks are unchanged.
Server updates may need a matching fresh player folder. Do not give players
server databases, private certificates, administrator credentials or backups.
'@,$utf8)
    }
    # SetServer validates the public files (wss url, allowed fields, no private key).
    if(-not $Unconfigured) {
        $set=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'SetServer.ps1') $ConnectionDirectory
        if($LASTEXITCODE -ne 0) { throw ('公开连接文件未通过检查：'+($set -join ' ')) }
    }
    WriteVersion $stage $base

    foreach($directory in @($stage,$repoStage)) {
        if(-not (Test-Path -LiteralPath $directory)) { continue }
        foreach($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Force) {
            $relative=$file.FullName.Substring($directory.Length+1).Replace('\','/')
            if($relative -match '(^|/)(data|run|logs|backups?)/|\.(key|sqlite|db|token)$|admin|secret') { throw ('客户端目录中出现不应分发的文件：'+$relative) }
            if($file.Extension -in @('.crt','.pem','.json') -and ([IO.File]::ReadAllText($file.FullName) -match 'PRIVATE KEY')) { throw ('客户端目录中出现私钥：'+$relative) }
        }
        foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.ps1' -File) {
            $tokens=$null; $errors=$null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            if($errors.Count) { throw ('PowerShell parse failure: '+$file.Name) }
        }
    }
    if($RepositoryCopy -and ((Test-Path -LiteralPath (Join-Path $repoStage 'connection.json')) -or (Test-Path -LiteralPath (Join-Path $repoStage 'server.crt')))) { throw '仓库副本不应包含服务器连接文件。' }

    $previous=SafeReplace $target $stage (Join-Path $OutputRoot 'previous')
    if($previous) { Write-Output ('PLAYER_CLIENT_PREVIOUS '+$previous) }
    if($RepositoryCopy) {
        $repoPrevious=SafeReplace $RepositoryDestination $repoStage (Join-Path $OutputRoot 'previous-repository')
        if($repoPrevious) { Write-Output ('REPOSITORY_CLIENT_PREVIOUS '+$repoPrevious) }
        Write-Output ('REPOSITORY_CLIENT_READY '+$RepositoryDestination+' tag='+$tag)
        # GitHub Release attachments: exactly the repository copy's files, Client.exe
        # included, uploaded one by one (no archive). The list and hashes sit beside
        # the folder so the folder holds only what gets uploaded.
        $releaseDir=Join-Path $OutputRoot ('release-'+$tag)
        $releaseStage=Join-Path $staging 'release'
        Copy-Item -LiteralPath $RepositoryDestination -Destination $releaseStage -Recurse
        $releasePrevious=SafeReplace $releaseDir $releaseStage (Join-Path $OutputRoot 'previous-release')
        if($releasePrevious) { Write-Output ('RELEASE_ASSETS_PREVIOUS '+$releasePrevious) }
        $assets=@(Get-ChildItem -LiteralPath $releaseDir -File | Sort-Object Name | ForEach-Object { [ordered]@{name=$_.Name;size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} })
        if(@(Get-ChildItem -LiteralPath $releaseDir -Directory).Count) { throw 'Release attachments must be a flat folder.' }
        if(-not ($assets | Where-Object { $_.name -eq 'Client.exe' })) { throw 'Release attachments are missing Client.exe.' }
        [IO.File]::WriteAllText(($releaseDir+'.json'),([ordered]@{tag=$tag;build_id=$manifest.build_id;repository=$Repository;target_path='clients/shooter-windows';assets=$assets}|ConvertTo-Json -Depth 4),$utf8)
        [IO.File]::WriteAllText(($releaseDir+'-SHA256SUMS.txt'),((($assets | ForEach-Object { $_.sha256+'  '+$_.name }) -join "`n")+"`n"),$utf8)
        Write-Output ('RELEASE_ASSETS_READY '+$releaseDir+' files='+$assets.Count+' bytes='+(Get-ChildItem -LiteralPath $releaseDir -File | Measure-Object Length -Sum).Sum)
    }
} finally {
    if(Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
$connection=if($Unconfigured){[pscustomobject]@{url='UNCONFIGURED'}}else{Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $target 'connection.json') | ConvertFrom-Json}
$size=(Get-ChildItem -LiteralPath $target -Recurse -File | Measure-Object Length -Sum).Sum
Write-Output ('PLAYER_CLIENT_READY '+$target+' build='+$manifest.build_id+' tag='+$tag+' url='+$connection.url+' bytes='+$size)
if([string]$connection.url -match '^wss://(127\.|localhost)') {
    Write-Output 'WARNING: 服务器对外地址是本机回环地址，只能在这台电脑上连接。给朋友用前，请在管理后台停止游戏服务器、把对外 IP 设为本机局域网地址、重新启动，然后再运行 PreparePlayerClient.cmd。'
}
