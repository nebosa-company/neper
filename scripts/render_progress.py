# -*- coding: utf-8 -*-
"""Render readiness, the charting plan, and the unfinished backlog.

Usage:  python scripts/render_progress.py [--charts-only]
        (from the repository root; --charts-only preserves other generated docs)

Compiler, tooling and library scores come from the active queue plus the
completed ledger; module and UI/host scores come from their inventories.
"""
import json, re, subprocess, datetime, html, sys
from pathlib import Path

from check_widget_plan import validate as validate_widget_plan
CHARTS_ONLY = __name__ == '__main__' and sys.argv[1:] == ['--charts-only']
if __name__ == '__main__' and sys.argv[1:] and not CHARTS_ONLY:
    raise SystemExit('usage: python scripts/render_progress.py [--charts-only]')
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
# the output a pure function of its inputs. The work queue and the completed ledger are
# inputs too: a score change there is the progress this page reports, so it moves the stamp.
INPUTS = ['src', 'lib', 'docs/module-apis.md', 'docs/widget-plan.json', 'docs/algos.md',
          'docs/work-queue.json', 'docs/work-done.jsonl']
stamp = subprocess.run(['git', 'log', '-1', '--format=%h %ct', '--'] + INPUTS,
                       capture_output=True, text=True).stdout.split()
rev, seconds = (stamp + ['unknown', ''])[:2]
# That commit's time in this machine's local time, with its offset from UTC.
moment = datetime.datetime.fromtimestamp(int(seconds)).astimezone() if seconds else datetime.datetime.now().astimezone()
offset = moment.strftime('%z')
when = '%s UTC%s:%s' % (moment.strftime('%Y-%m-%d %H:%M:%S'), offset[:3], offset[3:])

# ---- module numbers, recomputed here so the page cannot drift from the plan ----
txt = Path('docs/module-apis.md').read_text(encoding='utf-8')
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
         for l in Path(p).read_text(encoding='utf-8').splitlines()) if m)

seeded = {}
for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"',
                          Path('src/resolve.e').read_text(encoding='utf-8')):
    seeded.setdefault(mod, set()).add(nm)

dtot = dgot = 0
module_missing = {}
for mod, body in blocks.items():
    declarations = decl_names(body)
    present = impl.get(mod, set()) | seeded.get(mod, set())
    missing = set(declarations) - present
    if missing:
        module_missing[mod] = missing
    dtot += len(declarations)
    dgot += sum(1 for name in declarations if name in present)

# The selected algorithms (docs/algos.md, D834): every entry annotated with a
# library function is one more declaration the library owes until that function
# exists, whether its module is fenced yet or not. Duplicates of one function
# count once.
planned = {}
for mod, fn in re.findall(r'→ `(e\.[A-Za-z0-9_.]+)\.([A-Za-z_][A-Za-z0-9_]*)`',
                          Path('docs/algos.md').read_text(encoding='utf-8')):
    planned.setdefault(mod, set()).add(fn)
algos_total = sum(len(fns) for fns in planned.values())
algos_missing = 0
for mod, fns in planned.items():
    present = impl.get(mod, set()) | seeded.get(mod, set())
    if mod in blocks:
        present |= set(decl_names(blocks[mod]))
    missing = fns - present
    if missing:
        module_missing.setdefault(mod, set()).update(missing)
    algos_missing += len(missing)
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


progress_path = Path('docs/progress.html')

# The four readiness groups the page cards show (D2130). Compiler is the compiler work
# that is not NeperOS; NeperOS is the capability microkernel (D2119); Tooling is the tool
# work; Library -- e.lib blends the module-declaration, UI-control and library-capability
# readiness into one. Each groups both queued and delivered rows, so the score is true
# readiness, not just what is left.
neperos_rows = compiler.get('NeperOS', [])
compiler_rows = [row for group, rows in compiler.items() if group != 'NeperOS' for row in rows]


def group_score(rows):
    """Mean capability score as a percentage, with the delivered sum and the count."""
    if not rows:
        return 100.0, 0.0, 0
    delivered = sum(score for _, score, _ in rows)
    return 100.0 * delivered / len(rows), delivered, len(rows)


COMPILER_PCT, compiler_sum, compiler_n = group_score(compiler_rows)
NEPEROS_PCT, neperos_sum, neperos_n = group_score(neperos_rows)
# Library -- e.lib is the one blended readiness of its three parts, each weighted equally so
# the mostly-planned library capabilities are not washed out by the near-complete module
# declarations: the mean of the Modules, UI-and-host and Library percentages.
ELIB_PCT = (M + W + L) / 3.0

