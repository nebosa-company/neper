# C158 — NeperOS Mail remainder: accounts, folders and threads, HTML and attachments, notifications

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.70 of 1 |
| queue position | 53 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C128 (D2413): Mail syncs the INBOX of a fixed test account over IMAP and sends over SMTP, on TLS, and marks read and deleted on the server. Acceptance: (1) accounts added in the app (server, user, password kept in Secure, C116), OAuth for the large providers, several accounts, folder list and sync, IDLE or polling for push; (2) threads, labels, search, archive, mark unread and swipe actions done on the server; (3) rich messages: MIME multipart, HTML rendering through the Document engine (C123), inline images, attachments saved into Files (C125) and opened in their apps; (4) compose with attachments from Files, Photos and Camera, drafts, signatures and the contact picker (the vCard store, C127/C157); (5) notifications through the status server and a badge on the icon; (6) a fixture against the test IMAP and SMTP server that fetches, threads, searches, replies with an attachment and checks the sent message. PART (D2448): MIME bodies (multipart/alternative, HTML-only, quoted-printable) shown as text through e.fmt.extract; fixture mail_live. Remaining: HTML rendering through Document, inline images, attachments, compose with attachments, accounts/folders/threads, push. PART (D3903): Mail lists and saves multipart attachments (mail_attach, base64 menu.txt); verified on the pre-L125 image, and D2470 now lets the grown Mail image launch. Missing: HTML via Document, inline images, compose attachments, accounts, folders, threads, push. PART (D4900-D4906): mailboxes and folder switch, HTML newsletter with inline PNG, threads, accounts kept in /mail_accounts, compose with attachment, search/unread/archive on the server, polling plus notification, Open in Document; rows mail_html, mail_threads, mail_document, mail_open_attachment, mail_accounts(+_again), mail_attach(+_again), mail_actions, mail_push, mail_live_delete(_after) passed before the master merge (post-merge live rows unrun: CA mix-up with another lane host service). Remaining: OAuth, Secure-stored passwords (C116), drafts/signatures/contact picker, IDLE, Camera/Photos attachments, icon badge.

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
