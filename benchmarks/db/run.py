"""Run the e.db driver benchmark: Neper, the C baseline and optionally Go and Rust, alternated
within each round so drift hits every implementation equally; medians, and the winner of each
workload.

    python benchmarks/db/run.py --neper PREFIX --c BENCH_C [--go BENCH_GO] [--rust BENCH_RUST]
                                --runs 9 --out results.json

The Neper side is one executable per driver, built from benchmarks/db/src/<driver>.e and named
PREFIX-<driver> (plus `.exe` on Windows); C (c/bench.c), Go (go/) and Rust (rust/) are each one
executable taking the driver name first.

Servers must be running (tests/selfhost/db_servers.{ps1,sh} start <dir>); the client libraries
must be on PATH (Windows) or installed (Linux). SQLite writes a file in --scratch.
"""
import argparse, json, os, platform, statistics, subprocess, sys

WORK = {
    "sqlite": {"rows": 100000, "lookups": 20000},
    "postgresql": {"rows": 20000, "lookups": 5000},
    "mysql": {"rows": 20000, "lookups": 5000},
}
PORTS = {"postgresql": 55432, "mysql": 53306}


def location(driver, scratch, label):
    if driver == "sqlite":
        path = os.path.join(scratch, f"bench-{label}.sqlite")
        for suffix in ("", "-journal"):
            if os.path.exists(path + suffix):
                os.remove(path + suffix)
        return path
    if driver == "postgresql":
        return f"host=127.0.0.1 port={PORTS['postgresql']} user=neper dbname=postgres options='-c client_min_messages=warning'"
    return str(PORTS["mysql"])


def once(command, driver, scratch, label):
    work = WORK[driver]
    out = subprocess.run(command + [location(driver, scratch, label), str(work["rows"]), str(work["lookups"])],
                         capture_output=True, text=True, check=True).stdout.split()
    return {k: int(v) for k, v in (field.split("=") for field in out[1:])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--neper", required=True)
    ap.add_argument("--c", required=True)
    ap.add_argument("--go")
    ap.add_argument("--rust")
    ap.add_argument("--runs", type=int, default=7)
    ap.add_argument("--scratch", default=".")
    ap.add_argument("--out", required=True)
    ap.add_argument("--drivers", default="sqlite,postgresql,mysql")
    ap.add_argument("--pg-port", type=int, default=PORTS["postgresql"])
    ap.add_argument("--mysql-port", type=int, default=PORTS["mysql"])
    args = ap.parse_args()
    PORTS["postgresql"], PORTS["mysql"] = args.pg_port, args.mysql_port
    results = {"host": platform.system().lower(), "runs": args.runs, "work": WORK, "drivers": {}}
    suffix = ".exe" if os.name == "nt" else ""
    for driver in args.drivers.split(","):
        commands = {"neper": [f"{args.neper}-{driver}{suffix}"], "c": [args.c, driver]}
        if args.go:
            commands["go"] = [args.go, driver]
        if args.rust:
            commands["rust"] = [args.rust, driver]
        samples = {impl: [] for impl in commands}
        # One warm-up each, then every implementation once per round.
        for impl, command in commands.items():
            once(command, driver, args.scratch, impl)
        for _ in range(args.runs):
            for impl, command in commands.items():
                samples[impl].append(once(command, driver, args.scratch, impl))
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
        winners = {
            "insert": max(summary, key=lambda i: summary[i]["insert_rows_per_s"]),
            "scan": max(summary, key=lambda i: summary[i]["scan_rows_per_s"]),
            "lookup": min(summary, key=lambda i: summary[i]["lookup_us"]),
        }
        results.setdefault("winners", {})[driver] = winners
        print(f"{driver}:", flush=True)
        for impl, s in summary.items():
            print(f"  {impl:6} insert {s['insert_rows_per_s']:>11,.0f} rows/s | scan {s['scan_rows_per_s']:>12,.0f} rows/s | "
                  f"lookup {s['lookup_us']:7.2f} us", flush=True)
        print(f"  winners: insert {winners['insert']}, scan {winners['scan']}, lookup {winners['lookup']}", flush=True)
    with open(args.out, "w") as f:
        json.dump(results, f, indent=1)


if __name__ == "__main__":
    sys.exit(main())
