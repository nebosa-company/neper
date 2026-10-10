# -*- coding: utf-8 -*-
"""Project source metrics by language, with snapshot deltas (T033).

Usage:
  python scripts/source_metrics.py [ROOT] [--json] [--snapshot FILE] [--compare FILE]
                                   [--ignore GLOB]... [--max-files N] [--max-bytes N]

Counts code, comment and blank lines by language over a source tree. It is a
source-analysis command: `e.metrics` is runtime telemetry and is unrelated.

Policy, all of it stated in the report so a number is never read without it:
  * Traversal is bounded by --max-files (default 100000) and --max-bytes per file
    (default 4 MiB); what the bounds skipped is reported, never silently dropped.
  * Directories named .git, .neper, build, node_modules, target and docs/tasks, and
    anything matching an --ignore glob, are skipped. Symlinks are not followed.
  * A file with a NUL byte in its first 8 KiB is binary and is skipped; a file that
    is not valid UTF-8 is counted as latin-1 and listed under `decoded_as_latin1`.
  * A line is blank, a comment line (only comment text), or a code line. A line with
    code and a trailing comment is code. Block comments and strings are tracked per
    language; a language with no comment syntax in the table counts every non-blank
    line as code and is marked `heuristic`.
  * The report does not count itself: a snapshot or report file under ROOT named by
    --snapshot or matching `source-metrics*.json` is excluded.

A snapshot is the JSON the command emits with --json; --compare FILE prints per
language and total deltas against it. The command is deterministic: files are visited
in sorted order and the report is sorted by language.
"""
import fnmatch
import json
import os
import sys
from pathlib import Path

# language: (extensions, line comment prefixes, block comment (open, close) pairs, string quotes)
LANGUAGES = {
    "Neper": ([".e"], ["//"], [], ['"']),
    "C": ([".c", ".h"], ["//"], [("/*", "*/")], ['"', "'"]),
    "C++": ([".cc", ".cpp", ".hpp", ".cxx"], ["//"], [("/*", "*/")], ['"', "'"]),
    "Rust": ([".rs"], ["//"], [("/*", "*/")], ['"']),
    "Go": ([".go"], ["//"], [("/*", "*/")], ['"', "`"]),
    "Dart": ([".dart"], ["//"], [("/*", "*/")], ['"', "'"]),
    "JavaScript": ([".js", ".mjs", ".cjs", ".jsx"], ["//"], [("/*", "*/")], ['"', "'", "`"]),
    "TypeScript": ([".ts", ".tsx"], ["//"], [("/*", "*/")], ['"', "'", "`"]),
    "Python": ([".py"], ["#"], [], ['"', "'"]),
    "Shell": ([".sh", ".bash"], ["#"], [], ['"', "'"]),
    "PowerShell": ([".ps1", ".psm1"], ["#"], [("<#", "#>")], ['"', "'"]),
    "SQL": ([".sql"], ["--"], [("/*", "*/")], ["'"]),
    "HTML": ([".html", ".htm"], [], [("<!--", "-->")], []),
    "CSS": ([".css"], [], [("/*", "*/")], ['"', "'"]),
    "Markdown": ([".md"], [], [], []),
    "JSON": ([".json"], [], [], []),
    "YAML": ([".yml", ".yaml"], ["#"], [], []),
    "TOML": ([".toml"], ["#"], [], []),
}
# Languages whose comment syntax is not tracked: every non-blank line is code.
HEURISTIC = {"Markdown", "JSON"}
SKIP_DIRS = {".git", ".neper", "build", "node_modules", "target", "__pycache__"}
SKIP_PATHS = {"docs/tasks"}
BY_EXTENSION = {ext: name for name, (exts, *_rest) in LANGUAGES.items() for ext in exts}


def count_lines(text, language):
    """(code, comment, blank) for one file's text."""
    _exts, line_comments, blocks, quotes = LANGUAGES[language]
    code = comment = blank = 0
    in_block = None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # the newline that ends the last line starts no line
    for raw in lines:
        line = raw.strip()
        if not line:
            blank += 1
            continue
        if language in HEURISTIC:
            code += 1
            continue
        has_code = False
        has_comment = False
        i = 0
        quote = None
        while i < len(line):
            if in_block:
                has_comment = True
                end = line.find(in_block, i)
                if end < 0:
                    i = len(line)
                else:
                    i = end + len(in_block)
                    in_block = None
                continue
            ch = line[i]
            if quote:
                has_code = True
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = None
                i += 1
                continue
            opened = next((b for b in blocks if line.startswith(b[0], i)), None)
            if opened:
                in_block = opened[1]
                has_comment = True
                i += len(opened[0])
                continue
            if any(line.startswith(p, i) for p in line_comments):
                has_comment = True
                break
            if ch in quotes:
                quote = ch
            if not ch.isspace():
                has_code = True
            i += 1
        if has_code:
            code += 1
        elif has_comment:
            comment += 1
        else:
            blank += 1
    return code, comment, blank


def walk(root, ignores, max_files, excluded):
    files = []
    skipped = {"ignored": 0, "max_files": 0}
    for current, dirs, names in os.walk(root, followlinks=False):
        rel_dir = os.path.relpath(current, root).replace("\\", "/")
        dirs[:] = sorted(
            d for d in dirs
            if d not in SKIP_DIRS
            and not os.path.islink(os.path.join(current, d))
            and (rel_dir == "." and d or rel_dir + "/" + d) not in SKIP_PATHS
        )
        for name in sorted(names):
            path = os.path.join(current, name)
            rel = os.path.relpath(path, root).replace("\\", "/")
            if os.path.islink(path) or rel in excluded or fnmatch.fnmatch(name, "source-metrics*.json"):
                continue
            if any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(name, g) for g in ignores):
                skipped["ignored"] += 1
                continue
            if len(files) >= max_files:
                skipped["max_files"] += 1
                continue
            files.append((rel, path))
    return files, skipped


