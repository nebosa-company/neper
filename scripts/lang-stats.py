"""Compare what it costs an LLM to write Neper, Dart, Rust, JS, TS and Python.

Reads every Claude Code transcript under ~/.claude/projects, every Codex rollout under
~/.codex, and the DeepSeek steps in opencode's database. A row is a language, all agents
pooled; with --harness it is a language as one agent wrote it, and with --harness claude (codex, dsh) only that
agent is read. Codex's apply_patch counts as Write/Edit and its shell commands as Bash. Every
agent is costed with Claude's token weights and priced at the Opus list rate, so $ compares
effort, not bills; an opencode step a free tier ran (model id `:free`, or a zero recorded cost) carries
no dollars, only effort, and the period line says how many.

Code reaches a file four ways and all four count: the Write/Edit tools, `cat > file <<EOF`
heredocs, patch.exe specs (D1455; their new sides count as direct code), and Python patch or generator scripts (written to a .py file or inlined as `python - <<EOF`) whose
old/new strings carry the code. A script's new code is credited to the language it
patches, and so is the script's whole cost; a run of the script is one edit application,
so an `assert count == 1` failure is an edit that did not apply. All other Python in a
session (test oracles, analysis, doc patches) is tooling for that session's host
language: it costs the host and lands no code. Python's own row is project scripts:
.py files inside a repo, outside scratch and build folders; a source file of any language
written into one of those is a probe, whose cost is the host's and which lands nothing. A failed
build that carries neither a compile code nor a test signature is the shell's (plumb%), not
the language's (fail%). A scorecard and the four
tables it scores follow; with --help each has its columns explained beneath it. A KB is 1000 bytes of
source, never tokens.
"""
import argparse, ast, io, json, glob, os, re, sys, ntpath, textwrap, time, warnings, statistics, sqlite3, itertools, collections as C
from datetime import datetime

AXES = {  # every judged column, by what it measures
    'Cost (tokens / USD)': ['cost/B', '$/KB', 'direct $/KB', 'script $/KB', 'outK/KB', 'tok/B', 'thk/B', 'direct tok/B', 'script tok/B'],
    'Rework (iterations)': ['ed/fil', 'selfcor%', 'turns/ed', 'fix turns', '1-edit%'],
    'Correctness (right first time)': ['edit%', 'fail%', '1st-ok%', 'repeat%'],
    'Time': ['bld ms', 'cmp ms', 'p90 ms', 'mdl s/KB', 'tool s/KB'],
    'Context load': ['ctx Ktk', 'read/KB', 'diag B', 'cache%'],
    'Style': ['prose K/KB', 'script%']}
JUDGED = sum(map(len, AXES.values()))
AXES_HELP = 'score axes: each judged column weighs equally in the scorecard\n\n%-32s %-6s %s\n' % ('axis', 'share', 'columns') + '\n'.join(
    '%-32s %-6s %s' % (a if i == 0 else '', '%d/%d' % (len(cs), JUDGED) if i == 0 else '', ln)
    for a, cs in AXES.items() for i, ln in enumerate(textwrap.wrap(', '.join(cs), 50)))
ap = argparse.ArgumentParser(description=__doc__, epilog=AXES_HELP, formatter_class=argparse.RawDescriptionHelpFormatter, add_help=False)
ap.add_argument('-h', '--help', action='store_true', help='run as usual and explain every column beneath its table')
ap.add_argument('-c', '--color', action='store_true', help='mark best, second best and worst per column even when not on a terminal')
ap.add_argument('-d', '--days', type=float, help='only data from the last DAYS days')
ap.add_argument('-a', '--harness', nargs='?', const='split', choices=['claude', 'codex', 'dsh', 'opencode', 'split'], metavar='AGENT',
                help='alone: split every row by agent (claude, codex, deepseek) and score each harness apart; '
                     'with claude, codex or dsh (DeepSeek): read that agent only')
ARGS = ap.parse_args()
ONLY = {'claude': 'claude', 'codex': 'codex', 'dsh': 'deepseek', 'opencode': 'opencode'}.get(ARGS.harness)  # the one agent read, or None for all
ARGS.harness = ARGS.harness == 'split'  # every later test of it asks whether rows are split by agent
if ARGS.help: print(ap.format_help())


def explain(text):
    """A column legend, printed only with --help."""
    if ARGS.help: print(text)
NOW = time.time()
CUTOFF = NOW - ARGS.days * 86400 if ARGS.days else 0  # a reply older than this is left out

COLOR = sys.stdout.isatty() or ARGS.color
if COLOR and os.name == 'nt': os.system('')  # switches the console to honour ANSI escapes
GREEN, CYAN, RED, END = ('\033[32m', '\033[36m', '\033[31m', '\033[0m') if COLOR else ('', '', '', '')

warnings.filterwarnings('ignore', category=SyntaxWarning)  # transcript scripts are parsed, not run

ROOT = os.path.expanduser('~/.claude/projects')
LANG = {'.e': 'Neper', '.dart': 'Dart', '.rs': 'Rust', '.js': 'JS', '.mjs': 'JS', '.jsx': 'JS', '.ts': 'TS', '.tsx': 'TS', '.py': 'Python'}
CODE = {'e': 'Neper', 'dart': 'Dart', 'rs': 'Rust', 'js': 'JS', 'ts': 'TS'}  # what a script may patch and be credited for
ROWS = ['Neper', 'Dart', 'Rust', 'JS', 'TS', 'Python']
# neper is the binary (neper-self, neper-try.exe), never the repo path: repos/neper, D--repos-neper, src/neper.e
BUILD = re.compile(r'\b(cargo|flutter|dart|(?<!-)(?<!repos[\\/])neper(?:-\w+)*(?:\.exe)?(?![\w\\/.-])|tsc|npm|pnpm|node|vitest|jest|pytest|run\.sh|suite|make|gcc|clang|bootstrap|go (build|test)|dotnet)\b')
COMPILE = {'Neper': re.compile(r'\bE-[A-Z]+-\d{4}\b'), 'Rust': re.compile(r'error(\[E\d{4}\]|: )'), 'Dart': re.compile(r'\bError: |\berror •'),
           'JS': re.compile(r'\b(SyntaxError|TypeError|ReferenceError)\b'), 'TS': re.compile(r'\berror TS\d{4}\b'), 'Python': re.compile(r'Traceback|SyntaxError')}