GROUP_CARDS = [
    ('Compiler', 'compiler', COMPILER_PCT,
     '%.2f of %d capabilities' % (compiler_sum, compiler_n)),
    ('Library – e.lib', 'lib', ELIB_PCT,
     '%d of %d declarations · %d of %d UI controls · %.2f of %d library capabilities'
     % (dgot, dtot, wgot, wtot, l_sum, l_n)),
    ('Tooling', 'tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
    ('NeperOS', 'neperos', NEPEROS_PCT,
     '%.2f of %d capabilities' % (neperos_sum, neperos_n)),
]


def group_card(label, key, pct, sub):
    return ('<section class="card ' + key + '"><div class="lab">' + html.escape(label)
            + '</div><div class="val">' + ('%.2f' % pct) + '<span class="pc">%</span></div>'
            '<div class="track" role="img" aria-label="' + html.escape(label) + ': '
            + ('%.2f' % pct) + ' percent complete"><i style="width:' + ('%.1f' % pct)
            + '%"></i></div><div class="sub">' + sub + '</div></section>')


cards = '\n'.join(group_card(label, key, pct, sub) for label, key, pct, sub in GROUP_CARDS)

# Keep the chart catalogue in its maintained Markdown source. The readiness
# page links to a generated chart guide and shows the unfinished queue.
chart_plan = Path('docs/charting-engine-plan.md').read_text(encoding='utf-8')
queue_items = json.loads(WORK_QUEUE.read_text(encoding='utf-8'))['items']
# The first stable CPU release follows the M2/tool-complete gate in roadmap.md.
# These unfinished rows contain work that gate still requires. GPU milestones,
# later libraries and optional tooling do not block this release.
RELEASE_REQUIRED_IDS = {'C082', 'C088', 'T004', 'T012', 'T016', 'T023'}
queue_ids = {item['id'] for item in queue_items}
done_ids = {json.loads(line)['id'] for line in WORK_DONE.read_text(encoding='utf-8').splitlines()
            if line.strip()}
if not RELEASE_REQUIRED_IDS <= queue_ids | done_ids:
    raise SystemExit('release-required item missing from work inventories: '
                     + ', '.join(sorted(RELEASE_REQUIRED_IDS - queue_ids - done_ids)))
module_plan = json.loads(Path('docs/modules.json').read_text(encoding='utf-8'))
core_modules = set(next(tier['modules'] for tier in module_plan['tiers']
                        if tier['id'] == 'core'))
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
def unfinished_details(label, rows):
    # Each row is (id, title, evidence, group-colour key); the ID carries its group's colour.
    body = ''.join(
        '<tr><td>{number}</td><td><code class="id-{key}">{id}</code></td>'
        '<td class="work">{title}</td><td>{evidence}</td></tr>'.format(
            number=number, key=html.escape(key), id=html.escape(item_id),
            title=html.escape(title), evidence=html.escape(evidence))
        for number, (item_id, title, evidence, key) in enumerate(rows, 1)
    )
    content = (
        '<div class="table-scroll"><table><thead><tr><th scope="col">#</th>'
        '<th scope="col">ID</th><th scope="col" class="work">Work and progress</th>'
        '<th scope="col">Evidence and remaining work</th></tr></thead>'
        '<tbody>' + body + '</tbody></table></div>'
        if rows else '<p>No unfinished items.</p>'
    )
    return ('<details id="unfinished-' + label.lower() + '" open><summary>'
            + label + ' — ' + str(len(rows)) + ' pending</summary>'
            + content + '</details>')


def group_key(item):
    """The colour group a work item belongs to, matching the readiness cards."""
    if item['category'] == 'compiler':
        return 'neperos' if item['group'] == 'NeperOS' else 'compiler'
    if item['category'] == 'tooling':
        return 'tooling'
    return 'lib'


backlog = unfinished_details('Backlog', [
    (item['id'], item['title'] + ' (' + format(float(item['score']), '.0%') + ')',
     'See docs/charts.md for the engine, delivery evidence and previews.'
     if item['id'] == 'L061' else item['evidence'],
     group_key(item))
    for item in queue_items if float(item['score']) < 1
])
release_required_count = sum(item['id'] in RELEASE_REQUIRED_IDS for item in queue_items)
module_required_count = sum(mod in core_modules for mod in module_missing)
# A work-in-progress gallery render may exist before its chart is landed. Readiness
# counts tracked preview pairs, not untracked files from another working session.
preview_paths = sorted(Path(name) for name in subprocess.run(
    ['git', 'ls-files', 'docs/chart-previews/*.png'],
    capture_output=True, text=True, check=True).stdout.splitlines())
preview_backlog = [line.strip() for line in Path('docs/chart-preview-backlog.txt').read_text(encoding='utf-8').splitlines()
                   if line.strip() and not line.lstrip().startswith('#')]
if len(preview_backlog) != len(set(preview_backlog)) or any(
        re.fullmatch(r'[a-z][a-z0-9_]*', name) is None for name in preview_backlog):
    raise SystemExit('chart preview backlog contains a duplicate or invalid slug')
if any(not path.exists() or not path.with_suffix('.svg').exists()
       for path in preview_paths):
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
if not CHARTS_ONLY:
    Path('docs/charts.md').write_text(chart_guide, encoding='utf-8', newline='\n')
gallery_cards = '\n'.join(
    '<figure class="chart"><a href="chart-previews/{png}">'
    '<img src="chart-previews/{png}" alt="{title}" width="360" height="240" loading="lazy" decoding="async"></a>'
    '<figcaption><span>{title}</span><span><a href="chart-previews/{svg}">{vector_label}</a>{pdf}</span></figcaption>'
    '</figure>'.format(
        title=html.escape(path.stem.replace('_', ' ').title(), quote=True),
        png=html.escape(path.name, quote=True),
        svg=html.escape(path.with_suffix('.svg').name, quote=True),
        vector_label='Select in SVG' if path.stem == 'interactive_selection' else 'SVG',
        # A preview may also have a PDF companion from the PDF adapter.
        pdf=' · <a href="chart-previews/{}">PDF</a>'.format(html.escape(path.with_suffix('.pdf').name, quote=True))
        if path.with_suffix('.pdf').exists() else '')
    for path in preview_paths
)
charts_html = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Neper chart previews</title>
<style>
:root{color-scheme:light dark;font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
body{margin:0;background:#f4f6f9;color:#172033}
main{max-width:88rem;margin:auto;padding:2rem 1.25rem 4rem}
h1{margin:.5rem 0}p{margin:.5rem 0 1.5rem}a{color:#245aa8}
.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,20rem),1fr));gap:1rem}
.chart{margin:0;min-width:0;padding:.75rem;background:#fff;border:1px solid #dbe1ea;border-radius:.6rem}
.chart>a{display:block}.chart img{display:block;width:100%;height:auto}
figcaption{display:flex;justify-content:space-between;gap:1rem;align-items:baseline;padding:.6rem .2rem .1rem;font-weight:600}
@media(prefers-color-scheme:dark){body{background:#0f1319;color:#e8edf4}.chart{background:#171d26;border-color:#354051}a{color:#9dc0ff}}
</style>
</head>
<body>
<main>
<nav><a href="progress.html">Readiness</a> · <a href="charts.md">Charting-engine details</a></nav>
<h1>Rendered chart previews ({rendered}/{total})</h1>
<p>Click a preview to open its PNG, or choose SVG for the vector version. The interactive-selection SVG supports click and keyboard focus.</p>
<div class="gallery">
{cards}
</div>
</main>
</body>
</html>
'''.replace('{rendered}', str(len(preview_paths))).replace(
    '{total}', str(chart_total)).replace('{cards}', gallery_cards)
Path('docs/charts.html').write_text(charts_html, encoding='utf-8', newline='\n')
if CHARTS_ONLY:
    raise SystemExit(0)
backlog_section = (
    '<section class="backlog" aria-label="Backlog">'
    '<h2>Backlog</h2>'
    '<p class="sub">{count} pending capabilities in pickup order — the NeperOS stage '
    'first (D2119), then chart work, across all categories; the first row is next. '
    '{required_count} are release-required for the '
    '<a href="roadmap.md">first stable CPU compiler release</a>.</p>'
    '{backlog}</section>'
).format(count=len(queue_items), required_count=release_required_count, backlog=backlog)

page_html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neper readiness</title>
<style>
:root{color-scheme:light dark;--bg:#fff;--panel:#f5f7fa;--ink:#111827;--muted:#667085;--track:#d8e1ee;--rule:#e4e7ec;--c-compiler:#007dbc;--c-lib:#00885b;--c-tooling:#93731f;--c-neperos:#8269ba;--c-backlog:#b36137}
@media(prefers-color-scheme:dark){:root{--bg:#0f1319;--panel:#171d26;--ink:#e8edf4;--muted:#9aa7b5;--track:#293444;--rule:#29313d;--c-compiler:#5cb8ff;--c-lib:#50c591;--c-tooling:#d2ab57;--c-neperos:#bea2f8;--c-backlog:#f59a6d}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:64rem;margin:auto;padding:clamp(2rem,6vw,5rem) 1.25rem}header{margin-bottom:2rem}.eyebrow,.sub,footer{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace}
.eyebrow{margin:0 0 .5rem;color:var(--muted);font-size:.75rem;letter-spacing:.14em;text-transform:uppercase}h1{margin:0;font-size:clamp(2rem,5vw,3.5rem);line-height:1.1}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(13rem,1fr));gap:1rem}
.card{padding:1.25rem;border:1px solid var(--rule);border-left:.4rem solid var(--accent);border-radius:.75rem;background:var(--panel)}
.card.compiler{--accent:var(--c-compiler)}.card.lib{--accent:var(--c-lib)}.card.tooling{--accent:var(--c-tooling)}.card.neperos{--accent:var(--c-neperos)}
.lab{color:var(--accent);font-size:.85rem;font-weight:700;letter-spacing:.02em}.val{margin:.35rem 0;font-size:2.65rem;font-weight:700;line-height:1;font-variant-numeric:tabular-nums}.pc{font-size:1.2rem;color:var(--muted)}
.track{height:.5rem;margin:.8rem 0;background:var(--track);border-radius:1rem;overflow:hidden}.track i{display:block;height:100%;background:var(--accent);border-radius:inherit}.sub{color:var(--muted);font-size:.75rem}
footer{color:var(--muted);font-size:.8rem;margin-top:2rem;padding-top:1rem;border-top:1px solid var(--rule)}
.backlog{--accent:var(--c-backlog);margin-top:2.5rem;padding:1.25rem 1.25rem 1.5rem;border:1px solid var(--rule);border-left:.4rem solid var(--accent);border-radius:.75rem;background:var(--panel)}
.backlog h2{margin:0 0 .25rem;font-size:1.5rem;color:var(--accent)}.backlog p{margin:.25rem 0 1rem}
.backlog table{width:100%;border-collapse:collapse;font-size:.85rem}.backlog td{padding:.45rem .6rem;border-top:1px solid var(--rule);vertical-align:top}
.backlog th{text-align:left;padding:.45rem .6rem}.backlog code{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-size:.8rem;font-weight:700}
.backlog td:nth-child(2){white-space:nowrap}.backlog .work{width:40%}
.backlog code.id-compiler{color:var(--c-compiler)}.backlog code.id-lib{color:var(--c-lib)}.backlog code.id-tooling{color:var(--c-tooling)}.backlog code.id-neperos{color:var(--c-neperos)}
.backlog details{margin:0}.backlog summary{cursor:pointer;font-weight:600;color:var(--accent)}
.table-scroll{overflow-x:auto}.table-scroll table{min-width:44rem}.table-scroll td{overflow-wrap:anywhere}
@media(max-width:40rem){.backlog td{display:block;width:auto}.backlog td:nth-child(2){white-space:normal}.backlog td:first-child{border-top:1px solid var(--rule);padding-bottom:0}.backlog td+td{border-top:0}}
</style>
</head>
<body>
<main>
<header><p class="eyebrow">neper</p><h1>Readiness</h1></header>
<section class="cards" aria-label="Readiness by group">
__CARDS__
</section>
__BACKLOG__
<footer>Generated by <code>scripts/render_progress.py</code> at
<code>__REV__</code> (__DATE__).</footer>
</main>
</body>
</html>
"""
page_html = page_html.replace('__CARDS__', cards).replace('__BACKLOG__', backlog_section).replace('__REV__', rev).replace('__DATE__', when)
progress_path.write_text(page_html, encoding='utf-8', newline='\n')
print('wrote docs/progress.html')
print('compiler %.2f  modules %.2f  ui-host %.2f  tooling %.2f  library %.2f' % (C, M, W, T, L))
