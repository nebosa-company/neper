#!/bin/bash
# test262 parse conformance runner for e.js.parse (tracker 5.2, 5.14). From anywhere:
#   tests/browser/js/parse.sh TEST262_DIR MANIFEST [--floor N] [--show] [--only TEXT]
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
case "$(uname -s)" in
  Linux) os=linux; compiler="$repo/build/linux/neper-try"; exe="$repo/build/linux/js-parse-run" ;;
  *)     os=windows; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/js-parse-run.exe" ;;
esac
[ -x "$compiler" ] || { echo "no $compiler: run scripts/check-fixture.sh <any fixture> once to build it" >&2; exit 2; }
cd "$repo"
written=$("$compiler" emit-executable "$repo/tests/browser/js/parse_run.e" "$repo" x64 "$os" "$exe" --arena 1g)
[ "$written" = 'executable written' ] || { echo "parse_run.e did not emit: $written" >&2; exit 1; }
"$exe" "$@"
