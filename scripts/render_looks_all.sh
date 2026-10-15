#!/usr/bin/env bash
# Compile and run every looks sheet app (examples/looks/*.e): refreshes docs/ui/looks/<look>/*.png.
# Usage (Git Bash, from anywhere): scripts/render_looks_all.sh [name ...]   (no names = all)
# The popup menu app renders one sheet per process (a second menu in one process runs out of GPU
# memory), so it is run once per sheet name.
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
  if [ "$c" = "popup_menu" ]; then
    for s in popup_menu popup_menu-hover popup_menu_dialog popup_menu_file popup_menu_cards popup_menu_search \
             popup_menu_view popup_menu_cardart popup_menu_online popup_menu_reports popup_menu_tools \
             popup_menu_admin popup_menu_help; do
      "$out/$c.exe" "$s" >/dev/null 2>&1 || fail="$fail run:$c/$s"
    done
  else
    "$out/$c.exe" >/dev/null 2>&1 || fail="$fail run:$c"
  fi
done
if [ -n "$fail" ]; then echo "FAILED:$fail"; exit 1; fi
python scripts/render_looks.py
echo "all looks sheets rendered"
