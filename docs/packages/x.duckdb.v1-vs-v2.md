# 1 vs 2: keep v1 (fix in place) against port the driver to the v2 C API

Written before the port, measured against the tree at `257a308e2`, the last committed state on v1.

**Outcome: option 2 was taken and is what the tree now implements.** The decision entry is
D5965, which records what the move forced; this document is kept as the case for it. The
measured counts below are from before the port and are not the current sizes.

## What the two options actually are

**1 — keep the v1 driver, fix what is fixable.** The driver stays on `duckdb.h` (the v1
surface). The named-parameter check is relaxed to what the library can answer, and the
fixture's bind-dependent checks are either dropped or rewritten around `db.query` text. No
parameter binding: every `db.Parameter` a caller passes is effectively unusable.

**2 — port to `duckdb_v2_*`.** The binding becomes `v2.windows.e`/`v2.linux.e` (already
written, 169 lines, 94 declarations, both variants verified identical) and the 1501-line
driver is ported onto it. Binds become one call with name and value arrays.

## Measured surface

| | count |
|---|---|
| driver lines | 1501 |
| driver functions | 94 |
| lines calling the binding | 71 |
| …of those inside helpers that carry over unchanged | 5 |
| carry-over helper lines (pure word/byte walking, text rendering) | 396 |
| binding call sites that change | 66 |
| distinct binding functions the driver calls | 38 |
| v1 capi declarations today | 80 |

The 28 carry-over helpers — `word_at`, `byte_at`, `as_pointer`, `string_bytes`, `wide_text`,
`date_text`, `time_text`, `uuid_text`, `push_two`, `saturating_mul`, `reserve`, `room`, `take`
and the rest — do not touch the binding and port unchanged. That is 396 of 1501 lines, so
roughly two thirds of the driver is in the changed set.

## Cost of 1

**Work.** Two edits: relax `bind_all` (one function), and rewrite the fixture's
parameter-dependent section. Half a turn.

**What you get.** A driver that reads, writes and queries through `db.execute`/`db.query` with
no parameters, and refuses or silently drops everything else. `db.prepare`,
`db.execute_statement`, `db.query_statement` stay unusable.

**The ceiling that does not move.** The bind bug is in the library's v1 surface, not in this
driver: `duckdb_bind_int64` passes `duckdb_bind_value` the address of a local `Value`, and
`duckdb_bind_value` reads it. No amount of driver-side care fixes that. Upstream is explicit
that v1 is deprecated in 2.0 and *probably removed entirely in 3.0, likely about a year out*.

**The trap.** Option 1 looks like a one-line fix and lands a driver whose parameter path is a
lie: `db.Parameter` exists in the API, so callers will use it, and it will fail silently. That
is worse than refusing.

## Cost of 2

**Work already done.** The v2 binding is written and verified against the real library: the
probe ran `environment_create` → `instance_create` → `instance_attach` → `connection_create`,
`parse_sql` + iterator, parameter count 2 and names `id`/`name`, `prepared_statement_execute`
with name and value arrays returning changed-rows kind 1 for the INSERT, and
`result_get_schema` reporting 2 columns with type id 13. Every call the port needs is proven,
not assumed.

**Work left.** The port. 94 functions, 66 binding call sites. Three shapes change and they are
mechanical:

1. **0 is success, 1 is not.** v1 answers a status where `0` means OK; v2 answers a
   `DUCKDB_V2_ERROR` where `0` means OK too, but every *product* moves to an out parameter.
   So `let handle = capi.prepare(...)` becomes `var handle = 0; if v2.prepare(..., &handle) != 0
   { ... }`. This is the bulk of it and it is pattern-uniform.
2. **Binds collapse.** `bind_all` and the six `bind_value` arms become two arrays built once
   per execute. That is a *deletion*, not an addition.
3. **A reader holds a value.** v2 takes no `vector_get_data` pointer arithmetic; each cell is
   `vector_get_value`, an owned handle destroyed on the next row. This deletes most of the
   remaining 396 carry-over lines too — but it also means `db.reader_next_borrowed` stops being
   special, which is a behaviour change to document.

**What you get.** Parameters work, `db.prepare` works, DuckDB splits statements (no hand-written
scanner), and the surface has a future: v1 disappears in 3.0.

**The cost I already paid.** The port is not turn-key. I wrote it once and it did not compile.
The failures were all neper-syntax, not design: no pointer dereference (so the error-slot read
`slot.*` is invalid), no inline `if` expression, `:` not `=` in struct literals, and `->` on
every two-value return. Those are knowable — they cost me the turn, not the design. A port done
as a *transformation of the working file* (keeping each helper's shape, changing only the
binding call inside it) rather than a rewrite from scratch should compile in one or two
passes. I did it as a rewrite, which is why it failed.

## The honest comparison

| | 1 | 2 |
|---|---|---|
| turns of work left | ~0.5 | 1–2 |
| driver functions touched | 1 | 94 |
| binding call sites changed | 1 | 66 |
| parameters work | no | yes |
| `db.prepare` works | no | yes |
| survives DuckDB 3.0 | no | yes |
| risk of shipping a silent failure | high | low |
| new things to document | the limitation | the kind mapping, borrow semantics |

## Recommendation

**2.** Not because it is cheaper — it is 3–4x the work — but because option 1's output is a
driver whose advertised parameter path cannot work, on a library that removes the v1 surface
entirely. The binding is already written and every call is proven by the probe; what remains is
mechanical translation of 66 call sites.

If 2 is deferred, do not ship 1 as-is: make `db.execute`/`db.query` *refuse* a non-empty
`params` slice with a clear `db.Unsupported`, so nobody loses a day to a bind that quietly
binds nothing.
