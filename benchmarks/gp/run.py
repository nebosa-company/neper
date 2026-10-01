"""Measure GP-09 and GP-10 across Neper, C, C++, Rust and Go.

Builds and runs are alternated by round. The JSON records every sample, p50/p95,
one peak-RSS run, image size, commands, compiler versions and output oracle.
"""
import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import time


def distribution(values):
    ordered = sorted(values)
    def percentile(q):
        at = (len(ordered) - 1) * q
        low = int(at)
        high = min(low + 1, len(ordered) - 1)
        return ordered[low] + (ordered[high] - ordered[low]) * (at - low)
    return {
        "p50": round(statistics.median(ordered), 3),
        "p95": round(percentile(0.95), 3),
        "min": round(ordered[0], 3),
        "max": round(ordered[-1], 3),
        "samples": [round(value, 3) for value in values],
    }


def timed(command):
    start = time.perf_counter()
    done = subprocess.run(command, capture_output=True, text=True, errors="replace")
    elapsed = (time.perf_counter() - start) * 1000.0
    if done.returncode:
        raise SystemExit(f"failed ({done.returncode}): {' '.join(command)}\n{done.stderr[-1000:]}")
    return elapsed, done.stdout.strip()


def peak_rss(command, scratch):
    output = os.path.join(scratch, "time-rss.txt")
    done = subprocess.run(["/usr/bin/time", "-f", "%M", "-o", output] + command,
                          capture_output=True, text=True, errors="replace")
    if done.returncode:
        raise SystemExit(f"memory run failed ({done.returncode}): {' '.join(command)}\n{done.stderr[-1000:]}")
    with open(output, encoding="utf-8") as source:
        return int(source.read().strip()), done.stdout.strip()


def first_line(command):
    done = subprocess.run(command, capture_output=True, text=True, errors="replace")
    text = (done.stdout or done.stderr).splitlines()
    return text[0] if text else "unknown"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--neper", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--go", default="go")
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--scratch", default="/tmp/neper-gp")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    repo = os.path.abspath(args.repo)
    scratch = os.path.abspath(args.scratch)
    os.makedirs(scratch, exist_ok=True)
    tools = {
        "c": shutil.which("cc"),
        "cpp": shutil.which("c++"),
        "rust": shutil.which("rustc"),
        "go": os.path.abspath(args.go) if os.path.sep in args.go else shutil.which(args.go),
        "neper": os.path.abspath(args.neper),
    }
    missing = [name for name, path in tools.items() if not path or not os.path.exists(path)]
    if missing:
        raise SystemExit("missing toolchains: " + ", ".join(missing))

    sources = {
        language: {
            workload: os.path.join(repo, "benchmarks", "gp", language, f"{workload}.{extension}")
            for workload in ("gp09", "gp10")
        }
        for language, extension in (("c", "c"), ("cpp", "cpp"), ("rust", "rs"), ("go", "go"), ("neper", "e"))
    }
    binaries = {
        (workload, language): os.path.join(scratch, f"{workload}-{language}")
        for workload in ("gp09", "gp10") for language in tools
    }

    def build_command(workload, language):
        source, output = sources[language][workload], binaries[(workload, language)]
        if language == "c":
            return [tools[language], "-std=c11", "-O3", "-march=x86-64-v3", source, "-o", output]
        if language == "cpp":
            return [tools[language], "-std=c++17", "-O3", "-march=x86-64-v3", source, "-o", output]
        if language == "rust":
            return [tools[language], "-C", "opt-level=3", "-C", "target-cpu=x86-64-v3", source, "-o", output]
        if language == "go":
            return [tools[language], "build", "-trimpath", "-ldflags=-s", "-o", output, source]
        return [tools[language], "emit-executable", source, repo, "x64", "linux", output,
                "--release", "--unchecked", "--cpu", "x64-v3"]

    compile_samples = {(workload, language): [] for workload in ("gp09", "gp10") for language in tools}
    for key in compile_samples:
        timed(build_command(*key))
    for _ in range(args.runs):
        for key in compile_samples:
            elapsed, _ = timed(build_command(*key))
            compile_samples[key].append(elapsed)

    variants = []
    for workload in ("gp09", "gp10"):
        for language in ("c", "cpp", "rust", "go"):
            variants.append((workload, language, [binaries[(workload, language)]]))
        if workload == "gp09":
            variants.append((workload, "neper", [binaries[(workload, "neper")]]))
        else:
            variants.append((workload, "neper-cpu", [binaries[(workload, "neper")], "cpu"]))
            variants.append((workload, "neper-vulkan", [binaries[(workload, "neper")], "vulkan"]))

    runtime_samples = {(workload, name): [] for workload, name, _ in variants}
    outputs = {}
    for workload, name, command in variants:
        _, output = timed(command)
        outputs[(workload, name)] = output
    for workload in ("gp09", "gp10"):
        observed = {output for (candidate, _), output in outputs.items() if candidate == workload}
        if len(observed) != 1:
            raise SystemExit(f"{workload} output mismatch: {sorted(observed)}")
    for _ in range(args.runs):
        for workload, name, command in variants:
            elapsed, output = timed(command)
            if output != outputs[(workload, name)]:
                raise SystemExit(f"unstable output from {name} {workload}: {output}")
            runtime_samples[(workload, name)].append(elapsed)

    cells = []
    for workload, name, command in variants:
        language = "neper" if name.startswith("neper-") else name
        rss, output = peak_rss(command, scratch)
        if output != outputs[(workload, name)]:
            raise SystemExit(f"memory run output mismatch from {name} {workload}: {output}")
        cells.append({
            "workload": workload,
            "implementation": name,
            "compile_ms": distribution(compile_samples[(workload, language)]),
            "runtime_ms": distribution(runtime_samples[(workload, name)]),
            "peak_rss_kib": rss,
            "image_bytes": os.path.getsize(command[0]),
            "output": output,
            "build_command": build_command(workload, language),
            "run_command": command,
        })
        print(f"{workload} {name:13} compile {cells[-1]['compile_ms']['p50']:8.1f} ms "
              f"run {cells[-1]['runtime_ms']['p50']:8.1f}/{cells[-1]['runtime_ms']['p95']:8.1f} ms "
              f"rss {rss / 1024:7.1f} MiB")

    cpu = "unknown"
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as source:
            cpu = next(line.split(":", 1)[1].strip() for line in source if line.startswith("model name"))
    except (OSError, StopIteration):
        pass
    report = {
        "schema": "neper-gp-performance-v1",
        "version": 1,
        "host": platform.platform(),
        "machine": platform.machine(),
        "cpu": cpu,
        "runs": args.runs,
        "workloads": {
            "gp09": {"algorithm": "lower-case Base16 encode then decode", "bytes": 4194317, "iterations": 8},
            "gp10": {"algorithm": "y[i] = 3*x[i] + y[i]", "elements": 1048576, "iterations": 16},
        },
        "toolchains": {
            "c": first_line([tools["c"], "--version"]),
            "cpp": first_line([tools["cpp"], "--version"]),
            "rust": first_line([tools["rust"], "--version"]),
            "go": first_line([tools["go"], "version"]),
            "neper": tools["neper"],
        },
        "revision": subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
        "cells": cells,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as target:
        json.dump(report, target, indent=1)
        target.write("\n")
    print("wrote", args.out)


if __name__ == "__main__":
    main()
