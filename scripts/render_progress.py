# -*- coding: utf-8 -*-
"""Render the four headline readiness metrics to docs/progress.html.

Usage:  python scripts/render_progress.py     (from the repository root)

The page intentionally renders only four computed readiness metrics. Compiler and
tooling scores come from the active queue plus the completed ledger; module and
UI/host scores come from their machine-readable inventories.
"""
import json, re, subprocess, datetime
from pathlib import Path

from check_widget_plan import validate as validate_widget_plan
# Compiler/tooling readiness is data, not renderer code. The unfinished rows are
# ordered for serial feature pickup; delivered rows are kept out of fresh-session context.
WORK_QUEUE = Path("docs/work-queue.json")
WORK_DONE = Path("docs/work-done.jsonl")


def load_work_rows():
    queue_doc = json.loads(WORK_QUEUE.read_text(encoding="utf-8"))
    if queue_doc.get("schema") != "neper-work-queue-v1" or queue_doc.get("version") != 1:
        raise SystemExit("docs/work-queue.json: unsupported schema or version")

    tagged = [(item, False) for item in queue_doc.get("items", [])]
    for line_no, line in enumerate(WORK_DONE.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                tagged.append((json.loads(line), True))
            except json.JSONDecodeError as error:
                raise SystemExit(f"docs/work-done.jsonl:{line_no}: {error.msg}") from error

    seen = set()
    rows = []
    for item, delivered in tagged:
        required = {"id", "category", "group", "order", "title", "score", "evidence"}
        missing = required - item.keys()
        if missing:
            raise SystemExit(f"work item missing {sorted(missing)}")
        if item["id"] in seen:
            raise SystemExit("duplicate work item: " + item["id"])
        seen.add(item["id"])
        score = float(item["score"])
        if not 0 <= score <= 1 or delivered != (score == 1):
            raise SystemExit("work item is in the wrong file: " + item["id"])
        if item["category"] not in {"compiler", "tooling"}:
            raise SystemExit("invalid work item category: " + item["id"])
        rows.append(item)

    compiler_rows, tooling_rows = {}, []
    for item in sorted(rows, key=lambda row: (row["category"], row["order"])):
        row = (item["title"], float(item["score"]), item["evidence"])
        if item["category"] == "compiler":
            compiler_rows.setdefault(item["group"], []).append(row)
        else:
            tooling_rows.append(row)
    return compiler_rows, tooling_rows


compiler, tooling = load_work_rows()


# Stamp the last commit that touched what this page measures, not HEAD. Stamping
# HEAD would make the page differ from itself the moment it is committed, so every
# later run would show a spurious diff. Taking that commit's own date as well keeps
# the output a pure function of its inputs.
INPUTS = ['src', 'lib', 'docs/module-apis.md', 'docs/widget-plan.json']
stamp = subprocess.run(['git', 'log', '-1', '--format=%h %cs', '--'] + INPUTS,
                       capture_output=True, text=True).stdout.split()
rev, when = (stamp + ['unknown', str(datetime.date.today())])[:2]

# ---- module numbers, recomputed here so the page cannot drift from the plan ----
txt = open('docs/module-apis.md', encoding='utf-8').read()
blocks = dict(re.findall(r'^### `([^`]+)`\n(.*?)(?=^### |\Z)', txt, re.S | re.M))


def decl_names(body):
    out = []
    for f in re.findall(r'```neper\n(.*?)```', body, re.S):
        for line in f.splitlines():
            m = re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', line.strip())
            if m:
                out.append(m.group(2))
    return out


tracked = set(subprocess.run(['git', 'ls-files', 'lib/e'],
                             capture_output=True, text=True).stdout.split())
# `lib/e/os.linux.e` is `e.os`, not a module called `e.os.linux`: a per-target variant
# is one of the files a module may be written in (spec 2), so the trailing arch or os
# is not part of the name and the variants union into one surface.
VARIANTS = {'linux', 'windows', 'macos', 'none', 'x64', 'x86', 'aarch64', 'spv', 'ptx'}
impl = {}
for p in tracked:
    if not p.endswith('.e'):
        continue
    parts = p[len('lib/e/'):-2].replace('/', '.').split('.')
    if len(parts) > 1 and parts[-1] in VARIANTS:
        parts.pop()
    mod = 'e.' + '.'.join(parts)
    impl.setdefault(mod, set()).update(
        m.group(2) for m in
        (re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', l)
         for l in open(p, encoding='utf-8')) if m)

seeded = {}
for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"',
                          open('src/resolve.e', encoding='utf-8').read()):
    seeded.setdefault(mod, set()).add(nm)

dtot = dgot = 0
for mod, body in blocks.items():
    declarations = decl_names(body)
    present = impl.get(mod, set()) | seeded.get(mod, set())
    dtot += len(declarations)
    dgot += sum(1 for name in declarations if name in present)

widget_plan, widget_errors = validate_widget_plan(Path('.'))
if widget_errors:
    raise SystemExit('\n'.join(widget_errors))
wgot = sum(len(item['delivered'])
           for phase in widget_plan['phases'] for item in phase['items'])
wtot = sum(len(item['components'])
           for phase in widget_plan['phases'] for item in phase['items'])

