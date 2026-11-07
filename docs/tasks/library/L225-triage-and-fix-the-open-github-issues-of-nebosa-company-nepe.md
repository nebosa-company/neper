# L225 — Triage and fix the open GitHub issues of nebosa-company/neper (687 on 2026-10-31)

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 186 of 222 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Backlog only, nothing to start now. `gh issue list --repo nebosa-company/neper --state open` listed 687 open issues on 2026-10-31 (numbers up to #1620; labels: bug 205, SEO 25, internal 2, the rest unlabelled), most of them against the e.web modules (CSP, page, iframes). Acceptance: every open issue is either fixed with a regression test that fails if it comes back and closed, or closed with a reason; work them in groups by module (read the titles first with `gh issue list --json number,title,labels`), group duplicates, and re-run the issue count at the start of each session because new ones keep arriving.

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
