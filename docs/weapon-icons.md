# Weapon icons (MWR style) — tool and status

Goal: one command that turns a ported weapon into the four icons the game uses (CAC list, big CAC
header, kill feed, HUD), in the MWR style, with unique names, converted to the game's image format
and wired into the zone + statstable.

## Current state (27 Nov 2026)

`tools/weapon-icons/` renders **the correct weapon model** from `hmw-workbench` (MCP, orbit, world
model) and writes `out/<ref>-{list,header,hud}.png`. Working: the MCP driver
(`mcp_client.py`), the batch renderer (`render_icons.py`), the camera style config
(`style.json`, defaults yaw 90 / pitch 10 / fov 32 / dist 70, 2x sizes for downscaling).

Not yet usable as game icons, three blockers:

1. **Background**: the workbench's orbit view always draws its grid + axes; the `screenshot` MCP
   tool has no flag to hide them (`showGrid_` is set from the view mode in `src/app/commands.cpp`).
   The icon needs a plain (ideally transparent) background. Next: add a `grid`/`background`
   argument to the workbench MCP screenshot (a workbench milestone, its repo), then re-render.
2. **Textures**: the rendered gun is untextured/black - the workbench's asset roots do not include
   our AW zone source, so it cannot find `m/mtl_m1garand_*` + the AW images. Next: add
   `GAME\zonetool\hmw_aw_weapons` to its asset roots (workbench side) or render from a dump that
   already contains them.
3. **Format**: the game's images are `.h1Image` + `<name>_streamN.pixels`, and zonetool only
   *reads* that format (`zonetool/h1/assets/gfximage.cpp`, `utils/iwi/iwi.cpp`); the workbench has
   no writer either. Next: implement PNG → IWI (BC1/BC3 via DirectXTex/texconv, then the IWI
   header + mip payloads, streamed split like the extracted assets), or add a write path to
   zonetool. Until then no icon can be added to a zone.

## Style (to calibrate once 1-2 are fixed)

The MWR CAC list cell is a wide, slightly high 3/4 side view of the weapon, muzzle to the left,
dark translucent background, roughly 2:1, the weapon filling ~90% of the width with a small
margin, lighting from the upper left. `style.json` holds `yaw/pitch/fov/dist` and the output sizes;
the renderer is resolution-independent, so the same camera gives the list (512x256), header
(512x256) and HUD/kill feed (256x128) images.

## Run

```
py -3 tools/weapon-icons/render_icons.py --refs iw5_exocrossbow,iw5_dlcgun23,iw5_dlcgun18,iw5_combatknife
```

The workbench writes into its own `review/icons/` (it only accepts paths inside its repo); the
renderer copies the PNGs into `out/`. It needs `hmw-workbench.exe -mcp`
(`C:\Games\cod-hwm\hmw-workbench\build\bin\Release\hmw-workbench.exe`).

## When the blockers are gone

1. render → mask/crop to the style bounds, alpha background;
2. convert to `.h1Image` (+ streams) with names that cannot collide (`wpn_<ref>_icon_cac`, ...);
3. copy into `GAME\zonetool\hmw_aw_weapons\images`, add to the zone CSV, rebuild, zone-check;
4. point the statstable `image` column and the weapon def's `hudIcon`/`killIcon`/`dpadIcon` at the
   new names;
5. re-render the contact sheet (our icons next to the MWR ones) and take the CAC list/header,
   kill-feed and HUD screenshots.
