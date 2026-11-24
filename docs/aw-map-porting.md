# Porting an Advanced Warfare map to MWR (worked example: `mp_greenband`)

Reproducible record of the `mp_greenband` port, done on 2026-11-22 with
[x64-zt](https://github.com/Joelrau/x64-zt) (`Release.zonetool.zip`, tag `latest`, build 0.0.0.560)
and the guide at <https://docs.auroramod.dev/map-porting-s1>.

Paths used here:

- `AW`   = `C:\Games\cod-hwm\Call of Duty Advanced Warfare`
- `GAME` = `C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered`
- `REFS` = `C:\Games\cod-hwm\refs`

Expect **~20 GB of free disk** for the dump, the `zonetool_paths` dump, the zone folder copy and two builds.

## 0. Tools (one binary, two roles)

`Release.zonetool.zip` contains a single `zonetool.exe`. It picks the game from the executable in
the current directory:

| Directory | Game it loads | Role |
|---|---|---|
| `AW` (has `s1_mp64_ship.exe`) | S1 (Advanced Warfare) | dumping / `generatecsv` |
| `GAME` (has `h1_mp64_ship.exe`) | H1 (MWR) | `buildzone` |

```powershell
# download + extract (do not overwrite anything)
New-Item -ItemType Directory -Force "$REFS\tools\x64-zt"
Invoke-WebRequest "https://github.com/Joelrau/x64-zt/releases/download/latest/Release.zonetool.zip" `
  -OutFile "$REFS\tools\x64-zt\Release.zonetool.zip"
Expand-Archive "$REFS\tools\x64-zt\Release.zonetool.zip" "$REFS\tools\x64-zt\release"

# S1 role: a NEW file in AW
Copy-Item "$REFS\tools\x64-zt\release\zonetool.exe" "$AW\zonetool.exe"

# H1 role: a NEW file in GAME (HMW's own zonetool.exe 0.0.0.491 stays untouched)
Copy-Item "$REFS\tools\x64-zt\release\zonetool.exe" "$GAME\x64zt.exe"
```

## 1. Dumping is interactive (the part that costs time)

x64-zt is not a normal CLI for `dumpmap`/`generatecsv`: after loading the game it reads commands
from **stdin** with `std::getline` (`src/zonetool/component/s1/console.cpp`). Two consequences:

1. Commands that arrive before the game finishes loading are **read and dropped** (`ingame` is still
   false).
2. Without `-unbuffered-io`, redirected stdout is block-buffered, so logs look empty.

Drive it from PowerShell with a real stdin pipe (this is the exact method used):

```powershell
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$AW\zonetool.exe"; $psi.Arguments = '-unbuffered-io'
$psi.WorkingDirectory = $AW; $psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEndAsync()   # must keep draining stdout
Start-Sleep -Seconds 75                     # wait for "initialization complete"
$p.StandardInput.WriteLine('dumpmap h1 mp_greenband')   # target game + map
```

Then wait for `AW\dump\mp_greenband` to exist and stop growing (the driver used "no change for
150 s"), kill the process, and save `$out` to a log.

- **`dumpmap h1 mp_greenband`**: 43 477 files, 2.68 GB, ~25–35 min.
- Non-fatal: 72 × `Unable to map code constant 84 for technique 'postfx_*'` (converter limitation).
- `dumpmap` already dumps the dependencies (common zones included unless you pass `_ true`).

The reusable drivers are in [`aw-port-scripts/`](aw-port-scripts/):
`aw-dumpmap.ps1` (dumpmap + stable-folder wait), `aw-dumpzone.ps1` (dumpzone), `h1-command.ps1`
(generatecsv in GAME), `server-test.ps1` and `client-test.ps1`.

## 2. Missing images / materials (`zonetool_paths`)

```powershell
# same driver, command: dumpzone h1 common_mp
# output: AW\dump\common_mp  (74 372 files, 9.33 GB, ~20 min)
Move-Item "$AW\dump\common_mp" "$GAME\zonetool_paths\common_mp"
```

`GAME\zonetool_paths\` is **build-time only** (x64-zt scans every folder inside it for assets); it is
not shipped with the map. This cut the build warnings from 112 to 85. The remaining ones are AW
*patch*-level assets (`patch_common_mp`); dump it the same way if you want zero red effects.

## 3. Move the dump and generate the CSV

```powershell
robocopy "$AW\dump\mp_greenband" "$GAME\zonetool\mp_greenband" /E
```

Then run `generatecsv mp_greenband` with the same stdin driver, in `GAME`
(`h1-command.ps1` in `mwx-debug\aw-port`). It writes `GAME\zone_source\mp_greenband.csv`
(202 lines for greenband).

Do **not** use `x64zt.exe -dumpcsv mp_greenband`: that command dumps a CSV from a *loaded zone* and
fails with `Zone "mp_greenband" could not be found!` when the zone only exists as a folder.

The CSV ends with the script block (generatecsv adds it automatically):

```
// gsc
rawfile,maps/mp/mp_greenband.gsc
rawfile,maps/mp/mp_greenband_fx.gsc
rawfile,maps/createfx/mp_greenband_fx.gsc
rawfile,maps/mp/mp_greenband_precache.gsc
rawfile,maps/createart/mp_greenband_art.gsc
rawfile,maps/createart/mp_greenband_fog.gsc
rawfile,maps/createart/mp_greenband_fog_hdr.gsc
```

`rawfile` here means "GSC source shipped in the zone"; the game compiles it on demand.

## 4. Replace the AW map script

Keep the dumped originals for reference (e.g. `mwx-debug\aw-port\gsc-original`). The AW `main()`
calls AW-only script (`mp_greenband_precache`, `createart`, drones, `_water`, OSP overrides) and must
not be used as is.

Write this **minimal H1 script** to `GAME\zonetool\mp_greenband\maps\mp\mp_greenband.gsc`
(the rawfile entry above already points at it):

```gsc
main()
{
	maps\createfx\mp_greenband_fx::main();
	maps\mp\mp_greenband_fx::main();
	maps\mp\_load::main();
	maps\mp\_compass::setupminimap("compass_map_mp_greenband");
}
```

Order matters: map FX first, then `_load::main()` (spawn logic, gametype start), then the compass.
`mp_greenband_fx` (the `loadfx` table) and `createfx\mp_greenband_fx` (generatedCreateFX loop sounds)
are plain GSC and work in H1. The AW `_precache`/`createart` scripts are referenced by the CSV as
rawfiles but not called; they never run.

## 5. Build

```powershell
cd $GAME
.\x64zt.exe -buildzone mp_greenband          # CLI works for building
```

Result for greenband: **0 errors**, 85 warnings, ~60 s compilation (plus ~10 min parsing of 21 800
assets):

```
GAME\zone\mp_greenband.ff    274 404 824 bytes
GAME\zone\mp_greenband.pak   614 262 788 bytes
```

No `_load.ff` is produced by this flow (HMW's ported usermaps have one; this build does not).

## 6. Deploy as usermap

HMW usermap layout (see `GAME\hmw-usermaps\mp_rust`): one folder per map with
`<map>.ff`, `<map>.pak`, `<map>_load.ff`.

```powershell
New-Item -ItemType Directory -Force "$GAME\hmw-usermaps\mp_greenband"
Copy-Item "$GAME\zone\mp_greenband.ff"  "$GAME\hmw-usermaps\mp_greenband\"
Copy-Item "$GAME\zone\mp_greenband.pak" "$GAME\hmw-usermaps\mp_greenband\"
# no _load.ff: the build did not produce one
```

Test:

```powershell
# dedicated server (debug RPC on 27098, game port 27016)
Start-Process "$GAME\mwx.exe" -WorkingDirectory $GAME -ArgumentList `
  '-dedicated','-memoryfix','+set','net_port','27016','+set','mwx_gsc_print','1'
# then, through http://127.0.0.1:27098/rpc
#   {"method":"command","params":{"command":"set g_gametype war"}}
#   {"method":"command","params":{"command":"map mp_greenband"}}
#   {"method":"command","params":{"command":"spawnBot 4"}}
```

Observed: `Starting map: mp_greenband` → `Loading fastfile mp_greenband` →
`[load_timing] 49709 ms start mp_greenband` → status `map=mp_greenband`, 4 bots join.

## Known issue found with this port (2026-11-22)

The dedicated server loads the map (`map mp_greenband`, status `map=mp_greenband`) and `spawnBot 4`
joins bots, but `mwx.exe` then aborts (fail-fast). Windows Application log:

```
mwx.exe  0xC0000409 (BEX64)  fault offset 0x27b52d
```

Symbolizing the build's own PDB puts `0x27b52d` inside `abort()` (`__acrt_call_reportfault`, i.e.
`FAST_FAIL_FATAL_APP_EXIT`) — an unhandled C++ exception / `std::terminate`, not an access
violation. That is why no file appears in `GAME\minidumps\` (the HMW handler only dumps AVs); WER
keeps only a report.

Seen 4/4 on `-dedicated` (during the map load or within ~2 min of gameplay). The same map as a
**listen server** (client, `map mp_greenband`, `spawnBot 2`) ran 150 s with the player and both bots
alive and scoring (bot score 325), so it is not a bad asset in the zone. To get the throw site, run
the server under cdb with a fail-fast breakpoint:

```
sxe -c "kv; ~*k; .dump /ma C:\temp\abort.dmp; q" 0xC0000409
g
```

then trigger `map mp_greenband` through the debug server. The dump's call stack names the throwing
component.

Client check: `docs/aw-port-scripts/client-test.ps1` (client + `map mp_greenband` + class select).
Screenshots from this port are in `mwx-debug\aw-port\` (`lighting.png`, `missing-textures.png`,
`fullbright-models.png`). Visible defect: the glass/water door panels render with a noisy
placeholder (the 78 remaining missing images include `glass_*`, `water_*`, and `smk_*`; dumping AW
`patch_common_mp` into `zonetool_paths` is the next fix).

## Pitfalls / known issues

- **Interactive console**: commands sent before init are silently dropped; always wait ~75 s and keep
  stdin open. A `cmd` pipe with `ping -n 32` works too but is racy.
- **Redirected stdout of the dedicated server** stops at ~10.6 KB (buffered). Use the debug server
  `console` RPC (`http://127.0.0.1:27098/rpc`) or `hmw-mod\logs\games_mp.log` instead of the
  redirected file.
- **`generatecsv` ≠ `-dumpcsv`** (see step 3).
- **`common_mp` is not enough for zero warnings**: AW patch-level effects live in `patch_common_mp`.
- **First build vs. cached build**: the zone folder is 2.7 GB / 43 k files; parsing dominates the
  build time and is I/O-bound.
- **Do not modify game files**: all new files go to new folders (`zonetool\`, `zonetool_paths\`,
  `hmw-usermaps\`, `zone_source\`) plus `AW\zonetool.exe` and `GAME\x64zt.exe`.
