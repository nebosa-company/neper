#!/usr/bin/env python3
"""Semantic 1M-LOC LLM benchmark for Neper and Rust source trees.

Each case creates a fresh 500-module, exactly one-million-line tree. The corpus has
real-looking imports, definitions, constructors and call sites; filler comments keep
the lookup/edit problem large without inventing unrelated APIs.
"""

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


MODULE_COUNT = 500
LINES_PER_FILE = 2_000
CALLERS = (13, 71, 127, 193, 249, 313, 377, 441)
LEGACY_USERS = (19, 83, 151, 227, 301, 389)


def reported_tokens(output: str) -> int | None:
    """Return Codex CLI's final `tokens used` counter, when the agent emits one."""
    matches = re.findall(r"(?is)\btokens used\b.*?\n\s*([0-9][0-9,]*)\s*$", output)
    return int(matches[-1].replace(",", "")) if matches else None


def transcript_audit(transcript: str) -> dict[str, int]:
    """Summarize observable Codex tool activity from its CLI transcript.

    This is intentionally conservative: paths and returned filler lines are what the
    transcript exposes, not a claim of every byte the operating system read.
    """
    source_paths = set(re.findall(r"(?i)\bsrc[\\/][A-Za-z0-9_.-]+\.(?:e|rs)\b", transcript))
    return {
        "tool_calls": len(re.findall(r"(?m)^(?:exec|apply patch)$", transcript)),
        "search_commands": len(re.findall(r"\b(?:rg|Select-String|findstr|Get-ChildItem)\b", transcript)),
        "read_commands": len(re.findall(r"\b(?:Get-Content|type)\b", transcript)),
        "patch_operations": len(re.findall(r"(?m)^apply patch$", transcript)),
        "source_paths_observed": len(source_paths),
        "filler_lines_observed": len(re.findall(r"// generated (?:e|rs) filler line \d+", transcript)),
    }


def extension(language: str) -> str:
    return "." + language


def ordinary_path(language: str, module: int) -> str:
    return f"src/module_{module:04d}{extension(language)}"


def code(language: str, module: int) -> list[str]:
    """Executable snippets for an ordinary generated module."""
    if language == "e":
        imports, statements = [], []
        if module in CALLERS:
            imports.extend(("use calibration", "use sensor_model"))
            statements.extend((
                f"    let adjusted_{module:04d} = calibration.adjust_sensor_0417(41.7, 0.25)",
                f"    let sensor_{module:04d} = sensor_model.Sensor{{ sensor_id: u32({module}), temp: 41.8 }}",
                f"    let observed_{module:04d} = sensor_{module:04d}.sensor_id",
            ))
        if module in LEGACY_USERS:
            imports.append("use legacy_filter")
            statements.append(f"    let legacy_{module:04d} = legacy_filter.filter_legacy_sensor(41.8)")
        return imports + [f"fn generated_module_{module:04d}() {{"] + statements + ["}"]
    imports, statements = [], []
    if module in CALLERS:
        imports.extend((
            "use crate::calibration::adjust_sensor_0417;",
            "use crate::sensor_model::Sensor;",
        ))
        statements.extend((
            f"    let adjusted_{module:04d} = adjust_sensor_0417(41.7, 0.25);",
            f"    let sensor_{module:04d} = Sensor {{ sensor_id: {module}u32, temp: 41.8 }};",
            f"    let observed_{module:04d} = sensor_{module:04d}.sensor_id;",
        ))
    if module in LEGACY_USERS:
        imports.append("use crate::legacy_filter::filter_legacy_sensor;")
        statements.append(f"    let legacy_{module:04d} = filter_legacy_sensor(41.8);")
    return imports + [f"fn generated_module_{module:04d}() {{"] + statements + ["}"]


def special_code(language: str, name: str) -> list[str]:
    if name == "calibration":
        if language == "e":
            return [
                "fn adjust_sensor_0417(reading: f32, offset: f32) -> f32 {",
                "    ret reading + offset",
                "}",
            ]
        return [
            "pub fn adjust_sensor_0417(reading: f32, offset: f32) -> f32 {",
            "    reading + offset",
            "}",
        ]
    if name == "sensor_model":
        if language == "e":
            return ["type Sensor = struct {", "    sensor_id: u32,", "    temp: f32,", "}"]
        return ["pub struct Sensor {", "    pub sensor_id: u32,", "    pub temp: f32,", "}"]
    if language == "e":
        return [
            "fn filter_legacy_sensor(value: f32) -> f32 {",
            "    let damped = value * 0.5",
            "    ret damped",
            "}",
        ]
    return [
        "pub fn filter_legacy_sensor(value: f32) -> f32 {",
        "    let damped = value * 0.5;",
        "    damped",
        "}",
    ]


