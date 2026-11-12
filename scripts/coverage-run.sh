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
  { cd "${RD:-.}" && timeout 1200 valgrind --tool=callgrind --dump-line=yes --callgrind-out-file="$R/$name.out.part" "$C" "$@" >/dev/null 2>&1
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
# The tooling surface (tool.e, the project and query commands of main.e) and the encoder self tests.
CT=$REPO/tests/conformance/tools
run self_test self-test
run tool_tokens tokens --json --path every_kind.e "$REPO/tests/conformance/tokens/every_kind.e"
run tool_parse parse --json --path recovery.e "$REPO/tests/conformance/parse/recovery.e"
run tool_fmt fmt-file "$CT/fmt.e" --json
run tool_fmtreject fmt-file "$CT/fmt_reject.e" --json
run tool_index index-file "$CT/index.e" "$T" x64 linux --json
run tool_explain explain-file "$CT/explain.e" "$T" x64 linux --json
run tool_explainarm explain-file "$CT/explain_arm.e" "$T" x64 linux --json
run tool_context context-file "$CT/explain.e" "$T" x64 linux --json --symbol explain.main --budget 8
run tool_uses uses-file "$CT/explain.e" "$T" x64 linux --json --symbol explain.same
run tool_rename plan-rename-file "$CT/explain.e" "$T" x64 linux --json --symbol explain.same --to alike
run tool_manifest build-manifest-file "$CT/manifest.e" "$T" x64 linux --json
run tool_batch query-batch "$CT/contract.e" "$T" x64 linux --json --batch "$CT/batch.txt"
run tool_dis dis-file "$CT/dis.e" "$T" x64 linux --json
run tool_eval eval '1usize << 40' "$T" x64 linux
run tool_run run "$CT/run_trap_module/src/main.e" "$T" x64 linux "$B/trap.out" --json
run tool_testfile test-file "$CT/test.e" "$T" x64 linux "$B" --json
run tool_testproj test-project "$CT/test_project" "$T" x64 linux "$B" --json
run tool_checkproj check-project "$CT/check_project" "$T" x64 linux "$B" --json
run tool_indexproj index-project "$CT/index_project" "$T" x64 linux "$B" --json
# VEX and the wider moves are reached only above the x64-v1 baseline (D765).
for d in simd_codec simd_convert_lanes simd_lanes simd_masked_bounds simd_ops_reference gp09_simd_hex fmt_sse advanced aggregate; do
  s=$FIX/link/$d/src/main.e; [ -f "$s" ] || continue
  run "cpuv2_$d" emit-executable "$s" "$T" x64 linux "$B/$d.v2" --cpu x64-v2
  run "cpuv3_$d" emit-executable "$s" "$T" x64 linux "$B/$d.v3" --cpu x64-v3
  run "cpuv3rel_$d" emit-executable "$s" "$T" x64 windows "$B/$d.v3.exe" --cpu x64-v3 --release
done
# Remaining commands of main.e. Plans and artifacts are made once with the unprofiled compiler.
P=$OUT/prep; rm -rf "$P"; mkdir -p "$P/scratch/src" "$P/em" "$P/em2"
(cd "$CT" && "$C" plan-rename-file explain.e "$T" x64 linux --json --symbol explain.same --to alike > "$P/plan.jsonl")
cp "$CT/explain.e" "$P/scratch/src/"
"$C" emit-em-all "$FIX/link/function_values/src/main.e" "$T" x64 linux "$P/em" >/dev/null 2>&1
"$C" emit-executable "$FIX/link/function_values/src/main.e" "$T" x64 linux "$P/fv" >/dev/null 2>&1
"$C" emit-em-all "$FIX/link/element_cmp/src/main.e" "$T" x64 linux "$P/em2" >/dev/null 2>&1
RD=$CT run m_apply apply-plan "$P/plan.jsonl" --root "$P/scratch/src"
wait
RD=$CT run m_applyjson apply-plan "$P/plan.jsonl" --root "$P/scratch/src" --json
RD=$CT run m_applymiss apply-plan "$P/nothing.jsonl" --root "$P/scratch/src" --json
run m_cmpmiss compare-manifests "$P/a.json" "$P/b.json"
run m_info info --json
run m_infocap info --json --capabilities
run m_scan scan-file "$REPO/src/lex.e"
run m_scanmiss scan-file "$P/missing.e"
run m_parsefile parse-file "$FIX/source-load.e"
run m_sharedlib emit-shared-library "$FIX/link/shared_library/src/main.e" "$T" x64 linux "$B/lib.so"
RD=$CT run m_impact test-impact-file test_project/src/nested/deep.e "$T" x64 linux --json --changed nowhere
RD=$CT run m_addparam plan-add-parameter-file contract.e "$T" x64 linux --json --symbol contract.total --parameter 'scale: i64' --argument 1i64
RD=$CT run m_addparams plan-add-parameter-file contract.e "$T" x64 linux --json --symbol contract.total --parameter 'scale: i64' --arguments parameter_sites.txt
RD=$CT run m_signature plan-change-signature-file signature.e "$T" x64 linux --json --symbol signature.adjust --order 2,0,1
RD=$CT run m_signested plan-change-signature-file signature_nested.e "$T" x64 linux --json --symbol signature_nested.pair --order 1,0
RD=$CT run m_replace plan-replace-expression-file contract.e "$T" x64 linux --json --span 693:703 --with 131072usize
RD=$CT run m_replacebad plan-replace-expression-file contract.e "$T" x64 linux --json --span 693:700 --with 1usize
run m_linkem link-em "$B/fv.linked" "$P/em/main.x64-linux.em" "$P/em/ops.x64-linux.em"
run m_validate validate-em "$P/em/main.x64-linux.em"
run m_edge check-em-edge "$P/em2/main.x64-linux.em" "$P/em2/shapes.x64-linux.em"
run m_emerr check-em-errors "$P/em2/main.x64-linux.em" "$P/em2/shapes.x64-linux.em"
run m_manifestem manifest-em "$P/em/main.x64-linux.em"
# Short forms run in a project directory (D283).
RD=$CT/test_project run s_test test --json
RD=$CT/check_project run s_check check --json
RD=$CT/index_project run s_index index --json
RD=$CT/manifest_project run s_manifest build-manifest --json
RD=$CT/index_project run s_fmt fmt --check --json
RD=$CT/index_project run s_dis dis --json
RD=$CT/check_project run s_build build
RD=$CT/test_project run s_run run
# CLI error paths.
run e_none
run e_unknown frobnicate
run e_unknown_json frobnicate --json
run e_badtarget check-file "$FIX/link/advanced/src/main.e" "$T" x99 linux
run e_bados check-file "$FIX/link/advanced/src/main.e" "$T" x64 plan9
run e_nofile check-file "$P/missing.e" "$T" x64 linux
run e_langver check-file "$FIX/link/advanced/src/main.e" "$T" x64 linux --language-version 9.9
run e_langver_json check-file "$FIX/link/advanced/src/main.e" "$T" x64 linux --json --language-version 9.9
run e_shortbad check --bogus
run e_arena emit-executable "$FIX/link/advanced/src/main.e" "$T" x64 linux "$B/e.out" --arena nonsense
run e_gpu emit-executable "$FIX/link/advanced/src/main.e" "$T" x64 linux "$B/e.out" --gpu bogus
run e_contextbad context-file "$CT/explain.e" "$T" x64 linux --json --symbol nothing.here
run e_syntax check-file "$REPO/tests/conformance/reject/$(ls "$REPO/tests/conformance/reject" | grep '\.e$' | head -1)" "$T" x64 linux --json
wait
echo "done runs=$(ls "$R"/*.out | wc -l)"
