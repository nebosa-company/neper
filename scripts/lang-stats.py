"""Compare what it costs an LLM to write Neper, Dart, Rust and Python.

Reads every Claude Code transcript under ~/.claude/projects. Code reaches a file three
ways and all three count: the Write/Edit tools, `cat > file <<EOF` heredocs, and Python
patch or generator scripts (written to a .py file or inlined as `python - <<EOF`) whose
old/new strings carry the code. A script's new code is credited to the language it
patches, and so is the script's whole cost; a run of the script is one edit application,
so an `assert count == 1` failure is an edit that did not apply. All other Python in a
session (test oracles, analysis, doc patches) is tooling for that session's host
language: it costs the host and lands no code. Python's own row is project scripts:
.py files inside a repo, outside scratch and build folders. The columns are explained
below the table.
"""
import ast, json, glob, os, re, ntpath, warnings, collections as C

warnings.filterwarnings('ignore', category=SyntaxWarning)  # transcript scripts are parsed, not run

ROOT = os.path.expanduser('~/.claude/projects')
LANG = {'.e': 'Neper', '.dart': 'Dart', '.rs': 'Rust', '.py': 'Python'}
CODE = {'e': 'Neper', 'dart': 'Dart', 'rs': 'Rust'}  # what a script may patch and be credited for
ROWS = ['Neper', 'Dart', 'Rust', 'Python']
BUILD = re.compile(r'\b(cargo|flutter|dart|neper|tsc|npm|pnpm|node|pytest|run\.sh|suite|make|gcc|clang|bootstrap|go (build|test)|dotnet)\b')
TARGET = re.compile(r"""['"]([^'"\n]{1,200}?\.(e|dart|rs|md|json|jsonl|ps1|sh|html|txt|ebnf|py|c|h|toml|yaml|pas|dpr))['"]""")
HEREDOC = re.compile(r"(?ms)^([^\n]*?<<-?\s*['\"]?(\w+)['\"]?[^\n]*)\n(.*?)\n\2[ \t]*$")
PYRUN = re.compile(r'\bpython3?\s+(?:"[^"]*[/\\])?([\w.-]+\.py)\b')
SCRATCH = re.compile(r'scratchpad|[\\/](build|tmp|Temp)[\\/]', re.I)


def script_kind(code):
    """('patch'|'generate', credited language or None) for a script that writes files, else None."""
    ext = C.Counter(m.group(2) for m in TARGET.finditer(code))
    if not ext or not re.search(r"open\([^)]*['\"]w|write_text|\.write\(", code): return None
    kind = 'patch' if re.search(r'\.replace\(|\brep\(|\bedit\(|re\.sub', code) else 'generate'
    return kind, CODE.get(ext.most_common(1)[0][0])


def new_code(code, kind):
    """Bytes of new code a script carries: the second string of each (old, new) pair in a patch,
    every long string in a generator. Half of the long strings when the pairs cannot be found."""
    def is_str(n): return isinstance(n, ast.Constant) and isinstance(n.value, str)
    try: nodes = list(ast.walk(ast.parse(code)))
    except SyntaxError:
        longs = re.findall(r"(?s)('''|\"\"\")(.*?)\1", code)
        return sum(len(s.encode()) for _, s in longs) // (2 if kind == 'patch' else 1)
    longs = sum(len(n.value.encode()) for n in nodes if is_str(n) and len(n.value) >= 40)
    if kind == 'generate': return longs
    new = []
    for n in nodes:
        if isinstance(n, ast.Call) and len(n.args) >= 2 and is_str(n.args[0]) and is_str(n.args[1]): new.append(n.args[1].value)
        elif isinstance(n, ast.Tuple) and len(n.elts) == 2 and all(map(is_str, n.elts)): new.append(n.elts[1].value)
        elif isinstance(n, ast.Assign) and is_str(n.value) and any(
                isinstance(t, ast.Name) and t.id.startswith(('new', 'after', 'repl')) for t in n.targets): new.append(n.value.value)
    return sum(len(s.encode()) for s in new) if new else longs // 2


scripts = {}  # basename -> script_kind of every .py the transcripts wrote, so a later run is recognised


