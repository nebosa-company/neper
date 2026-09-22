"""Register a batch of library modules in a repo root: fences in module-apis.md,
entries in modules.json (append-only), and fixture blocks in run.ps1/run.sh.

usage: python add_batch.py <root> <batch.json>
batch.json: {"decision": "D835", "modules": [
  {"name": "e.math.ntheory", "deps": [], "fixture": "math_ntheory",
   "anchor": "### `e.math.fixed`\n", "note": "...", "comment": "..."}]}
`anchor` is the fence heading the new fence is inserted BEFORE. A module with
"refresh": true has its existing fence regenerated from source (nothing else changes).
"""
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
batch = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))

def lib_path(name):
    return root / 'lib' / 'e' / (name[2:].replace('.', '/') + '.e')

def fence(name):
    types, errors, consts, fns = [], [], [], []
    for ln in lib_path(name).read_text(encoding='utf-8').splitlines():
        m = re.match(r'^(fn|type|error|const|var)\s+(\w+)', ln)
        if not m:
            continue
        line = re.sub(r'\s*//.*$', '', ln).rstrip()  # the checked source carries no trailing comment
        kind = m.group(1)
        if kind == 'fn':
            fns.append(line.split(' {')[0])
        elif kind == 'error':
            errors.append(line)
        elif kind == 'const':
            consts.append(line)
        else:
            types.append(line)
    head = types + errors + consts
    return '\n'.join(head) + ('\n\n' if head else '') + '\n'.join(fns)

# module-apis.md
apis = root / 'docs' / 'module-apis.md'
text = apis.read_text(encoding='utf-8')
for m in batch['modules']:
    heading = f"### `{m['name']}`\n"
    if m.get('refresh'):
        start = text.index(heading)
        open_at = text.index('```neper\n', start)
        close_at = text.index('\n```\n', open_at)
        fresh = fence(m['name'])
        fresh_names = set(re.findall(r'^fn (\w+)', fresh, re.M))
        # Seeded intrinsics (e.str's format, push_err) have fence lines but no source line: keep them.
        kept = [l for l in text[open_at + 9:close_at].split('\n')
                if l.startswith('fn ') and re.match(r'fn (\w+)', l).group(1) not in fresh_names]
        text = text[:open_at] + '```neper\n' + fresh + (('\n' + '\n'.join(kept)) if kept else '') + text[close_at:]
        continue
    assert heading not in text, m['name']
    block = heading + '\n```neper\n' + fence(m['name']) + '\n```\n\n' + m['note'].strip() + '\n\n'
    assert text.count(m['anchor']) == 1, m['anchor']
    text = text.replace(m['anchor'], block + m['anchor'])
apis.write_text(text, encoding='utf-8', newline='\n')

# modules.json
plan_path = root / 'docs' / 'modules.json'
plan = json.loads(plan_path.read_text(encoding='utf-8'))
mods = plan['modules']
for m in [x for x in batch['modules'] if x.get('refresh') and 'deps' in x]:
    # A refreshed module may have gained imports; its dependency list follows its source.
    [x for x in mods if x['name'] == m['name']][0]['direct_dependencies'] = m['deps']
for m in [x for x in batch['modules'] if not x.get('refresh')]:
    assert not any(x['name'] == m['name'] for x in mods), m['name']
    prefix = m['name'].rsplit('.', 1)[0] + '.'
    candidates = [i for i, x in enumerate(mods) if x['name'].startswith(prefix)]
    at = (max(candidates) + 1) if candidates else len(mods)
    mods.insert(at, {"name": m['name'], "layer": m.get('layer', 2), "surface": "source", "milestone": None,
                     "schedule": "later", "direct_dependencies": m['deps'], "blocked_by": []})
for t in plan['tiers']:
    if t['id'] == 'extended':
        t['modules'] += [m['name'] for m in batch['modules'] if not m.get('refresh')]
plan_path.write_text(json.dumps(plan, indent=1, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')

# run.ps1 / run.sh
def camel(fixture):
    parts = fixture.split('_')
    return parts[0] + ''.join(p.capitalize() for p in parts[1:])

ps = sh = ''
for m in batch['modules']:
    fixture = m.get('fixture')
    if not fixture:
        continue
    var, exe = camel(fixture), fixture.replace('_', '-')
    comment = m['comment'] + f" ({batch['decision']})."
    ps += (f"# {comment}\n"
           f"${var}Path = Join-Path $testBuild '{exe}-selfhost.exe'\n"
           f"${var}Written = & $compiler emit-executable (Join-Path $PSScriptRoot 'fixtures\\link\\{fixture}\\src\\main.e') $repo 'x64' 'windows' ${var}Path\n"
           f"if ($LASTEXITCODE -ne 0 -or ${var}Written -ne 'executable written') {{ throw '{fixture} emission failed' }}\n"
           f"& ${var}Path\n"
           f"if ($LASTEXITCODE -ne 0) {{ throw \"a {fixture} check failed: exit $LASTEXITCODE\" }}\n")
    sh += (f"# {comment}\n"
           f"{fixture}_written=$($test_build/neper-self emit-executable \"$repo/tests/selfhost/fixtures/link/{fixture}/src/main.e\" \"$repo\" x64 linux \"$test_build/{exe}-selfhost\")\n"
           f"[ \"${fixture}_written\" = 'executable written' ]\n"
           f"chmod +x \"$test_build/{exe}-selfhost\"\n"
           f"\"$test_build/{exe}-selfhost\"\n")
anchor = "# `e.os`'s sockets over the loopback interface: a real TCP connection and a real UDP\n"
for rel, text in (('tests/selfhost/run.ps1', ps), ('tests/selfhost/run.sh', sh)):
    path = root / rel
    raw = open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in raw else '\n'
    a = anchor.replace('\n', nl)
    assert raw.count(a) == 1, rel
    raw = raw.replace(a, text.replace('\n', nl) + a)
    open(path, 'w', encoding='utf-8', newline='').write(raw)
print('registered', len(batch['modules']), 'modules in', root)