def scan(root, ignores, max_files, max_bytes, excluded):
    files, skipped = walk(root, ignores, max_files, excluded)
    languages = {}
    notes = {"binary": 0, "too_large": 0, "unknown_language": 0, "decoded_as_latin1": []}
    for rel, path in files:
        language = BY_EXTENSION.get(os.path.splitext(rel)[1].lower())
        if language is None:
            notes["unknown_language"] += 1
            continue
        try:
            size = os.path.getsize(path)
            if size > max_bytes:
                notes["too_large"] += 1
                continue
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if b"\x00" in data[:8192]:
            notes["binary"] += 1
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("latin-1")
            notes["decoded_as_latin1"].append(rel)
        code, comment, blank = count_lines(text.replace("\r\n", "\n"), language)
        entry = languages.setdefault(language, {"files": 0, "code": 0, "comment": 0, "blank": 0, "heuristic": language in HEURISTIC})
        entry["files"] += 1
        entry["code"] += code
        entry["comment"] += comment
        entry["blank"] += blank
    return {
        "languages": {k: languages[k] for k in sorted(languages)},
        "skipped": skipped,
        "notes": notes,
        "bounds": {"max_files": max_files, "max_bytes": max_bytes, "ignores": sorted(ignores)},
    }


def totals(report):
    t = {"files": 0, "code": 0, "comment": 0, "blank": 0}
    for entry in report["languages"].values():
        for key in t:
            t[key] += entry[key]
    return t


def human(report, baseline=None):
    lines = ["%-12s %7s %9s %9s %8s" % ("language", "files", "code", "comment", "blank")]
    for name, e in report["languages"].items():
        mark = "*" if e["heuristic"] else " "
        row = "%-12s %7d %9d %9d %8d%s" % (name, e["files"], e["code"], e["comment"], e["blank"], mark)
        if baseline is not None:
            b = baseline["languages"].get(name, {"files": 0, "code": 0, "comment": 0, "blank": 0})
            row += "   (%+d code, %+d comment, %+d files)" % (e["code"] - b["code"], e["comment"] - b["comment"], e["files"] - b["files"])
        lines.append(row)
    t = totals(report)
    row = "%-12s %7d %9d %9d %8d" % ("total", t["files"], t["code"], t["comment"], t["blank"])
    if baseline is not None:
        bt = totals(baseline)
        row += "   (%+d code, %+d comment, %+d files)" % (t["code"] - bt["code"], t["comment"] - bt["comment"], t["files"] - bt["files"])
    lines.append(row)
    if baseline is not None:
        for name in baseline["languages"]:
            if name not in report["languages"]:
                lines.append("%-12s removed since the snapshot" % name)
    lines.append("* heuristic: comment syntax not tracked, every non-blank line counted as code")
    n = report["notes"]
    lines.append("skipped: %d ignored, %d past max-files, %d binary, %d too large, %d unknown language"
                 % (report["skipped"]["ignored"], report["skipped"]["max_files"], n["binary"], n["too_large"], n["unknown_language"]))
    if n["decoded_as_latin1"]:
        lines.append("decoded as latin-1: %d file(s)" % len(n["decoded_as_latin1"]))
    return "\n".join(lines)


def main(argv):
    root = "."
    ignores = []
    as_json = False
    snapshot = compare = None
    max_files = 100000
    max_bytes = 4 * 1024 * 1024
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--json":
            as_json = True
        elif a in ("--snapshot", "--compare", "--ignore", "--max-files", "--max-bytes"):
            i += 1
            if i >= len(argv):
                print("source_metrics: %s needs a value" % a, file=sys.stderr)
                return 2
            v = argv[i]
            if a == "--snapshot":
                snapshot = v
            elif a == "--compare":
                compare = v
            elif a == "--ignore":
                ignores.append(v)
            elif a == "--max-files":
                max_files = int(v)
            else:
                max_bytes = int(v)
        elif a.startswith("-"):
            print("source_metrics: unknown option %s" % a, file=sys.stderr)
            return 2
        else:
            root = a
        i += 1
    root = os.path.abspath(root)
    excluded = set()
    for f in (snapshot, compare):
        if f:
            p = os.path.abspath(f)
            if p.startswith(root + os.sep):
                excluded.add(os.path.relpath(p, root).replace("\\", "/"))
    report = scan(root, ignores, max_files, max_bytes, excluded)
    baseline = None
    if compare:
        try:
            baseline = json.loads(Path(compare).read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            print("source_metrics: cannot read snapshot %s: %s" % (compare, e), file=sys.stderr)
            return 2
    if snapshot:
        Path(snapshot).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if as_json:
        out = dict(report)
        out["totals"] = totals(report)
        if baseline is not None:
            bt = totals(baseline)
            out["delta"] = {k: out["totals"][k] - bt[k] for k in bt}
        print(json.dumps(out, indent=2, sort_keys=True))
    else:
        print(human(report, baseline))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        # Cancelled: no partial report is written or printed as if it were complete.
        print("source_metrics: cancelled", file=sys.stderr)
        sys.exit(130)