# A failure that is the program's rather than the shell's (T030): an assertion, a panic, a trap, a
# timeout, a suite's own throw at one of its lines, the bootstrap lint. A failed build-shaped command
# with neither this nor a compile code is plumbing -- a PowerShell parse, a blocked sleep, a denied
# permission, an awk error, a missing file -- and is reported apart from fail% and 1st-ok%.
TESTFAIL = re.compile(r'\bassert|Assertion|\bpanicked\b|\btrap(?:ped)?\b|timed out|\btimeout\b|\bFAIL|\bthrow\b|run\.(?:ps1|sh):\d+|lint_bootstrap|\bexit(?:ed)? [1-9]|test result: FAILED')
# A command that compiles and does nothing else: one compiler invocation, after an optional `cd DIR &&`,
# with nothing chained, piped or run after it. Its wall time is the compiler's, not a suite's.
ONLY_COMPILE = re.compile(r'^\s*(?:cd\s+\S+\s*&&\s*)?\S*(?:neper(?:-\w+)*(?:\.exe)?\s+(?:build|check|emit-executable|emit-object|emit-em|check-file|build-file)'
                          r'|cargo\s+(?:build|check)|tsc|dart\s+(?:analyze|compile)|flutter\s+analyze)\b[^;&|\n]*$')
READS = ('Read', 'Grep', 'Glob')
TARGET = re.compile(r"""['"]([^'"\n]{1,200}?\.(e|dart|rs|js|ts|md|json|jsonl|ps1|sh|html|txt|ebnf|py|c|h|toml|yaml|pas|dpr))['"]""")
HEREDOC = re.compile(r"(?ms)^([^\n]*?<<-?\s*['\"]?(\w+)['\"]?[^\n]*)\n(.*?)\n\2[ \t]*$")
PYRUN = re.compile(r'\bpython3?\s+(?:"[^"]*[/\\])?([\w.-]+\.py)\b')
SCRATCH = re.compile(r'scratchpad|[\\/](build|tmp|Temp)[\\/]', re.I)
SPEC = re.compile(r'(?m)^@@@ (.+?)\s*$')  # a patch.exe spec (D1455): `@@@ path`, then <<< old === new >>> blocks
PATCHER = re.compile(r'\bpatch\.exe\b')
USD = 5e-6  # dollars per input-token equivalent: Opus 5 list price, $5 per million
KB = 1000   # a kilobyte of source, not a kibibyte
CODES = {'Neper': re.compile(r'\bE-[A-Z]+-\d{4}\b'), 'Rust': re.compile(r'\bE\d{4}\b'), 'TS': re.compile(r'\bTS\d{4}\b'),
         'Dart': re.compile(r'• ([a-z_]{6,})\s*$', re.M), 'JS': re.compile(r'\b[A-Z][A-Za-z]*Error\b'), 'Python': re.compile(r'\b[A-Z][A-Za-z]*Error\b')}


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


def spec_code(body):
    """What a patch.exe spec lands, one entry per file: the new sides of its edits, written directly."""
    parts = SPEC.split(body)  # text before the first file, then path, section, path, section...
    out = []
    for path, section in zip(parts[1::2], parts[2::2]):
        L = LANG.get(os.path.splitext(path)[1].lower())
        if L and not (L == 'Python' and SCRATCH.search(path)):
            out.append((L, 'direct', sum(len(n.encode()) for n in re.findall(r'(?ms)^===\n(.*?)^>>>', section)), {path}))
    return out


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
        elif L and SCRATCH.search(path): out.append((None, 'helper', 0, set()))  # a probe program: work, not landed code (T030)
        elif L: out.append((L, 'direct', len((body or '').encode()), {path}))
        elif n == 'Write' and SPEC.search(body or ''): out += spec_code(body)
    elif n == 'Bash':
        for m in HEREDOC.finditer(str(i.get('command', ''))):
            line, body = m.group(1), m.group(3)
            if re.search(r'\bpython3?\s+-\s*<<', line): python(None, body)
            elif SPEC.search(body): out += spec_code(body)
            else:
                tgt = re.search(r'(?<![\d&])>\s*[\'"]?([^\s\'"&|;]+)', line)
                if not tgt: continue
                L = LANG.get(os.path.splitext(tgt.group(1))[1].lower())
                if L == 'Python': python(tgt.group(1), body)
                elif L and SCRATCH.search(tgt.group(1)): out.append((None, 'helper', 0, set()))
                elif L: out.append((L, 'direct', len(body.encode()), {tgt.group(1)}))
    return out


def runs(cmd):
    """Kinds of the Python scripts a Bash command runs, by file name or inline."""
    ks = [scripts[b] for b in PYRUN.findall(cmd) if b in scripts]
    ks += [script_kind(m.group(3)) for m in HEREDOC.finditer(cmd) if re.search(r'\bpython3?\s+-\s*<<', m.group(1))]
    return ks


def when(o):
    try: return datetime.fromisoformat(o['timestamp'].replace('Z', '+00:00')).timestamp()
    except (KeyError, ValueError, AttributeError): return None


