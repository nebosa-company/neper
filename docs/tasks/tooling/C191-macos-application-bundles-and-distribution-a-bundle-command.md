# C191 — macOS application bundles and distribution: a bundle command, icon, code signing, notarization

| field | value |
|---|---|
| category | tooling / macOS |
| score | 0.60 of 1 |
| queue position | 9 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5224): scripts/macos-bundle.sh, run on a Mac, makes NAME.app from a program built for macOS: Contents/Info.plist (bundle id, name, version, NSHighResolutionCapable, LSUIElement with --agent, camera, microphone and location usage descriptions on request), Contents/MacOS/NAME, Contents/Resources/NAME.icns from a png (sips and iconutil), an ad-hoc signature verified with codesign --verify --deep --strict, and NAME.zip (ditto) with --zip. The macos-corpus job runs it on os_poller with an icon and checks plutil, the bundle id with PlistBuddy, the zip, and that the program inside the bundle runs, on aarch64 and x64 (BUNDLE PASS). It reuses what the run-time association bundles (D5217) already needed. Not done: a Developer ID signature with the hardened runtime and notarization (xcrun notarytool), which need an Apple developer identity this repository does not have, so their commands are in the script's header; a .dmg; document and URL types in the script (programs register them at run time with associate_file); a neper command that calls the script (the compiler's declaration capacity is full, so the script is the interface); Info.plist keys for entitlements. Done when a notarized bundle has been built and opened on a clean Mac.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
