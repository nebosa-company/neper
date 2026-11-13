# Compiler review and hardening plan (2026-11-12)

Source: a read-only review of `src/*.e` (106k lines, 60 files) at `6447598b3`, by five
parallel reviewers (front end, checker, middle/back end, targets, driver/tooling).
Goals in priority order: LLM-friendliness, one code base over many platforms, platform
versatility, compile speed, execution speed, with hardening throughout.

Standing of the evidence:

- **verified** - reproduced by running `build/windows/neper-self.exe` (built 2026-11-06)
  on scratch files, or measured.
- **source** - read in the source at the cited line, not run.
- **inferred** - a consequence deduced from the source. The first step of such a package
  is always a failing fixture; if it cannot be made to fail, close the package as
  "not a defect" with the fixture kept as a regression test.

Nothing was built for this review. No fresh timing was taken (no release compiler at
HEAD existed and building one writes into the shared tree); CS-00 does that first.
Recorded baseline, 2026-11-09: release self-build 2.75 s at `-j1`, 1.05 s at `-j8`,
360 MB; all-library root 23 s Windows / 13 s Linux; lower+codegen about 70% of wall.

Checked against `9224fac13` on 2026-11-13 (read and grep only, nothing built or run):

- 22 cited lines across `check.e`, `codegen_x64.e`, `regalloc.e`, `link_elf_a64.e`,
  `project.e`, `lower.e`, `parse.e`, `graph.e` and `main.e` were re-read; each still
  shows the cited code. The other evidence lines were not re-read.
- Only `src/main.e` moved since `6447598b3`. Add to a cited `main.e` line: +2 above
  line 19, +12 above 888, +14 above 1270, +16 above 1306, +24 above 1499, +26 above
  3991, +74 above 14642. Every other `src` file is unchanged.
- New since the review: `check --unused-imports` and `--unused-code`
  (`src/unused_use.e`, `src/unused_decl.e`). LF-02's flag loop now knows 14 flags;
  LF-16's command table must carry both; HD-02 and CS-04 can use `--unused-code` to
  confirm the dead code they delete.
- All 37 queue ids cited below are open in `docs/digest/queue.tsv`.
- The bootstrap limits quoted by the review were out of date and are corrected in
  section 0 item 4 and PL-09.

Package ids here (`LF`, `HD`, `PL`, `CS`, `XS`) are provisional. They are not queue
ids; an existing queue id is named where the work belongs to one.

## 0. Worker protocol

Every package below is one worker session. A worker:

1. Reads `docs/llm-neper-card.md`, then the package, then uses
   `neper context-file --symbol module.name` for each function named. Do not open
   `main.e`, `check.e`, `lower.e` or `tool.e` whole; use the line ranges given.
   Line numbers are as of `6447598b3`; re-locate by function name if they moved.
2. Writes the acceptance fixture first and sees it fail (or, for a refactor, records
   the byte-identity baseline first).