def claude():
    """Each Claude Code transcript as (agent, msgs, order, results): msgs maps an assistant message id to
    its content blocks, usage, the time of the record before it and its own time; results maps a
    tool_use id to its output text, time and whether it failed. The other agents are read into this shape."""
    for f in glob.glob(ROOT + '/**/*.jsonl', recursive=True):
        if os.path.getmtime(f) < CUTOFF: continue  # last written before the window: nothing in it counts
        msgs, order, results, last_user = {}, [], {}, None
        for line in open(f, encoding='utf8', errors='replace'):
            try: o = json.loads(line)
            except ValueError: continue
            m = o.get('message') or {}; ts = when(o)
            if o.get('type') == 'assistant' and m.get('id'):
                if m['id'] not in msgs: msgs[m['id']] = {'content': [], 'usage': {}, 'after': last_user, 'ts': ts}; order.append(m['id'])
                msgs[m['id']]['content'] += m.get('content') or []
                msgs[m['id']]['usage'] = m.get('usage') or {}
                msgs[m['id']]['ts'] = ts or msgs[m['id']]['ts']
            elif o.get('type') == 'user':
                last_user = ts or last_user
                if isinstance(m.get('content'), list):
                    for c in m['content']:
                        if isinstance(c, dict) and c.get('type') == 'tool_result':
                            text = str(c.get('content')); head = text[:300].lower()
                            results[c.get('tool_use_id')] = {'text': text, 'ts': ts, 'failed': bool(c.get('is_error')) or ('exit code' in head and 'exit code 0' not in head)}
        yield 'claude', msgs, order, results


JS_STR = r'"(?:[^"\\]|\\.)*"|`[^`]*`'
CMD = re.compile(r'\b(?:cmd|command)"?\s*:\s*(' + JS_STR + ')')
PATCH = re.compile(r'"\*\*\* Begin Patch(?:[^"\\]|\\.)*"|`\*\*\* Begin Patch[^`]*`')
HUNK = re.compile(r'^\*\*\* (Add|Update) File: (.+?)\s*$((?:\n(?!\*\*\* ).*)*)', re.M)
EXIT = re.compile(r'(?i)^Script failed|\bexit(?:_code| code)?"?\s*[=:]\s*-?[1-9]', re.M)


def js_str(s):
    """The value of a JS string literal: a double-quoted one is JSON, a template literal is raw."""
    if s[0] == '`': return s[1:-1]
    try: return json.loads(s)
    except ValueError: return s[1:-1]


def codex_calls(p, cid):
    """Claude-shaped tool_use blocks for one Codex call. apply_patch becomes a Write per added file and an
    Edit per updated one (new side = added and context lines, like an Edit's new_string); every shell
    command becomes a Bash. The newer Codex wraps both in an `exec` JavaScript cell, possibly several."""
    src = p.get('input') or p.get('arguments') or ''
    if p.get('type') == 'function_call':
        try: a = json.loads(src)
        except ValueError: a = {}
        c = a.get('command') or a.get('cmd')
        cmds, patches = [' '.join(c) if isinstance(c, list) else c] if c else [], []
    elif p.get('name') == 'apply_patch': cmds, patches = [], [src]
    else: cmds, patches = [js_str(m.group(1)) for m in CMD.finditer(src)], [js_str(m.group(0)) for m in PATCH.finditer(src)]
    out = [{'name': 'Bash', 'input': {'command': c}} for c in cmds]
    for patch in patches:
        for m in HUNK.finditer(patch):
            lines = m.group(3).split('\n')
            new = '\n'.join(l[1:] for l in lines if l[:1] in '+ ' and l)
            old = '\n'.join(l[1:] for l in lines if l[:1] in '- ' and l)
            out.append({'name': 'Write', 'input': {'file_path': m.group(2), 'content': new}} if m.group(1) == 'Add'
                       else {'name': 'Edit', 'input': {'file_path': m.group(2), 'old_string': old, 'new_string': new}})
    return [dict(b, type='tool_use', id='%s#%d' % (cid, n)) for n, b in enumerate(out)]


def codex():
    """Codex rollouts. A model response is the items up to its token_count event (later duplicates are
    dropped); shell exit codes reach the log only when the model printed them, so a failure is a failed
    script cell, a printed non-zero exit, or an apply_patch error."""
    home = os.path.expanduser('~/.codex')
    for f in glob.glob(home + '/sessions/**/*.jsonl', recursive=True) + glob.glob(home + '/archived_sessions/*.jsonl'):
        if os.path.getmtime(f) < CUTOFF: continue
        msgs, order, results, last_user, cur = {}, [], {}, None, None
        for line in open(f, encoding='utf8', errors='replace'):
            try: o = json.loads(line)
            except ValueError: continue
            p = o.get('payload') or {}; k = p.get('type'); ts = when(o)
            if o.get('type') != 'response_item' and k != 'token_count': continue
            if k in ('function_call', 'custom_tool_call', 'reasoning') or (k == 'message' and p.get('role') == 'assistant'):
                if cur is None: cur = len(order); msgs[cur] = {'content': [], 'usage': {}, 'after': last_user, 'ts': ts}; order.append(cur)
                msgs[cur]['ts'] = ts or msgs[cur]['ts']
                if k == 'message': msgs[cur]['content'] += [{'type': 'text', 'text': c.get('text', '')} for c in p.get('content') or []]
                elif k != 'reasoning': msgs[cur]['content'] += codex_calls(p, p.get('call_id'))
            elif k in ('function_call_output', 'custom_tool_call_output'):
                out = p.get('output')
                text = ''.join(x.get('text', '') for x in out if isinstance(x, dict)) if isinstance(out, list) else str(out)
                results[p.get('call_id')] = {'text': text, 'ts': ts, 'failed': bool(EXIT.search(text[:2000]))}
                last_user = ts or last_user
            elif k == 'message': last_user = ts or last_user
            elif k == 'token_count' and cur is not None and (p.get('info') or {}).get('last_token_usage'):
                u = p['info']['last_token_usage']; cached = u.get('cached_input_tokens', 0)
                msgs[cur]['usage'] = {'input_tokens': u.get('input_tokens', 0) - cached, 'cache_read_input_tokens': cached,
                                      'output_tokens': u.get('output_tokens', 0), 'output_tokens_details': {'thinking_tokens': u.get('reasoning_output_tokens', 0)}}
                cur = None
        yield 'codex', msgs, order, results


