#!/usr/bin/env bash
# regression sample of worker l3: re-render other looks' sheets and show any changed PNG outside the Linux folders
cd "$(dirname "$0")/.." || exit 1
mkdir -p /tmp/lx_l3
for c in "$@"; do
  for try in 1 2 3 4 5 6; do
    r=$(build/windows/neper-self.exe emit-executable examples/looks/$c.e "$(pwd)" x64 windows /tmp/lx_l3/reg_$c.exe --arena 4g 2>&1 | tail -1)
    [ "$r" = "executable written" ] && break
  done
  if [ "$r" != "executable written" ]; then echo "COMPILE FAIL $c: $r"; continue; fi
  /tmp/lx_l3/reg_$c.exe </dev/null >/dev/null 2>&1 || echo "RUN FAIL $c"
done
git status --short docs/ui/looks | grep -v "docs/ui/looks/linux\|docs/ui/looks/ref/linux" || echo "no other-look changes"