3. Edits with the Edit tool or `build/windows/patch.exe`. Never a Python patch script.
4. Keeps `src/` buildable by the C bootstrap until PL-09 lands: no `-=`, no
   `x > CONST {`, no top-level `var`, at most 400 locals per function and 192 fields
   per type (`bootstrap/neper.c:49,62`; both overflows are reported as E-TOOL-9999,
   not truncated). `Checker` has 164 fields, so the comment at `check.e:641` ("at the
   limit, 161") is stale; correct it when next in that file.
5. Verifies with `scripts/check-fixture.sh <fixture>` on the host, then hands off. Full
   suites are a separate verify-only session, never combined with the build session.
6. Follows `AGENTS.md` for landing: touched paths only, a `D<n>` row, the queue item.

Gates used below:

- **byte gate** - stage2 == stage3, and the emit sweep / goldens unchanged. Required
  for every package tagged *refactor*.
- **both back ends** - the fixture runs on x64 and on aarch64 (`scripts/a64-differential.*`)
  with equal output.
- **count gate** - cachegrind instruction count on the compiler self-build, before and
  after, stated in the D-row.

Model guide: **S** packages and anything tagged *mechanical* suit Sonnet. **Opus** for
packages tagged *soundness*, *refactor L*, or touching `regalloc.e`, generic deferral
or checker recovery.

Each heading ends with the proposed thinking effort. Raise one step if the first
attempt fails its acceptance; do not start higher.

## 1. Order of work

Wave 1 (independent, start now, all S or M):
HD-01..HD-06, HD-09, HD-10, HD-17, LF-01, LF-02, LF-08, LF-11, LF-14, LF-17, LF-18,
LF-19, LF-26, PL-02, PL-03, CS-00, XS-04.

Wave 2 (needs wave 1 pieces named in each package):
LF-03..LF-07, LF-09, LF-10, LF-13, LF-15, LF-16, HD-07, HD-08, HD-11..HD-16, PL-04..PL-06,
CS-01..CS-04, XS-01, XS-02. PL-06's generated matrix waits for PL-01; its jobs do not.

Wave 3 (structural, one at a time, each alone in `src/`):
LF-20 -> LF-21 -> LF-22 -> LF-23; PL-01 -> PL-07 -> PL-08; XS-03 -> existing C244..C251.

Wave 4: PL-09 (bootstrap retirement), LF-12 (checker recovery), LF-24, LF-25, PL-10.

Two packages never run concurrently if they share a file in "Files". Wave 3 packages
move code, so nothing else may be open in the file being split.

---

## 2. LLM-friendliness (LF)

The edit loop an agent runs is: locate -> context -> edit -> check -> repair -> test.
Today it loses turns to positional flags, single bare diagnostics, catch-all codes and
unbounded answers. These packages fix each of those at its source.

### LF-01 Query commands take flags by name and have short forms - M, Sonnet, medium
- Evidence (verified): `main.e:14537` requires `args[6]=="--json" && args[7]=="--symbol"`.
  The card's own spelling `context-file --symbol m.f` fails with a 942-byte usage line
  and exit 1. `test-file --only` must be the last two arguments (`:14697`).
  `short_form` (`main.e:1230-1240`) has no entry for context/uses/explain/plan-*/
  test-impact/query-batch.
- Do: in `dispatch`, scan flags by name for every `*-file` query command. Add short
  forms `context|uses|explain|impact|plan-rename|plan-add-parameter|
  plan-change-signature|plan-replace-expression [FILE]` to `short_form`, defaulting
  FILE to the project's `src/main.e`, target to the host, `--json` implied. The E-CLI
  message names the offending argument.
- Accept: a tools conformance case runs `context-file` with `--symbol` before and after
  `--json` and gets identical streams; an unknown flag exits 2 with E-CLI naming it;
  `neper context --symbol m.f` equals the long form. Card re-rendered, with
  `docs/llm-neper-card.src.md:189` ("past 256 locals silently") corrected to the
  bootstrap's reported 400.
- Files: `src/main.e` (1132-1604, 14500-14720), `docs/llm-neper-card.src.md`.

### LF-02 Short forms forward every flag - S, Sonnet, low
- Evidence (verified): `check bad.e --bogus-flag --deadline 5` behaves as plain `check`.
  The loop at `main.e:1262-1297` knows 12 flags and skips the rest; `test` never
  forwards `--only` (`:1470-1482`); `check FILE` drops `--project`/`--overlay`
  (`:1489-1500`); `build` drops `--arena/--time/--deadline/--cpu/--gpu/--stats`
  (`:1350-1392`).
- Do: forward unrecognised flags verbatim so `flags_known`/`check_flags` judge them.
  Remove the 16-argument cap at `main.e:14716`
  (`args.len <= 16 || has_dashdash`).
- Accept: `build F --time` prints phases; `check F --nope` exits 2; `test F --only a`
  runs one test; a build with five `--overlay` pairs is accepted.

### LF-03 Bounded, compact answers by default - M, Sonnet, medium (after LF-01)
- Evidence (measured on `src/main.e`): `uses-file --symbol main.same` 142 KB, 503
  records of ~280 B, every span zero-width; `uses_json` has no page (`tool.e:4640`).
  `index-file` 12.7 MB, 32,835 records, no filter (`main.e:14650`).
  `context-file --symbol main.dispatch` spends 40 of its 64 records on `dependency`
  facts carrying 64-hex hashes (`tool.e:3281`). The context `subject` span has
  `byte_start == byte_end`, so a worker cannot learn where the body ends.
- Do: put the existing `Page` on `uses_json`, `explain_json`, `impact_json` and the
  index (default 64 records, `complete:false` + `cursor`). Add
  `index --module M --kind fn|type|const --name PAT`. Move dependency facts behind
  `--deps`. Give `subject` the declaration's full extent. Add `--compact`: one line per
  record, `path:line:col in-function`, no JSON.
- Accept: default `uses main.same` is under 8 KB and resumable by cursor; context on
  `main.dispatch` shows at least 55 body facts; subject `end_line > line`; `--compact`
  output for `main.same` is under 20 KB for all 503 uses. Schema version bumped and
  `scripts/validate_stream.py` goldens refreshed.
- Files: `src/tool.e` (3200-3400, 4600-4760), `src/main.e` (13425-14102),
  `docs/schemas/`, `docs/tooling.md`.

### LF-04 `check --digest`: keep-going text diagnostics with fixes - M, Sonnet, medium
- Evidence (verified): text mode prints 1 of 3 errors as `path:l:c: error[CODE]: msg`
  with no fix (`emit_diagnostic`, `main.e:5144-5158`; first-error stop noted at
  `:10432`). JSON mode gave all 3 in 2.3 KB. Per-function continuation runs only under
  `--json` (`main.e:10499`).
- Do: a `--digest` mode (and make it the default for short-form `check`): keep going,
  one line per diagnostic
  `path:l:c CODE message | expected T, actual U | fix l:c-l:c -> "text"`, capped at 20,
  then `N errors (M shown), K unchecked`.
- Accept: the three-error fixture gives three lines under 500 bytes total; output is
  sorted by path, line, column and stable across `-j 1` and `-j 8`.

### LF-05 `neper fix`: apply a diagnostic's own fixes - M, Sonnet, medium (after LF-04)
- Evidence (source): five fix kinds exist, all `maybe` (`main.e:5311-5322`);
  `plan_collect` (`main.e:6240`) reads only `precondition`/`edit` records, so nothing
  applies a diagnostic's fix.
- Do: `neper fix FILE [--code C] [--dry-run]` collects the fixes of one check, turns
  them into a plan and runs it through `apply_transaction` (hash preconditions,
  re-check postcondition, as plans have today). Only fixes marked machine-applicable
  apply; promote the rename (E-NAME-0003) and cast-insert fixes from `maybe` when the
  re-check passes.
- Accept: the card's E-NAME-0003 and E-TYPE-0002 reject fences become clean after
  `fix`; a stale file hash aborts with nothing written.

### LF-06 `neper explain CODE` - S, Sonnet, low
- Evidence: `--explain` today is the inliner's (`main.e:14970`); `docs/diagnostics.md`
  has one line per code.
- Do: `neper explain E-XXXX-nnnn` prints the registry line, a minimal rejected example
  and the corrected form. The examples are generated at build time from the card's
  `neper reject` fences and the reject conformance corpus by a script (content it
  computes), not hand-kept twice.
- Accept: every code the card lists as verified has an explanation; an unknown code
  exits 2.

### LF-07 `neper verify`: the whole repair loop in one call - M, Sonnet, medium (after LF-04)
- Do: `neper verify [--changed m1,m2]` runs check + `fmt --check` + test-impact +
  `test --only` in one process, one digest, at most 30 lines; exit 0 only if all pass.
  With no `--changed`, it derives the changed modules from source hashes against the
  last manifest.
- Accept: on a one-function edit of a fixture project, output is at most 30 lines and
  names the tests it ran and the ones it skipped as unreached.

### LF-08 Every checker diagnostic kind has a registered code - M, Sonnet, mechanical, low
- Evidence (source): `diagnostic_code` (`check.e:17131-17182`) names 60 of 92 kinds;
  30 fall to `ret "E-TYPE-9999"` (`:17181`), including `FieldMissing` (which already
  carries a rename fix, `:2518`), `NonExhaustive`, `AssignmentImmutable`, `NotAType`,
  `MultipleBindingCount`, `ArrayElementCount`. 15 more map to other `-9999` codes
  (`:17146,17157,17161,17162,17176,17178,17180`), including the four `Try*` kinds and
  `GpuLaunch`. Unknown value, type and member all share E-NAME-9999
  (`main.e:9751,9774,9814`). Unregistered codes are emitted: `E-LIMIT-9999`
  (`main.e:9901`), `E-CODEGEN-9999` (`:10046`), `E-WASM-9999` (`:1934`), `E-CLI-0001`
  (`:2694`), which `docs/diagnostics.md:89-90` forbids.
- Do: register a code per kind in `docs/diagnostics.md`, extend `diagnostic_code`,
  split E-NAME-9999 into unknown-value / unknown-type / unknown-member, register the
  four stray codes. Add `scripts/check_diagnostic_codes.py`: fails if a
  `DiagnosticKind` other than `None`/`Generic` maps to a `-9999`, or if `src/` emits a
  code the registry lacks. Run it in both suites.
- Accept: one reject fixture per new code; the script passes; the card's per-family
  counts re-render.
- Also: drop the spurious `E-TYPE-0002 initializer type does not match binding` that
  precedes an unknown-name error (`main.e:9726-9728`, `resolve.e:1009-1012`; verified
  with `let count: usize = cuont`).

### LF-09 Syntax errors say what was wrong - M, Sonnet, medium (extends T028)
- Evidence (verified): one emit site (`main.e:8640`) for 89 bare `ret InvalidSyntax`
  in `parse.e`. Shapes an LLM writes from habit, and today's answer:

  | Input | Today |
  |---|---|
  | `let x = 1;`, `a ? b : c` | `E-LEX-9999: invalid token` (`lex.e:1186`) |
  | `5u` | `E-LEX-0003: invalid token` |
  | field `ok:` / `fn error()` | `unexpected 'ok'; expected a name` (`parse.e:1771,1672`) |
  | `for type in` | `unexpected 'type'` (`:1398`) |
  | `0 < n < 4` | `unexpected '<'` (`:836`) |
  | `R {}` | `unexpected '}'` (`:601`) |
  | `return ok` | `unexpected 'ok'` |
  | `else` on its own line | `unexpected 'else'` |
  | `i++` | `unexpected '+'; expected an expression` |

- Do: a reason enum on `parse.Tree`, set at these sites; `record_failure(..., true)`
  wherever `require(.Identifier)` meets a keyword; in `print_parse_failure` emit a
  registered code per reason with a fix: delete `;`, `return` -> `ret`, `i++` ->
  `i += 1`, keyword-as-name -> suggested rename, `R {}` -> `zero`, chained comparison
  -> `a < b && b < c`, ternary -> `if` form in the message.
- Accept: one reject fixture per row pinning code and fix; the card's "Traps" section
  gains nothing (the diagnostics now carry it).
- Files: `src/parse.e`, `src/lex.e:1186`, `src/main.e` (8600-8700).

### LF-10 Declaration errors always have a location and a kind - M, Sonnet, medium
- Evidence (source): bare error returns with no `record_failure`: InvalidType 252,
  TypeMismatch 71, Unsupported 63, ArgumentCount 49, InvalidConstant 49,
  InvalidOperator 38, InvalidFormat 37. Bodies have a statement-level fallback for
  three errors only (`check_statement`, `check.e:16141-16150`). Declarations have
  none: `collect_constant_declaration` (`:5746-5747`) and `evaluate_constant`
  (`:8419-8428`) return bare with the constant's token in hand. Result: `1:1
  E-TYPE-9999 type checking failed` (the known f32/str module-const symptom), and a
  token-less failure also ends cascade collection (`main.e:10408`).
- Do: record at the constant token in those two functions; add a fallback in
  `declarations_module`/`run_declarations` using `c.declaration`; add kinds (and codes,
  via LF-08) for format-verb error (`check.e:12115`), non-bool condition, duplicate
  case. Extend the statement fallback to every error in the list above.
- Accept: `const PI: f32 = 3.14` and `const S = "x"` in a context that fails report at
  the declaration with a registered code; a bad format verb names the verb and its
  column. A script counts bare `ret <Error>` lines without a preceding record in
  `check.e` and ratchets the number down.

### LF-11 Float literals are range-checked by the checker - S, Sonnet, low
- Evidence (source): `decimal.literal_bits` has one caller, `lower.e:295`; `check.e`
  has no `use decimal`. `let x: f32 = 1e39` passes `check-file` and fails in lowering
  as `cannot lower f: lowering failed`, E-TYPE-9999.
- Do: call `decimal.literal_bits` in the float-literal arm of `check_expr_uncached`;
  record a float-range kind mapped to E-TYPE-0004 (as integers are).
- Accept: reject fixture, E-TYPE-0004 at the literal, under `check-file` alone.

### LF-12 Many errors per function, no cascades - L, Opus, xhigh (wave 4)
- Evidence (source): `record_failure` returns if `c.failure_has_token`
  (`check.e:980`) and every statement is a `try`, so one diagnostic per function.
  No poisoned type exists (`Kind.Invalid` means unknown, not reported); each failing
  declaration re-runs all declarations on a fresh checker (`main.e:10416-10422`).
- Do: statement-level recovery in `check_block`: record, restore `local_count`,
  continue, cap 8 per function. `.Invalid` from a recorded failure is "already
  reported": `apply_context` and binary/call checks stay silent on it. New fix kinds:
  5 arity (counts already in `record_call_arity`, `check.e:20131`), 6 discarded call
  -> `try f()` or `let _ = f()` (`:14855`), 7 non-exhaustive switch -> add the named
  member arm.
- Accept: three independent errors in one function give three records; one undefined
  local used five times gives one; both suites' reject goldens reviewed for count
  changes.

### LF-13 A failed block header does not cascade; all failures print - S/M, Sonnet, medium
- Evidence (verified): `if x = 2usize {` yields 5 `unexpected` notes for the rest of
  the function; `recover_statement` (`parse.e:1616-1623`) stops at the newline so the
  body's `}` closes the enclosing block. Plain mode prints only `failure_token`
  though 64 are kept (`main.e:9485-9491`); the 65th is dropped silently (`parse.e:130`).
- Do: when the failed line ends in `{`, skip the balanced block in
  `recover_statement`; print every non-cascade failure in plain mode; say "and N more"
  past the cap. Restore `depth` (not only `soft_depth`) in recovery
  (`parse.e:798-800,824-838,1645-1647`).
- Accept: that fixture reports one diagnostic; a file with 100 bad statements reports
  64 and the count of the rest.

### LF-14 Module errors have a span and a suggestion - S, Sonnet, low
- Evidence (verified): `use e.strng` on line 2 reports `1:1`; `main.e:9539-9540`
  passes `no_token`; `graph.e:1316-1319` keeps only the name.
- Do: keep the `UseDecl` token in `graph.Import` (`collect_imports`); suggest the
  nearest directory-listing entry with `resolve.edit_distance`, as a fix.
- Accept: reject fixture asserts line 2 and a `fixes` entry `e.str`.

### LF-15 Duplicate and shadow errors name the first site - S, Sonnet, low
- Evidence (verified): E-NAME-0003 and E-NAME-0001 show only the second site;
  `resolve.Local` has no token (`resolve.e:47-50`, `:296-301`, `:895-905`).
- Do: store the token in `Local`; put the prior site in `related`. For E-NAME-0003
  against a module-scope function or qualifier, `related` is that declaration or `use`.
- Accept: reject fixtures assert `related[0]` line.

### LF-16 One command table drives dispatch, usage, `info` and exit codes - M, Sonnet, medium (T054, T011)
- Evidence (source): `info --json` lists 10 commands and
  `build_targets:["x64-linux","x64-windows"]` (`tool.e:237`) while eleven targets are
  dispatched; `capabilities_json` (`tool.e:262-263`) is a hand-kept string missing
  `--overlay/--path/--symbol/--only/--bytes/--cursor/--project/--target/
  --memory-budget`. Usage errors exit 1 (`main.e:1134`, `:15568`) but a bad
  `--language-version` exits 2 (`:1203`).
- Do: one const table (command, positionals, flags with value kind, writes-project
  yes/no, exit codes). Generate from it: flag validation, the usage text, `--help`,
  and `info --capabilities` (which also lists targets from PL-01's table and the
  diagnostics registry). Usage errors always exit 2; diagnostics found exit 1.
- Accept: `scripts/check_agent_routes.py` gains a check that every dispatched command
  is in `info`; a tools golden pins the capabilities stream.

### LF-17 Probing never writes into the project - S, Sonnet, low
- Evidence (source): `fmt` with no operand becomes `fmt-project --write`
  (`main.e:1408`); `check`/`index` with no operand create `.neper/debug/<leaf>`
  (`:1420`).
- Do: project-wide `fmt` requires explicit `--write` or `--check` (bare `fmt` prints
  what it would change and exits 1); `check` keeps child output in memory.
- Accept: a tools test snapshots a project tree, runs bare `fmt`, `check`, `index`,
  and finds the tree byte-identical.

### LF-18 Internal failures say where - S, Sonnet, low
- Evidence: `main` returns the raw error (`main.e:14237`); the user sees
  `E-TOOL-9999: internal compiler failure` and a bare error name.
- Do: keep the current phase and module in `Sink`; on an internal error print them
  plus a one-line repro (argv, compiler CRC). Register `E-TOOL-0005` for it.
- Accept: a self-test hook that forces an internal error in lowering prints the phase
  and module.

### LF-19 `uses-file` answers for constants and globals - S, Sonnet, low (next to T075)
- Evidence: `tool.e:4658` "names no function, type, field or error".
- Accept: `uses --symbol m.CONST` equals a grep count on a fixture.

### LF-20 A generated compiler map - S, Sonnet, low (wave 3 entry)
- Evidence: no architecture map exists; `main.e` has no header line; headers of
  `check.e` ("foundation") and `parse.e` ("revision-1") are stale.
- Do: fix the headers (one line of responsibility each). `scripts/render_digest.py`
  gains `docs/digest/compiler-map.tsv`: file, lines, responsibility, and for files
  over 3k lines the function clusters with line ranges (from `^fn` positions). Workers
  read it instead of the file.
- Accept: the map regenerates deterministically; `AGENTS.md` routing names it.

### LF-21 `plan-move-file`: move a function between modules - M, Opus, high
- Why: the splits below are thousands of mechanical requalifications; a plan command
  does them with hash preconditions, and agents get a general refactoring.
- Do: `plan-move-file --symbol m.f --to module2` emits edits that move the declaration
  and qualify or requalify every use, refusing when the move would create an import
  cycle (`graph.e:1170`).
- Accept: move a function between two fixture modules and back; tree byte-identical
  after the round trip.

### LF-22 Split `main.e` (15.5k) and `tool.e` (8.1k) - L, Opus, high, refactor (byte gate)
- Constraint: imports are acyclic, so `Sink` and the report helpers move first.
  `dispatch` is at the bootstrap's local cap (`main.e:14803`); split it into
  per-family functions as part of this.
- Proposed modules (approximate lines of `main.e`): `selftest.e` 44-784;
  `cli_flags.e` 785-1131 + 14260-14293; `cli_short.e` 1132-1604; `run_cmd.e`
  1949-2237; `test_cmd.e` 2238-3236; `project_cmd.e` 3396-4300; `report.e`
  4982-6205; `plan_apply.e` 6228-6972; `manifest_cmp.e` 6973-7381; `diag_text.e`
  7951-8729 + 9547-10400; `hot.e` 7468-7911 + 8730-9546 + 11263-11693; `crew.e`
  11694-13424; `query.e` 13425-14102. Of `tool.e`: `fmt.e` 1817-2927; `plan.e`
  3923-4030 + 4753-5400 + 5583-5990; `manifest.e` 6337-7516.
- One module per session, in the order listed, each landing alone.
- Accept: byte gate after every step; no `src` file over 4k lines at the end; the
  bootstrap (until PL-09) still builds it.

### LF-23 Split `check.e` (22k) - L, Opus, xhigh, refactor (byte gate)
- Leaf clusters with no back-edges, move first: constant integer arithmetic
  5753-6001; format verbs 9967-10195; atomic tables 11124-11242; diagnostic tables
  17131-17267; intrinsic seeds 4729-5245; layout 6184-6470; region and keeps walks
  17285-18186.
- Then, needing a bottom `check_core.e` for types and errors (no error alias exists,
  so `lower.e`'s 1,168 `check.` references are requalified with LF-21): interpreter
  6473-8399; resources 18927-22069; device 18187-18926.
- Accept: byte gate after every step.

### LF-24 Streaming `query-batch` as the server transport - S then M, Sonnet, medium (T062)
- Evidence: `source.load_stdin` at `main.e:13646` reads all of stdin first; a cold
  query costs 0.8-1.7 s on the compiler itself.
- Do: read stdin line by line, flush per answer; `BatchSession` already holds the
  snapshots. That is T062's `neper mcp` transport: a long-lived process so each agent
  call skips load, parse and check.
- Accept: a second query in one session answers in under 50 ms on `src/main.e`.

### LF-25 One suite, one fixture table - L, Opus, xhigh
- Evidence: `tests/selfhost/run.ps1` (12,615 lines, 1.3 MB) and `run.sh` (12,450
  lines, 1.0 MB) are the same suite written twice by hand; every fixture is a stanza
  in each. A worker adding a fixture edits both and cannot read either.
- Do: a fixture manifest (one row per step: fixture, command, target, expected stdout
  or exit code or trap text, host filter) and one runner. The runner is a Neper
  program built by the stage under test (`e.proc`, `e.fs` exist), with bounded workers
  by free memory, a per-step timeout, `--only`, `--resume`, and collect-all-failures
  as the default. `run.ps1`/`run.sh` shrink to: build the stages, run the runner.
  Migrate in slices: link fixtures first (the regular shape), special stanzas last;
  each slice deletes its stanzas from both scripts in the same commit.
- Accept: the migrated slice's pass/fail set equals the scripts' on both hosts; T076's
  acceptance (finishes, resumable, stderr tolerant) holds for migrated steps.
- Queue: T076 (widened).

### LF-26 `check-fixture.sh` shows the error - S, Sonnet, low
- Evidence: the build log goes to `build/check-fixture-build.log` with only "see log"
  printed (`scripts/check-fixture.sh:56-57`); the output `neper-try.exe` is shared by
  every session; it always rebuilds through the C bootstrap.
- Do: print the log's first 20 diagnostic lines; honour `NEPER_SEED`; per-session
  output name.

---

## 3. Hardening (HD)

### HD-01 Resource containment is truncated at depth 6 and the wrong answer is cached - S, Opus, high, soundness
- Evidence (source): `check.e:19096` `if depth > 6usize { ret 0u8 }` (0 = plain);
  `:19135` memoizes `affine_memo` whatever depth computed it. A `File` eight structs
  deep is untracked, and the answer depends on query order and so on worker schedule.
  The sibling `holds_pointer` (`:19068`) fails safe with `ret true`.
- Do: in `affine_kind`, drop the limit (by-value cycles are refused by
  `validate_aggregate_value_cycles`) or return "owed" at the limit; memoize only at
  depth 0.
- Accept: nine nested structs, innermost holding `os.File`, close forgotten:
  E-SAFETY-0002 in both declaration orders and at `-j 1` and `-j 8`.

### HD-02 x64 does not widen narrow integer parameters arriving in registers - S, Opus, high (C256)
- Evidence (source): `codegen_x64.e:2137-2139` in `prologue_parameters` stores the
  register as-is; the direct-move path `:2118-2124` also skips it; only stack-passed
  arguments are normalised (`:2148`). `store_incoming_parameters` (`:2197`) is dead
  since `24402e8ba`. a64 widens (`codegen_a64.e:1616`).
- Do: call `normalize_integer` when `integer_width(incoming) < 64` (always, or when
  the function is C-reachable: address taken, exported, `@cc`; measure the count gate
  for "always"). Delete the dead function.
- Accept: a C shim calls a Neper callback with i8/i16/i32 min and -1 and u8/u16/u32
  max, in register and stack positions; both back ends agree; `< 0` holds.

### HD-03 Negative tags of a narrow signed enum never compare equal - S, Opus, high (C256)
- Evidence (source): `enum_member_bits` (`check.e:2570-2579`) returns the
  width-truncated pattern; `lower.e:1840` emits it as `ConstInteger` of `tag_type`
  and `:1844` compares with a sign-extended load (`codegen_x64.e:4289`,
  `codegen_a64.e:1989`): 0xFFFFFFFF against 0xFFFF...FFFF. Same call at `lower.e:388,
  451, 2165, 2467, 5344, 5451, 8992, 10328` (each constant's type not traced).
- Do: one helper `nir.const_integer(builder, ty, magnitude, negative)` emitting the
  64-bit canonical form; `lower_constant` and every `enum_member_bits` site use it.
- Accept: `enum i8/i16/i32 { A = -1, B = -128 }` and a `union enum i32` through
  literal, struct field, switch, generated `eq` and formatter, both back ends.

### HD-04 Register eviction assumes value numbers ascend with position - S, Opus, high
- Evidence (source): `regalloc.e:930` walks values by number; eviction `:987-993`
  pops only the top holder. `nir.e:1612-1663` (`hoist_frame_addresses`) moves
  late-numbered values into the entry block, giving them an early `first`, so other
  holders can overlap. Latent miscompile on CPU kernels.
- Do: in `allocate_with`, sort by `first` with `sort_values_by_key`, or track the
  maximum `first` and make an out-of-order value spill itself.
- Accept: a `regalloc.self_test` case with an out-of-order value under pressure
  asserting no two overlapping ranges share a register; a kernel fixture with more
  than 12 hot locals in a loop equal to the serial result.

### HD-05 Parser nesting bound has two holes: stack overflow, no diagnostic - S, Sonnet, low
- Evidence (verified): a 2,000-link `p.b.b...` chain and 20,000 nested `switch` exit
  `0xC00000FD` with empty output. `parse.e:766-789` (postfix loop) and `:1550-1568`
  (`parse_switch_statement`) never call `enter`; `resolve.e:973-983` recurses over it.
- Do: count each postfix link as a level in `parse_postfix_node`; `enter` in
  `parse_switch_statement`.
- Accept: both shapes reject with the "nesting deeper than 128" diagnostic.

### HD-06 Valid large literals are rejected as syntax errors - S/M, Sonnet, medium (C254-adjacent)
- Evidence (verified): a 71 KB file with a 20,000-element `[_]u8{...}` gives
  `E-SYNTAX-9999 unexpected ','` at 1248:16. The tree pool is a guess
  (`graph.e:443-444`: `bytes / 2 + 4096` nodes, `bytes + 8192` children; again at
  `:1073,1079`) and `parse.e:182,189` return `InvalidSyntax` when full.
- Do: `add_child`/`add_node` return a distinct `parse.PoolFull`; `graph.parse_into_pool`
  and `worker_module` double the pool and reparse.
- Accept: link fixture with a generated 20,000-element table builds and sums right.

### HD-07 Every capacity names itself (C254, concrete list) - M, Sonnet, medium
- Evidence: symbols sized `sized(4096, total, 64)` (`main.e:4525`); 12,000
  `const` lines give `1:1 E-NAME-9999 name resolution failed` because
  `main.e:9824-9826` prints before `capacity_name` (`:14136`); 6,000 give `1:1
  E-TYPE-9999` (verified both). About 60 `ret Capacity` sites in `check.e` record no
  token or pool. Others: 8192 modules / 262144 imports (`main.e:4506,4508`), import
  depth 1024 (`graph.e:1160`), 256 directories reported as "`use x` cannot be
  resolved" (`project.e:361`, `main.e:9533`), 1024 project sources reported as "no
  readable src directory" (`main.e:3431,3694`), Mach-O 2048 imports as `InvalidImage`
  (`link_macho.e:569`), 16 params / 4 returns per function type (`check.e:3787-3789`),
  16 constant-call arguments reported as `InvalidConstant` (`:5596,6046`), loops 64,
  pins 16, comptime bindings 8, `UNDEF_FIELDS` 32.
- Do: size symbol and checker pools from the top-level node count the loader has;
  route `resolve.Capacity` through `capacity_name`; a `capacity(c, pool_name, limit,
  token)` helper in `check.e` used at every `ret Capacity`; register `E-LIMIT-0001`
  with pool name, limit and the flag or constant that raises it.
- Accept: the 12,000-const file checks clean; a fixture per remaining fixed limit
  asserts the pool's name in the message. `resolve.e:230` and `fill_indexes`
  (`check.e:5344`) stop falling back to linear scans silently: they report.

### HD-08 Safety facts are dropped silently at fixed limits - S, Opus, high, soundness
- Evidence (source): `resource_pin` (`check.e:18981`) returns silently at 16 pins, so
  the 17th `&x` in one statement is unpinned and E-SAFETY-0004 unenforced.
  `set_kernel_fact` (`:16510-16512`) past 64 kernels records "none", and which ones
  follows the worker count. `:16110` reads `c.break_locals[c.break_depth - 1]`
  unguarded at loop depth 65 (inferred: bounds trap).
- Do: each returns the named capacity error of HD-07 instead of dropping.
- Accept: a 17-pointer statement followed by a move reports E-SAFETY-0004 or the
  named limit, never silence; 65 nested loops with `break` reject by name.

### HD-09 Type memo key ignores `in_shared` and `foreign` - S, Opus, high
- Evidence (source): `same_expectation` (`check.e:13706-13710`) omits both;
  `type_equal` honours them (`:1345,1373`). `memo_intern` (`:13581`) and the
  expression cache (`:13657`) key on it and lowering reads the memo. Inferred
  consequence: `[]shared T` answered as `[]T`.
- Do: add both fields to `same_expectation` and `memo_hash`.
- Accept: one expression checked under both expectations in one function yields both
  types (C255-style probe).

### HD-10 Identical-function folding trusts a 64-bit hash - S, Sonnet, medium
- Evidence (source): `fold_function` (`main.e:10845-10848`) folds on a hash match
  with no byte comparison, and scans every earlier hash linearly.
- Do: an open-addressing table keyed by hash, and a byte compare of the hash input
  before folding.
- Accept: a self-test forcing two different bodies to one hash keeps both; `--time`
  `fold_ns` on the all-library root drops; byte gate.

### HD-11 NIR type verifier and allocation verifier - M, Opus, high (feeds C256)
- Evidence (source): `nir.e:1727-1936` checks structure only and runs in
  `end_function` (`:2153`), before `promote_locals` (`regalloc.e:278`) rewrites the
  function. Unchecked assumptions of both back ends: binary operand types agree;
  Load/Store width is 1, 2, 4 or 8; a narrow `ConstInteger` is canonical for its type;
  Call arity and types match the signature; `Extract` immediate below 2; no Phi or
  Switch reaches selection; value order (HD-04).
- Do: `nir.verify_types(builder, function)` from `end_function`, and again after
  promotion; a debug-build `regalloc.verify_allocation` after `allocate_with`.
- Accept: `nir.verify_self_test` gains one rejected function per invariant; reverting
  HD-03's fix locally fails with `Unverified` (state it in the D-row, do not commit
  the revert). Count gate: verifier cost under 2% of self-build in release.

### HD-12 a64 frames are not stack-probed - S, Sonnet, medium
- Evidence (source): `codegen_a64.e:107-112` is a bare `sub_immediate`; x64 probes
  every 4096 bytes (`emit_x64.e:664-687`, confirmed).
- Do: probe loop in `frame_prologue` above one page (16 KiB step on macOS).
- Accept: a thread with a 1 MB local array written from the far end exits 0, and
  unbounded recursion traps cleanly, under qemu-aarch64 and on the macOS runner.

### HD-13 Project `check` trusts children it never reads - M, Sonnet, medium
- Evidence (source): `check_project_command` (`main.e:3722-3739`) spawns
  `check-file` per source, never reads `status`; all children share the output base
  `npcheck-child` (`:3709`), so two sessions clobber each other. Cost is every file's
  import closure, serially.
- Do: one in-process load with all sources as roots (the graph already dedups
  modules). Until then: nonzero status with no result record is E-TOOL-9999, and the
  child base is random (`stage_bytes` does this).
- Accept: two concurrent project checks both answer correctly; a fixture whose child
  is killed reports `ok:false`; project check time on `lib/e` at most 1.2x one
  whole-program check.

### HD-14 Emitted images get the platform's standard mitigations - M, Sonnet, high
- Evidence (source): PE DllCharacteristics 256 (NX only), fixed base, no `.reloc`
  (`link_pe.e:346,359`). ELF x64 is ET_EXEC at a fixed base unless android or shared
  (`link_elf.e:138-141`); no PT_GNU_STACK or RELRO in any ELF writer (inferred: the
  stack is executable by default on x86-64). Mach-O already has PIE, 16K pages and an
  ad hoc signature.
- Do: PT_GNU_STACK (RW) in all four ELF writers; Linux executables ET_DYN as Android
  already is; PT_GNU_RELRO over the GOT (BIND_NOW is set); PE flags 0x160 with a
  reloc directory. A `--no-pie` flag keeps the old form for freestanding images.
- Accept: byte checks in `link_elf.self_test` and `link_pe.self_test`; `readelf -lW`
  shows `GNU_STACK RW`; the trap fixture still names its frames under ASLR; DWARF
  line fixture still resolves under gdb.

### HD-15 Generic-argument rows leak; parallel arrays unchecked - S, Sonnet, medium (C254)
- Evidence (source): `specialize_call` (`check.e:9240-9246`) and `specialize_value`
  (`:13411-13417`) claim `generic_arguments` rows per call site and never return them
  on a cache hit; only `atomic_wrapper_type` rolls back (`:11269,11274`).
  `resources` is indexed by `local_count` (`:8550`) but guarded only by `locals.len`;
  `init` (`:1018`) never compares the lengths.
- Do: roll back on a hit; assert equal lengths in `init`.
- Accept: a fixture with 50,000 calls of one generic instance builds at the default
  arena; self-test for the length check.

### HD-16 One "still generic" predicate, one substitution (C255) - S/M, Opus, xhigh
- Evidence (source): `type_shape_unknown` (`check.e:1403`),
  `type_depends_on_comptime` (`:1393`) and `type_still_generic` (`:3675`) disagree;
  the last ignores `Array && !has_length`, so `Box[[N]T]` reads as concrete
  (inferred). `substitute_type` (`:8757-8854`) and `substitute_aggregate_type`
  (`:3721-3814`) are near-copies.
- Do: one `type_pending(c, ty)`; one substitution taking a lookup mode. Then C255's
  probe matrix is written once against it.
- Accept: the C255 matrix (instance over instance at ret / assign / let / argument /
  field / array length) passes; byte gate.

### HD-17 Module path segments are case-checked - S, Sonnet, low (near C235)
- Evidence (verified): `use E.mem` is accepted on Windows; `project.e:294-302`
  matches the file stem exactly but `source_directory` (`:250`) trusts the OS for
  directories. Inferred: the same source fails on Linux.
- Do: in `select_source`, match each prefix segment against its parent listing.
- Accept: reject fixture on Windows with the registered module code and the
  correctly-cased name as the fix.

---

## 4. One code base, many platforms (PL)

Target matrix today (all targets are produced from any host; writers are byte-wise):

| target | linker / object | runtime | executed where |
|---|---|---|---|
| x64-windows | `link_pe.e`, `object_coff.e` | `runtime_pe_x64` | local Windows only; no CI runner |
| x64-linux | `link_elf.e`, `object_elf.e` | `runtime_elf_x64` | WSL; `linux-suite.yml` (manual) |
| aarch64-linux | `link_elf_a64.e` | `runtime_elf_a64` | 3 fixtures, only if qemu-aarch64 is present |
| x64/aarch64-android | ELF linkers + `builder.android` | ELF runtimes | never executed (one byte check) |
| x64/aarch64-macos | `link_macho.e` | `runtime_macos_*` | `macos-a64.yml` on push, but on committed binaries |
| aarch64-none / -neperos | `link_image_a64.e` | `runtime_none_a64` / `_neperos_a64` | qemu-system-aarch64 if present |
| wasm32-wasi | `wasm*.e` | none (`os.wasi.e`) | Node in both suites; CI manual |
| x86-* | accepted by `valid_arch`, no emitter | - | never |

### PL-01 One target record - L, Opus, high, refactor (byte gate). Prerequisite of C225, C238, C237
- Evidence (source): about 90 target string compares in 12 files (`main.e` 38,
  `project.e` 19, `stats.e` 6, `resolve.e` 6, `lower.e` 6, `em_link.e` 5, `tool.e` 3,
  `check.e` 3, `graph.e` 2, one each in `wasm.e`, `em.e`, `platform.wasi.e`) and six
  hand-kept lists that already disagree: `project.e:141` `target_suffix`, `:210`
  `valid_arch`, `:214` `valid_os`, `:409` `variants_seen` (no android), `main.e:7094`
  `host_variant_path` (has freebsd/android/ios, lacks neperos/wasi/none),
  `check.e:2884-2898` `target.Arch`/`target.Os`. Linker choice is a nested `if`
  (`main.e:15404-15428`); `em_link.e:1123-1131` re-derives the arch from five strings.
- Do: `src/target.e` with one `Target` struct (name, arch, os, source_os for variant
  selection, abi, object format, linker id, runtime id, page size, image base,
  interpreter path, executable file mode, variadic style, pointer bits, features) and
  one const table. `main.dispatch`, `machine_abi_of`, `save_executable`,
  `graph.load`, `project.valid_*`, `em_link`, `stats`, the `check.e` enum seeds and
  `info` read it. `x86` is refused by name until C224 (today it falls through to
  SystemV x64). `save_executable` (`main.e:6208`) takes the mode from the record
  (Android output misses 0755 today).
- Accept: `scripts/check_target_literals.py` fails on any target literal in `src/*.e`
  outside `target.e`; byte gate; adding a dummy row for a new OS on an existing arch
  needs edits in `target.e`, a runtime, and `lib/e/os.<os>.e` only (write that
  checklist into the file header).

### PL-02 aarch64 ELF segment alignment is 4 KiB - S, Sonnet, low (C236)
- Evidence (source): `link_elf_a64.e:21` `A64_IMAGE_PAGE = 4096`, used at `:309`.
  Inferred: on 16K/64K-page kernels (Android 15+ devices, Asahi, RHEL aarch64) RX and
  RW share a page and the image fails to load.
- Do: 65536 for aarch64 ELF in `write` and `write_dynamic` (from the target record
  once PL-01 lands).
- Accept: byte check `p_align >= 16384` and `p_vaddr % p_align == p_offset %
  p_align`; a fixture runs under `qemu-aarch64 -p 65536`.

### PL-03 Host detection and positional arch - S, Sonnet, low
- Evidence (source): `main.e:1962` answers `x64-linux` for any non-mac POSIX host;
  `main.e:1232` recognises only `x64` and `wasm32` as a positional arch, so
  `run F R aarch64 macos OUT` is read as the short form. `graph.e:342-346,384-388`
  decide the host by whether cwd starts with `/`.
- Do: read `e_machine` from the compiler's own ELF header (as `macos_target` does for
  Mach-O); use `project.valid_arch` at `:1232`; move the cwd test into `platform`.
- Accept: under qemu-aarch64, `neper build hello.e` writes an aarch64 ELF.

### PL-04 Runtime blobs: one assembler, a drift check, shared routines - M, Sonnet, medium
- Evidence (source): the seven `runtime_*.e` are embedded bytes generated by
  `scripts/embed-elf-runtime.ps1` (WSL GNU `as`, or `zig cc` with a different
  `-mcpu`) and `embed-pe-runtime.ps1` (`ml64`), Windows only. No suite or workflow
  checks a blob against its `.s`. Bodies identical across OSes: `neper_mem_alloc`,
  `neper_os_copy_bytes`, `neper_os_sha256_blocks` (a64 x3, x64 x2), x64 `aes_ctr`,
  `ghash_blocks`, `aes_expand_key`.
- Do: (a) `scripts/check_runtime_blobs.sh`: reassemble with one pinned assembler and
  diff against the `.e` bytes, run in `linux-suite.yml`; (b) split OS-neutral routines
  into `runtime_common_{x64,a64}.s`, concatenated by the embed step; (c) an sh embed
  script so regeneration is not Windows-only.
- Accept: changing one byte of a `.s` without re-embedding fails the check; blobs
  byte-identical after the split.

### PL-05 Variant surface parity for every OS - S, Sonnet, medium
- Evidence (source): `scripts/check_module_surfaces.py:203` accepts only `windows`
  and `linux`. `e.os` function counts: linux 298, windows 244, wasi 218, macos 214,
  neperos 131; 117 names common to all. 18 lib modules have variants; `net/auth`,
  `debug/dump/host` lack a macOS variant and `net/tls/hoststore` has only Windows
  (fallback files not checked). One suffix only: `os.linux.aarch64.e` cannot exist
  (`project.e:484` `AmbiguousVariant`).
- Do: extend the script to macos, neperos, wasi; emit per-module matrix
  implemented / `Unsupported` / absent into `docs/progress.html` via
  `render_progress.py`; fail when a function is absent (not `Unsupported`) in any
  variant. Allow an `os.arch` double suffix in `project.e` variant selection.
- Accept: the script fails today, listing the gaps; each gap is then either
  implemented or given an `os.Unsupported` body.

### PL-06 CI runs current source on every target, on push - M, Sonnet, medium (C253 widened)
- Evidence (source): every workflow but `macos-a64.yml` is `workflow_dispatch` only;
  there is no Windows runner; `macos-a64.yml` copies committed binaries
  (`tests/macos/hello`, last committed 2026-10-22); `freebsd-suite.yml:30` emits a
  target `valid_os` rejects; Android output is never executed.
- Do: on push to master: build from seed, cross-emit every row of the target table,
  run x64-linux natively, aarch64-linux on `ubuntu-24.04-arm`, macOS natively on
  freshly built images, wasm under Node, Windows on `windows-latest` (link fixtures
  only), Android under the emulator (one smoke fixture). A matrix generated from
  `target.e` (PL-01) so a new row gets a job.
- Accept: a deliberately broken a64 encoding on a branch turns the push red.

### PL-07 A shared instruction selector - L, Opus, xhigh, refactor (byte gate). Before C242/C243
- Evidence (source): duplicated between `codegen_x64.e` and `codegen_a64.e`: the
  opcode ladder (x64 4158-4779, a64 1927-2200), the line-table block (4142-4157,
  1909-1924), the pre-pass in `function()`, Cast/narrow/overflow rules (4346-4377,
  608-632). x64 only: immediate operands and dead constants (3983-4019), constant
  shift counts (4405; a64 materialises `width-1` for every shift at 531),
  FieldAddress+Load fusion, direct parameter moves, fall-through inversion in
  `BranchIf` (4643), short jump over a trap, debug locals. a64 only: scaled index.
  `regalloc.e:948` hard-codes `if register_count == 16 { caller_saved = 6 }`. Shared
  types sit in `emit_x64.Buffer` and `codegen_x64.Relocation`/`Abi`, which
  `codegen_a64` imports.
- Do: `src/select.e` owns the pre-pass, ladder, fusion decisions, line table, fixups
  and semantic checks, calling a per-target emit set; `regalloc.allocate` takes a
  descriptor (pool size, caller-saved count, vector count) from the target record;
  move the shared types to a neutral module. a64 gains the x64-only fusions as it
  moves onto the shared path (count gate on a64).
- Accept: byte gate on x64; a64 output changes only by the gained fusions, checked by
  the a64 differential; `codegen_a64.e` no longer imports `codegen_x64`.

### PL-08 riscv64-linux as the proof of PL-01 and PL-07 - L, Opus, xhigh (new; optional)
- Why: the cheapest honest test that a target is now a table row plus an emitter. The
  a64 path is the template (`emit_a64` 1460 lines, `link_elf_a64` 324). Needs an
  emitter, the per-target emit set, a runtime `.s`, `e_machine` and relocation numbers
  from the record. Runs under qemu-riscv64 in CI.
- Accept: the link-fixture slice that aarch64-linux runs passes on riscv64; the diff
  touches no file outside `target.e`, the new emitter, runtime and `os` variant.
- Decide before starting; C238 FreeBSD is the alternative proof for the OS axis and is
  cheap after PL-01 (OSABI byte, interpreter path, `os.freebsd.e`, a runtime).

### PL-09 Retire the C bootstrap through committed seeds - M, Opus, high (C088, C266, C263)
- Evidence (source): the bootstrap is still the default path in
  `scripts/build-bootstrap.sh`, `build-selfhost.{ps1,sh}`, `check-fixture.sh`,
  `run.ps1`/`run.sh` and seven workflows; `run.sh:78` already builds from
  `NEPER_SEED`. It costs `src/`: no `-=`, no `x > CONST {`, 400 locals per function
  (`main` and `dispatch` are at it), no `fs.temp_file` (`main.e:7383`), no `os.stat`
  (`:14151`), and it blocks T021.
- Do: publish a per-host stage-3 seed as a release asset, SHA-256 in
  `docs/bootstrap-archive.md`; `NEPER_SEED` becomes the default in the three scripts
  and CI fetches it; a seed is accepted only if rebuilding from it reproduces it
  (needs C267). After two consecutive reproducing seeds, delete `bootstrap/`, the
  card's "Bootstrap-only rules" paragraph, and the constraints in section 0 item 4.
- Accept: a clean clone on each host builds the compiler with no C compiler present.

### PL-10 Width axis for 32-bit targets - design only, Opus, xhigh (blocks C224, C239)
- Evidence (source): values are 64-bit throughout; even wasm32 keeps "every NIR
  value is an `i64`" (`wasm_code.e:6`). x86-32 and Thumb-2 need a pointer-width axis
  in layout, NIR and regalloc; z/OS (C241) needs a big-endian emit path, since every
  writer is little-endian by construction.
- Do: a decision row with the design (where `usize` width enters `layout.e`, how NIR
  types carry it, 64-bit arithmetic legalisation), and a cost estimate. No code.
- Also re-score L228: `lib/e/os.wasi.e` is 120 KB and fs/clock/process fixtures run
  in the wasm sweep, so its "missing WASI e.os" text looks stale.

---

## 5. Compile speed (CS)

### CS-00 A baseline that is one command - S, Sonnet, low (first)
- Do: `scripts/bench-compile.sh`: build a release compiler from the seed into a
  scratch directory outside the repo (the sandbox ACL note in memory applies), then
  report `--time` phases for (a) the self-build at `-j1` and `-j8`, (b) the
  all-library root, (c) a warm no-change build, (d) a one-function edit, (e)
  `check-file` and one `context-file` query. Five runs, median, one TSV row appended
  to `benchmarks/baseline/compile.tsv`.
- Accept: two consecutive runs differ by under 3% on (a). Every CS and XS package
  quotes its row before and after.

### CS-01 Warm builds do no SHA-256 and `--json` takes the no-op path - M, Sonnet, medium
- Evidence (source): the no-op shortcut requires `!report.json && !report.build.on`
  (`main.e:14821`) and short `run` always adds `--json` (`:1367`), so an agent's
  build never takes it. `source_sha_now` (`:8863`) hashes every source with SHA-256
  unless the manifest has `source_crc32c`, which only `emit-em-all` writes
  (`tool.e:7431`); `artifact_content_verified` (`:8905`) SHA-256s every kept
  artifact; `wave_texts` reads files serially (`graph.e:1259`).
- Do: the no-op path writes the JSON result; the hot executable manifest records
  `source_crc32c` (the D5973 key); then a size+mtime prefilter before any read.
- Accept: an unchanged `run --json` reports `load and parse` only; SHA-256 call count
  on a warm build is 0 (counter in `--stats`); CS-00 row (c) improves.

### CS-02 Generic instances: hashed lookup, shared across modules - M, Opus, high
- Evidence (source): `find_function_instance` (`check.e:9019`) scans every instance
  per generic call; `owner_instance_count` (`:9003`) scans again per new instance;
  instances are keyed by owner module (`:9023`) so a template body is re-checked per
  using module and per worker; `check_instance_body` (`:16655-16670`) scans all tree
  nodes by name though `declaration_at` (`:17901`) binary-searches;
  `protocol_function` (`:12621`) scans all functions per dispatch; `fork_checker`
  copies types, aggregates, fields, arguments and constants per worker
  (`main.e:11897-11928`).
- Do, in this order, one landing each: `lookup` table for instances keyed by
  (template, argument hash); `declaration_at` in `check_instance_body`; an index for
  `protocol_function`; then measure before attempting cross-module instance sharing
  (it changes artifact identity; needs its own decision row).
- Accept: an instance-heavy fixture (e.data.map over 200 key types); count gate.

### CS-03 Back-end constant factors - S each, Sonnet, low
- `lower.e:7543, 7685, 8727, 8966`: `var break_storage: [2048]usize = zero` clears
  16 KB per loop lowered; use `undef` or a shared stack.
- `lower.e:1223-1241`: `declare_globals` is modules x globals.
- `codegen_x64.e:3847-3889`: 16 delta rows per instruction cleared and swept per
  function; one event sweep.
- Accept: byte gate; count gate on the self-build.

### CS-04 Front-end constant factors - S each, Sonnet, low (type-name interning: medium)
- `error_table.e:63-88`: `validate_link` is errors x symbols, rehashing names per
  pair; `build` already sorts, so compare adjacent entries.
- `resolve.e:598`: a `"mem"` qualifier lookup runs for every named type before the
  cheap `same(base, "mem")` test; swap the order.
- `main.e:4529-4532`: the resolver token pool is dead (`resolve.e:210` assigns the
  module's slice); delete it.
- `parse.e:229-246`: `add_parent_since` rescans every descendant per enclosing block.
- `graph.e:656`: `find_module` is linear per import; use `lookup`.
- Type identity is `same(name)` string compares (513 sites in `check.e`;
  `is_integer_name` is 10 compares): intern builtin type names to ids once. This one
  is M; do it last and alone.

### CS-05 The server (see LF-24) is the largest per-call win for agents
A cold `context-file` on the compiler is 0.8-1.7 s; nearly all of it is load, parse
and check that a session already holds. No separate package: LF-24 delivers it.

Not proposed: another work-stealing attempt (C082 was measured slower, D1578).

---

## 6. Execution speed (XS)

The optimisation roadmap (`docs/compiler-optimizations.md`, C242-C252) stands. The
review found one missing prerequisite, two cheap wins the roadmap does not list, and
stale rows.

### XS-01 x64 array indexing uses scaled addressing - M, Opus, high
- Evidence (source): `codegen_x64.e:3782-3799` emits 8-10 instructions per index:
  copies base to r10, index to r11, length to rax (saving live rax), a
  `multiply_immediate` even for 2/4/8, `add`, restore, then a separate Load.
  `emit_x64.e` has no SIB-index encoder; a64 already uses `add_shifted`
  (`codegen_a64.e:677`).
- Do: bounds-compare index and length in the registers they occupy
  (`emit_guarded_trap` takes any pair); add `emit_x64.lea_scaled` and
  `load_memory_indexed`/`store_memory_indexed`; fuse IndexAddress with the following
  Load/Store as `field_fused` does (`:4297`); fuse FieldAddress with Store as well.
- Accept: emit sweep covers the new encodings against `disasm_x64`; count gate on the
  self-build and `benchmarks/gp`; both back ends agree on the index fixtures.

### XS-02 Spill slots are reused; short displacements - S, Sonnet, high
- Evidence (source): `regalloc.e:989-990,995-996` take a new slot per spilled value;
  `emit_x64.e:1026-1039` always emits disp32 (7 bytes, against 4); a64 slots past 256
  bytes cost two instructions (`codegen_a64.e:44-51`).
- Do: free-list slots by `last` in `allocate_with`; disp8 when `(slot+1)*8 <= 128`;
  address a64 slots from sp with scaled offsets.
- Accept: `--stats` frame bytes and `.text` size on the self-build both drop; count
  gate; HD-11's allocation verifier extended to "no two live values share a slot".

### XS-03 Promotion to values happens in NIR, before the optimisations - L, Opus, xhigh
- Evidence (source): no Phi is ever emitted (`wasm_code.e:1920`; no codegen arm).
  Mutable locals stay Load/Store until `promote_locals` inside regalloc
  (`regalloc.e:278`), so value numbering (C245), LICM (C246) and bounds-check
  elimination (C247) would see only memory traffic.
- Do: make promotion a NIR pass that runs before verification (HD-11), with phis or
  the documented multi-definition form the allocator already accepts; wasm and both
  native selectors consume it. This is the gate for C245-C247.
- Accept: byte gate is not expected to hold; instead the emit sweep, both suites and
  the count gate (no regression) on both back ends.

### XS-04 Roadmap corrections - S, Sonnet, low (docs only)
- C249's loop-depth spill weights already exist (`regalloc.e:721-773`); narrow C249
  to splitting, coalescing and rematerialisation.
- Compare-branch fusion and jump-to-next elision are done on both targets; the
  roadmap table says "unknown".
- Order after this plan: HD-02..HD-04, HD-11 -> PL-07 -> XS-01, XS-02 -> XS-03 ->
  C244 (SROA; struct copy was 16% of instructions) -> C245 -> C247 -> C246 -> C250
  -> C242/C243 (written once, on the shared selector) -> C257/C233.
- No separate no-optimisation path is needed: `--release`/`--unchecked` only drop
  checks, and inlining, promotion and allocation always run.

---

## 7. What was checked and found sound

So workers do not re-audit it: lexer UTF-8, BOM, CRLF and tab handling; parser
recovery loops all make progress; `lookup.e` probing terminates; constant folding
overflow, `i64` min / -1, shift counts; `decimal.e` rounding; extern integer returns
widened on both back ends; loads extend by type; a64 patch range checks; the x64
stack probe; artifact and executable writes staged and atomically replaced;
`apply-plan` locks, journals and recovers; the cache manifest is HMAC-checked; a
corrupt `.em` is rebuilt; writers are endian-explicit; W^X holds in ELF and PE;
Mach-O has PIE, 16K pages and a signature; no hash-order, pointer or thread
dependence was found in code generation (C267's stamp field was not located in the
files reviewed).

Not reviewed: `stats.e`, `assets.e`, `spirv.e`/`msl.e`/`glsl.e` beyond structure,
`bootstrap/neper.c`, and the 12.5k-line suite scripts beyond their shape.
