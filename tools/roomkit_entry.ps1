# Shared dispatch only. No startup, writes, dependency installation, or probes
# occur when this file is loaded. Compatible with Windows PowerShell 5.1.
function Assert-RoomKitPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ('Linked path refused: '+$Path)}
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break}; $cursor=$parent
    }
}
function Assert-RoomKitTree([string]$Path) {
    Assert-RoomKitPath $Path
    if(Test-Path -LiteralPath $Path -PathType Container) {
        # Walk one level at a time: never descend into a junction/symlink.
        foreach($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Linked runtime item refused: '+$item.FullName)}
            if($item.PSIsContainer){Assert-RoomKitTree $item.FullName}
        }
    }
}
function Require-RoomKitFiles([string]$Root,[string[]]$Files) {
    foreach($file in $Files) {
        $path=Join-Path $Root $file
        Assert-RoomKitPath $path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Incomplete RoomKit layout: '+$file)}
    }
}
function Get-RoomKitLayout([string]$Root,[string]$Platform) {
    Assert-RoomKitPath $Root
    $linux=Test-Path -LiteralPath (Join-Path $Root 'linux-package.json')
    $windows=Test-Path -LiteralPath (Join-Path $Root 'RunFramework.ps1')
    $source=Test-Path -LiteralPath (Join-Path $Root 'host/operator.gd')
    if(([int]$linux+[int]$windows+[int]$source) -ne 1){throw 'Unknown or ambiguous RoomKit layout; keep the complete source/package together.'}
    Require-RoomKitFiles $Root @('project.godot','tools/roomkit_entry.ps1','tools/roomkit.ps1')
    if($source) {
        Require-RoomKitFiles $Root @('host/managed_host.gd','sdk/roomkit/shared/json_wire.gd','tools/build_framework.ps1','examples/framework/services.json')
        return 'source'
    }
    if($linux) {
        if($Platform -ne 'Linux'){throw 'A Linux package cannot run on Windows.'}
        Require-RoomKitFiles $Root @('Operator.x86_64','Operator.pck','ManagedHost.x86_64','ManagedHost.pck','games.json','SHA256SUMS.txt','tools/roomkit_linux.sh','tools/runtime_paths.sh','tools/prepare_environment.sh')
        $manifest=Get-Content -LiteralPath (Join-Path $Root 'linux-package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if($manifest.format -ne 1 -or $manifest.engine -ne '4.7.2.stable.official.ed1daf0bf'){throw 'Unsupported Linux package metadata.'}
        return 'linux-package'
    }
    if($Platform -ne 'Windows'){throw 'A Windows package cannot run on Linux.'}
    Require-RoomKitFiles $Root @('Operator.exe','Operator.pck','ManagedHost.exe','ManagedHost.pck','artifacts/framework-games.json','checksums.json')
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'checksums.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($manifest.engine -ne '4.7.2.stable.official.ed1daf0bf' -or @($manifest.files).Count -eq 0){throw 'Unsupported Windows package metadata.'}
    return 'windows-package'
}
function Get-RoomKitOptions([string[]]$Arguments,[string]$Platform) {
    $action='help'; $options=@{}
    if($Arguments.Count -gt 0){$action=$Arguments[0]}
    if($action -notin @('help','start','status','stop','check')){throw 'Action must be start, status, stop, check or help.'}
    for($i=1;$i -lt $Arguments.Count;$i++) {
        $key=$Arguments[$i]
        if($key -notin @('--instance','--panel-port','--lobby-port','--control-port','--udp-range','--bind','--godot','--no-browser')){throw ('Unknown option: '+$key)}
        if($options.ContainsKey($key)){throw ('Duplicate option: '+$key)}
        if($key -eq '--no-browser'){$options[$key]=$true;continue}
        $i++
        if($i -ge $Arguments.Count -or [string]::IsNullOrEmpty($Arguments[$i]) -or $Arguments[$i].StartsWith('--')){throw ('Missing option value: '+$key)}
        $options[$key]=$Arguments[$i]
    }
    foreach($key in $options.Keys) {
        if($action -eq 'help' -or ($action -in @('status','stop') -and $key -ne '--instance') -or ($action -eq 'check' -and $key -ne '--godot')){throw ('Option does not apply to '+$action+': '+$key)}
        if($Platform -eq 'Linux' -and $key -in @('--godot','--no-browser')){throw 'Linux uses ROOMKIT_GODOT; it does not open a browser.'}
    }
    if($options.ContainsKey('--instance') -and $options['--instance'] -cnotmatch '^[a-z0-9-]{1,32}$'){throw 'Invalid instance name.'}
    foreach($key in @('--panel-port','--lobby-port','--control-port')) {
        if($options.ContainsKey($key) -and ($options[$key] -notmatch '^[1-9][0-9]{3,4}$' -or [int]$options[$key] -lt 1024 -or [int]$options[$key] -gt 65535)){throw ('Invalid port: '+$key)}
    }
    if($options.ContainsKey('--udp-range')) {
        if($options['--udp-range'] -notmatch '^([1-9][0-9]{3,4})-([1-9][0-9]{3,4})$'){throw 'Invalid UDP range.'}
        $first=[int]$Matches[1];$last=[int]$Matches[2]
        if($first -lt 1024 -or $last -gt 65535 -or $first -gt $last -or $last-$first -gt 255){throw 'Invalid UDP range.'}
    }
    if($options.ContainsKey('--bind')) {
        if($options['--bind'] -notmatch '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'){throw 'Invalid IPv4 address.'}
        foreach($octet in $options['--bind'].Split('.')){if([int]$octet -gt 255){throw 'Invalid IPv4 address.'}}
    }
    if($action -eq 'start') {
        $ports=if($Platform -eq 'Linux'){@{'--panel-port'='28491';'--lobby-port'='28500';'--control-port'='28501';'--udp-range'='28540-28555'}}else{@{'--panel-port'='28291';'--lobby-port'='28300';'--control-port'='28301';'--udp-range'='28400-28431'}}
        foreach($key in @($ports.Keys)){if($options.ContainsKey($key)){$ports[$key]=$options[$key]}}
        $tcp=@([int]$ports['--panel-port'],[int]$ports['--lobby-port'],[int]$ports['--control-port'])
        if(@($tcp|Select-Object -Unique).Count -ne 3){throw 'Panel, lobby and control ports must differ.'}
        $range=$ports['--udp-range'].Split('-')
        foreach($port in $tcp){if($port -ge [int]$range[0] -and $port -le [int]$range[1]){throw 'TCP port overlaps the UDP range.'}}
        if($Platform -eq 'Linux' -and $tcp[0] -eq 28291){throw 'Linux panel port 28291 is reserved by the existing launcher.'}
    }
    if($options.ContainsKey('--godot')) {
        if(-not[IO.Path]::IsPathRooted($options['--godot'])){throw 'Godot path must be absolute.'}
        Assert-RoomKitPath $options['--godot']
    }
    return @{Action=$action;Options=$options}
}
function Invoke-RoomKitWindowsDelegate([string]$File,[hashtable]$Parameters) {
    & $File @Parameters
    exit $LASTEXITCODE
}
function Invoke-RoomKitDelegate([string]$File,[object[]]$Arguments,[bool]$Shell) {
    if($Shell){& bash $File @Arguments; exit $LASTEXITCODE}
    & $File @Arguments
    # Official PowerShell launchers use exit; preserve the script exit code.
    exit $LASTEXITCODE
}
function Invoke-RoomKit([string]$Root,[string]$Platform,[string[]]$Arguments) {
    if($Platform -notin @('Windows','Linux')){throw 'Supported platforms: Windows and Linux.'}
    $parsed=Get-RoomKitOptions $Arguments $Platform
    $action=$parsed.Action;$options=$parsed.Options
    if($action -eq 'help') {
        Write-Output @'
RoomKit - management service (source or complete native package)
  RoomKit.cmd start|status|stop|check|help     Windows PowerShell 5.1
  bash RoomKit.sh start|status|stop|check|help Linux pwsh 7 + bash
No arguments shows this help and starts nothing. check never starts a service.
  --instance NAME   lowercase letters/digits/hyphens, 1-32 characters
  start: --panel-port P --lobby-port P --control-port P --udp-range A-B --bind IPv4
  Windows source start/check: --godot ABSOLUTE_PATH; start: --no-browser
Defaults: Windows framework / data/framework / panel 28291;
          Linux l3 / data/instance-l3/data / panel 28491.
Keep the same instance for status/stop. Saved network settings win on restart.
A custom Windows instance stores its data under data/instance-NAME/data.
Windows status may say UNKNOWN (legacy descriptors lack creation identity).
check is preparation validation, not running status. No automatic installation.
Old shortcuts remain available. Windows and Linux need different native binaries.
'@
        return
    }
    $layout=Get-RoomKitLayout $Root $Platform
    $name=if($Platform -eq 'Linux'){'l3'}else{'framework'}
    if($options.ContainsKey('--instance')){$name=$options['--instance']}
    $instance=Join-Path $Root ('data/instance-'+$name)
    $data=Join-Path $instance 'data'
    if($Platform -eq 'Windows' -and $name -eq 'framework'){$instance=Join-Path $Root 'data/framework';$data=$instance}
    # A stop/status must not inspect unrelated build history, public files or run
    # directories. Validate the actual record/signal, including every ancestor.
    if($action -in @('stop','status')) {
        Assert-RoomKitPath (Join-Path $data 'operator.json')
        if($Platform -eq 'Linux'){Assert-RoomKitPath (Join-Path $instance 'instance.json')}
        if($action -eq 'stop'){Assert-RoomKitPath (Join-Path $data 'operator-stop.request')}
    } elseif($action -eq 'start') {
        Assert-RoomKitTree $data
        Assert-RoomKitTree (Join-Path $Root 'run')
        if($Platform -eq 'Linux') {
            # Linux's existing launcher owns its selected instance tree.
            Assert-RoomKitTree $instance
        }
    }
    if($action -eq 'start'){Write-Output ('ROOMKIT_INSTANCE name='+$name+' data='+$data+' layout='+$layout)}
    # Relative paths avoid false positives in the existing Linux leftover scan.
    Set-Location -LiteralPath $Root
    if($Platform -eq 'Linux') {
        Require-RoomKitFiles $Root @('tools/roomkit_linux.sh','tools/runtime_paths.sh','tools/prepare_environment.sh')
        if($action -eq 'check'){Invoke-RoomKitDelegate 'tools/prepare_environment.sh' @('check') $true;return}
        $forward=@($action)
        foreach($key in @('--instance','--panel-port','--lobby-port','--control-port','--udp-range','--bind')){if($options.ContainsKey($key)){$forward+=@($key,$options[$key])}}
        Invoke-RoomKitDelegate 'tools/roomkit_linux.sh' $forward $true
        return
    }
    if($layout -eq 'windows-package' -and $options.ContainsKey('--godot')){throw 'Windows packages contain their engine; --godot is source-only.'}
    if($action -eq 'status') {
        Require-RoomKitFiles $Root @('tools/roomkit_status.ps1')
        Invoke-RoomKitWindowsDelegate (Join-Path $Root 'tools/roomkit_status.ps1') @{DataRoot=$data}
        return
    }
    if($action -eq 'check') {
        if($layout -eq 'source') {
            Require-RoomKitFiles $Root @('tools/check_environment.ps1')
            $checkParams=@{};if($options.ContainsKey('--godot')){$checkParams.Godot=$options['--godot']}
            Invoke-RoomKitWindowsDelegate (Join-Path $Root 'tools/check_environment.ps1') $checkParams
            return
        }
        Invoke-RoomKitWindowsDelegate (Join-Path $Root 'RunFramework.ps1') @{Operation='verify'}
        return
    }
    $parameters=@{Instance=$name}
    $mapping=@{'--panel-port'='PanelPort';'--lobby-port'='LobbyPort';'--control-port'='ControlPort';'--udp-range'='UdpRange';'--bind'='Bind';'--godot'='Godot';'--no-browser'='NoBrowser'}
    foreach($key in $mapping.Keys){if($options.ContainsKey($key)){$parameters[$mapping[$key]]=$options[$key]}}
    $mode=if($action -eq 'start'){'panel'}else{'stop'}
    if($layout -eq 'source') {
        Require-RoomKitFiles $Root @('tools/run_framework.ps1')
        $parameters.Mode=$mode; Invoke-RoomKitWindowsDelegate (Join-Path $Root 'tools/run_framework.ps1') $parameters
    } else { $parameters.Operation=$mode; Invoke-RoomKitWindowsDelegate (Join-Path $Root 'RunFramework.ps1') $parameters }
}
