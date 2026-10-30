# Handover: the Neper browser (conformance, the app, its targets) — updated 2026-10-30

The one browser handover. For another session or account continuing the work. Goal in force (user, repeated by a Stop hook every turn): **keep implementing the browser until it is fully implemented**, ending in **Neper-native applications**, tested on **Windows, Linux and the web (wasm32-wasi)**. Android and iOS do not compile yet. HTTP/3, WebSockets and WebGL are out of scope. Nothing here is "done"; this is a pause.

The other handover documents were reviewed and are different streams, left untouched: `HANDOVER.md` (2026-10-14, a general account-to-account note), `HANDOVER-GRID.md` (the data grid, G012), `docs/ui/26-10-20-HANDOVER-UI-LIB-L-and-F.md` (UI looks and feels), `docs/implementation-handoff.md` (a 2026-09-06 historical snapshot) and `docs/algos-handoff.md` (a prompt for the algos stream).

## 0. Resume in five commands

```bash
cd D:/repos/neper-wt-browser            # a worktree of D:/repos/neper on branch browser-conformance
git status --short | grep -v '^??'      # expect: M lib/e/fmt/css/layout.e (section 2)
git log --oneline -3                    # head was 972d92d22 (decisions D5940-D5942) before the uncommitted work
gh auth status | grep -B1 Active        # must be nebosa-company; oboobortot gets a 403 on this repository
D:/repos/neper/build/windows/neper-self.exe emit-executable tests/browser/wpt/run.e . x64 windows build/windows/run-wpt<N>.exe
```

Compilers live in the **main checkout** (`D:/repos/neper/build/windows/`); the worktree's `build/windows` is cleaned. Use `neper-self.exe` (`neper-try.exe` fails type-checking on any edit to `run.e`). Use a new `run-wpt<N>.exe` name per build.

## 1. State

- **Branch** `browser-conformance`, pushed to `origin/browser-conformance`, **86 commits ahead of `origin/master`, 1 behind**. `origin/master` was merged in on 2026-10-30 (4a7eb5077): the merge was clean for all source; only `docs/digest/*`, `docs/progress.html`, `docs/work-done.jsonl`, `docs/work-evidence.md` and `docs/work-queue.json` conflicted, resolved by taking master's and re-adding the browser's L172-L174 records, then `scripts/render_digest.py` and `scripts/render_progress.py`. **No pull request exists yet.** The next step for landing it is a PR from `browser-conformance` into `master`.
- **Last gated numbers** (runner `tests/browser/wpt/run.e`, build `run-wpt190`, committed code, 2026-10-30):

| Suite | Passing | Note |
|---|---|---|
| css/CSS2 | 5152 / 5829 | was 5118 on 2026-10-20 |
| css-flexbox | 634 / 908 | |
| css-grid | 719 / 1545 | |
| css-writing-modes | 622 / 995 | |
| css-sizing | 318 / 457 | 311 at the start of the session |
| css-multicol | 182 / 402 | 157 before D5940 |
| css-overflow | 274 / 501 | line-clamp is the biggest cluster (113 failing), then scroll-markers (44) |
| css-lists | 99 / 125 | 80 at the start |

  JavaScript: test262 96.2% (43619 of 45356 run, 8260 feature-gated skipped), measured 2026-10-18, recorded in `docs/browser-progress.html` row 5.14; the tree has more JS fixes since. Not re-measured. html5lib is 1791 of 1791.
