#!/bin/bash
# WPT URL parser runner for e.fmt.url (tracker 1.5). From anywhere:
#   tests/browser/url/run.sh [--show] [--floor N]
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
here="$repo/tests/browser/url"
case "$(uname -s)" in
  Linux) os=linux; compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/run-url" ;;
  *)     os=windows; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/run-url.exe" ;;
esac
[ -x "$compiler" ] || { echo "no $compiler: run scripts/check-fixture.sh <any fixture> once to build it" >&2; exit 2; }
cd "$repo"
written=$("$compiler" emit-executable "$here/run.e" "$repo" x64 "$os" "$exe" --arena 1g)
[ "$written" = 'executable written' ] || { echo "run.e did not emit: $written" >&2; exit 1; }
# The recorded floors: every case of urltestdata.json and of setters_tests.json passes.
if [ $# -eq 0 ]; then set -- --floor 896; elif [ "$1" = "--setters" ] && [ $# -eq 1 ]; then set -- --setters --floor 278; fi
"$exe" "$@"
