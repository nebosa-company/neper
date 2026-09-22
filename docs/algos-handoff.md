# Prompt: continue the algos.md standard-library stream

Paste everything below this line into a fresh Claude Code session in `D:\repos\neper`.

---

Continue the algos.md standard-library stream in `D:\repos\neper` (Neper language,
self-hosted compiler). Read `CLAUDE.md` first, then this whole prompt, then
`scripts/algos/agent_brief.md`, and `docs/decisions.md` rows D834, D867, D872, D881,
D910, D912 and D915 for the conventions the stream settled.

## Where it stands (2026-09-22, master `96ea9e10`, D915)

`docs/algos.md` maps 1,218 selected algorithms to functions of the `e.*` library
(`→ e.mod.fn` annotations; `e.mod` in the legend is not a module). The stream is
**essentially complete**: 217 of the 218 planned modules exist and the modules meter on
`docs/progress.html` reads 99.94%. Count what is left with:

```
python - <<'EOF'
import re, os, collections
planned = collections.defaultdict(set)
for mod, fn in re.findall(r'→ `(e\.[A-Za-z0-9_.]+)\.([A-Za-z_][A-Za-z0-9_]*)`', open('docs/algos.md', encoding='utf-8').read()):
    planned[mod].add(fn)
alias = {'e.text.case': 'e.text.casing'}
for m, fns in sorted(planned.items()):
    if m == 'e.mod': continue
    p = 'lib/' + alias.get(m, m).replace('.', '/') + '.e'
    have = set(re.findall(r'^fn (\w+)', open(p, encoding='utf-8').read(), re.M)) if os.path.exists(p) else set()
    gap = sorted(fns - have)
    if gap: print(m, gap)
EOF
```

(`render_progress.py` also counts seeded intrinsics and fence declarations as present,
so `e.mem.mark` is not owed even though this script lists it.) What that prints today, and
why each was left:

- `e.fmt.opus.decode` — the one planned module without a file. RFC 6716's SILK and CELT
  decoders are several thousand lines of tables and DSP; it needs a dedicated multi-session
  effort, not one agent pass. If attempted: TOC/packet parsing first, then CELT-only
  narrowband, with `pip install opuslib`? (no) — validate against a Python replica of the
  reference decoder or against `soundfile`'s libsndfile Opus support (`soundfile` is
  installed; check it can read .opus).
