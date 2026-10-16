#!/usr/bin/env bash
# Compile and run the Cupertino sheet apps (examples/looks/cup_<name>.e), one at a time; each renders
# docs/ui/looks/cupertino/<control>.png and cupertino-dark/<control>.png at 100 % and 150 %.
# Usage (Git Bash, from anywhere): scripts/cup_run.sh [name[:arg] ...]   (no names = every cup_ app)
# `name:arg` runs the app with one argument (the menu apps render one overlay per process: `menu`, then `menu:hover`).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/cup-exe"
mkdir -p "$out"
neper="${NEPER:-$root/build/windows/neper-self.exe}"
[ -x "$neper" ] || neper="/d/repos/neper/build/windows/neper-self.exe"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for f in examples/looks/cup_*.e; do n="$(basename "$f" .e)"; names+=("${n#cup_}"); done
  names+=("popup:open" "menu:hover" "alert:open")
fi
fail=""
for c in "${names[@]}"; do
  name="${c%%:*}"
  arg=""
  [ "$c" != "$name" ] && arg="${c#*:}"
  r=$("$neper" emit-executable "examples/looks/cup_$name.e" "$root" x64 windows "$out/cup_$name.exe" --arena 4g 2>&1 | tail -12)
  case "$r" in *"executable written"*) ;; *) echo "COMPILE FAILED cup_$name"; echo "$r"; fail="$fail compile:$name"; continue;; esac
  if "$out/cup_$name.exe" $arg >/dev/null 2>&1; then echo "ok cup_$c"; else echo "RUN FAILED cup_$c"; fail="$fail run:$c"; fi
done
[ -z "$fail" ] || { echo "FAILED:$fail"; exit 1; }
