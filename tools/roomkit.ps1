# Deliberately no parameter binder: reject duplicate/unknown options ourselves.
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'roomkit_entry.ps1')
    $platform=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){'Windows'}elseif($PSVersionTable.Platform -eq 'Unix' -and $IsLinux){'Linux'}else{'Unsupported'}
    Invoke-RoomKit -Root ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) -Platform $platform -Arguments @($args)
} catch {
    [Console]::Error.WriteLine('ROOMKIT_FAILED '+$_.Exception.Message)
    exit 2
}
