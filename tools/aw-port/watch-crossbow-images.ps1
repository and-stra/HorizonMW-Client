# watch the crossbow image files - moved from _migration\archive\mwx-debug\aw-weapons\W1.2\watch-crossbow-images.ps1 on 27 Nov 2026.
$names = @(
    'crossbow_scope_base_col','crossbow_scope_base_nml',
    '~crossbow_scope_base_spc-rgb&~d8544476','~crossbow_scope_base_occ-l',
    'crossbow_glass_col','crossbow_glass_nml',
    '~crossbow_glass_spc-rgb&cross~a7515f30','crossbow_target_ems',
    'wep_shared_gray_swatch_col','weapon_red_cross_background',
    'weapon_red_cross_background_s1','emblem_temp_col'
)
$root = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump\common_mp'
$deadline = (Get-Date).AddMinutes(40)
while ((Get-Date) -lt $deadline) {
    $missing = @()
    foreach ($n in $names) {
        $a = Join-Path $root ("images\$n.h1Image")
        $b = Join-Path $root ("streamed_images\$n.h1Image")
        if (-not (Test-Path -LiteralPath $a) -and -not (Test-Path -LiteralPath $b)) { $missing += $n }
    }
    $free = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    if ($missing.Count -eq 0) {
        "all 12 images present (free $free GB) - stopping zonetool"
        Get-Process zonetool,s1_mp64_ship -ErrorAction SilentlyContinue | Stop-Process -Force
        break
    }
    "missing=$($missing.Count) free=$free GB: $($missing -join ', ')"
    Start-Sleep -Seconds 10
}
