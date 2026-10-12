# C120 — NeperOS SSH: a real SSH client behind the Termius-style app

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 7 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The SSH app (D2215) has the hosts list, the host form and a terminal screen, but Connect opens a local demo shell because NeperOS has no network (C117). Acceptance: (1) an SSH-2 client over the C117 sockets: version exchange, key exchange (curve25519), host-key check against a known-hosts list the user confirms on first use, ciphers (chacha20-poly1305, aes-gcm), password and public-key authentication (ed25519), sessions with a pty and window size; (2) a terminal emulator behind the screen (ANSI colours, cursor movement, alternate screen, scrollback, resize) in place of the line-based demo, with Ctrl and Esc keys and a monospaced face; (3) keys and passwords kept in Secure (C116), a Keychain tab to create and import keys; (4) saved hosts kept in storage, groups and tags, snippets; (5) port forwarding (local and remote) and SFTP (browse, download, upload); (6) a fixture against an OpenSSH server in WSL or a local container, not the live internet. Not queued here: mosh, agent forwarding, jump hosts (a later item).

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
