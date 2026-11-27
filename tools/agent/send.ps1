# send a prompt to an agent session - moved from _migration\archive\mwx-debug\autonomous\send.ps1 on 27 Nov 2026.
param(
  [string]$Port = "27099",
  [Parameter(Mandatory=$true)][string]$Method,
  # semicolon separated key=value pairs; numeric values become numbers, true/false booleans,
  # a value starting with { or [ is parsed as JSON
  [string]$Pairs = "",
  # Lua/GSC code from a file (for lua_eval / gsc_eval, avoids all quoting problems)
  [string]$CodeFile = "",
  [int]$TimeoutSec = 180
)

$params = @{}
if ($Pairs -ne "") {
  foreach ($pair in $Pairs.Split(';')) {
    if ($pair -eq "") { continue }
    $index = $pair.IndexOf('=')
    $key = $pair.Substring(0, $index)
    $value = $pair.Substring($index + 1)

    if ($value -match '^-?\d+$') { $params[$key] = [int]$value }
    elseif ($value -match '^-?\d+\.\d+$') { $params[$key] = [double]$value }
    elseif ($value -eq 'true') { $params[$key] = $true }
    elseif ($value -eq 'false') { $params[$key] = $false }
    elseif ($value.StartsWith('{') -or $value.StartsWith('[')) { $params[$key] = ConvertFrom-Json $value }
    else { $params[$key] = $value }
  }
}

$body = @{ method = $Method; params = $params } | ConvertTo-Json -Depth 20 -Compress
if ($CodeFile -ne "") {
    $code = Get-Content -Raw $CodeFile
    $body = @{ method = $Method; params = @{ code = $code } } | ConvertTo-Json -Depth 20 -Compress
}
try {
  $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec
  $response | ConvertTo-Json -Depth 20
} catch {
  "ERROR: $($_.Exception.Message)"
}
