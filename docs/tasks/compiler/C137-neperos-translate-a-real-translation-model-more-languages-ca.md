# C137 — NeperOS Translate: a real translation model, more languages, camera and voice input

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 19 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Translate app (D2232) uses a sample book of eight phrases in six languages. Acceptance: (1) translation by an on-device model from the library (the ml modules) or a server over C117, with at least forty languages, auto-detect, and offline packs kept in Files (C125); (2) fonts and shaping for the scripts those languages need (Arabic, Devanagari, CJK, Cyrillic, Greek, Thai, Hebrew), added to the font set the apps load; (3) input by voice (Recorder's speech engine, C136), by camera (text recognition in e.gfx.vision on a Camera frame, C122) and by handwriting; (4) history and saved phrases, copy and share, speak the result (text to speech through e.audio); (5) conversation mode with two languages on the two halves of the screen; (6) a fixture on QEMU that translates a fixed sentence with a small test model and checks the output text. Not queued here: document translation, subtitles.

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
