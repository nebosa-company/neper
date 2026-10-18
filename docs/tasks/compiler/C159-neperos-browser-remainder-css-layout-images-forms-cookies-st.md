# C159 — NeperOS Browser remainder: CSS layout, images, forms, cookies, storage and downloads

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.70 of 1 |
| queue position | 54 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C129 (D2415): the Browser fetches an address over HTTPS and shows its HTML as lines of text with links. Acceptance: (1) HTTP/1.1 redirects, cookies, a cache, HTTP/2 and plain HTTP, the system proxy settings; (2) a CSS layout engine over e.fmt.css and e.fmt.html (block, inline, flex, grid, the common properties) painting through e.gfx.scene with shaped text, images (PNG, JPEG, SVG) and fonts; (3) forms and their submission, history, bookmarks, tabs that survive a restart (C125 storage), incognito, search suggestions and a chosen search engine; (4) downloads into Files and opening files in their apps; (5) permissions per site tied to Settings (C126); (6) a fixture against a local web server with a page that has an image and a form and a redirect. PART (D2455): e.net.cookie, an RFC 6265 cookie jar (net_cookie, 28 events vs an independent model). Remaining: the Browser using it (persisted store, request/response hooks), redirects and cache, CSS layout, forms, tabs, downloads. PART (D2456): the Browser keeps cookies in a jar that owns its strings and sends them (fixture browser_cookie, live); httpc.Reply carries the header block. Remaining: persisting the jar, redirects, cache, CSS layout, forms, tabs, downloads. PART (D2457): redirects followed (up to five hops, cookies kept at each; fixture browser_redirect, live). Remaining: persisting the jar, cache, HTTP/2, CSS layout, forms, tabs, downloads. PART (D2458): the persistent cookies are kept in /cookies across restarts (livediskfixture browser_jar and browser_jar_again). Remaining: cache, HTTP/2, CSS layout, forms, tabs, downloads, per-site permissions. PART (D3900): Browser fetches and draws an SVG <img>, submits a GET form (text and hidden fields), saves a non-page reply to /Downloads and reads it back; browser_form passes. Missing: POST, field editing, PNG/JPEG images, cache, HTTP/2, CSS layout, tabs across restart, permissions. PART (D4910-D4916): POST forms and field editing, PNG/JPEG images, ETag cache with 304, CSS cascade, tabs kept across restart, bookmarks, download opened in Document; rows browser_post, browser_images, browser_cache, browser_css, browser_tabs(+_again), browser_bookmark(+_again), browser_open_download. Remaining: HTTP/2, flex/grid layout, incognito, search engine and suggestions, per-site permissions.

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
