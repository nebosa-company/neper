# test262 run times

How long the JavaScript conformance runs take (what the runs are: `tests/browser/js/README.md`). Plan around these when starting
a sweep in the background. Counts of passing tests are in the tracker, not here.

## Measured

| Run | Tests | Wall time | How |
|---|---|---|---|
| Core: `language`, `built-ins`, `annexB`, `staging` | 50,253 listed (50,142 run) | 74 min (2026-10-31 to 11-01, third run) | chunks of 100, 5 chunks in parallel, 16 logical cores, nothing else heavy running; the Date dst-offset-caching tests dominate the tail |
| Temporal sweep: `intl402/Temporal`, `built-ins/Temporal/Duration`, `built-ins/Temporal/ZonedDateTime` | 3470 | 15 min (2026-10-31, 18:27 to 18:42) | chunks of 100, 3 chunks in parallel, 16 logical cores, nothing else heavy running |

## Observed while developing (not timed)

These are rough, taken from runs that shared the machine with builds and other sweeps, so they run high. The core run once took 1.5 to 2 hours that way.

| Run | Tests | Roughly |
|---|---|---|
| `intl402` | about 3,400 | 20 to 40 minutes |
| `built-ins/RegExp/property-escapes` | 613 | up to an hour: every chunk hits the 240 s limit and reruns test by test |
| Module suite: `language/module-code`, `import`, `export` | 733 | a few minutes |

The `staging/sm/Date/dst-offset-caching-*-of-8` tests take about 30 s each alone (step limit 4 billion) and time out when the machine is loaded with a six-way parallel run; rerun them alone. A third core run (2026-10-31, about 55 min with other builds running) lost two chunks to that.

A typical single test takes milliseconds. The cost is in a few heavy tests: the `intl402/DateTimeFormat` calendar sweeps take
one to two minutes each, and a crashing or hanging test costs its timeout (60 s alone, 240 s per chunk) before it is recorded.

## Update this

When you time a run, replace its row in "Measured" with the date, the wall time and the parallelism. Do not keep both an
observed and a measured figure for the same run.
