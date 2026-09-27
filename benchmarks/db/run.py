"""Run the e.db driver benchmark: the Neper programs and the C baseline, alternated, medians.

    python benchmarks/db/run.py --neper PREFIX --c BENCH_C --runs 9 --out results.json

The Neper side is one executable per driver, built from benchmarks/db/src/<driver>.e and named
PREFIX-<driver> (plus `.exe` on Windows); the C side is one executable taking the driver name.

Servers must be running (tests/selfhost/db_servers.{ps1,sh} start <dir>); the client libraries
must be on PATH (Windows) or installed (Linux). SQLite writes a file in --scratch.
"""
import argparse, json, os, platform, statistics, subprocess, sys

WORK = {
    "sqlite": {"rows": 100000, "lookups": 20000},
    "postgresql": {"rows": 20000, "lookups": 5000},
    "mysql": {"rows": 20000, "lookups": 5000},
}
PG = "host=127.0.0.1 port=55432 user=neper dbname=postgres options='-c client_min_messages=warning'"


def location(driver, scratch, label):
    if driver == "sqlite":
        path = os.path.join(scratch, f"bench-{label}.sqlite")
        for suffix in ("", "-journal"):
            if os.path.exists(path + suffix):
                os.remove(path + suffix)
        return path
    return PG if driver == "postgresql" else "53306"


def once(command, driver, scratch, label):
    work = WORK[driver]
    out = subprocess.run(command + [location(driver, scratch, label), str(work["rows"]), str(work["lookups"])],
                         capture_output=True, text=True, check=True).stdout.split()
    return {k: int(v) for k, v in (field.split("=") for field in out[1:])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--neper", required=True)
    ap.add_argument("--c", required=True)
    ap.add_argument("--runs", type=int, default=7)
    ap.add_argument("--scratch", default=".")
    ap.add_argument("--out", required=True)
    ap.add_argument("--drivers", default="sqlite,postgresql,mysql")
    args = ap.parse_args()
    results = {"host": platform.system().lower(), "runs": args.runs, "work": WORK, "drivers": {}}
    suffix = ".exe" if os.name == "nt" else ""
    for driver in args.drivers.split(","):
        neper = [f"{args.neper}-{driver}{suffix}"]
        c = [args.c, driver]
        samples = {"neper": [], "c": []}
        # One warm-up each, then alternate so drift hits both equally.
        once(neper, driver, args.scratch, "neper")
        once(c, driver, args.scratch, "c")
        for _ in range(args.runs):
            samples["neper"].append(once(neper, driver, args.scratch, "neper"))
            samples["c"].append(once(c, driver, args.scratch, "c"))
        work = WORK[driver]
        summary = {}
        for impl, runs in samples.items():
            med = {k: statistics.median(r[k] for r in runs) for k in runs[0]}
            summary[impl] = {
                "insert_rows_per_s": work["rows"] / (med["insert_ns"] / 1e9),
                "scan_rows_per_s": work["rows"] / (med["scan_ns"] / 1e9),
                "lookup_us": med["lookup_ns"] / work["lookups"] / 1e3,
                "median_ns": med,
                "samples": runs,
            }
        results["drivers"][driver] = summary
        n, c = summary["neper"], summary["c"]
        print(f"{driver:10} insert {n['insert_rows_per_s']:>11,.0f} vs {c['insert_rows_per_s']:>11,.0f} rows/s | "
              f"scan {n['scan_rows_per_s']:>12,.0f} vs {c['scan_rows_per_s']:>12,.0f} rows/s | "
              f"lookup {n['lookup_us']:7.2f} vs {c['lookup_us']:7.2f} us", flush=True)
    with open(args.out, "w") as f:
        json.dump(results, f, indent=1)


if __name__ == "__main__":
    sys.exit(main())