OPENCODE = {'read': 'Read', 'grep': 'Grep', 'glob': 'Glob', 'bash': 'Bash', 'write': 'Write', 'edit': 'Edit'}


FREE_MODEL = re.compile(r':free|-free', re.I)


def opencode_steps(agent, wanted):
    """Steps from the opencode database, one message per step (step-start to step-finish).
    `wanted(modelID)` picks the steps this agent owns; the other models' steps in a session are
    skipped. A step is `free` when its model id says so or opencode recorded a zero cost for a
    step that spent tokens (D2314): effort is still counted, dollars are not."""
    db = os.path.expanduser('~/.local/share/opencode/opencode.db')
    if not os.path.exists(db): return
    rows = sqlite3.connect('file:%s?mode=ro' % db, uri=True).execute(
        'select p.session_id, m.data, p.data, p.time_created from part p join message m on p.message_id = m.id order by p.session_id, p.time_created, p.id')
    for _, grp in itertools.groupby(rows, key=lambda r: r[0]):
        msgs, order, results, last_user, cur = {}, [], {}, None, None
        for _, md, pd, t in grp:
            m, p = json.loads(md), json.loads(pd); ts = t / 1000
            if m.get('role') != 'assistant': last_user = ts; continue
            if not wanted(m.get('modelID', '')): cur = None; continue
            free = bool(FREE_MODEL.search(m.get('modelID', ''))) or (m.get('cost') == 0 and m.get('providerID') == 'opencode')
            k = p.get('type')
            if k == 'step-start': cur = len(order); msgs[cur] = {'content': [], 'usage': {}, 'after': ts, 'ts': None, 'free': free, 'model': m.get('modelID', '')}; order.append(cur)
            elif cur is None: continue
            elif k == 'text': msgs[cur]['content'].append({'type': 'text', 'text': p.get('text', '')})
            elif k == 'tool':
                s = p.get('state') or {}; i = s.get('input') or {}; n = OPENCODE.get(p.get('tool'), p.get('tool'))
                if n in ('Write', 'Edit', 'Read'): i = {'file_path': i.get('filePath', ''), 'content': i.get('content'), 'old_string': i.get('oldString', ''), 'new_string': i.get('newString', '')}
                st = (s.get('time') or {}).get('start'); msgs[cur]['ts'] = min(filter(None, (msgs[cur]['ts'], st and st / 1000)), default=None)
                msgs[cur]['content'].append({'type': 'tool_use', 'id': p.get('callID'), 'name': n, 'input': i})
                end = (s.get('time') or {}).get('end')
                results[p.get('callID')] = {'text': str(s.get('output') or s.get('error') or ''), 'ts': end / 1000 if end else ts,
                                            'failed': s.get('status') == 'error' or (s.get('metadata') or {}).get('exit') not in (None, 0)}
            elif k == 'step-finish':
                tk = p.get('tokens') or {}; c = tk.get('cache') or {}
                msgs[cur]['usage'] = {'input_tokens': tk.get('input', 0), 'cache_read_input_tokens': c.get('read', 0), 'cache_creation_input_tokens': c.get('write', 0),
                                      'output_tokens': tk.get('output', 0) + tk.get('reasoning', 0), 'output_tokens_details': {'thinking_tokens': tk.get('reasoning', 0)}}
                msgs[cur]['ts'] = msgs[cur]['ts'] or ts; cur = None
        yield agent, msgs, order, results


def deepseek():
    return opencode_steps('deepseek', lambda model: 'deepseek' in model)


def opencode():
    """Every opencode step a DeepSeek model did not run: the free tiers and the other providers."""
    return opencode_steps('opencode', lambda model: bool(model) and 'deepseek' not in model)


S = C.defaultdict(C.Counter)       # (lang, mode) -> counters
FREE_TURNS = C.Counter()           # model id -> steps priced at zero (free tier)
build_s = C.defaultdict(list)      # host lang -> wall seconds of each build/test command
compile_s = C.defaultdict(list)    # host lang -> wall seconds of each command that only compiled
ctx_tok = C.defaultdict(list)      # lang -> context tokens at each turn that landed its code
fix_t = C.defaultdict(list)        # host lang -> assistant turns from a compile failure to the next passing build
diag_b = C.defaultdict(list)       # host lang -> bytes of each failed build/test output
cache = C.defaultdict(lambda: [0, 0])  # lang -> [cache-read tokens, context tokens] over turns that landed its code

