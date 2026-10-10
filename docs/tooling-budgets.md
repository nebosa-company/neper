# Tooling latency budgets (T040)

Measured by `python scripts/measure_tooling_latency.py COMPILER --runs 3 --write`.
Budget is twice the worst measured run, rounded up to 50 ms, floor 100 ms: a query
above its budget on a quieter host is a regression, not noise. Host: Windows, AMD64;
compiler sha256 6ea9d1b0a326.

| query | program | min ms | median ms | max ms | output bytes | exit | budget ms |
|---|---|---|---|---|---|---|---|
| `check-file` | `tests/conformance/tools/explain.e` | 55 | 55 | 60 | 16 | 0 | 150 |
| `index` | `tests/conformance/tools/explain.e` | 88 | 89 | 93 | 33135 | 0 | 200 |
| `context-file --symbol` | `tests/conformance/tools/explain.e` | 87 | 88 | 89 | 2084 | 0 | 200 |
| `uses-file --symbol` | `tests/conformance/tools/explain.e` | 87 | 87 | 88 | 318 | 0 | 200 |
| `check-file` | `src/main.e` | 446 | 453 | 463 | 16 | 0 | 950 |
| `index` | `src/main.e` | 1290 | 1314 | 1320 | 11819362 | 0 | 2650 |
| `context-file --module` | `src/main.e` | 1563 | 1652 | 1743 | 10468 | 0 | 3500 |

Resource budgets are not frozen here: peak memory of a build is `--stats` output and
is tracked by the memory-reduction suite rows (D1660-D1671); a per-query memory
reading needs the T039 session accounting and is recorded when that lands.
