# -*- coding: utf-8 -*-
"""Render docs/progress.html from the roadmap rubric and the module plan.

Usage:  python scripts/render_progress.py     (from the repository root)

The four readiness numbers are computed, never typed: compiler and tooling scores
come from the active queue plus the completed ledger, while module and UI/host
scores come from their machine-readable inventories. Post-M2 track status is
rendered separately from docs/hardening-tracks.json and is never inferred from
precursor capability scores.
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
INPUTS = ['src', 'lib', 'docs/roadmap.md', 'docs/module-apis.md', 'docs/modules.json',
          'docs/hardening-tracks.json',
          'docs/widget-library-proposal.md', 'docs/widget-plan.json']
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

plan = json.load(open('docs/modules.json'))['modules']
hardening = json.load(open('docs/hardening-tracks.json', encoding='utf-8'))
if hardening.get('schema_version') != 1:
    raise SystemExit('docs/hardening-tracks.json: unsupported schema_version')
allowed_hardening_status = {'planned', 'open', 'in_progress', 'closed'}
hardening_ids, hardening_track_ids = set(), set()
reference_host = hardening.get('reference_host', {})
reference_host_requirements = set()
if reference_host.get('status') not in allowed_hardening_status:
    raise SystemExit('docs/hardening-tracks.json: invalid reference_host status')
if (reference_host.get('status') != 'planned'
        and not Path(reference_host.get('path', '')).exists()):
    raise SystemExit('docs/hardening-tracks.json: reference_host path is missing')
for track in hardening.get('tracks', []):
    track_id = track.get('id')
    if not track_id or track_id in hardening_track_ids:
        raise SystemExit('docs/hardening-tracks.json: missing or duplicate track id')
    hardening_track_ids.add(track_id)
    if track.get('status') not in allowed_hardening_status:
        raise SystemExit('docs/hardening-tracks.json: invalid status for ' + track_id)
    source = track.get('source', '')
    if not source or not Path(source).is_file():
        raise SystemExit('docs/hardening-tracks.json: missing source for ' + track_id)
    if track['status'] == 'closed' and not track.get('closure'):
        raise SystemExit('docs/hardening-tracks.json: closed track lacks closure: ' + track_id)
    for requirement in track.get('requirements', []):
        match = re.fullmatch(r'(H\d\d)(?::[a-z_]+)?', requirement)
        if not match:
            raise SystemExit('docs/hardening-tracks.json: invalid requirement ' + requirement)
        hardening_ids.add(match.group(1))
        if track.get('owner') == reference_host.get('name'):
            reference_host_requirements.add(match.group(1))
expected_hardening_ids = {'H%02d' % n for n in range(1, 46)}
if hardening_ids != expected_hardening_ids:
    missing = sorted(expected_hardening_ids - hardening_ids)
    extra = sorted(hardening_ids - expected_hardening_ids)
    raise SystemExit('docs/hardening-tracks.json: coverage mismatch missing=%s extra=%s'
                     % (missing, extra))
if set(reference_host.get('owns', [])) != reference_host_requirements:
    raise SystemExit('docs/hardening-tracks.json: reference_host ownership mismatch')
surf = {}
for m in plan:
    surf[m['surface']] = surf.get(m['surface'], 0) + 1
# `docs/modules.json` is the plan and this table is the plan's, so every module in it gets a
# row whether or not a line of it exists. A page that listed only what is written cannot be
# read as a roadmap: what is missing is the part a reader is asking about.
planned = {m['name']: m for m in plan}
tier_of = {}
for tier in json.load(open('docs/modules.json'))['tiers']:
    for name in tier['modules']:
        tier_of[name] = tier['id']

mod_rows, dtot, dgot = [], 0, 0
for mod in sorted(blocks):
    d = decl_names(blocks[mod])
    have = impl.get(mod, set()) | seeded.get(mod, set())
    h = sum(1 for n in d if n in have)
    dtot += len(d)
    dgot += h
    entry = planned.get(mod, {})
    mod_rows.append((mod, h, len(d), entry.get('surface', 'planned'),
                     entry.get('milestone'), entry.get('schedule', 'later'),
                     tier_of.get(mod, ''), entry.get('blocked_by', [])))
# Written first and most complete first; then what is scheduled, by milestone; then what is not
# scheduled at all. Read top to bottom that is the order the plan intends to be worked in, which
# is the only ordering a roadmap can justify.
mod_rows.sort(key=lambda r: (-r[1] / r[2], r[4] is None, r[4] or '', r[0]))

# ---- widget-library numbers, recomputed from its implementation inventory ----
widget_plan, widget_errors = validate_widget_plan(Path('.'))
if widget_errors:
    raise SystemExit('\n'.join(widget_errors))
widget_rows, wgot, wtot = [], 0, 0
complete_widget_phases = set()
resolved_widget_blockers = set(widget_plan.get('resolved_blockers', []))
for phase in widget_plan['phases']:
    phase_blocked = [blocker for blocker in phase['blocked_by']
                     if (blocker.startswith('P') and blocker not in complete_widget_phases)
                     or (blocker.startswith('e.')
                         and planned.get(blocker, {}).get('surface') != 'source')
                     or (not blocker.startswith(('P', 'e.'))
                         and blocker not in resolved_widget_blockers)]
    for item in phase['items']:
        item_blocked = [blocker for blocker in item.get('blocked_by', [])
                        if (blocker.startswith('P') and blocker not in complete_widget_phases)
                        or (blocker.startswith('e.')
                            and planned.get(blocker, {}).get('surface') != 'source')
                        or (not blocker.startswith(('P', 'e.'))
                            and blocker not in resolved_widget_blockers)]
        blocked = list(dict.fromkeys(phase_blocked + item_blocked))
        have = len(item['delivered'])
        total = len(item['components'])
        wgot += have
        wtot += total
        widget_rows.append((phase['id'], item['id'], item['name'], item['module'],
                            have, total, item['components'], item['delivered'], item['evidence'],
                            blocked))
    if all(set(item['components']) == set(item['delivered']) for item in phase['items']):
        complete_widget_phases.add(phase['id'])

c_sum = sum(s for g in compiler.values() for _, s, _ in g)
c_n = sum(len(g) for g in compiler.values())
t_sum = sum(s for _, s, _ in tooling)
t_n = len(tooling)
C, M, T = 100 * c_sum / c_n, 100 * dgot / dtot, 100 * t_sum / t_n
W = 100 * wgot / wtot

SRC = 'source'
PART = 'partial'


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def mark(v):
    if v == 1:
        return '<span class="s s3" aria-hidden="true"></span>', '1'
    if v == 0:
        return '<span class="s s0" aria-hidden="true"></span>', '0'
    return '<span class="s s2" aria-hidden="true"></span>', ('%g' % v)


def table(items):
    rows = []
    for name, v, note in items:
        dot, num = mark(v)
        rows.append('<tr><td class="mk">' + dot + '</td><td class="nm">' + esc(name)
                    + '</td><td class="sc">' + num + '</td><td class="nt">'
                    + esc(note) + '</td></tr>')
    return ('<table><thead><tr><th class="mk"><span class="vh">State</span></th>'
            '<th>Capability</th><th class="sc">Score</th><th>Evidence or gap</th>'
            '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table>')


def hardening_table(tracks):
    rows = []
    for track in tracks:
        blockers = ', '.join(track['blocks']) if track['blocks'] else 'nothing'
        rows.append('<tr><td class="nm"><code>' + esc(track['id'])
                    + '</code> &middot; ' + esc(track['name'])
                    + '</td><td class="sc">' + esc(track['status'])
                    + '</td><td class="nt">' + esc(', '.join(track['requirements']))
                    + '</td><td class="nt">' + esc(track['owner'])
                    + '</td><td class="nt">' + esc(track['exit'])
                    + ' Blocks: ' + esc(blockers) + '.</td></tr>')
    return ('<table><thead><tr><th>Track</th><th>Status</th><th>Requirements</th><th>Owner</th>'
            '<th>Exit and blockers</th></tr></thead><tbody>' + ''.join(rows)
            + '</tbody></table>')


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
    delta_class = 'flat'
    if delta > 0.004:
        delta_class = 'up'
    elif delta < -0.004:
        delta_class = 'down'
    delta_text = '%+.2f pp' % delta
    return ('<div class="tile"><div class="lab">' + label + '</div>'
            '<div class="val">' + ('%.2f' % pct) + '<span class="pc">%</span>'
            '<span class="delta ' + delta_class + '" title="Change since the previous generation">'
            + delta_text + '</span></div>'
            '<div class="track" role="img" aria-label="' + label + ': '
            + ('%.2f' % pct) + ' percent complete"><i style="width:'
            + ('%.1f' % pct) + '%"></i></div>'
            '<div class="sub">' + sub + '</div></div>')


groups = ''
for g, items in compiler.items():
    s = sum(x for _, x, _ in items)
    groups += ('<h3>' + esc(g) + ' <em>' + ('%.2f of %d' % (s, len(items)))
               + '</em></h3>' + table(items))

mod_body = ''
module_evidence = {
    'e.crypto.sign': ('P-256/SHA-256 ECDSA verification '
                      '(D645; RFC 6979 fixture; tls-p256-openrouter.md)'),
    'e.crypto.x509': ('P-256 X.509 chains and non-authoritative unsupported suffixes '
                      '(D646, D649; tls-p256-openrouter.md)'),
    'e.net.tls': ('TLS 1.3 ECDSA P-256/SHA-256 client authentication and OpenRouter '
                  'record framing (D647-D648; live Windows/Linux HTTP 200; '
                  'tls-p256-openrouter.md)'),
}
for m, h, d, surface, milestone, schedule, tier, blocked in mod_rows:
    # Both of these are intrinsics plus source now, and saying only "intrinsics" understates
    # how much of them is written down: e.os is mostly its two per-target files, and e.mem gained
    # `copy` and `eq`.
    if m == 'e.mem':
        where = 'compiler intrinsics, lib/e/mem.e'
    elif m == 'e.os':
        where = 'compiler intrinsics, lib/e/os.linux.e, lib/e/os.windows.e'
    elif h:
        where = 'lib/' + m.replace('.', '/') + '.e'
    elif blocked:
        where = 'blocked: ' + ', '.join(blocked)
    elif schedule == 'scheduled':
        where = 'scheduled, not started'
    else:
        where = 'after the scheduled set'
    if m in module_evidence:
        where += '; ' + module_evidence[m]
    when = milestone if milestone else '&mdash;'
    mod_body += ('<tr><td class="nm"><code>' + esc(m) + '</code></td><td class="sc">'
                 + ('%d / %d' % (h, d)) + '</td><td class="sc">'
                 + ('%.0f%%' % (100 * h / d)) + '</td><td class="sc">' + when
                 + '</td><td class="sc">' + esc(tier) + '</td><td class="nt">'
                 + esc(surface) + ' &middot; ' + esc(where) + '</td></tr>')
mod_table = ('<table><thead><tr><th>Module</th><th class="sc">Declarations</th>'
             '<th class="sc">Share</th><th class="sc">Milestone</th><th class="sc">Tier</th>'
             '<th>Surface and where it comes from</th></tr></thead><tbody>'
             + mod_body + '</tbody></table>')

widget_body = ''
for phase, item_id, name, module, have, total, components, delivered, evidence, blocked in widget_rows:
    dot, _ = mark(have / total)
    gap = [component for component in components if component not in delivered]
    note = evidence if evidence else 'missing: ' + ', '.join(gap)
    if blocked:
        note += '; blocked by ' + ', '.join(blocked)
    widget_body += ('<tr><td class="mk">' + dot + '</td><td class="sc">' + esc(phase)
                    + '</td><td class="nm">' + esc(name) + '</td><td><code>'
                    + esc(module) + '</code></td><td class="sc">'
                    + ('%d / %d' % (have, total)) + '</td><td class="nt">'
                    + esc(note) + '</td></tr>')
widget_table = ('<table><thead><tr><th class="mk"><span class="vh">State</span></th>'
                '<th class="sc">Phase</th><th>Work item</th><th>Owner</th>'
                '<th class="sc">Components</th><th>Evidence or gap</th>'
                '</tr></thead><tbody>' + widget_body + '</tbody></table>')

mod_pct = 100 * (surf.get(SRC, 0) + 0.5 * surf.get(PART, 0)) / len(plan)

# The prose below the table names three modules by their counts. Typing those in is
# how the page goes stale one increment after it is written, so they come from the
# same rows the table does.
counts = {row[0]: (row[1], row[2]) for row in mod_rows}
written_modules = sum(1 for row in mod_rows if row[1])


def count_of(module):
    h, d = counts[module]
    return '%d of %d' % (h, d)

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neper Readiness</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Spectral:ital,wght@0,400;0,600;1,400&amp;family=IBM+Plex+Mono:wght@400;500&amp;family=IBM+Plex+Sans:wght@400;500;600&amp;display=swap">
<style>
:root {
  --ink:#101418; --ink-2:#42505f; --ink-3:#78838f;
  --rule:#e4e8ee; --rule-2:#eef1f5; --paper:#ffffff; --panel:#f7f8fa;
  --ramp-3:#1a4fa0; --ramp-2:#7297d2; --ramp-1:#c9d8ee; --ramp-0:#dfe4ea;
  --serif:"Spectral",Georgia,"Times New Roman",serif;
  --sans:"IBM Plex Sans","Segoe UI",system-ui,-apple-system,Helvetica,Arial,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,"Cascadia Mono",Consolas,monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
    --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
    --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
  }
}
:root[data-theme="dark"] {
  --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
  --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
  --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
}
* { box-sizing:border-box; }
body {
  margin:0; background:var(--paper); color:var(--ink);
  font:400 16px/1.6 var(--sans); -webkit-font-smoothing:antialiased;
}
.wrap { max-width:60rem; margin:0 auto; padding:3.5rem 1.5rem 5rem; }
header { border-bottom:1px solid var(--rule); padding-bottom:1.75rem; margin-bottom:2.5rem; }
.eyebrow {
  font:500 .75rem/1 var(--mono); letter-spacing:.14em; text-transform:uppercase;
  color:var(--ink-3); margin:0 0 .9rem;
}
h1 {
  font:600 2.5rem/1.15 var(--serif); margin:0 0 .6rem; letter-spacing:-.01em;
  text-wrap:balance; color:var(--ink);
}
.stand { font-size:1.0625rem; color:var(--ink-2); max-width:46rem; margin:0; }
.stand em { font-family:var(--serif); }
.kpi { display:grid; grid-template-columns:repeat(auto-fit,minmax(13rem,1fr)); gap:1.75rem; margin:0 0 2rem; }
.tile { display:flex; flex-direction:column; gap:.55rem; }
.lab { font:500 .8125rem/1 var(--sans); letter-spacing:.02em; color:var(--ink-2); }
.val { font:600 3rem/1 var(--sans); letter-spacing:-.03em; color:var(--ink); }
.pc { font-size:1.375rem; font-weight:500; color:var(--ink-3); margin-left:.08em; }
.track { height:8px; border-radius:4px; background:var(--ramp-1); overflow:hidden; }
.track i { display:block; height:100%; border-radius:4px; background:var(--ramp-3); }
.sub { font:400 .8125rem/1.45 var(--mono); color:var(--ink-3); }
.delta { margin-left:.55rem; font:500 .75rem/1 var(--mono); vertical-align:middle; }
.delta.up { color:#18794e; }
.delta.down { color:#b42318; }
.delta.flat { color:var(--ink-3); }
section { margin:0 0 3.25rem; }
h2 {
  font:600 1.5rem/1.25 var(--serif); margin:0 0 .75rem; letter-spacing:-.005em;
  padding-top:1.5rem; border-top:2px solid var(--ink); display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem; flex-wrap:wrap;
}
h2 span { font:500 .875rem/1 var(--mono); color:var(--ink-3); letter-spacing:0; }
h3 {
  font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
  color:var(--ink-2); margin:2rem 0 .75rem; display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem;
}
h3 em { font:400 .8125rem/1 var(--mono); letter-spacing:0; text-transform:none; color:var(--ink-3); }
p { max-width:46rem; color:var(--ink-2); }
.tw { overflow-x:auto; }
table { border-collapse:collapse; width:100%; font-size:.875rem; min-width:34rem; }
th {
  text-align:left; font:500 .6875rem/1 var(--mono); letter-spacing:.1em;
  text-transform:uppercase; color:var(--ink-3); padding:0 .75rem .5rem 0;
  border-bottom:1px solid var(--rule);
}
td { padding:.45rem .75rem .45rem 0; border-bottom:1px solid var(--rule-2); vertical-align:baseline; }
tbody tr:last-child td { border-bottom:0; }
.nm { color:var(--ink); width:46%; }
/* Six columns rather than four, so the name gives most of its width back. */
.mods table { min-width:46rem; }
.mods .nm { width:22%; }
.mods .nt { width:34%; }
.nt { color:var(--ink-3); font:400 .8125rem/1.45 var(--mono); }
.sc { font-variant-numeric:tabular-nums; font-family:var(--mono); color:var(--ink-2);
      text-align:right; white-space:nowrap; width:1%; padding-right:1.25rem; }
th.sc { text-align:right; }
.mk { width:1.25rem; padding-right:.6rem; }
.s { display:inline-block; width:9px; height:9px; border-radius:2px; }
.s3 { background:var(--ramp-3); }
.s2 { background:var(--ramp-2); }
.s0 { background:var(--ramp-0); }
.vh { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); }
code { font:400 .875em/1 var(--mono); color:var(--ink); }
.note {
  background:var(--panel); border-left:2px solid var(--ramp-2);
  padding:1.15rem 1.35rem; margin:2rem 0 0; font-size:.9375rem;
}
.note p { margin:0 0 .65rem; }
.note p:last-child { margin:0; }
.note h4 { font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
           color:var(--ink-2); margin:0 0 .7rem; }
.legend { display:flex; gap:1.5rem; flex-wrap:wrap; font:400 .8125rem/1 var(--mono);
          color:var(--ink-3); margin:0 0 2rem; padding-bottom:.25rem; }
.legend span { display:inline-flex; align-items:center; gap:.45rem; }
footer { border-top:1px solid var(--rule); margin-top:3rem; padding-top:1.25rem;
         font:400 .8125rem/1.6 var(--mono); color:var(--ink-3); }
</style>
</head>
<body>
<div class="wrap">

<header>
  <p class="eyebrow">neper &middot; milestone M2</p>
  <h1>Readiness</h1>
  <p class="stand">Four numbers for four deliverables, each scored against the
  capability lists the <em>roadmap</em>, <em>module plan</em> and widget inventory state. Every row
  below carries its evidence or its gap, so the totals are checkable rather than
  asserted.</p>
</header>

<div class="kpi">
__KPI__
</div>

<p class="legend">
  <span><i class="s s3"></i> delivered &mdash; score 1</span>
  <span><i class="s s2"></i> partial &mdash; score 0.25 to 0.5</span>
  <span><i class="s s0"></i> not started &mdash; score 0</span>
</p>

<section>
  <h2>Compiler <span>__CSUM__ / __CN__ &middot; __CPCT__%</span></h2>
  <p>The furthest along of the three, for a narrow reason: the front end is nearly
  complete while whole back-end subsystems have not been started. It compiles its own
  source on both platforms, and stage&nbsp;2 and stage&nbsp;3 come out byte-identical
  &mdash; the strongest single result on this page.</p>
__GROUPS__
</section>

<section>
  <h2>Modules <span>__DGOT__ / __DTOT__ &middot; __MPCT__%</span></h2>
  <p>Scored by <strong>declaration</strong> rather than by module.
  <code>docs/module-apis.md</code> freezes __DTOT__ declarations across __NMOD__
  modules, and __DGOT__ of them exist in committed source or as compiler intrinsics.
  Counting whole modules gives a similar figure &mdash; __NSRC__ at
  <code>surface:"source"</code> and __NPART__ at <code>"partial"</code> out of __NPLAN__,
  or __MODPCT__%.</p>
  <p>The two framings agree because the delivered modules are finished: every container
  and algorithm module with a count below implements its frozen surface in full. What is
  missing is breadth, not polish. The design layer is a separate story &mdash; all
  __NMOD__ modules have a frozen, mechanically extractable API, which is what makes the
  denominator meaningful.</p>
  <p>The table is the whole plan, not the part that exists: every one of the __NPLAN__
  modules in <code>docs/modules.json</code> has a row, __NWRITTEN__ of them with something
  written. The rest carry what is known about them instead &mdash; the milestone they are
  scheduled for, the tier that says what stability they will promise, and what they are
  waiting on. <strong>core</strong> is the required-first set, <strong>extended</strong> is
  stable but independently delivered, and <strong>experimental</strong> promises no
  compatibility. A module with no milestone is not scheduled yet, which is a statement
  about order and not about doubt.</p>
  <div class="tw mods">__MODTABLE__</div>
  <div class="note">
    <h4>What the two large partials mean</h4>
    <p><code>e.os</code> at __COS__ and <code>e.io</code> at __CIO__ are not stalled
    work. <code>e.os</code> is the subset the compiler needs to build itself, plus
    everything written since as neper source rather than supplied as intrinsics: the
    filesystem calls <code>e.fs</code> needs, sockets, a poller, file mappings, directory
    watches, file locks, process groups, name resolution and the loader. Those are per target,
    over <code>os.syscall</code> on Linux and <code>kernel32</code> through
    <code>@import</code> on Windows, which is what D32 said all along (D97) &mdash; and on Linux
    the resolver is a DNS client written in neper, because that host has nothing to ask (D120).
    The loader is the one place <code>os.linux.e</code> names a library instead of a syscall.
    That did cost something at first &mdash; every binary using <code>e.os</code> came out linked
    against libc, because the compiler emitted every function of every module it touched &mdash;
    which is what dead-function elimination fixed: only what <code>main</code> reaches is emitted,
    so a binary that opens no library is freestanding again and a minimal one went from 221&nbsp;KB
    to 8&nbsp;KB (D130 corrects D128). Nothing in that fence is unwritten:
    <code>last_error_detail</code> was the last, and it waited on a module-scope <code>var</code>
    in the compiler, which is now built. It is a slot per thread keyed by the thread's own
    identifier, with no atomics available inside <code>e.os</code>'s dependency budget &mdash; so a
    detail may be absent and is never another thread's (D132).
    <code>e.io</code> is the subset the compiler needs.
    <code>e.io</code> no longer waits on <code>printf</code>: that expands, over a
    4&nbsp;KiB buffer of its own drained through a generated sink.</p>
    <p><code>e.str</code> is complete at __CSTR__ and is the first module at
    <code>surface:&nbsp;"source"</code> to have needed the compiler for any of it.
    <code>format</code> expands, and so does <code>push_err</code> &mdash; the one
    declaration a library could not write, because what it prints is the qualified
    name and the merged error table is a property of the whole program, where a
    module sees one module at a time. What the expansion still cannot reach is a
    slice, an array or a named type's own <code>format</code>, each of which needs it
    to recurse into an argument.</p>
    <p>What <code>e.io</code>'s remaining declarations wait on is not a compiler
    feature but a decision. Ten of its constructors have to supply a callback of
    their own, and the shape they need &mdash;
    <code>fn(*void, []u8) -&gt; (usize, err)</code> &mdash; is not one the frozen
    surface declares. The language has no visibility mechanism (spec&nbsp;&sect;12), so
    a helper cannot be added quietly: it would be a public symbol the plan does not
    know about. <code>printf</code>'s own sink hit exactly this and was answered by
    generating the function in the compiler, which is one of the three ways the rest
    could go; widening the surface and making the constructors intrinsics are the
    others.</p>
  </div>
</section>

<section>
  <h2>UI and host integration <span>__WGOT__ / __WTOT__ &middot; __WPCT__%</span></h2>
  <p>The UI and host-capability inventory comes from <code>docs/widget-plan.json</code>. Phases and
  work items are ordered for harness pickup; each row names its owner, blockers and
  exact missing components. Candidate modules become module-plan entries when P0
  freezes their public APIs, so this inventory tracks design-to-source delivery
  without pretending that provisional constructor signatures are already stable.</p>
  <div class="tw mods">__WTABLE__</div>
</section>

<section>
  <h2>Tooling <span>__TSUM__ / __TN__ &middot; __TPCT__%</span></h2>
  <p>This score describes delivered version-1 commands, schemas and conformance
  evidence. It is not a T2 completion percentage. Existing context, edit, diagnostic
  and runner features are predecessor evidence until the version-2 slices below close.</p>
  <div class="tw">__TTABLE__</div>
</section>

<section>
  <h2>Post-M2 hardening tracks <span>status, not a percentage</span></h2>
  <p><code>docs/hardening-tracks.json</code> is the ownership and status authority.
  A capability score above cannot close a track; closure requires the evidence named
  by that track. In particular, T2.2 emits evidence but T2.3 is the first slice allowed
  to emit <code>verified</code>.</p>
  <div class="tw mods">__HTABLE__</div>
</section>

<div class="note">
  <h4>Method</h4>
  <p>Each capability scores 1 when delivered, 0 when not started, and a fraction
  between when partial, with the reason stated in its own row. Items are weighted
  equally inside a dimension; no dimension is weighted against another, and the four
  numbers are never combined into one. Compiler capability rows may carry precursor
  evidence for later tracks; the separate hardening table is authoritative for track
  status. GPU (M3) and Metal (M5) remain separate milestones.</p>
  <p>The signed value beside each headline percentage is its percentage-point change
  from the preceding generated score. Re-rendering an unchanged score preserves that
  comparison, so routine regeneration does not erase the last observable movement.</p>
  <p>Module readiness counts declarations present in committed source or seeded as
  compiler intrinsics. Uncommitted work in the tree is deliberately not counted.</p>
  <p>One judgement is worth naming. Self-hosting is four rows out of __CN__ here, but it
  is the binary M2 exit gate. Read the compiler number as capability coverage, not as
  distance to the milestone.</p>
</div>

<div class="note">
  <h4>Keeping this current</h4>
  <p>This page is generated, never hand-edited. <strong>Every session that lands a
  capability updates it</strong>: move the affected rows in the tables at the top of
  <code>scripts/render_progress.py</code>, run <code>python
  scripts/render_progress.py</code> from the repository root, and commit the regenerated
  page with the change that earned it. The module numbers need no editing at all &mdash;
  they are read from <code>docs/module-apis.md</code>, <code>docs/modules.json</code>,
  the committed <code>lib/e</code> sources and the intrinsics seeded in
  <code>src/resolve.e</code>. Widget work updates the affected item's
  <code>delivered</code> and <code>evidence</code> fields in
  <code>docs/widget-plan.json</code>; the widget percentage and table are generated
  from those fields.</p>
  <p>A readiness figure that moves only when someone remembers to move it is worse than
  no figure. This is the single readiness document for the project; there is no second
  copy to keep in step.</p>
</div>

<footer>
  Generated by <code>scripts/render_progress.py</code> from <code>docs/roadmap.md</code>,
  <code>docs/module-apis.md</code>, <code>docs/modules.json</code>,
  <code>docs/widget-plan.json</code> and the compiler sources, as they stood at
  <code>__REV__</code> (__DATE__).
</footer>

</div>
</body>
</html>
"""

