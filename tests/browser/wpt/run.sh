#!/bin/bash
# WPT reftest runner for the Neper browser stack (tracker 0.6, 9.2). From anywhere:
#   tests/browser/wpt/run.sh [--floor N] [--show] [--only TEXT] [--out DIR] [manifest]
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
case "$(uname -s)" in
  Linux) os=linux; compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/run-wpt" ;;
  *)     os=windows; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/run-wpt.exe" ;;
esac
[ -x "$compiler" ] || { echo "no $compiler: run scripts/check-fixture.sh <any fixture> once to build it" >&2; exit 2; }
cd "$repo"
written=$("$compiler" emit-executable "$repo/tests/browser/wpt/run.e" "$repo" x64 "$os" "$exe" --arena 1g)
[ "$written" = 'executable written' ] || { echo "run.e did not emit: $written" >&2; exit 1; }
"$exe" "$@"
