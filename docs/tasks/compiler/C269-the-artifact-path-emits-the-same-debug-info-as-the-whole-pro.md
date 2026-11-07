# C269 — the artifact path emits the same debug info as the whole-program path

| field | value |
|---|---|
| category | compiler / Hardening |
| score | 0.00 of 1 |
| queue position | 223 of 223 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found once crew_windows could finally be reached: 'crew_windows at -j 1 is not the image linked from its artifacts (--time)'. Repro: emit-em-all over crew_windows then link-em the twelve artifacts, and separately emit-executable the same fixture at -j 1, both in the default (debug) mode. Sizes 75560 linked against 76072 direct. A PE section compare (dumpbin /headers) shows every section identical except .debug_info: 3FFA virtual / 4000 raw linked, against 4068 / 4200 direct -- the whole 512-byte file difference is that section's rounding. The code is byte-identical: 0 differing bytes across 0x400..0xB000, which is the headers' payload, .text (A8F5/AA00) and .idata (1B0/200). Inside .debug_info the first four bytes are the unit length, 0x3FF6 linked against 0x4064 direct, and the streams diverge at +0x10A6: the linked copy lists `e.os.PollRegistration`, the direct one `e.text.utf8.Iterator`, so the subprogram DIEs are in a different order and 110 bytes differ in total. In --release the two paths are byte-identical (E5321649... both), which is why this has never been seen: release emits no debug info to disagree about. Pre-existing and not this session's: the untouched Nov 6 self-hosted compiler produces the same two hashes (C1E733B0... linked, FE538AEC... direct). Acceptance: the artifact path and the whole-program path emit the same .debug_info for the same program in the default mode, so the two images are byte-identical there as they already are in --release; crew_windows' artifact comparison then covers both modes again; and a check pins the two images byte for byte in a debug build, which is what would have caught this before a suite run had to reach line 1067 to notice.

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
