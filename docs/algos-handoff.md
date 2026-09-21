# Prompt: continue the algos.md standard-library stream

Paste everything below this line into a fresh Claude Code session in `D:\repos\neper`.

---

Continue the algos.md standard-library stream in `D:\repos\neper` (Neper language,
self-hosted compiler). Read `CLAUDE.md` first, then this whole prompt, then
`scripts/algos/agent_brief.md`, `docs/decisions.md` rows D834, D857, D867 and
D869–D871 for the conventions the stream settled.

## What the stream is

`docs/algos.md` maps 2,250 algorithms to functions of the `e.*` library (`→ e.mod.fn`
annotations). The job is to implement the modules that do not exist yet, five modules
per batch, each module with a link fixture whose expected values come from a Python
reference (scipy, numpy, scikit-image, networkx, a replica of the algorithm), and to
register every batch so `docs/progress.html` counts it. 177 modules landed so far
(through D871). Count what is left with:

```
python - <<'EOF'
import re, os, collections
planned = collections.defaultdict(set)
for mod, fn in re.findall(r'→ `(e\.[A-Za-z0-9_.]+)\.([A-Za-z_][A-Za-z0-9_]*)`', open('docs/algos.md', encoding='utf-8').read()):
    planned[mod].add(fn)
missing = sorted((m, len(f)) for m, f in planned.items() if not os.path.exists('lib/' + m.replace('.', '/') + '.e'))
print(len(missing), sum(n for _, n in missing)); print(*missing, sep='\n')
EOF
```

(`e.text.case` is already implemented as `e.text.casing` — `case` is a keyword — and
`e.concurrent.queue`, `e.net.http`, `e.net.tls`, `e.crypto.aead/hash/kdf/kx/mac/sign`
exist; only the named functions missing from them are owed. Ignore modules whose file
exists.)

## How a batch is produced (the cycle that works)

