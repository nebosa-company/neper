# C032 — Checked optimized builds and unsafe boundaries (M2.5-core H03)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.94 of 1 |
| queue position | 1 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H03 — checked optimized execution and unsafe boundaries** (track: M2.5-core (Language safety and GPU contracts, in_progress)):

The closure design for this requirement is `docs/m25-h03-checked-release.md`; read it after the section below.

Separate optimization from check removal. Recommend that ordinary optimized builds
retain bounds, null, tag, alignment and defined invalid-state checks wherever the
representation supports them. Eliminate redundant checks only with a valid proof.
Enumerate the complete revised check table; avoid the misleading label "safe
release" until the claimed checked subset has a defensible safety argument.

- A null check cannot establish pointer liveness; a bounds check cannot establish
  that a slice's base/length were validly constructed. H01/H02 and trusted boundary
  validation are prerequisites for stronger claims.
- Specify explicit unsafe operations and caller obligations for raw dereference,
  casts, external calls, uninitialized reads, packed/unaligned access and unchecked
  indexing. Unsafe is neither a guarantee of correctness nor blanket permission
  for unrelated operations in a callee.
- Preserve mandatory checks even in unsafe code where the contract requires them.
  Replace/reconcile `@nocheck` deliberately; do not create overlapping switches
  with unclear precedence. Report every suppressed check and its source origin.
- Keep existing defined arithmetic choices unless independently changed and
  versioned. Check retention alone does not reconcile debug overflow traps with
  release wrapping. Record build mode as context until each divergence is resolved.
- Invalid reference/resource representations and invalid `zero`/`undef` values
  must not enter checked code unnoticed. Definite-initialization checks need
  field/element handling or conservative rejection; byte patterns are not proof.
- Inventory unchecked dependencies in the build manifest and context output.
  A checked caller does not sanitize an unchecked callee. Version/cache identity
  includes safety policy, ABI and summary format.

