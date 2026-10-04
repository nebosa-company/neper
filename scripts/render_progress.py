# -*- coding: utf-8 -*-
"""Render readiness, the charting plan, and the unfinished backlog.

Usage:  python scripts/render_progress.py     (from the repository root)

Compiler, tooling and library scores come from the active queue plus the
completed ledger; module and UI/host scores come from their inventories.
"""
import json, re, subprocess, datetime, html
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
        if item["category"] not in {"compiler", "tooling", "library"}:
            raise SystemExit("invalid work item category: " + item["id"])
        rows.append(item)

    compiler_rows, tooling_rows, library_rows = {}, [], []
    for item in sorted(rows, key=lambda row: (row["category"], row["order"])):
        row = (item["title"], float(item["score"]), item["evidence"])
        if item["category"] == "compiler":
            compiler_rows.setdefault(item["group"], []).append(row)
        elif item["category"] == "tooling":
            tooling_rows.append(row)
        else:
            library_rows.append(row)
    return compiler_rows, tooling_rows, library_rows


compiler, tooling, library = load_work_rows()


# Stamp the last commit that touched what this page measures, not HEAD. Stamping
# HEAD would make the page differ from itself the moment it is committed, so every
# later run would show a spurious diff. Taking that commit's own date as well keeps
# the output a pure function of its inputs.
INPUTS = ['src', 'lib', 'docs/module-apis.md', 'docs/widget-plan.json', 'docs/algos.md']
stamp = subprocess.run(['git', 'log', '-1', '--format=%h %ct', '--'] + INPUTS,
                       capture_output=True, text=True).stdout.split()
rev, seconds = (stamp + ['unknown', ''])[:2]
# That commit's time in this machine's local time, with its offset from UTC.
moment = datetime.datetime.fromtimestamp(int(seconds)).astimezone() if seconds else datetime.datetime.now().astimezone()
offset = moment.strftime('%z')
when = '%s UTC%s:%s' % (moment.strftime('%Y-%m-%d %H:%M:%S'), offset[:3], offset[3:])

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

# The selected algorithms (docs/algos.md, D834): every entry annotated with a
# library function is one more declaration the library owes until that function
# exists, whether its module is fenced yet or not. Duplicates of one function
# count once.
planned = {}
for mod, fn in re.findall(r'→ `(e\.[A-Za-z0-9_.]+)\.([A-Za-z_][A-Za-z0-9_]*)`',
                          open('docs/algos.md', encoding='utf-8').read()):
    planned.setdefault(mod, set()).add(fn)
algos_total = sum(len(fns) for fns in planned.values())
algos_missing = 0
for mod, fns in planned.items():
    present = impl.get(mod, set()) | seeded.get(mod, set())
    if mod in blocks:
        present |= set(decl_names(blocks[mod]))
    algos_missing += sum(1 for fn in fns if fn not in present)
dtot += algos_missing

widget_plan, widget_errors = validate_widget_plan(Path('.'))
if widget_errors:
    raise SystemExit('\n'.join(widget_errors))
# A phase marked for the next release is planned, not owed by this one.
current_phases = [phase for phase in widget_plan['phases'] if phase.get('release') != 'next']
wgot = sum(len(item['delivered']) for phase in current_phases for item in phase['items'])
wtot = sum(len(item['components']) for phase in current_phases for item in phase['items'])

c_sum = sum(score for group in compiler.values() for _, score, _ in group)
c_n = sum(len(group) for group in compiler.values())
t_sum = sum(score for _, score, _ in tooling)
t_n = len(tooling)
l_sum = sum(score for _, score, _ in library)
l_n = len(library)
C, M, W, T, L = (100 * c_sum / c_n, 100 * dgot / dtot,
                 100 * wgot / wtot, 100 * t_sum / t_n,
                 100 * l_sum / l_n if l_n else 100.0)


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
    meter('Modules', M, '%d of %d declarations, %d of %d selected algorithms' % (dgot, dtot, algos_total - algos_missing, algos_total)),
    meter('UI and host integration', W, '%d of %d capabilities' % (wgot, wtot)),
    meter('Tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
    meter('Library', L, '%.2f of %d capabilities' % (l_sum, l_n)),
])

