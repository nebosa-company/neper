#!/usr/bin/env bash
# usage: looks_run.sh <app> [part ...]  (compile examples/looks/<app>.e into D:/Temp/claude/looks11-g1 and run it)
cd "$(dirname "$0")/.."
app=$1; shift
/d/repos/neper/build/windows/neper-self.exe emit-executable examples/looks/$app.e . x64 windows D:/Temp/claude/looks11-g1/$app.exe --arena 4g 2>&1 | tail -1
if [ $# -eq 0 ]; then D:/Temp/claude/looks11-g1/$app.exe >/dev/null 2>&1; echo run $?; else for p in "$@"; do D:/Temp/claude/looks11-g1/$app.exe $p >/dev/null 2>&1; echo run $p $?; done; fi
