#!/bin/bash
# Web Platform Tests for scripts (tracker 6): runs a list of WPT files (paths relative to the checkout) through web-run in
# parallel chunks, so a crash or a hang loses one chunk and not the run.
#   tests/browser/web/run.sh [--root DIR] [--out DIR] [--jobs N] [--chunk N] [--build] LIST
# Prints one `FILE path pass/total` line per test file and a final `wpt FILES files SUBTESTS subtests PASS pass` line;
# the per-chunk raw output stays in --out (default $TMPDIR/web-run) for reading the failures (`--show` lines).
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
root="${WPT_ROOT:-/d/Temp/wpt}"
out="${TMPDIR:-/tmp}/web-run"
jobs=3
chunk=20
build=0
while [ $# -gt 1 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --chunk) chunk="$2"; shift 2 ;;
    --build) build=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
list="$1"
case "$(uname -s)" in
  Linux) compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/web-run"; os=linux ;;
  *) compiler="$repo/build/windows/neper-try.exe"; exe="${WEB_RUN_EXE:-$repo/build/windows/web-run.exe}"; os=windows ;;
esac
if [ "$build" = 1 ] || [ ! -x "$exe" ]; then
  (cd "$repo" && "$compiler" emit-executable tests/browser/web/run.e "$repo" x64 "$os" "$exe" --arena 3g)
fi
rm -rf "$out"; mkdir -p "$out"
split -l "$chunk" -a 4 "$list" "$out/c_"
ls "$out"/c_* | xargs -P "$jobs" -I{} bash -c "cd '$repo'; timeout 300 '$exe' '$root' {} --show > {}.out 2>&1; echo \"exit \$?\" >> {}.out"
cat "$out"/c_*.out | grep '^FILE ' | sort -u
cat "$out"/c_*.out | grep '^wpt ' | awk '{f+=$2; s+=$4; p+=$6} END {print "wpt", f, "files", s, "subtests", p, "pass"}'
bad=$(grep -L '^wpt ' "$out"/c_*.out | wc -l)
echo "chunks without a result: $bad"