def landed(t, full):
    """What a tool call lands: (lang, mode, new_bytes, target_files). mode is direct (the tool
    wrote the code), script (a Python script carries it) or helper (Python tooling, no code)."""
    i = t.get('input') or {}; n = t.get('name'); out = []

    def python(path, body):
        base = ntpath.basename(path) if path else None
        if base and path.endswith('.py') and n != 'Edit': full[base] = body
        k = script_kind(full.get(base, body) if base else body)
        if base and k: scripts[base] = k
        if k and k[1]: out.append((k[1], 'script', new_code(body, k[0]), {m.group(1) for m in TARGET.finditer(body) if CODE.get(m.group(2)) == k[1]}))
        elif k or not path or SCRATCH.search(path): out.append((None, 'helper', 0, set()))
        else: out.append(('Python', 'direct', len(body.encode()), {path}))

    if n in ('Write', 'Edit', 'MultiEdit'):
        path = i.get('file_path', '')
        body = i.get('content', '') if n == 'Write' else i.get('new_string', '') if n == 'Edit' else ''.join(e.get('new_string', '') for e in i.get('edits', []))
        L = LANG.get(os.path.splitext(path)[1].lower())
        if L == 'Python': python(path, body or '')
        elif L: out.append((L, 'direct', len((body or '').encode()), {path}))
    elif n == 'Bash':
        for m in HEREDOC.finditer(str(i.get('command', ''))):
            line, body = m.group(1), m.group(3)
            if re.search(r'\bpython3?\s+-\s*<<', line): python(None, body)
            else:
                tgt = re.search(r'(?<![\d&])>\s*[\'"]?([^\s\'"&|;]+)', line)
                if not tgt: continue
                L = LANG.get(os.path.splitext(tgt.group(1))[1].lower())
                if L == 'Python': python(tgt.group(1), body)
                elif L: out.append((L, 'direct', len(body.encode()), {tgt.group(1)}))
    return out


def runs(cmd):
    """Kinds of the Python scripts a Bash command runs, by file name or inline."""
    ks = [scripts[b] for b in PYRUN.findall(cmd) if b in scripts]
    ks += [script_kind(m.group(3)) for m in HEREDOC.finditer(cmd) if re.search(r'\bpython3?\s+-\s*<<', m.group(1))]
    return ks


S = C.defaultdict(C.Counter)  # (lang, mode) -> counters

for f in glob.glob(ROOT + '/**/*.jsonl', recursive=True):
    msgs, order, results = {}, [], {}
    for line in open(f, encoding='utf8', errors='replace'):
        try: o = json.loads(line)
        except ValueError: continue
        m = o.get('message') or {}
        if o.get('type') == 'assistant' and m.get('id'):
            if m['id'] not in msgs: msgs[m['id']] = {'content': [], 'usage': {}}; order.append(m['id'])
            msgs[m['id']]['content'] += m.get('content') or []
            msgs[m['id']]['usage'] = m.get('usage') or {}
        elif o.get('type') == 'user' and isinstance(m.get('content'), list):
            for c in m['content']:
                if isinstance(c, dict) and c.get('type') == 'tool_result':
                    head = str(c.get('content'))[:300].lower()
                    results[c.get('tool_use_id')] = bool(c.get('is_error')) or ('exit code' in head and 'exit code 0' not in head)
    # first pass: what each turn lands, and the session's host language (most new code)
    full, turn, host_bytes = {}, {}, C.Counter()
    for mid in order:
        turn[mid] = [(t, landed(t, full)) for t in msgs[mid]['content'] if t.get('type') == 'tool_use']
        for _, es in turn[mid]:
            for L, mode, b, _ in es:
                if L: host_bytes[L] += b
    if not host_bytes: continue
    host = max(host_bytes, key=host_bytes.get)
    pending = 0
    for mid in order:
        msg = msgs[mid]; u = msg['usage']
        out = u.get('output_tokens', 0); think = (u.get('output_tokens_details') or {}).get('thinking_tokens', 0)
        cc = u.get('cache_creation')
        write = cc.get('ephemeral_1h_input_tokens', 0) * 2 + cc.get('ephemeral_5m_input_tokens', 0) * 1.25 if cc \
            else u.get('cache_creation_input_tokens', 0) * 1.25
        pending += u.get('input_tokens', 0) + write + u.get('cache_read_input_tokens', 0) * 0.1 + out * 5
        edits = []
        for t, es in turn[mid]:
            failed = results.get(t['id'], False)
            for L, mode, b, files in es:
                key = (L or host, mode)
                edits.append((key, b))
                S[key]['edits'] += 1; S[key]['bytes'] += b
                for p in files: S[key]['files:' + p] = 1
                if mode == 'direct': S[key]['applied'] += 1; S[key]['apply_err'] += failed
            if t.get('name') == 'Bash':
                cmd = str((t.get('input') or {}).get('command', ''))
                ks = runs(cmd)
                for k in ks:  # a patch run is an edit application; any other python run is a test run
                    if k and k[1]: S[(k[1], 'script')]['applied'] += 1; S[(k[1], 'script')]['apply_err'] += failed
                    else: S[(host, 'helper')]['builds'] += 1; S[(host, 'helper')]['build_fail'] += failed
                if not ks and (BUILD.search(cmd) or PYRUN.search(cmd)):  # a build, or a script written outside these transcripts
                    S[(host, 'helper')]['builds'] += 1; S[(host, 'helper')]['build_fail'] += failed
        if edits:  # the work leading up to an edit is charged to what it landed, by new bytes
            code = [(k, b) for k, b in edits if b]
            share = code or [((host, 'helper'), 1)]
            tot = sum(b for _, b in share)
            for k, b in share: S[k]['cost'] += pending * b / tot
            pending = 0
        if len(turn[mid]) == 1 and len(edits) == 1 and edits[0][1] >= 200 and not any(c.get('type') == 'text' for c in msg['content']):
            k = edits[0][0]; S[k]['d_bytes'] += edits[0][1]; S[k]['d_vis'] += out - think; S[k]['d_think'] += think
    S[(host, 'helper')]['cost'] += pending  # tail work (verification) belongs to the session's code