- `e.os.{sandbox, send_file, signal, wait_u32}` — per-target syscalls behind the
  bootstrap-seeded `e.os` surface (see memory: "the fixed os surface is what the bootstrap
  seeds; add there only; variants already have the rest"). `wait_u32` exists on the
  variants (`e.thread.pool`, `e.sync.spin_lock` use it); the others need Windows and Linux
  implementations in `lib/e/os.windows.e` / `os.linux.e` plus the seeded surface entry and
  a suite pin. Compiler-adjacent; read D97–D132 first.
- `e.thread.fiber` — a context switch belongs in the runtime prefix
  (`src/runtime_*`, D149–D151), so it is compiler work.

## How the stream worked (for anything you add)

1. **Modules are written by parallel subagents** (Agent tool, background, 4–6 in flight)
   whose prompt starts with "Read `scripts/algos/agent_brief.md` first and follow it
   exactly", names the module/file/fixture/ok line, quotes the plan entries and names the
   Python reference. Agents work in the main tree, run only `check-file` and
   `bash build/fx.sh <fixture>` (copy `scripts/algos/fx.sh` to `build/fx.sh` first), touch
   no docs/git/suites. **Foundational modules** (`e.mem`, `e.gpu`, `e.io`, `e.os`, `e.str`,
   `e.bytes`, `e.atomic`, `e.sync`, `e.text.utf8`) are developed in a copy and dropped in
   only when they compile — a half-edited one breaks every build on the machine, including
   other sessions' (D912). Expect 5–30 min and 100–330k tokens per agent.
2. **Verify each report**: `python scripts/algos/join_structs.py lib/e/<path>.e` (every
   `type X = struct/union/enum {` on ONE line; joining changes line numbers, which can move
   a reject golden's span), then `bash build/fx.sh <new fixture>` AND every existing
   fixture of a touched module (`grep -rl "use e.<name>" tests/selfhost/fixtures/link/*/src/main.e`).
   For modules the compiler itself links (`grep -h '^use e\.' src/*.e`: `e.algo.hash`,
   `e.io`, `e.mem`, `e.os` and everything they import), also
   `build/windows/neper.exe build src/main.e --arena 1g --output build/probe.exe`.
3. **Describe the batch** in `scripts/algos/batchN.json` (shape in `add_batch.py`): a new
   module is `{name, deps, fixture, anchor, note, comment}`; an extended module is
   `{name, "refresh": true, comment}` plus `fixture` on one module per shared fixture and
   `deps` when its `use` lines changed (recompute: the batch44/45 generators in the
   transcript did it programmatically — compare `^use e\.` lines with
   `docs/modules.json` `direct_dependencies`). Append a `## D<n>` row to
   `scripts/algos/decisions-pending.md`.
4. **Register in the detached worktree `build/wt-algos`** (never the shared main tree):
   `git -C build/wt-algos checkout -q --detach master`, copy the modules/fixtures/
   `scripts/algos/*` (and `docs/algos.md` if you edited it) in, then
   `bash scripts/algos/reapply.sh build/wt-algos scripts/algos/decisions-pending.md batchN`
   (fences, modules.json, runner blocks, decision rows, surface check, staging incl.
   modified modules, renders). Pinned modules (`grep -n "expected_.*_surface='" tests/selfhost/run.sh`:
   audio_spatial, hash, bitset, ring, deque, list, sort, heap) are append-only and need
   `python scripts/algos/pin_surface.py . lib/e/<path>.e expected_<x>_surface expected<X>Surface`
   in the worktree. `e.algo.hash`'s artifact-interface pin (`-ne 26` / `= '26'` in the
   runners) is its declaration count.
5. **Linux fixture sweep** (~1 min): names into `build/linux_fx_list.txt`, then
   `MSYS_NO_PATHCONV=1 wsl.exe -e bash /mnt/d/repos/neper/build/linux_fx_all.sh`.
6. **Commit** in the worktree (`git commit -q -F build/commit-msg.txt`), then from the main
   tree `git update-ref refs/heads/master <new> <old>` (if master moved: `git rebase master`
   in the worktree first; conflicts are only ever `docs/decisions.md`/`progress.html` —
   take master's, re-insert your row, re-render), `git reset -q HEAD -- <your paths>`,
   `git checkout HEAD -- docs tests/selfhost/run.ps1 tests/selfhost/run.sh` ONLY after
   checking those working copies carry nothing of another session's, `git push origin master`.
7. **Full suites** when a batch touches something every program links, or every ~50
   features: Windows `build/run-suite-windows-algos.ps1` launched detached
   (`Start-Process pwsh -File ...`, log `build/suite-windows-algos.log` ends `EXIT:n`; run
   `wsl --shutdown` first — the WSL VM's memory otherwise starves the C bootstrap), Linux
   `MSYS_NO_PATHCONV=1 wsl.exe -e bash /mnt/d/repos/neper/build/linux_suite_algos.sh` from
   the Bash tool in the background (`build/suite-linux-algos-tail.log` ends `exit=n`).
   One WSL VM: message the peer UI session ("Neper", bridge address in the transcript)
   before and after. `.wslconfig` caps the VM at 5 GB with 8 GB swap on D: — without the
   cap the VM is torn down mid-build when C: is nearly full.
8. **When goldens move** (a module every program links changed: every tools-corpus
   snapshot golden, the module's digests, explain-inline rows, reject spans, the static
   gate): `python scripts/algos/make_refresh_runners.py build/wt-algos` writes
   `run-refresh.ps1/.sh` that copy actual over expected instead of failing; run those
   (Windows via a launcher like `build/run-refresh-windows.ps1`, Linux via a copy of
   `linux_suite_algos.sh` pointing at `run-refresh.sh`), normalise the re-pinned baselines
   with `scripts/algos/fix_baseline_paths.py` and set their `revision`, then **audit every
   refreshed golden's diff** (only `snapshot`, `*_sha256`, `.value` module digests, `inline`
   rows for the grown module, or a moved span may differ — the audit script is in the
   D915 transcript and easy to rewrite), delete the generated runners, run the real suites
   clean, and name the re-pin in the decision row (D506 zero-growth rule for the gate).

## Numbers and peers

Decision numbers: this stream owns D916–D939 by agreement with the UI session; a third
session has been taking numbers without agreement (it used D911, D913, D914, D916), so
always `grep -c '^## D<n> ' docs/decisions.md` before writing a row and skip taken ones.
The UI session ("Neper") owns `lib/e/ui/*` and `lib/e/os/shell*`; do not edit those.

## Language facts the agents keep hitting (also in the brief)

`ret f()` cannot forward a tuple; `try` only in a plain-`err` function (in a tuple-returning
one it passes the checker and fails at lowering); `let _ = f()` for a discarded result;
reserved or colliding names: `case`, `error`, `target`, `shared`, `next`, `at`, `main`,
`capacity`, `use`, `Vec`, `default`, `union`, any module-scope fn of the same module (adding
one breaks older functions' locals of that name), any import alias, `.len`; a `let`/tuple
name may not be rebound in a sibling block; `[N]T{ a, b }` array literals, but an inline
literal cannot be sliced (bind first); `&Struct { ... }` as an argument is refused; a `u32`
cannot index a slice; `arr[i] = zero` and `p.field = zero` through a pointer are refused;
`a += b - c` traps on the subtraction; `else` must share the line with `}`; a bare `{ }`
block is a syntax error; intrinsics (`e.atomic.*`, `mem.address_of`) cannot be called
unqualified from their own module; `Atomic[T]` fields inside a generic struct work; an
indexed fn pointer must be bound before it is called; bash heredocs mangle `\n`, `\"` and
apostrophes (use Write/Edit); `mem.alloc` memory is not zeroed.

Start by running the count above; if only the three deferred items print, the stream is
done and the remaining work is theirs (opus, os syscalls, fibers), each a project of its own.
