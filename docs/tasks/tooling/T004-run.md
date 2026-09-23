# T004 — run

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.88 of 1 |
| queue position | 33 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

The contract is `docs/tooling.md`, section `## 7. Test, build and command results` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `run PATH ROOT ARCH OS OUTPUT [--release] [--arena SIZE] --json` (D231): a build, then the program is launched with its stdout and stderr to files beside the executable and read back whole into one `run` record with the process exit code, captured bytes base64 when they are not UTF-8 (section 2); tests/conformance/tools/run.e exits 3 and writes a non-UTF-8 stderr byte. A trap's record is read back out of stderr as the structured `trap` payload (D253): its kind, a byte-precise zero-width span at the site when the file is the operand, the record's values text as one entry, and one backtrace frame per `  at` line with its qualified function, the operand source where the frame lies in it, and its line; tests/conformance/tools/run_trap.e pins a bounds trap two frames deep, spelled relative to the test build dir so the golden carries no host path. `-- ARGS...` after the flags reaches the program as its arguments on both hosts, spaces kept (D267, tests/conformance/tools/run_args.e echoes three and exits with their count); a relative OUTPUT with directories launches on Windows too, spelled the host's way. A Linux build writes its executable mode 0755 and `run` and `test` launch it directly, no `sh -c` and `chmod` in front (D291: `os.set_mode` joined the bootstrap's fixed surface, the per-host `e.os` source having it); the Linux suite requires the corpus build's executable to be one. a trap and a frame in another module name that module's source under its own root with the line and column the child printed (D503; `run_trap_module`), where both were null

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] streaming
- [ ] a project root

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D231` — `run --json` builds then launches, capturing the whole output (`docs/decisions.md:4189`)
- `D253` — A trap's record is read back as the `trap` payload, under `run` and `test` (`docs/decisions.md:4761`)
- `D267` — `run` passes what follows `--` to the program (`docs/decisions.md:5139`)
- `D291` — A Linux build writes its executable executable (`docs/decisions.md:5737`)
- `D503` — A trap in another module, sourced (`docs/decisions.md:10736`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `chmod`: `benchmarks/scale/profile_own.sh`×2, `benchmarks/differential/bootstrap.py`×1, `benchmarks/differential/differential.py`×1, `benchmarks/metamorphic/metamorphic.py`×1, `benchmarks/scale/profile.sh`×1, `benchmarks/scale/profile_check.sh`×1, `benchmarks/scale/profile_edit.sh`×1, `benchmarks/scale/profile_warm.sh`×1
- `os.set_mode`: `src/main.e`×2‡, `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×2, `lib/e/fs.e`×1
- `e.os`: `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×164, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×145, `src/resolve.e`×36†, `lib/e/ui/app.e`×12†, `lib/e/os.linux.e`×9‡, `src/check.e`×8‡, `lib/e/fs.e`×7, `lib/e/os.windows.e`×7‡

## Existing fixtures

- `tests/conformance/tools/run.e`
- `tests/conformance/tools/run_trap.e`
- `tests/conformance/tools/run_args.e`

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