USD = 5e-6 * 1024  # $5 per million input-token equivalents, per KB
print('%-7s %7s %6s %6s %6s %7s %6s %6s %7s %9s %8s' % ('lang', 'KB', 'tok/B', 'thk/B', 'edit%', 'builds', 'fail%', 'ed/fil', 'script%', 'cost/B', '$/KB'))
for L in ROWS:
    d, s, h = S[(L, 'direct')], S[(L, 'script')], S[(L, 'helper')]
    kb = d['bytes'] + s['bytes']
    if not kb: continue
    files = sum(1 for k in list(d) + list(s) if k.startswith('files:'))
    cost_b = (d['cost'] + s['cost'] + h['cost']) / kb
    print('%-7s %7d %6.3f %6.3f %6.1f %7d %6.1f %6.1f %6.0f%% %9.1f %8.3f' % (
        L, kb // 1024, d['d_vis'] / max(d['d_bytes'], 1), d['d_think'] / max(d['d_bytes'], 1),
        100 * (d['apply_err'] + s['apply_err']) / max(d['applied'] + s['applied'], 1), h['builds'],
        100 * h['build_fail'] / max(h['builds'], 1), (d['edits'] + s['edits']) / max(files, 1), 100 * s['bytes'] / kb, cost_b, cost_b * USD))

print('\nhow the code was delivered ($/KB of new code, and output tokens per new byte in single-edit replies):')
for L in ROWS:
    d, s, h = S[(L, 'direct')], S[(L, 'script')], S[(L, 'helper')]
    if not d['bytes']: continue
    print('%-7s direct %5.3f $/KB %5.2f tok/B   via python scripts %5.3f $/KB %5.2f tok/B   helper python (oracles, analysis, docs) $%.0f' % (
        L, d['cost'] / max(d['bytes'], 1) * USD, d['d_vis'] / max(d['d_bytes'], 1),
        s['cost'] / max(s['bytes'], 1) * USD, s['d_vis'] / max(s['d_bytes'], 1), h['cost'] * 5e-6))

print('''
KB      new code landed, in KB: direct edits plus the new strings of Python patch/generator scripts
tok/B   visible output tokens per byte of code in replies that are exactly one direct edit
thk/B   thinking tokens per byte of code, from the same replies
edit%   edit applications that failed: a Write/Edit error, or a patch script run that failed
builds  build and test commands run in sessions whose host language this is (python oracles included)
fail%   those commands that failed
ed/fil  edits per distinct target file, a measure of rework
script% share of the new code that arrived inside Python patch/generator scripts
cost/B  tokens spent per byte of new code, in input-token equivalents: all the reading, thinking,
        testing and helper scripting that led to the edit (output x5, 1h cache write x2,
        5m cache write x1.25, cache read x0.1)
$/KB    cost/B in USD per KB at $5 per million input tokens (Opus 5 list price)''')
