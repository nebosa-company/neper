"""Compare what it costs an LLM to write Neper, Python, Rust and Dart.

Reads every Claude Code transcript under ~/.claude/projects and attributes each code
edit to a language by file extension. Python patch or generator scripts written in
neper sessions that carry Neper code count as Neper (only their new code counts as
bytes); scripts that carry docs are kept apart. The columns are explained below the
table it prints.
"""
import json, glob, os, re, collections as C

ROOT = os.path.expanduser('~/.claude/projects')
# every language, not just the four reported: an edit in another language absorbs the work leading up to it
LANG = {'.e': 'neper', '.dart': 'dart', '.rs': 'rust', '.ts': 'ts', '.tsx': 'ts', '.js': 'js', '.mjs': 'js',
        '.py': 'python', '.pas': 'pascal', '.dpr': 'pascal', '.c': 'c', '.h': 'c', '.go': 'go', '.ps1': 'powershell',
        '.cs': 'csharp', '.kt': 'kotlin', '.swift': 'swift', '.java': 'java', '.cpp': 'cpp', '.sh': 'shell'}
GROUPS = {'Neper': ['neper', 'neper-via-py'], 'Python': ['python', 'python@neper'], 'Rust': ['rust'], 'Dart': ['dart']}
BUILD = re.compile(r'\b(cargo|flutter|dart|neper|tsc|npm|pnpm|node|pytest|python|run\.sh|suite|make|gcc|clang|bootstrap|go (build|test)|dotnet)\b')
TRIPLE = re.compile(r"(?s)(?:[rRbB]?)('''|\"\"\")(.*?)\1")
TARGET = re.compile(r"""['"]([^'"\n]{1,200}?\.(e|md|json|jsonl|ps1|sh|html|txt|ebnf|py|c|h|toml|yaml))['"]""")
DOCS = {'md', 'json', 'jsonl', 'html', 'txt', 'ebnf'}


def script_kind(code):
    """'patch neper', 'generate docs', ... for a script that writes files; None otherwise."""
    ext = C.Counter(m.group(2) for m in TARGET.finditer(code))
    if not ext or not re.search(r"open\([^)]*['\"]w|write_text|\.write\(", code): return None
    top = ext.most_common(1)[0][0]
    kind = 'patch' if re.search(r'\.replace\(|\brep\(|\bedit\(|re\.sub', code) else 'generate'
    return kind + (' neper' if top == 'e' else ' docs' if top in DOCS else ' other')


S = C.defaultdict(C.Counter)
full = {}  # a script's full text from its Write, so a later Edit fragment is classified by the whole file

for f in glob.glob(ROOT + '/**/*.jsonl', recursive=True):
    neper_session = 'repos-neper' in f
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
    last_lang, pending = None, 0
    for mid in order:
        msg = msgs[mid]; u = msg['usage']
        out = u.get('output_tokens', 0); think = (u.get('output_tokens_details') or {}).get('thinking_tokens', 0)
        cc = u.get('cache_creation')
        write = cc.get('ephemeral_1h_input_tokens', 0) * 2 + cc.get('ephemeral_5m_input_tokens', 0) * 1.25 if cc \
            else u.get('cache_creation_input_tokens', 0) * 1.25
        pending += u.get('input_tokens', 0) + write + u.get('cache_read_input_tokens', 0) * 0.1 + out * 5
        tools = [c for c in msg['content'] if c.get('type') == 'tool_use']
        edits = []
        for t in tools:
            i = t.get('input') or {}; n = t.get('name'); path = i.get('file_path', '')
            if n == 'Write': code = i.get('content', '')
            elif n == 'Edit': code = i.get('new_string', '')
            elif n == 'MultiEdit': code = ''.join(e.get('new_string', '') for e in i.get('edits', []))
            else: code = None
            L = LANG.get(os.path.splitext(path)[1].lower()) if code is not None else None
            if L == 'python' and neper_session:
                if n == 'Write': full[path] = code
                kind = script_kind(full.get(path, code)) or ''
                if kind.endswith('neper'):
                    L = 'neper-via-py'
                    strs = [m.group(2) for m in TRIPLE.finditer(code)]
                    # a patch carries old/new pairs; only the new half is new code
                    S[L]['new_code'] += sum(len(x.encode()) for x in (strs[1::2] if kind.startswith('patch') else strs))
                elif kind.endswith('docs'): L = 'docs-via-py'
                else: L = 'python@neper'
            if L:
                edits.append((L, code)); last_lang = L
                s = S[L]; s['edits'] += 1; s['bytes'] += len(code.encode())
                s['edit_err'] += results.get(t['id'], False); s['files:' + path] = 1
            if n == 'Bash' and BUILD.search(str(i.get('command', ''))):
                cmd = str(i.get('command', ''))
                if re.search(r'\.py\b|^\s*python', cmd): BL = 'python@neper' if neper_session else 'python'
                elif neper_session and re.search(r'\bneper\b|run\.sh|\.e\b|suite|bootstrap', cmd): BL = 'neper'
                else: BL = last_lang
                if BL: S[BL]['builds'] += 1; S[BL]['build_fail'] += results.get(t['id'], False)
        if edits:  # the work leading up to an edit is charged to that edit's language
            eb = sum(len(c.encode()) or 1 for _, c in edits)
            for L, c in edits: S[L]['cost'] += pending * (len(c.encode()) or 1) / eb
            pending = 0
        if len(tools) == 1 and len(edits) == 1 and not any(c.get('type') == 'text' for c in msg['content']):
            L, c = edits[0]; b = len(c.encode())
            if b >= 200: S[L]['d_bytes'] += b; S[L]['d_vis'] += out - think; S[L]['d_think'] += think
    if last_lang: S[last_lang]['cost'] += pending  # tail work (verification) belongs to the last edit

print('%-7s %7s %6s %6s %6s %7s %6s %6s %9s %8s' % ('lang', 'KB', 'tok/B', 'thk/B', 'edit%', 'builds', 'fail%', 'ed/fil', 'cost/B', '$/KB'))
for g, ks in GROUPS.items():
    t = C.Counter()
    for k in ks: t.update(S[k])
    if not t['edits']: continue
    code = t['bytes'] - S['neper-via-py']['bytes'] + t['new_code'] if g == 'Neper' else t['bytes']
    files = sum(1 for k in t if k.startswith('files:'))
    cost_b = t['cost'] / code
    print('%-7s %7d %6.3f %6.3f %6.1f %7d %6.1f %6.1f %9.1f %8.3f' % (
        g, code // 1024, t['d_vis'] / max(t['d_bytes'], 1), t['d_think'] / max(t['d_bytes'], 1),
        100 * t['edit_err'] / t['edits'], t['builds'], 100 * t['build_fail'] / max(t['builds'], 1),
        t['edits'] / files, cost_b, cost_b * 5e-6 * 1024))

print('''
KB      new code written, in KB (Neper includes the new half of Python patch scripts)
tok/B   visible output tokens per byte of code, from replies that are exactly one code edit
thk/B   thinking tokens per byte of code, from the same replies
edit%   Write/Edit calls that failed to apply
builds  build and test commands run for the language
fail%   those commands that failed
ed/fil  edits per distinct file, a measure of rework
cost/B  tokens spent per byte, in input-token equivalents: all the reading, thinking and
        testing that led to the edit (output x5, 1h cache write x2, 5m cache write x1.25,
        cache read x0.1)
$/KB    cost/B in USD per KB at $5 per million input tokens (Opus 5 list price)''')
