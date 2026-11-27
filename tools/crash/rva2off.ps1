# RVA to file offset - moved from _migration\archive\mwx-debug\rva2off.ps1 on 27 Nov 2026.
param([string]$Path, [uint32]$Rva)
$fs = [IO.File]::OpenRead($Path)
$br = New-Object IO.BinaryReader($fs)
$fs.Position = 0x3C
$pe = $br.ReadInt32()
$fs.Position = $pe + 6
$nsec = $br.ReadUInt16()
$fs.Position = $pe + 20
$optSize = $br.ReadUInt16()
$secStart = $pe + 24 + $optSize
$result = $null
for ($i = 0; $i -lt $nsec; $i++) {
    $fs.Position = $secStart + $i * 40
    $nameBytes = $br.ReadBytes(8)
    $name = [Text.Encoding]::ASCII.GetString($nameBytes).Trim([char]0)
    $vsize = $br.ReadUInt32()
    $vaddr = $br.ReadUInt32()
    $rsize = $br.ReadUInt32()
    $roff = $br.ReadUInt32()
    $span = [Math]::Max($vsize, $rsize)
    if ($Rva -ge $vaddr -and $Rva -lt ($vaddr + $span)) {
        $result = [pscustomobject]@{ section = $name; rva = ('0x{0:X}' -f $vaddr); file_offset = ($roff + $Rva - $vaddr) }
    }
}
$fs.Close()
$result
