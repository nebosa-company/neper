# -*- coding: utf-8 -*-
"""Render one self-contained task file per unfinished feature to docs/tasks/.

Usage:  python scripts/render_tasks.py     (from the repository root)

Everything left to implement, in four inventories, each already machine-readable:
  compiler/ and tooling/  the partial rows of docs/work-queue.json
  modules/                every module-apis.md fence with a missing declaration
  ui/                     every docs/widget-plan.json item with an undelivered component
  milestones/             roadmap.md bullets that have no queue row (M3+, T2 slices, M6, backlog)

The files are written for a small local coding model: each one carries the
definition of done, what is already delivered, the exact remaining checklist, the
decision rows it must read, the source files that mention its identifiers, and the
commands that prove it. Re-run after every queue, plan or fence change; never edit
the output by hand.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "tasks"
DOCS = ROOT / "docs"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def slug(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:60].rstrip("-")


def write(rel, text):
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


# ---------------------------------------------------------------- sources
queue = json.loads(read("docs/work-queue.json"))["items"]
done_ids = {json.loads(l)["id"]: json.loads(l)["title"]
            for l in read("docs/work-done.jsonl").splitlines() if l.strip()}
plan = json.loads(read("docs/modules.json"))
modules = {m["name"]: m for m in plan["modules"]}
widget_plan = json.loads(read("docs/widget-plan.json"))
roadmap = read("docs/roadmap.md")
hardening = read("docs/post-m2-llm-hardening.md")
decisions_text = read("docs/decisions.md")
tracks = json.loads(read("docs/hardening-tracks.json"))
module_apis = read("docs/module-apis.md")
proposal = read("docs/widget-library-proposal.md")

DECISIONS = {}
for i, line in enumerate(decisions_text.splitlines(), 1):
    m = re.match(r"## (D\d+) (?:—|--|-) (.*)", line) or re.match(r"\| (D\d+) \| ([^|]+) \|", line)
    if m:
        DECISIONS[m.group(1)] = (m.group(2).strip(), i)

HSECTIONS = {}
for m in re.finditer(r"^## \d+\. (H\d\d) — (.*?)\n(.*?)(?=^## \d+\. |\Z)", hardening, re.S | re.M):
    HSECTIONS[m.group(1)] = (m.group(2).strip(), m.group(3).strip())

H_TRACK = {}
for t in tracks["tracks"]:
    for r in t["requirements"]:
        H_TRACK.setdefault(r.split(":")[0], []).append((t["id"], t["name"], t["status"]))

API_BLOCKS = dict(re.findall(r"^### `([^`]+)`\n(.*?)(?=^### |\Z)", module_apis, re.S | re.M))


def roadmap_section(title):
    m = re.search(r"^## " + re.escape(title) + r".*?\n(.*?)(?=^## |\Z)", roadmap, re.S | re.M)
    return m.group(1) if m else ""


def roadmap_bullets(section):
    """Top-level `- ` bullets of one roadmap section, continuation lines joined."""
    out, cur = [], None
    for line in roadmap_section(section).splitlines():
        if line.startswith("- "):
            if cur:
                out.append(cur)
            cur = line[2:]
        elif cur is not None and line.startswith("  "):
            cur += " " + line.strip()
        elif cur is not None and not line.strip():
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return out


def roadmap_bullet(section, keyword):
    for b in roadmap_bullets(section):
        if keyword in b:
            return b
    raise SystemExit("no roadmap bullet in %r containing %r" % (section, keyword))


def roadmap_done_when(section):
    m = re.search(r"\*\*Done when:\*\*(.*?)(?=\n\n|\Z)", roadmap_section(section), re.S)
    return ("**Done when:**" + m.group(1)).strip() if m else ""


def tracked_files():
    return subprocess.run(["git", "ls-files", "src", "lib", "tests", "scripts", "docs/schemas", "benchmarks", "bootstrap"],
                          capture_output=True, text=True, cwd=ROOT).stdout.split()


TRACKED = tracked_files()
SIZES = {p: (ROOT / p).stat().st_size for p in TRACKED if (ROOT / p).exists()}

STOP = {"windows", "linux", "release", "debug", "result", "stdout", "stderr", "message", "symbol",
        "kind", "executable", "module", "modules", "source", "sources", "target", "shared", "worker",
        "workers", "phase", "record", "records", "header", "true", "false", "usize", "isize", "main",
        "build", "check", "test", "run", "tokens", "parse", "index", "info", "format", "manifest",
        "through", "inline", "diagnostic", "stream", "option", "options", "project", "artifact",
        "artifacts", "section", "features", "version", "unsafe", "checks", "commands", "float"}


def identifiers(text):
    """Backticked identifiers, flags and fixture paths worth grepping for."""
    out = []
    for tok in re.findall(r"`([^`\n]{3,60})`", text):
        tok = tok.strip()
        if " " in tok and not tok.startswith("--"):
            continue
        core = tok.split()[0].lstrip("-").split("(")[0]
        if len(core) < 4 or core.lower() in STOP or not re.match(r"^[A-Za-z_@.][A-Za-z0-9_./:-]*$", core):
            continue
        if core not in out:
            out.append(core)
    return out


def anchors(text, limit_tokens=24, limit_files=8):
    """git grep every identifier over the tracked tree; return (token, [(file, count)])."""
    rows = []
    for tok in identifiers(text)[:limit_tokens]:
        proc = subprocess.run(["git", "grep", "-c", "-F", "-e", tok, "--", "src", "lib", "tests/conformance", "scripts", "benchmarks"],
                              capture_output=True, text=True, cwd=ROOT, encoding="utf-8", errors="replace")
        hits = []
        for line in proc.stdout.splitlines():
            path, _, n = line.rpartition(":")
            if path and not path.startswith(("benchmarks/tokens/", "scripts/render_tasks.py", "scripts/bonsai_driver.py")):
                hits.append((path.replace("\\", "/"), int(n)))
        hits.sort(key=lambda h: -h[1])
        specific = any(c in tok for c in "._-/") or tok[:1].isupper()
        if hits and (len(hits) <= 12 or specific):
            rows.append((tok, hits[:limit_files]))
    return rows


def fixture_paths(text):
    """`link/name` and `tests/conformance/...` spellings that exist on disk."""
    found = []
    for m in re.findall(r"`?((?:tests/conformance/[a-z_]+/|link/|check/|em/|nir/|graph/|resolve/|scope/|modules/|variants/|cycle/|diagnostics/)[A-Za-z0-9_./-]+)`?", text):
        m = m.rstrip(".,;)")
        cands = [m, "tests/selfhost/fixtures/" + m, "tests/selfhost/fixtures/" + m + "/src/main.e",
                 "tests/conformance/" + m, m + ".e"]
        for c in cands:
            if (ROOT / c).exists() and c not in found:
                found.append(c)
                break
    return found


def decisions_of(text):
    ids = sorted({d for d in re.findall(r"\bD\d{2,3}\b", text)}, key=lambda d: int(d[1:]))
    rows = []
    for d in ids:
        if d in DECISIONS:
            title, line = DECISIONS[d]
            rows.append("- `%s` — %s (`docs/decisions.md:%d`)" % (d, title, line))
    return rows


def split_gap(evidence):
    """Return (delivered, remaining): the gap sentence cut out of the evidence.

    The gap clause is the sentence that starts at the marker and ends at the next
    sentence boundary; what follows it (C066, C080) is delivered work, not gap."""
    for marker in ("Not yet:", "What is left is", "what remains sequential is"):
        i = evidence.rfind(marker)
        if i < 0:
            continue
        tail = evidence[i + len(marker):]
        m = re.search(r"\.\s+(?=[A-Z`])", tail)
        end = m.start() if m else len(tail)
        remaining = tail[:end].strip(" .")
        delivered = (evidence[:i].rstrip(" .;,") + ("" if not m else ". " + tail[m.end():])).strip()
        return delivered, remaining
    return evidence, ""


SPLIT_AT = re.compile(r"(?:, and |; | and (?=(?:a|an|the|every|both|any|streamed|sequence|columns|more)\b)"
                      r"|, (?=(?:a|an|the|every|both|any|streamed|sequence|columns|more|reuse|variant|partial|edit|cross|serialized"
                      r"|aliases|non|build|generation|raw|lazy|allocation|pinned|following|comptime|compiler|meta|which)\b))")


def checklist(remaining):
    """Split the gap clause into lines at depth-0 separators (never inside parentheses or backticks)."""
    if not remaining:
        return []
    parts, cur, depth, tick, i = [], "", 0, False, 0
    while i < len(remaining):
        c = remaining[i]
        if c == "`":
            tick = not tick
        elif c == "(" and not tick:
            depth += 1
        elif c == ")" and not tick:
            depth = max(0, depth - 1)
        if depth == 0 and not tick:
            m = SPLIT_AT.match(remaining, i)
            if m:
                parts.append(cur)
                cur = ""
                i = m.end()
                continue
        cur += c
        i += 1
    parts.append(cur)
    parts = [p.strip(" .") for p in parts if p.strip(" .")]
    return parts if parts else [remaining]


def size_note(path):
    n = SIZES.get(path)
    if n is None:
        return ""
    if n > 120_000:
        return "‡"
    if n > 40_000:
        return "†"
    return ""


def deps_table(names):
    rows = ["| dependency | surface | source file | layer |", "|---|---|---|---|"]
    for d in names:
        m = modules.get(d)
        rel = "lib/e/" + d[2:].replace(".", "/") + ".e"
        exists = (ROOT / rel).exists()
        rows.append("| `%s` | %s | %s | %s |" % (d, m["surface"] if m else "?", "`%s`" % rel if exists else "missing",
                                               m["layer"] if m else "?"))
    return "\n".join(rows)


def module_file_of(name):
    return "lib/e/" + name[2:].replace(".", "/") + ".e"


def procedure(unit, record):
    return """## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. %s
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. %s Run `python scripts/render_progress.py` and commit only the touched paths.
""" % (unit, record)


PROCEDURE = procedure(
    "Pick **one** line of the remaining checklist above. Do not attempt the whole item.",
    "Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful.")
MODULE_PROCEDURE = procedure(
    "A module is one deliverable: the whole fence, in order. Across sessions, land one group of related functions at a time and keep `lib/e/<module>.e` compiling and its fixture passing after each.",
    "When every declaration is present, move the module's `surface` to `\"source\"` in `docs/modules.json` (validated by `python tests/test_module_plan.py`).")
WIDGET_PROCEDURE = procedure(
    "Take the one component `check_widget_plan.py --next` names; a component is a widget with its layout, paint, semantics and input fixtures.",
    "Append the component to `delivered` and its sentence to `evidence` in `docs/widget-plan.json`.")


# ---------------------------------------------------------------- queue items
def effort(item):
    m, t = item.get("model", ""), item.get("thinking", "")
    if m == "opus" and t == "xhigh":
        return "very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line"
    if m == "opus":
        return "high — rated for a frontier model; one checklist line per session, thinking budget unlimited"
    if m == "sonnet":
        return "medium — rated for a mid-size model; one or two checklist lines per session"
    return "low — rated for a small model; a whole checklist line per session is realistic"


DEFINITION = {
    # id: (kind, key)   kind: hardening H-id | roadmap (section, keyword) | text
    "C029": ("roadmap", ("M1 — The full CPU language", "`Vec[T, N]`")),
    "C060": ("spec", "Argument packs"),
    "C062": ("text", "One merged error table per image: every module's `error` names get one identity across the whole program, built in `main.e` before lowering, so a trap and `neper test` can name an error from any module (spec §7, §11 Trap protocol)."),
    "C065": ("roadmap", ("M1 — The full CPU language", "full debug-mode check table")),
    "C066": ("roadmap", ("M1 — The full CPU language", "Compile-time interpreter")),
    "C079": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Cross-module inlining")),
    "C080": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Incremental and parallel module")),
    "C082": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Work-stealing thread pool")),
    "C083": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Determinism harness")),
    "C084": ("roadmap", ("M1 — The full CPU language", "Debug info on the default path")),
    "C088": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Bootstrap compiler frozen")),
    "T001": ("roadmap", ("M1 — The full CPU language", "finite-command JSONL contract")),
    "T002": ("tooling", "## 7. Test, build and command results"),
    "T003": ("tooling", "## 7. Test, build and command results"),
    "T004": ("tooling", "## 7. Test, build and command results"),
    "T005": ("roadmap", ("M1 — The full CPU language", "`@test` discovery")),
    "T006": ("roadmap", ("M1 — The full CPU language", "`neper fmt` implements")),
    "T007": ("roadmap", ("M1 — The full CPU language", "Lossless `tokens`/`parse`")),
    "T008": ("roadmap", ("M1 — The full CPU language", "Lossless `tokens`/`parse`")),
    "T009": ("roadmap", ("M1 — The full CPU language", "Complete deterministic `index`")),
    "T010": ("tooling", "## 7. Test, build and command results"),
    "T011": ("tooling", "## 1. Version and stream envelope"),
    "T012": ("tooling", "## 9. Conformance and compatibility"),
    "T013": ("roadmap", ("M1 — The full CPU language", "Stable diagnostic codes")),
    "T014": ("roadmap", ("M1 — The full CPU language", "canonical v1 build manifest")),
    "T015": ("tooling", "## 8. Generated source maps"),
    "T016": ("tooling", "## 9. Conformance and compatibility"),
    "T021": ("text", "The compiler's own hashing (CRC-32C for artifact checksums, SHA-256 for manifest digests) comes from `lib/e` (`e.algo.hash`, `e.crypto.hash`) instead of private copies in `src/`, so one implementation is tested once and the compiler is a client of its own library. Blocked in part by the C bootstrap, which must still compile every module the compiler imports."),
    "T022": ("roadmap", ("M2 — Self-hosting and `.em` modules", "Determinism harness")),
    "T023": ("text", "A committed corpus of generated-code benchmarks (`benchmarks/llm_edit`, spec §1 NFRs, roadmap 'Cross-milestone verification': GP-09 and the LLM thresholds — 95% parse first pass, 90% type-check first pass, zero unrelated formatted diff, 95% one-turn repairs) with a runner and a report section that `tooling.md` §9 asks for."),
}

NOTES = {
    "C029": ["The one remaining line is an ABI change: `Vec`/`Mask` in xmm registers across a call on both System V and win64 (spec §5). Start by reading how aggregates cross today (`src/lower.e` and `src/codegen_x64.e`, search `by address`) and the fixture `link/simd_lanes`."],
    "C044": ["`any vectorizer` is reported unavailable on purpose: auto-vectorisation is under roadmap 'Deliberately not scheduled'. Do not build one; the remaining lines are the measurements."],
    "C060": ["The evidence names no gap clause; the remaining line is the third pack intrinsic: `gpu.launch` must expand a comptime pack the way the two others do. The other two are the reference implementation — find them with `rg -n 'pack' src/check.e src/lower.e`."],
    "C066": ["Order matters: the evidence says 'Before it: integer const folding, and a branch over a local' are done; next is structs, then slices, then strings, then the arena as interpreter memory, then an array across a call, then meta-only calls in a body. Roadmap backlog 'neper eval EXPR' (D470) waits on this item."],
    "C080": ["The gap clause in the queue predates D319–D324, which delivered the hot build it names. At 0.95 what is still owed is the roadmap's 'a one-function edit rebuilds in milliseconds' on both hosts against a measured baseline, and a warm build that does not load every module's declarations. Measure with `--stats` on a warm no-change build before choosing; if nothing is left, the honest increment is a `Not yet:` rewrite and the score."],
    "C082": ["The remaining gap is spelled in the evidence's last clause: collecting the declarations, reachability and layout are still sequential, and work is assigned statically rather than stolen. Measure before and after with `--stats`; a change that does not move a number is not the feature."],
    "C084": ["Score 0.35 with three large deliverables. Take them in the roadmap's order: the DWARF locals-and-types subset on ELF first (`lldb`/`gdb` must show locals), CodeView on PE second, a named `.nepersym` section third. Each is its own session series."],
    "C088": ["Last of all: this item is score 0 by design. Freezing and deleting `bootstrap/neper.c` is only correct after every other compiler item no longer needs a stage-0 rebuild and the archived recovery revision (C087) is verified on a machine with no `neper` binary. Do not pick this item while any other compiler item is partial."],
    "T007": ["The evidence names no gap: the 94th token kind is not pinned by `every_kind` (93 of 94). Find which kind is missing by diffing the registry in `docs/grammar.ebnf` against the golden in `tests/conformance/tokens/`, add it, and re-pin."],
    "T012": ["The remaining shape is `packageManifest`: it is in `docs/schemas/neper-v1.schema.json` with nothing producing it. It becomes producible with M6 pacman P0; until then the honest increment is a fixture document validated by `scripts/validate_stream.py` so the schema branch is exercised."],
    "T021": ["Blocked in part: the C bootstrap refuses `lib/e/crypto/hash.e` (nineteen E-TYPE-0002s, a `u64` shifted by a `u32`). Either fix the bootstrap's shift typing (`bootstrap/neper.c`) or rewrite those shifts in the library so both compilers accept them; then move SHA-256. CRC-32C first needs the table-driven `crc32c` in `e.algo.hash` (D333)."],
    "T023": ["Score 0.5 with only a path as evidence. Read `benchmarks/llm_edit` and `tests/test_llm_edit_benchmark.py` first; the missing half is the report `tooling.md` §9 names and its runner entry in both suites."],
}


def definition_text(item):
    hid = re.search(r"\bH(\d\d)\b", item["title"])
    kind, key = DEFINITION.get(item["id"], (None, None))
    if hid and ("H" + hid.group(1)) in HSECTIONS:
        h = "H" + hid.group(1)
        title, body = HSECTIONS[h]
        track = "; ".join("%s (%s, %s)" % t for t in H_TRACK.get(h, []))
        extra = ""
        for p in sorted(DOCS.glob("m25-%s-*.md" % h.lower())):
            extra += "\n\nThe closure design for this requirement is `docs/%s`; read it after the section below." % p.name
        return ("From `docs/post-m2-llm-hardening.md`, **%s — %s** (track: %s):%s\n\n%s" % (h, title, track or "unassigned", extra, body))
    if kind == "roadmap":
        section, keyword = key
        return "From `docs/roadmap.md`, section **%s**:\n\n> %s\n\n%s" % (section, roadmap_bullet(section, keyword), roadmap_done_when(section))
    if kind == "tooling":
        return "The contract is `docs/tooling.md`, section `%s` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft)." % key
    if kind == "spec":
        m = re.search(r"^### " + re.escape(key) + r"\n(.*?)(?=^##)", read("docs/spec.md"), re.S | re.M)
        return "From `docs/spec.md`, section **%s**:\n\n%s" % (key, m.group(1).strip() if m else "(section not found)")
    if kind == "text":
        return key
    return "See `docs/roadmap.md` and the evidence below."


def render_queue_item(item, position):
    delivered, remaining = split_gap(item["evidence"])
    lines = checklist(remaining)
    dec = decisions_of(item["evidence"])
    anch = anchors(item["evidence"])
    fx = fixture_paths(item["evidence"])
    out = []
    out.append("# %s — %s" % (item["id"], item["title"]))
    out.append("")
    out.append("| field | value |\n|---|---|")
    out.append("| category | %s / %s |" % (item["category"], item["group"]))
    out.append("| score | %.2f of 1 |" % float(item["score"]))
    out.append("| queue position | %d of %d (only position 1 is eligible for the next session; see README) |" % (position, len(queue)))
    out.append("| difficulty | %s |" % effort(item))
    out.append("")
    out.append("## Definition of done\n")
    out.append(definition_text(item))
    out.append("")
    out.append("## Already delivered\n")
    out.append("Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.\n")
    out.append("> " + delivered.replace("\n", "\n> "))
    out.append("")
    out.append("## Remaining work\n")
    if lines:
        out.append("The queue's own gap clause, split into checklist lines. Each line is one session's target.\n")
        for l in lines:
            out.append("- [ ] %s" % l)
    else:
        out.append("- [ ] (no gap clause in the queue — see the notes below)")
    if item["id"] in NOTES:
        out.append("")
        out.append("Notes:\n")
        for n in NOTES[item["id"]]:
            out.append("- " + n)
    out.append("")
    if dec:
        out.append("## Decisions to read first\n")
        out.append("Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.\n")
        out.extend(dec)
        out.append("")
    if anch:
        out.append("## Code anchors\n")
        out.append("Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.\n")
        for tok, hits in anch:
            out.append("- `%s`: " % tok + ", ".join("`%s`×%d%s" % (p, n, size_note(p)) for p, n in hits))
        out.append("")
    if fx:
        out.append("## Existing fixtures\n")
        for f in fx:
            out.append("- `%s`" % f)
        out.append("")
    out.append("## Verification\n")
    out.append("- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).")
    out.append("- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).")
    if item["category"] == "tooling":
        out.append("- Every emitted record must validate: `python scripts/validate_stream.py`.")
    out.append("- `python scripts/render_progress.py` must run clean after the queue edit.")
    out.append("")
    out.append(PROCEDURE)
    return "\n".join(out)


# ---------------------------------------------------------------- modules
def decl_names(body):
    out = []
    for f in re.findall(r"```neper\n(.*?)```", body, re.S):
        for line in f.splitlines():
            m = re.match(r"(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)", line.strip())
            if m:
                out.append(m.group(2))
    return out


VARIANTS = {"linux", "windows", "macos", "none", "x64", "x86", "aarch64", "spv", "ptx"}


def implemented_names():
    impl = {}
    for p in TRACKED:
        if not p.startswith("lib/e/") or not p.endswith(".e"):
            continue
        parts = p[len("lib/e/"):-2].replace("/", ".").split(".")
        if len(parts) > 1 and parts[-1] in VARIANTS:
            parts.pop()
        mod = "e." + ".".join(parts)
        impl.setdefault(mod, set()).update(
            m.group(2) for m in (re.match(r"(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)", l)
                                 for l in (ROOT / p).read_text(encoding="utf-8").splitlines()) if m)
    for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"', read("src/resolve.e")):
        impl.setdefault(mod, set()).add(nm)
    return impl


IMPL = implemented_names()

WAVES = roadmap_bullets("Later toolchain-library waves — unnumbered")


def wave_of(name):
    for b in WAVES:
        if "`%s`" % name in b:
            return b
    return ""


def grep_lines(rel, pattern, limit=12):
    out = []
    for i, line in enumerate(read(rel).splitlines(), 1):
        if pattern in line:
            out.append("`%s:%d` %s" % (rel, i, line.strip()[:140]))
            if len(out) >= limit:
                break
    return out


def siblings(name):
    d = Path(module_file_of(name)).parent.as_posix()
    files = [p for p in TRACKED if p.startswith(d + "/") and p.endswith(".e") and p.count("/") == d.count("/") + 1]
    return sorted(files)[:8]


def render_module(name, missing, total):
    m = modules[name]
    body = API_BLOCKS[name]
    out = []
    out.append("# %s — %d of %d declarations missing" % (name, len(missing), total))
    out.append("")
    out.append("| field | value |\n|---|---|")
    out.append("| file to create | `%s` |" % module_file_of(name))
    out.append("| plan row | layer %s, surface `%s`, milestone %s, schedule `%s` |" % (m["layer"], m["surface"], m["milestone"] or "none", m["schedule"]))
    out.append("| blocked by | %s |" % (", ".join("`%s`" % b for b in m["blocked_by"]) or "nothing recorded in `modules.json`"))
    unmet = [d for d in m["direct_dependencies"] if not (ROOT / module_file_of(d)).exists() and d not in ("e.os",)]
    out.append("| unmet dependencies | %s |" % (", ".join("`%s`" % d for d in unmet) or "none — every dependency has source"))
    out.append("")
    out.append("## Definition of done\n")
    out.append("Implement **exactly** the public fence below in `%s`; nothing more, nothing less, same spelling, same order. "
               "A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` "
               "row moves to `surface:\"source\"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template)."
               % module_file_of(name))
    if wave_of(name):
        out.append("\nRoadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):\n\n> " + wave_of(name))
    if m["blocked_by"]:
        out.append("\nBlockers named in the plan must be resolved first; a blocked module is not eligible. Search `docs/roadmap.md` and `docs/decisions.md` for each blocker id.")
    out.append("")
    out.append("## Dependencies\n")
    out.append(deps_table(m["direct_dependencies"]))
    out.append("\nThe module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer %s may depend on layers %s." %
               (m["layer"], next(l["may_depend_on"] for l in plan["layers"] if l["id"] == m["layer"])))
    out.append("")
    out.append("## Public API fence (verbatim from `docs/module-apis.md`)\n")
    out.append(body.strip())
    out.append("")
    out.append("## Missing declarations\n")
    for n in missing:
        out.append("- [ ] `%s`" % n)
    out.append("")
    refs = []
    for rel in ("docs/stdlib-hardening.md", "docs/ui-framework.md", "docs/algorithm-format-coverage.md", "docs/spec.md"):
        refs += grep_lines(rel, "`%s`" % name, 6)
    if refs:
        out.append("## Contracts that name this module\n")
        out.append("Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.\n")
        out.extend("- " + r for r in refs)
        out.append("")
    sib = siblings(name)
    if sib:
        out.append("## Style references\n")
        out.append("Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):\n")
        out.extend("- `%s`%s" % (s, size_note(s)) for s in sib)
        out.append("")
    out.append("## Verification\n")
    out.append("- `build/windows/tests/selfhost/neper-self.exe parse-file %s` prints `parse file ok`." % module_file_of(name))
    out.append("- A fixture `tests/selfhost/fixtures/link/%s/src/main.e` that prints one fixed line on success, registered in both runners." % name[2:].replace(".", "_"))
    out.append("- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.")
    out.append("- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by %d." % len(missing))
    out.append("")
    out.append(PROCEDURE.replace("Update this item's `score` and `evidence` in `docs/work-queue.json` (append the new\n   sentence to the evidence, keep the `Not yet:` clause truthful)",
                                 "Move the module's `surface` to `\"source\"` in `docs/modules.json`"))
    return "\n".join(out)


# ---------------------------------------------------------------- widgets
def proposal_lines(component):
    return grep_lines("docs/widget-library-proposal.md", component, 4)


def proposal_phase(phase_name):
    m = re.search(r"^### Phase \d — " + re.escape(phase_name.lower()) + r"\n(.*?)(?=^### |\Z)", proposal, re.S | re.M | re.I)
    return m.group(1).strip() if m else ""


def render_widget(phase, item):
    out = []
    out.append("# %s — %s (%d components)" % (item["id"], item["name"], len(item["components"])))
    out.append("")
    out.append("| field | value |\n|---|---|")
    out.append("| phase | %s — %s |" % (phase["id"], phase["name"]))
    out.append("| module | `%s` |" % item["module"])
    mod = modules.get(item["module"])
    if mod:
        out.append("| module surface | `%s`, layer %s, deps %s |" % (mod["surface"], mod["layer"], ", ".join("`%s`" % d for d in mod["direct_dependencies"])))
    else:
        out.append("| module surface | candidate identity — its fence is not yet in `module-apis.md`; Phase 0 freezes it before any source |")
    blockers = list(phase.get("blocked_by", [])) + list(item.get("blocked_by", []))
    out.append("| blocked by | %s |" % (", ".join("`%s`" % b for b in blockers) or "phase prerequisites only"))
    out.append("| delivered | %d of %d |" % (len(item["delivered"]), len(item["components"])))
    out.append("")
    out.append("## Eligibility\n")
    out.append("`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `%s`. "
               "An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. "
               "The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first." % WIDGET_NEXT)
    out.append("")
    out.append("## Definition of done\n")
    out.append("Every component below is implemented in `%s`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, "
               "recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. "
               "Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility)." % item["module"])
    ph = proposal_phase(phase["name"])
    if ph:
        out.append("\nPhase exit from the proposal:\n\n" + "\n".join("> " + l for l in ph.splitlines()))
    out.append("")
    out.append("## Components\n")
    for c in item["components"]:
        mark = "x" if c in item["delivered"] else " "
        out.append("- [%s] `%s`" % (mark, c))
        for l in proposal_lines(c)[:2]:
            out.append("  - " + l)
    out.append("")
    out.append("## Verification\n")
    out.append("- `python scripts/check_widget_plan.py` passes and `--next` moves past this item's components.")
    out.append("- `python tests/test_widget_plan.py` passes.")
    out.append("- Both self-host suites green; `docs/progress.html` regenerated.")
    out.append("")
    out.append(PROCEDURE.replace("Update this item's `score` and `evidence` in `docs/work-queue.json` (append the new\n   sentence to the evidence, keep the `Not yet:` clause truthful)",
                                 "Append the component to `delivered` and its sentence to `evidence` in `docs/widget-plan.json`"))
    return "\n".join(out)


# ---------------------------------------------------------------- roadmap-only milestones
MILESTONES = [
    ("M3-01", "M3 — GPU", "`@gpu(X, Y, Z)` profile enforcement", "@gpu profile enforcement, device types, address spaces, shared var"),
    ("M3-02", "M3 — GPU", "SPIR-V emitter", "SPIR-V emitter on the Vulkan 1.2 floor and the Vulkan compute runtime"),
    ("M3-03", "M3 — GPU", "CPU backend (spec §10, D38)", "CPU backend: workgroup-by-workgroup launch with barrier loop-fission"),
    ("M3-04", "M3 — GPU", "`e.gpu`: `Device`", "e.gpu runtime surface: Device, Queue, Buf[T], launch, sync, barriers, atomics, subgroups"),
    ("M3-05", "M3 — GPU", "Device selection: bounded `devices`", "Device selection: DeviceInfo/DeviceKind/DeviceKey, open_id, multi-device tests"),
    ("M3-06", "M3 — GPU", "Device-callable inference", "Device-callable inference into the kernel-owning module's .em"),
    ("M3-07", "M3 — GPU", "Floating point (spec §11, D39)", "GPU floating point: no contraction, math.fma only, denormals, ftz opt-in"),
    ("M3-08", "M3 — GPU", "determinism harness gains the device-reached", "Determinism harness: the device-reached edit case"),
    ("M4-01", "M4 — Breadth and depth", "aarch64 emitter", "aarch64 emitter (macOS, Linux, Windows on ARM)"),
    ("M4-02", "M4 — Breadth and depth", "x86-32 emitter", "x86-32 emitter"),
    ("M4-03", "M4 — Breadth and depth", "PTX emitter", "PTX emitter"),
    ("M4-04", "M4 — Breadth and depth", "Own linker, hard case", "Own linker, hard case: dynamic imports by name, Apple ad-hoc signing, PDB writer"),
    ("M4-05", "M4 — Breadth and depth", "neper-format debug side table", "neper-format debug side table in .em"),
    ("M4-06", "M4 — Breadth and depth", "Debug engine", "Debug engine: process control, breakpoints, stepping, stack walking"),
    ("M4-07", "M4 — Breadth and depth", "`neper dap`", "neper dap over the debug engine plus VS Code and Zed extensions"),
    ("M4-08", "M4 — Breadth and depth", "Optimiser depth", "Optimiser depth: inlining heuristics, load/store forwarding, scheduling"),
    ("M5-01", "M5 — Native Metal", "Metal backend", "Metal backend: MSL or AIR emitter plus a Metal runtime"),
    ("M5-02", "M5 — Native Metal", "Metal-only capabilities", "Metal-only capabilities on the GPU profile"),
    ("M6-01", "M6 — pacman package manager", "**P0, formats and resolution:**", "pacman P0: project.yaml subset, lock, SemVer, PubGrub resolution"),
    ("M6-02", "M6 — pacman package manager", "**P1, local and offline:**", "pacman P1: asset hashing, path dependencies, content-addressed cache, sync --frozen --offline"),
    ("M6-03", "M6 — pacman package manager", "**P2, remote sources:**", "pacman P2: signed registry protocol, Git dependencies, publish/yank"),
    ("M6-04", "M6 — pacman package manager", "**P3, generated inputs:**", "pacman P3: root-only tasks, capability approval, generated-source maps"),
    ("M6-05", "M6 — pacman package manager", "Portable CLI:", "pacman portable CLI with the toolchain's JSON conventions"),
    ("M6-06", "M6 — pacman package manager", "public namespace policy", "Namespace policy: e.* reserved, registry packages export x.<owner>.*"),
]

T2_SLICES = [
    ("T2-0", "Tooling v2 foundations (T2.0)", "1. **T2.0 — foundations:**"),
    ("T2-1", "Tooling v2 understand and check (T2.1)", "2. **T2.1 — understand and check:**"),
    ("T2-2", "Tooling v2 edit and test evidence (T2.2)", "3. **T2.2 — edit and test evidence:**"),
    ("T2-3", "Tooling v2 trusted verification, neper-agent-host (T2.3)", "4. **T2.3 — trusted verification:**"),
    ("T2-4", "Tooling v2 integration and durable operation (T2.4)", "5. **T2.4 — integration and durable operation:**"),
]

# Where the nearest existing implementation lives, for bullets whose text names no identifier.
RELATED = {
    "M3": ["src/nir.e", "src/lower.e", "src/codegen_x64.e", "lib/e/simd.e", "lib/e/thread.e", "docs/m25-gpu-contracts.md", "scripts/check_gpu_contracts.py"],
    "M4-01": ["src/emit_x64.e", "src/codegen_x64.e", "src/regalloc.e", "src/object_elf.e", "src/link_elf.e", "src/runtime_elf_x64.s"],
    "M4-02": ["src/emit_x64.e", "src/codegen_x64.e", "src/regalloc.e", "src/object_coff.e", "src/link_pe.e"],
    "M4-03": ["src/nir.e", "src/lower.e", "src/codegen_x64.e"],
    "M4-04": ["src/link_pe.e", "src/link_elf.e", "src/em_link.e", "src/object_coff.e"],
    "M4-05": ["src/em.e", "src/binary.e", "src/layout.e"],
    "M4-06": ["lib/e/proc.e", "lib/e/os.windows.e", "lib/e/os.linux.e", "src/disasm_x64.e"],
    "M4-07": ["src/tool.e", "src/main.e", "docs/tooling.md"],
    "M4-08": ["src/nir.e", "src/lower.e", "src/regalloc.e", "src/em_link.e"],
    "M5": ["src/nir.e", "src/lower.e"],
    "M6": ["docs/pacman.md", "src/project.e", "src/source.e", "docs/schemas/neper-v1.schema.json", "lib/e/fmt/yaml.e", "lib/e/crypto"],
    "T2": ["src/tool.e", "src/main.e", "docs/tooling.md", "docs/tooling-v2-draft.md", "docs/schemas/neper-v1.schema.json", "tests/conformance/tools"],
    "E2": ["benchmarks", "tests/test_llm_edit_benchmark.py", "docs/m2-baseline.md", "docs/general-purpose-verification.md"],
    "BL-01": ["src/main.e", "tests/conformance/tools/info_version"],
    "BL-02": ["src/check.e", "src/main.e"],
    "BL-03": ["docs/spec.md", "docs/modules.md", "docs/module-apis.md", "docs/tooling.md", "scripts/render_progress.py"],
    "BL-04": ["src/link_pe.e", "src/object_coff.e", "src/main.e"],
    "BL-05": ["src/link_pe.e", "src/main.e"],
    "BL-06": ["src/main.e", "lib/e/fs.e"],
    "BL-07": ["docs/grammar.ebnf", "scripts/render_card.py", "tests/conformance/tokens"],
}


def related_files(mid):
    for key in (mid, mid.split("-")[0]):
        if key in RELATED:
            return RELATED[key]
    return []

BACKLOG = [
    ("BL-01", "`--help` and `info` name every dispatched command", "**`--help` and `info`"),
    ("BL-02", "`neper eval EXPR` on the comptime interpreter", "**`neper eval EXPR`"),
    ("BL-03", "Call the standard library `e.lib`", "**Call the standard library"),
    ("BL-04", "Windows resources: `.rc` compiler and `.rsrc` linking", "**Windows resources"),
    ("BL-05", "`build --subsystem gui`", "**`build --subsystem gui`"),
    ("BL-06", "`run --watch`", "**`run --watch`"),
    ("BL-07", "A TextMate grammar", "**A TextMate grammar"),
]


def numbered_item(section, prefix):
    text = roadmap_section(section)
    m = re.search(r"^" + re.escape(prefix) + r"(.*?)(?=^\d+\. \*\*|\n\n[A-Z]|\Z)", text, re.S | re.M)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else ""


def spec_pointers(text):
    """Spec sections named as `spec §N` in a bullet, resolved to headings, subheadings and lines."""
    rows = []
    lines = read("docs/spec.md").splitlines()
    for n in sorted({int(x) for x in re.findall(r"spec §(\d+)", text)}):
        inside = False
        for i, l in enumerate(lines, 1):
            if l.startswith("## "):
                inside = l.startswith("## %d." % n)
                if inside:
                    rows.append("- `docs/spec.md:%d` %s" % (i, l[3:]))
            elif inside and l.startswith("### "):
                rows.append("  - `docs/spec.md:%d` %s" % (i, l[4:]))
    return rows


def render_milestone(mid, title, body, section, done_when, module_refs, extra=""):
    out = ["# %s — %s" % (mid, title), ""]
    out.append("| field | value |\n|---|---|")
    out.append("| roadmap section | %s |" % section)
    out.append("| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |")
    out.append("| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |")
    out.append("")
    out.append("## Definition of done\n")
    out.append("> " + body)
    if done_when:
        out.append("\n" + done_when)
    if extra:
        out.append("\n" + extra)
    sp = spec_pointers(body)
    if sp:
        out.append("\n## Spec sections\n")
        out.extend(sp)
    dec = decisions_of(body)
    if dec:
        out.append("\n## Decisions to read first\n")
        out.extend(dec)
    if module_refs:
        out.append("\n## Module fences this bullet delivers\n")
        for name in module_refs:
            out.append("- `%s` — `docs/tasks/modules/%s.md`" % (name, name))
    anch = anchors(body, limit_tokens=16)
    rel = related_files(mid)
    if anch or rel:
        out.append("\n## Code anchors\n")
        for tok, hits in anch:
            out.append("- `%s`: " % tok + ", ".join("`%s`×%d%s" % (p, n, size_note(p)) for p, n in hits))
        if rel:
            out.append("- nearest existing implementation: " + ", ".join("`%s`%s" % (r, size_note(r)) for r in rel)
                       + " († over 40 KB, ‡ over 120 KB — read by region)")
    out.append("\n## First session\n")
    out.append("1. Read the spec sections and decisions above in full.")
    out.append("2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: \"\"`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.")
    out.append("3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.")
    out.append("4. Then follow README §Session procedure for the first capability.")
    return "\n".join(out)


# ---------------------------------------------------------------- README
TRAPS = """## Repository traps