# Keep the chart catalogue in its maintained Markdown source. The readiness
# page links to a generated chart guide and shows the unfinished queue.
chart_plan = Path('docs/charting-engine-plan.md').read_text(encoding='utf-8')
queue_items = json.loads(WORK_QUEUE.read_text(encoding='utf-8'))['items']
chart_item = next((item for item in queue_items if item['id'] == 'L061'), None)
if chart_item is None:
    for line in WORK_DONE.read_text(encoding='utf-8').splitlines():
        if line.strip():
            item = json.loads(line)
            if item['id'] == 'L061':
                chart_item = item
                break
if chart_item is None:
    raise SystemExit('L061 missing from work queue and completion ledger')
backlog = '\n'.join(
    '<tr><td><code>{id}</code></td><td>{title}</td><td>{score:.0%}</td><td>{evidence}</td></tr>'.format(
        id=html.escape(item['id']), title=html.escape(item['title']),
        score=float(item['score']), evidence=html.escape(
            'See docs/charts.md for the engine, delivery evidence and previews.'
            if item['id'] == 'L061' else item['evidence']))
    for item in queue_items
)
preview_paths = sorted(Path('docs/chart-previews').glob('*.png'))
preview_backlog = [line.strip() for line in Path('docs/chart-preview-backlog.txt').read_text(encoding='utf-8').splitlines()
                   if line.strip() and not line.lstrip().startswith('#')]
if len(preview_backlog) != len(set(preview_backlog)) or any(
        re.fullmatch(r'[a-z][a-z0-9_]*', name) is None for name in preview_backlog):
    raise SystemExit('chart preview backlog contains a duplicate or invalid slug')
if any(not path.with_suffix('.svg').exists() for path in preview_paths):
    raise SystemExit('a chart PNG is missing its SVG companion')
if {path.stem for path in preview_paths} & set(preview_backlog):
    raise SystemExit('a rendered chart remains in the preview backlog')
chart_total = len(preview_paths) + len(preview_backlog)
preview_notes = Path('docs/chart-previews/README.md').read_text(encoding='utf-8')
gallery_rows = '\n'.join(
    '| {title} | ![{title}](chart-previews/{png}) | [SVG](chart-previews/{svg}) |'.format(
        title=path.stem.replace('_', ' ').title(), png=path.name,
        svg=path.with_suffix('.svg').name)
    for path in preview_paths
)
chart_guide = (
    '# Neper charts and diagrams\n\n'
    'Neper builds renderer-neutral chart layouts from borrowed data and caller-owned '
    'output storage. The same marks feed its CPU scene/PNG and SVG adapters. '
    'This guide collects the produced charts, their preview notes, and the '
    'charting-engine design and catalogue. Readiness scores remain in '
    '[progress.html](progress.html).\n\n'
    '## Rendered previews ({rendered}/{total})\n\n'
    'The total includes rendered PNG/SVG pairs and the '
    '[planned gallery targets](chart-preview-backlog.txt).\n\n'
    '| Chart | PNG preview | Vector |\n|---|---|---|\n{gallery}\n\n'
    '## Charting-engine delivery evidence\n\n{evidence}\n\n'
    '## Preview descriptions\n\n{notes}\n\n'
    '{plan}\n'
).format(rendered=len(preview_paths), total=chart_total, gallery=gallery_rows,
         evidence=chart_item['evidence'],
         notes=preview_notes.removeprefix('# Chart previews\n').strip(),
         plan=re.sub(r'^(#+) ', lambda match: '#' + match.group(1) + ' ', chart_plan, flags=re.M).strip())
Path('docs/charts.md').write_text(chart_guide, encoding='utf-8', newline='\n')
chart_section = (
    '<section class="tools" aria-label="Charting engine readiness">'
    '<h2>Charting engine</h2>'
    '<p>Chart capability <code>L061</code>: {score:.0%} complete. '
    'Rendered previews ({preview_count}/{chart_total}). '
    '<a href="charts.md">Charting-engine description and produced charts</a>.</p></section>'
    '<section class="tools" aria-label="Unfinished work queue">'
    '<h2>Backlog</h2><p>{count} unfinished capabilities in pickup order.</p>'
    '<details><summary>Show the full backlog</summary><div class="table-scroll">'
    '<table><thead><tr><th>ID</th><th>Capability</th><th>Progress</th><th>Evidence and remaining work</th></tr></thead>'
    '<tbody>{backlog}</tbody></table></div></details></section>'
).format(score=float(chart_item['score']), preview_count=len(preview_paths), chart_total=chart_total,
         count=len(queue_items), backlog=backlog)

