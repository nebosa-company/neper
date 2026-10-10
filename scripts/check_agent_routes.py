# -*- coding: utf-8 -*-
"""Smoke check of the agent routes (T036): an agent that follows AGENTS.md or the
OpenCode skill reaches the card, `context-file`, a patch tool and `check-fixture`
without a full-file read.

Usage:  python scripts/check_agent_routes.py

Checks, each naming the file and the missing item on failure:
  * AGENTS.md routes to the card, context-file, patch/plan-*, check-fixture and the
    digests, and points at the skill.
  * .opencode/skills/neper/SKILL.md has `name`/`description` frontmatter and routes
    to the same five things.
  * Every repository path either names exists; every compiler command the skill
    names is a command the card lists as verified.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = ["llm-neper-card.md", "context-file", "check-fixture", "digest"]
PATCH_ANY = ["patch.exe", "tools/patch", "plan-"]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def main():
    problems = []

    def need(where, text, items):
        for item in items:
            if item not in text:
                problems.append("%s does not route to %s" % (where, item))

    agents = read("AGENTS.md")
    need("AGENTS.md", agents, REQUIRED)
    if not any(p in agents for p in PATCH_ANY):
        problems.append("AGENTS.md does not route to a patch tool")
    need("AGENTS.md", agents, [".opencode/skills/neper/SKILL.md"])

    skill_path = ROOT / ".opencode" / "skills" / "neper" / "SKILL.md"
    if not skill_path.exists():
        problems.append(".opencode/skills/neper/SKILL.md is missing")
    else:
        skill = skill_path.read_text(encoding="utf-8")
        front = re.match(r"^---\n(.*?)\n---\n", skill, re.S)
        if not front or not re.search(r"^name:\s*neper\s*$", front.group(1), re.M) or "description:" not in front.group(1):
            problems.append("the skill lacks `name: neper` and `description:` frontmatter")
        need("the skill", skill, REQUIRED)
        if not any(p in skill for p in PATCH_ANY):
            problems.append("the skill does not route to a patch tool")
        card = read("docs/llm-neper-card.md")
        verified = set(re.findall(r"^\| `([a-z-]+)` \| verified \|$", card, re.M))
        for command in set(re.findall(r"`((?:context|uses|explain|check)-file|plan-[a-z-]+-file|apply-plan)`", skill)):
            if command not in verified:
                problems.append("the skill names `%s`, which the card does not list as verified" % command)
        for path in set(re.findall(r"`((?:docs|scripts|tools)/[A-Za-z0-9_./-]+)`", skill + agents)):
            if "<" in path or "*" in path:
                continue
            if not (ROOT / path).exists():
                problems.append("a route names %s, which does not exist" % path)

    if problems:
        for p in problems:
            print("check_agent_routes: " + p, file=sys.stderr)
        return 1
    print("agent routes ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
