# C043 — Immutable snapshots and correct cache identity (v1 precursor for T2 H15)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.63 of 1 |
| queue position | 6 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H15 — immutable snapshots and correct cache identity** (track: T2.0 (Tooling foundations, open)):

**T2 tooling-v2 delivery: implemented snapshot, overlay and publication contracts.** Extend
H08/H09 across the entire build/query/edit workflow, not only individual fix spans.

- A snapshot identifies exact source bytes, resolution graph, generated inputs,
  compiler/toolchain identity, language/grammar/IR/ABI/summary versions, target/CPU
  features, check/optimization policy and other declared build inputs. Files read
  lazily must be pinned or verified; concurrent filesystem changes cannot create
  a mixed-version snapshot. Never rely on modification time alone.
- Derive stage-specific keys from the relevant subset of inputs. Diagnostic/index
  keys include location/provenance data even when code-generation keys need not.
  Define canonical serialization; process-local intern IDs are not persistent keys.
- Support multi-file in-memory overlays with additions, replacements, moves and
  deletions. Check an overlay before publishing it. Every result identifies its
  snapshot; a stale ID/cursor/edit is rejected or explicitly rebased and revalidated.
- Give concurrent builds isolated temporary outputs and publish complete artifacts
  atomically. Separate targets, CPU features and policies even where today's cache
  filename would collide. Cancellation must preserve the previous valid artifact.
- Define the supported transaction coordination boundary. A source transaction must
  lock or otherwise coordinate participating editors and validate all preconditions;
  arbitrary noncooperating writers cannot be made atomic by a last-second hash
  check. Detect conflicts, preserve recoverable originals, and never silently
  overwrite an intervening edit. Document crash recovery and visibility guarantees.
- Treat xxHash64 as a fast candidate fingerprint, not an unexplained equality
  proof. For local semantic reuse require canonical-input/result equality or a
  specified collision-verification strategy. Shared/untrusted artifacts additionally
  need strong content integrity and explicit trust/provenance rules under H24.

Acceptance: concurrent edits during lazy reads; two policy/CPU-feature builds;
stale multi-file patches; interrupted publication; identical inputs at different
worker counts; injected hash collisions; toolchain/schema change; package-resolution
and generator-input changes. No result may silently mix snapshots or overwrite a
different build identity. Later package support supplies its immutable resolution
identity without requiring M6 implementation now.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Artifacts carry format version, target triple, build mode, source hash and interface/body hashes, and a mismatch is a miss (D205-D214); published by one atomic replace (D343); `--unchecked` is its own mode byte, so a warm build over the other policy's artifacts rebuilds every module as `mode-changed` and is the clean image, both suites both ways (D369); the writing compiler's own hash rides in every artifact and a warm build by another compiler executable rebuilds every module as `compiler-changed`, both suites (D398); a context answer's subject names the program's snapshot -- every module's source hash folded in graph order -- and both suites see it change with an edit (D407). `--inline-cap` rides in the identity's top byte, so a warm build under another cap rebuilds every module as `options-changed`, both suites (D431). `--overlay PATH=FILE` (D502) builds with a module's text from another file -- an editor's buffer -- the overlay's hash the input's and the artifact's identity, the file untouched; both suites build the value fixture over its edit as an overlay and read the file again without it. The key is a candidate, not a proof (D507): every hit on the 64-bit source key is verified by the bytes' SHA-256 when they are the artifact's and by the canonical text's -- comments left out -- when they are not, the artifact carrying both, and `--fault-collision` injects a hit on every key so both suites see a body edit under it rebuilt; the manifest's input digest is the bytes' own for a kept module too, which D504 had left as the artifact's. The overlays reach `check-file` and every query (D524): a check and a `uses-file` over a buffer of the root answer for the buffer with the file untouched, both suites; a plan over overlays hashes the buffers in its preconditions

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] CPU features in the identity
- [ ] the transaction boundary

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D205` — `emit-em-all --incremental` applies the edge rule (`docs/decisions.md:3736`)
- `D214` — The edge rule is settled before lowering, and a kept module is not compiled (`docs/decisions.md:3917`)
- `D343` — An artifact is published by one atomic replace, and a damaged cache is rebuilt (`docs/decisions.md:7368`)
- `D369` — A check policy is a build identity: `--unchecked` artifacts carry their own mode (`docs/decisions.md:8128`)
- `D398` — The compiler that wrote an artifact is part of its identity (`docs/decisions.md:8852`)
- `D407` — A context answer names the program it was computed against (`docs/decisions.md:9071`)
- `D431` — The inline cap is part of the artifact identity (`docs/decisions.md:9550`)
- `D502` — Overlays: a module's text from another file (`docs/decisions.md:10722`)
- `D504` — Trivia apart from the identity (`docs/decisions.md:10747`)
- `D507` — The key is a candidate (`docs/decisions.md:10796`)
- `D524` — Overlays for a check and the queries (`docs/decisions.md:11026`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `unchecked`: `src/em.e`×36‡, `src/main.e`×27‡, `src/check.e`×23‡, `src/tool.e`×11‡, `src/codegen_x64.e`×1‡, `src/lower.e`×1‡, `tests/conformance/reject/safety_unchecked.expected.jsonl`×1
- `mode-changed`: `src/tool.e`×1‡
- `compiler-changed`: `src/tool.e`×1‡
- `inline-cap`: `src/main.e`×6‡, `src/lower.e`×2‡, `src/nir.e`×1†
- `options-changed`: `src/main.e`×1‡, `src/tool.e`×1‡
- `fault-collision`: `src/main.e`×3‡
- `check-file`: `src/main.e`×10‡, `src/tool.e`×6‡, `benchmarks/fuzz/fuzz.py`×3, `benchmarks/scale/profile_check.sh`×3, `scripts/card_examples.py`×2, `scripts/algos/agent_brief.md`×1, `scripts/algos/decisions-pending.md`×1†, `scripts/render_card.py`×1
- `uses-file`: `src/tool.e`×7‡, `src/check.e`×3‡, `src/main.e`×3‡, `scripts/render_card.py`×1, `tests/conformance/tools/plan_generated.x64-linux.expected.jsonl`×1, `tests/conformance/tools/plan_generated.x64-windows.expected.jsonl`×1, `tests/conformance/tools/plan_parameter.x64-linux.expected.jsonl`×1, `tests/conformance/tools/plan_parameter.x64-windows.expected.jsonl`×1

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
