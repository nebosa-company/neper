# C126 — NeperOS Settings: settings that act on the system, kept across restarts, searchable

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 1 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Settings app (D2220) keeps its values as sample state in the process; only its own Dark theme switch has an effect. Acceptance: (1) a settings service (a server in the capability model) that holds the values, answers reads from apps and sends changes to the parts that act on them: the display brightness and timeout to the GPU/display server, the volumes to the audio server (e.audio), Wi-Fi, Bluetooth, mobile and airplane mode to the network stack (C117), Do Not Disturb and per-app notification permission to the status server (C111), the screen lock and fingerprint to the lock screen, the 24-hour format and time zone to e.time, the font size and high-contrast text to the shared text kit so every app follows; (2) kept in storage (C125) across restarts, with Reset restoring the defaults; (3) the Dark theme, font size and contrast apply to every app through the app kit, not only to Settings; (4) search across all settings by name and keyword, with the page opened on the match; (5) the pages that are lists here become real: Wi-Fi networks from a scan and a password sheet, Apps from the installed apps with permissions and Uninstall (and Dynamic apps from C124), Storage and Battery from the system's real numbers; (6) a fixture on QEMU that changes a setting, restarts the shell and checks it held and took effect. Not queued here: accounts, backup, parental controls.

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