c_sum = sum(score for group in compiler.values() for _, score, _ in group)
c_n = sum(len(group) for group in compiler.values())
t_sum = sum(score for _, score, _ in tooling)
t_n = len(tooling)
C, M, W, T = (100 * c_sum / c_n, 100 * dgot / dtot,
              100 * wgot / wtot, 100 * t_sum / t_n)


def previous_percentages(path):
    """Read the last generated KPI values and their displayed deltas."""
    if not path.exists():
        return {}
    text = path.read_text(encoding='utf-8')
    pairs = re.findall(
        r'<div class="tile"[^>]*><div class="lab">([^<]+)</div>'
        r'<div class="val">([0-9]+(?:\.[0-9]+)?)<span class="pc">%</span>'
        r'(?:<span class="delta [^"]+"[^>]*>([+-][0-9]+(?:\.[0-9]+)?) pp</span>)?',
        text,
    )
    return {label: (float(value), float(delta or 0.0))
            for label, value, delta in pairs}


progress_path = Path('docs/progress.html')
previous = previous_percentages(progress_path)


def meter(label, pct, sub):
    old_pct, old_delta = previous.get(label, (pct, 0.0))
    delta = old_delta if round(pct, 2) == round(old_pct, 2) else pct - old_pct
    if abs(delta) < 0.005:
        delta = 0.0
    delta_class = 'up' if delta > 0.004 else 'down' if delta < -0.004 else 'flat'
    return ('<div class="tile"><div class="lab">' + label + '</div>'
            '<div class="val">' + ('%.2f' % pct) + '<span class="pc">%</span>'
            '<span class="delta ' + delta_class + '">' + ('%+.2f pp' % delta)
            + '</span></div><div class="track" role="img" aria-label="' + label
            + ': ' + ('%.2f' % pct) + ' percent complete"><i style="width:'
            + ('%.1f' % pct) + '%"></i></div><div class="sub">' + sub + '</div></div>')


kpi = '\n'.join([
    meter('Compiler', C, '%.2f of %d capabilities' % (c_sum, c_n)),
    meter('Modules', M, '%d of %d declarations' % (dgot, dtot)),
    meter('UI and host integration', W, '%d of %d capabilities' % (wgot, wtot)),
    meter('Tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
])

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neper readiness</title>
<style>
:root{color-scheme:light dark;--bg:#fff;--panel:#f5f7fa;--ink:#111827;--muted:#667085;--track:#d8e1ee;--fill:#245aa8;--rule:#e4e7ec}
@media(prefers-color-scheme:dark){:root{--bg:#0f1319;--panel:#171d26;--ink:#e8edf4;--muted:#9aa7b5;--track:#293444;--fill:#8fb0e6;--rule:#29313d}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:64rem;margin:auto;padding:clamp(2rem,6vw,5rem) 1.25rem}header{margin-bottom:2rem}.eyebrow,.sub,footer{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace}
.eyebrow{margin:0 0 .5rem;color:var(--muted);font-size:.75rem;letter-spacing:.14em;text-transform:uppercase}h1{margin:0;font-size:clamp(2rem,5vw,3.5rem);line-height:1.1}
.kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(13rem,1fr));gap:1rem}.tile{padding:1.25rem;border:1px solid var(--rule);border-radius:.75rem;background:var(--panel)}
.lab{color:var(--muted);font-size:.85rem;font-weight:600}.val{margin:.35rem 0;font-size:2.65rem;font-weight:700;line-height:1;font-variant-numeric:tabular-nums}.pc{font-size:1.2rem;color:var(--muted)}
.delta{margin-left:.5rem;font:600 .72rem ui-monospace,"Cascadia Mono",Consolas,monospace}.delta.up{color:#168052}.delta.down{color:#c4322b}.delta.flat{color:var(--muted)}
.track{height:.5rem;margin:.8rem 0;background:var(--track);border-radius:1rem;overflow:hidden}.track i{display:block;height:100%;background:var(--fill);border-radius:inherit}.sub{color:var(--muted);font-size:.75rem}
.method,footer{color:var(--muted);font-size:.8rem}.method{margin:1.5rem 0 0}.method a{color:inherit}footer{margin-top:2rem;padding-top:1rem;border-top:1px solid var(--rule)}
</style>
</head>
<body>
<main>
<header><p class="eyebrow">neper</p><h1>Readiness</h1></header>
<section class="kpi" aria-label="Project readiness metrics">
__KPI__
</section>
<p class="method">Compiler and tooling use the <a href="work-queue.json">active queue</a>
and <a href="work-done.jsonl">completion ledger</a>; module and UI totals are computed
from their machine-readable plans and committed source.</p>
<footer>Generated by <code>scripts/render_progress.py</code> at
<code>__REV__</code> (__DATE__).</footer>
</main>
</body>
</html>
"""
html = html.replace('__KPI__', kpi).replace('__REV__', rev).replace('__DATE__', when)
progress_path.write_text(html, encoding='utf-8', newline='\n')
print('wrote docs/progress.html')
print('compiler %.2f  modules %.2f  ui-host %.2f  tooling %.2f' % (C, M, W, T))
