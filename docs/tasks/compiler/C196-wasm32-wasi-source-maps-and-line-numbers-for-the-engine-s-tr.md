# C196 — wasm32-wasi source maps, and line numbers for the engine's traps

| field | value |
|---|---|
| category | compiler / WebAssembly |
| score | 0.00 of 1 |
| queue position | 103 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Design D5683. Needs nothing (if C194 has moved the runner, change lib/wasm/run-wasm.mjs). Build: `--source-map` on emit-executable wasm32 wasi writes OUT.map (Source Map v3: sources as trap records spell paths, names empty, one generated line whose columns are byte offsets in the module file; an entry at the first byte of each NIR instruction whose `site.line` differs from the previous entry's) and a `sourceMappingURL` custom section after the name section; off by default. The runner, and neper-host.js when present, adds path:line from the map to each `wasm-function[N]:0xOFFSET` frame of an engine error when OUT.map lies beside the module. Acceptance: (1) tests/wasm/null_call (not a link fixture: native ends it with an access violation, D5604), a null function value called two frames deep, built with --source-map: the runner's error names the call's src/main.e line in its first frame; checked by the D5651 blocks of run.sh and run.ps1. (2) `wasm-tools validate` passes on that module. (3) Without the flag every sweep module is byte-identical to the compiler before. DWARF stays unwritten (D5684)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `source-map`: `src/main.e`×3‡, `src/tool.e`×1‡, `tests/conformance/tools/combined_inputs.e.map.json`×1, `tests/conformance/tools/combined_stale.e.map.json`×1, `tests/conformance/tools/generated_map.e.map.json`×1, `tests/conformance/tools/hand_edited.e.map.json`×1, `tests/conformance/tools/manifest_map.x64-linux.expected.jsonl`×1, `tests/conformance/tools/manifest_map.x64-windows.expected.jsonl`×1
- `site.line`: `src/codegen_x64.e`×6‡, `src/codegen_a64.e`×5†, `src/spirv.e`×4‡, `src/wasm_code.e`×2†, `src/em.e`×1‡, `src/lower.e`×1‡, `src/nir.e`×1†

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
