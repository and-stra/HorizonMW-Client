# Plan: analyse the closed-source hmw-mod.exe

Goal: find out what the current official client (hmw-mod.exe v1.6.7, Oct 2026) does that our client
(based on the last open-source HMW code, Oct 2024) does not, and re-implement what we want in our own
code. We do not copy their code, and nothing from the binary goes into the repo.

## Findings so far

- Not packed or virtualized: normal MSVC sections, code entropy ~6.6, no VMProtect/Themida markers.
  Most strings are plain (`scr_`, `HorizonMW`, `getInfo`, `infoResponse`); a few are built at runtime
  (Drop Zone / gametype registration not found as plain text).
- Resources: splash (768x480) and banner (610x60) are identical to the ones in our repo; HMW logo PNG.
- It redirects the loading icon to the material `hmw_loading_animation` (we do this too since 8075d016).
- Drop Zone = `maps/mp/gametypes/dz.gsc` (GSC source rawfile in `hmw_files.ff`, compiled by gsc-tool)
  + `ui_scripts/mp/hud/dz_hud.lua`; its whitelist/table registration must be in the exe. Copy of the
  script: `C:\Games\cod-hwm\refs\key\hmw_dz.gsc`.

## Steps

1. **Export** (opencode): Java 21 + Ghidra 11.2.1 (Jython), headless analysis of a copy of the exe in
   `C:\Games\cod-hwm\refs\hmw_bin\`, script `refs\tools\ghidra_scripts\ExportDecomp.py` ->
   `refs\hmw_decomp\strings.tsv` (string, address, functions using it) and `decomp_*.c`.
2. **Map against our source** (Claude): identify components by their strings/log messages, list the
   functions/features that do not exist in our code.
3. **Targeted questions**, in this order:
   a) how `dz` is registered (gametype whitelist, gametypes table, menu) -> enable Drop Zone in MWX
      together with Infected (gamemodes phase 4);
   b) new or changed components vs. the open-source version;
   c) crash fixes (quit crash in Com_Shutdown, emblem Create2DTexture failure);
   d) anything else useful for LAN play.
4. **Result**: a list in `docs/investigations/hmw-diff.md` with a recommendation per item; the user decides what we
   re-implement; implementation goes through the normal spec -> opencode -> review loop.