page_html = """<!doctype html>
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
footer{color:var(--muted);font-size:.8rem;margin-top:2rem;padding-top:1rem;border-top:1px solid var(--rule)}
.tools{margin-top:2.5rem}.tools h2{margin:0 0 .25rem;font-size:1.5rem}.tools h3{margin:1.5rem 0 .5rem;font-size:1rem}
.tools table{width:100%;border-collapse:collapse;font-size:.85rem}.tools td{padding:.45rem .6rem;border-top:1px solid var(--rule);vertical-align:top}
.tools td:first-child{width:45%;overflow-wrap:anywhere}.tools code{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-size:.8rem}
.tools th{text-align:left;padding:.45rem .6rem}.tools details{margin:1rem 0}.tools summary{cursor:pointer;font-weight:600}
.tools ol{padding-left:1.5rem}.tools li{margin:.3rem 0}
.table-scroll{overflow-x:auto}.table-scroll table{min-width:48rem}.table-scroll td:first-child{width:auto}.table-scroll td{overflow-wrap:anywhere}
@media(max-width:40rem){.tools td{display:block;width:auto}.tools td:first-child{width:auto;border-top:1px solid var(--rule);padding-bottom:0}.tools td+td{border-top:0}}
</style>
</head>
<body>
<main>
<header><p class="eyebrow">neper</p><h1>Readiness</h1></header>
<section class="kpi" aria-label="Project readiness metrics">
__KPI__
</section>
__CHART_SECTION__
<section class="tools" aria-label="How to run the tools">
<h2>Tools</h2>
<p class="sub">From the repository root. PowerShell on Windows, Bash on Linux and macOS.</p>
<h3>Build and test the compiler</h3>
<table>
<tr><td><code>scripts/build-bootstrap.ps1</code> / <code>scripts/build-bootstrap.sh</code></td><td>Build the C bootstrap compiler into <code>build/windows</code> or <code>build/linux</code>.</td></tr>
<tr><td><code>scripts/build-selfhost.ps1</code> / <code>scripts/build-selfhost.sh</code></td><td>Build the self-hosted compiler (<code>neper-self</code>) with the bootstrap.</td></tr>
<tr><td><code>pwsh tests/selfhost/run.ps1</code> / <code>bash tests/selfhost/run.sh</code></td><td>The full self-host suite: fixed point (stage 2 equals stage 3), every link, check and conformance fixture, tool goldens.</td></tr>
<tr><td><code>bash scripts/check-fixture.sh NAME [--keep]</code></td><td>Build and run one link fixture with the self-hosted compiler.</td></tr>
<tr><td><code>python -m unittest discover -s tests -p "test_*.py"</code></td><td>The Python unit tests: module plan, module surfaces, widget plan, GPU contracts, LLM edit benchmark scoring. Run one with <code>python tests/test_module_surfaces.py</code>.</td></tr>
<tr><td><code>python scripts/lint_bootstrap.py src</code></td><td>Find source the C bootstrap cannot compile before building it.</td></tr>
<tr><td><code>build/windows/patch.exe SPEC</code></td><td>Apply a multi-site edit spec (<code>@@@</code> file, <code>&lt;&lt;&lt;</code> old, <code>===</code>, new <code>&gt;&gt;&gt;</code>); source in <code>tools/patch</code>.</td></tr>
</table>
<h3>Check the plans and goldens</h3>
<table>
<tr><td><code>python scripts/check_module_surfaces.py [--compiler PATH --os TARGET]</code></td><td>Every module fence in <code>docs/module-apis.md</code> against the declarations in <code>lib/e</code>.</td></tr>
<tr><td><code>python scripts/check_module_plan.py</code> / <code>python scripts/check_widget_plan.py</code></td><td>Validate <code>docs/modules.json</code> and <code>docs/widget-plan.json</code>.</td></tr>
<tr><td><code>python scripts/library_fixtures.py [--write]</code></td><td>Check, or regenerate, <code>docs/library-fixtures.json</code>.</td></tr>
<tr><td><code>python scripts/validate_stream.py [PATH ...]</code></td><td>Validate the committed <code>.jsonl</code> goldens and <code>docs/modules.json</code> against the v1 stream schema.</td></tr>
<tr><td><code>python scripts/card_examples.py COMPILER ROOT ARCH OS OUTDIR</code></td><td>Check every example in the language card with the compiler.</td></tr>
</table>
<h3>Regenerate documents</h3>
<table>
<tr><td><code>python scripts/render_progress.py</code></td><td>This readiness page and <code>docs/charts.md</code>, from the work queue, chart plan, preview inventory, completion ledger, module and widget plans and committed source.</td></tr>
<tr><td><code>python scripts/render_tasks.py</code></td><td>One task file per unfinished feature under <code>docs/tasks</code>.</td></tr>
<tr><td><code>python scripts/render_card.py [--check]</code></td><td>The LLM language card from the grammar and the diagnostic registry.</td></tr>
<tr><td><code>python scripts/render_ux_theme.py [--check]</code></td><td>The UI theme block in <code>lib/e/ui/style.e</code> from <code>docs/ux/tokens.json</code>.</td></tr>
<tr><td><code>scripts/build-docs-pdf.ps1</code> / <code>scripts/build-docs-pdf.sh</code></td><td>The documentation PDF, <code>docs/neper.pdf</code>; the wrappers make <code>.venv-docs-pdf</code> and install the pinned dependencies. Direct: <code>python scripts/build-docs-pdf.py [--out docs/neper.pdf] [--quiet]</code>.</td></tr>
<tr><td><code>python scripts/render_module_apis.py [--output PATH]</code></td><td>The module API catalogue PDF (default <code>output/pdf/module-apis.pdf</code>); needs <code>reportlab</code>.</td></tr>
</table>
<h3>Website</h3>
<table>
<tr><td><code>python -m http.server 8000 -d docs</code></td><td>Preview the landing page, <code>docs/index.html</code>, at <code>http://localhost:8000</code>. It is a static GitHub Pages site with no build step.</td></tr>
<tr><td><code>docs/landing-page-maintenance.md</code></td><td>Where each number on the page comes from, the one-line recounts for modules, signatures, algorithms and controls, and how to refresh compile time and executable size.</td></tr>
</table>
<h3>Measure</h3>
<table>
<tr><td><code>python scripts/lang-stats.py [--days N] [--harness] [--color] [--help]</code></td><td>What it costs an LLM to write Neper against Dart, Rust, JS, TS and Python, from local agent transcripts; <code>--help</code> explains every column.</td></tr>
<tr><td><code>python benchmarks/baseline/measure.py --compiler PATH --repo ROOT --host windows|linux</code></td><td>Cold and warm build times, peak memory and image size on the compiler and the scale workloads.</td></tr>
<tr><td><code>python scripts/check_batch_snapshots.py COMPILER ROOT ARCH OS WORKDIR [CYCLES]</code></td><td>Batch-session snapshot soak.</td></tr>
<tr><td><code>scripts/embed-pe-runtime.ps1</code> / <code>scripts/embed-elf-runtime.ps1</code></td><td>Regenerate the embedded runtimes after a runtime source change.</td></tr>
</table>
</section>
<footer>Generated by <code>scripts/render_progress.py</code> at
<code>__REV__</code> (__DATE__).</footer>
</main>
</body>
</html>
"""
page_html = page_html.replace('__KPI__', kpi).replace('__CHART_SECTION__', chart_section).replace('__REV__', rev).replace('__DATE__', when)
progress_path.write_text(page_html, encoding='utf-8', newline='\n')
print('wrote docs/progress.html')
print('compiler %.2f  modules %.2f  ui-host %.2f  tooling %.2f  library %.2f' % (C, M, W, T, L))
