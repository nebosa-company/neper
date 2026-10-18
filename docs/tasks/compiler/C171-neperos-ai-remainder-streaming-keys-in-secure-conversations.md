# C171 — NeperOS AI remainder: streaming, keys in Secure, conversations, files and tools

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.50 of 1 |
| queue position | 66 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C141 (D2430): AI sends a conversation to a provider and shows the answer. Acceptance: (1) the reply streamed (server-sent events) into the bubble, which needs the network layer to read a response incrementally and the compositor's ticks to keep arriving during a request; (2) the API key kept in Secure (C170's store), never in memory longer than a request, and a cheap key check on Save; (3) conversations kept in storage (C125) with titles, search, rename and delete, system prompts, and temperature and token limits as settings; a configurable host for the local server; (4) images from Camera and Photos, files from Files and documents from Document as inputs, and the reply's code blocks highlighted; (5) a tool-use loop so a conversation can call other apps through capabilities, each with a confirmation; (6) a fixture against a mock server that streams a reply and checks the error paths for each provider's status codes. Not queued here: voice mode, image generation. PART (D2453): e.fmt.sse, an incremental Server-Sent Events reader (fmt_sse, 46 checks vs the standard's algorithm on whole streams and every prefix). Remaining: incremental reads from the network server over TLS, streaming into the bubble, keys in Secure, conversations, files, tools. PART (D4102-D4103): reply streams into the bubble over TLS (ai_stream), key checked and sealed in the Secure vault (ai_secure, ai_secure_again), conversations and options kept. Missing: images/files as inputs, tool-use loop, per-provider error-path fixture. PART (D5101, D5102): attachments, tool loop and per-provider error words are committed with a host test server; rows ai_err_anthropic/openai/google, ai_attach, ai_tools are NOT yet run on QEMU. Remaining: those boots.

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