Recorded from earlier sessions; each one cost hours. Check them before blaming the change.

- **Two compilers, two truths.** `build/windows/neper.exe` (or `build/linux/neper`) is the C bootstrap: more permissive than the language. `neper-self` is the self-hosted compiler and the only one whose verdict counts. A clean bootstrap build proves nothing. `MAX_LOCALS 256` and `MAX_DECLS` in `bootstrap/neper.c` are program-wide and near full: a new compiler file can silently truncate or refuse. Keep new compiler code small; do not raise the limits without measuring memory.
- **Reserved local names.** `target`, `shared` and a local shadowing a module-scope `fn` pass the bootstrap and kill `neper-self` (`ModuleShadow`). Do not name locals after modules, module-scope functions or keywords.
- **Capacities sit at their limit.** The arena (`--arena 1g` for the compiler), bootstrap tokens and resolver tokens have each been full before; a diagnostic blaming your change may be a full table. `MAX_TRAP_SITES` full surfaced as a bare `E-LINK-9999`.
- **Never edit `src/` while a suite runs.** Stage 2 fails silently. Never run both suites at once.
- **Byte-equality needs the same cwd and operand.** `--arena` is baked at emit time; stage 2 must equal stage 3 byte for byte, so an added global or a changed `--arena` breaks the fixed point.
- **A debug edit that fails to compile leaves the OLD binary answering.** Check `$LASTEXITCODE` / `$?` of the build before trusting a run.
- **Fixtures cap at about 450 statements** per function under the bootstrap frame sizing; split large fixtures.
- **Launch WSL from PowerShell**, never from Git Bash (it rewrites `/mnt/d/...`). `run.sh` fails silently on some errors; run `bash -x` when a step's output is missing.
- **Commit with explicit pathspecs.** The working tree is shared with other sessions; the index may carry their staged deletions. Never `git add -A` or `git add .`. Check `git status` before staging.
- **Generics.** An instance over a still-generic instance is not concrete (D163); both substituters must claim their argument block before recursing; a `T`-typed value's `==` is `T.eq`, a struct has no fallback `eq`. Diagnose `E-TYPE-0002` with a temporary debug print of both types, not theory.
- **Narrow extern returns.** A foreign `i32` return read unwidened made every `< 0` check pass silently; test the sign, not only equality.
- **Artifacts.** Every `em.artifact_*` reader CRC-validates — never call one in a loop. The root artifact must be named first to the linker.
- **Format synthesises a function per call shape** (`format`); comptime `Field`/`Member` values ride in generic arguments and only ever stand as a `for` subject.
- **The C bootstrap ignores module variants** (`os.linux.e`, `os.windows.e`); its fixed `e.os` surface is what `src/resolve.e` seeds — add new OS intrinsics there.
- **Big literals go in strings**; untyped float literals inside generics do not infer; `ret (a, b)` needs the parentheses; a `Builder` holds the arena top.
- **Windows Defender** quarantines a PE under about 2 KB that imports only `VirtualAlloc`+`ExitProcess` (D152); the Windows entry keeps its command-line parser on purpose.
"""

FIXTURE_TEMPLATE = r"""## Fixture template

