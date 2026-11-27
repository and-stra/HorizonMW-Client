# debug RPC helper - moved from _migration\archive\mwx-debug\autonomous\rpc.ps1 on 27 Nov 2026.
param(
  [string]$Port = "27099",
  [Parameter(Mandatory=$true)][string]$Method,
  [string]$Params = "{}",
  [string]$ParamsFile = "",
  [string]$Code = "",
  [int]$TimeoutSec = 120
)

if ($ParamsFile -ne "") {
  $paramsObject = Get-Content -Raw $ParamsFile | ConvertFrom-Json
} elseif ($Code -ne "") {
  $paramsObject = [pscustomobject]@{ code = $Code }
} else {
  $paramsObject = ConvertFrom-Json $Params
}

$body = @{ method = $Method; params = $paramsObject } | ConvertTo-Json -Depth 20 -Compress
try {
  $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec
  $response | ConvertTo-Json -Depth 20
} catch {
  "ERROR: $($_.Exception.Message)"
}
