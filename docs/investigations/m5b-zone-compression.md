# M5b - zone compression and startup I/O profile (measurement only)

Question: are the nine HMW content zones still zlib, and is the ~28 s load CPU (decompression) or
disk-bound? Could an LZ4 repack still help?

## Zone headers (`hmw-mod\zone\<name>.ff`, 2026-11-24)

Format per `src/client/repack.cpp:10-18`: `S1ffu100` at 0, version `0x42` at 8, `compress` at 12,
`compressType` at 13 (1 = zlib, 4 = LZ4).

| zone | size | magic | compressType |
|---|---|---|---|
| hmw_killstreak | 117.6 MB | S1ffu100 | 4 (LZ4) |
| hmw_attachments | 338.3 MB | S1ffu100 | 4 (LZ4) |
| hmw_ar1 | 267.8 MB | S1ffu100 | 4 (LZ4) |
| hmw_smg | 393.4 MB | S1ffu100 | 4 (LZ4) |
| hmw_shotgun | 277.5 MB | S1ffu100 | 4 (LZ4) |
| hmw_rangers | 293.8 MB | S1ffu100 | 4 (LZ4) |
| hmw_nightshade | 458.0 MB | S1ffu100 | 4 (LZ4) |
| hmw_dlc_factions | 510.7 MB | S1ffu100 | 4 (LZ4) |
| hmw_dlc_killstreaks | 191.8 MB | S1ffu100 | 4 (LZ4) |

**The repack was already done** (file dates 2026-11-20 18:18). The zlib originals are in
`GAME\hmw-mod\zone_backup_zlib\` (21 files, `compressType = 1`; e.g. `hmw_dlc_factions.ff`
383.4 MB zlib vs 510.7 MB LZ4). `mwx-logs\repack.log` ends with the usermap restore, not a failed
repack. So LZ4 is already active and still the load is slow.

## One startup profile (`tools/test/profile-startup.ps1`)

Sampled `Win32_Process` CPU (`UserModeTime`) and `ReadTransferCount` every 250 ms while the client
loaded the nine zones (test mode, fresh process):

| metric | value |
|---|---|
| zone block (`hmw_killstreak` start -> first main-thread frame) | 40.7 s |
| CPU time in that window | 7.86 s |
| CPU as % of one core | **19.3 %** |
| bytes read | 2836.7 MB (the nine files total 2848.9 MB) |
| read throughput | **69.7 MB/s** |

(The 40.7 s run was slower than the usual ~28 s; the ratio and the ~70 MB/s are the point.)

## Conclusion

The load is **I/O-bound, not decompression-bound**: it reads every byte of the nine zones once at
~70 MB/s while the CPU is mostly idle. LZ4 already removed the decompression cost; another repack
would not help. The remaining options are outside the zone format:

- faster storage for `GAME\hmw-mod\zone` (the whole game is on C:; a faster SSD / NVMe),
- antivirus exclusion for the game folder (70 MB/s is low for an NVMe and consistent with on-access
  scanning),
- load fewer/smaller zones (only what the menu and the selected map need), or strip unused content
  from the nine zones,
- keep the current ~28-60 s startup; no code change.

No repack was performed in this step; nothing was changed.
