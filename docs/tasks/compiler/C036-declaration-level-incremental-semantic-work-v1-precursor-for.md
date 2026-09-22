# C036 — Declaration-level incremental semantic work (v1 precursor for T2 H14)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.87 of 1 |
| queue position | 3 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H14 — declaration-level incremental semantic work** (track: T2.1 (Understand and check, open)):

**T2 tooling-v2 delivery: implemented CPU compiler/query reuse.** Extend H10; do not count
parallel module compilation as incremental function reuse. Spec §12 currently
recompiles a module when its source hash changes. The module may remain the artifact
and linking unit while unchanged internal work is reused.

- Define query identities/results for declaration parsing, lookup, type checking,
  resource/lifetime analysis, generic instantiation, lowering and function emission.
  They share the real semantic engine used by build/check; no approximate checker.
- Record actual dependencies, including absent lookups, generic strategies, safety
  summaries, compile-time inputs and target-dependent layout. Recompute affected
  queries; if their relevant result is unchanged, stop downstream invalidation.
- Separate source/trivia, semantic, debug-location and tooling-provenance identities.
  A comment edit may require source/debug remapping without repeating unaffected
  checking or instruction selection. Do not reuse stale locations to save work.
- Reuse unchanged function emission and relocation descriptions when their full
  dependencies match. Layout/link/debug work may still be necessary; account for
  it separately rather than promising every edit avoids relinking.
- Bound recursive summary convergence and specialization. Public checked summaries
  should permit local analysis without repeatedly inspecting arbitrary callee bodies.
  Exhaustion is an explicit incomplete/failure result, not an optimistic summary.
- Expose structured dirty reasons, dependency paths, cache hits/misses, declarations
  rechecked, instances expanded, functions emitted and bytes/artifacts regenerated.

Acceptance fixtures: comment-only edit; local non-inlined body edit; unrelated
declaration insertion; signature/layout change; fallback protocol insertion/removal;
generic/comptime dependency change; deleted declaration; broken edit then repair;
edit then revert. Specify the expected reused/invalidated units for each fixture.
Assert clean/incremental semantic and deterministic artifact equivalence where the
same build contract promises byte equality. Compare relocated debug mappings too.
Performance closure uses H25, not an assertion that caching is always faster.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Module-level reuse with structured reasons (D363): the build manifest's `incremental` array says per module whether it was kept or rebuilt and why -- stable, edges-hold, edge-changed, source-changed, mode-changed, no-artifact -- asserted by both suites on a warm build and a body edit; a comment-only edit to the compiler rebuilds one module and keeps the rest by their edges; an unchanged import of a changed module is parsed for its declarations alone in a debug build -- header trees, the bodies skipped at the tokens (D392), and in a release build for its declarations and the bodies short enough to be inlining candidates, the oracle's own bound (D421: the edited build's parse 57-62 -> 45-51 ms, resolve 12 -> 6); a kept module's bodies are not checked in either mode (D391); the manifest's `work` and `--stats` count the bodies checked, the modules and the functions lowered -- zero on a warm build over a stable cache, one module and its functions after an edit that changed no interface, asserted by both suites (D405). the manifest's `work` and `--stats` count the declarations the front end held after its declaration pass, which on a warm build over a stable cache is the seeded surface alone -- 28 on the incremental fixture against 403 cold -- pinned by both suites (D446). A body's use of a foreign constant is a value edge (D492): the constant's value is baked into the body, and a warm build after the value changed rebuilds the module as `edge-changed` -- before, only a constant's use in another constant was an edge, and the module folding `if dep.LIMIT > 2` was kept with the old value, a wrong program from a warm build; the `incremental_value` fixture pins it in both modes on both hosts. A layout a body reads is an edge too (D493): every foreign aggregate reachable from the signatures a module references, spelled in its tokens, or held in those aggregates' fields is a signature edge whose hash covers the fields in order, so a reordered record rebuilds the module reading it -- before, the module was kept and read the old offset; `incremental_layout` pins it. A protocol function's absence is an edge (D494): for every such aggregate, the `eq`, `cmp` and `hash` its module does not declare are section 12's negative lookup edges, which nothing had written, so declaring one rebuilds the module whose instance took the supplied rule -- H14's fallback fixture, `incremental_fallback`, was a third wrong program from a warm build before. A declaration deleted from a dependency (D495) fails the warm build as a cold one -- the resolver's diagnostic at the dependent's line, naming the module and the member, exit 1, the previous executable untouched -- where it surfaced as an internal failure; `incremental_deleted` pins it, and the broken-then-repaired and edit-then-revert cases of H14's list were probed and hold. Trivia is apart from the identity (D504): the artifact's source hash leaves every comment's body out, so an edit inside a comment that moves no line keeps the module `stable` and the image is the clean build's, while a line added or removed rebuilds it, since the line tables would be wrong; both suites edit a comment of the incremental fixture in both modes. The identity leaves every line's trailing whitespace out with the comments (D534), so a comment added at a line's end or blanked to spaces keeps the module, and the warm path is held under the turns over the compiler: every comment of every module blanked keeps all thirty-five modules `stable` with the cold image, and one module's literals hoisted or its locals renamed rebuilds that module alone with the cold image, both suites -- a parameter's name being out of the signature identity since D535, where a rename had rebuilt every importer; and the same three edits hold over a cold release build with artifacts (D536), the two modules that inline from the edited one rebuilt by their body edges and the image the cold release build's. The per-module buffers grow to the function (D541): the link's line-row scratch and the writer's code-hash scratch were fixed at sixteen thousand rows and four megabytes, and a function of twenty thousand statements filled the one, twenty-seven thousand the other, both refused as a table full with no cause named; both grow on demand from the worker's arena, the buffer is named in the diagnostic, and both suites build a function of thirty thousand statements

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] declarations from the Interface instead of a lexed tree
- [ ] reuse inside a rebuilt module

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D363` — The build manifest says what an incremental build kept, and why (`docs/decisions.md:7985`)
- `D391` — A kept module's bodies are not checked in a release build either (`docs/decisions.md:8678`)
- `D392` — Header trees: an unchanged import of a changed module is parsed for its declarations alone (`docs/decisions.md:8720`)
- `D405` — The manifest counts what a build did rather than kept (`docs/decisions.md:9021`)
- `D421` — A release build's header trees keep the oracle's candidates (`docs/decisions.md:9348`)
- `D446` — The manifest counts the declarations rechecked (`docs/decisions.md:9791`)
- `D492` — A body's use of a constant is a value edge (`docs/decisions.md:10563`)
- `D493` — A layout a body reads is an edge (`docs/decisions.md:10580`)
- `D494` — A protocol function's absence is an edge (`docs/decisions.md:10598`)
- `D495` — A deleted declaration on the warm path (`docs/decisions.md:10621`)
- `D504` — Trivia apart from the identity (`docs/decisions.md:10747`)
- `D534` — Trailing whitespace out of the identity, and the warm path under the turns (`docs/decisions.md:11165`)
- `D535` — A parameter's name is not its signature (`docs/decisions.md:11182`)
- `D536` — The warm path under the turns, in release (`docs/decisions.md:11193`)
- `D541` — The buffers grow to the function (`docs/decisions.md:11259`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `edge-changed`: `src/tool.e`×1‡

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
