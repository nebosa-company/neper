# Closing the e.db performance gap

The four-way benchmark (D1597, `docs/blog/e-db-three-drivers.html`) scores each
implementation as the geometric mean of its percentage of the fastest, over 18 cells
(3 drivers × 3 workloads × 2 hosts): **C 86%, Rust 80%, Neper 69%, Go 59%**. Neper's
inserts and lookups are close to C; its scans run at 51–66% of the fastest on every
driver and host. This document says where that time goes, what to change, in what
order, and which model and effort each piece needs.

## What was measured

SQLite scan of 100,000 rows `(id BIGINT, name VARCHAR(32), score DOUBLE)` on Windows,
medians of interleaved runs on a loaded machine (ratios are reliable, absolute
times are not). Each variant is a temporary edit of `lib/x/sqlite/sqlite.e` built in a
worktree; none is committed.

| Variant | Scan | Change |
|---|---|---|
| Driver as shipped | 29 ms | — |
| Borrow SQLite's text bytes instead of copying them | 25 ms | −15% |
| … and skip the three `column_type` calls per row | 20 ms | −19% more |
| … and make one library call per row | 15 ms | equals C |
| C (`benchmarks/db/c/bench.c`) | 14.4 ms | |

Two independent readings give the same number: **a call into a C library costs Neper
about 15 ns more than it costs C** (4.7 ms over 300,000 calls, both times). A scan
makes 5–11 such calls per row, so scans show it; inserts and lookups spend their time
inside the database. `db.Value` stores, the `Driver` table dispatch and the workload's
own loop are not the cost: with one call per row Neper matches C with all of them
still in place.

### Why a call costs 15 ns

`src/codegen_x64.e`, the call case at about line 3270, and `load_call_arguments` at
about line 1358:

1. Every argument is written to an outgoing stack slot, then read back into the
   register the convention names for it.
2. Every live value in a caller-saved register is stored before the call and reloaded
   after it (`save_live_registers` / `restore_live_registers`). The allocator
   (`src/regalloc.e`, `allocate_with`) hands out registers lowest-first, and registers
   0–4 are the caller-saved ones, so a value that lives across a call almost always
   sits in one and is spilled at every call it crosses. Registers 5–9 are callee-saved
   and are only reached once 0–4 are busy.
3. The result goes r10 → destination register → its stack slot (`store_result`).
4. Every imported call is made as if variadic: a float argument is copied into its
   integer register too (Win64), or `al` is set (System V).

That is roughly ten memory operations per call that C does not do. Item 4 is cheap
and correct; items 1–3 are the cost.

## The work

### 1. Call-aware register allocation and direct argument passing (compiler)

**Done as D1607 (with D1608), short of its acceptance.** The Windows SQLite scan is
3.3% faster against the D1606 compiler in the same rounds, not the 28% estimated, and
reaches 56–59% of C rather than 70%. Images are 7–16% smaller. The proposal is kept
below for the record.

The one change that helps everything: every call in every Neper program, the three
drivers, inserts and lookups as well as scans, and the compiler's own build time.

- `src/regalloc.e`, `build_ranges` / `allocate_with`: record for each live range whether
  it crosses a call instruction. When choosing a register, prefer 5–9 (callee-saved)
  for a range that crosses a call and 0–4 for one that does not; fall back to the other
  group when the preferred one is full. The existing spill logic stays as it is.
  `callee_saved_count` in `codegen_x64.e` already sizes the prologue from the highest
  callee-saved register in use, so the frame follows.
- `src/codegen_x64.e`, the call case: when an argument's value is already in a register
  and no earlier argument's move clobbers it, move it straight to the parameter
  register; keep the outgoing-slot path for stack arguments and for the cases the
  ordering cannot resolve. `load_call_arguments` becomes the fallback rather than the
  rule.
- Leave the variadic double-copy alone; it is one instruction per float argument.

Acceptance: both suites pass on both hosts, including the stage 2 = stage 3 fixed
point (the compiler's own code changes, so the `.em` byte-equality checks are
expected to move and be re-baselined, as D1593 did); `benchmarks/db/run.py` on both
hosts with the SQLite scan at ≥ 70% of C (from 52%), no cell slower than before;
`tests/selfhost/fixtures/link/` gains one fixture whose function keeps six values
live across a call and checks them after, so the callee-saved path is exercised on
its own. Record as a D-row.

Expected: SQLite scan 52% → about 72% of C; a smaller gain on every other cell and
on compile times.

**Model and effort: Opus 5.5 at high effort** (Fable 5.1 at max if the first attempt
regresses the fixed point). This is the back end of a self-hosting compiler: the change
is small in lines but every mistake shows up as a miscompiled compiler two stages
later, and the diagnosis needs the disassembler and both hosts. 2–4 days including
suites.

### 2. Borrowed rows (driver contract)

**Done as D1599, differently from what follows.** Shortening `reader_next_err`'s lifetime
would have left the drivers' own `scalar` helpers, which return a value after closing
the reader, pointing at freed memory. So borrowing is a second call,
`db.reader_next_borrowed`, with its own `db.Driver` entry. Measured −10% on the Windows
SQLite scan. The original proposal is kept below for the record.

`lib/e/db.e`: a `Text` or `Bytes` value a reader fills is valid until the next
`reader_next_err` or `close_rows` on that reader; a caller that keeps one copies it.
Every C API already has exactly that lifetime (`sqlite3_column_text` until the next
step, libpq until the result is cleared, MySQL until the next fetch), so the drivers
stop copying:

