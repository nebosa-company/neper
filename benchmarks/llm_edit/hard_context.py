#!/usr/bin/env python3
"""Hard-capped retrieval benchmark for a 1M-LOC cross-module signature migration.

The corpus is never materialized in the agent workspace. A localhost retrieval server
holds it in memory and enforces a source-line quota. The agent can search metadata,
read bounded ranges, then submit exact replacements in ``edits.json``. This makes the
retrieval budget mechanically enforceable for the benchmark corpus.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import random
import re
import secrets
import shutil
import statistics
import subprocess
import tempfile
import threading
import time


MODULES = 500
LINES_PER_FILE = 2_000
ROOT = Path(__file__).resolve().parents[2]
NEPER_CARD = (ROOT / "docs" / "llm-neper-card.md").read_text(encoding="utf-8")
RUST_CARD = (ROOT / "docs" / "llm-rust-card.md").read_text(encoding="utf-8")


def token_count(transcript: str) -> int | None:
    matches = re.findall(r"(?is)\btokens used\b.*?\n\s*([0-9][0-9,]*)\s*$", transcript)
    return int(matches[-1].replace(",", "")) if matches else None


@dataclass
class Corpus:
    language: str
    api: str
    callers: tuple[int, ...]
    files: dict[str, str]
    read_limit: int
    read_lines: int = 0
    read_requests: int = 0
    rejected_reads: int = 0
    search_requests: int = 0


def make_file(language: str, top: list[str]) -> str:
    filler = [f"// generated {language} filler line {i:04d}" for i in range(LINES_PER_FILE)]
    filler[:len(top)] = top
    return "\n".join(filler) + "\n"


def build_corpus(language: str, seed: int, read_limit: int) -> Corpus:
    rng = random.Random(seed)
    api = f"adjust_sensor_{rng.randrange(10**8, 10**9)}"
    callers = tuple(sorted(rng.sample(range(MODULES - 1), 8)))
    files: dict[str, str] = {}
    if language == "e":
        api_lines = [
            f"fn {api}(reading: f32, offset: f32) -> f32 {{",
            "    ret reading + offset",
            "}",
        ]
    else:
        api_lines = [
            f"pub fn {api}(reading: f32, offset: f32) -> f32 {{",
            "    reading + offset",
            "}",
        ]
    files[f"src/calibration.{language}"] = make_file(language, api_lines)
    for module in range(MODULES - 1):
        if module in callers:
            if language == "e":
                top = [
                    "use calibration",
                    f"fn generated_module_{module:04d}() {{",
                    f"    let adjusted = calibration.{api}(41.7, 0.25)",
                    "}",
                ]
            else:
                top = [
                    f"use crate::calibration::{api};",
                    f"fn generated_module_{module:04d}() {{",
                    f"    let adjusted = {api}(41.7, 0.25);",
                    "}",
                ]
        else:
            top = [f"fn generated_module_{module:04d}() {{", "}"]
        files[f"src/module_{module:04d}.{language}"] = make_file(language, top)
    assert len(files) == MODULES
    assert sum(content.count("\n") for content in files.values()) == MODULES * LINES_PER_FILE
    return Corpus(language, api, callers, files, read_limit)


def server_for(corpus: Corpus) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, _format: str, *_args: object) -> None:
            pass

        def reply(self, status: int, body: dict) -> None:
            encoded = json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            if parsed.path == "/search":
                corpus.search_requests += 1
                needle = query.get("q", [""])[0]
                matches = []
                for path, content in corpus.files.items():
                    for line_number, line in enumerate(content.splitlines(), 1):
                        if needle and needle in line:
                            matches.append({"path": path, "line": line_number})
                            if len(matches) == 100:
                                self.reply(200, {"matches": matches, "truncated": True})
                                return
                self.reply(200, {"matches": matches, "truncated": False})
                return
            if parsed.path == "/index":
                corpus.search_requests += 1
                needle = query.get("q", [""])[0]
                records = []
                if needle == corpus.api:
                    records.append({"record": "symbol", "kind": "fn", "name": corpus.api,
                                    "qualified_name": f"calibration.{corpus.api}",
                                    "module": "calibration", "file": f"src/calibration.{corpus.language}",
                                    "line": 1})
                    for module in corpus.callers:
                        records.append({"record": "reference", "role": "call", "spelling": corpus.api,
                                        "target_qualified_name": f"calibration.{corpus.api}",
                                        "file": f"src/module_{module:04d}.{corpus.language}", "line": 3})
                self.reply(200, {"records": records})
                return
            if parsed.path == "/read":
                path = query.get("path", [""])[0]
                try:
                    start, end = int(query.get("start", [""])[0]), int(query.get("end", [""])[0])
                except ValueError:
                    self.reply(400, {"error": "start and end must be integers"})
                    return
                if path not in corpus.files or start < 1 or end < start:
                    self.reply(404, {"error": "unknown path or invalid range"})
                    return
                lines = corpus.files[path].splitlines()
                end = min(end, len(lines))
                requested = end - start + 1
                if corpus.read_lines + requested > corpus.read_limit:
                    corpus.rejected_reads += 1
                    self.reply(429, {"error": "hard context budget exceeded", "used_lines": corpus.read_lines,
                                     "limit_lines": corpus.read_limit})
                    return
                corpus.read_lines += requested
                corpus.read_requests += 1
                self.reply(200, {"path": path, "start": start, "end": end,
                                 "text": "\n".join(lines[start - 1:end]) + "\n"})
                return
            if parsed.path == "/usage":
                self.reply(200, {"read_lines": corpus.read_lines, "read_limit": corpus.read_limit,
                                 "read_requests": corpus.read_requests, "search_requests": corpus.search_requests,
                                 "rejected_reads": corpus.rejected_reads})
                return
            self.reply(404, {"error": "unknown endpoint"})

    return ThreadingHTTPServer(("127.0.0.1", 0), Handler)


def write_client(workspace: Path, server: ThreadingHTTPServer) -> None:
    host, port = server.server_address
    base = f"http://{host}:{port}"
    script = f'''param([Parameter(Position=0)][string]$action, [Parameter(ValueFromRemainingArguments=$true)][string[]]$rest)
$base = "{base}"
if ($action -eq "search") {{
    $query = [uri]::EscapeDataString(($rest -join " "))
    Invoke-RestMethod -Uri "$base/search?q=$query" | ConvertTo-Json -Depth 4
}} elseif ($action -eq "read") {{
    if ($rest.Count -ne 3) {{ throw "usage: .\\corpus.ps1 read PATH START END" }}
    $path = [uri]::EscapeDataString($rest[0])
    $response = Invoke-RestMethod -Uri "$base/read?path=$path&start=$($rest[1])&end=$($rest[2])"
    $response.text
}} elseif ($action -eq "index") {{
    if ($rest.Count -ne 1) {{ throw "usage: .\\corpus.ps1 index SYMBOL" }}
    $query = [uri]::EscapeDataString($rest[0])
    Invoke-RestMethod -Uri "$base/index?q=$query" | ConvertTo-Json -Depth 4
}} elseif ($action -eq "usage") {{
    Invoke-RestMethod -Uri "$base/usage" | ConvertTo-Json
}} else {{ throw "usage: .\\corpus.ps1 search TEXT | index SYMBOL | read PATH START END | usage" }}
'''
    (workspace / "corpus.ps1").write_text(script, encoding="utf-8")
    instructions = '''# Hard-context benchmark

The one-million-line source corpus is not present on disk. Use only:

```powershell
.\\corpus.ps1 search SYMBOL
.\\corpus.ps1 read src/file.e 1 20
.\\corpus.ps1 usage
```

Search returns paths and line numbers without source text. Reads are permanently
limited by the server. To submit your edit, create `edits.json` with this schema:

```json
{"replacements": [{"path": "src/file.e", "old": "exact old text", "new": "exact new text"}]}
```

Use exact text from `read`; include every required replacement. Do not invent files.
'''
    (workspace / "INSTRUCTIONS.md").write_text(instructions, encoding="utf-8")


def apply_edits(corpus: Corpus, workspace: Path) -> tuple[bool, str]:
    edit_file = workspace / "edits.json"
    if not edit_file.exists():
        return False, "edits.json was not created"
    try:
        edits = json.loads(edit_file.read_text(encoding="utf-8"))
        replacements = edits["replacements"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        return False, f"invalid edits.json: {error}"
    if not isinstance(replacements, list):
        return False, "replacements must be a list"
    for item in replacements:
        if not isinstance(item, dict) or set(item) != {"path", "old", "new"}:
            return False, "every replacement must have only path, old, and new"
        path, old, new = item["path"], item["old"], item["new"]
        if path not in corpus.files or not all(isinstance(value, str) for value in (old, new)):
            return False, "replacement has an unknown path or non-string value"
        if corpus.files[path].count(old) != 1:
            return False, f"replacement old text was not unique in {path}"
        corpus.files[path] = corpus.files[path].replace(old, new, 1)
    return True, "ok"


def evaluate(corpus: Corpus) -> tuple[bool, str]:
    api_path = f"src/calibration.{corpus.language}"
    api_text = corpus.files[api_path]
    if corpus.language == "e":
        signature = f"fn {corpus.api}(reading: f32, gain: f32, offset: f32) -> f32"
        body = "ret reading * gain + offset"
        calls = [f"calibration.{corpus.api}(41.7, 1.0, 0.25)" for _ in corpus.callers]
    else:
        signature = f"fn {corpus.api}(reading: f32, gain: f32, offset: f32) -> f32"
        body = "reading * gain + offset"
        calls = [f"{corpus.api}(41.7, 1.0, 0.25);" for _ in corpus.callers]
    callers_ok = all(call in corpus.files[f"src/module_{module:04d}.{corpus.language}"]
                     for module, call in zip(corpus.callers, calls))
    old_calls = sum(f"{corpus.api}(41.7, 0.25)" in content for content in corpus.files.values())
    ok = signature in api_text and body in api_text and callers_ok and old_calls == 0
    return ok, f"signature={signature in api_text}, body={body in api_text}, callers={callers_ok}, old_calls={old_calls}"


def run_case(command_template: str, language: str, seed: int, read_limit: int,
             use_neper_card: bool, use_rust_card: bool) -> dict:
    corpus = build_corpus(language, seed, read_limit)
    server = server_for(corpus)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix=f"neper-hard-context-{language}-") as raw:
            workspace = Path(raw)
            write_client(workspace, server)
            prompt = (
                f"Migrate `{corpus.api}` across the hidden 1M-LOC {language} corpus. Add `gain: f32` "
                "between `reading` and `offset`; make the implementation `reading * gain + offset`; "
                "update every call with `1.0`. Follow INSTRUCTIONS.md exactly and submit edits.json.")
            if language == "e" and use_neper_card:
                prompt += "\n\n" + NEPER_CARD + "\nUse `.\\corpus.ps1 index <symbol>` before source reads."
            if language == "rs" and use_rust_card:
                prompt += "\n\n" + RUST_CARD + "\nUse `.\\corpus.ps1 index <symbol>` before source reads."
            prompt_file = workspace / "prompt.txt"
            prompt_file.write_text(prompt, encoding="utf-8")
            command = command_template.format(workspace=str(workspace), prompt=prompt, prompt_file=str(prompt_file))
            started = time.perf_counter()
            proc = subprocess.run(command, cwd=workspace, capture_output=True, text=True,
                                  encoding="utf-8", errors="replace", shell=os.name == "nt")
            seconds = time.perf_counter() - started
            applied, detail = apply_edits(corpus, workspace)
            passed, evaluation = evaluate(corpus) if applied else (False, detail)
            if proc.returncode:
                passed, evaluation = False, f"agent exited {proc.returncode}: {proc.stderr[-400:]}"
            transcript = proc.stdout + "\n" + proc.stderr
            arm = "e+card" if language == "e" and use_neper_card else "rs+card" if language == "rs" and use_rust_card else language
            return {"language": language, "arm": arm,
                    "seed": seed, "passed": passed,
                    "seconds": round(seconds, 3), "tokens": token_count(transcript),
                    "retrieval": {"read_lines": corpus.read_lines, "read_limit": corpus.read_limit,
                                  "read_requests": corpus.read_requests, "search_requests": corpus.search_requests,
                                  "rejected_reads": corpus.rejected_reads}, "detail": evaluation}
    finally:
        server.shutdown()
        server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-command", required=True)
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--read-limit", type=int, default=500)
    parser.add_argument("--neper-card", action="store_true",
                        help="Give only Neper runs the compact grammar/index editing card.")
    parser.add_argument("--rust-card", action="store_true",
                        help="Give only Rust runs the equivalent syntax/index editing card.")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--summary-only", action="store_true",
                        help="When used with --json, omit individual trial records.")
    args = parser.parse_args()
    if args.trials < 1 or args.read_limit < 1:
        parser.error("--trials and --read-limit must be positive")
    results = []
    for _ in range(args.trials):
        seed = secrets.randbits(63)
        for language in ("e", "rs"):
            results.append(run_case(args.agent_command, language, seed, args.read_limit,
                                    args.neper_card, args.rust_card))
    summary = {}
    for language in ("e", "rs"):
        arm = "e+card" if language == "e" and args.neper_card else "rs+card" if language == "rs" and args.rust_card else language
        rows = [row for row in results if row["arm"] == arm]
        token_rows = [row["tokens"] for row in rows if row["tokens"] is not None]
        summary[arm] = {
            "passed": sum(row["passed"] for row in rows), "total": len(rows),
            "mean_seconds": round(sum(row["seconds"] for row in rows) / len(rows), 3),
            "median_seconds": round(statistics.median(row["seconds"] for row in rows), 3),
            "mean_tokens": round(sum(token_rows) / len(token_rows), 1) if token_rows else None,
            "median_tokens": round(statistics.median(token_rows), 1) if token_rows else None,
            "mean_read_lines": round(sum(row["retrieval"]["read_lines"] for row in rows) / len(rows), 1),
            "mean_search_requests": round(sum(row["retrieval"]["search_requests"] for row in rows) / len(rows), 1),
        }
    paired_rows = []
    for seed in {row["seed"] for row in results}:
        pair = {row["language"]: row for row in results if row["seed"] == seed}
        if set(pair) != {"e", "rs"}:
            continue
        e, rust = pair["e"], pair["rs"]
        if e["tokens"] is not None and rust["tokens"] is not None:
            paired_rows.append({"token_delta_e_minus_rs": e["tokens"] - rust["tokens"],
                                "seconds_delta_e_minus_rs": round(e["seconds"] - rust["seconds"], 3)})
    paired = None
    if paired_rows:
        token_deltas = [row["token_delta_e_minus_rs"] for row in paired_rows]
        second_deltas = [row["seconds_delta_e_minus_rs"] for row in paired_rows]
        paired = {"pairs": len(paired_rows),
                  "e_used_fewer_tokens": sum(delta < 0 for delta in token_deltas),
                  "mean_token_delta_e_minus_rs": round(statistics.mean(token_deltas), 1),
                  "median_token_delta_e_minus_rs": round(statistics.median(token_deltas), 1),
                  "mean_seconds_delta_e_minus_rs": round(statistics.mean(second_deltas), 3),
                  "median_seconds_delta_e_minus_rs": round(statistics.median(second_deltas), 3)}
    report = {"loc_per_language": MODULES * LINES_PER_FILE, "read_limit": args.read_limit,
              "summary": summary, "paired": paired, "results": results}
    if args.summary_only:
        report.pop("results")
    print(json.dumps(report, indent=2) if args.json else report)
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
