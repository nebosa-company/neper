# T011 — info

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.95 of 1 |
| queue position | 45 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | low — rated for a small model; a whole checklist line per session is realistic |

## Definition of done

The contract is `docs/tooling.md`, section `## 1. Version and stream envelope` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `info --json` (D229): the header, one `info` record -- tool version, the one language profile, the commands the stream reaches (`check`, `info`, `parse`, `tokens`), the host target, both build targets, the one CPU level the emitter honours -- every collection sorted by bytes, and a result; tests/conformance/tools pins it per host. `commands` names every section 1 command the stream reaches -- build, check, dis, fmt, index, info, parse, run, test, tokens -- sorted by UTF-8 bytes (D259); it had stopped at the four of D229. `--language-version MAJOR.MINOR` on any command selects the one advertised profile, 0.1, and is taken off the arguments; another version is E-CLI-9999 before any source is read, as a stream whose header names the command (D283, tests/conformance/tools/info_version)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a `features` list beyond empty
- [ ] the other CPU levels of the spec's table

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D229` — `info --json` is the capability query, pinned per host (`docs/decisions.md:4158`)
- `D259` — `info` names every command the stream reaches (`docs/decisions.md:4925`)
- `D283` — `--language-version` selects the advertised profile, or refuses before reading (`docs/decisions.md:5588`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `language-version`: `src/main.e`×2‡, `scripts/render_card.py`×1

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
