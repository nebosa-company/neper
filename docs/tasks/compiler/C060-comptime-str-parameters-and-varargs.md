# C060 — Comptime str parameters and varargs

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.95 of 1 |
| queue position | 19 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/spec.md`, section **Argument packs**:

A trailing parameter declared `...` accepts a comptime-known list of arguments. The
function is monomorphised per distinct argument shape, so there is no `va_list`, no
runtime type information, and no boxing — the pack is gone by codegen.

```
fn printf[FMT: str](args: ...) -> err // e.io
fn format[FMT: str](a: *mem.Arena, args: ...) -> (str, err) // e.str
fn launch[K: fn](q: *gpu.Queue, g: gpu.Grid, args: ...) -> err // e.gpu
```

**In v1 a `...` parameter appears only in these three functions, and all three are
compiler intrinsics** (§14). No user code and no other core function can declare
one: `...` in any other signature is a compile error (the C variadic on an `extern`,
§5, is a different thing with a different rule). There is no pack API — no
`args.len`, no iteration, no per-element type query — because a pack exists only for
the compiler to expand: `printf` and `format` expand against the format string into
straight-line pushes, and into a call to a type's own `format` where the argument has
one (§4, Protocols above); `launch` checks the pack against the parameter list of the
`@gpu` function `K` names (§10). Packs are comptime-only: there are no runtime
variadics in neper, and a pack cannot be stored, forwarded at runtime, or inspected.

This is a language exception, and it is recorded as one (D19): three intrinsics
behind a token, not a general mechanism the library could have written. It is the
cheaper of the two honest choices — a comptime pack API with length, indexing and
type dispatch is an interpreter feature with rules of its own — and the three cover
what formatting and kernel launch need. Opening `...` to user code is deferred, not
undecided: it needs that API, and nothing in `lib/e` or the self-hosted compiler
needs it.

Together, comptime parameters, evaluation and these three intrinsic argument packs
cover the use cases that this specification accepts in place of conventional
generics, macros and `#define` constants. Argument packs themselves do not replace
generics, and v1 exposes no additional metaprogramming mechanism.

---

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> link/comptime_str, link/str_format, link/io_printf; two of the three pack intrinsics expand, `gpu.launch` does not

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

Notes:

- The evidence names no gap clause; the remaining line is the third pack intrinsic: `gpu.launch` must expand a comptime pack the way the two others do. The other two are the reference implementation — find them with `rg -n 'pack' src/check.e src/lower.e`.

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `gpu.launch`: `src/check.e`×10‡, `lib/e/gpu/tensor.e`×8, `lib/e/gpu.e`×2, `src/lower.e`×1‡

## Existing fixtures

- `tests/selfhost/fixtures/link/comptime_str`
- `tests/selfhost/fixtures/link/str_format`
- `tests/selfhost/fixtures/link/io_printf`

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