- **Decision rows** D5940 (multicol column starts), D5941 (the app's scripts, taps, fonts) and D5942 (the wasm build) were appended. D5940-D5942 are a small block above master's maximum at the time (D5935); a peer using the same numbers will conflict, renumber when merging.
- **Queue evidence not updated:** L166 (`score 0.20`) and the others were not touched beyond the L172-L174 records. The queue's first item is C104 (NeperOS on a Pixel), not a browser item; `AGENTS.md` says to work only on the first item, which the browser branch does not follow. Decide with the user whether browser evidence goes in the queue.

## 2. Uncommitted in the worktree (not gated)

`lib/e/fmt/css/layout.e`, +23 lines, `contain: size` with `contain-intrinsic-*`:
1. `self_collapsing` returns false for a size-contained box with a positive intrinsic height (an empty contained block was collapsing to 0).
2. `size_contained` reads `contain-intrinsic-inline-size` and `-block-size` (inline is the width in a horizontal mode, the height in a vertical one).
3. `layout_contents_height` (atomic inlines) and `flex_place_item` (flex items) take the intrinsic height when contained.

Measured: `css/css-sizing/contain-intrinsic*` 8 → 18 of 27 (`run-wpt194`); full css-sizing was 324 with change 1 alone (`run-wpt191`). **Not run:** css-sizing, flexbox, grid, writing-modes, multicol, overflow and CSS2 on the final diff (a chain on `run-wpt193` was stopped; it lacked the flex change anyway). Gate it, then commit and push. Still failing in that directory: 008 (vertical-writing box), 012, 014, 017, 020, 023, 025, 027, logical-002.

`git status` may also show untracked `docs/tasks/...` files from the task renderer; leave them (see the memory note on `render_tasks`), never `git add -A`.

## 3. The app and its three targets

`examples/browser/main.e` is the windowed browser (tabs, omnibox, back/forward/reload, star, history, profile file `neper-browser.profile` in the working directory), over `lib/e/web/shell.e` and `lib/e/web/page.e`. Build **with a large arena**:

```bash
C=D:/repos/neper/build/windows/neper-self.exe
$C emit-executable examples/browser/main.e . x64 windows OUT.exe --arena 4g
$C emit-executable examples/browser/main.e . x64 linux   OUT      --arena 4g
# wasm needs a compiler built with a bigger arena (the stock one runs out of arena on this program):
$C emit-executable src/main.e . x64 windows D:/Temp/neper-big.exe --arena 6g
D:/Temp/neper-big.exe emit-executable examples/browser/main.e . wasm32 wasi build/wasm-sweep/neper_browser.wasm
```

- **Windows:** verified (rendering, scripts, timers, real clicks, `rules.html`). The default arena makes every https page fail as "not private" (the tab arena and the TLS chain check share it; an RSA verify that cannot allocate returns false, which `x509.verify` reports as `UnknownAuthority`; the mislabel is not fixed).
- **Linux:** verified on a virtual display (rendering, wheel scroll, a real click on an `onclick` div, `rules.html` combo toggle). Recipe: WSL has `Xvfb` and `xdotool`; WSLg mounts `/tmp/.X11-unix` read-only, so run `wsl -u root -e unshare -m bash script.sh` where the script does `mount -t tmpfs none /tmp/.X11-unix`, `export HOME=/home/gaddl`, starts `Xvfb :99 -ac -screen 0 1280x900x24`, serves the page with `python3 -m http.server`, runs the binary with `DISPLAY=:99`, drives it with `xdotool` (`click 5` is wheel down), and `xwd -root -display :99 -out f.xwd`. Convert XWD (25 big-endian header words, 32-bit BGRA) with PIL. Fonts: DejaVu files are in the face list. The Linux binary was not re-run after the last font edit (4a19b7a85) or after the merge.
- **Web (wasm32-wasi):** `tests/wasm/browser/neper_browser.html` runs the app on a canvas; serve with `node scripts/serve-wasm.mjs --isolated --port 8765` (the window needs a cross-origin isolated page) and open `/tests/wasm/browser/neper_browser.html?url=<encoded data: URL>`. Verified once in the Browser pane with a `data:` page. **Not verified on the web:** scripts, clicks, scrolling. The host (`lib/wasm/neper-host.js`) has no sockets, so only `data:` pages and seeded files load; web networking needs a host bridge. Fonts are the two Jost files the page seeds (`jost-regular.ttf`, `jost-bold.ttf`); there is no italic.

Things that silently broke pages before, all fixed and recorded in D5941: a 128 MB tab arena starved the page's JS runtime (now 512 MB, so about 7 tabs fit a 4 GB arena); a pending timer never ran in an idle window; a tap reached links only, never `onclick`; the renderer held 16 fonts and dropped the rest (now 32).

## 4. The loop that works

1. Pick a failing cluster: `build/windows/run-wpt<N>.exe --show --only css/<suite>/ D:/wptdata/wpt/MANIFEST.txt > f.txt`, then count by prefix (`grep FAIL f.txt | sed -E 's/-?[0-9]+[a-z]?\.(x?html?|xht)( \(match\))?$//' | sort | uniq -c | sort -rn`).
2. See one test: `--only css/<suite>/<test> --out D:/Temp/rv` writes `.test.png` and `.ref.png` for failures only. The reference is rendered by our engine too; read the reference markup before trusting it. Compare run-lengths or bounding boxes with PIL.
3. **`--text` prints every laid-out fragment as `x,y:text`** (`lib/e/ui/html_view.e` `fragment_text`). It found the counter, multicol and font bugs; use it before reading pixels. Empty boxes have no fragment, so colour runs in the PNGs are the only view of them.
4. Fix in `lib/e/fmt/css/layout.e` (or `style.e`, `paint.e`). Apply multi-site edits with `D:/repos/neper/build/windows/patch.exe spec` (`@@@ path` / `<<<` / `===` / `>>>`), single edits with the Edit tool; never a Python patch script.
5. Gate before every commit, no suite may drop: css-lists, css-multicol, css-overflow, css-sizing, css-flexbox, css-grid, css-writing-modes (10-15 min each, quicker if run one at a time) and CSS2 (**about two hours** on this machine; a monitor on a done-file, not chained sleeps). A sweep that "stops growing" is usually one slow test; check CPU before killing.
6. Commit only your paths with the Co-Authored-By trailer, and **push after each commit** (the user asked for commits and pushes from time to time). Pushes need the `nebosa-company` GitHub account.

## 5. Traps

- Compiler "arena exhausted": the compiler itself needs a bigger arena (build one with `--arena 6g`); a program's `--arena` is separate. `neper-try.exe` mis-types edits to `run.e`.
- A PowerShell window capture of the app must call `user32 SetProcessDPIAware()` first, or `GetWindowRect`/`PrintWindow` crop the top-left of the real window and a correct render looks clipped. Capture only the app window (`PrintWindow` on `MainWindowHandle`), never the whole screen: the user's other windows (a browser with their tabs) are on it.
- Real mouse input: use `docs/grid-parity/drive.ps1` (it shows the warning-emoji overlay the user requires). Posted `WM_*` messages scroll but do not click.
- The app refuses `file://` by design; serve a folder with `python -m http.server` (use `D:/tools/neper-pyenv/Scripts/python.exe -I`). Git Bash has no python.
- Multicol: one tall column is laid out and then sliced. D5940 builds a table of column starts (`mc_prepare`, `column_of`, `col_start`, `col_end`, `col_dy`) for the plain balanced case only; spanner runs (`colify_run`) and `column-wrap` rows keep the old formula.
- `self_collapsing` (empty blocks) runs before the block layout path: anything that gives an empty block a height (size containment, now) must be checked there too.
- A passing test can pass by coincidence (test and reference wrong the same way); judge a flip by what newly fails.
- Windows is Git Bash: `D:/...` to the `.exe` tools, `/d/...` to bash tools.

## 6. Open work, largest first

- **css-multicol (220 failing).** The clusters: `column-height` 24 (css-multicol-2: `column-wrap`, `column-height`, row gaps), nested multicol 21 (an inner container with `column-fill:auto` and a fixed height fragmenting across the outer's columns), fill-balance 17 (nested and flex-item multicols, a flex-stretched multicol needs a re-layout with the definite height), span-all 14+11+11, `multicol-columns`/`multicol-breaking` ~20. Fixing the nested and spanner cases needs **fragmentation-aware inner columns**, not another slice tweak.
- **css-sizing (139 failing):** aspect-ratio 53, contain-intrinsic-size (section 2), intrinsic-percent 14, stretch 13, replaced-aspect 5, float-clearance 4, fit-content 4, box-sizing-replaced 3 (one image is 9 px too wide; per-image sizes not traced), svg-intrinsic 3, range-percent 3. `block-aspect-ratio-with-margin-collapsing-002` is unresolved.
- **css-flexbox 274, css-grid 826, css-writing-modes 373, CSS2 677** still failing; the 2026-10-20 cluster notes (grid-lanes, subgrid unimplemented, baseline alignment, bidi) still describe them. css-overflow: line-clamp 113, scroll-markers 44, text-overflow-string 21.
- **The browser as a product:** page scripts, timers and clicks work on small pages and on `rules.html`; **real-site behaviour is unmeasured** (jQuery 3.5.1 init, AJAX re-render, iframes, `getBoundingClientRect` feedback), as is performance and memory. Form controls, text input, selection, favicons and downloads are not checked. Broken images draw their alt text but not Chrome's broken-image icon.
- **Web target:** networking, and scripts/clicks/scroll unverified; fonts are Jost only.
- **Not done:** the `x509.verify` out-of-memory mislabel (change `sign.rsa_pkcs1v15_verify_hash` to report an error, three callers plus fixtures), queue evidence for L166-L171, a decision for the 898-commit local `master` (below).

## 7. Branches not merged into master (checked 2026-10-30, `git branch --no-merged origin/master`)

87 local branches are not merged into `origin/master`; most are other agents' work, listed so nobody deletes them blind.

- **Mine:** `browser-conformance` (86 ahead, 1 behind `origin/master`; pushed as `origin/browser-conformance`; no PR). This is the one that matters for the browser.
- **Local `master` has diverged from `origin/master`: 898 commits ahead, 24 behind.** Those are the shared tree's unpushed commits (memory note: peers' local commits wait for their suites; the user lands shared-tree commits themself). Do not push `master` without them. The browser branch is based on `origin/master`, not local `master`.
- **Issue-fix branches, 66** (`codex/fix-*` and `fix-*`, all from 2026-10-28, one commit each, e.g. `fix-1252-css-percent-cap`, `fix-1253-css-lang`, `fix-1254-css-syntax` touch browser CSS code): some have worktrees under `C:/Users/gaddl/.codex/worktrees/`. Whether each was merged by another route is not checked.
- **Older streams:** `g001/g23/g4/g5/g6/g6b/g6c/g6d/g6e-on-origin`, `grid-docs-on-origin` (the data grid, 2026-10-12), `blog-*` (4), `looks46-d`, `macos-a64`, `macos-dir`, `shell-baseline` (marked TEMPORARY), `ai/sharp-kalam-d399bd` (f16/bf16 arithmetic), and remote-only `origin/poll-ci` and `origin/backup/origin-master-2026-10-22`.
- 28 agent worktrees sit under `D:/repos/neper/.claude/worktrees/`; their branches are `worktree-agent-*`.

## 8. Rules of the repo and the user

- A fix is done with a regression test that fails if the behaviour breaks; the browser branch has leaned on the WPT sweeps instead of the `css_layout` fixture cases (`tests/selfhost/fixtures/link/css_layout`, next free case was 106 on 2026-10-20). Adding fixture cases is owed.
- Minimal comments; only non-derivable why or constraints. No Python patch scripts; use `patch.exe` or the Edit tool.
- Commit only touched paths; never `git add -A`. Fetch before pushing.
- Show the user UI results as screenshots (`SendUserFile`); only of the app window. Recommend, then wait for "lock it in" on decisions.
- End substantive replies with **Summary:** and **Next step:** (the user's global `CLAUDE.md`).
