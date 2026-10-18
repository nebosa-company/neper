#!/usr/bin/env bash
# Worker l4: compile and run one Linux sheet app, then compare. Usage: scripts/l4_run.sh <sheet> [--png]   (sheet = list_box, ...)
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="${L4OUT:-D:/Temp/l4out}"
mkdir -p "$out"
for i in 1 2 3; do
  r=$(build/windows/neper-self.exe emit-executable "examples/looks/linux_$1.e" "$root" x64 windows "$out/linux_$1.exe" --arena 4g 2>&1 | tail -3)
  [ "$r" = "executable written" ] && break
  echo "$r"
done
[ "$r" = "executable written" ] || exit 1
"$out/linux_$1.exe" </dev/null || exit 2
python -I scripts/linux_cmp_l4.py compose "$1" >/dev/null
python -I scripts/linux_cmp_l4.py cmp "$1" ${2:-}
