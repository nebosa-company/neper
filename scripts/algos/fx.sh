#!/bin/bash
# usage: build/fx.sh <fixture-name>  — run one link fixture with neper-try and neper-self
cd /d/repos/neper || exit 99
n=$1
for c in build/windows/neper-try.exe build/windows/tests/selfhost/neper-self.exe; do
  rm -f build/fx_$n.exe
  $c emit-executable tests/selfhost/fixtures/link/$n/src/main.e . x64 windows build/fx_$n.exe 2>&1 | tail -3
  build/fx_$n.exe; echo "$c exit=$?"
done
