@echo off
rem Minimal, size-optimised 32-bit Node.js for Windows (run from the repo root
rem with NODE_VERSION set and the extracted source in node-v%NODE_VERSION%).
setlocal
cd node-v%NODE_VERSION% || exit /b 1

rem Same feature set as the linux/macOS bases: no ICU, no inspector, NODE_OPTIONS
rem ignored, no bundled TS tooling / SQLite / built-in code cache.
rem (without-intl is a vcbuild argument; the rest go to configure.)
set config_flags=--without-node-options --without-inspector --without-amaro --without-sqlite --without-node-code-cache

rem OPT=O1: optimise for size (MSVC's -Os). _CL_ is appended after the project's
rem own flags, so /O1 overrides its /Ox. OPT=O2: keep the project's /Ox (speed).
rem `release` already enables LTCG.
if not defined OPT set OPT=O1
if /i "%OPT%"=="O1" set _CL_=/O1

call vcbuild.bat release x86 vs2022 without-intl no-cctest nonpm nocorepack
if errorlevel 1 exit /b 1
endlocal
