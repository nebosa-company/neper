# C129 — NeperOS Browser: a real engine: HTTP over TLS, HTML and CSS, images, forms

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 11 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Browser app (D2224) shows sample pages that live in the app. Acceptance: (1) HTTP/1.1 and HTTP/2 over the C117 TLS client with redirects, cookies, a cache and the system proxy settings; (2) an HTML5 parser and a CSS layout engine (block, inline, flex, grid, the common properties) painting through e.gfx.scene, with e.text shaping, images (PNG, JPEG, SVG) and fonts; (3) forms, links, history, bookmarks, the address bar with search suggestions and a chosen search engine, tabs that survive a restart (C125 storage), incognito; (4) downloads into Files and opening files in their apps (C123); (5) a script engine is a separate item (JavaScript or Neper in the page); (6) permissions per site (camera, location) tied to Settings (C126); (7) a fixture on QEMU against a local web server that loads a page with an image and a form and follows a link. Not queued here: extensions, sync, WebRTC.

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
