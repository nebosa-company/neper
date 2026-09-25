#!/usr/bin/env python3
"""Large-corpus LLM benchmark: search, refactor, and deletion across 1M LOC."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import time


MODULES = 500
LINES_PER_MODULE = 2_000
OLD_NAME = "recalibrate_sensor_0417"
NEW_NAME = "recalibrate_sensor_precisely_0417"
DELETE_NAME = "obsolete_sensor_0418"
REF_MODULES = (13, 71, 127, 193, 249, 313, 377, 441)
DELETE_MODULES = (19, 83, 151, 227, 301, 389)


def relative(language: str, module: int) -> str:
    return f"src/module_{module:04d}.{language}"


def source_for(language: str, module: int) -> str:
    extension = "e" if language == "e" else "rs"
    comment = "//"
    lines = [f"{comment} generated {language} module {module:04d}, line {line:04d}"
             for line in range(1, LINES_PER_MODULE + 1)]
    if module == 417:
        if language == "e":
            snippet = [
                f"fn find_sensor_0417(value: f32) -> f32 {{",
                "    ret value",
                "}",
                f"fn {OLD_NAME}(value: f32) -> f32 {{",
                "    ret value * 1.01",
                "}",
            ]
        else:
            snippet = [
                "fn find_sensor_0417(value: f32) -> f32 {",
                "    value",
                "}",
                f"fn {OLD_NAME}(value: f32) -> f32 {{",
                "    value * 1.01",
                "}",
            ]
        lines[100:106] = snippet
    if module == 418:
        if language == "e":
            snippet = [
                f"fn {DELETE_NAME}(value: f32) -> f32 {{",
                "    let damped = value * 0.5",
                "    ret damped",
                "}",
            ]
        else:
            snippet = [
                f"fn {DELETE_NAME}(value: f32) -> f32 {{",
                "    let damped = value * 0.5;",
                "    damped",
                "}",
            ]
        lines[200:204] = snippet
    if module in REF_MODULES:
        lines[300] = f"let probe_{module:04d} = {OLD_NAME}(41.7);"
    if module in DELETE_MODULES:
        lines[400] = f"let retired_{module:04d} = {DELETE_NAME}(41.8);"
    return "\n".join(lines) + "\n"


def build_workspace(workspace: Path, language: str) -> None:
    src = workspace / "src"
    src.mkdir()
    for module in range(MODULES):
        (src / f"module_{module:04d}.{language}").write_text(
            source_for(language, module), encoding="utf-8")
    actual_lines = sum(
        path.read_text(encoding="utf-8").count("\n") for path in src.iterdir())
    if actual_lines != MODULES * LINES_PER_MODULE:
        raise RuntimeError(f"generated {actual_lines} lines, expected 1,000,000")


def count_token(workspace: Path, token: str) -> int:
    return sum(path.read_text(encoding="utf-8").count(token)
               for path in (workspace / "src").iterdir())


def count_lines(workspace: Path) -> int:
    return sum(path.read_text(encoding="utf-8").count("\n")
               for path in (workspace / "src").iterdir())


def task_prompt(language: str, task: str) -> str:
    if task == "search":
        return (
            "This workspace contains one million lines of source. Find the file that defines "
            "`find_sensor_0417`. Reply with only its project-relative path.")
    if task == "refactor":
        return (
            f"This workspace contains one million lines of {language} source. Rename "
            f"`{OLD_NAME}` to `{NEW_NAME}` and update every call site. Make no unrelated edits.")
    return (
        f"This workspace contains one million lines of {language} source. Delete the "
        f"`{DELETE_NAME}` function and every call site. Do not replace or rename it, and make "
        "no unrelated edits.")


def evaluate(language: str, task: str, workspace: Path, answer: str, before_lines: int) -> tuple[bool, str]:
    if task == "search":
        expected = relative(language, 417)
        actual = answer.strip().strip("`").replace("\\", "/")
        return actual == expected, f"expected {expected!r}, got {actual!r}"
    if task == "refactor":
        old_count = count_token(workspace, OLD_NAME)
        new_count = count_token(workspace, NEW_NAME)
        expected = 1 + len(REF_MODULES)
        changed = before_lines - count_lines(workspace)
        ok = old_count == 0 and new_count == expected and abs(changed) <= 20
        return ok, f"old={old_count}, new={new_count}/{expected}, line_delta={changed}"
    old_count = count_token(workspace, DELETE_NAME)
    deleted = before_lines - count_lines(workspace)
    expected_deleted = 4 + len(DELETE_MODULES)
    ok = old_count == 0 and expected_deleted <= deleted <= 20
    return ok, f"remaining={old_count}, deleted_lines={deleted}/{expected_deleted}+"


def run_case(agent_command: str, language: str, task: str) -> dict:
    with tempfile.TemporaryDirectory(prefix=f"neper-mega-{language}-{task}-") as raw:
        workspace = Path(raw)
        build_workspace(workspace, language)
        before_lines = count_lines(workspace)
        prompt = task_prompt(language, task)
        prompt_file = workspace / "prompt.txt"
        prompt_file.write_text(prompt, encoding="utf-8")
        command = agent_command.format(
            workspace=str(workspace), prompt_file=str(prompt_file))
        argv = shlex.split(command) if os.name != "nt" else [
            part.strip('"') for part in shlex.split(command, posix=False)]
        started = time.perf_counter()
        proc = subprocess.run(
            argv, cwd=workspace,
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            shell=False)
        seconds = time.perf_counter() - started
        passed, detail = evaluate(language, task, workspace, proc.stdout, before_lines)
        if proc.returncode:
            passed = False
            detail = f"agent exited {proc.returncode}: {proc.stderr[-400:]}"
        return {"language": language, "task": task, "passed": passed,
                "seconds": round(seconds, 3), "detail": detail}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-command", required=True,
                        help="Template using {workspace}, {prompt}, or {prompt_file}.")
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be at least 1")
    results = [run_case(args.agent_command, language, task)
               for _ in range(args.trials)
               for task in ("search", "refactor", "delete")
               for language in ("e", "rs")]
    summary = {}
    for language in ("e", "rs"):
        rows = [row for row in results if row["language"] == language]
        summary[language] = {"passed": sum(row["passed"] for row in rows),
                             "total": len(rows),
                             "mean_seconds": round(sum(row["seconds"] for row in rows) / len(rows), 3)}
    report = {"loc_per_language": MODULES * LINES_PER_MODULE,
              "summary": summary, "results": results}
    print(json.dumps(report, indent=2) if args.json else report)
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
