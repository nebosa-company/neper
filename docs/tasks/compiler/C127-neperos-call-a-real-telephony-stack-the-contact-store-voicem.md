# C127 — NeperOS Call: a real telephony stack, the contact store, voicemail

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 9 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Call app (D2222) has a keypad, recents, contacts and a call screen on sample data; a call is a demo that 'connects' after a second. Acceptance: (1) a telephony server over the modem or a SIP/VoIP stack on C117 networking: dial, answer, reject, hold, mute, speaker, DTMF, call waiting and conference; (2) the in-call audio path through e.audio with the earpiece, speaker and Bluetooth routes; (3) a contact store shared with Messages, Mail and Wallet: add, edit, delete, favorites, search, import and export vCard; (4) recents and missed-call notifications through the status server, and Do Not Disturb honoured; (5) voicemail and visual voicemail; (6) emergency numbers always dialable; (7) a fixture on QEMU against a loopback SIP server that dials, answers and ends a call and checks the audio frames. Not queued here: video calls (Meet), SMS (Messages), eSIM management.

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
