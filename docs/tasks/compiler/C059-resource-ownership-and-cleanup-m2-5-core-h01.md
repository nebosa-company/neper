# C059 — Resource ownership and cleanup (M2.5-core H01)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.99 of 1 |
| queue position | 14 of 46 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H01 — ownership, resource states and cleanup** (track: M2.5-core (Language safety and GPU contracts, in_progress)):

The closure design for this requirement is `docs/m25-h01-ownership.md`; read it after the section below.

Adopt a small compiler-enforced resource model for `Arena`, builders and owned OS
handles. An affine value permits at most one use of ownership; requiring eventual
cleanup is a separate obligation. The earlier proposal conflated those properties.
Specify both rather than promising that non-copyability prevents leaks.

Required rules:

- Distinguish owned resources, temporary borrows and explicitly duplicated
  resources. An OS duplication operation creates a new ownership identity; copying
  handle bits does not. Immutability of a binding does not imply unique ownership.
- Ownership transfer must be visible in signatures and source. Define argument
  evaluation order, moves into aggregates, return values, reassignment and joins
  after branches/loops. Moving an object cannot invalidate outstanding borrows.
- Resource containment propagates non-copyability through structs, arrays,
  tagged unions, generics and slices of owned resources. Disallow partial moves in
  the initial design unless field-sensitive state tracking is fully specified.
- Define valid states for `zero`, `undef`, failed construction and partially built
  containers. Generic copy, serialization, reflection, `mem.bitcast` and pointer
  casts must not manufacture ownership or duplicate a resource in checked code.
- Every normal scope exit, `ret`, `try`, `break` and `continue` must discharge live
  cleanup obligations or transfer them. Keep cleanup visible through `defer` or an
  explicit scope construct; do not add arbitrary hidden user destructors.
- Resolve when deferred arguments are captured and whether scheduling a close
  reserves consumption. Reject a later move/close that would make the deferred
  operation invalid. Define reverse cleanup order and partial-acquisition behavior.
- Classify consuming operations on both success and failure. A failed close/join
  cannot leave ownership unspecified, invite a blind retry of a reused OS handle,
  or lose the primary error when cleanup also fails.
- Traps, process exit and forced termination retain a separate contract: no promise
  that every resource is cleaned up after an abort. Never use cleanup as the sole
  mechanism preventing another thread from accessing freed storage.

Resource representations need protection: currently every module declaration is
exported and handles expose ordinary data. Evaluate narrowly opaque resource
representations/access restrictions before introducing a general visibility system.
Raw imports/exports of handles belong to audited unsafe wrappers. Resource identity
must survive safe API boundaries without requiring a global release-mode registry.

Acceptance: reject duplicate ownership, deferred double-close, use-after-move,
resource-copy through a generic/aggregate and forgotten required cleanup; accept
transfer, explicit OS duplication and correct cleanup on all control-flow exits.
Exercise allocation failure at each acquisition step and erroring cleanup. Each
diagnostic identifies acquisition, conflicting use and exit/consumption sites.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The seeded and declared resources are affine and obligated, `own` transfers, every exit audits, `defer` reserves, failed acquisition narrows, branches/loops join, borrows cannot be consumed, copies and representation access are refused, and `os.dup` creates the only second handle identity (D345-D353). Pointer-mediated consumption resolves to the pinned owner (D610); concrete generic containment is classified after substitution (D611); tagged-union payloads propagate affinity (D612); and contextual closers consume their final resource parameter (D613). Fixed arrays inherit their element's classification and track comptime-indexed slots, exact provenance and full or comptime-offset slice aliases (D616-D620). Runtime-indexed reads, moves, overwrites and stores conservatively cover every possible affine element, and runtime-offset slices retain the same owner set (D711, D716-D720). Owned resource-slice parameters carry collective obligations, reject partial moves, drain through a proven zero-to-length sweep, and receive full or comptime-offset fixed-array ownership transfers (D721-D725). Dynamically filled `os.Thread` arrays retain their view behavior until owned resource-slice summaries can prove helper joins. Seeded handle representations are private behind explicit plain-handle views; resource reflection is empty outside the declaring module; `meta.get` and `meta.set` reject affine fields; and every delivered typed format codec stops at the same named-field boundary (D624-D628). Both host compilers pin valid transfers and each negative surface

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] arbitrary/dynamic resource-slice partitions
- [ ] a failure-safe generic container for obligated elements (H02)
- [ ] cross-function borrow retention beyond explicit `own` (H02)
- [ ] the recorded debug check-bodies budget breach

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D345` — Resources are affine and owed: the H01 rules checked over the seeded handles (`docs/decisions.md:7412`)
- `D353` — A container takes what it is given, a flag is tested like an error, and the bootstrap's token table (`docs/decisions.md:7709`)
- `D610` — A resource moved through a pointer is still pinned (`docs/decisions.md:12325`)
- `D611` — Generic containment is decided after substitution (`docs/decisions.md:12340`)
- `D612` — A tagged union carries the ownership of any payload (`docs/decisions.md:12356`)
- `D613` — A resource cleanup owns its final parameter (`docs/decisions.md:12370`)
- `D616` — Literal-indexed fixed-array slots carry ownership (`docs/decisions.md:12415`)
- `D620` — Comptime slice offsets retain the same resource slots (`docs/decisions.md:12474`)
- `D624` — Seeded resource representations use explicit handle views (`docs/decisions.md:12532`)
- `D628` — Typed codecs inherit the reflective resource boundary (`docs/decisions.md:12578`)
- `D711` — Runtime array alias reads use every possible element owner (`docs/decisions.md:13458`)
- `D716` — Runtime affine-array reads check every possible slot (`docs/decisions.md:13507`)
- `D720` — Runtime-offset slices retain affine-array candidates (`docs/decisions.md:13558`)
- `D721` — Owned resource-slice parameters carry one collective obligation (`docs/decisions.md:13569`)
- `D725` — Constant-offset owned slices transfer one suffix (`docs/decisions.md:13608`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `os.dup`: `tests/conformance/accept/safety_owned_slice_offset_transfer.e`×3, `src/main.e`×2‡, `tests/conformance/accept/safety_owned_slice_transfer.e`×2, `tests/conformance/reject/safety_array_element_site.e`×2, `tests/conformance/reject/safety_dynamic_array_move.e`×2, `tests/conformance/reject/safety_dynamic_array_read.e`×2, `tests/conformance/reject/safety_dynamic_array_slice_offset.e`×2, `tests/conformance/accept/safety.e`×1
- `os.Thread`: `src/main.e`×5‡, `lib/e/thread.e`×2, `benchmarks/metamorphic/rename_symbols.py`×1, `src/em_link.e`×1†, `src/graph.e`×1†
- `meta.get`: `src/check.e`×3‡, `lib/e/fmt/asn1.e`×2, `lib/e/fmt/bson.e`×2, `lib/e/fmt/csv.e`×1, `lib/e/fmt/html/template.e`×1, `lib/e/fmt/ini.e`×1, `lib/e/fmt/json.e`×1†, `lib/e/fmt/msgpack.e`×1
- `meta.set`: `lib/e/fmt/csv.e`×5, `lib/e/fmt/ini.e`×5, `lib/e/cli.e`×4, `lib/e/fmt/bson.e`×4, `lib/e/fmt/json.e`×4†, `lib/e/fmt/msgpack.e`×4, `lib/e/fmt/yaml.e`×4, `lib/e/fmt/asn1.e`×3

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
