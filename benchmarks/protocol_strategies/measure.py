"""Measure equivalent implicit and explicit protocol strategies (D730, H06)."""

import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path


def make_source(strategy, count):
    explicit = strategy == "explicit"
    lines = ["error Failed", ""]
    for index in range(count):
        name = f"Item{index:04d}"
        protocol = f"item{index:04d}_cmp"
        lines += [
            f"type {name} = struct {{ value: i64 }}",
            f"fn {protocol}(a: {name}, b: {name}) -> i32 {{",
            "    if a.value < b.value { ret 0i32 - 1i32 }",
            "    if a.value > b.value { ret 1i32 }",
            "    ret 0i32",
            "}",
            "",
        ]
    if explicit:
        lines += [
            "fn compare[T: type, F: fn(T, T) -> i32](a: T, b: T) -> i32 { ret F(a, b) }",
            "",
            "fn main() -> err {",
        ]
    else:
        lines += [
            "fn compare[T: type](a: T, b: T) -> i32 { ret T.cmp(a, b) }",
            "",
            "fn main() -> err {",
        ]
    for index in range(count):
        name = f"Item{index:04d}"
        arguments = f"{name}" + (f", item{index:04d}_cmp" if explicit else "")
        lines.append(
            f"    if compare[{arguments}]({name} {{ value: 0i64 }}, "
            f"{name} {{ value: 1i64 }}) != 0i32 - 1i32 {{ ret Failed }}"
        )
    lines += ["    ret ok", "}", ""]
    return "\n".join(lines)


def percentile(values, q):
    ordered = sorted(values)
    point = (len(ordered) - 1) * q
    low = int(point)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (point - low)


def distribution(values):
    return {
        "p50": round(statistics.median(values), 1),
        "p95": round(percentile(values, 0.95), 1),
        "min": min(values),
        "max": max(values),
        "runs": len(values),
    }


def compile_once(compiler, repo, host, source, output):
    command = [
        compiler,
        "emit-executable",
        str(source),
        repo,
        "x64",
        host,
        str(output),
        "--json",
        "--time",
        "--explain",
        "-j",
        "1",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, errors="replace")
    records = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
    if completed.returncode or not records or not records[-1].get("ok"):
        raise RuntimeError((completed.stdout + completed.stderr)[-2000:])
    check_ms = next(
        record["ms"]
        for record in records
        if record.get("record") == "progress" and record.get("phase") == "check bodies"
    )
    costs = [record for record in records if record.get("record") == "instance-cost"]
    return check_ms, sum(row["instructions"] for row in costs), sum(row["bytes"] for row in costs)


def delta(explicit, implicit):
    return {
        "absolute": round(explicit - implicit, 1),
        "percent": None if implicit == 0 else round(100.0 * (explicit - implicit) / implicit, 1),
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--host", choices=("windows", "linux"), required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--types", type=int, default=256)
    parser.add_argument("--revision", default=None)
    args = parser.parse_args(argv)
    if args.runs < 1 or args.types < 1:
        parser.error("--runs and --types must be positive")

    repo = os.path.abspath(args.repo)
    compiler = os.path.abspath(args.compiler)
    root = Path(repo) / "build" / "protocol-strategies"
    cells = []
    extension = ".exe" if args.host == "windows" else ""
    for strategy in ("implicit", "explicit"):
        directory = root / strategy / "src"
        directory.mkdir(parents=True, exist_ok=True)
        source = directory / "main.e"
        text = make_source(strategy, args.types)
        source.write_text(text, encoding="utf-8", newline="\n")
        output = root / strategy / ("program" + extension)
        compile_once(compiler, repo, args.host, source, output)  # warm filesystem/cache
        times = []
        instructions = set()
        machine_bytes = set()
        executable_bytes = set()
        for _ in range(args.runs):
            elapsed, instruction_count, byte_count = compile_once(
                compiler, repo, args.host, source, output
            )
            times.append(elapsed)
            instructions.add(instruction_count)
            machine_bytes.add(byte_count)
            executable_bytes.add(output.stat().st_size)
        if len(instructions) != 1 or len(machine_bytes) != 1 or len(executable_bytes) != 1:
            raise RuntimeError("deterministic cost changed between runs")
        cells.append(
            {
                "strategy": strategy,
                "source_sha256": hashlib.sha256(text.encode()).hexdigest(),
                "source_bytes": len(text.encode()),
                "check_bodies_ms": distribution(times),
                "instance_instructions": instructions.pop(),
                "instance_bytes": machine_bytes.pop(),
                "executable_bytes": executable_bytes.pop(),
            }
        )

    implicit, explicit = cells
    revision = args.revision
    if revision is None:
        revision = subprocess.run(
            ["git", "-c", f"safe.directory={repo}", "-C", repo, "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    report = {
        "schema": "neper-protocol-strategies",
        "version": 1,
        "host": args.host,
        "machine": platform.machine(),
        "platform": platform.platform(),
        "compiler": compiler,
        "revision": revision,
        "types": args.types,
        "runs": args.runs,
        "workers": 1,
        "cells": cells,
        "explicit_minus_implicit": {
            "check_bodies_p50_ms": delta(
                explicit["check_bodies_ms"]["p50"], implicit["check_bodies_ms"]["p50"]
            ),
            "instance_bytes": delta(explicit["instance_bytes"], implicit["instance_bytes"]),
            "executable_bytes": delta(
                explicit["executable_bytes"], implicit["executable_bytes"]
            ),
        },
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(
        "implicit/explicit check p50 %.1f/%.1f ms, instances %d/%d B, image %d/%d B"
        % (
            implicit["check_bodies_ms"]["p50"],
            explicit["check_bodies_ms"]["p50"],
            implicit["instance_bytes"],
            explicit["instance_bytes"],
            implicit["executable_bytes"],
            explicit["executable_bytes"],
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