- `lib/x/sqlite/sqlite.e`: `column_copy` becomes a view over the library's pointer;
  `reserve` and the reader buffer go for text and blob.
- `lib/x/postgresql/libpq.e`: `decode` returns the view for text-like OIDs and `bytea`;
  the `take` + `mem.copy` stays only for values it rewrites (`jsonb` strips a version
  byte, so that one still copies, or returns `v[1..]` as a view).
- `lib/x/oracle/mysql.e`: the same for the row's text.
- The three fixtures under `tests/selfhost/fixtures/link/` that read text keep working
  because none of them holds a value across `next`; add one check that reads a row,
  advances, and copies before use, to document the contract.
- `docs/packages/` and the blog's driver-writing section say so in one sentence each.

Expected: −15% on scans, all drivers.

**Model and effort: Sonnet 5 at medium effort.** Mechanical across three files with a
clear rule; the only judgement is which libpq decodes rewrite bytes. Half a day with
both-host fixtures.

### 3. Fewer calls per row (drivers)

**libpq done as D1606; SQLite not done.** libpq readers take 256 rows per result where
libpq has chunked mode (looked up at run time, since WSL's libpq 16 lacks it). The Windows
PostgreSQL scan went from 7.9 ms to 4.2 ms, against C's 4.5 ms. The SQLite `STRICT`-table
shortcut is left out: nothing in the tree or benchmark uses a strict table, and knowing one
is strict costs a schema query per statement. The original proposal is kept below.

- SQLite: `column_type` is needed because a column can hold any storage class. Ask it
  only when the declared kind is `Null` (unknown) or the table is not `STRICT`; a
  `STRICT` table (SQLite ≥ 3.37) guarantees the declared type, so the driver can trust
  `columns[i].kind` there. Reading `STRICT` needs one `PRAGMA table_list` or a look at
  `sqlite_schema` per statement, cached on the `Stmt`. For a non-strict table nothing
  changes. −19% on this benchmark's scan once the table is declared `STRICT`; the
  benchmark's own `CREATE TABLE` in `benchmarks/db/src/workload.e` should not change
  (it is shared with C, Go and Rust), so this item's gain shows on strict tables only.
- libpq: single-row mode is one `PQgetResult` per row plus `PQresultStatus`,
  `PQgetisnull`, `PQgetlength`, `PQgetvalue` per column and `PQclear`, about 11 calls
  per row against C's 4. Use `PQsetChunkedRowsMode` (libpq 17) to fetch chunks of, say,
  256 rows into one result, and drop `PQgetisnull` in favour of `PQgetlength` = −1 …
  or, with a pre-17 libpq, keep single-row mode. Check the installed version in
  `D:\tools\postgresql` first.
- MySQL: `mysql_fetch_row` + `mysql_fetch_lengths` per row is already two calls; the
  rest is text parsing. Nothing to do here beyond item 2 and the float parser (D1593).

Expected: SQLite strict scans −19%; PostgreSQL scans −20–30%.

**Model and effort: Sonnet 5 at high effort** for libpq chunked mode (a new libpq
entry point, a result that outlives several `next` calls, and end-of-chunk handling),
**Sonnet 5 at medium** for the SQLite strict-table check. About a day each.

### 4. Word-wide `mem.copy` (library)

**Done as D1600, in `e.bytes` rather than `e.mem`.** `e.mem` cannot call its own
intrinsics (`size_of`, `cast`, `address_of` resolve only through an import alias of
`e.mem`, and a module cannot import itself), so a generic `mem.copy[T]` cannot choose a
word loop for one-byte `T`. `bytes.copy(dst, src)` is the word-wide copy: 1 KB copied
200,000 times took 46 ms instead of 336 ms. The three drivers' copying readers use it.
The original proposal is kept below for the record.

`lib/e/mem.e` `copy[T]` and the drivers' `copy_foreign` are bounds-checked byte loops.
Not the cost for this benchmark's 4–8-byte names, and item 2 removes the copies from
the scan path, but any caller copying real text or blob columns pays it. Copy `u8`
slices eight bytes at a time through `u64` views with a byte tail; keep the generic
loop for other `T`. Not measured; do it last and measure it with a 1 KB-column
variant of the benchmark.

**Model and effort: Haiku 4.5 at medium effort.** A contained change with an obvious
check. Two hours.

## Order

1 first: it is the largest gain and the only one that helps outside the drivers. 2 in
parallel by another session, since it touches only `lib/x` and `lib/e/db.e`. 3 after 2
(it reworks the same `fill` functions). 4 whenever.

## Constraints

- Shared working tree: commit with explicit pathspecs; check `docs/decisions.md` for
  peers' uncommitted rows before appending. D1599–D1609 and D1640+ are free at the
  time of writing (D1610–D1639 are reserved by the SPIR-V session).
- Never edit `src/` while a suite runs.
- Build a private compiler from a worktree: `build/windows/neper.exe build <wt>/src/main.e --arena 4g --output <wt>/neper-bench.exe`
  (1g ran out of memory under load). It is `neper-self`: there is no `build`
  subcommand (it stack-overflows instead of printing usage; worth a one-line fix), so
  build programs with
  `neper-bench.exe emit-executable benchmarks/db/src/sqlite.e <wt> x64 windows OUT.exe --release`.
- Benchmark on both hosts with `benchmarks/db/run.py` (Windows, ports from
  `build/db/ports`) and `benchmarks/db/run-linux-all.sh`; interleaved rounds, compare
  ratios, and say in the D-row when the machine was loaded.
- Update the blog's tables and `docs/index.html` card only from a full run of both
  hosts, and copy the JSON into `benchmarks/db/results/`.
