# C189 — macOS notices through UNUserNotificationCenter: removal, replacement and actions

| field | value |
|---|---|
| category | library / macOS |
| score | 0.40 of 1 |
| queue position | 7 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5221), the center path unverified: for a program with a bundle identifier (shell.bundled()), notice_publish and notice_update ask UNUserNotificationCenter for alert and sound authorization once (requestAuthorizationWithOptions with a hand-built global block, waiting up to a minute) and post a request whose identifier is neper-<id> (the same id again replaces it); notice_remove removes the delivered and pending request; the capability notice_remove is true once the center has authorized the program. A program with no bundle, or one that was not authorized, keeps osascript banners and Unsupported removal. tests/macos/probe/un_notices.e on the runners (a registered association bundle started with open): bundled detection works and the program runs through publish, count, remove, count and ends, but the runner never authorizes the center, so the banner went through osascript, the delivered count stayed 0 and removal was refused; the corpus is 1105. Open: the center path itself (post, replace, remove, getDelivered) has never run, because nothing here can answer the authorization prompt (C192); action buttons (UNNotificationAction categories and a delegate for responses) are not built. Done when a real authorized run posts, replaces and removes, and actions are decided.

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