1. **Modules are written by parallel subagents**, one module (or 2–4 small ones)
   each, launched with the Agent tool in the background, 4–6 in flight. Each agent's
   prompt starts with "Read `scripts/algos/agent_brief.md` first and follow it
   exactly", names the module, its file, its fixture name and ok line, lists the plan
   entries (grep `docs/algos.md` for `` `e.mod. ``), sketches the API, and names the
   Python reference to verify against. Agents work in the main tree, run only
   `build/windows/neper-try.exe check-file …` and `bash scripts/algos/fx.sh <fixture>`
   (copy it to `build/fx.sh` first: the brief and agents call `bash build/fx.sh`),
   touch no docs, git or suites, and keep their scratch in a subdirectory of the
   session scratchpad (one agent once wiped the scratchpad root — the brief says not to).
   They report the public functions, the module's `use` lines, deferrals (`ponytail:`
   comments) and compiler quirks. Expect ~5–20 min and ~100–200k tokens per agent.
2. **When an agent reports**, verify yourself: `python scripts/algos/join_structs.py
   lib/e/<path>.e` (every `type X = struct/enum {` must be ONE line or the suite's
   fence check fails), then `bash scripts/algos/fx.sh <fixture>` must print the ok
   line twice (`neper-try` and `neper-self`). Write the batch description
   `scripts/algos/batchN.json` (shape in `add_batch.py`: name, deps = the module's
   `use` lines, fixture, the fence `anchor` heading it is inserted before in
   `docs/module-apis.md` — `### \`e.grep\`\n` for new top-level modules, a sibling's
   heading otherwise — a `note` paragraph and a one-line `comment` for the runners),
   and a decision row `## D<n> — <title>` appended to
   `scripts/algos/decisions-pending.md` (five to twelve lines: what landed, what was
   measured against, what was deferred, one lesson). Decision numbers: the stream
   owns **D872–D884**; the peer UI session starts at D885 — if you need more, message
   that session ("Neper") first and agree a block.
3. **Registration and suites happen in the detached worktree `build/wt-algos`**
   (create it with `git worktree add --detach build/wt-algos master` if absent),
   never in the shared main tree, because another session commits there:
   - copy the modules and fixtures into the worktree, and `scripts/algos/*` too;
   - `git -C build/wt-algos reset -q --mixed master`, then `git checkout master --
     <every file master changed since the worktree's base>` (drop files master
     deleted), so the peer's versions of the shared files are the base;
   - `bash scripts/algos/reapply.sh build/wt-algos scripts/algos/decisions-pending.md
     batchN batchN+1 …` (fences, modules.json, runner blocks, decision rows, surface
     check, staging, `render_progress.py`, `render_tasks.py`);
   - Linux fixture sweep (fast, ~5 min): write the fixture names to
     `build/linux_fx_list.txt` and run `MSYS_NO_PATHCONV=1 wsl.exe -e bash
     /mnt/d/repos/neper/build/linux_fx_all.sh` (see that script; it uses the
     worktree's `build/linux/tests/selfhost/neper-self`);
   - full suites every 50 modules (user rule; last full pair passed at D868 with
     165 modules, and the 12 of D869–D871 were fixture-swept on both hosts): Windows
     `build/run-suite-windows-algos.ps1` (log `build/suite-windows-algos.log`, ends
     `EXIT:n`, ~1 h), then Linux from the Bash tool in the background:
     `MSYS_NO_PATHCONV=1 wsl.exe -e bash /mnt/d/repos/neper/build/linux_suite_algos.sh`
     (tail log `build/suite-linux-algos-tail.log` ends `exit=n`, ~1 h). One WSL VM:
     never two Linux jobs at once, and message the peer session before and after.
   - commit in the worktree with explicit paths already staged (`git commit -F`),
     then `git update-ref refs/heads/master <new> <old>` from the main tree, then in
     the main tree `git reset -q HEAD -- <your paths>` and `git push origin master`;
     tell the peer the new SHA (their working copies of the shared files are then
     behind HEAD).
4. Memory of the host: 16 GB, C: nearly full (the pagefile cannot grow), WSL has 8 GB
   swap on D:. Under pressure the WSL VM dies at the suite's release stage and the
   Windows suite can fail with "the compiler's arena is exhausted" (a commit failure,
   not a code problem): run fewer agents while a suite runs, and rerun.

## Language facts the agents keep hitting (also in the brief)

`ret f()` cannot forward a tuple; `try` only in a plain-`err` function; `let _ = f()`
for a discarded result; reserved or colliding names: `case`, `error`, `target`,
`shared`, `next`, `at`, `main`, `capacity`, `use`, `Vec`, any module-scope fn of the
same module, any imported module alias, `.len`; `[N]T{ a, b }` array literals; no
`const X: f64/str` (use a function); no if-expressions, no `break`, no `\u` escapes;
narrowing conversions and `u64(negative)` trap; `mem.alloc` memory is not zeroed;
bash heredocs and `sed` mangle `\n` and apostrophes (use the Write/Edit tools);
multi-line struct/enum declarations break the fence check. `*f64` parameters work
since D867.

## Where it stands

- master: batches 1–30 landed (D834–D871); the fixed-point suites are green as of
  D868's tree; the 12 modules of D869–D871 passed their fixtures on both hosts.
- Remaining (~70 modules): e.fmt codecs (lz4, snappy, brotli, lzma, flac, opus,
  avro, parquet, arrow, flatbuffers, jwt), e.db.query (16), e.db.storage (18),
  e.db.pool, e.net.* (balance, coap, dns, http.auth, http3, idna, mqtt, quic,
  reliable, stun, plus the missing http/tls functions), e.crypto.* missing functions
  (cipher, classic, merkle, noise, secret, and the named hash/kdf/kx/sign entries),
  e.thread.pool (5), e.concurrent (deque, stack, reclaim), e.text.segment and
  e.text.bidi (need Unicode property data — check `lib/e/text/unicode.e` first),
  e.ui.state, e.ui.undo, e.mod, e.algo (smt, privacy, egraph, geo, query),
  e.test.* leftovers, e.game.grid/ai missing functions. Do the pure ones first;
  thread/atomic modules last (read `lib/e/thread.e`, `lib/e/atomic.e`,
  `lib/e/concurrent/queue.e` before those).
- Batch JSONs already used are `scripts/algos/batch28–30.json` (templates).

Start by running the count above, then launch the first wave of agents.
