# -*- coding: utf-8 -*-
"""Rank open library work by what agents actually hand-roll (T043).

Usage:  python scripts/library_demand.py [--days N] [--projects DIR] [--write]

Reads the Claude Code transcripts of this repository (default
~/.claude/projects/<repo>), takes every Neper source an agent wrote with the Write or
Edit tool outside `lib/e/` (a test fixture, a tool, a probe), and collects the
function names it declares. A name that appears in sessions but is not a declaration
of the standard library is something an agent had to write for itself; a name that
*is* a library declaration written again somewhere else is a function agents did not
find. Both are demand. Open `L` queue items are scored by the demand their title and
evidence words share with those names, giving a ranked view for the breadth work.

With --write the result goes to docs/digest/library-demand.tsv; without it the top of
the ranking prints. Re-run after new transcripts accumulate; the serial head of the
queue is never reordered from this, it only says where the next breadth work pays.
"""
import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FN = re.compile(r"^\s*fn\s+([a-z_][a-z0-9_]*)\s*[\[(]", re.M)
STOP = {
    "main", "run", "get", "set", "new", "of", "to", "is", "as", "with", "from", "the", "and", "for", "in", "add",
    "push", "make", "read", "write", "name", "text", "value", "list", "check", "test", "print", "join", "len",
}


def library_names():
    """Every function declared under lib/e, name -> sorted modules."""
    names = collections.defaultdict(set)
    for path in (ROOT / "lib" / "e").rglob("*.e"):
        module = "e." + ".".join(path.relative_to(ROOT / "lib" / "e").with_suffix("").parts)
        for m in FN.finditer(path.read_text(encoding="utf-8", errors="replace")):
            names[m.group(1)].add(module)
    return names


def transcript_files(projects, days):
    cutoff = None
    if days:
        import time
        cutoff = time.time() - days * 86400
    for path in sorted(Path(projects).glob("*.jsonl")):
        if cutoff and path.stat().st_mtime < cutoff:
            continue
        yield path


def written_neper(path):
    """(file_path, text) for each Write/Edit of a .e file in one transcript."""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"file_path"' not in line or ".e\"" not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            content = record.get("message", {}).get("content")
            if not isinstance(content, list):
                continue
            for part in content:
                if not isinstance(part, dict) or part.get("type") != "tool_use":
                    continue
                args = part.get("input") or {}
                target = str(args.get("file_path", "")).replace("\\", "/")
                if not target.endswith(".e") or "/lib/e/" in target:
                    continue
                text = args.get("content") or args.get("new_string") or ""
                if text:
                    yield target, text


def words(text):
    return {w for w in re.findall(r"[a-z]{3,}", text.lower()) if w not in STOP}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--days", type=int, default=0)
    ap.add_argument("--projects", default=str(Path.home() / ".claude" / "projects" / "D--repos-neper"))
    ap.add_argument("--write", action="store_true")
    opts = ap.parse_args(argv)

    library = library_names()
    sessions = collections.defaultdict(set)
    for path in transcript_files(opts.projects, opts.days):
        for target, text in written_neper(path):
            for name in set(FN.findall(text)):
                sessions[name].add(path.stem)

    rows = []
    for name, seen in sessions.items():
        kind = "reinvented" if name in library else "hand-rolled"
        rows.append((len(seen), name, kind, ",".join(sorted(library.get(name, ())))[:80]))
    rows.sort(key=lambda r: (-r[0], r[1]))

    queue = json.loads((ROOT / "docs" / "work-queue.json").read_text(encoding="utf-8"))["items"]
    demand = collections.Counter()
    for count, name, kind, modules in rows:
        for w in set(re.split(r"_", name)) - STOP:
            if len(w) >= 3:
                demand[w] += count
    ranked = []
    for item in queue:
        if item["category"] != "library" or item["score"] >= 1:
            continue
        score = sum(demand[w] for w in words(item["title"]) if w in demand)
        ranked.append((score, item["id"], item["title"]))
    ranked.sort(key=lambda r: (-r[0], r[1]))

    lines = ["rank\tid\tdemand\ttitle"]
    for rank, (score, ident, title) in enumerate(ranked, 1):
        lines.append("%d\t%s\t%d\t%s" % (rank, ident, score, title))
    lines += ["", "sessions\tname\tkind\tlibrary modules"]
    lines += ["%d\t%s\t%s\t%s" % r for r in rows[:150]]
    body = "\n".join(lines) + "\n"
    if opts.write:
        out = ROOT / "docs" / "digest" / "library-demand.tsv"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(body, encoding="utf-8", newline="\n")
        print("wrote %s (%d open library items ranked, %d names)" % (out.relative_to(ROOT), len(ranked), len(rows)))
    else:
        print("\n".join(lines[:40]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
