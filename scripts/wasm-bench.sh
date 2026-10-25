#!/bin/bash
# Time the CPU benchmarks (benchmarks/cpu/*) as wasm32-wasi modules under Node (C183).
#
#   scripts/wasm-bench.sh TAG COMPILER [NAME...]   # default: every benchmarks/cpu program
#
# Each program is built with COMPILER, run three times, and the fastest run is printed with the
# module's size, so two compilers (the dispatch loop and the structured one) compare on one
# line each. Output goes to build/wasm-bench/<name>.<TAG>.wasm.
set -u
tag=${1:?usage: wasm-bench.sh TAG COMPILER [NAME...]}
compiler=${2:?usage: wasm-bench.sh TAG COMPILER [NAME...]}
shift 2
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$repo/build/wasm-bench"
mkdir -p "$out"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
    for dir in "$repo"/benchmarks/cpu/*/; do
        [ -f "${dir}src/main.e" ] && names+=("$(basename "$dir")")
    done
fi
for name in "${names[@]}"; do
    wasm="$out/$name.$tag.wasm"
    if ! "$compiler" emit-executable "$repo/benchmarks/cpu/$name/src/main.e" "$repo" wasm32 wasi "$wasm" > "$out/$name.$tag.build" 2>&1; then
        printf '%s\t%s\tdid not build: %s\n' "$name" "$tag" "$(head -c 200 "$out/$name.$tag.build" | tr '\n' ' ')"
        continue
    fi
    best=
    for run in 1 2 3; do
        # The runner times compile, link and run itself (NEPER_WASM_TIME): `date +%s%N` is GNU's.
        NEPER_WASM_TIME=1 node --no-warnings "$repo/scripts/run-wasm.mjs" "$wasm" > "$out/$name.$tag.out" 2> "$out/$name.$tag.err" < /dev/null
        status=$?
        if [ "$status" -ne 0 ]; then best="exit $status"; break; fi
        elapsed=$(sed -n 's/^wasm time: \([0-9]*\) ms$/\1/p' "$out/$name.$tag.err" | tail -n 1)
        if [ -z "$best" ] || [ "$elapsed" -lt "$best" ]; then best=$elapsed; fi
    done
    printf '%s\t%s\t%s ms\t%s bytes\t%s\n' "$name" "$tag" "$best" "$(wc -c < "$wasm" | tr -d ' ')" "$(head -c 80 "$out/$name.$tag.out" | tr '\n' ' ')"
done
