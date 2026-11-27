# read game memory - moved from _migration\archive\mwx-debug\readmem.ps1 on 27 Nov 2026.
param([int]$ProcessId, [string]$Address, [int]$Length, [string]$OutFile)
$src = @"
using System;
using System.Runtime.InteropServices;
public static class MemReader {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr baseAddr, byte[] buffer, IntPtr size, out IntPtr bytesRead);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
}
"@
Add-Type -TypeDefinition $src
$h = [MemReader]::OpenProcess(0x0010, $false, $ProcessId)
if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$addr = [Convert]::ToInt64($Address.Replace('0x',''), 16)
$buf = New-Object byte[] $Length
$read = [IntPtr]::Zero
$ok = [MemReader]::ReadProcessMemory($h, [IntPtr]$addr, $buf, [IntPtr]$Length, [ref]$read)
[MemReader]::CloseHandle($h) | Out-Null
if (-not $ok) { throw "ReadProcessMemory failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
[IO.File]::WriteAllBytes($OutFile, $buf)
"read $($read.ToInt64()) bytes to $OutFile"
