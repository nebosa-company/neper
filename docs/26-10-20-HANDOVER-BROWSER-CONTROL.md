# Handover: the Neper browser (conformance, the app, its targets) — updated 2026-10-31

The one browser handover. For another session or account continuing the work. Goal in force (user, repeated by a Stop hook every turn): **keep implementing the browser until it is fully implemented**, ending in **Neper-native applications**, tested on **Windows, Linux and the web (wasm32-wasi)**. Android and iOS do not compile yet. HTTP/3, WebSockets and WebGL are out of scope. Nothing here is "done"; this is a pause.

The other handover documents were reviewed and are different streams, left untouched: `HANDOVER.md` (2026-10-14, a general account-to-account note), `HANDOVER-GRID.md` (the data grid, G012), `docs/ui/26-10-20-HANDOVER-UI-LIB-L-and-F.md` (UI looks and feels), `docs/implementation-handoff.md` (a 2026-09-06 historical snapshot) and `docs/algos-handoff.md` (a prompt for the algos stream).

## 0. Resume in five commands

```bash
cd D:/repos/neper-wt-browser            # a worktree of D:/repos/neper on branch browser-conformance
git status --short | grep -v '^??'      # expect nothing (section 2)
git log --oneline -3                    # head was 5e6923d83 (the second merge of origin/master) before this handover edit
gh auth status | grep -B1 Active        # must be nebosa-company; oboobortot gets a 403 on this repository
D:/repos/neper/build/windows/neper-self.exe emit-executable tests/browser/wpt/run.e . x64 windows build/windows/run-wpt<N>.exe
```

Compilers live in the **main checkout** (`D:/repos/neper/build/windows/`); the worktree's `build/windows` is cleaned. Use `neper-self.exe` (`neper-try.exe` fails type-checking on any edit to `run.e`). Use a new `run-wpt<N>.exe` name per build.

## 1. State

- **Branch** `browser-conformance`, pushed to `origin/browser-conformance`, **90 commits ahead of `origin/master`, 15 behind** (after `git fetch`, 2026-10-31). `origin/master` was merged in twice: 2026-10-30 (4a7eb5077, clean for source) and 2026-10-31 (**5e6923d83**, 12 conflicts resolved: six shared docs, `layout.e`, `paint.e`, `scene.e`, `page.e` and two selfhost fixtures). How the source conflicts went: the browser's `list_ordinal` and bidi code were kept (they cover master's value-reset and Open/Close cases), master's run-in guard and `Tab` piece/tab stops were taken (bidi leaves a line with a tab alone), the renderer holds 32 fonts. **Master's own tree did not build the browser** (`page.e` called `url.zero_buf`/`url.buf_take` after `e.fmt.url` changed its API, `shell.e` assigned `t.pg = zero`), fixed in the merge with `url_buf`, `url_take` and `null_page` helpers. **No pull request exists.** Merge again before a PR: `git merge origin/master` on a scratch branch, resolve, rebuild all three targets, re-run the css_layout and web_shell fixtures (`NEPER_COMPILER=<compiler built with --arena 6g> scripts/check-fixture.sh <name>`) and the CSS gate.
- **15 newer master commits conflict again (trial merge, 8 files):** the six shared docs again (`docs/decisions.md`, `docs/digest/decisions.tsv`, `docs/digest/queue.tsv`, `docs/progress.html`, `docs/work-evidence.md`, `docs/work-queue.json`: take master's, re-add the browser's L183-L185 records and D5949-D5951, rerun `scripts/render_digest.py` and `scripts/render_progress.py`) and two source files, `lib/e/gfx/scene.e` and `lib/e/web/page.e`. Layout, paint and the other browser files merge clean. Decision and queue numbers may have moved again; check master's maximum first.
- **Renumbered after master took the numbers:** the browser's queue items L172 (visit history), L173 (ad and tracker blocking) and L174 (certificate validation) are now **L183, L184, L185** (master uses L172-L182 for OpenGL); decisions D5940-D5942 are now **D5949, D5950, D5951** (master had D5940-D5948). The text of this handover below that says D5940/D5941/D5942 means D5949/D5950/D5951.
- **Fixture edits the merge needed (review them):** `css_layout` kept both sides' cases (master's #109 became #135, master's `css_issue_regressions` exits +50) and its #1198 bidi check accepts the first word's fragment with or without a trailing space (our bidi emits the space as its own fragment, visual order is right); `web_shell` runs master's frame-registry check first and wraps its two scripts in blocks (they both declared a global `const frame`, which our engine now rejects as a redeclaration, as a browser would), and master's tab-reuse exit codes became 80-86.
- **Last gated numbers** (runner `tests/browser/wpt/run.e`, build `run-wpt196` = the merged tree before the `shell.e` and fixture edits, 2026-10-31):

| Suite | Passing | Note |
|---|---|---|
| css/CSS2 | 5167 / 5829 | 5152 before the second merge; 5118 on 2026-10-20 |
| css-flexbox | 634 / 908 | |
| css-grid | 719 / 1545 | |
| css-writing-modes | 625 / 995 | 622 before the second merge |
| css-sizing | 328 / 457 | 311 at the start of the session; 318 before 8b9725731 |
| css-multicol | 182 / 402 | 157 before D5940 |
| css-overflow | 274 / 501 | line-clamp is the biggest cluster (113 failing), then scroll-markers (44) |
| css-lists | 99 / 125 | 80 at the start |

  JavaScript: test262 96.2% (43619 of 45356 run, 8260 feature-gated skipped), measured 2026-10-18, recorded in `docs/browser-progress.html` row 5.14; the tree has more JS fixes since. Not re-measured. html5lib is 1791 of 1791.
