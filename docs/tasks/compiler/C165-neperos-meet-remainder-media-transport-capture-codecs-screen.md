# C165 — NeperOS Meet remainder: media transport, capture, codecs, screen sharing

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 60 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C135 (D2424): Meet signals over a WebSocket and shows the people and the speaker the server names. Acceptance: (1) media over C117 (needs UDP in the network server): a WebRTC-style stack (ICE, DTLS-SRTP) or a simple SFU protocol; (2) capture: the camera frames from the camera server (C153) and the microphone from e.audio, encoded and sent with a codec from the library, the received streams decoded into the tiles; (3) the speaker and grid layouts follow the audio levels; (4) screen sharing from the compositor, raise hand visible to others, chat in the meeting (C134/C164), captions; (5) echo cancellation, noise suppression and bandwidth adaptation; (6) a fixture with two clients in one machine against a relay that exchanges test frames and checks them.

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
