# C272 — chacha20-poly1305 sessions reach an encrypted packet and cannot open it

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 224 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> net_ssh fails on every chacha20-poly1305 case (password, early, key, badpass, sftp, forward, forward_refused) while gcm256, gcm128, rekey, badhost and unit all pass. The client gives up in take_packet: the first four bytes of the peer's first encrypted frame decrypt to a length outside 5..35000. What has been ruled out, each against the peer itself: the key material is identical (asyncssh patched to print its 64-byte key, its second half equals our key_in_len byte for byte); the client's key_in_len equals an independent RFC 4253 derivation from K/H/session_id in all seven sessions of a run; the chacha20 primitive is byte-identical to asyncssh's for a known key, nonce and plaintext; the key split (first half payload, second half header), the nonce construction and the counter split (header 0, payload 1) all match the peer's source; seq_in and seq_out advance once per packet in a single path; the keys are installed before encrypted_in is set. The anomaly: those four bytes decrypt to a plausible length 744 at sequence 0 but to garbage at the sequence the client holds (3), while asyncssh's connection.py only zeroes _send_seq/_recv_seq in __init__ and never on a key change. Shifting the client's nonces by -3 makes the header decode and moves the failure to FAIL_MAC, and shifting the payload nonce as well moves it to FAIL_DISCONNECT -- a desynchronised stream rather than a fix. The GCM paths pass because their length is in the clear and their nonce is a separate invocation counter, so a sequence disagreement is invisible there and fatal here, which is why this survived. Acceptance: a chacha20-poly1305 session completes against asyncssh like the GCM ones; a unit vector decrypts a fixed frame from the peer with a fixed key and sequence; and the sequence numbers the client uses are recorded next to the frame they decrypt, so the next disagreement names itself.

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
