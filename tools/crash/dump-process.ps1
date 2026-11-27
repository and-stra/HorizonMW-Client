# process/minidump inspector - moved from _migration\archive\mwx-debug\dump-process.ps1 on 27 Nov 2026.
param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [string]$Out = ""
)
$ErrorActionPreference = "Stop"
if (-not $Out) {
    $Out = Join-Path "C:\Games\cod-hwm\_migration\archive\mwx-debug\zone-stall" ("mwx-stall-$ProcessId-{0}.dmp" -f (Get-Date -Format "HHmmss"))
}
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null

$source = @"
using System;
using System.Runtime.InteropServices;
public static class MiniDump {
    [DllImport("dbghelp.dll", SetLastError = true)]
    public static extern bool MiniDumpWriteDump(IntPtr hProcess, uint processId, IntPtr hFile,
        uint dumpType, IntPtr exceptionParam, IntPtr userStreamParam, IntPtr callbackParam);
}
"@
Add-Type -TypeDefinition $source
$p = Get-Process -Id $ProcessId
$fs = [IO.File]::Create($Out)
try {
    $ok = [MiniDump]::MiniDumpWriteDump($p.Handle, [uint32]$ProcessId, $fs.SafeFileHandle.DangerousGetHandle(),
        0x2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero) # MiniDumpWithFullMemory
    if (-not $ok) { throw ("MiniDumpWriteDump failed: {0}" -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
} finally { $fs.Dispose() }
Write-Host ("wrote {0} ({1:N1} MB)" -f $Out, ((Get-Item $Out).Length / 1MB))