- **Decision rows** D5940 (multicol column starts), D5941 (the app's scripts, taps, fonts) and D5942 (the wasm build) were appended. D5940-D5942 are a small block above master's maximum at the time (D5935); a peer using the same numbers will conflict, renumber when merging.
- **Queue evidence not updated:** L166 (`score 0.20`) and the others were not touched beyond the L172-L174 records. The queue's first item is C104 (NeperOS on a Pixel), not a browser item; `AGENTS.md` says to work only on the first item, which the browser branch does not follow. Decide with the user whether browser evidence goes in the queue.

## 2. Uncommitted work: none

The worktree is clean (untracked `docs/tasks/...` files from the task renderer may show; leave them, never `git add -A`). The last change, `contain: size` with `contain-intrinsic-*`, was gated and landed as **8b9725731** (pushed): an empty contained block keeps its intrinsic height (`self_collapsing` no longer collapses it), `size_contained` reads `contain-intrinsic-inline-size`/`-block-size` (inline is the width in a horizontal mode, the height in a vertical one), and `layout_contents_height` (atomic inlines) and `flex_place_item` (flex items) take the intrinsic height. Gate on `run-wpt195`: css-sizing 318 -> 328, `contain-intrinsic*` 8 -> 18 of 27, every other suite unchanged, CSS2 5152.

Still failing in `css/css-sizing/contain-intrinsic-size/`: 008 (vertical-writing box), 012, 014, 017, 020, 023, 025, 027, logical-002.

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

Things that silently broke pages before, all fixed and recorded in D5941: a 128 MB tab arena starved the page's JS runtime (now 256 MB, about 15 tabs in a 4 GB arena; 512 MB made the web_shell fixture's default arena run out); a pending timer never ran in an idle window; a tap reached links only, never `onclick`; the renderer held 16 fonts and dropped the rest (now 32).

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
- **css-sizing (129 failing):** aspect-ratio 53, contain-intrinsic-size (9, section 2), intrinsic-percent 14, stretch 13, replaced-aspect 5, float-clearance 4, fit-content 4, box-sizing-replaced 3 (one image is 9 px too wide; per-image sizes not traced), svg-intrinsic 3, range-percent 3. `block-aspect-ratio-with-margin-collapsing-002` is unresolved.
- **css-flexbox 274, css-grid 826, css-writing-modes 373, CSS2 677** still failing; the 2026-10-20 cluster notes (grid-lanes, subgrid unimplemented, baseline alignment, bidi) still describe them. css-overflow: line-clamp 113, scroll-markers 44, text-overflow-string 21.
- **The browser as a product:** page scripts, timers and clicks work on small pages and on `rules.html`; **real-site behaviour is unmeasured** (jQuery 3.5.1 init, AJAX re-render, iframes, `getBoundingClientRect` feedback), as is performance and memory. Form controls, text input, selection, favicons and downloads are not checked. Broken images draw their alt text but not Chrome's broken-image icon.
- **Web target:** networking, and scripts/clicks/scroll unverified; fonts are Jost only.
- **Not done:** the `x509.verify` out-of-memory mislabel (change `sign.rsa_pkcs1v15_verify_hash` to report an error, three callers plus fixtures), queue evidence for L166-L171, the second merge with `origin/master` (section 1).

## 7. Branches not merged into master (re-checked 2026-10-31 against the fetched `origin/master`)

The shared tree was landed since the 2026-10-30 check: **local `master` is now 0 ahead and 26 behind `origin/master`** (it was 898 ahead), and the unmerged local branches fell from 87 to **25**. What is still unmerged:

- **Mine:** `browser-conformance` (90 ahead, 15 behind; also `origin/browser-conformance`; no PR; a trial merge with the 15 newer master commits reports 8 conflicts, listed in the last line of section 1).
- **Issue-fix branches, 8** (2026-10-28, one commit each): `codex/fix-1258-wasi-proc-reap`, `codex/fix-182-gfx-paint`, `fix-1167-remote`, `fix-1256-remote`, `fix-1257-window-bounds`, `fix-438-metal-device`, `fix-478-wasi-args`, `fix-644-gpu-lost`. The other 58 were merged.
- **Older streams:** `g001/g23/g4/g5/g6/g6b/g6c/g6d/g6e-on-origin` and `grid-docs-on-origin` (the data grid, 2026-10-12), `blog-agent-loop`, `blog-cleartype`, `blog-cleartype-on-origin`, `blog-update`, `looks46-d`, `shell-baseline` (marked TEMPORARY), and the remote-only `origin/backup/origin-master-2026-10-22`.
- Agent worktrees remain under `D:/repos/neper/.claude/worktrees/` (28 on 2026-10-30) and `C:/Users/gaddl/.codex/worktrees/`.

## 8. Rules of the repo and the user

- A fix is done with a regression test that fails if the behaviour breaks; the browser branch has leaned on the WPT sweeps instead of the `css_layout` fixture cases (`tests/selfhost/fixtures/link/css_layout`, next free case was 106 on 2026-10-20). Adding fixture cases is owed.
- Minimal comments; only non-derivable why or constraints. No Python patch scripts; use `patch.exe` or the Edit tool.
- Commit only touched paths; never `git add -A`. Fetch before pushing.
- Show the user UI results as screenshots (`SendUserFile`); only of the app window. Recommend, then wait for "lock it in" on decisions.
- End substantive replies with **Summary:** and **Next step:** (the user's global `CLAUDE.md`).
