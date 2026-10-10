# -*- coding: utf-8 -*-
"""Freeze the inputs of the LLM-performance measurement before any model run (T027, H12).

Usage:
  python scripts/freeze_llm_protocol.py            write docs/llm-protocol-freeze.json for the current tree
  python scripts/freeze_llm_protocol.py --check    report which frozen input has drifted since (exit 1 on drift)

H12 asks that the compiler, schema, cards, prompts, fixtures, environment and baseline be archived before they are
altered, and that the task set and decision criteria be registered before candidate results are inspected. This records
what can be computed from the tree: content hashes of every input a run reads, the acceptance rule as data, the arms and
strata, and the placeholders (model families and versions, the held-out task ids) that must be filled and then frozen
before the first model run. A run's report names this file's hash; `--check` says what changed since.
"""
import hashlib
import json
import os
import platform
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "llm-protocol-freeze.json")


def sha(path):
    with open(os.path.join(ROOT, path), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def tree(directory, suffixes):
    entries = []
    base = os.path.join(ROOT, directory)
    for current, dirs, files in os.walk(base):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(suffixes):
                rel = os.path.relpath(os.path.join(current, name), ROOT).replace("\\", "/")
                entries.append((rel, sha(rel)))
    digest = hashlib.sha256()
    for rel, h in entries:
        digest.update(("%s %s\n" % (rel, h)).encode("utf-8"))
    return {"files": len(entries), "sha256": digest.hexdigest()}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


# What each input is and where it lives. A path is hashed whole; a tree is hashed as sorted (path, hash) lines.
FILES = {
    "card": "docs/llm-neper-card.md",
    "card_source": "docs/llm-neper-card.src.md",
    "agents": "AGENTS.md",
    "stream_schema": "docs/schemas/neper-v1.schema.json",
    "capabilities_golden": "tests/conformance/tools/capabilities.expected.jsonl",
    "tooling_budgets": "docs/tooling-budgets.md",
    "hardening_spec": "docs/post-m2-llm-hardening.md",
    "edit_benchmark_tasks": "benchmarks/llm_edit/tasks.json",
    "edit_benchmark_runner": "benchmarks/llm_edit/run.py",
    "edit_benchmark_readme": "benchmarks/llm_edit/README.md",
    "language_stats": "scripts/lang-stats.py",
    "opencode_skill": ".opencode/skills/neper/SKILL.md",
}
TREES = {
    "compiler_source": ("src", (".e",)),
    "standard_library": ("lib", (".e",)),
    "conformance_corpus": ("tests/conformance", (".e", ".jsonl", ".txt")),
    "llm_generation_benchmark": ("benchmarks/llm_gen", (".py", ".json", ".md", ".e")),
}

# The acceptance rule of H12 section 15, as data a report can quote and a checker can compare against.
ACCEPTANCE = {
    "order": ["verified correctness", "total interaction tokens per verified success", "repair turns", "source-token pressure"],
    "seeds_per_case": 20,
    "runs_per_task_minimum": 3,
    "minimum_tasks_per_family": {"local_edit": 200, "compiler_error_repair": 200},
    "thresholds": {
        "first_pass_local_edit_parse": 0.95,
        "first_pass_type_check": 0.90,
        "median_unrelated_formatted_diff": 0,
        "repair_within_one_additional_turn": 0.95,
    },
    "decision": "rank first, or be statistically tied, or expand the held-out evaluation; never assert superiority from an inconclusive result",
    "families": "at least two independently trained model families, fixed versions and settings, never pooled",
    "costs": "aborted tasks, retries, timeouts and failures keep their token and time costs in the totals",
}
ARMS = [
    {"id": "m2-baseline", "tools": "M2 compiler, equivalent minimal guidance"},
    {"id": "revised-minimal", "tools": "revised compiler, equivalent minimal guidance"},
    {"id": "revised-tools", "tools": "revised compiler with context, repair and test tools (info --json --capabilities lists them)"},
]
STRATA = ["local generation/editing", "nonlocal change", "temporal defects", "concurrency", "semantic context",
          "broken/adversarial input", "long-running behavior", "compiler correctness"]


def build():
    inputs = {}
    for name, path in FILES.items():
        inputs[name] = {"path": path, "sha256": sha(path) if os.path.exists(os.path.join(ROOT, path)) else None}
    for name, (directory, suffixes) in TREES.items():
        inputs[name] = dict(tree(directory, suffixes), path=directory)
    return {
        "schema": "neper-llm-protocol-freeze",
        "version": 1,
        "revision": git("rev-parse", "HEAD"),
        "dirty_paths": sorted(l.split(None, 1)[1] for l in git("status", "--porcelain", "--untracked-files=no").splitlines() if l.strip()),
        "environment": {"python": platform.python_version(), "os": platform.system(), "machine": platform.machine()},
        "inputs": inputs,
        "acceptance": ACCEPTANCE,
        "arms": ARMS,
        "strata": STRATA,
        "to_register_before_first_run": {
            "model_families": [],
            "held_out_task_ids": [],
            "harness_arm_opencode": None,
            "baseline_results_archive": None,
        },
    }


def main(argv):
    frozen = build()
    if "--check" in argv:
        if not os.path.exists(OUT):
            print("no freeze recorded: run without --check first", file=sys.stderr)
            return 2
        with open(OUT, encoding="utf-8") as f:
            recorded = json.load(f)
        drift = []
        for name, now in frozen["inputs"].items():
            was = recorded["inputs"].get(name)
            if was is None:
                drift.append("%s: not in the freeze" % name)
            elif was.get("sha256") != now.get("sha256"):
                drift.append("%s (%s): changed" % (name, now["path"]))
        for name in recorded["inputs"]:
            if name not in frozen["inputs"]:
                drift.append("%s: no longer an input" % name)
        if drift:
            print("\n".join(drift))
            print("%d input(s) drifted since the freeze of %s" % (len(drift), recorded["revision"][:12]))
            return 1
        print("every frozen input is unchanged since %s" % recorded["revision"][:12])
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(frozen, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    print("wrote %s: %d inputs at %s%s" % (os.path.relpath(OUT, ROOT), len(frozen["inputs"]), frozen["revision"][:12],
                                          " (dirty: %d tracked path(s))" % len(frozen["dirty_paths"]) if frozen["dirty_paths"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