def write_file(path: Path, lines: list[str], language: str) -> None:
    filler = [f"// generated {language} filler line {line:04d}" for line in range(LINES_PER_FILE)]
    filler[:len(lines)] = lines
    path.write_text("\n".join(filler) + "\n", encoding="utf-8")


def build_workspace(workspace: Path, language: str) -> None:
    src = workspace / "src"
    src.mkdir()
    for module in range(MODULE_COUNT - 3):
        write_file(src / f"module_{module:04d}{extension(language)}", code(language, module), language)
    for name in ("calibration", "sensor_model", "legacy_filter"):
        write_file(src / f"{name}{extension(language)}", special_code(language, name), language)
    lines = sum(path.read_text(encoding="utf-8").count("\n") for path in src.iterdir())
    if lines != MODULE_COUNT * LINES_PER_FILE:
        raise RuntimeError(f"expected 1,000,000 lines, got {lines}")


def files(workspace: Path) -> list[Path]:
    return list((workspace / "src").iterdir())


def text(workspace: Path) -> str:
    return "".join(path.read_text(encoding="utf-8") for path in files(workspace))


def task_prompt(language: str, task: str, context_files: int, context_lines: int) -> str:
    budget = (
        f"Context budget: inspect no more than {context_files} source files and read no more "
        f"than {context_lines:,} source lines in total. Filename search and file listings do not "
        "count as source reads. Keep the edit correct even if the budget is tight.\n\n")
    if task == "signature":
        return budget + (
            "Across this one-million-line source tree, change `adjust_sensor_0417` to take "
            "`gain: f32` between `reading` and `offset`. Its implementation must become "
            "`reading * gain + offset`; update every call site with gain `1.0`. Do not make "
            "unrelated edits.")
    if task == "field":
        return budget + (
            "Across this one-million-line source tree, migrate `Sensor.sensor_id: u32` to "
            "`Sensor.id: u64`. Update every constructor and field access. Preserve explicit "
            "conversion: use `u64(<value>)` in Neper and the `u64` literal suffix in Rust. "
            "Do not make unrelated edits.")
    return budget + (
        "Delete the obsolete `legacy_filter` module from this one-million-line source tree, "
        "including its definition, every import, and every call site. Do not replace or rename "
        "the feature, and make no unrelated edits.")


def evaluate(language: str, task: str, workspace: Path, before_lines: int) -> tuple[bool, str]:
    src = workspace / "src"
    corpus = text(workspace)
    after_lines = corpus.count("\n")
    if task == "signature":
        definition = src / f"calibration{extension(language)}"
        if language == "e":
            signature_ok = "fn adjust_sensor_0417(reading: f32, gain: f32, offset: f32) -> f32" in definition.read_text(encoding="utf-8")
            body_ok = "ret reading * gain + offset" in definition.read_text(encoding="utf-8")
            calls_ok = all(f"calibration.adjust_sensor_0417(41.7, 1.0, 0.25)" in
                           (src / f"module_{m:04d}.e").read_text(encoding="utf-8") for m in CALLERS)
        else:
            signature_ok = "adjust_sensor_0417(reading: f32, gain: f32, offset: f32) -> f32" in definition.read_text(encoding="utf-8")
            body_ok = "reading * gain + offset" in definition.read_text(encoding="utf-8")
            calls_ok = all(f"adjust_sensor_0417(41.7, 1.0, 0.25);" in
                           (src / f"module_{m:04d}.rs").read_text(encoding="utf-8") for m in CALLERS)
        old_calls = len(re.findall(r"adjust_sensor_0417\(41\.7, 0\.25\)", corpus))
        ok = signature_ok and body_ok and calls_ok and old_calls == 0
        return ok, f"signature={signature_ok}, body={body_ok}, callers={calls_ok}, old_calls={old_calls}"
    if task == "field":
        model = (src / f"sensor_model{extension(language)}").read_text(encoding="utf-8")
        shape_ok = ("id: u64" in model and "sensor_id" not in model)
        if language == "e":
            users_ok = all(
                f"Sensor{{ id: u64({m}), temp: 41.8 }}" in (src / f"module_{m:04d}.e").read_text(encoding="utf-8") and
                f"sensor_{m:04d}.id" in (src / f"module_{m:04d}.e").read_text(encoding="utf-8") for m in CALLERS)
        else:
            users_ok = all(
                f"Sensor {{ id: {m}u64, temp: 41.8 }}" in (src / f"module_{m:04d}.rs").read_text(encoding="utf-8") and
                f"sensor_{m:04d}.id" in (src / f"module_{m:04d}.rs").read_text(encoding="utf-8") for m in CALLERS)
        remaining = len(re.findall(r"\bsensor_id\b", corpus))
        ok = shape_ok and users_ok and remaining == 0
        return ok, f"shape={shape_ok}, users={users_ok}, stale_field={remaining}"
    legacy_file = src / f"legacy_filter{extension(language)}"
    stale = len(re.findall(r"\b(?:legacy_filter|filter_legacy_sensor)\b", corpus))
    deleted = before_lines - after_lines
    minimum = LINES_PER_FILE + 2 * len(LEGACY_USERS)
    # Removing the module removes its 2,000 generated lines plus six import/call pairs.
    # Allow a small buffer for an agent that also removes adjacent blank lines.
    ok = not legacy_file.exists() and stale == 0 and minimum <= deleted <= minimum + 32
    return ok, f"file_deleted={not legacy_file.exists()}, stale={stale}, deleted_lines={deleted}/{minimum}+"


