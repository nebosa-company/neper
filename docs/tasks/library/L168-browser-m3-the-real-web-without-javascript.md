# L168 — Browser M3: the real web without JavaScript

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 99 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/browser-progress.html. Needs L167. Acceptance: (1) Wikipedia with its 12k-node table, MDN with web fonts, craigslist and abv.bg match the Dart goldens within the per-site tolerance; (2) P3 3.13, 3.15, 3.16 SVG, web fonts; (3) P4 4.3 HTTP/2 transport, 4.4 and 4.5 TLS 1.3 interop and TLS 1.2, 4.8 HTTP cache, 4.11 to 4.14 cookies, CORS, SSRF, CSP, 4.17 filter lists; (4) core N.1 and N.2 scene limits and glyph cache as measured by these pages; (5) 7.2 to 7.6 control API, input, thread split, form widgets, accessibility; (6) a shell with tabs, history and bookmarks (7.7)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
