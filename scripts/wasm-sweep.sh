#!/bin/bash
# Build every link fixture for wasm32-wasi and for the host, run both, and compare exit status,
# standard output and standard error (D5213, D5668). Each fixture is one of
#   pass             the same exit status, the same stdout and the same stderr
#   stderr-differs   the same status and stdout, a different stderr (the first difference follows).
#                    Native frame lines (`  at f (file:line)`), which WebAssembly cannot walk, and
#                    carriage returns are left out of the comparison
#   fail             it ran and the status or stdout differed
#   refused          the WebAssembly emitter did not write a module (the reason is the second column)
#   invalid          the module was written and Node would not compile or link it
#   skipped          the host build does not run clean either, so there is nothing to compare with
#
#   scripts/wasm-sweep.sh                 # every fixture
#   scripts/wasm-sweep.sh -j 4 NAME...    # these, four at a time
#   scripts/wasm-sweep.sh --release       # both builds with --release
#
# The compiler is build/<host>/neper-try, or the one NEPER_COMPILER names (required on macOS).
# Results go to build/wasm-sweep/results.tsv (or WASM_SWEEP_OUT) and the counts to the end of the
# run. A run is limited to 120 seconds with timeout(1), or a watchdog where there is none (macOS).
set -u
jobs=1
release=
names=()
while [ $# -gt 0 ]; do
    case "$1" in
        -j) shift; jobs=${1:?-j needs a number} ;;
        --release) release=--release ;;
        *) names+=("$1") ;;
    esac
    shift
done
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
host_arch=x64
case "$(uname -s)" in
  Linux)  host_os=linux;  compiler="$repo/build/linux/neper-try";       ext="" ;;
  Darwin) host_os=macos;  compiler=${NEPER_COMPILER:?set NEPER_COMPILER to a compiler built on this Mac}; ext=""
          [ "$(uname -m)" = arm64 ] && host_arch=aarch64 ;;
  *)      host_os=windows; compiler="$repo/build/windows/neper-try.exe"; ext=".exe" ;;
esac
compiler=${NEPER_COMPILER:-$compiler}
out=${WASM_SWEEP_OUT:-$repo/build/wasm-sweep}
mkdir -p "$out"
if [ ${#names[@]} -eq 0 ]; then
    for dir in "$repo"/tests/selfhost/fixtures/link/*/; do
        [ -f "${dir}src/main.e" ] && names+=("$(basename "$dir")")
    done
fi

# limited SECONDS COMMAND...: the command's status; 124 (timeout's) or 137 when it ran out of time.
limited() {
    local seconds=$1 pid watcher status
    shift
    if command -v timeout > /dev/null 2>&1; then timeout "$seconds" "$@"; return; fi
    "$@" &
    pid=$!
    ( sleep "$seconds"; kill -9 "$pid" 2> /dev/null ) > /dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    status=$?
    kill "$watcher" 2> /dev/null
    wait "$watcher" 2> /dev/null
    return $status
}

# What a trap writes, less the frames WebAssembly cannot walk and the carriage returns Windows adds.
plain() { tr -d '\r' < "$1" | grep -v '^  at '; }

one() {
    name=$1
    source="$repo/tests/selfhost/fixtures/link/$name/src/main.e"
    host="$out/$name$ext"
    wasm="$out/$name.wasm"
    rm -f "$out/$name".*
    if ! "$compiler" emit-executable "$source" "$repo" "$host_arch" "$host_os" "$host" $release > "$out/$name.host.build" 2>&1; then
        printf '%s\tskipped\thost build\n' "$name"
        return
    fi
    limited 120 "$host" > "$out/$name.host.out" 2> "$out/$name.host.err" < /dev/null
    host_status=$?
    rm -f "$host"
    if ! "$compiler" emit-executable "$source" "$repo" wasm32 wasi "$wasm" $release > "$out/$name.wasm.build" 2>&1; then
        printf '%s\trefused\t%s\n' "$name" "$(grep -m1 -o 'E-[A-Z]*-[0-9]*.*' "$out/$name.wasm.build" | cut -c1-200)"
        return
    fi
    limited 120 node --no-warnings "$repo/scripts/run-wasm.mjs" "$wasm" > "$out/$name.wasm.out" 2> "$out/$name.wasm.err" < /dev/null
    wasm_status=$?
    rm -f "$wasm"
    if [ "$wasm_status" -eq 125 ]; then
        printf '%s\tinvalid\t%s\n' "$name" "$(head -c 300 "$out/$name.wasm.err" | tr '\n' ' ')"
    elif [ "$wasm_status" -eq "$host_status" ] && cmp -s "$out/$name.host.out" "$out/$name.wasm.out"; then
        plain "$out/$name.host.err" > "$out/$name.host.plain"
        plain "$out/$name.wasm.err" > "$out/$name.wasm.plain"
        if cmp -s "$out/$name.host.plain" "$out/$name.wasm.plain"; then
            printf '%s\tpass\t\n' "$name"
        else
            printf '%s\tstderr-differs\t%s\n' "$name" "$(diff "$out/$name.host.plain" "$out/$name.wasm.plain" | grep -m1 '^[<>]' | cut -c1-200)"
        fi
    else
        printf '%s\tfail\thost exit %s, wasm exit %s\n' "$name" "$host_status" "$wasm_status"
    fi
}
export -f one limited plain
export NEPER_WASM_STATS=${NEPER_WASM_STATS:-1}
export repo host_os host_arch compiler out ext release

printf '%s\n' "${names[@]}" | xargs -P "$jobs" -I{} bash -c 'one {}' | tee "$out/results.tsv"
printf '\n'
for kind in pass stderr-differs fail refused invalid skipped; do
    printf '%s %s\n' "$kind" "$(grep -c "	$kind	" "$out/results.tsv")"
done
printf 'fixtures %s\n' "${#names[@]}"
# How the functions of the modules that were written came out (NEPER_WASM_STATS, C183): the
# structured walk, or the dispatch loop for an irreducible function.
cat "$out"/*.wasm.build 2> /dev/null | awk '/^wasm functions /{ f += $3; s += $5; d += $7; i += $9 } END { printf "functions %d structured %d dispatch %d irreducible %d\n", f, s, d, i }' FS='[ ,()]+'
grep -h '^dispatch ' "$out"/*.wasm.build 2> /dev/null | sort | uniq -c | sort -rn | head -20