Acceptance: optimized and debug runs for every check-table row, with expected
differences named; equivalent safe-program results; failed checks before memory
side effects; codegen tests for eliminated and retained checks. Audit emitted loads,
stores and optimizer assumptions, including foreign callbacks and packed records.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A release build keeps `bounds`, `null`, `tag` and `align` (D355, `m25-h03-checked-release.md`); `@nocheck` is the explicit unchecked operation in every mode and `--unchecked` the whole-image one; the manifest lists every `@unsafe` function and `@nocheck` block and the check policy; a fixture traps in release on all three memory rows; the first bounds proof (`while i < x.len`, D356) its guard form (`if i < x.len`, D377), its conjunct form (the leftmost `i < x.len` of an `&&`, D378) its early-exit form (`if i >= x.len { ret }` proving the rest of the block, D380) the width proof (a `u8` widened, a literal mask or offset into an array of known length, D384) the slack form (`while at + K <= x.len` proving `x[at + j]`, D385) its early-exit form (`if at + K > x.len { ret }`, D387) and the equal-length form (`if a.len != b.len { ret }` proving the other slice, D390; 544 checks elided in the compiler's own build) with their eliminated and retained fixtures and a `--stats` count, which also found and closed the inlined bodies' lost checks. the second-local form (`let n = x.len` then `while i < n`, D452) with its eliminated and retained fixtures; the field base (`while i < s.items.len` proving `s.items[i]` through a local struct, or through a pointer when the body calls nothing, D462; fixture 76 -> 80, the compiler's own build 552 -> 576) with its eliminated fixtures and a retained one whose call empties the slice. An invalid `undef` cannot be made (D475): `= undef` of a type that admits only its members -- `bool`, an enum, a tagged union, a struct or array holding one -- is refused as E-SAFETY-0017 at compile time, so the `invalid` check release does not keep is never owed for it. A named constant is a literal to the proofs (D527): `at + LIMIT < len` elides the check `at + 3usize < len` elided, bare or through a `use` qualifier, where a constant had been no bound -- found by the metamorphic turn over the compiler, whose image grew by the retained checks when its literals were hoisted, and byte-identical since, which both suites hold; and a field spelled like a local is not a write to the local in the proofs' scans (D528), which the renamed-locals turn found keeping a check. The `invalid` representation check reaches every direct `mem.bitcast` to `bool`, an enum or a tagged union in debug and release (D548, D554), and the fixture proves `--unchecked` removes it. Definite initialization of the references an `undef` value holds (D918): `= undef` of a type holding a slice, a pointer, a function value or a `str` at any depth is E-SAFETY-0021 unless every reference-holding field is written -- or the whole value assigned -- before the value is read, scanned from the declaration to the end of the enclosing block, with `&x` not a read, only a write at the declaration's own depth counted, and more than 32 reference fields refused rather than tracked; `accept/safety_undef_written.e` collects the four written forms and `reject/safety_undef_reference.e` reads a slice field that was never written and `reject/safety_undef_branch.e` one written only inside an `if`. A pointer cast keeps a representation (D919): `mem.cast[*P]` to a `P` that admits only its members is E-SAFETY-0022 unless its source points to `P` or `void`, it is a placement whose next mention writes the whole value, or it stands in `@nocheck`; the library's fifteen field-by-field placements now write the whole state first and `e.ui.widget`'s typed state lookup is an `@nocheck` block naming its obligation; `accept/safety_cast_representation.e`, `reject/safety_cast_representation.e` and `reject/safety_cast_placement.e`

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a field base through a pointer across a call (the compiler's commonest guard, `c.tokens[at]`, which is also under a count field rather than the slice's length), representations introduced through a foreign write
- [ ] the load/store audit
- [ ] cold wall +16-29% and image +40% against budgets of +10%/+5%

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D355` — A release build is a checked build, and every unsafe boundary is listed (`docs/decisions.md:7776`)
- `D356` — The first bounds proof, and the inlined bodies that had lost their checks (`docs/decisions.md:7803`)
- `D377` — The guard form of the bounds proof: `if i < x.len` proves its block (`docs/decisions.md:8383`)
- `D378` — The conjunct form of the bounds proof: the leftmost `i < x.len` of an `&&` proves the rest (`docs/decisions.md:8402`)
- `D380` — The early-exit form of the bounds proof: `if i >= x.len { ret }` proves the rest of the block (`docs/decisions.md:8445`)
- `D384` — The width proof: an index that cannot reach the array's length (`docs/decisions.md:8541`)
- `D385` — The slack form of the bounds proof: `while at + K <= x.len` proves `x[at + j]` (`docs/decisions.md:8560`)
- `D387` — The warm build profiled: the byte sinks copy whole, and the hash's loads are proven (`docs/decisions.md:8599`)
- `D390` — Two slices of one length: `if a.len != b.len { ret }` proves the other (`docs/decisions.md:8659`)
- `D452` — The bounds proof through a second local (`docs/decisions.md:9884`)
- `D462` — The bounds proof through a field base (`docs/decisions.md:10036`)
- `D475` — An invalid `undef` is refused (`docs/decisions.md:10306`)
- `D527` — A named constant is a literal to the proofs (`docs/decisions.md:11064`)
- `D528` — The index names every reference (`docs/decisions.md:11079`)
- `D548` — Bytes read as a bool or an enum are checked (`docs/decisions.md:11367`)
- `D554` — The tagged union's punned tag (`docs/decisions.md:11462`)
- `D918` — Definite initialization of the references an `undef` value holds (`docs/decisions.md:18081`)
- `D919` — A pointer cast keeps a representation (`docs/decisions.md:18122`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `@nocheck`: `src/tool.e`×4‡, `src/nir.e`×3†, `tests/conformance/tools/manifest_unsafe/src/main.e`×3, `src/main.e`×2‡, `tests/conformance/accept/safety_cast_representation.e`×2, `lib/e/ui/widget.e`×1‡, `src/check.e`×1‡, `src/em.e`×1‡
- `unchecked`: `src/em.e`×36‡, `src/main.e`×27‡, `src/check.e`×23‡, `src/tool.e`×11‡, `src/codegen_x64.e`×1‡, `src/lower.e`×1‡, `tests/conformance/reject/safety_unchecked.expected.jsonl`×1
- `@unsafe`: `src/tool.e`×6‡, `lib/e/os.linux.e`×2‡, `lib/e/os.windows.e`×2‡, `src/check.e`×2‡, `tests/conformance/tools/manifest_unsafe/src/main.e`×2, `lib/e/proc.e`×1, `src/main.e`×1‡, `tests/conformance/reject/safety_opaque.expected.jsonl`×1
- `mem.bitcast`: `lib/e/math.e`×26†, `lib/e/str.e`×16†, `lib/e/fmt/cbor.e`×13, `lib/e/math/float.e`×12, `lib/e/gfx/scene.e`×9‡, `lib/e/os.windows.e`×7‡, `lib/e/audio.e`×6, `lib/e/fmt/bson.e`×6
- `e.ui.widget`: `lib/e/ui/accessibility.e`×2, `lib/e/ui/control.e`×2‡, `lib/e/ui/animation.e`×1, `lib/e/ui/app.e`×1†, `lib/e/ui/collection.e`×1†, `lib/e/ui/navigation.e`×1†, `lib/e/ui/overlay.e`×1†, `lib/e/ui/testing.e`×1

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