AGENTS = ['claude', 'codex', 'deepseek', 'opencode']
span = []  # times of every reply counted, for the period line
for agent, msgs, order, results in itertools.chain(*(read() for name, read in zip(AGENTS, (claude, codex, deepseek, opencode)) if ONLY in (None, name))):
    tag = lambda L: '%s %s' % (L, agent) if ARGS.harness else L  # with --harness a row is a language as one agent wrote it
    order = [mid for mid in order if (msgs[mid]['ts'] or 0) >= CUTOFF]
    span += [msgs[mid]['ts'] for mid in order if msgs[mid]['ts']]
    # first pass: what each turn lands, and the session's host language (most new code)
    full, turn, host_bytes = {}, {}, C.Counter()
    for mid in order:
        turn[mid] = [(t, landed(t, full)) for t in msgs[mid]['content'] if t.get('type') == 'tool_use']
        for _, es in turn[mid]:
            for L, mode, b, _ in es:
                if L: host_bytes[L] += b
    if not host_bytes: continue
    host = max(host_bytes, key=host_bytes.get); hk = tag(host)
    H = S[(hk, 'helper')]
    pending, since_build, repair, last_codes, recent = C.Counter(), 0, None, set(), C.defaultdict(list)
    for ti, mid in enumerate(order):
        msg = msgs[mid]; u = msg['usage']
        out = u.get('output_tokens', 0); think = (u.get('output_tokens_details') or {}).get('thinking_tokens', 0)
        cc = u.get('cache_creation')
        write = cc.get('ephemeral_1h_input_tokens', 0) * 2 + cc.get('ephemeral_5m_input_tokens', 0) * 1.25 if cc \
            else u.get('cache_creation_input_tokens', 0) * 1.25
        ctx = u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
        # A free-tier step spent tokens but no dollars: it adds effort (tok, ctx, turns) and no cost.
        if msg.get('free'): FREE_TURNS[msg.get('model', '')] += 1
        else: pending['cost'] += u.get('input_tokens', 0) + write + u.get('cache_read_input_tokens', 0) * 0.1 + out * 5
        pending['out'] += out; pending['turns'] += 1
        text_chars = sum(len(c.get('text', '')) for c in msg['content'] if c.get('type') == 'text')
        tool_chars = sum(len(json.dumps(c.get('input'))) for c in msg['content'] if c.get('type') == 'tool_use')
        pending['prose'] += (out - think) * text_chars / max(text_chars + tool_chars, 1)  # visible tokens spent talking, not calling
        if msg['ts'] and msg['after']: pending['model_s'] += min(max(msg['ts'] - msg['after'], 0), 600)
        edits = []
        for t, es in turn[mid]:
            r = results.get(str(t.get('id')).split('#')[0]) or {}  # a Codex cell's calls share its result
            failed = r.get('failed', False)
            dur = min(max(r['ts'] - msg['ts'], 0), 1800) if r.get('ts') and msg['ts'] else 0
            pending['tool_s'] += dur
            pulled = t.get('name') in READS or (t.get('name') == 'PowerShell' and not BUILD.search(str((t.get('input') or {}).get('command', ''))))
            for L, mode, b, files in es:
                key = (tag(L or host), mode)
                edits.append((key, b))
                S[key]['edits'] += 1; S[key]['bytes'] += b
                for p in files: S[key]['files:' + p] = 1
                if mode == 'direct':
                    S[key]['applied'] += 1; S[key]['apply_err'] += failed; since_build += not failed
                    if repair: repair[1] += not failed
                if b: ctx_tok[tag(L)].append(ctx); cache[tag(L)][0] += u.get('cache_read_input_tokens', 0); cache[tag(L)][1] += ctx
            i = t.get('input') or {}
            if t.get('name') in ('Write', 'Edit') and es and es[0][1] == 'direct':  # rework of the model's own recent text
                path, L = i.get('file_path', ''), tag(es[0][0])
                if t['name'] == 'Edit':
                    S[(L, 'direct')]['edit_calls'] += 1
                    prev = '\n'.join(txt for tt, txt in recent[path] if ti - tt <= 5)
                    if prev and any(ln.strip() in prev for ln in i.get('old_string', '').splitlines() if len(ln.strip()) >= 20):
                        S[(L, 'direct')]['selfcorr'] += 1
                recent[path].append((ti, i.get('content') or i.get('new_string') or ''))
            if t.get('name') == 'Bash':
                cmd = str((t.get('input') or {}).get('command', ''))
                ks = runs(cmd)
                text = r.get('text', '')
                program_failed = failed and bool((host in COMPILE and COMPILE[host].search(text)) or TESTFAIL.search(text))
                # A patch run and a build in one command (T030): a failure with a compile code or a
                # test signature is the build's, not an edit that did not apply, and the build counts.
                chained = bool(ks) and bool(BUILD.search(cmd))
                for k in ks:  # a patch run is an edit application; any other python run is a test run
                    if k and k[1]:
                        patch_failed = failed and not (chained and program_failed)
                        S[(tag(k[1]), 'script')]['applied'] += 1; S[(tag(k[1]), 'script')]['apply_err'] += patch_failed; since_build += not patch_failed
                        if repair: repair[1] += not patch_failed
                    else: ks = []
                chained = chained and bool(ks)
                if PATCHER.search(cmd) and not es:  # a spec written earlier is applied now; its code was counted when written
                    S[(hk, 'direct')]['apply_err'] += failed
                    if not BUILD.search(cmd): continue
                plumbing = failed and not program_failed
                building = (not ks or chained) and (BUILD.search(cmd) or PYRUN.search(cmd))
                if chained and plumbing:
                    pass  # the patch failed, counted above: no build ran
                elif building and plumbing:
                    H['plumbing'] += 1  # the shell failed, not the language: no build, and the edits wait for one
                elif building:  # a build or test run, or a script written outside these transcripts
                    H['builds'] += 1; H['build_fail'] += failed; build_s[hk].append(dur)
                    if ONLY_COMPILE.match(cmd): compile_s[hk].append(dur)
                    H['fb_n'] += since_build; H['fb_ok'] += since_build * (not failed); since_build = 0
                    if failed:
                        diag_b[hk].append(len(text))
                        codes = set(CODES[host].findall(text)) if host in CODES else set()
                        if codes and last_codes: H['rediag_n'] += 1; H['rediag_hit'] += bool(codes & last_codes)
                        if codes: last_codes = codes
                        if host in COMPILE and COMPILE[host].search(text):
                            H['compile_err'] += 1
                            if repair is None: repair = [ti, 0]  # turn of the first compile failure, edits applied since
                    else:
                        last_codes = set()
                        if repair is not None:
                            fix_t[hk].append(ti - repair[0]); H['fix_n'] += 1; H['fix_one'] += repair[1] == 1; repair = None
                elif not ks and not es: pulled = True  # a shell command that only looked: cat, sed, tgrep, git, ls
            if pulled: pending['read_b'] += len(r.get('text', ''))
        if edits:  # the work leading up to an edit is charged to what it landed, by new bytes
            code = [(k, b) for k, b in edits if b]
            share = code or [((hk, 'helper'), 1)]
            tot = sum(b for _, b in share)
            for k, b in share:
                for q, v in pending.items(): S[k][q] += v * b / tot
            pending = C.Counter()
        if len(turn[mid]) == 1 and len(edits) == 1 and edits[0][1] >= 200 and not any(c.get('type') == 'text' for c in msg['content']):
            k = edits[0][0]; S[k]['d_bytes'] += edits[0][1]; S[k]['d_vis'] += out - think; S[k]['d_think'] += think
    for q, v in pending.items(): H[q] += v  # tail work (verification) belongs to the session's code


