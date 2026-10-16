#!/bin/bash
# html5lib tree-construction runner for e.fmt.html (tracker 0.6). From anywhere:
#   tests/browser/html5lib/run.sh [--show] [files.dat...]   (default: every data/*.dat)
# Needs the self-hosted compiler build/{windows/neper-try.exe,linux/neper-try}; scripts/check-fixture.sh builds it.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
here="$repo/tests/browser/html5lib"
case "$(uname -s)" in
  Linux) os=linux; compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/run-html5lib" ;;
  *)     os=windows; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/run-html5lib.exe" ;;
esac
[ -x "$compiler" ] || { echo "no $compiler: run scripts/check-fixture.sh <any fixture> once to build it" >&2; exit 2; }
[ $# -gt 0 ] && [ "${*#--show}" != "$*" ] && [ $# -eq 1 ] && set -- "$@" "$here"/data/*.dat
[ $# -gt 0 ] || set -- "$here"/data/*.dat
cd "$repo"
written=$("$compiler" emit-executable "$here/run.e" "$repo" x64 "$os" "$exe" --arena 1g)
[ "$written" = 'executable written' ] || { echo "run.e did not emit: $written" >&2; exit 1; }
"$exe" "$@"
