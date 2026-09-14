#!/bin/bash
# Build one link fixture with the self-hosted compiler and run it.
#
# The full suite makes 415 compiler invocations over 175 fixtures and builds the compiler
# two or three times for the fixed point. That is the right price when a change can reach
# the compiler -- anything under src/, bootstrap/ or scripts/, or an edit to a lib module
# something else imports. It is the wrong price for a change that only ADDS a lib module
# and its own fixture: the compiler does not import e.game or e.math.fixed, so nothing
# else in the suite can see the change, and the only new fact is whether this one fixture
# passes. Use this during development and the full suite once per batch, at merge.
#
#   scripts/check-fixture.sh game_core          # host compiler, host target
#   scripts/check-fixture.sh game_core --keep   # leave the executable behind
set -eu

fixture=${1:?usage: check-fixture.sh <fixture-name> [--keep]}
keep=${2:-}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source="$repo/tests/selfhost/fixtures/link/$fixture/src/main.e"
[ -f "$source" ] || { printf '%s\n' "no such fixture: $fixture" >&2; exit 2; }

case "$(uname -s)" in
  Linux) host_os=linux;  bootstrap="$repo/build/linux/neper";       compiler="$repo/build/linux/neper-try";       exe="$repo/build/linux/check-$fixture" ;;
  *)     host_os=windows; bootstrap="$repo/build/windows/neper.exe"; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/check-$fixture.exe" ;;
esac

# Rebuild the self-hosted compiler only when a source file is newer than it, so a run of
# this script normally costs one compile of one fixture.
newest_source=$(find "$repo/src" -name '*.e' -newer "$compiler" -print -quit 2>/dev/null || true)
if [ ! -x "$compiler" ] || [ -n "$newest_source" ]; then
    printf '%s\n' "building the self-hosted compiler ($host_os)..."
    [ -x "$bootstrap" ] || "$repo/scripts/build-bootstrap.sh"
    "$bootstrap" build "$repo/src/main.e" --arena 1g --output "$compiler" > "$repo/build/check-fixture-build.log" 2>&1 \
        || { printf '%s\n' "the compiler did not build; see build/check-fixture-build.log" >&2; exit 1; }
fi

written=$("$compiler" emit-executable "$source" "$repo" x64 "$host_os" "$exe")
[ "$written" = 'executable written' ] || { printf '%s\n' "$fixture did not emit: $written" >&2; exit 1; }
[ "$host_os" = windows ] || chmod +x "$exe"

status=0
"$exe" || status=$?
[ -n "$keep" ] || rm -f "$exe"

if [ "$status" -eq 0 ]; then
    printf '%s\n' "$fixture passed on x64-$host_os"
else
    # A fixture returns a check number, but `fn main() -> i64` reaches the exit code as 1
    # whatever it returns, so the number is a marker in the source rather than a status.
    printf '%s\n' "$fixture FAILED on x64-$host_os (exit $status)" >&2
fi
exit "$status"
