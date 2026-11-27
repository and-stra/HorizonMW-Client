# Building MWX

## Requirements

- Windows 10/11 x64, Visual Studio 2022 (Desktop C++ / MSVC v143), Windows SDK.
- Git with the submodules (`deps/`), Python 3 (test/tool scripts), PowerShell 5.1.
- The game install as a sibling of the repo:
  `C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered`.

## Build

```
cd C:\Games\cod-hwm\cod-mwx
tools\build\build-mwx.bat -nogit
```

- `-nogit` builds **what is checked out** (no checkout, no fast-forward). Use it on work branches.
- Without `-nogit` the script checks out `mwx` and fast-forwards it from `claude/mwx` — for the
  orchestrator's workflow only.
- The script runs premake (`tools\premake5 vs2022`), MSBuild (`build\hmw-mod.sln`, Release x64),
  copies `build\bin\x64\Release\mwx.exe` to `GAME\mwx.exe`, archives `mwx.pdb` per commit under
  `refs\pdb\<commit>\`, mirrors `data\mwx` into `GAME\mwx` (robocopy `/MIR`) and copies every
  `data\mods\<name>` into `GAME\mods\<name>`.
- A running `mwx.exe` cannot be overwritten: the script renames it to `mwx-prev-<n>.exe` first.
  A stale locked process can print "Zugriff verweigert" for the old-file cleanup but the new exe is
  still copied (verify the hash of `GAME\mwx.exe` vs `build\bin\x64\Release\mwx.exe`).
- Log: `build-mwx.log` in the repo root.

## After a build

- `GAME\mwx` must mirror `data\mwx` (the build does this). A manual single-file copy is the same
  operation, e.g. when only a ui_script changed.
- The PDB for each commit is in `refs\pdb\<sha>\mwx.pdb`; the crash dumps symbolise against it.
- Run the tests per [testing.md](../guides/testing.md) — never two full suites back to back, and no
  heavy I/O while a client loads (it causes false zone-load stalls).

## Removing build output

`tools\build\build-mwx.bat` is the only supported way; do not clean `build\` by hand (the PDB
archive and the git checkout share it). Free space: keep ≥20 GB on C:.
