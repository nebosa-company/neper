#!/usr/bin/env bash
# usage: scripts/coverage-run.sh BUILDER OUTDIR [STRIDE]
# Builds HEAD's compiler as a release Linux binary (BUILDER is any Linux neper compiler),
# runs every STRIDE-th fixture under callgrind across targets and commands, and writes
# OUTDIR/runs/*.out and OUTDIR/lines.txt for scripts/coverage_report.py. Run from WSL's own
# disk or /mnt; JOBS=N runs N at once (about 100-300 MB each); MSTRIDE=M runs the cross-target matrix on
# every M-th fixture while x64 linux covers all STRIDE-th ones; UI_STRIDE=U thins the ui_*
# fixtures, which need ~400 MB and minutes each under valgrind. A rerun skips finished runs,
# so delete OUTDIR/runs to start over.
set -u
BUILDER=$(realpath "$1"); OUT=$(realpath -m "$2"); STRIDE=${3:-32}
REPO=$(cd "$(dirname "$0")/.." && pwd)
FIX=$REPO/tests/selfhost/fixtures
T=$OUT/tree; C=$OUT/neper-cov; R=$OUT/runs; B=$OUT/bin
mkdir -p "$R" "$B"

if [ ! -x "$C" ]; then
  rm -rf "$T" && mkdir -p "$T"
  git -C "$REPO" archive HEAD src lib | tar -x -C "$T"
  (cd "$T" && "$BUILDER" emit-executable src/main.e . x64 linux "$C" --release) || { echo "build failed" >&2; exit 1; }
  objdump --dwarf=decodedline "$C" > "$OUT/lines.txt"
fi

JOBS=${JOBS:-1}; MSTRIDE=${MSTRIDE:-1}; UI_STRIDE=${UI_STRIDE:-1}; k=0; u=0
run() {
  local name=$1; shift
  [ -s "$R/$name.out" ] && return
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
  { timeout 1200 valgrind --tool=callgrind --dump-line=yes --callgrind-out-file="$R/$name.out.part" "$C" "$@" >/dev/null 2>&1
    mv "$R/$name.out.part" "$R/$name.out" && echo "$name"; } &
}
pick() { ls "$FIX/$1" | sort | grep -Ev "$2" | awk -v s="$3" -v o="$4" 'NR % s == o'; }

for d in $(pick link '^gfx_chart' "$STRIDE" 0); do
  s=$FIX/link/$d/src/main.e; [ -f "$s" ] || continue; b=$B/$d
  case $d in ui_*) u=$((u+1)); [ $((u % UI_STRIDE)) -eq 0 ] || continue;; esac
  run "link_$d" emit-executable "$s" "$T" x64 linux "$b"
  k=$((k+1)); [ $((k % MSTRIDE)) -eq 0 ] || continue
  run "x64win_$d" emit-executable "$s" "$T" x64 windows "$b.exe"
  run "x64mac_$d" emit-executable "$s" "$T" x64 macos "$b.mx"
  run "a64lin_$d" emit-executable "$s" "$T" aarch64 linux "$b.al"
  run "a64mac_$d" emit-executable "$s" "$T" aarch64 macos "$b.am"
  run "wasm_$d" emit-executable "$s" "$T" wasm32 wasi "$b.wasm"
  run "rel_$d" emit-executable "$s" "$T" x64 linux "$b.rel" --release -j 4
  run "em_$d" emit-em "$s" "$T" x64 linux "$b.em"
done
for d in $(pick check '^$' $((STRIDE / 2 + 1)) 0); do
  s=$FIX/check/$d/src/main.e; [ -f "$s" ] || continue
  run "check_$d" check-file "$s" "$T" x64 linux
done
# gpu_* fixtures (glsl.e, most of spirv.e) abort valgrind with an aspacem out_of_memory, so they are not run here.
for d in advanced aggregate; do
  s=$FIX/link/$d/src/main.e; [ -f "$s" ] || continue
  run "fmt_$d" fmt-file "$s" --check
  run "tokens_$d" tokens "$s"
  run "parse_$d" parse "$s"
  run "resolve_$d" resolve-file "$s" "$T" x64 linux
  run "nir_$d" nir-file "$s" "$T" x64 linux
  run "codegen_$d" codegen-file "$s" "$T" x64 linux
  run "obj_$d" object-file "$s" "$T" x64 windows
  run "objlin_$d" emit-object "$s" "$T" x64 linux "$B/$d.o"
  run "obja64_$d" emit-object "$s" "$T" aarch64 linux "$B/$d.a64.o"
  run "imgnone_$d" emit-executable "$s" "$T" aarch64 none "$B/$d.img"
  run "imgneperos_$d" emit-executable "$s" "$T" aarch64 neperos "$B/$d.nos"
  run "wthreads_$d" emit-executable "$s" "$T" wasm32 wasi "$B/$d.wt.wasm" --threads --source-map
  run "dis_$d" dis-file "$s" "$T" x64 linux --json
  run "exp_$d" emit-executable "$s" "$T" x64 linux "$B/exp_$d" --explain --json --stats-full --time
done
wait
echo "done runs=$(ls "$R"/*.out | wc -l)"
