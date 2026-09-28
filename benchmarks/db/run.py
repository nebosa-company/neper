"""Run the e.db driver benchmark: Neper, the C baseline and optionally Go and Rust, alternated
within each round so drift hits every implementation equally; medians, and the winner of each
workload.

    python benchmarks/db/run.py --neper PREFIX --c BENCH_C [--go BENCH_GO] [--rust BENCH_RUST]
                                --runs 9 --out results.json

The Neper side is one executable per driver, built from benchmarks/db/src/<driver>.e and named
PREFIX-<driver> (plus `.exe` on Windows); C (c/bench.c), Go (go/) and Rust (rust/) are each one
executable taking the driver name first.

Servers must be running (tests/selfhost/db_servers.{ps1,sh} start <dir>); the client libraries
must be on PATH (Windows) or installed (Linux). SQLite writes a file in --scratch. ODBC reaches
the PostgreSQL server through psqlODBC: by the DSN `neper_psqlodbc` on Windows, whose driver
manager wants one (run-windows-all.ps1 registers it), and by the driver's path on Linux.

SQL Server (`--tds PORTS`, the file tests/selfhost/sqlserver.{ps1,sh} start writes) is reached
over TDS 8.0 strict by Neper (x.microsoft.tds) and Go (go-mssqldb), by C through Microsoft's
ODBC Driver 18 with Encrypt=Strict, and by Rust through tiberius, which has no strict mode and
negotiates TLS inside PRELOGIN. Every one of them checks the server's certificate against the
same pinned one. C runs its `odbc` path; the others take `host;port;der;pem;user;password`.
"""
import argparse, base64, json, os, platform, statistics, subprocess, sys

WORK = {
    "sqlite": {"rows": 100000, "lookups": 20000},
    "postgresql": {"rows": 20000, "lookups": 5000},
    "mysql": {"rows": 20000, "lookups": 5000},
    "odbc": {"rows": 20000, "lookups": 5000},
    "sqlserver": {"rows": 20000, "lookups": 5000},
}
PORTS = {"postgresql": 55432, "mysql": 53306}
ODBC_LINUX_DRIVER = "/usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so"
TDS = {}


def read_tds(ports, scratch):
    """The SQL Server connection from a ports file, with the certificate also written as PEM."""
    for line in open(ports):
        key, _, value = line.strip().partition("=")
        if key.startswith("tds_"):
            TDS[key[4:]] = value
    der = open(TDS["root"], "rb").read()
    if der.startswith(b"-----BEGIN"):
        sys.exit("--tds: tds_root must be a DER certificate")
    TDS["pem"] = os.path.join(scratch, "sqlserver.pem")
    with open(TDS["pem"], "w") as f:
        body = base64.b64encode(der).decode()
        f.write("-----BEGIN CERTIFICATE-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END CERTIFICATE-----\n")


def location(driver, scratch, label):
    if driver == "sqlserver":
        if label == "c":
            name = "{ODBC Driver 18 for SQL Server}"
            return (f"Driver={name};Server=tcp:127.0.0.1,{TDS['port']};Encrypt=Strict;ServerCertificate={TDS['pem']};"
                    f"UID={TDS['user']};PWD={{{TDS['password']}}};Database=neper")
        return ";".join(["localhost", TDS["port"], TDS["root"], TDS["pem"], TDS["user"], TDS["password"]])
    if driver == "sqlite":
        path = os.path.join(scratch, f"bench-{label}.sqlite")
        for suffix in ("", "-journal"):
            if os.path.exists(path + suffix):
                os.remove(path + suffix)
        return path
    if driver == "postgresql":
        return f"host=127.0.0.1 port={PORTS['postgresql']} user=neper dbname=postgres options='-c client_min_messages=warning'"
    if driver == "odbc":
        via = "DSN=neper_psqlodbc" if os.name == "nt" else f"Driver={ODBC_LINUX_DRIVER}"
        return f"{via};Server=127.0.0.1;Port={PORTS['postgresql']};Uid=neper;Database=postgres;BoolsAsChar=0"
    return str(PORTS["mysql"])


def once(command, driver, scratch, label):
    work = WORK[driver]
    p = subprocess.run(command + [location(driver, scratch, label), str(work["rows"]), str(work["lookups"])],
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"{label} {driver} failed (exit {p.returncode}): {p.stderr.strip()[:500]}")
    out = p.stdout.split()
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
    ap.add_argument("--drivers", default="sqlite,postgresql,mysql,odbc")
    ap.add_argument("--pg-port", type=int, default=PORTS["postgresql"])
    ap.add_argument("--mysql-port", type=int, default=PORTS["mysql"])
    ap.add_argument("--tds", help="the ports file tests/selfhost/sqlserver.{ps1,sh} start wrote")
    args = ap.parse_args()
    PORTS["postgresql"], PORTS["mysql"] = args.pg_port, args.mysql_port
    if args.tds:
        read_tds(args.tds, args.scratch)
    results = {"host": platform.system().lower(), "runs": args.runs, "work": WORK, "drivers": {}}
    suffix = ".exe" if os.name == "nt" else ""
    for driver in args.drivers.split(","):
        commands = {"neper": [f"{args.neper}-{driver}{suffix}"], "c": [args.c, "odbc" if driver == "sqlserver" else driver]}
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
