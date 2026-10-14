# Handover (2026-10-14)

Written for a session that continues this work from another Claude account. Read `AGENTS.md`/`CLAUDE.md` first;
this file is the state of the work and the traps found, not a replacement for them.

## Standing goal

`/goal keep on implementing everything in the backlog` — `docs/work-queue.json` holds the open items (84:
C 39, T 19, L 14, G 12). `docs/digest/queue.tsv` is the one-row-per-item view. Order, scoring and closing rules
are in `AGENTS.md` (close at score 1.0: remove from the queue, append one JSON line to `docs/work-done.jsonl`,
then `python scripts/render_progress.py`, `python scripts/render_digest.py`, `git checkout -- docs/tasks`).
`docs/progress.html` lists only pending/partial work; remarks live in `docs/work-evidence.md`.

## What is on master (local, 591 commits ahead of origin/master — NOT pushed)

Four parallel lanes of NeperOS work were merged this session (queue scores updated, decisions D4800–D5107):

| Lane | Items | Now |
|---|---|---|
| K | C152, C172 (Document), C150 (storage), C154 (Wallet) | 0.75 / 0.75 / 0.85 / 0.85 |
| L | C158 Mail, C159 Browser, C160 Maps, C156 Weather | 0.7 / 0.7 / 0.65 / 0.75 |
| M | C168 Steps, C176, C166, C167 Translate, C157 Call | 0.85 / 0.8 / 0.4 / 0.2 / 0.15 |
| N | C170 Secure, C164 Chat, C171 AI, C155 SSH, C173/C151 Dynamic | 0.7 / 0.55 / 0.5 / 0.5 / 0.6 / 0.5 |

Not started by any lane: **C153** (Camera sensor feed/video) and **C165** (Meet media transport). C161 stays 0.85
(real sensor hardware only). C104/C107/C147/C082/C088/C092, L048/L065/L136/L125/L098/L148/L066/L067/L163/L164
tails, T011/T004 (need decisions), T027 (provider) are as in the queue.

Merge-conflict resolutions worth knowing: `neperos/src/shell.e` (home_floor vs M's step widget; `widget_slot`
uses `installed_total`), `neperos/src/main.e` fs-grant condition lists (28 and 35 both included),
`host_services.py` (ai_services + WEB routes, both with their `return`), test PKI regenerated once with every SAN
(`ca.der/ca.pem/server.pem/server.key`, P-256, 2026-10-01..2125; root key discarded as before).

Lane worktrees (can be removed): `D:/Temp/lanes/{K,L,M,N}` on `lane-K..N`; all merged. Scratch harnesses:
`D:/Temp/lanes/run_suite_row.py` (a `fixture` row against the SUITE build), `run_seed_row.py` (seedfixture rows;
sets NEPEROS_RNG), `swap_prog.py` (replace one program of a shell archive), `net_boot.sh` (the network boot).

## The full Windows suite — state

Never yet green end-to-end. Run it from a **clean detached worktree**, not the shared tree (peers keep
uncommitted/committed work in `lib/e/ui/*` that breaks `ui_datagrid` and the conformance snapshot):

```
cd /d/temp/lanes/SUITE        # lowercase "temp": the dir's real casing, --absolute-paths conformance compares it
rm -rf build/windows/tests/selfhost/fs-scratch      # stale np-fs* from an aborted run fails e.fs (exit 224)
export NEPER_SEED='D:/Temp/neper-seed2.exe'
pwsh -NoProfile -File tests/selfhost/run.ps1 > /d/Temp/suite_full.out 2>&1
```

