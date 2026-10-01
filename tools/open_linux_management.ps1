param(
    [string]$Server='192.168.10.105',
    [string]$User='zhao',
    [ValidateRange(1024,65535)][int]$PanelPort=28491,
    [switch]$NoBrowser,
    [ValidateRange(0,3600)][int]$HoldSeconds=0
)
# Only SSH is started here. The remote Operator is neither started nor stopped.
# The local port must equal the remote port: admin_http validates Host/Origin.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::Expect100Continue=$false
$ip=$null
if(-not [Net.IPAddress]::TryParse($Server,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $User -notmatch '^[a-z_][a-z0-9_-]{0,31}$'){throw 'Use an IPv4 server address and a valid SSH username.'}
$Server=$ip.ToString()
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$evidence=Join-Path $project ('logs/linux-management-'+[Guid]::NewGuid().ToString('N'))
$cursor=$evidence
while($cursor){
    $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
    if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refused linked log directory.'}
    $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
}
New-Item -ItemType Directory -Path $evidence | Out-Null
$url='http://127.0.0.1:'+$PanelPort+'/'
$tunnel=$null
$success=$false
$ready=$false
$browserOpened=$false
$cleanupError=''
# Close the anonymous job when this launcher exits, including a console close.
# Only the SSH process created below is assigned; existing listeners are untouched.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace RoomKit {
    public sealed class ManagementTunnelJob : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct Basic {
            public long ProcessTime, JobTime;
            public uint Flags;
            public UIntPtr Minimum, Maximum;
            public uint ActiveProcesses;
            public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct Io {
            public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
        }
        [StructLayout(LayoutKind.Sequential)] struct Extended {
            public Basic Basic;
            public Io Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, IntPtr value, uint length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
        IntPtr handle;
        public ManagementTunnelJob() {
            handle=CreateJobObject(IntPtr.Zero, null);
            if(handle==IntPtr.Zero) throw new Win32Exception();
            var info=new Extended(); info.Basic.Flags=0x2000;
            int size=Marshal.SizeOf(typeof(Extended));
            IntPtr memory=Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(info, memory, false);
                if(!SetInformationJobObject(handle, 9, memory, (uint)size)) throw new Win32Exception();
            } catch { Dispose(); throw; } finally { Marshal.FreeHGlobal(memory); }
        }
        public void Assign(IntPtr process) { if(!AssignProcessToJobObject(handle, process)) throw new Win32Exception(); }
        public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
    }
}
'@
$job=New-Object RoomKit.ManagementTunnelJob
try {
    $reservation=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$PanelPort)
    try{$reservation.Start()}catch{throw ('Local port '+$PanelPort+' is occupied. Use the existing SSH window or close it first; nothing was stopped.')}finally{$reservation.Stop()}
    $arguments=@('-N','-T','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=2','-L',('127.0.0.1:'+$PanelPort+':127.0.0.1:'+$PanelPort),($User+'@'+$Server))
    $tunnel=Start-Process -FilePath ssh.exe -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $evidence 'ssh.out') -RedirectStandardError (Join-Path $evidence 'ssh.err')
    $heldHandle=$tunnel.Handle
    $job.Assign($heldHandle)
    $ready=$false
    $end=[DateTime]::UtcNow.AddSeconds(20)
    do {
        if($tunnel.HasExited){throw ('SSH tunnel failed. See '+(Join-Path $evidence 'ssh.err')+'. No service was changed.')}
        try {
            $reply=Invoke-RestMethod -Uri ($url+'api') -Method Post -ContentType 'application/json' -Body '{"action":"setup.status","payload":{}}' -TimeoutSec 3
            if($reply.ok -eq $true -and $null -ne $reply.payload.initialized){$ready=$true;break}
        }catch{}
        Start-Sleep -Milliseconds 200
    }while([DateTime]::UtcNow -lt $end)
    if(-not $ready){throw 'Linux panel is not responding. Check its official start/status entry; no service was changed.'}
    $listeners=@(Get-NetTCPConnection -State Listen -LocalAddress 127.0.0.1 -LocalPort $PanelPort -ErrorAction Stop)
    if($listeners.Count -ne 1 -or $listeners[0].OwningProcess -ne $tunnel.Id){$ready=$false;throw 'The forwarded port is not owned by this SSH process; refused to open another listener.'}
    $page=Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5
    if($page.StatusCode -ne 200 -or $page.Content -notmatch 'RoomKit'){throw 'The forwarded address did not return the RoomKit page.'}
    Write-Output ('LINUX_MANAGEMENT_READY '+$url)
    Write-Output 'Keep this window open while using the panel. Closing it disconnects SSH only.'
    Write-Output 'The LAN test administrator is separate from your Windows administrator. See the private admin.json listed in docs/17.'
    if(-not $NoBrowser){Start-Process $url;$browserOpened=$true}
    if($HoldSeconds -gt 0){
        $end=[DateTime]::UtcNow.AddSeconds($HoldSeconds)
        while([DateTime]::UtcNow -lt $end){if($tunnel.HasExited){throw 'SSH tunnel disconnected.'};Start-Sleep -Milliseconds 200}
    }else{[void](Read-Host 'Press Enter to disconnect SSH (Linux server keeps running)')}
    $success=$true
}finally{
    try{
        if($null -ne $tunnel -and -not $tunnel.HasExited){$tunnel.Kill();if(-not $tunnel.WaitForExit(5000)){throw 'SSH cleanup exceeded 5 seconds.'}}
    }catch{$success=$false;$cleanupError=$_.Exception.GetType().Name}
    finally{
        $job.Dispose()
        if($null -ne $tunnel){$tunnel.Dispose()}
        [IO.File]::WriteAllText((Join-Path $evidence 'result.json'),(@{ready=$ready;success=$success;port=$PanelPort;server=$Server;browser_opened=$browserOpened;cleanup_error=$cleanupError}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        Write-Output ('LINUX_MANAGEMENT_CLOSED evidence='+$evidence)
    }
}
if(-not $success){exit 1}
