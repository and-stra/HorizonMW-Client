# dump the exception context - moved from _migration\archive\mwx-debug\dumpctx.ps1 on 27 Nov 2026.
param([string]$Path)
$fs = [IO.File]::OpenRead($Path)
$br = New-Object IO.BinaryReader($fs)
$sig = $br.ReadUInt32()
$ver = $br.ReadUInt32()
$nstreams = $br.ReadUInt32()
$dirRva = $br.ReadUInt32()
$fs.Position = $dirRva
$excRva = 0
for ($i = 0; $i -lt $nstreams; $i++) {
    $type = $br.ReadUInt32()
    $size = $br.ReadUInt32()
    $rva = $br.ReadUInt32()
    if ($type -eq 6) { $excRva = $rva }
}
if ($excRva -eq 0) { throw "no exception stream" }
$fs.Position = $excRva + 8
$code = $br.ReadUInt32()
$flags = $br.ReadUInt32()
$rec = $br.ReadUInt64()
$addr = $br.ReadUInt64()
$nparams = $br.ReadUInt32()
$fs.Position = $excRva + 8 + 4 + 4 + 8 + 8 + 4 + 4
$p = @()
for ($i = 0; $i -lt 15; $i++) { $p += $br.ReadUInt64() }
$ctxSize = $br.ReadUInt32()
$ctxRva = $br.ReadUInt32()
$fs.Position = $ctxRva
$ctx = $br.ReadBytes([Math]::Min($ctxSize, 0x4D0))
$fs.Close()
function U64($o) { [BitConverter]::ToUInt64($ctx, $o) }
"ExceptionCode=0x{0:X8} ExceptionAddress=0x{1:X} NumberParameters={2}" -f $code, $addr, $nparams
$params = @(); for ($i = 0; $i -lt [Math]::Min(4, $nparams); $i++) { $params += ('0x{0:X}' -f $p[$i]) }
"Parameters: $($params -join ', ')"
foreach ($r in @(
    @('Rax',0x78), @('Rcx',0x80), @('Rdx',0x88), @('Rbx',0x90), @('Rsp',0x98), @('Rbp',0xA0),
    @('Rsi',0xA8), @('Rdi',0xB0), @('R8',0xB8), @('R9',0xC0), @('R10',0xC8), @('R11',0xD0),
    @('R12',0xD8), @('R13',0xE0), @('R14',0xE8), @('R15',0xF0), @('Rip',0xF8))) {
    "{0}=0x{1:X}" -f $r[0], (U64 $r[1])
}
