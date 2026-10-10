---
name: neper
description: Edit, build and verify Neper (.e) source in this repository: card first, context-file before file reads, patch or plan-* before scripts, check-fixture to verify.
---

# Working on Neper source

Read `AGENTS.md` first (shared-tree and queue rules), then `docs/llm-neper-card.md`:
its Traps section lists what ends most builds (`target`, `Vec`, `i8`, `ok`/`err`/`error`
as names, a local reusing a module-scope name, a tuple call returned directly, the
`\xHH` escape set, bootstrap-only rules). Do not write Neper from Rust, Zig or C habits.

## Order of work

1. Locate before reading: `docs/digest/queue.tsv` and `docs/digest/decisions.tsv` for the
   queue and the decision log, then `grep -n "^## D<n> " docs/decisions.md` for one entry.
   Never read `docs/decisions.md` or a large source file whole.
2. Resolve symbols with the compiler, not by reading files:
   `neper index --json`, `neper context-file --symbol module.name --budget 2000`,
   `neper uses-file --symbol module.name`. A function's answer is 1-5 K tokens; its file
   is 100 times that.
3. Change with `build/windows/patch.exe` (a spec of `@@@ / <<< / === / >>>` sites with
   file preconditions) or the Edit tool. Use `plan-rename-file`, `plan-add-parameter-file`,
   `plan-change-signature-file` or `plan-replace-expression-file` and `apply-plan` for a
   rename, a parameter or a signature. Do not write a Python script that carries
   `old`/`new` strings; a script is for content it computes.
4. Verify one fixture, not the suite: `scripts/check-fixture.sh <fixture>` (host
   compiler and target), then `neper check-file` / `fmt --check` on what you touched.
   The full suites run once per batch, at merge.
5. Repair from the diagnostic's identity: its code (`E-XXXX-nnnn`), span and
   expected/actual. A code repeating across consecutive failures means the message was
   misread; re-attach the subject. The diagnostic's `fixes` are machine-applicable.

## Rules that hold everywhere

- The working tree is shared: commit only the paths you touched, never `git add -A`.
- Name the queue item (`L0xx`/`C0xx`/`T0xx`) and its acceptance list in every build
  prompt; append design decisions to `docs/decisions.md` as `## D<n> — title`.
- `docs/progress.html` is generated (`python scripts/render_progress.py`), never edited.
