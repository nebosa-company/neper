# C194 — macOS corpus: the fixtures that are only reported (extern_many, freestanding, os_syscall, x_tds_integrated, gpu_*)

| field | value |
|---|---|
| category | library / macOS |
| score | 0.70 of 1 |
| queue position | 12 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Done 2026-10-25 (D5225): the Mac corpus asserts every fixture that can run on a Mac (1108 pass, 0 fail, 0 info) and skips seven with the reason a Mac has by nature, as SKIP lines counted apart in the TOTAL: extern_many (four glibc extensions libSystem lacks, then it reads its own ELF header), freestanding and os_syscall (an ELF image, Linux system call numbers), gpu_vulkan_raw and gpu_fault_unchecked (Vulkan, which a Mac does not have; a Metal backend is C193), x_tds_integrated (SSPI, Windows), net_ssh (driven by the workflow's SSH step, reported as its SSH line). gpu_reshape is now asserted at 50, the sum its own comment gives. Open: Mac counterparts of the ELF and system-call fixtures (a Mach-O header check and BSD system call numbers) would turn three skips into asserted tests; ui_collections4_v2 failed once on x64 under Rosetta (exit 190, a gesture timing check at 50 ms after a release) and passed on rerun, so it is timing-sensitive on a loaded runner. Done when the three Mac counterparts exist or are decided against.

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
