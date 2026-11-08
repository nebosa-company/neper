# C267 — emitted binaries are reproducible: no field may depend on which compiler binary ran

| field | value |
|---|---|
| category | compiler / Hardening |
| score | 0.00 of 1 |
| queue position | 223 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found while verifying 18 bootstrap-lint fixes by differential build. Two compilers built from the same command line, from source states that differ only by the fix, emit binaries that differ in exactly 8 bytes on many fixtures and match on others. The 8 bytes sit inside an ASCII field `!003d88c0<8 hex>:...` in the image, and the control proves they track the compiler binary rather than the code: the untouched Nov 6 self-hosted compiler differs from a current build in the same 8 bytes at the same offset on the same fixture. Emitting the same source twice with the SAME compiler is byte-identical, so this is not general nondeterminism. The consequence is that byte-identical output cannot be used to check a codegen change, which is the cheapest and strongest regression test available: masking the field is required before any build comparison, and that masking is knowledge held outside the tree. Acceptance: identify what the 8 hex digits hash (candidate: the compiler image, its build id, or a toolchain signature), make the field a function of the translation unit and not of the compiler that performed it, or document it as an intentional stamp in the binary format's spec; a check that builds one source with two different compiler binaries and compares the images byte for byte, so this cannot regress silently; and the header comment in the emitted image's format doc stating whether reproducibility across compiler builds is promised.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
