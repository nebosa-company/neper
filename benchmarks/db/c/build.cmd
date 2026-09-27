@echo off
rem Builds bench-c.exe with MSVC against the Windows SDK's winsqlite3 and the client libraries
rem unpacked under %NEPER_DB_TOOLS% (default D:\tools). Usage: build.cmd <output.exe>
setlocal
if "%NEPER_DB_TOOLS%"=="" set NEPER_DB_TOOLS=D:\tools
if "%VCVARS%"=="" set VCVARS=D:\VS\Community\VC\Auxiliary\Build\vcvars64.bat
call "%VCVARS%" >nul || exit /b 1
cl /nologo /O2 /W3 /Fe:%1 /Fo:%~dp1 "%~dp0bench.c" /I "%NEPER_DB_TOOLS%\postgresql\include" /I "%NEPER_DB_TOOLS%\mysql\include" winsqlite3.lib "%NEPER_DB_TOOLS%\postgresql\lib\libpq.lib" "%NEPER_DB_TOOLS%\mysql\lib\libmysql.lib" || exit /b 1
