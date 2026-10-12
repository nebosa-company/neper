# L163 — Fast, small PNG encoding: dynamic Huffman, lazy matching and table CRC

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.00 of 1 |
| queue position | 142 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Backlog from the chart benchmark (D2108, D2110). On the same 360x240 chart raster, e.fmt.png at .Balanced takes about 18 ms and writes 14,004 B, while zlib level 6 with the same filter-0 rows takes 1.74 ms for 11,283 B; rasterizing takes 2.0 ms, so the encoder is the whole PNG gap to matplotlib. e.algo.deflate writes fixed-Huffman blocks only (zlib restricted to fixed Huffman gives 12,903 B, so dynamic trees are worth about 1.6 KB here), has no lazy matching and restarts its 16-deep hash chain at every 32 KiB block (about 1.1 KB more), and e.fmt.png computes CRC-32 bit by bit. Done when: e.algo.deflate writes dynamic-Huffman blocks with lazy matching and a window that spans blocks, round-tripping through its own decoder and Python's zlib on a corpus; e.fmt.png uses a table-driven CRC; the chart benchmark's PNG pass is at least as fast as matplotlib's with files no larger than zlib level 6 on the same rows; both suites pass. Adaptive per-row filters are optional: Pillow's heuristic made this chart larger.

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