def run_case(command_template: str, language: str, task: str,
             context_files: int, context_lines: int) -> dict:
    with tempfile.TemporaryDirectory(prefix=f"neper-semantic-{language}-{task}-") as raw:
        workspace = Path(raw)
        build_workspace(workspace, language)
        before_lines = MODULE_COUNT * LINES_PER_FILE
        prompt_file = workspace / "prompt.txt"
        prompt = task_prompt(language, task, context_files, context_lines)
        prompt_file.write_text(prompt, encoding="utf-8")
        command = command_template.format(workspace=str(workspace), prompt_file=str(prompt_file))
        argv = shlex.split(command) if os.name != "nt" else [
            part.strip('"') for part in shlex.split(command, posix=False)]
        started = time.perf_counter()
        proc = subprocess.run(argv, cwd=workspace,
                              capture_output=True, text=True, encoding="utf-8", errors="replace",
                              shell=False)
        elapsed = time.perf_counter() - started
        passed, detail = evaluate(language, task, workspace, before_lines)
        if proc.returncode:
            passed, detail = False, f"agent exited {proc.returncode}: {proc.stderr[-400:]}"
        # `codex exec` writes its session transcript and final token counter to stderr;
        # its user-facing final response is stdout. Inspect both without double-counting.
        transcript = proc.stdout + "\n" + proc.stderr
        return {"language": language, "task": task, "passed": passed,
                "seconds": round(elapsed, 3), "tokens": reported_tokens(transcript),
                "audit": transcript_audit(transcript),
                "detail": detail}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-command", required=True,
                        help="Command template with {workspace}, {prompt}, or {prompt_file}.")
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--context-files", type=int, default=20,
                        help="Advisory maximum number of source files an agent may inspect.")
    parser.add_argument("--context-lines", type=int, default=10_000,
                        help="Advisory maximum number of source lines an agent may read.")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be at least 1")
    if args.context_files < 1 or args.context_lines < 1:
        parser.error("context budgets must be positive")
    results = [run_case(args.agent_command, language, task, args.context_files, args.context_lines)
               for _ in range(args.trials) for task in ("signature", "field", "delete")
               for language in ("e", "rs")]
    summary = {}
    for language in ("e", "rs"):
        rows = [r for r in results if r["language"] == language]
        token_rows = [r["tokens"] for r in rows if r["tokens"] is not None]
        audit = {key: round(sum(r["audit"][key] for r in rows) / len(rows), 1)
                 for key in rows[0]["audit"]}
        summary[language] = {"passed": sum(r["passed"] for r in rows), "total": len(rows),
                             "mean_seconds": round(sum(r["seconds"] for r in rows) / len(rows), 3),
                             "mean_reported_tokens": round(sum(token_rows) / len(token_rows), 1)
                             if token_rows else None,
                             "mean_observed_activity": audit}
    report = {"loc_per_language": MODULE_COUNT * LINES_PER_FILE,
              "summary": summary, "results": results}
    print(json.dumps(report, indent=2) if args.json else report)
    return 0 if all(r["passed"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
