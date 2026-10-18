#!/usr/bin/env bash
# build + run one linux sheet app of worker l3: scripts/lxb.sh progress_bar
cd "$(dirname "$0")/.." || exit 1
mkdir -p /tmp/lx_l3
for n in "$@"; do
  for try in 1 2 3 4 5 6; do
    r=$(build/windows/neper-self.exe emit-executable examples/looks/linux_$n.e "$(pwd)" x64 windows /tmp/lx_l3/linux_$n.exe --arena 4g 2>&1 | tail -4)
    [ "$(echo "$r" | tail -1)" = "executable written" ] && break
    case "$r" in *rena*) continue;; *) break;; esac
  done
  echo "$r"
  [ "$(echo "$r" | tail -1)" = "executable written" ] && /tmp/lx_l3/linux_$n.exe </dev/null 2>&1 | tail -3
done
