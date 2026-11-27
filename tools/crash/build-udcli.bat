REM build the udis86 disassembler CLI - moved from mwx-debug\build-udcli.bat on 27 Nov 2026.
@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d C:\Games\cod-hwm\cod-mwx\deps\udis86
cl /nologo /O2 /Fe:C:\Games\cod-hwm\mwx-debug\udcli.exe udcli\udcli.c libudis86\decode.c libudis86\syn.c libudis86\syn-att.c libudis86\syn-intel.c libudis86\udis86.c libudis86\itab.c
exit /b %errorlevel%
