@echo off
rem MWX build script (repository copy).
rem
rem   tools\build\build-mwx.bat [-nogit] [-game <dir>] [-log <file>]
rem
rem Default: checkout the mwx branch, fast-forward it to claude/mwx, update the submodules, run
rem premake + msbuild (Release x64), copy mwx.exe into the game folder, archive mwx.pdb per commit
rem and mirror data\mwx and data\mods into the game folder.
rem
rem   -nogit        build whatever is checked out (no checkout, no fast-forward); used by the
rem                 autonomous/fix branches and by C:\Games\cod-hwm\build-branch.bat
rem   -game <dir>   game folder (default: C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\...
rem   -log <file>   log file (default: <repo>\build-mwx.log)
rem
rem The script never touches hmw-mod.exe, game files or .ff files. A running mwx.exe (a game or the
rem MCP server opencode started) is renamed to mwx-prev-<n>.exe instead of being overwritten.
setlocal
set ROOT=%~dp0..\..
set REPO=%ROOT%
set GAME=%ROOT%\..\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered
set LOG=%REPO%\build-mwx.log
set NOGIT=0

rem two positional flag pairs are enough for the wrappers
if /i "%~1"=="-nogit" set NOGIT=1
if /i "%~1"=="-game" set GAME=%~2
if /i "%~1"=="-log" set LOG=%~2
if /i "%~2"=="-nogit" set NOGIT=1
if /i "%~2"=="-game" set GAME=%~3
if /i "%~2"=="-log" set LOG=%~3
if /i "%~3"=="-nogit" set NOGIT=1
if /i "%~3"=="-game" set GAME=%~4
if /i "%~3"=="-log" set LOG=%~4

echo ==== MWX build %date% %time% ==== > "%LOG%"
cd /d "%REPO%" || goto :fail

if "%NOGIT%"=="0" (
  echo [1/5] git checkout mwx >> "%LOG%"
  git checkout mwx >> "%LOG%" 2>&1 || goto :fail
  rem Claude pushes its commits to the branch claude/mwx (mwx itself is checked out here)
  git rev-parse --verify --quiet claude/mwx >nul && (git merge --ff-only claude/mwx >> "%LOG%" 2>&1 || (echo claude/mwx and mwx have diverged: merge them by hand >> "%LOG%" & goto :fail))
) else (
  echo [1/5] no git (build what is checked out) >> "%LOG%"
  git rev-parse --abbrev-ref HEAD >> "%LOG%" 2>&1
)

echo [2/5] submodules >> "%LOG%"
git submodule update --init --recursive >> "%LOG%" 2>&1 || goto :fail

echo [3/5] Visual Studio >> "%LOG%"
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
if not exist "%VSWHERE%" (echo vswhere.exe not found: install Visual Studio 2022 Build Tools >> "%LOG%" & goto :fail)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSPATH=%%i
if not defined VSPATH (echo No Visual Studio with the C++ tools found >> "%LOG%" & goto :fail)
echo %VSPATH% >> "%LOG%"
call "%VSPATH%\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >> "%ROOT%\build-vsenv.log" 2>&1

echo [4/5] premake + msbuild >> "%LOG%"
tools\premake5 vs2022 >> "%LOG%" 2>&1 || goto :fail
msbuild build\hmw-mod.sln /m /p:Configuration=Release /p:Platform=x64 /v:minimal /nologo >> "%LOG%" 2>&1 || goto :fail

echo [5/5] copy mwx.exe >> "%LOG%"
rem A running mwx.exe cannot be overwritten, but it can be renamed. Use a unique backup name: a
rem fixed mwx.exe.old may itself be held by a stale process.
for %%F in ("%GAME%\mwx-prev-*.exe") do del /f /q "%%F" >> "%LOG%" 2>&1
if exist "%GAME%\mwx.exe" ren "%GAME%\mwx.exe" "mwx-prev-%RANDOM%.exe" >> "%LOG%" 2>&1
copy /y "build\bin\x64\Release\mwx.exe" "%GAME%\mwx.exe" >> "%LOG%" 2>&1 || goto :fail

rem Archive the PDB per commit so crashes in this build can be symbolised later.
for /f %%h in ('git rev-parse HEAD') do set HASH=%%h
set PDBDIR=%ROOT%\..\refs\pdb\%HASH%
if not exist "%PDBDIR%" mkdir "%PDBDIR%"
copy /y "build\bin\x64\Release\mwx.pdb" "%PDBDIR%\mwx.pdb" >> "%LOG%" 2>&1

rem MWX: mirror the client data (ui_scripts, ...) into the game folder
robocopy "%REPO%\data\mwx" "%GAME%\mwx" /MIR /NFL /NDL /NJH /NJS /NP >> "%LOG%" 2>&1
if errorlevel 8 goto :fail
rem MWX: copy every mod (data\mods\<name>\ -> GAME\mods\<name>\), without /MIR so a mod.ff
rem that was built into GAME\mods\<name>\ stays
if exist "%REPO%\data\mods" for /d %%D in ("%REPO%\data\mods\*") do robocopy "%%D" "%GAME%\mods\%%~nxD" /E /NFL /NDL /NJH /NJS /NP >> "%LOG%" 2>&1
if errorlevel 8 goto :fail

echo BUILD OK >> "%LOG%"
echo BUILD OK
exit /b 0

:fail
echo BUILD FAILED >> "%LOG%"
echo BUILD FAILED - see %LOG%
exit /b 1
