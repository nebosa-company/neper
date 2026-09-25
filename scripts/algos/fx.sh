#!/bin/bash
# usage: build/fx.sh <fixture-name>  — run one link fixture with neper-try and neper-self
cd /d/repos/neper || exit 99
n=$1
[[ $n =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "invalid fixture name: $n" >&2; exit 2; }
for c in build/windows/neper-try.exe build/windows/tests/selfhost/neper-self.exe; do
  rm -f "build/fx_$n.exe"
  $c emit-executable "tests/selfhost/fixtures/link/$n/src/main.e" . x64 windows "build/fx_$n.exe" 2>&1 | tail -3
  "build/fx_$n.exe"; echo "$c exit=$?"
done
