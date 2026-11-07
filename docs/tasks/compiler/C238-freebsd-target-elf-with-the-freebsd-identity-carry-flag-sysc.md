# C238 — FreeBSD target: ELF with the FreeBSD identity, carry-flag syscalls, per-OS constant tables

| field | value |
|---|---|
| category | compiler / OS targets |
| score | 0.00 of 1 |
| queue position | 189 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Backlog only; blueprint is docs/os/free-bsd.md. First acceptance: an x86_64-freebsd static ELF (EI_OSABI 9, .note.tag ABI note) runs under a FreeBSD 14.x VM, writes and exits; then e.mem/e.io/e.fs/e.time fixtures where each differing constant (CLOCK_MONOTONIC 4, O_CREAT 0x200, EAGAIN 35) has a fixture that fails if the Linux value is used, and a syscall failure fixture proving the carry flag becomes an err. Later: thr_new and _umtx_op threads, kqueue, aarch64, dynamic linking via /libexec/ld-elf.so.1. Syscall numbers come from the target release headers, generated, never hand-typed.

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
