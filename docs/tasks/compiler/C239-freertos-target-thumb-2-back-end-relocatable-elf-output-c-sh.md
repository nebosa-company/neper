# C239 — FreeRTOS target: Thumb-2 back end, relocatable ELF output, C shim for the kernel API

| field | value |
|---|---|
| category | compiler / OS targets |
| score | 0.00 of 1 |
| queue position | 190 of 223 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Backlog only; blueprint is docs/os/free-rtos.md. Blocked first on whether the linker can write ET_REL objects (check before sizing). First acceptance: a thumbv7m object whose main prints through semihosting and exits runs under QEMU (lm3s6965evb or mps2-an385) linked with the FreeRTOS ARM_CM3 port; then known-answer fixtures for __aeabi_uldivmod/ldivmod and memcpy, then the neper_freertos.c shim with e.thread/e.sync/e.time fixtures, then neper size and neper stack-report. Thumb bit, branch range and literal pools are the traps. Later: standalone image with a memory map, thumbv6m/v7em, RV32.

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
