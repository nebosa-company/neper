# C164 — NeperOS Chat remainder: TLS, accounts and presence, history, files, encryption

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.55 of 1 |
| queue position | 59 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C134 (D2423): the Chat app talks to a loopback WebSocket server for the general room. Acceptance: (1) wss with a way to poll a TLS connection from an app (the network server's poll is plain TCP only), accounts, rooms and direct messages as the server has them, presence and typing indicators, delivery and read marks; (2) message history in storage (C125), search, threads, mentions, reactions kept on the server, edit and delete; (3) files and images from Files and Camera, link previews; (4) notifications through the status server with per-room settings (C126); (5) voice and video from a room opens Meet (C135); (6) end-to-end encryption with keys in Secure (C116); (7) a fixture across two clients. PART (D4105): wss with TLS polling, presence, typing, delivered marks, history on disk; chat_tls, chat_tls_again, chat_presence pass. Missing: accounts, search/threads/reactions, files, notifications, Meet hand-off, E2E, two-client fixture. PART (D5105, D5106): accounts, ids, reactions, threads, search and a second client are committed; chat_search and clipboard_long pass on QEMU, chat_two/chat_account/chat_account_bad unrun. Remaining: files and images, server history, notifications, E2E.

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
