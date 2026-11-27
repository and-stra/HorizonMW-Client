param(
    [Parameter(Mandatory=$true)][string]$Map,
    [Parameter(Mandatory=$true)][int]$Port,
    [string]$RepoRoot = "",
    [string]$RefsRoot = "",
    [string]$OutDir = "",
    [int]$MinProps = 20,
    [int]$MaxProps = 40,
    [switch]$Fallback
)

# MWX Prop Hunt prop list generator.
#
#   powershell -File tools\ph-props\generate.ps1 -Map mp_rust -Port 27120
#
# Input : refs\maps\<map>\xmodels.txt (see refs\maps\_status.md)
#         a running mwx dedicated server on <map> with its debug port at -Port
# Output: data\mwx\ph_props\ph_props_<map>.csv
#
# The server has to run the map first: XModel bounds are read from the loaded zone through
# the debug method model_bounds (added for this, see docs/guides/mcp.md). The format is the one
# maps\mp\gametypes\_hodgepodge_ph.gsc reads:
#   model,size class,packid[,offset xyz][,angles xyz]
# only the first three columns are written (the optional offset/angle columns stay undefined,
# which is what the MWR tables do for plain props).
#
# -Fallback writes the universal prop list for maps without an xmodels dump
# (invasion, hardhat, paris, skidrow): the models MWR's Mad Props mode loads on every map.

$ErrorActionPreference = "Stop"

