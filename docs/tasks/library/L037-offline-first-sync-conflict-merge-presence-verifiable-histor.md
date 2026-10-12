# L037 — Offline-first sync, conflict merge, presence, verifiable history

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.80 of 1 |
| queue position | 54 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Appdor src/offline (coalescing enqueue, cursor pullChanges, field-level conflict detect with manual/LWW/field-merge resolve, durable queue with dead letters), src/sync (mapping propose, lease claim, doubling backoff, drift accept), src/history (diffRecords, revision replay, sha256 prev-plus-canonical tamper-evident chain), src/realtime (30s-TTL presence, version-or-LWW merge; polling transport flagged). Port into e.algo.sync/merge/queue/diff/chain/presence. PART ONE DELIVERED (D2336): lib/e/algo/chain.e, e.algo.chain -- the hash chain, diff, WAS/CHANGED predicates, history filter, field history, plan retention and export; fixture algo_chain, 220 scripts against appdor's tamper-evident.js on Windows and Linux. PART TWO (D2337): lib/e/algo/sync.e, e.algo.sync -- src/offline index.js, durable-queue.js and sync-engine.js: coalescing queue, durable outbox (backoff, dead letters, quota-aware persistence, attachment holds), cursor and delta pull, field-level conflicts and resolution, run_sync; fixture algo_sync, 260 scripts against appdor's own modules on Windows and Linux. PART THREE (D2338): lib/e/algo/realtime.e, e.algo.realtime -- presence, cell resolution, record merge, viewer filter, degradation, topic authorization, connection lifecycle, telemetry, payload trimming, view membership; fixture algo_realtime, 220 scripts against appdor's src/realtime on Windows and Linux. NOT DONE: src/offline write-queue.js, conflict-review.js, read-cache.js, access-purge.js; src/sync (mapping, lease, backoff, drift). PART FOUR (D2339): lib/e/algo/syncjob.e, e.algo.syncjob -- src/sync sync-schedule.js, sync-refusal.js and the pure half of synced-table.js with syncPlan; fixture algo_syncjob, 700 inputs against appdor's own modules on Windows and Linux. NOT DONE: src/offline write-queue, conflict-review, read-cache, access-purge; src/sync writeback.js, change-stream.js, entity-browse.js, proposeMapping/pagination parts of synced-table.js, sql-source.js.

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
