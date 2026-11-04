# T068 — pacman P0: strict project.yaml parser, canonical project.lock writer, SemVer ranges and PubGrub resolver

| field | value |
|---|---|
| category | tooling / Project tools |
| score | 0.00 of 1 |
| queue position | 172 of 219 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/pacman.md:410 by the single-list audit; not previously a queue row. Acceptance: A `neper pacman` command group resolves a manifest into a byte-canonical project.lock with module-export validation and PubGrub conflict explanations. Golden fixtures cover the manifest/lock formats, resolution ties, conflicts and yanked versions; tests/conformance/package/p0.package.json is produced by the real emitter rather than hand-written. Size XL. Checked open: grep -ril pacman src lib tests scripts: only src/assets.e (comment) and generators; no PubGrub/project.lock/project.yaml producer in src or lib; queue.tsv and work-done.jsonl have no pacman row; work-queue.json T012 says 'Missing: the producer (M6 pacman P0)'.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Existing fixtures

- `tests/conformance/package/p0.package.json`

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
