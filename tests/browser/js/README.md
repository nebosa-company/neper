# JavaScript conformance: test262

The JavaScript interpreter in `lib/e/js` is measured against [test262](https://github.com/tc39/test262), the official
ECMAScript conformance suite kept by TC39. It covers the language (`test/language`), the built-ins (`test/built-ins`,
including Temporal and Atomics) and the Intl specification, ECMA-402 (`test/intl402`). A test passes when its script finishes
without an uncaught exception, or, for a `negative` test, throws the expected error. The pass counts and what is still open
live in the tracker (`docs/browser-progress.html`, row 5.14), not here; how long the runs take is in `docs/test262-runtimes.md`.

## Files

- `t262.e` runs the suite: `t262 TEST262_DIR LIST [--show] [--floor N] [--strict]`. `LIST` names test files, one path per line,
  relative to `TEST262_DIR`. Each test gets a fresh realm with the harness files from its `includes:` metadata. Tests that need a
  host feature the interpreter does not provide are counted as skipped (the list is `skipped_feature` in `t262.e`).
- `parse_run.e` and `parse.sh` check only that the parser accepts and rejects the right programs (tracker 5.2).
- `own/` holds tests of ours in test262 format for behaviour test262 does not cover. Copy one under `TEST262_DIR/test` to run it.

## Running

test262 is not vendored. Clone it, build the runner, and give it a list:

```
git clone --depth 1 https://github.com/tc39/test262.git /d/Temp/test262
build/windows/neper-try.exe emit-executable tests/browser/js/t262.e . x64 windows build/windows/js-t262.exe --arena 2g
(cd /d/Temp/test262 && find test/built-ins/RegExp -name '*.js' -not -name '*_FIXTURE*' > /d/Temp/regexp.list)
(cd /d/Temp/test262 && /d/repos/neper/build/windows/js-t262.exe D:/Temp/test262 /d/Temp/regexp.list --show)
```

`--show` prints each failing test and a final `test262 N pass P skip S` line. Run a large list in chunks of about a hundred
tests, each under a timeout: a test that crashes or hangs takes its whole process with it.

## Limits worth knowing

- There is no garbage collector, so one process allocates from a single arena (`--arena`); a test that builds a lot of garbage
  can exhaust it. The calendar sweeps in `intl402/DateTimeFormat` need more than `2g`.
- The step limit per test is 40 million interpreter steps, 400 million for `intl402`.
- Generator and async tests run on threads, so a loaded machine can fail a test with "cannot start generator thread" that
  passes when run alone.
