#!/usr/bin/env bash
# Compile and run every looks sheet app (examples/looks/*.e): refreshes docs/ui/looks/<look>/*.png.
# Usage (Git Bash, from anywhere): scripts/render_looks_all.sh [name ...]   (no names = all)
# One process renders every sheet of an app (looks.e frees each rig's gpu device and arena memory).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/looks-exe"
mkdir -p "$out"
neper="$root/build/windows/neper-self.exe"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for f in examples/looks/*.e; do names+=("$(basename "$f" .e)"); done
fi
fail=""
for c in "${names[@]}"; do
  r=$("$neper" emit-executable "examples/looks/$c.e" "$root" x64 windows "$out/$c.exe" --arena 4g 2>&1 | tail -1)
  if [ "$r" != "executable written" ]; then fail="$fail compile:$c"; continue; fi
  "$out/$c.exe" >/dev/null 2>&1 || fail="$fail run:$c"
done
if [ -n "$fail" ]; then echo "FAILED:$fail"; exit 1; fi
python scripts/render_looks.py
echo "all looks sheets rendered"
