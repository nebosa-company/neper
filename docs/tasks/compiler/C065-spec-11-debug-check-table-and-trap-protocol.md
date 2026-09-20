# C065 — Spec 11 debug check table and trap protocol

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.99 of 1 |
| queue position | 21 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/roadmap.md`, section **M1 — The full CPU language**:

> The full debug-mode check table of spec §11 — bounds, null, tag, overflow, narrow, shift, enum, align — the trap protocol, `unreachable()`, and the arena fills

**Done when:** every item above is implemented in the self-hosted compiler, and
`lib/e` builds and its tests pass under `neper test`; all applicable conformance
fixtures validate byte-for-byte after the specified duration normalization; tooling
streams reconstruct source exactly and validate against the schema; formatter
idempotence holds; every M1 API fence matches extracted source declarations; and the
S0 generated-code benchmark has been rerun with no unexplained regression.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> A check that fires follows the trap protocol (D194): the runtime's `neper_trap` writes `file:line:col: trap[kind]: <values>` to stderr and exits 134 on both platforms, and link/trap_bounds pins the record for an index and a slice past the end. Rows delivered: `bounds` (index and slice), the compiler's own `unreachable` points, the `unreachable()` builtin with its literal as the values, which the checker counts as diverging (D195, link/trap_unreachable, check/unreachable_argument), the rows that trap in every mode -- `divide` by zero and the minimum by -1, both reported before x64 could raise `#DE` for them, and `shift` by a count past the width -- with a signed operand printed signed (D196, link/trap_arithmetic), `enum`: section 4's `Kind(x)` cast exists now and traps on a value naming no member (D197, link/trap_enum, check/enum_cast_width), `narrow` for an integer source: a cast whose value does not fit by width or by sign traps, and section 4's meant truncation `T.trunc(x)` exists and never does (D198, link/trap_narrow, check/trunc_float_argument), `narrow` for a float source -- NaN and a value past the target's range -- `tag`: a payload read or written under another member's tag (D200, link/trap_tag), `null`: every dereference of a pointer value -- `*p` and `p.field` -- read or written, refused for nil (D201, link/trap_null), and `overflow`: `+ - *` and unary `-` on every width, an unsigned 64-bit `*` through `mul`'s high half (D202, link/trap_overflow); `@nocheck { }` leaves the debug-only rows out of a block and the release rows in (D203, link/nocheck); `emit-executable --release` is the release build: every debug-only row left out, `+ - *` wrapping, casts truncating, shifts masked and a float outside its target saturating, NaN to 0 (D204, link/release_build, a fifth smaller). A trap ends with its backtrace: one `  at module.function` line per frame, walked over the rbp chain and named from a symbol table the driver appends after the code, which the artifact path reproduces byte for byte (D206, link/trap_backtrace), each frame with the file and line its call is at, from the line table (D209, D212), and `align`: `simd.load_aligned`/`store_aligned` at an address that is not a multiple of the vector's width, checked at the call site in debug and left out in release (D210, link/trap_align)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the test root's control handle

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D194` — A failed check follows section 11's trap protocol (`docs/decisions.md:3535`)
- `D195` — `unreachable()` is the one always-on builtin (`docs/decisions.md:3554`)
- `D196` — The `divide` and `shift` rows trap with a record (`docs/decisions.md:3569`)
- `D197` — `Kind(x)` is a cast, and the `enum` row traps (`docs/decisions.md:3588`)
- `D198` — Integer casts are checked, and `T.trunc(x)` is the meant truncation (`docs/decisions.md:3607`)
- `D200` — The `tag` row, and the float side of `narrow` (`docs/decisions.md:3648`)
- `D201` — The `null` row: a dereference of `nil` traps (`docs/decisions.md:3668`)
- `D202` — The `overflow` row: `+ - *` and unary `-` trap when the result does not fit (`docs/decisions.md:3681`)
- `D203` — `@nocheck { ... }` leaves the debug-only rows out of a block (`docs/decisions.md:3701`)
- `D204` — `emit-executable --release` is the release build (`docs/decisions.md:3717`)
- `D206` — A trap ends with its backtrace, from a symbol table after the code (`docs/decisions.md:3755`)
- `D209` — The line table: every frame of a backtrace has its file and line (`docs/decisions.md:3821`)
- `D210` — The `align` row is checked at the aligned intrinsics' call sites (`docs/decisions.md:3840`)
- `D212` — Nested inlining through a second oracle, and every function has a frame (`docs/decisions.md:3875`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `neper_trap`: `src/em.e`×3‡, `src/runtime_elf_x64.s`×3†, `src/codegen_x64.e`×2‡, `src/runtime_elf_x64.e`×2, `src/runtime_pe_x64.asm`×2†, `src/runtime_pe_x64.e`×2†
- `T.trunc`: `lib/e/bytes.e`×1, `src/check.e`×1‡, `src/codegen_x64.e`×1‡, `src/lower.e`×1‡
- `simd.load_aligned`: `src/lower.e`×1‡
- `store_aligned`: `src/lower.e`×2‡, `lib/e/simd.e`×1

## Existing fixtures

- `tests/selfhost/fixtures/link/trap_bounds`
- `tests/selfhost/fixtures/link/trap_unreachable`
- `tests/selfhost/fixtures/check/unreachable_argument`
- `tests/selfhost/fixtures/link/trap_arithmetic`
- `tests/selfhost/fixtures/link/trap_enum`
- `tests/selfhost/fixtures/check/enum_cast_width`
- `tests/selfhost/fixtures/link/trap_narrow`
- `tests/selfhost/fixtures/check/trunc_float_argument`
- `tests/selfhost/fixtures/link/trap_tag`
- `tests/selfhost/fixtures/link/trap_null`
- `tests/selfhost/fixtures/link/trap_overflow`
- `tests/selfhost/fixtures/link/nocheck`
- `tests/selfhost/fixtures/link/release_build`
- `tests/selfhost/fixtures/link/trap_backtrace`
- `tests/selfhost/fixtures/link/trap_align`

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
