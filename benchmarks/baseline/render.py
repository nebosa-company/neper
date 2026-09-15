# Renders the baseline tables of docs/m2-baseline.md from the measured JSON documents
# under benchmarks/baseline/results/ (D338): the numbers in the document are never
# typed by hand.
#
#   python benchmarks/baseline/render.py            (from the repository root)
import glob, json, os

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
doc = os.path.join(root, 'docs', 'm2-baseline.md')
results = {}
for path in sorted(glob.glob(os.path.join(here, 'results', '*.json'))):
    with open(path, encoding='utf-8') as f:
        results[os.path.basename(path)] = json.load(f)

def fmt_ms(v):
    return f'{v / 1000:.2f} s' if v >= 1000 else f'{v:.0f} ms'

lines = []
for name, r in results.items():
    lines.append(f"### `{name}` -- {r['host']}, {r['jobs']} workers, {r['runs']} runs per cell, revision `{r['revision'][:12]}`")
    lines.append('')
    lines.append(f"Compiler `{os.path.basename(r['compiler'])}`, `--arena {r['arena']}`, platform `{r['platform']}`.")
    lines.append('')
    lines.append('| workload | lines | mode | cold p50 | cold p95 | warm p50 | warm p95 | peak RSS | arena high-water | image |')
    lines.append('|---|---|---|---|---|---|---|---|---|---|')
    for c in r['cells']:
        if 'failed' in c:
            lines.append(f"| {c['workload']} | {c['lines']:,} | {c['mode']} | failed | | | | | | (`{c['failed'].strip().splitlines()[-1][:40]}` after {c.get('retries', 0)} retries) |")
            continue
        lines.append(f"| {c['workload']} | {c['lines']:,} | {c['mode']} | {fmt_ms(c['cold']['p50'])} | {fmt_ms(c['cold']['p95'])} | {fmt_ms(c['warm']['p50'])} | {fmt_ms(c['warm']['p95'])} | {c.get('peak_mb') or '?'} MB | {c.get('arena_mb') or '?'} MB | {c.get('image_bytes') or 0:,} B |")
    lines.append('')
    lines.append('Cold phase split, p50 over the runs (ms):')
    lines.append('')
    phases = []
    for c in r['cells']:
        for k in c.get('cold_phase_p50', {}):
            if k not in phases: phases.append(k)
    lines.append('| workload | mode | ' + ' | '.join(phases) + ' |')
    lines.append('|---|---|' + '---|' * len(phases))
    for c in r['cells']:
        if 'failed' in c: continue
        lines.append(f"| {c['workload']} | {c['mode']} | " + ' | '.join(f"{c['cold_phase_p50'].get(k, 0):.0f}" for k in phases) + ' |')
    lines.append('')
table = '\n'.join(lines)

with open(doc, encoding='utf-8') as f:
    text = f.read()
start = text.index('<!-- baseline tables -->') + len('<!-- baseline tables -->')
end = text.index('<!-- end baseline tables -->')
text = text[:start] + '\n\n' + table + '\n' + text[end:]
with open(doc, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
print('rendered', doc)
