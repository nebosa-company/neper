# -*- coding: utf-8 -*-
"""Measure the compiler's agent-facing tool latency and freeze budgets from it (T040).

Usage:  python scripts/measure_tooling_latency.py COMPILER [--runs N] [--write]

T2.1 asks for latency, startup and resource budgets to be frozen before the
understand-and-check work is implemented. This times each query over two programs --
a small one (the conformance explain.e) and the compiler's own source, the largest
program in the repository -- N runs each, and reports min/median/max wall time and
the output size. With --write it records the reading and a proposed budget
(2x the worst run, rounded up to the next 50 ms, floor 100 ms) in
docs/tooling-budgets.md, with the host and compiler identity so a later reading is
comparable. Budgets are frozen by committing that file; a regression is a later run
above its row. Memory is not sampled here: `--stats` carries it for builds.
"""
import hashlib
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SMALL = "tests/conformance/tools/explain.e"
LARGE = "src/main.e"
QUERIES = [
    ("check-file", SMALL, [], "check-file"),
    ("index", SMALL, ["--json"], "index"),
    ("context-file --symbol", SMALL, ["--json", "--symbol", "explain.main", "--budget", "8"], "context-file"),
    ("uses-file --symbol", SMALL, ["--json", "--symbol", "explain.main"], "uses-file"),
    ("check-file", LARGE, [], "check-file"),
    ("index", LARGE, ["--json"], "index"),
    ("context-file --module", LARGE, ["--json", "--module", "main", "--budget", "40"], "context-file"),
]


def time_run(compiler, command, program, extra, runs):
    args = [compiler, command, str(ROOT / program), str(ROOT), "x64", "windows" if os.name == "nt" else "linux", *extra]
    times, size, status = [], 0, 0
    for _ in range(runs):
        started = time.perf_counter()
        done = subprocess.run(args, capture_output=True, cwd=ROOT)
        times.append((time.perf_counter() - started) * 1000)
        size = len(done.stdout)
        status = done.returncode
    return times, size, status


def budget_ms(worst):
    return max(100, int(-(-(worst * 2) // 50) * 50))


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    compiler = argv[0]
    runs = int(argv[argv.index("--runs") + 1]) if "--runs" in argv else 5
    rows = []
    for label, program, extra, command in QUERIES:
        times, size, status = time_run(compiler, command, program, extra, runs)
        rows.append((label, program, min(times), statistics.median(times), max(times), size, status))
    lines = ["| query | program | min ms | median ms | max ms | output bytes | exit | budget ms |", "|---|---|---|---|---|---|---|---|"]
    for label, program, lo, mid, hi, size, status in rows:
        lines.append("| `%s` | `%s` | %.0f | %.0f | %.0f | %d | %d | %d |" % (label, program, lo, mid, hi, size, status, budget_ms(hi)))
    table = "\n".join(lines)
    print(table)
    if "--write" in argv:
        digest = hashlib.sha256(Path(compiler).read_bytes()).hexdigest()[:12]
        body = """# Tooling latency budgets (T040)

Measured by `python scripts/measure_tooling_latency.py COMPILER --runs %d --write`.
Budget is twice the worst measured run, rounded up to 50 ms, floor 100 ms: a query
above its budget on a quieter host is a regression, not noise. Host: %s, %s;
compiler sha256 %s.

%s

Resource budgets are not frozen here: peak memory of a build is `--stats` output and
is tracked by the memory-reduction suite rows (D1660-D1671); a per-query memory
reading needs the T039 session accounting and is recorded when that lands.
""" % (runs, platform.system(), platform.machine(), digest, table)
        (ROOT / "docs" / "tooling-budgets.md").write_text(body, encoding="utf-8", newline="\n")
        print("wrote docs/tooling-budgets.md")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
