# C058 — Regions, borrows and container views (M2.5-core H02)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.99 of 1 |
| queue position | 13 of 46 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H02 — regions, borrowing and stable container views** (track: M2.5-core (Language safety and GPU contracts, in_progress)):

The closure design for this requirement is `docs/m25-h02-regions.md`; read it after the section below.

Prefer lexically delimited scratch regions and build-then-freeze containers, but
do not describe escape prevention as a trivial block rule. A pointer can escape
inside a struct, through a callback, into a global, via an imported function or
through a different alias of the arena. Preventing those escapes requires analysis.

Define a bounded checked subset with these properties:

- Track the storage owner of borrowed pointers/slices recursively through
  aggregates. Public signatures describe no-escape inputs and which input/region
  a result borrows from. Body inference checks the contract; cross-module calls
  use serialized summaries rather than reading arbitrary bodies.
- A region may end only when its live borrows are dead. Parent reset/allocation
  interactions, nested regions, arena transfer and reborrowing have one specified
  rule. A borrowed region view is not an independently movable arena owner.
- Return, global stores, heap-like arena stores, callbacks, indirect calls and
  thread handoff cannot erase the origin. Unknown foreign/raw-pointer behavior
  requires an unsafe boundary, not an inferred no-escape claim.
- Start conservatively with lexical lifetimes. Measure whether false rejections
  justify non-lexical liveness; do not quietly infer arbitrary whole-program
  ownership. Persistent graphs must have a documented handle/pool construction or
  an explicit unsafe implementation with a checked public interface.
- Replace publicly escaping mutable-container backing slices with a scoped borrow
  or consuming freeze operation. During a scoped view, reject invalidating growth,
  mutation and reset through all tracked aliases. Returning raw pointers from
  `get` would recreate the problem; copy accessors and borrowing accessors differ.
- A frozen slice still borrows its backing arena. Freezing a builder prevents its
  growth, not the arena's destruction or reset. State the remaining lifetime.
- Repeated append-only temporary buffers should reuse scratch regions rather than
  exhaust the root arena. Correctness includes bounded steady-state memory.

Generation-tagged checked handles are a possible alternative for selected dynamic
containers. They require an owner identity, generation-wrap policy, runtime costs
and checks on every protected access. Filling released bytes with `0xDD` detects
neither every use-after-reset nor a stale yet addressable pre-growth slice.

