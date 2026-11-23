#!/usr/bin/env python3
"""Run the goldens whose per-case cost is minutes, in bounded chunks.

A whole golden can cost hours: `fieldssp` is 547 cases at 21.7 s each, about 3.3 h (D7822), and a
dozen `ghyp*`/`mirt`/`rugarch` goldens are in the same class (D7821). The suite cannot run those as
one process, so each of their fixtures accepts a case range - `<first> <count>` (D7823) - and this
runner walks a golden in fixed chunks, each chunk its own process with its own timeout. A chunk
fails if any case in it fails; the exit status is 0 only when every chunk of every selected fixture
passed.

    scripts/run-sliced-fixtures.py                      # every sliced fixture, host target
    scripts/run-sliced-fixtures.py ghyp2 ghypfit        # by golden name (the part after oracle_)
    scripts/run-sliced-fixtures.py fieldssp --chunk 25 --timeout 900
    scripts/run-sliced-fixtures.py ghyp2 --from 1300    # the expensive block only

Why a Python runner and not a shell one: it needs to work on both hosts unattended, and the repo's
other cross-host tooling (scripts/*.py) is Python. It builds with the same compiler the suite uses -
`build/windows/neper-rel.exe` on Windows, `build/linux/neper-try` on Linux - and removes the
executable it built unless --keep is given.
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fixtures whose goldens accept a case range. Keep this in step with the fixtures that call
# oracle.slice; a name here that does not is harmless but misleading, so the runner checks.
SLICED = (
    "fieldssp",
    "ghypcdf",
    "ghypfit",
    "ghyphess",
    "ghyphess2",
    "ghyp2",
    "ghypnfit",
    "ghypnfit2",
    "lavaan_cfa",
    "mgcv_reml2",
    "mirt",
    "ordinal3",
    "phangorn",
    "rugarch",
    "emmeanscontr",
)


def compiler_and_target():
    if os.name == "nt":
        return os.path.join(ROOT, "build", "windows", "neper-rel.exe"), "x64", "windows"
    return os.path.join(ROOT, "build", "linux", "neper-try"), "x64", "linux"


def case_count(golden_path):
    with open(golden_path, encoding="utf-8") as handle:
        return len(json.load(handle)["cases"])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("fixtures", nargs="*", help="golden names to run (default: every sliced fixture)")
    parser.add_argument("--chunk", type=int, default=4, help="cases per chunk (default 4: the worst goldens cost about 120 s a case, so ten cases exceed a 20 minute budget - measured on ghypnfit2, D7825)")
    parser.add_argument("--timeout", type=int, default=1200, help="seconds per chunk (default 1200)")
    parser.add_argument("--from", dest="first", type=int, default=0, help="first case index (default 0)")
    parser.add_argument("--to", dest="last", type=int, default=0, help="stop before this case index (default: the end of the golden)")
    parser.add_argument("--log", default="", help="TSV of finished chunks; with it, chunks already passed are skipped (a resumed sweep)")
    parser.add_argument("--keep", action="store_true", help="keep the built executable")
    args = parser.parse_args()

    compiler, arch, target_os = compiler_and_target()
    if not os.path.exists(compiler):
        print("no compiler at %s: build it first (scripts/build-bootstrap.sh on Linux)" % compiler, file=sys.stderr)
        return 2

    chosen = args.fixtures or list(SLICED)
    unknown = [name for name in chosen if name not in SLICED]
    if unknown:
        print("not a sliced fixture: %s (known: %s)" % (", ".join(unknown), ", ".join(SLICED)), file=sys.stderr)
        return 2

    env = dict(os.environ)
    env.setdefault("TEMP", os.path.join(ROOT, "build"))
    env.setdefault("TMP", env["TEMP"])

    # A sweep over every golden is hours of compute, so a --log makes it resumable: each finished
    # chunk is one TSV line, and a line with status 0 means that chunk is not run again.
    passed = set()
    log_handle = None
    if args.log:
        if os.path.exists(args.log):
            with open(args.log, encoding="utf-8") as handle:
                for line in handle:
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) >= 4 and parts[3] == "0":
                        passed.add((parts[0], parts[1]))
        log_handle = open(args.log, "a", encoding="utf-8")

    failures = []
    for name in chosen:
        fixture = "oracle_" + name
        source = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", fixture, "src", "main.e")
        golden = os.path.join(ROOT, "tests", "oracle", name + ".json")
        if not os.path.exists(source) or not os.path.exists(golden):
            print("%-16s SKIP (no fixture or golden)" % name, flush=True)
            continue
        with open(source, encoding="utf-8") as handle:
            if "oracle.slice(" not in handle.read():
                print("%-16s SKIP (its main does not call oracle.slice)" % name, flush=True)
                continue
        exe = os.path.join(ROOT, "build", "check-%s-%d" % (fixture, os.getpid()) + (".exe" if os.name == "nt" else ""))
        built = subprocess.run(
            [compiler, "emit-executable", source, ROOT, arch, target_os, exe],
            cwd=ROOT, capture_output=True, text=True, env=env)
        if built.returncode != 0 or "executable written" not in built.stdout:
            print("%-16s EMIT-FAIL %s" % (name, (built.stdout + built.stderr).strip().splitlines()[:1]), flush=True)
            failures.append(name)
            continue
        total = case_count(golden)
        if args.last and args.last < total:
            total = args.last
        start = args.first
        chunk_failures = 0
        began = time.time()
        while start < total:
            count = min(args.chunk, total - start)
            if log_handle is not None and (name, str(start)) in passed:
                start += count
                continue
            started = time.time()
            try:
                ran = subprocess.run([exe, str(start), str(count)], cwd=ROOT, capture_output=True,
                                     text=True, timeout=args.timeout, env=env)
                status = ran.returncode
                detail = "" if status == 0 else (ran.stdout.strip().splitlines()[:1] or [""])[0][:150]
            except subprocess.TimeoutExpired:
                status = "TIMEOUT"
                detail = ""
            if log_handle is not None:
                log_handle.write("%s\t%d\t%d\t%s\n" % (name, start, count, status))
                log_handle.flush()
            print("%-16s [%4d..%4d) %-7s %6.1fs %s" % (name, start, start + count, status,
                                                       time.time() - started, detail), flush=True)
            if status != 0:
                chunk_failures += 1
            start += count
        elapsed = time.time() - began
        if chunk_failures:
            failures.append(name)
            print("%-16s FAILED %d chunk(s) in %.0fs" % (name, chunk_failures, elapsed), flush=True)
        else:
            print("%-16s passed %d cases in %.0fs" % (name, total - args.first, elapsed), flush=True)
        if not args.keep and os.path.exists(exe):
            try:
                os.remove(exe)
            except OSError:
                pass

    if failures:
        print("sliced fixtures failing: %s" % ", ".join(failures), file=sys.stderr)
        return 1
    print("all selected sliced fixtures passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
