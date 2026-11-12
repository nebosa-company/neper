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
# More of tool.e: contexts, impact, renames of types and fields, manifests, formatting (the suite's own invocations).
for s in context_moves.open_and_close context_moves.width context_moves.views context_moves.ends; do
  RD=$CT run "t_ctx_$s" context-file context_moves.e "$T" x64 linux --json --symbol $s --budget 16
done
for s in subjects.LIMIT subjects.counter; do RD=$CT run "t_ctx_$s" context-file subjects.e "$T" x64 linux --json --symbol $s --budget 8; done
for s in contract.main contract.bump contract.first contract.total; do RD=$CT run "t_ctx_$s" context-file contract.e "$T" x64 linux --json --symbol $s --budget 16; done
RD=$CT run t_ctx_module context-file contract.e "$T" x64 linux --json --module contract --budget 64 --bytes 3000
RD=$CT run t_ctx_modgpu context-file contract.e "$T" x64 linux --json --module e.gpu --budget 64
RD=$CT run t_ctx_modunchecked context-file contract.e "$T" x64 linux --json --module contract --unchecked --budget 64
RD=$CT run t_ctx_unchecked context-file contract.e "$T" x64 linux --json --symbol contract.main --unchecked --budget 64
RD=$CT run t_ctx_project context-file test_project/src/nested/deep.e "$T" x64 linux --json --module helper --budget 64
RD=$CT run t_ctx_partial context-file query_partial.e "$T" x64 linux --json --symbol query_partial.later
RD=$CT run t_ctx_tiny context-file explain.e "$T" x64 linux --json --symbol explain.main --budget 1
RD=$CT run t_impact_why test-impact-file test_project/src/nested/deep.e "$T" x64 linux --json --changed helper --why
RD=$CT run t_impact_deep test-impact-file test_project/src/nested/deep.e "$T" x64 linux --json --changed deep
for c in plan_rename_type:deep.pick:choose plan_rename_type:main.twice:double plan_rename_type:deep.Rec:Pair plan_rename_type:deep.rec_cmp:compare errors_project:faults.Stalled:Blocked; do
  d=${c%%:*}; r=${c#*:}; RD=$CT/$d run "t_ren_${d}_${r%%:*}" plan-rename-file src/main.e "$T" x64 linux --json --symbol ${r%%:*} --to ${r#*:}
  RD=$CT/$d run "t_use_${d}_${r%%:*}" uses-file src/main.e "$T" x64 linux --json --symbol ${r%%:*}
done
RD=$CT run t_ren_field plan-rename-file contract.e "$T" x64 linux --json --symbol contract.Counter.hits --to count
RD=$CT run t_use_field uses-file contract.e "$T" x64 linux --json --symbol contract.Counter.hits
RD=$CT run t_sig_remove plan-change-signature-file signature_remove.e "$T" x64 linux --json --symbol signature_remove.adjust --order 0,1
RD=$CT run t_sig_remove2 plan-change-signature-file signature_remove.e "$T" x64 linux --json --symbol signature_remove.adjust --order 0,2
RD=$CT run t_sig_dup plan-change-signature-file signature.e "$T" x64 linux --json --symbol signature.adjust --order 0,0
RD=$CT run t_param_bump plan-add-parameter-file contract.e "$T" x64 linux --json --symbol contract.bump --parameter 'by: i64' --argument 1i64
for f in fold_const explain_fold explain_when; do RD=$CT run "t_explain_$f" explain-file $f.e "$T" x64 linux --json; done
RD=$CT run t_manifest_gen build-manifest-file generated_map.e "$T" x64 linux --json
RD=$CT run t_manifest_proj build-manifest-file manifest_project/src/main.e "$T" x64 linux --json
RD=$CT run t_manifest_unsafe build-manifest-file manifest_unsafe/src/main.e "$T" x64 linux --json
RD=$CT run t_batch_broken query-batch query_broken.e "$T" x64 linux --json --batch batch_broken.txt
RD=$CT run t_batch_mem query-batch contract.e "$T" x64 linux --json --batch batch_memory.txt
RD=$CT run t_batch_unchecked query-batch contract.e "$T" x64 linux --json --batch batch_unchecked.txt --unchecked
RD=$CT run t_fmt_check fmt-file fmt_check.e --check
RD=$CT run t_fmt_stmts fmt-file fmt_statements.e --json
RD=$CT run t_fmt_plain fmt-file fmt.e
RD=$CT run t_fmt_miss fmt-file no-such-operand.e --check
for c in $(ls "$REPO/tests/conformance/format" | grep -v expected | sed 's/\.e$//'); do
  run "t_format_$c" fmt-file "$REPO/tests/conformance/format/$c.e"
  run "t_formatchk_$c" fmt-file "$REPO/tests/conformance/format/$c.e" --check --json
done
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
# Diagnostics as records: every check fixture again under --json (emit_diagnostic and the printers).
for d in $(ls "$FIX/check" | sort); do
  s=$FIX/check/$d/src/main.e; [ -f "$s" ] || continue
  run "checkjson_$d" check-file "$s" "$T" x64 linux --json
done
# Incremental rebuilds (section 12): a cold build, a warm one, then each edit the fixture ships.
wait
for d in incremental incremental_generic incremental_layout incremental_generic_layout incremental_value incremental_deleted incremental_fallback incremental_reset; do
  S=$P/inc_$d; rm -rf "$S"; mkdir -p "$S/src" "$S/art"; cp "$FIX/link/$d/src/"*.e "$S/src/"
  "$C" emit-em-all "$S/src/main.e" "$T" x64 linux "$S/art" --release >/dev/null 2>&1
  run "inc_${d}_same" emit-em-all "$S/src/main.e" "$T" x64 linux "$S/art" --release --incremental; wait
  for e in $(ls "$FIX/link/$d/edits" 2>/dev/null | sort); do
    b=${e%.e}; b=${b%%_*}; cp "$FIX/link/$d/edits/$e" "$S/src/$b.e"
    run "inc_${d}_${e%.e}" emit-em-all "$S/src/main.e" "$T" x64 linux "$S/art" --release --incremental; wait
  done
done
# The apply-plan transaction (D1519): held lock, a death after one file, recovery, a writer that
# skips the lock, a plan over two programs, a stale file in the second, a foreign root.
A=$CT/uses_alias; AP=$P/alias.jsonl
(cd "$A" && "$C" plan-rename-file src/main.e "$T" x64 linux --json --symbol deep.pick --to choose > "$AP")
fresh() { rm -rf "$P/$1"; cp -r "$A" "$P/$1"; }
fresh txn_held; mkdir -p "$P/txn_held/src/.neper"; : > "$P/txn_held/src/.neper/transaction.lock"
run x_held apply-plan "$AP" --root "$P/txn_held/src"
fresh txn_die
run x_die apply-plan "$AP" --root "$P/txn_die/src" --fault-apply 1; wait
run x_dieagain apply-plan "$AP" --root "$P/txn_die/src"; wait
run x_recover apply-plan --recover --root "$P/txn_die/src"; wait
run x_reapply apply-plan "$AP" --root "$P/txn_die/src"; wait
fresh txn_edit
run x_edit apply-plan "$AP" --root "$P/txn_edit/src" --fault-edit 1
fresh txn_stale
run x_first apply-plan "$AP" --root "$P/txn_stale/src"; wait
run x_stale apply-plan "$AP" --root "$P/txn_stale/src" --json; wait
run x_foreign apply-plan "$CT/plan_foreign_root.jsonl" --root "$P/txn_stale/src" --json
for side in one two three four five; do fresh multi_$side; done
echo '// changed' >> "$P/multi_five/src/deep.e"
run x_multi apply-plan "$AP" --root "$P/multi_one/src" --also "$AP" --root "$P/multi_two/src" --json
run x_multisame apply-plan "$AP" --root "$P/multi_three/src" --also "$AP" --root "$P/multi_three/src"
run x_multistale apply-plan "$AP" --root "$P/multi_four/src" --also "$AP" --root "$P/multi_five/src"
run x_noroot apply-plan "$AP"
run x_badplan apply-plan "$REPO/README.md" --root "$P/multi_one/src"
wait
wait
echo "done runs=$(ls "$R"/*.out | wc -l)"
