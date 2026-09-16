# -*- coding: utf-8 -*-
"""Check a build stream's `stats` record (D476).

Usage:  python scripts/check_stats_record.py STREAM.jsonl

Exactly one `stats` record, before the `result`, flat (every value a scalar),
carrying the keys every build has and at least one phase; with `--stats-full`
the pool keys come in capacity/used pairs.  Exit 0 when so, 1 otherwise.
"""
import json, sys

REQUIRED = ["files", "loc", "functions", "function_instances", "compile_mode",
            "target_arch", "target_os", "executable_size_bytes", "wall_time_ms",
            "execution_time_ms", "executable_peak_working_set_mb", "exit_code"]

def main(path):
    records = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
    kinds = [r.get("record") for r in records]
    if kinds.count("stats") != 1:
        return "expected one stats record, found %d" % kinds.count("stats")
    if kinds.index("stats") > kinds.index("result"):
        return "the stats record comes after the result"
    stats = records[kinds.index("stats")]
    for key, value in stats.items():
        if isinstance(value, (dict, list)):
            return "key %r is not a scalar" % key
    missing = [k for k in REQUIRED if k not in stats]
    if missing:
        return "missing keys: %s" % ", ".join(missing)
    if not any(k.startswith("phase_") and k.endswith("_ms") for k in stats):
        return "no phase_<name>_ms key"
    pools = [k for k in stats if k.startswith("pool_")]
    for k in pools:
        if k.endswith("_capacity") and k[:-9] + "_used" not in stats:
            return "pool %r has no _used key" % k
    return None

if __name__ == "__main__":
    problem = main(sys.argv[1])
    if problem:
        print("check_stats_record: " + problem)
        sys.exit(1)
    print("stats record ok")