A library or link fixture is a program root that prints one fixed line and exits 0. Register it in **both** runners, next to its neighbours.

`tests/selfhost/fixtures/link/<name>/src/main.e`:

```neper
use e.io
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    // arrange, act, then one check per behaviour:
    if 1 + 1 != 2 { ret Failed }
    io.print("<name> ok\n")
}
```

`tests/selfhost/run.ps1` (Windows):

```powershell
$nameExecutablePath = Join-Path $testBuild '<name>-selfhost.exe'
$nameWritten = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\link\<name>\src\main.e') $repo 'x64' 'windows' $nameExecutablePath
if ($LASTEXITCODE -ne 0 -or $nameWritten -ne 'executable written') { throw '<name> did not compile' }
$nameOutput = & $nameExecutablePath
if ($LASTEXITCODE -ne 0 -or $nameOutput -ne '<name> ok') { throw '<name> failed' }
```

`tests/selfhost/run.sh` (Linux):

```bash
name_executable_path="$test_build/<name>-selfhost"
name_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/<name>/src/main.e" "$repo" x64 linux "$name_executable_path")
[ "$name_written" = 'executable written' ]
chmod +x "$name_executable_path"
name_output=$("$name_executable_path")
[ "$name_output" = '<name> ok' ]
```

A check (diagnostic) fixture lives under `tests/selfhost/fixtures/check/<name>` and is compared against a golden diagnostic line; copy an existing neighbour's runner block. A tooling fixture lives under `tests/conformance/<command>/` with its `.jsonl` golden, validated by `python scripts/validate_stream.py`.
"""


def render_readme(index):
    out = []
    out.append("# Neper — every feature left to implement\n")
    out.append("Generated by `scripts/render_tasks.py`; do not edit by hand. One file per unfinished feature, "
               "written so that a local model with a bounded context can implement it without the history of earlier sessions. "
               "Four inventories, each derived from the repository's machine-readable plans:\n")
    out.append("| directory | source of truth | count |\n|---|---|---|")
    for d, src, n in index["counts"]:
        out.append("| `%s/` | %s | %d |" % (d, src, n))
    out.append("")
    out.append("""## The model this is written for

