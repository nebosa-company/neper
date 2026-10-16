#!/bin/bash
# Renders a web page to a PNG with the CPU renderer (tracker 0.6, render tool). From anywhere:
#   tests/browser/tools/render.sh URL OUT.png [--width N] [--height N] [--full] [--scroll N]
# Needs the self-hosted compiler build/windows/neper-try.exe (scripts/check-fixture.sh builds it) and network access.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
case "$(uname -s)" in
  Linux) os=linux; compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/browser-render" ;;
  *)     os=windows; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/browser-render.exe" ;;
esac
[ -x "$compiler" ] || { echo "no $compiler: run scripts/check-fixture.sh <any fixture> once to build it" >&2; exit 2; }
cd "$repo"
written=$("$compiler" emit-executable "$repo/tests/browser/tools/render.e" "$repo" x64 "$os" "$exe" --arena 8g)
[ "$written" = 'executable written' ] || { echo "render.e did not emit: $written" >&2; exit 1; }
"$exe" "$@"
