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
#   scripts/check-fixture.sh game_core                          # host compiler, host target
#   scripts/check-fixture.sh game_core --keep                   # leave the executable behind
#   scripts/check-fixture.sh game_core --target wasm32-wasi     # a WebAssembly module under Node
#   scripts/check-fixture.sh wasm_release --target wasm32-wasi --release   # built with --release
#   scripts/check-fixture.sh wasm_atomics --target wasm32-wasi --threads   # the threaded module shape (D5671)
set -eu

fixture=${1:?usage: check-fixture.sh <fixture-name> [--keep] [--target wasm32-wasi] [--release]}
shift
keep=
release=
threads=
target=
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) keep=1 ;;
        --release) release=--release ;;
        --threads) threads=--threads ;;
        --target) shift; target=${1:?--target needs a value} ;;
        *) printf '%s\n' "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source="$repo/tests/selfhost/fixtures/link/$fixture/src/main.e"
[ -f "$source" ] || { printf '%s\n' "no such fixture: $fixture" >&2; exit 2; }

host_arch=x64
case "$(uname -s)" in
  Linux) host_os=linux;  bootstrap="$repo/build/linux/neper";       compiler="$repo/build/linux/neper-try";       exe="$repo/build/linux/check-$fixture" ;;
  Darwin) host_os=macos;  bootstrap=/nonexistent; compiler=${NEPER_COMPILER:?set NEPER_COMPILER to a compiler built on this Mac}; exe="$repo/build/check-$fixture"; [ "$(uname -m)" = arm64 ] && host_arch=aarch64 ;;
  *)     host_os=windows; bootstrap="$repo/build/windows/neper.exe"; compiler="$repo/build/windows/neper-try.exe"; exe="$repo/build/windows/check-$fixture.exe" ;;
esac

# Rebuild the self-hosted compiler only when a source file is newer than it, so a run of
# this script normally costs one compile of one fixture.
# NEPER_COMPILER names a compiler already built (a stage 2, say) and skips the rebuild below.
newest_source=
[ -n "${NEPER_COMPILER:-}" ] && compiler=$NEPER_COMPILER
[ -z "${NEPER_COMPILER:-}" ] && newest_source=$(find "$repo/src" -name '*.e' -newer "$compiler" 2>/dev/null | head -n 1 || true)
if [ -z "${NEPER_COMPILER:-}" ] && { [ ! -x "$compiler" ] || [ -n "$newest_source" ]; }; then
    printf '%s\n' "building the self-hosted compiler ($host_os)..."
    [ -x "$bootstrap" ] || "$repo/scripts/build-bootstrap.sh"
    "$bootstrap" build "$repo/src/main.e" --arena 1g --output "$compiler" > "$repo/build/check-fixture-build.log" 2>&1 \
        || { printf '%s\n' "the compiler did not build; see build/check-fixture-build.log" >&2; exit 1; }
fi

if [ -n "$target" ]; then
    [ "$target" = wasm32-wasi ] || { printf '%s\n' "unknown target: $target" >&2; exit 2; }
    exe="${exe%.exe}.wasm"
    written=$("$compiler" emit-executable "$source" "$repo" wasm32 wasi "$exe" $release $threads)
    [ "$written" = 'executable written' ] || { printf '%s\n' "$fixture did not emit: $written" >&2; exit 1; }
    status=0
    node --no-warnings "$repo/lib/wasm/run-wasm.mjs" "$exe" || status=$?
    [ -n "$keep" ] || rm -f "$exe"
    if [ "$status" -eq 0 ]; then
        printf '%s\n' "$fixture passed on wasm32-wasi"
    else
        printf '%s\n' "$fixture FAILED on wasm32-wasi (exit $status)" >&2
    fi
    exit "$status"
fi

written=$("$compiler" emit-executable "$source" "$repo" "$host_arch" "$host_os" "$exe" $release)
[ "$written" = 'executable written' ] || { printf '%s\n' "$fixture did not emit: $written" >&2; exit 1; }
[ "$host_os" = windows ] || chmod +x "$exe"

status=0
"$exe" || status=$?
[ -n "$keep" ] || rm -f "$exe"

if [ "$status" -eq 0 ]; then
    printf '%s\n' "$fixture passed on $host_arch-$host_os"
else
    # A fixture returns a check number, but `fn main() -> i64` reaches the exit code as 1
    # whatever it returns, so the number is a marker in the source rather than a status.
    printf '%s\n' "$fixture FAILED on $host_arch-$host_os (exit $status)" >&2
fi
exit "$status"