PrismML **Bonsai 2 27B** (a ternary-quantised Qwen3.8-27B, 1.76 bits per weight, about 6–8.5 GB on disk, 262,144-token context, thinking on by default with `thinking_budget_tokens`, OpenAI-style tool calling; GGUF needs PrismML's `llama.cpp` fork, stock builds refuse or miscompute). Sources: [docs.prismml.com/bonsai-2-27b](https://docs.prismml.com/bonsai-2-27b.md), [Bonsai 27B](https://docs.prismml.com/models/bonsai-27b). It is a capable but not frontier model, so every file here assumes:

- **One checklist line per session.** Files list the remaining work as lines; take the first unchecked one. The queue's own `model`/`thinking` rating is shown as a difficulty; `very high` lines may need to be split again by hand.
- **Context is the budget.** `src/check.e` (844 KB), `src/main.e` (554 KB), `src/lower.e` (441 KB), `src/tool.e` (338 KB) and `docs/decisions.md` (1 MB) do not fit. Every file here gives `file:line` anchors; read with `git grep -n` and `sed -n 'A,Bp'`, never whole files over 120 KB. Keep the working set under ~60K tokens so thinking has room.
- **Thinking budget unlimited (`-1`) for compiler items, `xhigh` effort;** `medium` is enough for a library module against a frozen fence.
- **The language card is `docs/llm-neper-card.md`** (grammar revision 3, generated). Read it before writing any neper. Neper is not Rust, Zig or C: no implicit conversions, `(value, err)` returns, `ret` not `return`, `err`/`try`/`ok`, arena-first parameters, `use e.x as x`.
- **Never trust prose over tools.** `docs/progress.html`, `work-queue.json`, `modules.json`, `widget-plan.json` and the fixtures are the truth; `implementation-handoff.md` is a historical snapshot.
- **Give it a tool loop, not a chat.** Run it through an agent harness with shell, read, edit and search tools against this checkout; paste the task file as the first user message and `docs/llm-neper-card.md` as the second. Ask it to stop and report after the fixture passes on one host rather than continuing.

## Running the driver

`scripts/bonsai_driver.py` runs one task per session with four tools (`read_lines`, `search`, `edit`, `run`), then gates on both suites and commits the touched paths or reverts them. It talks to any OpenAI-compatible server with `--endpoint`, or to LM Studio's SDK without it.

Bonsai needs PrismML's llama.cpp fork (LM Studio's stock runtime crashes on its quant types). Prebuilt Windows binaries: <https://github.com/PrismML-Eng/llama.cpp/releases> — the CUDA **12.4** build plus its `cudart-…-cuda-12.4` runtime zip for an NVIDIA driver in the 5xx series (the 13.3 build needs a 580+ driver), or the CPU build without a GPU. The model: <https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf> (`PQ2_0`, 7.2 GB).

