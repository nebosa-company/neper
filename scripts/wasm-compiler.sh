#!/bin/bash
# The compiler as neper.wasm (C184, D5640): build src/main.e for wasm32-wasi with the native
# compiler, then have both emit each program for each target from the repository root and
# compare the bytes. Each pair is one of
#   identical            the same bytes
#   identity-only        they differ only in the embedded compiler identity (identity_only below)
#   differ             both wrote and the bytes differ (cmp's first difference follows)
#   wasm-failed          the native compiler wrote and neper.wasm did not (its message follows)
#   refused-same         neither wrote, with the same diagnostics
#   refused-differently  neither wrote, with different diagnostics
#
#   scripts/wasm-compiler.sh                          # basic, wasm_flow, wasm_reserve, the compiler
#   scripts/wasm-compiler.sh -j 4 --all               # every link fixture
#   scripts/wasm-compiler.sh --target wasm32-wasi compiler   # neper.wasm emitting itself
#
# A name is a link fixture, or `compiler` for src/main.e. Targets default to x64-windows and
# x64-linux. The native compiler is build/<host>/neper-try or NEPER_COMPILER. Results go to
# build/wasm-compiler/results.tsv; the status is 1 when any pair is not identical, identity-only
# or refused the same way.
set -u
jobs=1
names=()
targets=()
all=
while [ $# -gt 0 ]; do
    case "$1" in
        -j) shift; jobs=${1:?-j needs a number} ;;
        --target) shift; targets+=("${1:?--target needs ARCH-OS}") ;;
        --all) all=1 ;;
        *) names+=("$1") ;;
    esac
    shift
done
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 2
case "$(uname -s)" in
  Linux) compiler=build/linux/neper-try ;;
  *)     compiler=build/windows/neper-try.exe ;;
esac
compiler=${NEPER_COMPILER:-$compiler}
out=build/wasm-compiler
mkdir -p "$out/bytes"
[ ${#targets[@]} -eq 0 ] && targets=(x64-windows x64-linux)
if [ -n "$all" ]; then
    for dir in tests/selfhost/fixtures/link/*/; do
        [ -f "${dir}src/main.e" ] && names+=("$(basename "$dir")")
    done
fi
[ ${#names[@]} -eq 0 ] && names=(basic wasm_flow wasm_reserve compiler)

written=$("$compiler" emit-executable src/main.e . wasm32 wasi "$out/neper.wasm" 2>&1)
[ "$written" = 'executable written' ] || { printf 'neper.wasm did not build: %s\n' "$written" >&2; exit 1; }

# An executable that embeds device code carries the identity of the compiler that wrote it: a CRC
# and the size of the compiler's own file, as sixteen hex digits before a colon (D398, D1734). Two
# native compilers of different bytes differ there too, so a difference inside those digits and
# nowhere else is the identity, not a miscompile.
identity_only() {
    [ "$(wc -c < "$1")" = "$(wc -c < "$2")" ] || return 1
    ids=$(LC_ALL=C grep -obaP '[0-9a-f]{16}:' "$1" | cut -d: -f1 | tr '\n' ' ')
    [ -n "$ids" ] && [ "$ids" = "$(LC_ALL=C grep -obaP '[0-9a-f]{16}:' "$2" | cut -d: -f1 | tr '\n' ' ')" ] || return 1
    cmp -l "$1" "$2" | awk -v ids="$ids" 'BEGIN { n = split(ids, at, " ") }
        { hit = 0; for (i = 1; i <= n; i++) if ($1 > at[i] && $1 <= at[i] + 16) hit = 1; if (!hit) bad = 1 }
        END { exit bad }'
}

one() {
    name=$1 target=$2
    source=tests/selfhost/fixtures/link/$name/src/main.e
    [ "$name" = compiler ] && source=src/main.e
    arch=${target%%-*} os=${target#*-}
    native="$out/bytes/$name.$target.native" wasm="$out/bytes/$name.$target.wasm"
    rm -f "$native" "$wasm"
    native_said=$("$compiler" emit-executable "$source" . "$arch" "$os" "$native" 2>&1)
    start=$(date +%s%N)
    wasm_said=$(node --no-warnings scripts/run-wasm.mjs "$out/neper.wasm" emit-executable "$source" . "$arch" "$os" "$wasm" 2>&1)
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    if [ -f "$native" ] && [ -f "$wasm" ]; then
        if cmp -s "$native" "$wasm"; then
            result=identical
        elif identity_only "$native" "$wasm"; then
            result=identity-only
        else
            result="differ	$(cmp "$native" "$wasm" 2>&1 | head -1)"
        fi
    elif [ -f "$native" ]; then
        result="wasm-failed	$(printf '%s' "$wasm_said" | tr '\n\t' '  ' | cut -c1-240)"
    elif [ "$native_said" = "$wasm_said" ]; then
        result=refused-same
    else
        result="refused-differently	$(printf '%s' "$wasm_said" | tr '\n\t' '  ' | cut -c1-240)"
    fi
    rm -f "$native" "$wasm"
    printf '%s\t%s\t%s\t%sms\n' "$name" "$target" "$result" "$ms"
}
export -f one identity_only
export compiler out

: > "$out/results.tsv"
for target in "${targets[@]}"; do
    for name in "${names[@]}"; do printf '%s %s\n' "$name" "$target"; done
done | xargs -P "$jobs" -n 2 bash -c 'one "$0" "$1"' | tee -a "$out/results.tsv"
good='	identical	\|	identity-only	\|	refused-same	'
printf '%s pairs: %s identical, %s identity only, %s refused the same, %s other\n' \
    "$(wc -l < "$out/results.tsv")" \
    "$(grep -c '	identical	' "$out/results.tsv")" \
    "$(grep -c '	identity-only	' "$out/results.tsv")" \
    "$(grep -c '	refused-same	' "$out/results.tsv")" \
    "$(grep -vc "$good" "$out/results.tsv")"
! grep -q -v "$good" "$out/results.tsv"
