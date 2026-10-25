#!/bin/bash
# Build every link fixture for wasm32-wasi and for the host, run both, and compare exit status
# and standard output (D5213). Each fixture is one of
#   pass     the same exit status and the same stdout
#   fail     it ran and differed
#   refused  the WebAssembly emitter did not write a module (the reason is the second column)
#   invalid  the module was written and Node would not compile or link it
#   skipped  the host build does not run clean either, so there is nothing to compare with
#
#   scripts/wasm-sweep.sh                 # every fixture
#   scripts/wasm-sweep.sh -j 4 NAME...    # these, four at a time
#   scripts/wasm-sweep.sh --release       # both builds with --release
#   scripts/wasm-sweep.sh --host neper-host   # run the modules through lib/wasm/neper-host.js (D5678), not run-wasm.mjs
#   scripts/wasm-sweep.sh --host both         # through both, building once; the second runner's verdicts go to results-second.tsv
#
# The compiler is build/<host>/neper-try, or the one NEPER_COMPILER names. Results go to
# build/wasm-sweep/results.tsv and the counts to the end of the run.
set -u
jobs=1
release=
runner=run-wasm
names=()
while [ $# -gt 0 ]; do
    case "$1" in
        -j) shift; jobs=${1:?-j needs a number} ;;
        --release) release=--release ;;
        --host) shift; runner=${1:?--host needs run-wasm, neper-host or both} ;;
        *) names+=("$1") ;;
    esac
    shift
done
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)" in
  Linux) host_os=linux;  compiler="$repo/build/linux/neper-try";       ext="" ;;
  *)     host_os=windows; compiler="$repo/build/windows/neper-try.exe"; ext=".exe" ;;
esac
compiler=${NEPER_COMPILER:-$compiler}
out=${WASM_SWEEP_OUT:-$repo/build/wasm-sweep}
mkdir -p "$out"
rm -f "$out/results-second.tsv"
if [ ${#names[@]} -eq 0 ]; then
    for dir in "$repo"/tests/selfhost/fixtures/link/*/; do
        [ -f "${dir}src/main.e" ] && names+=("$(basename "$dir")")
    done
fi

one() {
    name=$1
    source="$repo/tests/selfhost/fixtures/link/$name/src/main.e"
    host="$out/$name$ext"
    wasm="$out/$name.wasm"
    rm -f "$out/$name".*
    if ! "$compiler" emit-executable "$source" "$repo" x64 "$host_os" "$host" $release > "$out/$name.host.build" 2>&1; then
        printf '%s\tskipped\thost build\n' "$name"
        return
    fi
    timeout 120 "$host" > "$out/$name.host.out" 2> /dev/null < /dev/null
    host_status=$?
    rm -f "$host"
    if ! "$compiler" emit-executable "$source" "$repo" wasm32 wasi "$wasm" $release > "$out/$name.wasm.build" 2>&1; then
        printf '%s\trefused\t%s\n' "$name" "$(grep -m1 -o 'E-[A-Z]*-[0-9]*.*' "$out/$name.wasm.build" | cut -c1-200)"
        return
    fi
    # With --host both the first runner's verdict goes to standard output, the second's to $out/results-second.tsv.
    first=1
    for run_with in $runners; do
        case $run_with in neper-host) runner_path="$repo/lib/wasm/neper-host.js" ;; *) runner_path="$repo/scripts/run-wasm.mjs" ;; esac
        timeout 120 node --no-warnings "$runner_path" "$wasm" > "$out/$name.wasm.out" 2> "$out/$name.wasm.err" < /dev/null
        wasm_status=$?
        if [ "$wasm_status" -eq 125 ]; then
            verdict=$(printf '%s\tinvalid\t%s' "$name" "$(head -c 300 "$out/$name.wasm.err" | tr '\n' ' ')")
        elif [ "$wasm_status" -eq "$host_status" ] && cmp -s "$out/$name.host.out" "$out/$name.wasm.out"; then
            verdict=$(printf '%s\tpass\t' "$name")
        else
            verdict=$(printf '%s\tfail\thost exit %s, wasm exit %s' "$name" "$host_status" "$wasm_status")
        fi
        if [ -n "$first" ]; then printf '%s\n' "$verdict"; first=; else printf '%s\n' "$verdict" >> "$out/results-second.tsv"; fi
    done
    rm -f "$wasm"
}
export -f one
export NEPER_WASM_STATS=${NEPER_WASM_STATS:-1}
case $runner in both) runners="neper-host run-wasm" ;; *) runners=$runner ;; esac
export runners
export repo host_os compiler out ext release

printf '%s\n' "${names[@]}" | xargs -P "$jobs" -I{} bash -c 'one {}' | tee "$out/results.tsv"
printf '\n'
for kind in pass fail refused invalid skipped; do
    printf '%s %s\n' "$kind" "$(grep -c "	$kind	" "$out/results.tsv")"
done
printf 'fixtures %s\n' "${#names[@]}"
# How the functions of the modules that were written came out (NEPER_WASM_STATS, C183): the
# structured walk, or the dispatch loop for an irreducible function.
cat "$out"/*.wasm.build 2> /dev/null | awk '/^wasm functions /{ f += $3; s += $5; d += $7; i += $9 } END { printf "functions %d structured %d dispatch %d irreducible %d\n", f, s, d, i }' FS='[ ,()]+'
grep -h '^dispatch ' "$out"/*.wasm.build 2> /dev/null | sort | uniq -c | sort -rn | head -20