if ($RepoRoot -eq "") {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
if ($RefsRoot -eq "") {
    $RefsRoot = (Resolve-Path (Join-Path $RepoRoot "..\refs\maps")).Path
}
if ($OutDir -eq "") {
    $OutDir = Join-Path $RepoRoot "data\mwx\ph_props"
}
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Invoke-Rpc([int]$RpcPort, [string]$Method, $Params) {
    $body = @{ method = $Method; params = $Params } | ConvertTo-Json -Depth 6 -Compress
    return Invoke-RestMethod -Uri "http://127.0.0.1:$RpcPort/rpc" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 120
}

function Get-Bounds([string[]]$Models) {
    $result = @{}
    $batch = 250
    for ($i = 0; $i -lt $Models.Count; $i += $batch) {
        $slice = $Models[$i..([Math]::Min($i + $batch - 1, $Models.Count - 1))]
        $response = Invoke-Rpc $Port "model_bounds" @{ models = $slice }
        if ($response.error) { throw "model_bounds: $($response.error)" }
        foreach ($entry in $response.result.models) {
            $result[$entry.model] = $entry
        }
        Write-Host ("  bounds {0}/{1}" -f ([Math]::Min($i + $batch, $Models.Count)), $Models.Count)
    }
    return $result
}

# Names that are never props: weapons and their parts, characters, vehicles, effects,
# decals, foliage, sky, UI and tiny clutter.
$bad = 'wpn_|weapon|viewmodel|viewhands|attach_|reticle|killicon|hud|ui_|icon|tag_|ncs_|netconststrings|' +
       'character|soldier|body_|head_|zombie|dog_|agent|' +
       'vehicle|veh_|heli|plane|tank|turret|wreck|destroyed|_dmg|_dam\b|_damaged|broken|_broken|debris|ruin|' +
       'fx\b|_fx|vfx|particle|smoke|blood|splash|impact|tracer|muzzle|flash|glow|light|sky|cloud|sun_|moon|lensflare|flare|' +
       'decal|foliage|tree|bush|grass|shrub|plant|_leaf|ivy|vine|' +
       'objective|bomb_|flag_|camera|_cam\b|_vm\b|_npc\b|_mp_camo|_cinematic|_lod[0-9]|_shadow|_collision|_editor'

# Props that read as "a thing you can hide as" win over map trim (pipes, doors) when a map
# has enough candidates; the rest still fill the list to 20 on sparse maps.
$liked = 'barrel|crate|box|case|chair|canister|laptop|tire|pump|boulder|rock|trashbag|cardboard|banana|' +
         'computer|tv|console|fan|basket|bucket|tool|generator|table|sofa|couch|bench|cabinet|shelf|locker|' +
         'mattress|monitor|phone|radio|backpack|bag|cylinder|bottle|can_|jerry|ammo|sandbag'
$trim = 'pipe|door|gate|fence|railing|stairs|window|antenna|cable|wire|sign|board|panel|plate|beam|bar_|pole|post_|' +
        'column|brick|wall_|ceiling|floor|roof|vent|duct|shelf_|frame_'

function Get-Candidates([string]$MapName) {
    $file = Join-Path (Join-Path $RefsRoot $MapName) "xmodels.txt"
    if (!(Test-Path $file)) { return $null }

    $names = Get-Content -Path $file -Encoding UTF8 | ForEach-Object {
        $_.Trim().TrimStart(',').Trim().Replace('/', '\')
    }
    $names = $names | Where-Object {
        $_ -ne "" -and
        $_ -notmatch $bad -and
        $_ -notmatch '^netconststrings' -and
        $_ -notmatch '^(wpn|s1|iw|h2|h1)_' -and
        $_ -match '^[a-z0-9_\\\.]+$'
    } | Sort-Object -Unique

    return $names
}

function Get-SizeClass([double]$maxDim) {
    if ($maxDim -le 24) { return "xsmall" }
    if ($maxDim -le 48) { return "small" }
    if ($maxDim -le 90) { return "medium" }
    return "large"
}

function Select-Props($Candidates, $Bounds, [string]$MapName) {
    $available = @()
    foreach ($name in $Candidates) {
        $entry = $Bounds[$name]
        if ($null -eq $entry -or -not $entry.loaded) { continue }

        $dx = [double]$entry.maxs[0] - [double]$entry.mins[0]
        $dy = [double]$entry.maxs[1] - [double]$entry.mins[1]
        $dz = [double]$entry.maxs[2] - [double]$entry.mins[2]
        $maxDim = [Math]::Max($dx, [Math]::Max($dy, $dz))
        $minDim = [Math]::Min($dx, [Math]::Min($dy, $dz))
        $height = $dz

        # too small / too big / too flat (a slab) / one-dimensional
        if ($maxDim -lt 10 -or $maxDim -gt 180) { continue }
        if ($height -lt 8 -or $height -gt 200) { continue }
        if ($minDim -lt 3) { continue }
        # a prop has to be visible from the side as well; a 180 x 4 x 20 board is not
        if ($dx -gt 0 -and $dy -gt 0 -and ($dx / $dy) -gt 12) { continue }
        if ($dy -gt 0 -and $dx -gt 0 -and ($dy / $dx) -gt 12) { continue }

        $available += [pscustomobject]@{
            model = $name
            size = (Get-SizeClass $maxDim)
            maxDim = [Math]::Round($maxDim, 1)
            height = [Math]::Round($height, 1)
            radius = $entry.radius
            pref = if ($name -match $liked) { 2 } elseif ($name -match $trim) { 0 } else { 1 }
        }
    }

    if ($available.Count -eq 0) { return @() }

    # deterministic order, seeded by the map (same output for every run)
    $seed = 0
    foreach ($ch in $MapName.ToCharArray()) { $seed = ($seed * 31 + [int]$ch) % 2147483647 }
    $random = [Random]::new($seed)
    $shuffled = $available | Sort-Object @{ Expression = { -$_.pref } }, @{ Expression = { $random.Next() } }

    # up to 10 per size class, 40 overall
    $picked = @()
    $perClass = [Math]::Ceiling($MaxProps / 4)
    foreach ($class in @("xsmall", "small", "medium", "large")) {
        $ofClass = $shuffled | Where-Object { $_.size -eq $class } | Select-Object -First $perClass
        $picked += $ofClass
    }

    # a map with a thin size class still gets its 20 props from the other classes
    if ($picked.Count -lt $MinProps) {
        $have = @{}
        foreach ($p in $picked) { $have[$p.model] = $true }
        foreach ($entry in $shuffled) {
            if ($picked.Count -ge $MinProps) { break }
            if (-not $have.ContainsKey($entry.model)) {
                $picked += $entry
                $have[$entry.model] = $true
            }
        }
    }

    if ($picked.Count -gt $MaxProps) {
        $picked = $picked | Select-Object -First $MaxProps
    }

    return $picked
}

function Write-Table([string]$MapName, $Props) {
    $path = Join-Path $OutDir ("ph_props_{0}.csv" -f $MapName)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($prop in $Props) {
        $lines.Add(("{0},{1},0" -f $prop.model, $prop.size))
    }
    [IO.File]::WriteAllText($path, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host ("wrote {0} ({1} props)" -f $path, $Props.Count)
}

$fallbackModels = @(
    "com_cardboardbox06", "me_banana_box1", "fs_h1_mwr_com_tv1_cinematic", "com_computer_case",
    "com_trashbag2_white", "com_trashbag", "com_propane_tank"
)

if ($Fallback) {
    Write-Host "fallback list for $Map"
    $bounds = Get-Bounds $fallbackModels
    $props = @()
    foreach ($name in $fallbackModels) {
        $entry = $bounds[$name]
        if ($null -eq $entry -or -not $entry.loaded) {
            Write-Warning "  $name is not loaded on this map, skipped"
            continue
        }
        $dx = [double]$entry.maxs[0] - [double]$entry.mins[0]
        $dy = [double]$entry.maxs[1] - [double]$entry.mins[1]
        $dz = [double]$entry.maxs[2] - [double]$entry.mins[2]
        $maxDim = [Math]::Max($dx, [Math]::Max($dy, $dz))
        $props += [pscustomobject]@{ model = $name; size = (Get-SizeClass $maxDim) }
    }
    if ($props.Count -eq 0) { throw "no fallback prop is loaded on $Map" }
    Write-Table $Map $props
    exit 0
}

$candidates = Get-Candidates $Map
if ($null -eq $candidates) {
    throw "no xmodels.txt for $Map (refs\maps\$Map). Use -Fallback for a map without a dump."
}
Write-Host ("{0}: {1} name candidates" -f $Map, $candidates.Count)

$bounds = Get-Bounds $candidates
$loaded = ($bounds.Values | Where-Object { $_.loaded }).Count
Write-Host ("{0}: {1} xmodels loaded on the map" -f $Map, $loaded)

$props = Select-Props $candidates $bounds $Map
if ($props.Count -lt $MinProps) {
    throw ("only {0} usable props on {1} (min {2}); use -Fallback" -f $props.Count, $Map, $MinProps)
}
Write-Table $Map $props
