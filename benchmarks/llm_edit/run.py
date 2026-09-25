#!/usr/bin/env python3
"""Compare an LLM's search and surgical-edit performance on sample.e/sample.rs."""

from __future__ import annotations

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TASKS = Path(__file__).with_name("tasks.json")


def reported_tokens(output: str) -> int | None:
    match = re.search(r"tokens used\s*\n\s*([\d,]+)", output, re.IGNORECASE)
    return int(match.group(1).replace(",", "")) if match else None


def changed_lines(before: str, after: str) -> int:
    changes = 0
    for line in difflib.ndiff(before.splitlines(), after.splitlines()):
        if line.startswith(("+ ", "- ")):
            changes += 1
    return changes


def score(task: dict, before: str, after: str, answer: str) -> tuple[bool, str]:
    if task["kind"] == "search":
        actual = answer.strip().strip("`").strip()
        expected = task["expected"]
        return actual == expected, f"expected {expected!r}, got {actual!r}"

    failures = []
    for check in task["checks"]:
        count = len(re.findall(check["pattern"], after))
        if "count" in check and count != check["count"]:
            failures.append(f"/{check['pattern']}/ count {count}, expected {check['count']}")
        if "min_count" in check and count < check["min_count"]:
            failures.append(f"/{check['pattern']}/ count {count}, expected >= {check['min_count']}")
    edits = changed_lines(before, after)
    if edits > task["max_changed_lines"]:
        failures.append(f"changed {edits} lines, limit {task['max_changed_lines']}")
    if before == after:
        failures.append("file was not changed")
    return not failures, "; ".join(failures) or "ok"


def run_trial(command: str, source: Path, task: dict) -> dict:
    with tempfile.TemporaryDirectory(prefix="neper-llm-bench-") as raw_dir:
        workspace = Path(raw_dir)
        target = workspace / source.name
        shutil.copy2(source, target)
        before = target.read_text(encoding="utf-8")
        prompt = (
            f"Work only on {target.name}. {task['prompt']}\n"
            "For a search task, print only the requested answer. For an update task, edit the file."
        )
        prompt_file = workspace / "prompt.txt"
        prompt_file.write_text(prompt, encoding="utf-8")
        rendered = command.format(
            workspace=str(workspace), file=str(target),
            prompt_file=str(prompt_file),
        )
        argv = shlex.split(rendered) if os.name != "nt" else [
            part.strip('"') for part in shlex.split(rendered, posix=False)]
        started = time.perf_counter()
        proc = subprocess.run(
            argv, cwd=workspace, capture_output=True, text=True, shell=False,
        )
        elapsed = time.perf_counter() - started
        after = target.read_text(encoding="utf-8")
        passed, detail = score(task, before, after, proc.stdout)
        if proc.returncode:
            passed = False
            detail = f"agent exited {proc.returncode}: {proc.stderr.strip()}"
        return {
            "language": source.suffix[1:], "task": task["id"], "kind": task["kind"],
            "passed": passed, "detail": detail, "seconds": round(elapsed, 3),
            "changed_lines": changed_lines(before, after),
            "tokens": reported_tokens(proc.stdout + "\n" + proc.stderr),
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-command", required=True, help=(
        "Command template; placeholders: {workspace}, {file}, {prompt}, {prompt_file}. "
        "Prefer {prompt_file} to avoid shell quoting issues."))
    parser.add_argument("--tasks", type=Path, default=DEFAULT_TASKS)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be at least 1")
    tasks = json.loads(args.tasks.read_text(encoding="utf-8"))
    sources = [ROOT / "examples/sample.e", ROOT / "examples/sample.rs"]
    results = [run_trial(args.agent_command, source, task)
               for _ in range(args.trials) for task in tasks for source in sources]
    summary = {}
    for language in ("e", "rs"):
        rows = [r for r in results if r["language"] == language]
        token_rows = [r["tokens"] for r in rows if r["tokens"] is not None]
        summary[language] = {
            "passed": sum(r["passed"] for r in rows), "total": len(rows),
            "pass_rate": sum(r["passed"] for r in rows) / len(rows),
            "mean_seconds": round(sum(r["seconds"] for r in rows) / len(rows), 3),
            "mean_changed_lines": round(sum(r["changed_lines"] for r in rows) / len(rows), 2),
            "mean_reported_tokens": (round(sum(token_rows) / len(token_rows), 1)
                                     if token_rows else None),
        }
    report = {"summary": summary, "results": results}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for language, row in summary.items():
            print(f"{language:>2}: {row['passed']}/{row['total']} passed "
                  f"({row['pass_rate']:.0%}), {row['mean_seconds']:.3f}s mean, "
                  f"{row['mean_changed_lines']:.2f} changed lines mean")
        for row in results:
            if not row["passed"]:
                print(f"FAIL {row['language']} {row['task']}: {row['detail']}")
    return 0 if all(r["passed"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
