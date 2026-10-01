# Plumbing shared by the Linux acceptance and endurance drivers (dot-source it
# after support/portable.ps1): the administrator HTTP API of an Operator and real
# headless clients (tests/run_framework_clients.gd) driven through command files.
# The same client protocol as tests/test_framework_clients.ps1; no game logic here.
# Credentials only ever go to 600 files inside the caller's private folder and
# the one-use client bootstrap (the client deletes it after reading).
$script:RkApiUrl=''
$script:RkToken=''
$script:RkCommand=0
$script:RkUtf8=New-Object Text.UTF8Encoding($false)

function Rk-SaveJson([string]$Path,$Value) {
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 50 -Compress),$script:RkUtf8)
    if ($script:RkPosix) { [IO.File]::SetUnixFileMode($temporary,[IO.UnixFileMode]'UserRead,UserWrite') }
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Rk-ReadJson([string]$Path) {
    # Reports are atomically replaced by a running client. Both existence and
    # content reads can race that replacement; let the caller's bounded poll retry.
    try { if (-not (Test-Path -LiteralPath $Path)) { return $null }; return Get-Content -Encoding UTF8 -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

## Administrator API. -Anonymous for setup/login. Throws on a transport failure
## (the message never contains the credential).
function Rk-Api([string]$Action,$Payload=@{},[switch]$Anonymous,[int]$Timeout=65) {
    $headers=@{}
    if ($script:RkToken -and -not $Anonymous) { $headers.Authorization='Bearer '+$script:RkToken }
    $body=[Text.Encoding]::UTF8.GetBytes((@{action=$Action;payload=$Payload} | ConvertTo-Json -Depth 25 -Compress))
    try { return Invoke-RestMethod -Uri ($script:RkApiUrl+'/api') -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec $Timeout }
    catch { throw ('API '+$Action+' transport failed (credentials suppressed)') }
}
function Rk-WaitApi([int]$Seconds=90) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { if ((Rk-Api 'setup.status' @{} -Anonymous -Timeout 5).ok) { return $true } } catch { }
        Start-Sleep -Milliseconds 300
    }
    return $false
}
function Rk-AdminLogin([string]$File) {
    $saved=Rk-ReadJson $File
    $reply=Rk-Api 'admin.login' @{username=$saved.username;password=$saved.password} -Anonymous
    if ($reply.ok) { $script:RkToken=$reply.payload.token }
    return $reply.ok
}
function Rk-WaitHost([string]$State,[int]$Seconds=90) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do { $status=(Rk-Api 'status').payload; if ($status.host.state -eq $State) { return $status }; Start-Sleep -Milliseconds 400 } while ([DateTime]::UtcNow -lt $deadline)
    return $status
}
function Rk-WaitRoom([string]$RoomId,[string]$State='READY',[int]$Seconds=60) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do { $row=@((Rk-Api 'status').payload.rooms | Where-Object room_id -eq $RoomId)[0]; if ($null -ne $row -and $row.state -eq $State) { return $row }; Start-Sleep -Milliseconds 300 } while ([DateTime]::UtcNow -lt $deadline)
    return $row
}
function Rk-Coins([string]$UserId,[string]$Game) {
    $reply=Rk-Api 'asset.read' @{user_id=$UserId;game_id=$Game}
    if (-not $reply.ok) { throw ('asset.read failed: '+$reply.code) }
    return $reply.payload.state
}

## A real headless client. $Settings: username, password, display_name,
## invite_code (register when present), register, room_id.
function Rk-StartClient([string]$Godot,[string]$Project,[string]$Folder,[string]$Name,[string]$Game,$Connection,$Manifest,[hashtable]$Settings) {
    $directory=Join-Path $Folder $Name
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $bootstrap=Join-Path $directory 'bootstrap.json'
    $report=Join-Path $directory 'report.json'
    $config=@{connection=@{url=$Connection.url;ca_certificate=$Connection.ca_certificate;server_hostname=$Connection.server_hostname;game_id=$Game};manifest=$Manifest;game_id=$Game;report_path=$report;control_directory=$directory;timeout_ms=1200000}
    foreach($key in $Settings.Keys) { $config[$key]=$Settings[$key] }
    Rk-SaveJson $bootstrap $config
    $arguments=@('--headless','--path',$Project,'--log-file',(Join-Path $directory 'engine.log'),'--script','res://tests/run_framework_clients.gd','--',('--test-config='+$bootstrap))
    $process=Rk-StartHidden $Godot $arguments (Join-Path $directory 'console.log') (Join-Path $directory 'stderr.log')
    return @{name=$Name;game=$Game;directory=$directory;report=$report;process=$process;user_id=''}
}
function Rk-Report($Client) { return Rk-ReadJson $Client.report }
function Rk-WaitReport($Client,[scriptblock]$Predicate,[int]$Seconds=90) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $report=Rk-Report $Client
        if ($null -ne $report -and (& $Predicate $report)) { return $report }
        if ($Client.process.HasExited) { return $null }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}
## Sends one command and returns its result (with elapsed_ms) or $null on timeout.
function Rk-Command($Client,[string]$Action,[hashtable]$Payload=@{},[int]$Seconds=65) {
    $script:RkCommand++
    $id='c'+$script:RkCommand.ToString('D6')
    $value=@{id=$id;action=$Action}
    foreach($key in $Payload.Keys) { $value[$key]=$Payload[$key] }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Rk-SaveJson (Join-Path $Client.directory ($id+'.command.json')) $value
    $report=Rk-WaitReport $Client {param($r) @($r.results | Where-Object id -eq $id).Count -gt 0} $Seconds
    if ($null -eq $report) { return $null }
    $result=@($report.results | Where-Object id -eq $id)[-1]
    $result | Add-Member -NotePropertyName elapsed_ms -NotePropertyValue $clock.ElapsedMilliseconds -Force
    return $result
}
## Asks the client to close; a test client that does not leave is ended by the
## test that started it (its own child process, never another one).
function Rk-StopClient($Client) {
    if (-not $Client.process.HasExited) { try { [void](Rk-Command $Client 'close' @{} 8) } catch { } }
    $clean=$true
    if (-not $Client.process.WaitForExit(5000)) { $Client.process.Kill(); [void]$Client.process.WaitForExit(5000); $clean=$false }
    # Normally the client deleted its one-use bootstrap; one that never read it must not keep it.
    Remove-Item -LiteralPath (Join-Path $Client.directory 'bootstrap.json') -ErrorAction SilentlyContinue
    return $clean -and $Client.process.HasExited -and $Client.process.ExitCode -eq 0
}

## The public connection of an instance with an absolute CA path.
function Rk-Connection([string]$PublicDir) {
    $public=Rk-ReadJson (Join-Path $PublicDir 'connection.json')
    return @{url=$public.url;ca_certificate=(Join-Path $PublicDir $public.ca_certificate);server_hostname=$public.server_hostname}
}