~3 h, sequential, no resume, one QEMU at a time. The SUITE worktree is pinned to `591e9a2c`
(= master `3fe23739` + the RNG commit, i.e. my merged state *without* the peer's later G012 commits). **A suite run
(#17) was started at 13:13 on 2026-10-14 and may still be running or have finished: read the tail of
`D:/Temp/suite_full.out` (look for `EXIT`) before starting another.** Everything up to the NeperOS
`seedfixture` rows passed in run 16; the standalone seed rows (12) all pass. Not yet reached in a full run:
`sheetfixture`, `moredocfixture`, `scanfixture`, `externalfixture`, `installdiskfixture`, `installseedfixture`,
`installappsfixture`, `livefixture`, `livediskfixture`, `liveseedfixture`, `diskfixture` (79 rows). Expect more
table-expectation drift there (see below). Linux `run.sh` has never been run (edits are by analogy).

Failures found and fixed this session (so you know the pattern): module-apis catalogue lines with bodies
(e.gfx.vision), library-fixtures manifest stale, `fmt_png_quant` path had a form feed, host_services.py lost
`return`s in a merge, shell.e `installed_len` scalar vs array, `flashlight_timer`/`blocks_hold`/`compass_replay`/
`clipboard_long`/`flashlight_strobe` timing rows (the **guest runs much slower than the wall clock**: size
waits/holds generously and assert the measurement line, D2462–D2477), `document_device` count 6→8, seedfixture
rows need `NEPEROS_RNG=1` (Secure vault). Two outstanding items outside this repo state:

- The peer's G012 commits changed `lib/e/os.windows.e` etc., so
  `tests/conformance/tools/plan_rename.x64-windows.expected.jsonl` (snapshot hash) is stale on master — whoever
  lands the grid work must refresh it. `lib/e/ui/control.e` has the peer's uncommitted edits: never touch it.
- Live rows `ai_*`, `ssh_sftp`, `ssh_key`, `ssh_terminal_keys`, `chat_two`, `chat_account*`, `weather_live`,
  `mail_live`, `browser_live` were never run after the merges (host-service port conflicts between lanes).
  Lane N left `D:/Temp/lanes/N_scratch/{getlock.sh,livebatch.sh}`; use the lock dir `D:/Temp/hostsvc.lock`.

## Practical traps

- Bash hook mangles backslashes in heredocs/`sed`: use the Edit tool, or `chr(92)` in Python; a `\f` once became a
  form feed in `run.ps1`.
- Do not edit source with Python old/new scripts (AGENTS.md); Edit tool or `build/windows/patch.exe`.
- Never `git add -A`; commit only touched paths. The shared tree has peers' untracked/modified files.
- `git cherry-pick $(git rev-parse HEAD)` in a worktree takes whatever a peer committed last — use hashes.
- `D:/Temp/resolve.py` keeps both sides of conflict markers (check the result: it left duplicated `if` lines once).
- Windows `-notmatch` on arrays, QMP timeouts (60 s, retries), shared ports 8443/8143/8025 (one lane at a time).
- Apps over ~1.6 MB need the two-level-3-table window (D2470/D2480); keep Mail/Document under 3.5 MB.

## Publishing

GitHub Pages serves `master:/docs`. Origin/master is **96342f14** (the blog post
`docs/blog/charts-speed-and-png-size.html` is live). Do not push local master wholesale: ~590 commits are untested
on the Linux suite. Publish by building a one-off commit on top of origin/master with a temp index (docs files
only), with `gh auth switch --user nebosa-company`. Pushing needs the user's explicit go-ahead.

## Next steps, in order

1. Read `D:/Temp/suite_full.out`; fix the first failure; rerun (or pre-check the row with the scratch runners).
2. Once a full run is green on a clean worktree: refresh the conformance snapshot after the peer lands, then run
   `tests/selfhost/run.sh` on Linux/WSL (WSL needs ~5 GB free commit).
3. Run the unrun live rows (list above), then raise C171/C155/C164/C173/C151 scores truthfully.
4. Continue the backlog in four lanes (worktrees `D:/Temp/lanes/<NAME>` on `lane-<NAME>`, brief in
   `D:/Temp/lane_brief.txt`): C153, C165, C167, C157, C166, then the remaining C/T/L items.
5. Quiet-machine rerun of `benchmarks/charts` timings is owed.