Measured on an RTX 3080 Laptop GPU (16 GB): loads in 11 s, 330 tok/s prompt, 37 tok/s generation at a 128K context with an 8-bit KV cache (12 GB VRAM). The fork's RAM prompt cache crashes the server on the second request, so it is disabled below. CPU-only on an Iris Xe box runs but at about 1 tok/s, unusable for sessions.

```powershell
D:/tools/prism-llama-cu12/llama-server.exe -m D:/tools/models/Ternary-Bonsai-2-27B-PQ2_0.gguf -c 131072 -ngl 99 -np 1 -fa on -ctk q8_0 -ctv q8_0 --cache-ram 0 --slot-prompt-similarity 0 --cache-reuse 0 --jinja --port 8080
python scripts/bonsai_driver.py --endpoint http://localhost:8080/v1 --dry-run --kind all   # which task would run
python scripts/bonsai_driver.py --endpoint http://localhost:8080/v1 --kind modules --max-tasks 3
python scripts/bonsai_driver.py --endpoint http://localhost:8080/v1 --kind queue           # the queue head's first unchecked line
```

Selection: `modules` = no `blocked_by`, every dependency on disk, not an M3+ module, lowest layer first; `queue` = position 1 only; `ui/` and `milestones/` are never selected (blocked, or need a human-added queue row). A task that fails twice is skipped; state and transcripts live under `build/bonsai/`. The tree must be clean (`git status`) before a session.