Acceptance: nested-region escapes, aliases across reset, returned borrowed fields,
retained callbacks, live views across growth, freeze followed by reset and repeated
request/frame loops. Include valid nonescaping counterparts to measure false
positives. Reject or trap each protected violation before invalid memory is used;
record raw-pointer cases explicitly outside the guarantee.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The lexical subset (D354, `m25-h02-regions.md`): a mark is followed, values allocated after it dangle at the reset, views of a container dangle at its mutation, both refused at the use (E-SAFETY-0013/0014) with the join and loop rules of H01; no false positive across the compiler, library and fixtures; a pointer local bound from `&x` is recorded as an alias of `x`, and the lending rule (D393), the region rule and the view rule (D394) follow it, `.len` excepted, a slice bound from a place of `x` is the same alias (D395), and a struct local given `&x` in a field -- by its literal or by a store -- aliases `x` through that field alone (D413); an assignment records the same alias a binding does and ends the one the local held, and a slice rebound ends the aliases other slices held of its old storage (D416). A view's end is a fact of the context page (D501): at the `mem.reset` of its region or the call given its container by pointer, the local views nothing from there, which is what the rules refuse a read after; `context_moves.ends` pins it per host. Mutable container calls follow direct and copied local pointer aliases (D671-D672); region matching canonicalizes direct, addressed and aliased arena locals (D673), including copied pointer parameters (D676); copied marks retain the original checkpoint (D677); accessors through pointer aliases produce tracked views (D678); and deferred reset takes effect at scope exit, allowing earlier uses while refusing direct, derived-slice and derived-pointer returns across the reset (D675, D680-D681). Pointer aliases extracted from an aggregate, the aggregate carrier itself, and direct aggregate copies or assignments retain that reset boundary and are E-SAFETY-0018 (D682-D685). Addressed accessors and mutations through tracked aggregate pointer fields use the pointed-to container (D687-D688); nested aggregate literals and field assignments retain their enclosed region pointer (D689-D690). Two independent top-level pointer fields retain field-specific targets through use, carrier return, aggregate copy and separate field assignment (D691-D694). The sparse form retains third and later top-level aliases through use, carrier return, aggregate copy, separate field assignment and thread contexts without growing every `Resource` (D696-D700). Recursive field paths retain every nested owner through use, carrier return, aggregate copy, nested assignment and thread context (D701-D705). Comptime-indexed fixed-array paths retain each element owner through use, carrier return, lexical copy, separate assignment and thread context (D706-D710). Runtime indices conservatively use every matching element owner for reads, deferred returns, mutable-call invalidation and thread lending, including below nested aggregate fields (D711-D715). Explicit `@borrows` summaries are declaration-checked, proved over scalar and aggregate returns, applied to the exact caller argument and carried through generic specialization (D731-D735, E-SAFETY-0019). Explicit `@noescape` inputs are declaration-checked; direct and aggregate returns, global retention, unannotated/extern calls, indirect callbacks and thread handoff are rejected, while exact forwarding to another checked no-escape parameter is accepted (D736-D739, E-SAFETY-0020). Nonempty multi-input sets receive the same return, global and forwarding proof for every named origin (D741-D744); artifact-format-14 interfaces and canonical signatures serialize the counted ordered set through generic specialization (D745)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] arbitrary heap/container retention
- [ ] raw-cast provenance
- [ ] non-lexical liveness
- [ ] build-then-freeze containers
- [ ] generation-tagged handles

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D354` — H02's lexical subset: a region ends at its reset, a view at its container's change (`docs/decisions.md:7739`)
- `D393` — A pointer bound from `&x` is `x` by another name to the lending rule (`docs/decisions.md:8751`)
- `D394` — A pointer bound from `&x` reaches storage a reset took away (`docs/decisions.md:8770`)
- `D395` — A slice bound from a place of `x` is the same alias (`docs/decisions.md:8786`)
- `D413` — A struct holding `&x` in a field aliases `x` through that field (`docs/decisions.md:9188`)
- `D416` — An assignment records an alias as a binding does, and ends the one it replaces (`docs/decisions.md:9249`)
- `D501` — A view's end as a fact (`docs/decisions.md:10712`)
- `D671` — Mutable calls follow a direct pointer alias to the container (`docs/decisions.md:13058`)
- `D672` — Pointer copies retain their original local target (`docs/decisions.md:13069`)
- `D673` — Region matching uses canonical local arena identity (`docs/decisions.md:13079`)
- `D675` — A deferred region reset takes effect at scope exit (`docs/decisions.md:13099`)
- `D676` — A pointer-parameter copy keeps the parameter's storage identity (`docs/decisions.md:13110`)
- `D677` — A copied region mark retains the original checkpoint (`docs/decisions.md:13121`)
- `D678` — Accessors follow local pointer aliases to their container (`docs/decisions.md:13131`)
- `D680` — A derived slice cannot escape across its deferred reset (`docs/decisions.md:13151`)
- `D681` — A derived pointer cannot escape across its deferred reset (`docs/decisions.md:13161`)
- `D682` — Aggregate pointer aliases retain a deferred-reset boundary (`docs/decisions.md:13170`)
- `D685` — Aggregate assignment copies the same pointer alias (`docs/decisions.md:13198`)
- `D687` — Mutable calls prefer the storage behind an aggregate pointer field (`docs/decisions.md:13218`)
- `D688` — Accessors prefer the storage behind an aggregate pointer field (`docs/decisions.md:13228`)
- `D689` — Nested aggregate literals retain their enclosed region pointer (`docs/decisions.md:13237`)
- `D690` — Aggregate field assignment retains an enclosed region pointer (`docs/decisions.md:13244`)
- `D691` — Two aggregate pointer fields retain distinct lexical targets (`docs/decisions.md:13254`)
- `D694` — Pointer-field assignment preserves sibling aliases (`docs/decisions.md:13285`)
- `D696` — Later aggregate pointer fields use a sparse alias table (`docs/decisions.md:13309`)
- `D700` — Thread contexts resolve later aggregate pointer fields (`docs/decisions.md:13349`)
- `D701` — Nested aggregate pointer aliases retain complete paths (`docs/decisions.md:13359`)
- `D705` — Thread contexts resolve recursive aggregate alias paths (`docs/decisions.md:13401`)
- `D706` — Fixed-array literals retain comptime element alias paths (`docs/decisions.md:13411`)
- `D710` — Thread contexts resolve fixed-array element aliases (`docs/decisions.md:13449`)
- `D711` — Runtime array alias reads use every possible element owner (`docs/decisions.md:13458`)
- `D715` — Runtime element candidates compose with nested aggregate paths (`docs/decisions.md:13497`)
- `D731` — Result borrows are explicit declaration contracts (`docs/decisions.md:13682`)
- `D735` — Borrow summaries survive specialization and artifacts (`docs/decisions.md:13729`)
- `D736` — No-escape inputs are explicit declaration contracts (`docs/decisions.md:13741`)
- `D739` — No-escape forwarding requires a checked matching callee (`docs/decisions.md:13767`)
- `D741` — One no-escape contract may name several inputs (`docs/decisions.md:13785`)
- `D744` — Multi-input forwarding is positional at both ends (`docs/decisions.md:13806`)
- `D745` — Artifact format 14 carries a counted no-escape position set (`docs/decisions.md:13813`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.len`: `src/main.e`×542‡, `src/check.e`×333‡, `src/tool.e`×309‡, `src/em.e`×168‡, `lib/e/fmt/json.e`×154†, `lib/e/os.linux.e`×145‡, `lib/e/algo/sketch.e`×139†, `lib/e/ui/control.e`×136‡
- `mem.reset`: `lib/e/os.windows.e`×70‡, `lib/e/os.linux.e`×54‡, `lib/e/fmt/json.e`×26†, `lib/e/net/http.e`×26†, `lib/e/io.e`×17, `lib/e/fs.e`×14, `lib/e/grep.e`×10, `lib/e/net/ws.e`×7
- `context_moves.ends`: `tests/conformance/tools/context_moves.x64-linux.expected.jsonl`×1, `tests/conformance/tools/context_moves.x64-windows.expected.jsonl`×1
- `Resource`: `src/check.e`×144‡, `src/main.e`×16‡, `lib/e/fmt/brotli.e`×1‡
- `@borrows`: `src/check.e`×3‡, `tests/conformance/accept/regions_borrow_contract_aggregate.e`×1, `tests/conformance/accept/regions_borrow_contract_artifact.e`×1, `tests/conformance/reject/regions_borrow_contract_body.e`×1, `tests/conformance/reject/regions_borrow_contract_body.expected.jsonl`×1, `tests/conformance/reject/regions_borrow_contract_call.e`×1, `tests/conformance/reject/regions_borrow_contract_generic.e`×1, `tests/conformance/reject/regions_borrow_contract_name.e`×1

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
