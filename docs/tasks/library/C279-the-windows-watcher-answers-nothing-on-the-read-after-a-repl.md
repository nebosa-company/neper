# C279 — the Windows watcher answers nothing on the read after a replacement

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open. os_watch fails with exit 27 on this host: after os.replace puts replacement.txt over seen.txt in a watched directory, the fixture expects the watch to report seen.txt as Modified. What has been established, each by a probe rather than by reading: the split of the exit codes shows the failing assertion is the one after the replacement, and the creation check before it passes, so opening a watch, making a change and reading once works. The replacement is reported as what this host calls it -- lib/e/os.windows.e maps FILE_ACTION_RENAMED_NEW to Added, and lib/e/os.linux.e maps IN_MOVED_TO to Added likewise, so the fixture's `.Modified` is the kqueue answer (the fixture's own comment cites macOS kqueue re-registration) and cannot arrive here. Relaxing that check to any event naming seen.txt still fails, so no event names the replaced path at all. Replacing the check with a drain -- read the replacement's events without asserting them, then write to seen.txt and read again -- fails at the second read, which returns zero records and is reported as an Overflow. That is the real defect: the second read on one watch, after a completed read and a re-arm, completes with no records. 6a74004a5 ('re-arm the Windows watcher') was the commit that last touched this path, so a regression there or in arm_watch's overlapped reset is the place to look. Acceptance: two consecutive watch_read calls on one Windows watch each report the change made between them; the fixture's replacement check accepts the action this host reports or drops it in favour of the write that follows; and os_watch exits 0 on Windows and Linux. Further, this round: probes in build/tmp-duckdb-probe (watchseq) show two consecutive watches on one directory each report their own change -- write a file, watch, replace it onto another name, read, close, watch again, write the replaced name, read -- so the watcher itself is sound and the fixture's assumption of one read per change was the wrong one: a write is reported as two records and a read collects only what completed the request armed before it, so two changes on one watch need two reads and the second waits for a third change. Rewriting the replacement section to open one watch per change, with the file made before its watch opens, and accepting whatever action the host reports for the replacement, carries the fixture past the replacement, the rewrite and the removal -- verified with markers: 'replace read done', 'rewrite read done', 'remove read done' all print. It then blocks in the #733 section: after the arena is filled until allocation fails and the read is expected to fail, the write that follows never completes the watch, so either that failed read does not re-arm or its re-arm fails silently. That section also allocates a megabyte at a time until the host refuses, which is what produced the out-of-memory kills seen while running it here, so it needs the arena to be bounded rather than exhausted against the machine. The fixture is left at HEAD: the replacement work is a real improvement but cannot be committed while a later section hangs.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.Modified`: `lib/e/fs/watch.e`×1, `lib/e/os.linux.e`×1‡, `lib/e/os.macos.e`×1‡, `lib/e/os.wasi.e`×1‡, `lib/e/os.windows.e`×1‡

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
