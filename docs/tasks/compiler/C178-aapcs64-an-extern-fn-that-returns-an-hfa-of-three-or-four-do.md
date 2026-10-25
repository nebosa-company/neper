# C178 — AAPCS64: an extern fn that returns an HFA of three or four doubles (CGRect, NSRect)

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.00 of 1 |
| queue position | 2 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found on 2026-10-23 by the macOS window probe: `extern fn f(r: usize, s: usize) -> CGRect` with CGRect = struct { x: f64, y: f64, w: f64, h: f64 } stops aarch64 lowering with `cannot lower main: construct is not implemented in self-hosted lowering` at the call (x64 compiles it, through the memory-returned slot). A two-double struct, a double, a BOOL and a C string all return correctly on both Mac architectures; AppKit hands window and view sizes back as NSRect, so the window code reads them through KVC (`valueForKey:` then `NSValue getValue:`) until this is fixed. Where it stops: `lower.e` `c_result_type` already names a 3- or 4-member HFA `return-hfa-N-W` (D2124) and `codegen_a64.e` `pack_hfa` / `hfa_pair` pack the members into at most the two eightbytes x0 and x1 hold; a four-double HFA comes back in v0-v3, four eightbytes, which the result model (one value, or a pair) has no room for. Plan: give a call whose result is a 3- or 4-member HFA a result slot, as a C return slot is for a struct returned in memory: lowering allocates it and passes nothing, the call selection stores v0-v3 into it after the call, and the value is read from the slot. Acceptance: (1) a fixture `macos_hfa_return` calls CoreGraphics `CGRectMake`, `CGRectInset` and `CGRectUnion` through `@import` for aarch64-macos and x64-macos and checks every member, and passes on a Mac in the corpus; (2) an aarch64-linux fixture returns 3- and 4-member double HFAs and a 4-member float HFA from a C shared object built by cc, run under the aarch64 test environment; (3) x64 and the 2-member case are byte-identical to before; (4) the window code reads sizes by a direct rect-returning call and the KVC workaround is deleted.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `valueForKey:`: `lib/e/os.macos.e`×1‡
- `lower.e`: `src/main.e`×17‡, `lib/e/os.neperos.e`×1, `lib/e/ui/navigation.e`×1‡, `scripts/lint_bootstrap.py`×1
- `c_result_type`: `src/lower.e`×3‡
- `return-hfa-N-W`: `src/codegen_a64.e`×1†
- `pack_hfa`: `src/codegen_a64.e`×2†
- `hfa_pair`: `src/codegen_a64.e`×2†

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
