# Library review and hardening plan (2026-11-13)

Source: a read-only review of `lib/e` at `e5cbfecd7` (748 modules, 774 files, 623k lines,
about 27,000 functions), by four parallel reviewers (core runtime; formats, text, crypto,
net; UI, gfx, web, js; algorithms, math, ml) plus whole-library counts by script.
Goals: tests that would catch a break, an honest completeness figure, hardening at trust
boundaries, and documentation that exists once. The compiler has its own plan in
`docs/compiler-hardening-plan.md`; its section 0 worker protocol applies here unchanged.

Standing of the evidence:

- **measured** - counted by a script over the tree (regex over source, not the compiler).
- **verified** - a reviewer cited the line and it was re-read for this plan.
- **reviewer** - a reviewer read it at the cited line; not re-read.
- **inferred** - deduced, not confirmed. The item's first step is a failing fixture;
  if it cannot be made to fail, close the item as "not a defect" and keep the fixture.

Nothing was built or run. No fixture was executed, so every statement about what a test
covers rests on which names a fixture's source mentions.

This file is design notes: evidence and approach. The open items themselves (status,
acceptance, model, thinking effort and order) live in `docs/work-queue.json` under the
ids used as headings below, and only there.

## 1. What the counts say

| Measure | Value | Standing |
|---|---|---|
| `@test` functions in `lib/e` | 17; link fixtures are the tests | measured |
| Line coverage of `lib/e` | not measured anywhere (the 82.8% figure is the compiler's) | measured |
| Modules used by no fixture directly | 119 (70.9k code lines) | measured |
| Modules used by exactly one fixture | 348 | measured |
| Functions no fixture or example can reach | 1,185 of 26,908 (22k lines, 3.8%); a floor, since any mention of a name counts as a call | measured |
| ...of which AV1 and mp4 | 24 modules, about 17,500 lines, no fixture and no user | measured |
| Source modules absent from `docs/modules.json` | 111 (av1, `js.b_*`, `ui.looks_*`, `ui.win*`...) | measured |
| Modules labelled `partial` | 155, of which 147 have nothing pending | measured |
| Commits since 2026-10-01 touching `docs/module-apis.md` | 573 of 5,303 | measured |
| Comment lines | 46,027 (7.3% of lines, 10.5% of bytes) | measured |
| Comment lines citing a decision number, queue id or ledger round | about 2,700 | measured |

Assertion quality is not the problem: all 60-odd fixtures the reviewers sampled assert
results with per-check exit codes, and 155 of 203 algorithm fixtures cite an external
reference. What is missing is breadth, a coverage number, and corpora.

Dependencies the queue order encodes: L257 -> L258 -> L259 run one at a time in the
files they move, and L263 needs L247's private marker. Two items never run together
if they share a file.

---

## 3. Tests and coverage (LT)

### L230 A library line-coverage number
- Evidence (measured): `scripts/coverage-run.sh` and `coverage_report.py` cover `src/` only.
  Fixture binaries already carry DWARF lines on ELF.
- Do: run each link fixture's own binary under callgrind, merge against its line table,
  keep only `lib/e` paths, report per module and in total; write
  `docs/lib-coverage-floor.txt` and ratchet it as the compiler's floor is ratcheted.

### L231 The unreached-function list as a gate
- Evidence (measured): 1,185 functions are named by no fixture, example or reached library
  function. Largest outside AV1: `e.os` 62 functions, `e.gpu` 26, `e.ui.datagrid` 43,
  `e.gpu.vulkan` 14, `e.fmt.flatbuffers` 21, `e.ui.browser` 11.
- Do: produce the list with `check --unused-code` over an all-library root (the compiler's
  answer, not a regex); commit the count as a ceiling that may only fall. Each entry is
  then tested or deleted.

### L232 AV1 and mp4: test or leave the library
- Evidence (measured, verified): `fmt/av1*.e` (23 files) and `fmt/mp4.e` have no fixture
  and no importer. `mp4.e:173-181` rescans every stsc run for every chunk (chunks x runs,
  both input-sized); `:194` adds `offset + size` unchecked before the bounds test.
- Do: one decode fixture against reference frames, plus truncated and oversized inputs;
  a single monotonic run cursor in `mp4`; check `offset <= len && size <= len - offset`.
  If no fixture lands, move the cohort out of `lib/e` until one does.

### L233 Fuzz the parsers
- Evidence (reviewer): `lib/e/test/fuzz.e` is used only by `test_fuzz` and `test_gaps`; no
  decoder is fuzzed and no corpus exists.
- Do: one mutation fixture per decoder asserting "an error, never a trap", seeded from the
  fixture's existing valid inputs. Start with opus, webp, pdf, css, tiff, mp4, yaml.

### L234 Conformance corpora
- Evidence (reviewer): absent from the suite: Wycheproof, JSONTestSuite, yaml-test-suite,
  toml-test, html5lib, PngSuite, any regex suite. `tests/browser/js/own` (21 tests),
  html5lib (61 files) and the WPT reftests exist in the repo but only `tests/browser/url`
  is run (verified: two `tests/browser` lines in `run.sh`). test262 is not vendored.
- Do: wire what is already in the repo first, each with a pinned pass list and a floor;
  then add the external corpora one per landing.

### L235 Thin modules get a second fixture
- Evidence (measured): one fixture each: `e.ui.datagrid` (12.1k code lines), `e.fmt.opus`
  (3.8k), `e.text.math` (2.7k), `e.gfx.cssvalue` (2.6k), `e.fmt.xsd.schema`, `e.fmt.webp`,
  `e.gfx.mesh`, `e.fmt.xslt`, `e.algo.workflow`, `e.algo.expr`, `e.algo.fsm`. No direct
  fixture: `e.js.temporal` (3.7k), `e.js.intl` (3.1k), `e.js.regex`, `e.js.module`,
  `e.js.b_wasm`, `e.time.names`, `e.net.uts46`.
- Evidence (reviewer): untested by name: `fs.vfs` `exists`/`make_dirs`/`copy_file`;
  `proc` `spawn_in`/`output_in`/`spawn_piped_group`/`run_contained`; `time.parse`
  `parse_iso`/`parse_lenient`; cron lists, the 0/7 Sunday alias and stepped ranges; invalid
  UTF-8 into `e.str`; the OS-random entry points of `algo.privacy`.
- Do: order by L230's per-module number once it exists; until then, the list above.

### L236 Fixture hygiene
- Evidence (verified): 12 fixtures cite a reference script under `scratchpad/` that is not
  in the repo. Evidence (reviewer): `path_pure` exits 20 for every split case and 40 for
  every normalize case; `math_special` checks `erfc(4.0)` with an absolute tolerance wider
  than the value; the `control` fixture tests language control flow, not `e.control`; 3 of
  142 `ui_*` fixtures load a font and `ui_windows_looks` asserts only "painted more than
  zero commands"; 9 of 142 exercise a platform look, the rest run by hand through 255
  `examples/looks` apps.
- Do: commit each reference generator beside its fixture; per-case exit codes; delete the
  vacuous check; rename `control`; load the Ahem-like font and assert text extents and a
  frame hash in a looks subset inside the suite.

---

## 4. Hardening (LH)

### L237 Page scripts have no step limit
- Context: soundness.
- Evidence (verified): `web/script.e:1331-1333` sets `step_limit` for the DOM runtime boot
  and resets it to 0; nothing else in `lib/e/web` sets it.
- Do: a per-task step budget for page scripts; check the 80% arena limit in `tick()`, not
  only on JS function entry (reviewer, inferred: `interp.e:3335`).

### L238 Predictable passwords and UUIDs in the formula engine
- Context: soundness.
- Evidence (verified): `algo/formula.e:1828,2406` is xorshift64* seeded from
  `ctx.random_seed`; `algo/formula/misc.e:149,402` draw UUID and GENERATEPASSWORD from it.
- Do: both draw from `os.random`; RAND keeps the seeded generator.

### L239 WAL replay swallows a failed delete
- Evidence (verified): `db/storage.e:882` `let _ = table_delete(t, key)` then counts it
  applied; the put at `:878` propagates.

### L240 TIFF inflate skips zlib validation
- Evidence (verified): `fmt/tiff.e:335-346` drops two header bytes unvalidated, ignores the
  decode status and never checks Adler-32; reviewer: each strip allocates a new 32K decoder.
- Do: call `e.fmt.zlib`; hoist the decoder out of the strip loop.

### L241 Recursion without a depth guard
- Evidence (inferred): `js/parser.e:916`, `js/interp.e:4708`, `js/b_json.e:425`,
  `js/b_array.e:1029` (`max_depth` counts JS calls only); `parse/comb.e` (no guard at all);
  `fmt/avro.e:208,356` on a cyclic schema. Reviewer: `b_json.e:480` cycle check is
  quadratic in depth; `algo/sort.e:378-416` `quick` recurses on both halves.
- Do: one depth counter per parser; `quick` recurses on the smaller half.

### L242 `@import` fan-out
- Evidence (verified): `web/page.e:294-307` caps depth at four with no visited set and no
  total; fetches are synchronous.

### L243 Stub resolver
- Evidence (verified): `os.linux.e:1328` 512-byte messages, no EDNS or TCP retry (the
  comment at `:1326` accepts a truncated answer); `:2385` one datagram with the wrong id
  ends the lookup as `Failed`. Reviewer: the question section is never compared;
  `read_text_file` (`:1949-1971`) truncates `/etc/hosts` past 256 KB silently.

### L244 Secrets are never wiped; crypto gaps
- Evidence (reviewer): no wipe in `crypto`, `net/tls.e`, `net/ssh.e`. `crypto/x509.e:825`
  takes the first issuer match with no backtracking (inferred); a matched root is not
  checked for unhandled critical extensions; no revocation path. `algo/privacy.e:41-90`
  samples Laplace and Gaussian noise in double precision.
- Do: `secret.wipe` at TLS/SSH close and KDF exit; try every issuer candidate; snapping or
  discrete samplers for the privacy mechanisms; state the revocation gap in the module.

### L245 Silent truncation at fixed limits
- Evidence (verified): `test/coverage.e:47` drops every counter past 4096. Reviewer:
  `time/recur.e:11-13` ends quietly at its search bound; `cli/complete.e:242` cuts the fish
  chain at depth 16; `os/shell.linux.e:360` accumulates a `u32` unchecked; `mem.e:12`
  `copy` copies the shorter length; `mem.e:122` `pool_free` accepts a double free
  (verified: the comment says so); `gfx/filter.e:92` and about 20 siblings multiply
  `w * h` unchecked where `gfx/image.e:57` checks.
- Do: each returns a named error or sets a flag the caller reads.

### L246 Copy replaces without a sync
- Evidence (verified): `fs.e:776-792` closes the temp file and calls `os.replace` with no
  sync between, so a crash can leave an empty file under the final name.
- Do: sync before replace (behind a flag if the count gate objects).

---

## 5. Completeness and correctness (LC)

### L247 `partial` means partial
- Evidence (measured): 147 of 155 `partial` modules have zero pending declarations; they
  are partial only because a source module with a private helper cannot be `source`. The
  real gaps are `e.os.shell` (93 pending), `e.crypto.hash` (2), `e.ui.winedit` (2) and five
  modules with one each.
- Do: derive the label from `docs/library-fixtures.json` pending counts, or add a
  `private` marker the surface check honours. The second is a language decision row.

### L248 Every source module is in the plan
- Evidence (measured): 111 modules with source are not in `docs/modules.json`, so
  `check_module_surfaces.py` never looks at them.
- Do: `check_module_plan.py` fails on a `lib/e` file with no entry; support modules get an
  `internal` marker instead of a catalogue.

### L249 `docs/algos.md` says what was delivered
- Evidence (verified for the sort and binomial rows, reviewer for the rest): Timsort maps
  to a bottom-up merge sort (`sort.e:100`), IntroSort to heapsort (`:16`), Karatsuba to
  schoolbook multiply, Bentley-Ottmann to an O(n^2) scan, Ziggurat to Marsaglia polar,
  BTPE to a rounded normal above mean 30 (`rand/dist.e:96`). Two mapped names do not
  exist (`stat.causal.propensity`, `timeseries.arima`).
- Do: restate each row as the algorithm delivered, or implement the named one. A script
  checks that every mapped name resolves.

### L250 Numeric defects
- Evidence (verified): `stat/test.e:41-47` computes `2*(1-cdf)`, exactly 0 past z of about
  8.3; `search.e:188` Lomuto partition with `<` is quadratic on equal keys; `ml/cluster.e:55`
  `kmeans` with zero iterations returns `ok` with every label equal to `k`.
- Evidence (reviewer): `ml/tree.e:137-163` insertion-sorts every feature at every node;
  `formula/math.e:1055` has a 1.5e-7 `erf` beside `math/special.e:63`; `stat/test.e:20-39`
  divides by `len` and `len-1` unguarded.

### L251 Platform parity is declared, not discovered
- Context: with compiler plan C327.
- Evidence (verified): EINVAL maps to `Unsupported` on Linux (`os.linux.e:312`) and code 87
  to `Invalid` on Windows (`os.windows.e:1135`). `sandbox` refuses `deny_dynamic_code`
  before applying anything on Linux (`:5943`, leaving `:5986` dead) and after on the other
  hosts. Reviewer: clipboard, `window_present_rect`, `window_on_resize` are constant
  `Unsupported` on Linux; recursive watch is refused on Linux and Windows, implemented on
  macOS, and two comments say otherwise.
- Do: one error mapping; one sandbox contract; a per-host capability table generated from
  source (the same matrix C327 renders).

### L252 Disabled crypto
- Evidence (verified): `crypto/sign.e:2181` `ml_dsa_sign` begins `ret Unsupported` above
  about 140 dead lines. Reviewer: ECDSA P-256/P-384 signing and ffdhe2048 are `Unsupported`
  because bignum is variable-time; the TLS server therefore accepts only an Ed25519 leaf,
  offers x25519 with no HelloRetryRequest, and treats KeyUpdate as fatal. `net/dns.e:616`
  refuses RSASHA256 although an RSA verifier exists (verified).
- Do: delete the dead body now; wire DNSSEC algorithm 8; constant-time field arithmetic is
  its own queue item.

### L253 Declared ceilings become metadata
- Evidence (reviewer): `wasm.e:6-8` (no body type validation; verified), yaml multi-line
  scalars and anchors, webp first frame only, jpeg 8-bit only, zstd without dictionaries,
  parquet missing three encodings, AV1 8-bit 4:2:0 only; 144 `ponytail:` markers in the
  UI slice.
- Do: `/ponytail-debt` style harvest into one generated table in `docs/progress.html`;
  the wasm validator and AV1 `TooLarge` (pool exhaustion is reported as `Unsupported`) are
  their own items.

### L254 Options that do nothing
- Evidence (reviewer): `control.e:6573` the Windows look ignores `ProgressOptions` `tone`,
  `thick`, `buffer`, `full_bleed`; `:17523` `along` is unused; `:66-73` `ButtonOptions`
  carries fields documented as existing for the looks sheets.

---

## 6. Structure and duplication (LS)

### L255 One helper, not thirty
- Context: mechanical.
- Evidence (reviewer, counts not re-checked): about 36 hex-digit helpers, about 30
  fixed-endian readers, 8 UTF-8 encoders beside `text/utf8.e:65`, 9 decimal parsers with
  differing overflow handling, 6 byte-equality copies beside `str.eq`, base64 in three
  network modules, CRC/Adler copies beside `e.algo.hash`, Cholesky five times, Dijkstra
  four, FNV-1a four, gcd three, four archive path-safety validators, the HTTP smuggling
  rules twice in `net/http.e`, `valid.iban` and `checksum.is_iban` disagreeing on length.
- Do: one family per landing; the survivor lives in `e.str`, `e.bytes`, `e.algo.hash`,
  `e.algo.linalg` or `e.fs.path`. L231's count and the byte gate guard each landing.

### L256 Generated blobs are assets
- Evidence (verified sizes): `js/tzpack.e` 1.2 MB, `web/dom_js.e` 1.1 MB (generated
  `str.push` over `web/js/*.js`), `ui/winmenuicon.e` 688 KB, `ui/windlg88.e` 480 KB;
  reviewer: 2.83 MB of baked atlases in `ui/win*`, `adwicon`, `matglyph*`.
- Do: embed through `e.asset`; the generator and its input are the only source.

### L257 Sheet support code leaves the library
- Evidence (verified): `ui/dlggrid`, `windlg`, `wintreeicon*` and 11 `looks_*` modules are
  imported only by `examples/looks`. Reviewer: 35 `looks_*` files, 2,616 lines, named by
  work round and lane; 14 are imported by the control modules; 18 process-wide switches
  (`set_caret_hidden`...) change drawing for screenshots; the `.Windows` look bakes in one
  application's strings (`winmenuicon.e:12`).
- Do: move example-only modules to `examples/looks/`; rename the rest by content; carry
  the switches in `Theme`.

### L258 Split `ui/control.e` by platform look
- Context: refactor byte gate.
- Evidence (reviewer): lines 16900-24727 are look code: 341 functions prefixed
  `win`/`linux`/`cup`/`mat`/`dark_`, 254 `profile ==` branches, eight dotted-rectangle
  painters, and the custom-node block repeated 54 times. `control.e:19297` picks a variant
  by testing whether the ink's red channel is between 0.34 and 0.37 (verified).
- Do: `control_win.e`, `control_linux.e`, `control_cup.e`, `control_mat.e`; one dots
  painter taking colours and phase; a `custom_node[T]` helper; a flag instead of the
  colour test. Needs the compiler plan's T097 (`plan-move-file`).

### L259 Split the other large UI files
- Context: refactor byte gate.
- Seams (reviewer, inferred from type positions): `datagrid.e` core 98-1830, chooser
  1838-2050, dialogs 2050-3340, wizard 3341-4300, print 4306-5800, filter and navigation
  5811-8800; `collection.e` pager, reorder, table 1750-5730, tree, property grid, lists,
  tiles; `navigation.e` bars, menu bar, drawer, tabs, dock, workspace, wizard, palette,
  ribbon, title bar; `overlay.e` menus, dialogs, sheets, date, time, colour.

---

## 7. Documentation (LD)

Comment volume is not the problem (7% of lines). Three things are.

### L260 Comments carry no history
- Context: mechanical.
- Evidence (measured): 2,014 comment lines cite `D<n>`, 204 a queue id, 467 a ledger
  round or gap; 1,662 of the `D<n>` lines are in `lib/e/ui`. Reviewer estimates by slice:
  history 3-18% of comments, restating the code 15-40%.
- Do: strip the reference and keep the sentence when it still explains a constraint;
  delete the line when the reference was all it said. A check fails on a new
  `D[0-9]+`, queue id or `#NNN` in a `lib/e` comment (AV1 mode names `D45`..`D203` exempt).

### L261 Stale comments found
- Evidence (verified): `crypto/sign.e:2178` describes a signer whose body is `ret
  Unsupported`. Reviewer: `os.macos.e:922` ("not served on macOS yet", implemented below);
  `os.wasi.e:2086,2093` say NeperOS; `os.e:2` "lands in M1"; `os.linux.e:5934-5937` and
  `os.macos.e:2644` on the sandbox contract; `fs/watch.e:3` and `os.windows.e:134` on
  recursive watch; `fmt/mp4.e:7,82`; `math/special.e:61` (2 against the code's 2.5);
  `algo/sort.e:7-9`; 14 generated headers citing `ref/windows-1to1/`.

### L262 Design-spec prose lives in one place
- Evidence (reviewer): of `control.e`'s 2,944 comment lines, 2,213 are per-control spec
  blocks (metrics, token names, key offsets) that repeat `docs/ux/components`; 301 are
  capture measurements.
- Do: keep the constraint a reader of the code needs; the spec stays in `docs/ux`.

### L263 The catalogue is generated, not synced
- Evidence (measured): `docs/module-apis.md` (2.1 MB) repeats the library's signatures;
  573 commits since 2026-10-01 touched it, and `check_module_surfaces.py` fails today on
  an uncommitted `e.net.fetch` helper. The file is both the plan for what is not built
  and a copy of what is.
- Do: for `surface:"source"` modules, render the catalogue section from the source
  (`render_module_apis.py` exists); the hand-written file keeps only fences for
  declarations not yet delivered. Needs L247's private marker so a helper is not a
  surface change.

Not reviewed: `lib/x`, `lib/wasm`, `e.gfx.chart` internals beyond counts, and the
`docs/` tree outside the files named here (`docs/ui` alone is 301 MB in 14,383 files).