kpi = '\n'.join([
    meter('Compiler', C, '%.2f of %d capabilities' % (c_sum, c_n)),
    meter('Modules', M, '%d of %d declarations' % (dgot, dtot)),
    meter('UI and host integration', W, '%d of %d capabilities' % (wgot, wtot)),
    meter('Tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
])

for key, val in [
    ('__KPI__', kpi),
    ('__GROUPS__', groups),
    ('__MODTABLE__', mod_table),
    ('__WTABLE__', widget_table),
    ('__TTABLE__', table(tooling)),
    ('__HTABLE__', hardening_table(hardening['tracks'])),
    ('__CSUM__', '%.2f' % c_sum), ('__CN__', str(c_n)), ('__CPCT__', '%.2f' % C),
    ('__TSUM__', '%.2f' % t_sum), ('__TN__', str(t_n)), ('__TPCT__', '%.2f' % T),
    ('__DGOT__', str(dgot)), ('__DTOT__', str(dtot)), ('__MPCT__', '%.2f' % M),
    ('__WGOT__', str(wgot)), ('__WTOT__', str(wtot)), ('__WPCT__', '%.2f' % W),
    ('__NMOD__', str(len(blocks))), ('__NPLAN__', str(len(plan))),
    ('__NWRITTEN__', str(written_modules)),
    ('__NSRC__', str(surf.get(SRC, 0))), ('__NPART__', str(surf.get(PART, 0))),
    ('__MODPCT__', '%.2f' % mod_pct),
    ('__COS__', count_of('e.os')), ('__CIO__', count_of('e.io')),
    ('__CSTR__', count_of('e.str')),
    ('__DATE__', when), ('__REV__', rev),
]:
    html = html.replace(key, val)

progress_path.write_text(html, encoding='utf-8', newline='\n')
print('wrote docs/progress.html')
print('compiler %.2f  modules %.2f  ui-host %.2f  tooling %.2f' % (C, M, W, T))
