# C185 — macOS file and protocol associations, Finder-opened files and URLs (small bundles, application delegate)

| field | value |
|---|---|
| category | library / macOS |
| score | 0.90 of 1 |
| queue position | 3 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built and verified 2026-10-25 (D5217): shell.associate_file/associate_protocol write a bundle under ~/Library/Application Support/Neper/Associations (Info.plist with CFBundleDocumentTypes or CFBundleURLTypes, a copy of the program as its executable), register it with lsregister -f and make it the default handler (LSSetDefaultRoleHandlerForContentType / LSSetDefaultHandlerForURLScheme); dissociate removes it. The shell target is the NSApp delegate and the GURL Apple event handler; application:openURLs: (file URLs become File activations by path) and application:openFiles: feed activation_poll. tests/macos/probe/open_events.e: open on a file of the registered type and on a registered URL start the registered copy, which receives both and the parent reads them back, on aarch64 and x64; ui_activation passes with associations on; the corpus is 1105 pass. Open: a double-click in Finder and a link in a browser are what a person does and are untested (C192), and the bundle holds a copy of the program, so it is stale after the program is rebuilt (register again). Done when a real Finder open is checked.

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