def merged(L):
    d, s, h = S[(L, 'direct')], S[(L, 'script')], S[(L, 'helper')]
    t = d + s + h
    return d, s, h, t, d['bytes'] + s['bytes']


first, last = (CUTOFF, NOW) if ARGS.days else (min(span, default=NOW), max(span, default=NOW))
print('period: %s -> %s (%s days)%s\n' % (datetime.fromtimestamp(first).strftime('%Y-%m-%d %H:%M'), datetime.fromtimestamp(last).strftime('%Y-%m-%d %H:%M'),
                                          '%g' % ARGS.days if ARGS.days else '%.0f' % ((last - first) / 86400),
                                          ('' if ARGS.days else ', all data') + (', %s only' % ONLY if ONLY else '')))
if FREE_TURNS:
    print('free tier: %s step(s) priced at $0 (effort counted, dollars not): %s\n' % (sum(FREE_TURNS.values()), ', '.join('%s %d' % kv for kv in sorted(FREE_TURNS.items()))))

FLOOR = 100 * KB  # a language with less landed source than this is too thin to compare
if ARGS.harness: ROWS = ['%s %s' % (L, a) for L in ROWS for a in AGENTS]
thin = ['%s %d KB' % (L, merged(L)[4] // KB) for L in ROWS if merged(L)[4] < FLOOR]
ROWS = [L for L in ROWS if merged(L)[4] >= FLOOR]
if thin: print('under %d KB of landed source, not shown: %s\n' % (FLOOR // KB, ', '.join(thin)))
explain(('colours: %sbest%s  %ssecond best%s  %sworst%s in each judged column; sample-size columns (KB, builds, fixes, pairs, helper $) and cmpl%% are not judged\n'
         % (GREEN, END, CYAN, END, RED, END)) if COLOR else 'run with -c/--color (or on a terminal) to mark best, second best and worst per column\n')


CONTESTS = []  # (column, better, {row label: value}) of every judged column, for the scorecard


def table(title, cols, rows):
    """cols are (name, width, format, better) with better 'low', 'high' or None for a column that
    is a sample size rather than a quality; rows are (label, values). In a judged column the best
    value is green, the second best cyan, the worst red; a None value prints as - and is not judged."""
    CONTESTS.extend((n, better, {label: vals[c] for label, vals in rows}) for c, (n, _, _, better) in enumerate(cols) if better)
    print(title)
    print('%-15s ' % ('lang agent' if ARGS.harness else 'lang') +' '.join('%*s' % (w, n) for n, w, _, _ in cols))
    for label, vals in rows:
        cells = []
        for c, (_, w, fmt, better) in enumerate(cols):
            v = vals[c]; text = '-' if v is None else fmt % v
            ranked = sorted({r[1][c] for r in rows if r[1][c] is not None}, reverse=better == 'high')
            if better and v is not None and len(ranked) > 1:
                if v == ranked[0]: text = GREEN + text + END
                elif v == ranked[-1]: text = RED + text + END
                elif v == ranked[1]: text = CYAN + text + END
            cells.append(' ' * (w - len('-' if v is None else fmt % v)) + text)
        print('%-15s ' % label + ' '.join(cells))


sys.stdout, TABLES = io.StringIO(), sys.stdout  # the scorecard is scored from these tables but printed above them
rows = []
for L in ROWS:
    d, s, h, t, kb = merged(L)
    files = sum(1 for k in list(d) + list(s) if k.startswith('files:'))
    cost_b = t['cost'] / kb
    rows.append((L, (kb // KB, d['d_vis'] / max(d['d_bytes'], 1), d['d_think'] / max(d['d_bytes'], 1),
                     100 * (d['apply_err'] + s['apply_err']) / max(d['applied'] + s['applied'], 1), h['builds'],
                     100 * h['build_fail'] / max(h['builds'], 1), 100 * h['plumbing'] / max(h['builds'] + h['plumbing'], 1),
                     (d['edits'] + s['edits']) / max(files, 1), 100 * s['bytes'] / kb, cost_b, cost_b * USD * KB)))
table('COST  (KB is kilobytes, 1000 bytes, of source text landed in files; never tokens)',
      [('KB', 7, '%d', None), ('tok/B', 6, '%.3f', 'low'), ('thk/B', 6, '%.3f', 'low'), ('edit%', 6, '%.1f', 'low'), ('builds', 7, '%d', None),
       ('fail%', 6, '%.1f', 'low'), ('plumb%', 6, '%.1f', None), ('ed/fil', 6, '%.1f', 'low'), ('script%', 7, '%.0f%%', 'low'), ('cost/B', 9, '%.1f', 'low'), ('$/KB', 8, '%.3f', 'low')], rows)

explain('''
KB       kilobytes (1000 bytes) of UTF-8 source text that landed in files of this language: the
         content of Write/Edit calls and cat heredocs, plus the new-side strings of Python
         patch/generator scripts. Source bytes, not tokens.
tok/B    visible output tokens the model emitted per byte of source landed, measured only on replies
         that were exactly one direct edit and nothing else (so the anchor text of an Edit counts)
thk/B    thinking tokens per byte of source landed, from the same replies
edit%    edit applications that failed: a Write/Edit tool error, or a patch-script run that failed
builds   build and test commands run in sessions whose host language this is (python oracles included),
         less those that failed as plumbing
fail%    those commands that failed with a compile code or a test signature (an assertion, a panic, a
         trap, a timeout, a suite's own throw): the language's failures, not the shell's
plumb%   build-shaped commands that failed with neither -- a PowerShell parse, a blocked sleep, a denied
         permission, a missing file -- as a share of all of them; not judged, not in fail% or 1st-ok%
ed/fil   edit applications per distinct target file; higher means the same files were reworked more
script%  share of the landed source bytes that arrived inside Python patch/generator scripts
cost/B   input-token equivalents spent per byte of source landed, counting every token of the turns
         that led to the edit (reading, thinking, testing, helper scripting): input x1, 1h cache
         write x2, 5m cache write x1.25, cache read x0.1, output x5
$/KB     cost/B priced at $5 per million input-token equivalents (Opus 5 list), per KB of source''')

rows = []
for L in ROWS:
    d, s, h, t, kb = merged(L)
    bs = sorted(build_s[L]) or [0]
    rows.append((L, (t['out'] / kb, statistics.median(ctx_tok[L]) / 1000 if ctx_tok[L] else 0, t['read_b'] / kb,
                     t['turns'] / max(d['applied'] + s['applied'], 1), 100 * h['fb_ok'] / max(h['fb_n'], 1),
                     statistics.median(bs) * 1000, statistics.median(compile_s[L]) * 1000 if compile_s[L] else None,
                     (bs[int(len(bs) * 0.9)] if len(bs) > 1 else bs[0]) * 1000, 100 * h['compile_err'] / max(h['build_fail'], 1),
                     t['model_s'] / kb * KB, t['tool_s'] / kb * KB)))
table('\nPROCESS  (how the code got written)',
      [('outK/KB', 8, '%.1f', 'low'), ('ctx Ktk', 8, '%.0f', 'low'), ('read/KB', 8, '%.1f', 'low'), ('turns/ed', 8, '%.1f', 'low'), ('1st-ok%', 8, '%.1f', 'high'),
       ('bld ms', 8, '%.0f', 'low'), ('cmp ms', 8, '%.0f', 'low'), ('p90 ms', 8, '%.0f', 'low'), ('cmpl%', 6, '%.1f', None), ('mdl s/KB', 9, '%.0f', 'low'), ('tool s/KB', 9, '%.0f', 'low')], rows)

explain('''
outK/KB   thousand output tokens (visible + thinking) generated per KB of source landed; the raw
          writing effort, before input and cache costs
ctx Ktk   median context size, in thousand tokens, of the turns that landed this language's code
          (input + cache read + cache write): how much the model had loaded when it wrote
read/KB   bytes of tool output the model pulled into context per byte of source landed: Read, Grep
          and Glob results plus shell commands that only looked (cat, sed, tgrep, git, ls)
turns/ed  assistant replies per edit application: reading, thinking and testing turns between edits
1st-ok%   edit applications whose first following build/test command passed
bld ms    wall-clock milliseconds of a build/test command, median, from the tool call's timestamp to
          its result's (foreground commands only, capped at 1800 s): the whole command, including
          the program or suite it runs and the 0.3-1.4 s every tool call pays
cmp ms    the same median over commands that only compiled: one compiler invocation, nothing
          chained, piped or run after it
p90 ms    the same, 90th percentile
cmpl%     share of the failed build/test commands whose output carries this language's compiler
          diagnostics (Neper E-XXXX-nnnn, Rust error[E], Dart Error:, TS error TS, JS/Python
          exception names): a compile failure rather than a test or runtime failure
mdl s/KB  seconds the model spent generating (user record to last assistant block, capped at 600 s)
          per KB of source landed
tool s/KB seconds tools ran (call to result) per KB of source landed''')

rows = []
for L in ROWS:
    d, s, h, t, kb = merged(L)
    rows.append((L, (h['fix_n'], statistics.median(fix_t[L]) if fix_t[L] else None, 100 * h['fix_one'] / h['fix_n'] if h['fix_n'] else None,
                     statistics.median(diag_b[L]) if diag_b[L] else None, h['rediag_n'], 100 * h['rediag_hit'] / h['rediag_n'] if h['rediag_n'] else None,
                     100 * d['selfcorr'] / d['edit_calls'] if d['edit_calls'] else None,
                     100 * cache[L][0] / cache[L][1] if cache[L][1] else None, t['prose'] / kb)))
table('\nREPAIR & REWORK  (what happened after the model got it wrong)',
      [('fixes', 6, '%d', None), ('fix turns', 9, '%.0f', 'low'), ('1-edit%', 8, '%.1f', 'high'), ('diag B', 8, '%.0f', 'low'), ('pairs', 6, '%d', None),
       ('repeat%', 8, '%.1f', 'low'), ('selfcor%', 8, '%.1f', 'low'), ('cache%', 7, '%.1f', 'high'), ('prose K/KB', 10, '%.2f', 'low')], rows)
explain('''
fixes      repairs observed: a build that failed with compiler diagnostics followed later by a passing
           build (sample size for the next two columns)
fix turns  median assistant replies from that failing build to the passing one: how far a diagnostic
           is from its fix
1-edit%    share of those repairs that took exactly one edit application
diag B     median bytes of a failed build/test command's output: how much the model must read to
           learn what went wrong (all languages pass through the same output condenser)
pairs      consecutive failed builds that both carried error codes (sample size for repeat%)
repeat%    share of those pairs whose second failure repeats a code from the first (Neper E-XXXX-nnnn,
           Rust Ennnn, TS TSnnnn, Dart analyzer codes, JS/Python exception names): the model misread
           or did not fix the message
selfcor%   Edit calls whose old text is a line the model itself wrote to that file within the previous
           five replies: rework of fresh code, unlike ed/fil which also counts revisiting old files
cache%     cache-read tokens as a share of the context at turns that landed this language's code:
           how stable the prompt prefix stayed
prose K/KB thousand visible output tokens spent on text blocks (explaining, not calling tools) per
           KB of source landed, splitting each reply's visible tokens by characters

The shell output condenser (RTK) strips most flutter, cargo and pytest diagnostics down to an exit
code and a file name, while neper's own commands pass through intact. Outside Neper, fixes and pairs
are therefore small and diag B measures the condenser; read this table as Neper against itself over
time, and the other rows as indicative only.''')

rows = []
for L in ROWS:
    d, s, h, t, kb = merged(L)
    rows.append((L, (d['cost'] / max(d['bytes'], 1) * USD * KB, d['d_vis'] / max(d['d_bytes'], 1),
                     s['cost'] / s['bytes'] * USD * KB if s['bytes'] else None, s['d_vis'] / s['d_bytes'] if s['d_bytes'] else None, h['cost'] * USD)))
table('\nDELIVERY  (how the code reached the file)',
      [('direct $/KB', 11, '%.3f', 'low'), ('direct tok/B', 12, '%.2f', 'low'), ('script $/KB', 11, '%.3f', 'low'), ('script tok/B', 12, '%.2f', 'low'), ('helper $', 9, '%.0f', None)], rows)
explain('''
direct    code the Write/Edit tools or a cat heredoc put in the file: $ per KB of that source, and
          visible output tokens per byte of it in replies that were exactly one such edit
script    code that arrived as the new side of a Python patch/generator script: the same two figures,
          per KB and per byte of the new code only (the script's anchors and boilerplate are cost)
helper $  dollars spent on Python that landed no code: test oracles, analysis, doc patches''')

sys.stdout, TABLES = TABLES, sys.stdout.getvalue()

# SCORECARD: every judged column above is a contest; with --harness one per harness, so a language
# only meets the languages the same agent wrote. Best scores 1, worst 0, the rest evenly by distinct value.
assert {c for c, _, _ in CONTESTS} == {c for cs in AXES.values() for c in cs}, 'AXES must name every judged column'
SPLIT = AGENTS if ARGS.harness else []  # the per-harness score columns
pts, medals = C.defaultdict(list), C.defaultdict(C.Counter)
for col, better, vals in CONTESTS:
    for a in SPLIT or ['all']:
        field = {L.split()[0]: v for L, v in vals.items() if v is not None and (not SPLIT or L.split()[1] == a)}
        ranked = sorted(set(field.values()), reverse=better == 'high')
        if len(ranked) < 2: continue
        for L, v in field.items():
            pos = ranked.index(v)
            pts[(L, 'all')].append(1 - pos / (len(ranked) - 1))
            if SPLIT: pts[(L, a)].append(pts[(L, 'all')][-1])
            if pos < 3: medals[L][pos] += 1
langs = sorted({L for L, _ in pts}, key=lambda L: -statistics.mean(pts[(L, 'all')]))
PLACE = {0: GREEN + '1st' + END, 1: CYAN + '2nd' + END, 2: '3rd'}
print('SCORECARD  (every judged column%s)' % (', each harness ranking only its own languages' if SPLIT else ''))
print('place %-7s ' % 'lang' + ''.join('%9s ' % a for a in SPLIT) + '%7s %8s %5s %5s %5s' % ('overall', 'contests', '1st', '2nd', '3rd'))
for i, L in enumerate(langs):
    per = ['%9s ' % ('%.0f' % (100 * statistics.mean(pts[(L, a)])) if pts[(L, a)] else '-') for a in SPLIT]
    print('%s   %-7s ' % (PLACE.get(i, '%dth' % (i + 1)), L) + ''.join(per) + '%7.0f %8d %5d %5d %5d' % (
        100 * statistics.mean(pts[(L, 'all')]), len(pts[(L, 'all')]), medals[L][0], medals[L][1], medals[L][2]))
explain('''
place     order by overall score
overall   mean score, 0-100, over every contest the language entered: 100 means best in every
          judged column, 0 worst in every one; this orders the table
contests  judged columns the language was compared in
1st..3rd  times the language ranked first, second or third in a contest''' + ('''
claude..  the same mean within one harness, where each agent's languages only meet each other;
          - means the agent landed too little of it. A contest there needs two languages, so
          contests counts columns x harnesses. The harnesses are unequal: Claude compares five
          languages, Codex and DeepSeek two each, where winning a column takes only beating one
          rival. Read overall with contests beside it.''' if SPLIT else '''
Without --harness every agent's work in a language is pooled into one row; run with -a to
split it by agent, or with --harness claude (codex, dsh) to read one agent only.'''))
print('\n' + TABLES, end='')
