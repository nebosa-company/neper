# C124 — NeperOS Dynamic: apps from a prompt, compiled in Neper on a server, scanned, installed

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 3 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). Dynamic is the app that makes apps: the user writes a prompt that says what app they need; the prompt goes to a NeperOS server that has a model write the app in the Neper language, compiles it, security scans it, and sends the result back to be installed on the device; no compiler, editor, IDE, debugger or linter on the phone; a Dynamic app can be extended later with extra features by another prompt. Acceptance: (1) the prompt screen (a text field on the on-screen keyboard, the apps already made, a progress view with the stages: written, compiled, scanned, ready), and the follow-up prompt on an existing app that sends its source and the request and gets a new version; (2) the server side as a documented protocol over C117's TLS: a request carries the prompt, the app's identity and the device's API level; the answer carries the app image, its source, its manifest (name, icon, the capabilities it asks for) and a signature; the source stays on the server and on the device for extension; (3) the compile step is the Neper compiler against the NeperOS app kit (appkit, text, scenes, the e.* library) with the diagnostics fed back to the model for repair until it builds or gives up with a readable message; (4) the security scan: the manifest's capabilities are checked against what the code calls (no raw syscall or MMIO outside the app kit; no network unless declared; no storage outside the app's own directory), the build is reproducible, the image is signed by the server, and the device verifies the signature and the manifest before installing; the first run shows the capabilities and asks; (5) install: the image lands under the app's own directory, the icon joins the home grid, an app can be removed, updated and rolled back; the kernel launches it with only the capabilities granted; (6) limits and honesty: a Dynamic app is generated code, labelled so; resource limits and a kill switch; the server keeps an audit log and can revoke a signature; (7) a fixture against a local test server with a canned model answer (no live model in the suite) that goes prompt to installed icon to launch to extension. Not queued here: sharing apps between users, a store, paid generation, on-device compilation.

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