## Repository rules (from `CLAUDE.md`)

1. Work only on the **first** item of `docs/work-queue.json`. Keep it first while partial; at score 1 remove it and append the record as one JSON line to `docs/work-done.jsonl`.
2. After every landed capability run `python scripts/render_progress.py` and commit `docs/progress.html` with the implementation. Never hand-edit it.
3. Append design decisions to `docs/decisions.md` as `## D<n> — <title>`; never rewrite earlier rows.
4. The working tree is shared: commit only touched paths, check `git status` first, never overwrite a file another session changed.

The module and UI inventories are outside the queue's serial rule; a module whose dependencies exist and whose `blocked_by` is empty may be taken by a session that is not the queue's. `python scripts/check_widget_plan.py --next` names the only eligible UI component.

## Build and verify

```powershell
# Windows: bootstrap, self-host, then the whole Windows suite (about 20–30 minutes; never run both suites at once)
& tests/selfhost/run.ps1
```

```powershell
# Linux suite through WSL — launch from PowerShell, not Git Bash
wsl -d Ubuntu-24.04 -- bash /mnt/d/repos/neper/tests/selfhost/run.sh
```

```powershell
# Fast inner loop: build stage 1 only (the C bootstrap), then the self-hosted compiler
& scripts/build-bootstrap.ps1
& build/windows/neper.exe build src/main.e --arena 1g --output build/windows/tests/selfhost/neper-self.exe
```

