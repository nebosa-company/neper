#!/usr/bin/env bash
# Compile and run every looks sheet app (examples/looks/*.e): refreshes docs/ui/looks/<look>/*.png.
# Usage (Git Bash, from anywhere): scripts/render_looks_all.sh [name ...]   (no names = all)
# An app's main renders only its default sheet(s); every other sheet is reached by an argument, so the
# apps in scripts/looks_scale_sheets.json run once per listed argument (a plain run of them leaves e.g. the
# combo_box_open_* sheets at whatever an earlier round committed).
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
runs=$(python - <<'PY'
import json, glob, os
t = json.load(open("scripts/looks_scale_sheets.json"))
by = {"native_dark_open": ["", "1", "2", "3", "4", "5"]}
for app, args in t.values():
    by.setdefault(app, []).extend(args or [""])
for f in sorted(glob.glob("examples/looks/*.e")):
    a = os.path.basename(f)[:-2]
    for x in sorted(set(by.get(a, [""]))):
        print(a, x)
PY
)
runs=$(printf '%s' "$runs" | tr -d '\r')
for c in "${names[@]}"; do
  r=$("$neper" emit-executable "examples/looks/$c.e" "$root" x64 windows "$out/$c.exe" --arena 4g 2>&1 | tail -1)
  if [ "$r" != "executable written" ]; then fail="$fail compile:$c"; continue; fi
  while read -r app arg; do
    [ "$app" = "$c" ] || continue
    "$out/$c.exe" $arg </dev/null >/dev/null 2>&1 || fail="$fail run:$c $arg"
  done <<<"$runs"
done
if [ -n "$fail" ]; then echo "FAILED:$fail"; exit 1; fi
python scripts/render_looks.py
echo "all looks sheets rendered"