```powershell
# One fixture with the self-hosted compiler
& build/windows/tests/selfhost/neper-self.exe emit-executable tests/selfhost/fixtures/link/<name>/src/main.e . x64 windows build/<name>.exe
& build/<name>.exe
```

Other checks: `python scripts/validate_stream.py` (every JSONL golden against `docs/schemas/neper-v1.schema.json`), `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os windows`, `python tests/test_module_plan.py`, `python scripts/check_widget_plan.py`, `git diff --check`.

## Adding a queue row

A `milestones/` file has no queue row. Its first session adds one to `docs/work-queue.json`: `{"id": "C0nn", "category": "compiler"|"tooling", "group": ..., "order": n, "title": ..., "score": 0, "model": ..., "thinking": ..., "evidence": ""}`, placed after the existing rows of its group, with a decision row that records the split. `render_progress.py` validates the shape.

""")
    out.append(TRAPS)
    out.append(FIXTURE_TEMPLATE)
    out.append("## Index\n")
    for heading, rows in index["sections"]:
        out.append("### " + heading + "\n")
        out.append("| file | title | status |\n|---|---|---|")
        for rel, title, status in rows:
            out.append("| [`%s`](%s) | %s | %s |" % (rel, rel, title, status))
        out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------- main
def main():
    global WIDGET_NEXT
    WIDGET_NEXT = subprocess.run([sys.executable, "scripts/check_widget_plan.py", "--next"],
                                 capture_output=True, text=True, cwd=ROOT).stdout.strip().splitlines()[-1]
    if OUT.exists():
        for p in OUT.rglob("*.md"):
            p.unlink()
    index = {"counts": [], "sections": []}

    comp, tool = [], []
    for pos, item in enumerate(queue, 1):
        rel = "%s/%s-%s.md" % (item["category"], item["id"], slug(item["title"]))
        write(rel, render_queue_item(item, pos))
        row = (rel, item["title"], "score %.2f, queue #%d" % (float(item["score"]), pos))
        (comp if item["category"] == "compiler" else tool).append(row)
    index["counts"].append(("compiler", "`docs/work-queue.json` rows with `category: compiler`", len(comp)))
    index["counts"].append(("tooling", "`docs/work-queue.json` rows with `category: tooling`", len(tool)))
    index["sections"].append(("Compiler (queue order)", comp))
    index["sections"].append(("Tooling (queue order)", tool))

    mods = []
    for name, body in API_BLOCKS.items():
        decls = decl_names(body)
        missing = [n for n in decls if n not in IMPL.get(name, set())]
        if missing:
            write("modules/%s.md" % name, render_module(name, missing, len(decls)))
            m = modules[name]
            unmet = [d for d in m["direct_dependencies"] if not (ROOT / module_file_of(d)).exists() and d != "e.os"]
            status = "%d/%d missing" % (len(missing), len(decls))
            if m["blocked_by"]:
                status += "; blocked by " + ", ".join(m["blocked_by"])
            if unmet:
                status += "; needs " + ", ".join(unmet)
            mods.append(("modules/%s.md" % name, "layer %s, %s" % (m["layer"], m["milestone"] or "later"), status))
    mods.sort(key=lambda r: (modules[r[0][8:-3]]["layer"], r[0]))
    index["counts"].append(("modules", "`docs/module-apis.md` fences with a declaration absent from `lib/e`", len(mods)))
    index["sections"].append(("Modules (by layer — lower layers first, they unblock the rest)", mods))

    ui = []
    for phase in widget_plan["phases"]:
        for item in phase["items"]:
            if len(item["delivered"]) < len(item["components"]):
                rel = "ui/%s-%s.md" % (item["id"], slug(item["name"]))
                write(rel, render_widget(phase, item))
                blk = ", ".join(list(phase.get("blocked_by", [])) + list(item.get("blocked_by", [])))
                ui.append((rel, "%s — %s" % (phase["id"], item["name"]), "%d/%d delivered%s" % (len(item["delivered"]), len(item["components"]), "; blocked by " + blk if blk else "")))
    index["counts"].append(("ui", "`docs/widget-plan.json` items with an undelivered component", len(ui)))
    index["sections"].append(("UI and host integration (plan order)", ui))

    ms = []
    missing_modules = {r[0][8:-3] for r in mods}
    for mid, section, keyword, title in MILESTONES:
        body = roadmap_bullet(section, keyword)
        mods_named = [n for n in dict.fromkeys(re.findall(r"`(e\.[a-z_.]+)`", body)) if n in missing_modules]
        extra = ""
        if mid.startswith("M3"):
            mods_named = list(dict.fromkeys(mods_named + ["e.gpu"]))
            extra = ("M2.5 froze the contracts this bullet implements: `docs/m25-gpu-contracts.md` and `docs/m25-gpu-contracts.json` "
                     "(checked by `python scripts/check_gpu_contracts.py` and `tests/test_gpu_contracts.py`), `docs/m25-gpu-closure.md`. "
                     "A device runtime test may not be reported as passing on a CPU mock. `libvulkan` needs M4's dynamic-import linking; "
                     "until then a Vulkan program links with `--linker=system`.")
        if mid.startswith("M6"):
            extra = "The normative design is `docs/pacman.md`; the `packageManifest` shape is already in `docs/schemas/neper-v1.schema.json`."
        if mid in ("M4-04", "M4-05", "M4-06", "M4-07"):
            extra = "Predecessor: queue item C084 (`docs/tasks/compiler/`) delivers the M1 debug subset this builds on."
        rel = "milestones/%s-%s.md" % (mid, slug(title))
        write(rel, render_milestone(mid, title, body, section, roadmap_done_when(section), mods_named, extra))
        ms.append((rel, title, section))
    t2 = roadmap_section("T2 — agent tooling v2")
    for mid, title, prefix in T2_SLICES:
        body = numbered_item("T2 — agent tooling v2", prefix)
        hs = sorted(set(re.findall(r"H\d\d", body)))
        extra = "Requirements: " + ", ".join("`%s` — %s (`docs/post-m2-llm-hardening.md`)" % (h, HSECTIONS[h][0]) for h in hs if h in HSECTIONS)
        extra += "\n\nThe v1 precursors already in the queue (`docs/tasks/compiler/`, titles ending 'precursor for T2 Hxx') are inputs to this slice, not its closure. `docs/tooling-v2-draft.md` is the protocol draft; `docs/hardening-tracks.json` carries the track status."
        rel = "milestones/%s-%s.md" % (mid, slug(title))
        write(rel, render_milestone(mid, title, body, "T2 — agent tooling v2", roadmap_done_when("T2 — agent tooling v2"), [], extra))
        ms.append((rel, title, "T2 — agent tooling v2"))
    e2 = roadmap_section("E2 — measured LLM-experience claim gate")
    rel = "milestones/E2-measured-llm-experience-claim-gate.md"
    write(rel, render_milestone("E2", "Measured LLM-experience claim gate", re.sub(r"\s+", " ", e2.split("**Done when:**")[0]).strip(),
                                "E2 — measured LLM-experience claim gate", roadmap_done_when("E2 — measured LLM-experience claim gate"), [],
                                "Requirements: " + ", ".join("`%s` — %s" % (h, HSECTIONS[h][0]) for h in ("H12", "H20", "H25", "H33", "H43") if h in HSECTIONS)))
    ms.append((rel, "Measured LLM-experience claim gate", "E2"))
    for mid, title, prefix in BACKLOG:
        body = roadmap_bullet("Backlog — recorded, not scheduled", prefix)
        rel = "milestones/%s-%s.md" % (mid, slug(title))
        write(rel, render_milestone(mid, title, body, "Backlog — recorded, not scheduled", "", []))
        ms.append((rel, title, "Backlog"))
    index["counts"].append(("milestones", "`docs/roadmap.md` M3–M6, T2 slices, E2 and backlog bullets without a queue row", len(ms)))
    index["sections"].append(("Milestones without a queue row (roadmap order)", ms))

    write("README.md", render_readme(index))
    total = sum(n for _, _, n in index["counts"])
    print("wrote docs/tasks: %d task files + README" % total)


if __name__ == "__main__":
    main()
