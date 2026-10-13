#!/usr/bin/env python3
"""Independent model of the e.ui.code_editor services of D4401 (L065) for
tests/selfhost/fixtures/link/ui_code_editor_svc: registry-ID language packs and the suffix map, wrap-aware motion
over collapsed folds, per-view fold state mapped through edits, the completion source model, revisioned
diagnostics, and the bracket and JSON lints.

The model shares no code with lib/e/ui/code_editor.e. Where an outside oracle exists it is used instead of a
model: the JSON lint's error offsets come from Python's json module, the suffix map is read from the
language matrix in docs/code-editor-plan.md, and the comment and string rules of each language pack are
checked against the Pygments lexer for that language on the curated documents (the generator stops on a
mismatch). Folds are checked against a per-character provenance model. Run from the repo root to rewrite the
GENERATED block of the fixture's main.e.
"""
import json
import pathlib
import random
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gen_ui_code_editor_ext_test as ext   # the older model: scan, folds, wrap rows (no engine code)

RS, US = b'\x1e', b'\x1f'
TOK_KEYWORD, TOK_TYPE, TOK_IDENT, TOK_NUMBER, TOK_STRING, TOK_COMMENT, TOK_OPERATOR, TOK_PUNCT = 1, 2, 3, 4, 5, 6, 7, 8
ENGINE = pathlib.Path('lib/e/ui/code_editor.e').read_text(encoding='utf-8')
rnd = random.Random(4401)


# ---- packs ----------------------------------------------------------------------------------------------------
def P(lc='', bo='', bc='', q='', mq='', fold=False, nested=False, lc2='', b2o='', b2c=''):
    return dict(lc=lc, bo=bo, bc=bc, q=q, mq=mq, fold=fold, nested=nested, lc2=lc2, b2o=b2o, b2c=b2c)


# The comment, string and case rules of each new pack, written from the language references.
SEMANTICS = {
    'jsonc': P('//', '/*', '*/', '"'),
    'c': P('//', '/*', '*/', '"\''),
    'csharp': P('//', '/*', '*/', '"\''),
    'kotlin': P('//', '/*', '*/', '"\'', '"', nested=True),
    'swift': P('//', '/*', '*/', '"', '"', nested=True),
    'dart': P('//', '/*', '*/', '"\'', '"\'', nested=True),
    'r': P('#', '', '', '"\'`'),
    'protobuf': P('//', '/*', '*/', '"\''),
    'assembly': P('#', '/*', '*/', '"\'', lc2='@'),
    'intelasm': P(';', '', '', '"\'', fold=True),
    'markdown': P('', '<!--', '-->', '`'),
    'sqlite': P('--', '/*', '*/', '"\'`', fold=True),
    'mysql': P('--', '/*', '*/', '"\'`', fold=True, lc2='#'),
    'postgresql': P('--', '/*', '*/', '"\'`', fold=True),
    'objectpascal': P('//', '{', '}', "'", fold=True, b2o='(*', b2c='*)'),
    'powershell': P('#', '<#', '#>', '"\'', '"\'', fold=True),
    'terraform': P('#', '/*', '*/', '"', lc2='//'),
    'batch': P('::', '', '', '"', fold=True, lc2='rem '),
    'vbnet': P("'", '', '', '"', fold=True, lc2='rem '),
    'vbclassic': P("'", '', '', '"', fold=True, lc2='rem '),
    'fortran': P('!', '', '', '"\'', fold=True),
    'php': P('//', '/*', '*/', '"\'`', fold=True, lc2='#'),
    'ada': P('--', '', '', '"', fold=True),
    'objectivec': P('//', '/*', '*/', '"\''),
    'cobol': P('*>', '', '', '"\'', fold=True),
    'julia': P('#', '#=', '=#', '"', '"', nested=True),
    'ruby': P('#', '', '', '"\'`'),
    'perl': P('#', '', '', '"\'`'),
    'sas': P('', '/*', '*/', '"\'', fold=True),
    'matlab': P('%', '%{', '%}', '"'),
    'caml': P('', '(*', '*)', '"', '"', nested=True),
    'prolog': P('%', '/*', '*/', '"\'`'),
    'gml': P('//', '/*', '*/', '"\''),
}
# The older packs keep the ext model's tables (the lua long comment is `--[[ ]]`).
OLD = {'javascript': ext.JS, 'jsx': ext.JS, 'typescript': ext.TS, 'tsx': ext.TS, 'python': ext.PY, 'cpp': ext.C,
       'rust': ext.RUST, 'go': ext.GO, 'java': ext.JAVA, 'json': ext.JSON, 'shell': ext.SHELL, 'sql': ext.SQL,
       'css': ext.CSS, 'html': ext.HTML, 'xml': ext.HTML, 'yaml': ext.YAML, 'toml': ext.TOML, 'lua': ext.LUA}


def words_of_fn(fn):
    """The keyword and type lists of `lang_<fn>` as written in the engine source (first two string literals)."""
    m = re.search(r'fn lang_%s\([^)]*\) -> Language \{(.*?)\n\}\n' % fn, ENGINE, re.S)
    if not m: raise SystemExit('no pack function lang_%s' % fn)
    lits = re.findall(r'"((?:\\.|[^"\\])*)"', m.group(1))
    return set(lits[0].split()), set(lits[1].split())


FN_OF = {'c': 'c_dialect'}


def model_pack(pid):
    if pid in OLD:
        o = OLD[pid]
        d = P(o['lc'], o['bo'], o['bc'], o['q'], o['mq'])
        d['kw'], d['ty'] = o['kw'], o['ty']
        return d
    sem = dict(SEMANTICS[pid])
    if pid in ('sqlite', 'mysql', 'postgresql'):
        kw, ty = words_of_fn('sql_dialect')
        extra = re.search(r'id, "%s"\) \{ ret lang_sql_dialect\("([^"]*)"' % pid, ENGINE)
        if extra: ty = set(extra.group(1).split())
    else:
        kw, ty = words_of_fn(FN_OF.get(pid, pid))
    sem['kw'], sem['ty'] = kw, ty
    return sem


def is_word(c): return 48 <= c <= 57 or 65 <= c <= 90 or 97 <= c <= 122 or c == 95 or c >= 128


def scan_pack(doc, L):
    """Tokens per line as [(kind, start, end)] with nesting, two block pairs, case folding and a second line
    comment, from scratch."""
    starts = [0] + [i + 1 for i, c in enumerate(doc) if c == 10]
    out, state = [], None  # None normal; ('b', pair, depth); ('q', ch)

    def sw(p, e, s, fold=False):
        if not s or p + len(s) > e: return False
        chunk = doc[p:p + len(s)]
        if fold: chunk = bytes(c + 32 if 65 <= c <= 90 else c for c in chunk)
        return chunk == s.encode()

    def comment(p, e, pair, depth):
        op, cl = (L['bo'], L['bc']) if pair == 1 else (L['b2o'], L['b2c'])
        while p < e and depth > 0:
            if sw(p, e, cl): p += len(cl); depth -= 1
            elif L['nested'] and pair == 1 and sw(p, e, op): p += len(op); depth += 1
            else: p += 1
        return p, depth

    for li, s in enumerate(starts):
        e = starts[li + 1] - 1 if li + 1 < len(starts) else len(doc)
        toks, p = [], s
        while p < e:
            t0 = p
            if state and state[0] == 'b':
                p, d = comment(p, e, state[1], state[2])
                state = ('b', state[1], d) if d else None
                toks.append((TOK_COMMENT, t0, p))
            elif state and state[0] == 'q':
                q, closed = state[1], False
                while p < e and not closed:
                    if doc[p] == 92 and p + 1 < e: p += 2
                    elif doc[p] == q: p += 1; closed = True
                    else: p += 1
                if closed: state = None
                toks.append((TOK_STRING, t0, p))
            else:
                c = doc[p]
                if c in (32, 9, 13): p += 1
                elif sw(p, e, L['bo']) or sw(p, e, L['b2o']):
                    pair = 1 if sw(p, e, L['bo']) else 2
                    p += len(L['bo'] if pair == 1 else L['b2o'])
                    p, d = comment(p, e, pair, 1)
                    state = ('b', pair, d) if d else None
                    toks.append((TOK_COMMENT, t0, p))
                elif sw(p, e, L['lc']) or sw(p, e, L['lc2'], L['fold']):
                    p = e; toks.append((TOK_COMMENT, t0, p))
                elif chr(c) in L['q']:
                    p += 1
                    closed = False
                    while p < e and not closed:
                        if doc[p] == 92 and p + 1 < e: p += 2
                        elif doc[p] == c: p += 1; closed = True
                        else: p += 1
                    if not closed and chr(c) in L['mq']: state = ('q', c)
                    toks.append((TOK_STRING, t0, p))
                elif is_word(c) and not 48 <= c <= 57:
                    while p < e and is_word(doc[p]): p += 1
                    w = doc[t0:p].decode('latin-1')
                    if L['fold']: w = ''.join(chr(ord(ch) + 32) if 'A' <= ch <= 'Z' else ch for ch in w)
                    k = TOK_KEYWORD if w in L['kw'] else TOK_TYPE if w in L['ty'] else TOK_IDENT
                    toks.append((k, t0, p))
                elif 48 <= c <= 57:
                    while p < e and (is_word(doc[p]) or doc[p] == 46): p += 1
                    toks.append((TOK_NUMBER, t0, p))
                else:
                    p += 1
                    toks.append((TOK_PUNCT if chr(c) in '()[]{},;' else TOK_OPERATOR, t0, p))
        out.append(toks)
    return starts, out


def dump_tokens(toks):
    return '|'.join(' '.join('%d:%d-%d' % t for t in line) for line in toks).encode()


# ---- documents per pack ---------------------------------------------------------------------------------------
def first_word(ws):
    for w in sorted(ws):
        if w.isalpha() and w.isascii(): return w
    return 'foo'


# Packs whose strings do not use a backslash escape in the language itself (the engine treats a backslash as an
# escape in every pack, so a document with one is not in the common subset there).
NO_BACKSLASH = {'ada', 'cobol', 'matlab', 'vbnet', 'vbclassic', 'objectpascal', 'batch', 'powershell', 'sql', 'sqlite',
                'postgresql', 'mysql', 'fortran', 'intelasm', 'prolog', 'caml', 'assembly', 'yaml', 'sas', 'protobuf'}
# Packs whose lexer needs real statements to classify anything: documents of their own.
SPECIAL = {
    'yaml': ['key: "str"\n# note\nother: 12\n'],
    'assembly': ['\tmov $1, %eax\n# note\n\t.string "hi"\n/* blk\n more */\n'],
    'prolog': ['foo(X) :- bar("str").\n% note\n'],
    'batch': ['echo "str" foo\nREM note here\nset y=12\n'],
    'matlab': ['x = "str";\n% note\ny = 12;\n%{\nc1\n%}\n'],
}
# Lexers that do not nest block comments although the language does.
NO_NEST_LEXER = {'kotlin', 'dart'}


def curated_docs(pid, L):
    """(agree, edge): documents inside the subset every reference lexer accepts, and engine-only edge cases
    (unterminated strings and comments, which lexers recover from in their own ways)."""
    kw, ty = 'foo', 'bar'
    q = L['q'][0:1] or ''
    lc, bo, bc, lc2 = L['lc'], L['bo'], L['bc'], L['lc2']
    agree, edge = [], []
    NL, BS = '\n', chr(92)
    if pid in SPECIAL:
        agree = [d.encode() for d in SPECIAL[pid]]
        if q: edge.append(('%s a 12 %s trailing' % (kw, q)).encode())
        if bo: edge.append(NL.join(['%s a %s open' % (kw, bo), ' still', '']).encode())
        return agree, edge
    if q:
        agree.append(('%s x = %sstr%s %s%s' % (kw, q, q, ty, NL)).encode())
        if pid not in NO_BACKSLASH:
            agree.append(('%s v = %sa%s%sb%s %s' % (kw, q, BS, q, q, NL)).encode())
        edge.append(('%s a 12 %s trailing' % (kw, q)).encode())
    if lc:
        agree.append(NL.join(['%s foo' % kw, '%s one two' % lc, '%s y = 12' % ty, '']).encode())
    if lc2.strip():
        c2 = lc2.upper() if lc2.endswith(' ') and L['fold'] else lc2
        agree.append(NL.join(['%s x' % kw, '%s note here' % c2, '%s y' % ty, '']).encode())
    if bo:
        if pid == 'matlab':
            agree.append(NL.join(['%s a' % kw, bo, ' c1', ' c2', bc, '%s b' % ty, '']).encode())
        else:
            agree.append(NL.join(['%s a %s c1' % (kw, bo), ' c2', ' c3 %s after' % bc, '%s b' % ty, '']).encode())
        edge.append(NL.join(['%s a %s open' % (kw, bo), ' still', '']).encode())
        if L['nested']:
            d = NL.join(['x %s a %s b %s c' % (bo, bo, bc), ' d %s e' % bc, kw]).encode()
            (edge if pid in NO_NEST_LEXER else agree).append(d)
    if L['b2o']:
        agree.append(NL.join(['%s %s one' % (kw, L['b2o']), ' two %s %s q' % (L['b2c'], ty), '']).encode())
    if L['fold']:
        agree.append(NL.join(['%s x' % kw.upper(), '%s y' % ty.capitalize(), '']).encode())
    return agree, edge


# Pygments lexer for each pack (None when it has no lexer or the lexer disagrees with the reference on the subset).
LEXERS = {
    'javascript': 'JavascriptLexer', 'typescript': 'TypeScriptLexer', 'python': 'PythonLexer', 'cpp': 'CppLexer',
    'c': 'CLexer', 'rust': 'RustLexer', 'go': 'GoLexer', 'java': 'JavaLexer', 'json': 'JsonLexer', 'jsonc': 'JsonLexer',
    'shell': 'BashLexer', 'sql': 'SqlLexer', 'css': 'CssLexer', 'yaml': 'YamlLexer', 'toml': 'TOMLLexer',
    'lua': 'LuaLexer', 'csharp': 'CSharpLexer', 'kotlin': 'KotlinLexer', 'swift': 'SwiftLexer', 'dart': 'DartLexer',
    'r': 'SLexer', 'protobuf': 'ProtoBufLexer', 'assembly': 'GasLexer', 'intelasm': 'NasmLexer',
    'mysql': 'MySqlLexer', 'postgresql': 'PostgresLexer', 'objectpascal': 'DelphiLexer', 'powershell': 'PowerShellLexer',
    'terraform': 'TerraformLexer', 'batch': 'BatchLexer', 'vbnet': 'VbNetLexer', 'fortran': 'FortranLexer',
    'ada': 'AdaLexer', 'objectivec': 'ObjectiveCLexer', 'cobol': 'CobolFreeformatLexer', 'julia': 'JuliaLexer',
    'ruby': 'RubyLexer', 'perl': 'PerlLexer', 'matlab': 'MatlabLexer', 'caml': 'OcamlLexer', 'prolog': 'PrologLexer',
}


def pygments_classes(pid, doc):
    """Per byte: 'c' comment, 's' string, 'o' other, from the Pygments lexer; None without one."""
    name = LEXERS.get(pid)
    if not name: return None
    import pygments.lexers
    from pygments.token import Comment, String
    lex = getattr(pygments.lexers, name)(stripnl=False, ensurenl=False)
    text = doc.decode('utf-8')
    cls, off = ['o'] * len(text), 0
    for idx, tok, val in lex.get_tokens_unprocessed(text):
        kind = 'o'
        if tok in Comment and not (tok in Comment.Preproc or tok in Comment.PreprocFile): kind = 'c'
        elif tok in String: kind = 's'
        for i in range(idx, idx + len(val)): cls[i] = kind
    return cls


def model_classes(doc, toks):
    cls = ['o'] * len(doc)
    for line in toks:
        for k, a, b in line:
            if k == TOK_COMMENT:
                for i in range(a, b): cls[i] = 'c'
            elif k == TOK_STRING:
                for i in range(a, b): cls[i] = 's'
    return cls


def cross_check(pid, L, doc):
    pc = pygments_classes(pid, doc)
    if pc is None: return None
    starts, toks = scan_pack(doc, L)
    mc = model_classes(doc, toks)
    bad = [i for i in range(len(doc)) if doc[i] not in (32, 9, 10, 13) and pc[i] != mc[i]]
    return bad

# ---- suffix map: read from the language matrix in docs/code-editor-plan.md --------------------------------------
def plan_suffix_map():
    plan = pathlib.Path('docs/code-editor-plan.md').read_text(encoding='utf-8')
    order, ids = [], []
    for name, pid, cell in re.findall(r'^\| ([^|`]+) \| `(\w+)` \| ([^|]+) \|', plan, re.M):
        order.append((pid, re.findall(r'`\.([A-Za-z0-9]+)`', cell)))
    comp_id = {}
    for rank, name, comp, cell in re.findall(r'^\| (\d+) \| ([^|]+) \| `(Code\w+)` \| ([^|]+) \|', plan, re.M):
        first = re.search(r'`(\w+)`', cell)
        if first and comp not in comp_id: comp_id[comp] = first.group(1)
    for comp, cell in re.findall(r'^\| `(Code\w+)` \| ([^|]+) \|', plan, re.M):
        if comp in comp_id and comp_id[comp] != 'scratch':
            order.append((comp_id[comp], re.findall(r'`\.([A-Za-z0-9]+)`', cell)))
    mapping = {}
    for pid, sufs in order:
        for s in sufs:
            if s.lower() not in mapping: mapping[s.lower()] = pid
    mapping['c'] = 'c'          # C proper is its own dialect pack (the plan: "C needs actual C dialect rules")
    mapping['jsonc'] = 'jsonc'  # JSON with comments (the plan: support comments explicitly)
    mapping['lua'] = 'lua'
    para = re.search(r'Shared suffixes\s+require project/dialect metadata.*?\n\n', plan, re.S).group(0)
    amb = set(re.findall(r'`\.(\w+)`', para))
    m2 = re.search(r'ambiguous `\.(\w+)`/`\.(\w+)`', plan)
    amb.update(m2.groups())
    return mapping, amb


def lit_case(fields, expected):
    return ([f if isinstance(f, bytes) else f.encode() for f in fields], expected if isinstance(expected, bytes) else expected.encode())


# ---- model: token cases ----------------------------------------------------------------------------------------
def vocab_for(L):
    v = [b'foo', b'x1', b'12', b'3.5', b' ', b' ', b'\n', b'\n', b'(', b')', b';', b'+', b'\t']
    for w in sorted(L['kw'])[:3] + sorted(L['ty'])[:2]:
        if w.isascii(): v.append(w.encode())
        if L['fold'] and w.isascii(): v.append(w.upper().encode())
    for s in (L['lc'], L['lc2'], L['bo'], L['bc'], L['b2o'], L['b2c']):
        if s: v.append(s.encode())
    for ch in L['q']: v.append(ch.encode())
    v.append(b'\\')
    return v


def token_cases(cases):
    ids = sorted(set(SEMANTICS) | set(OLD))
    for pid in ids:
        L = model_pack(pid)
        agree, edge = curated_docs(pid, L)
        docs = agree + edge
        voc = vocab_for(L)
        for _ in range(3):
            doc = b''.join(rnd.choice(voc) for _ in range(rnd.randint(6, 30)))[:160]
            if valid_utf8(doc): docs.append(doc)
        for doc in docs:
            if RS in doc or US in doc: continue
            if pid in OLD:
                starts, toks = ext_scan(doc, OLD[pid])
            else:
                starts, toks = scan_pack(doc, L)
            cases.append(([doc, pid.encode(), b'L'], dump_tokens(toks)))
    # nested comments saturate nowhere near the depth table; one deep case
    L = model_pack('caml')
    doc = b'(* ' * 20 + b'x' + b' *)' * 20 + b' y'
    starts, toks = scan_pack(doc, L)
    cases.append(([doc, b'caml', b'L'], dump_tokens(toks)))
    doc = b'(* ' * 20 + b'x\n' + b'y *)\n' * 1 + b'z *) w\n'
    starts, toks = scan_pack(doc, L)
    cases.append(([doc, b'caml', b'L'], dump_tokens(toks)))


def ext_scan(doc, lang):
    starts, toks = ext.scan(doc, lang)
    return starts, toks


def valid_utf8(b):
    try: b.decode('utf-8'); return True
    except UnicodeDecodeError: return False


def suffix_cases(cases):
    mapping, amb = plan_suffix_map()
    for s in sorted(mapping):
        cases.append(([b'', s.encode(), b'I'], mapping[s].encode()))
        up = s.upper()
        if up != s: cases.append(([b'', up.encode(), b'I'], mapping[s].encode()))
        cases.append(([b'', s.encode(), b'A'], b'1' if s in amb else b'0'))
    for s in ['', 'xyz', 'sqlite4', 'cppx', 'Rs', 'RS', 'jsx', 'TSX', 'sb3', 'longsuffixnamethatistoolong', 'e1']:
        exp = mapping.get(s.lower(), '') if len(s) <= 16 else ''
        cases.append(([b'', s.encode(), b'I'], exp.encode() if exp else b'-'))
    for name, exp in [('main.RS', 'rust'), ('a.b.c.py', 'python'), ('Gemfile', 'ruby'), ('Rakefile', 'ruby'),
                      ('Makefile', '-'), ('x.', '-'), ('.hidden', '-'), ('plain', '-'), ('dir.d/file', '-'),
                      ('notes.TXT', 'text'), ('lib.h', 'cpp'), ('main.pl', 'perl'), ('x.sb3', '-'), ('a.S', 'assembly')]:
        cases.append(([name.encode(), b'', b'N'], exp.encode()))


# ---- model: wrap-aware motion ----------------------------------------------------------------------------------
def code_doc(rnd, lang_comment='//'):
    """A block-structured source with wrapped-width lines for the motion cases."""
    lines, depth = [], 0
    for _ in range(rnd.randint(4, 12)):
        ind = '    ' * depth
        w = ' '.join(rnd.choice(['alpha', 'beta', 'gamma', 'delta', 'x', 'yy', 'zzz', 'return', 'value=1', '(call)'])
                     for _ in range(rnd.randint(1, 9)))
        r = rnd.random()
        if r < 0.3 and depth < 3:
            lines.append(ind + w + ' {'); depth += 1
        elif r < 0.5 and depth > 0:
            depth -= 1; lines.append('    ' * depth + '}')
        else:
            lines.append(ind + w + ';')
    while depth > 0:
        depth -= 1; lines.append('    ' * depth + '}')
    return '\n'.join(lines).encode()


class Motion:
    def __init__(self, doc, width, tab, lang, collapsed_lines):
        self.doc, self.width, self.tab = doc, width, tab
        self.starts = [0] + [i + 1 for i, c in enumerate(doc) if c == 10]
        self.n = len(self.starts)
        self.all_stops = ext.clusters(doc, 0, len(doc)) + [len(doc)]
        self.rows, self.stops = {}, {}
        for ln in range(self.n):
            e = ext.line_end(doc, self.starts, ln)
            stops = ext.clusters(doc, self.starts[ln], e)
            k, rows = 0, [self.starts[ln]]
            while True:
                nk = ext.next_row(doc, stops, k, e, width, tab)
                if nk is None: break
                k = nk; rows.append(stops[k])
            self.rows[ln], self.stops[ln] = rows, stops
        fl = {}
        for (f, t) in ext.folds(doc, lang):
            fl.setdefault(ext.line_of(self.starts, f), (f, t))
        self.hidden = set()
        for ln in collapsed_lines:
            if ln in fl:
                f, t = fl[ln]
                for l in range(ext.line_of(self.starts, f) + 1, ext.line_of(self.starts, t) + 1): self.hidden.add(l)
        self.ok_collapse = [ln for ln in collapsed_lines if ln in fl]

    def line_end(self, ln): return ext.line_end(self.doc, self.starts, ln)

    def row_of(self, ln, pos):
        rows = self.rows[ln]
        for i, rs in enumerate(rows):
            nxt = rows[i + 1] if i + 1 < len(rows) else None
            if nxt is None or pos < nxt: return i
        return len(rows) - 1

    def row_bounds(self, ln, r):
        rows = self.rows[ln]
        rs = rows[r]
        re_ = rows[r + 1] if r + 1 < len(rows) else self.line_end(ln)
        return rs, re_

    def col_in_row(self, ln, r, pos):
        rs, _ = self.row_bounds(ln, r)
        col = 0
        for s in self.stops[ln]:
            if s >= pos or s < rs: continue
            col = col + self.tab - col % self.tab if self.doc[s] == 9 else col + 1
        return col

    def prev_stop(self, ln, pos):
        best = None
        for s in self.stops[ln] + [self.line_end(ln)]:
            if s < pos: best = s
        return best

    def pos_in_row(self, ln, r, goal):
        rs, re_ = self.row_bounds(ln, r)
        end = self.line_end(ln)
        last = re_ if re_ >= end else self.prev_stop(ln, re_)
        col, best = 0, rs
        for s in [x for x in self.stops[ln] if rs <= x] + [end]:
            if s > last: break
            if col <= goal: best = s
            if s >= last: break
            col = col + self.tab - col % self.tab if self.doc[s] == 9 else col + 1
        return best

    def next_visible(self, ln):
        for l in range(ln + 1, self.n):
            if l not in self.hidden: return l
        return None

    def prev_visible(self, ln):
        for l in range(ln - 1, -1, -1):
            if l not in self.hidden: return l
        return None

    def run(self, start, moves):
        anchor = head = start
        goal = None
        out = []
        for ch in moves:
            extend = ch.isupper()
            c = ch.lower()
            lo, hi = min(anchor, head), max(anchor, head)
            ln = ext.line_of(self.starts, head)
            r = self.row_of(ln, head)
            rs, re_ = self.row_bounds(ln, r)
            end = self.line_end(ln)
            h, g = head, goal
            if c == 's':
                h, g = rs, None
            elif c == 'e':
                h = re_ if re_ >= end else self.prev_stop(ln, re_)
                g = None
            elif c in 'ud':
                if g is None: g = self.col_in_row(ln, r, head)
                if c == 'u':
                    if rs > self.starts[ln]:
                        h = self.pos_in_row(ln, r - 1, g)
                    else:
                        pl = self.prev_visible(ln)
                        if pl is None: h = 0
                        else: h = self.pos_in_row(pl, len(self.rows[pl]) - 1, g)
                else:
                    if re_ < end:
                        h = self.pos_in_row(ln, r + 1, g)
                    else:
                        nl = self.next_visible(ln)
                        if nl is None: h = len(self.doc)
                        else: h = self.pos_in_row(nl, 0, g)
            else:  # l, r: one stop left or right, collapsing a non-empty range when not extending
                empty = lo == hi
                stops = self.all_stops
                if c == 'l':
                    if not extend and not empty: h = lo
                    else: h = max([s for s in stops if s < head], default=0)
                else:
                    if not extend and not empty: h = hi
                    else: h = min([s for s in stops if s > head], default=len(self.doc))
                g = None
            head = h; goal = g
            if not extend: anchor = h
            out.append('%d.%d' % (head, anchor))
        return ' '.join(out)


def wrap_cases(cases):
    for i in range(36):
        doc = code_doc(rnd)
        if i % 4 == 3: doc = doc.replace(b'    ', b'\t')
        lang = ext.JS if i % 2 == 0 else ext.C
        sid = b'javascript' if i % 2 == 0 else b'cpp'
        width = rnd.choice([0, 12, 16, 20, 30])
        tab = rnd.choice([2, 4, 8])
        starts = [0] + [j + 1 for j, c in enumerate(doc) if c == 10]
        fold_lines = []
        fl = [ext.line_of(starts, f) for f, t in ext.folds(doc, lang)]
        for ln in fl:
            if rnd.random() < 0.5 and len(fold_lines) < 8: fold_lines.append(ln)
        start = rnd.choice([0, rnd.randint(0, len(doc))])
        while start < len(doc) and (doc[start] & 192) == 128: start += 1
        moves = ''.join(rnd.choice('uuuddddsEeulrUD') for _ in range(rnd.randint(8, 24)))
        m = Motion(doc, width, tab, lang, fold_lines)
        if width == 0:
            # no wrapping: the engine falls back to line motion, which counts code points; keep to row-free moves
            moves = ''.join(rnd.choice('lr') for _ in range(rnd.randint(3, 8)))
            m = Motion(doc, 1000, tab, lang, [])
        exp = m.run(start, moves)
        cases.append(([doc, sid, b'V', str(width).encode(), str(tab).encode(), str(start).encode(),
                       (','.join(str(x) for x in m.ok_collapse) if width else '-').encode(), moves.encode()], exp.encode()))
    # fixed: a wrapped line with a tab, goal kept across a short row
    doc = b'one two three four five six seven\nx\nfoo bar baz qux quux corge grault'
    for moves in ('dddduuuu', 'eDDDss', 'DDDDuuu'):
        m = Motion(doc, 10, 4, ext.PLAIN, [])
        cases.append(([doc, b'text', b'V', b'10', b'4', b'3', b'-', moves.encode()], m.run(3, moves).encode()))


# ---- model: folds through edits (per-character provenance) -----------------------------------------------------
class FoldModel:
    """A view is a list of (from, to) regions; each character carries the set of region ids covering it. An
    edit keeps a region over its surviving original characters plus inserted characters whose left and right
    neighbours are both in it."""

    def __init__(self, doc, lang, cap=6):
        self.doc = bytearray(doc)
        self.lang = lang
        self.cap = cap
        self.cov = [[set() for _ in doc] for _ in range(2)]   # per view, per char: region ids
        self.nid = 0
        self.undo, self.redo = [], []
        self.header = [dict(), dict()]  # view -> region id -> header line at creation (not used for output)

    def starts(self): return [0] + [i + 1 for i, c in enumerate(self.doc) if c == 10]

    def folds_now(self): return ext.folds(bytes(self.doc), self.lang)

    def region_list(self, v):
        ids = {}
        for i, s in enumerate(self.cov[v]):
            for r in s:
                lo, hi = ids.get(r, (i, i + 1))
                ids[r] = (min(lo, i), max(hi, i + 1))
        return sorted(ids.values())

    def header_line(self, region):
        return ext.line_of(self.starts(), region[0])

    def collapse(self, v, ln):
        ft = None
        for (f, t) in self.folds_now():
            if ext.line_of(self.starts(), f) == ln: ft = (f, t); break
        if ft is None: return False
        # replace an existing region headed by ln
        for r in self.region_list(v):
            if self.header_line(r) == ln:
                self.remove_region(v, r)
                break
        if len(self.region_list(v)) >= self.cap: return False
        self.nid += 1
        for i in range(ft[0], ft[1]): self.cov[v][i].add(self.nid)
        return True

    def remove_region(self, v, r):
        ids = {}
        for i, s in enumerate(self.cov[v]):
            for x in s:
                lo, hi = ids.get(x, (i, i + 1))
                ids[x] = (min(lo, i), max(hi, i + 1))
        for x, extent in ids.items():
            if extent == r:
                for s in self.cov[v]: s.discard(x)
                return

    def expand(self, v, ln):
        for r in self.region_list(v):
            if self.header_line(r) == ln:
                self.remove_region(v, r)
                return True
        return False

    def edit(self, at, rem, text, record=True):
        n = len(self.doc)
        if at > n or rem > n - at: return False
        removed = bytes(self.doc[at:at + rem])
        for v in range(2):
            left = self.cov[v][at - 1] if at > 0 else set()
            right = self.cov[v][at + rem] if at + rem < n else set()
            inside = left & right
            self.cov[v][at:at + rem] = [set(inside) for _ in text]
        self.doc[at:at + rem] = text
        if record:
            self.undo.append((at, len(text), removed))
            self.redo = []
        return True

    def do_undo(self):
        if not self.undo: return True
        at, ln, removed = self.undo.pop()
        text_now = bytes(self.doc[at:at + ln])
        self.edit(at, ln, removed, record=False)
        self.redo.append((at, len(removed), text_now))
        return True

    def do_redo(self):
        if not self.redo: return True
        at, ln, text = self.redo.pop()
        cur = bytes(self.doc[at:at + ln])
        self.edit(at, ln, text, record=False)
        self.undo.append((at, len(text), cur))
        return True

    def refresh(self, v):
        dropped = 0
        cur = {(f, t) for (f, t) in self.folds_now()}
        for r in self.region_list(v):
            ln = self.header_line(r)
            ft = None
            for (f, t) in self.folds_now():
                if ext.line_of(self.starts(), f) == ln: ft = (f, t); break
            if ft != r:
                self.remove_region(v, r); dropped += 1
        return dropped

    def collapse_all(self, v):
        fl = self.folds_now()
        if len(fl) > self.cap: return False
        for s in self.cov[v]: s.clear()
        for (f, t) in fl:
            self.nid += 1
            for i in range(f, t): self.cov[v][i].add(self.nid)
        return True

    def hidden_lines(self, v):
        st = self.starts()
        h = set()
        for (f, t) in self.region_list(v):
            for l in range(ext.line_of(st, f) + 1, ext.line_of(st, t) + 1): h.add(l)
        return sorted(h)

    def report(self, flag):
        def regs(v):
            r = self.region_list(v)
            return ','.join('%d-%d' % x for x in r) if r else '-'
        h = self.hidden_lines(0)
        return ('!' if flag else '') + regs(0) + ';' + regs(1) + ';' + (','.join(str(x) for x in h) if h else '-')


def fold_cases(cases):
    for i in range(34):
        doc = code_doc(rnd)
        lang, sid = (ext.JS, b'javascript') if i % 2 == 0 else (ext.PY, b'python')
        if sid == b'python':
            lines = []
            for l in doc.split(b'\n'):
                lines.append(l.replace(b' {', b':').replace(b'}', b'pass').replace(b';', b''))
            doc = b'\n'.join(lines)
        m = FoldModel(doc, lang)
        starts = m.starts()
        ops, outs = [], []
        folds_now = lambda: [ext.line_of(m.starts(), f) for f, t in m.folds_now()]
        for _ in range(rnd.randint(5, 12)):
            r = rnd.random()
            fl = folds_now()
            if r < 0.35 and fl:
                v, ln = rnd.randint(0, 1), rnd.choice(fl)
                ops.append('C%d.%d' % (v, ln))
                ok = m.collapse(v, ln)
                outs.append(m.report(not ok))
            elif r < 0.45:
                v, ln = rnd.randint(0, 1), rnd.randint(0, len(m.starts()) - 1)
                ops.append('X%d.%d' % (v, ln))
                ok = m.expand(v, ln)
                outs.append(m.report(not ok))
            elif r < 0.75:
                n = len(m.doc)
                at = rnd.randint(0, n)
                rem = rnd.choice([0, 0, rnd.randint(0, min(12, n - at))])
                text = rnd.choice([b'', b'XY', b'\n', b'\n    z;\n', b'{', b'}', b'q'])
                if rem > n - at: rem = n - at
                ops.append('E%d:%d:%s' % (at, rem, text.decode()))
                ok = m.edit(at, rem, text)
                outs.append(m.report(not ok))
            elif r < 0.85:
                ops.append('Z')
                outs.append(m.report(not m.do_undo()))
            elif r < 0.92:
                ops.append('Y')
                outs.append(m.report(not m.do_redo()))
            elif r < 0.96:
                v = rnd.randint(0, 1)
                ops.append('R%d' % v)
                d = m.refresh(v)
                outs.append(('d' if d else '') + m.report(False))
            else:
                v = rnd.randint(0, 1)
                ops.append('A%d' % v)
                ok = m.collapse_all(v)
                outs.append(m.report(not ok))
        # the report may begin with 'd' (dropped) then optional '!' : engine prints d first then ! then folds
        fields = [doc, sid, b'F'] + [o.encode() for o in ops]
        exp = '|'.join(outs)
        cases.append((fields, exp.encode()))


# ---- model: completion ----------------------------------------------------------------------------------------
def engine_words(fn):
    m = re.search(r'fn lang_%s\([^)]*\) -> Language \{(.*?)\n\}\n' % fn, ENGINE, re.S)
    lits = re.findall(r'"((?:\\.|[^"\\])*)"', m.group(1))
    return lits[0].split(), lits[1].split()


def lower_ascii(b): return bytes(c + 32 if 65 <= c <= 90 else c for c in b)


def comp_score(label, prefix):
    n = len(prefix)
    if n == 0: return 3
    if len(label) >= n:
        if label[:n] == prefix: return 3
        if lower_ascii(label[:n]) == lower_ascii(prefix): return 2
    at, pl = 0, lower_ascii(prefix)
    for c in lower_ascii(label):
        if at < n and c == pl[at]: at += 1
    return 1 if at == n else 0


class Comp:
    def __init__(self, doc, kw, ty, pos, manual, triggers, sources, cap_items, cap_text):
        self.doc, self.cap_items, self.cap_text = doc, cap_items, cap_text
        f = pos
        while f > 0 and is_word(doc[f - 1]): f -= 1
        self.frm, self.to = f, pos
        self.items, self.ntext, self.incomplete, self.valid = [], 0, False, False
        if f == pos and not manual:
            if not (pos > 0 and chr(doc[pos - 1]) in triggers): return
        prefix = doc[f:pos]
        gather = []
        for kind, rank, words in sources:
            for w in words.split(' '):
                if w: gather.append((w.encode(), kind, rank))
        for w in kw: gather.append((w.encode(), 1, 1000))
        for w in ty: gather.append((w.encode(), 2, 1001))
        ws = pos
        while ws > 0 and is_word(doc[ws - 1]): ws -= 1
        we = pos
        while we < len(doc) and is_word(doc[we]): we += 1
        p = 0
        while p < len(doc):
            if is_word(doc[p]):
                q = p
                while q < len(doc) and is_word(doc[q]): q += 1
                if not 48 <= doc[p] <= 57 and not (p == ws and q == we) and 2 <= q - p <= 128:
                    gather.append((doc[p:q], 3, 2000))
                p = q
            else:
                p += 1
        for label, kind, rank in gather:
            if not label: continue
            sc = comp_score(label, prefix)
            if sc == 0: continue
            dup = [it for it in self.items if it['label'] == label]
            if dup:
                d = dup[0]
                if sc > d['score'] or (sc == d['score'] and rank < d['rank']):
                    d['score'], d['rank'], d['kind'] = sc, rank, kind
                continue
            if len(self.items) >= cap_items or self.ntext + len(label) > cap_text:
                self.incomplete = True
                continue
            self.items.append(dict(label=label, kind=kind, rank=rank, score=sc))
            self.ntext += len(label)
        self.sort()
        self.valid = True

    def sort(self):
        self.items.sort(key=lambda it: (-it['score'], it['rank'], len(it['label']), it['label']))

    def refine(self, pos):
        if not self.valid or self.incomplete or pos < self.to or pos > len(self.doc) or self.frm > pos: return False
        if any(not is_word(self.doc[k]) for k in range(self.frm, pos)):
            self.valid = False
            return False
        prefix = self.doc[self.frm:pos]
        keep = []
        for it in self.items:
            sc = comp_score(it['label'], prefix)
            if sc > 0:
                it['score'] = sc
                keep.append(it)
        self.items = keep
        self.to = pos
        self.sort()
        return True

    def report(self):
        return '%d%s%s|%s' % (len(self.items), 'i' if self.incomplete else '', 'v' if self.valid else '',
                              ' '.join('%s/%d/%d' % (it['label'].decode(), it['score'], it['kind']) for it in self.items))


def completion_cases(cases):
    pool = ['foo', 'foobar', 'Foo', 'fooBar', 'bar', 'barBaz', 'baz', 'value', 'values', 'valueOf', 'index', 'item', 'items',
            'for', 'format', 'filter', 'fetch', 'x1', 'xy', 'myVar', 'myValue', 'getValue', 'setValue']
    langs = [('javascript', 'javascript'), ('python', 'python'), ('cpp', 'c'), ('objectpascal', 'objectpascal'),
             ('sql', 'sql'), ('text', None)]
    for i in range(40):
        sid, fn = langs[i % len(langs)]
        if fn: kw, ty = engine_words(fn if fn != 'sql' else 'sql')
        else: kw, ty = [], []
        words = [rnd.choice(pool) for _ in range(rnd.randint(4, 14))]
        seps = [' ', ' ', '\n', '.', '(', ' = ', '; ', '\t']
        doc = ''.join(w + rnd.choice(seps) for w in words)
        docb = doc.encode()
        pos = rnd.randint(0, len(docb))
        # the caret inside or at the end of a word most of the time, so the prefix is not empty
        spans = [(m.start(), m.end()) for m in re.finditer(rb"[A-Za-z0-9_]+", docb) if m.end() - m.start() >= 2]
        word_end = len(docb)
        if spans and rnd.random() < 0.85:
            ws_, we_ = rnd.choice(spans)
            pos = rnd.randint(ws_ + 1, we_)
            word_end = we_
        manual = rnd.random() < 0.3
        triggers = rnd.choice(['', '.', '.:'])
        srcs = []
        if rnd.random() < 0.7:
            srcs.append((rnd.choice([4, 5]), rnd.randint(0, 5), ' '.join(rnd.sample(pool, rnd.randint(1, 5)))))
        if rnd.random() < 0.3:
            srcs.append((5, rnd.randint(0, 5), ' '.join(rnd.sample(pool, rnd.randint(1, 4)))))
        cap_items = rnd.choice([4, 8, 64])
        cap_text = rnd.choice([40, 120, 2000])
        c = Comp(docb, kw, ty, pos, manual, triggers, srcs, cap_items, cap_text)
        outs = [c.report()]
        span_hi = min(word_end, len(docb)) if word_end >= pos else min(len(docb), pos + 6)
        later = sorted(rnd.sample(range(pos, span_hi + 1), min(2, span_hi - pos + 1)))
        later = [x for x in later if x >= pos]
        for rp in later:
            ok = c.refine(rp)
            outs.append('>' + ('' if ok else '~') + c.report())
        srcspec = ';'.join('%d:%d:%s' % s for s in srcs)
        fields = [docb, sid.encode(), b'K', str(pos).encode(), b'1' if manual else b'0', triggers.encode(), srcspec.encode(),
                  ('%d:%d' % (cap_items, cap_text)).encode(), (','.join(str(x) for x in later) if later else '-').encode()]
        cases.append((fields, ''.join(outs).encode()))


# ---- model: diagnostics ---------------------------------------------------------------------------------------
def map_point(at, rem, tl, p, assoc):
    if p < at: return p
    if p <= at + rem: return at + (tl if assoc > 0 else 0)
    return p - rem + tl


class DiagModel:
    def __init__(self, doc, lang):
        self.doc = bytearray(doc)
        self.lang = lang
        self.items = []     # dict(from,to,sev,code,src,msg)
        self.undo, self.redo = [], []
        self.cap, self.text_cap = 12, 256

    def sort(self):
        self.items.sort(key=lambda d: (d['from'], d['to'], d['sev'], d['src'], d['code']))   # stable

    def publish(self, src, stale, items):
        if stale: return 'stale'
        for d in items:
            if d['from'] > d['to'] or d['to'] > len(self.doc): return 'bad'
        kept = [d for d in self.items if d['src'] != src]
        if len(kept) + len(items) > self.cap: return 'big'
        if sum(len(d['msg']) for d in kept) + sum(len(d['msg']) for d in items) > self.text_cap: return 'big'
        self.items = kept + [dict(d, src=src) for d in items]
        self.sort()
        return None

    def edit(self, at, rem, text, record=True):
        n = len(self.doc)
        if at > n or rem > n - at: return False
        removed = bytes(self.doc[at:at + rem])
        new = []
        for d in self.items:
            f, t = d['from'], d['to']
            if t > f:
                # by provenance: the range's surviving characters, plus the inserted text when the characters on
                # both sides of the replaced span are in the range
                pos = []
                for i in range(f, t):
                    if i < at: pos.append(i)
                    elif i >= at + rem: pos.append(i - rem + len(text))
                left_in = at > 0 and f <= at - 1 < t
                right_in = at + rem < n and f <= at + rem < t
                if left_in and right_in and text:
                    pos.extend(range(at, at + len(text)))
                if not pos: continue
                new.append(dict(d, **{'from': min(pos), 'to': max(pos) + 1}))
            else:
                p = map_point(at, rem, len(text), f, 1)
                new.append(dict(d, **{'from': p, 'to': p}))
        self.items = new
        self.doc[at:at + rem] = text
        self.sort()
        if record:
            self.undo.append((at, len(text), removed))
            self.redo = []
        return True

    def do_undo(self):
        if not self.undo: return True
        at, ln, removed = self.undo.pop()
        text_now = bytes(self.doc[at:at + ln])
        self.edit(at, ln, removed, record=False)
        self.redo.append((at, len(removed), text_now))
        return True

    def do_redo(self):
        if not self.redo: return True
        at, ln, text = self.redo.pop()
        cur = bytes(self.doc[at:at + ln])
        self.edit(at, ln, text, record=False)
        self.undo.append((at, len(text), cur))
        return True

    def report(self, flag, query=None):
        er = sum(1 for d in self.items if d['sev'] == 1)
        wa = sum(1 for d in self.items if d['sev'] == 2)
        ot = len(self.items) - er - wa
        body = ' '.join('%d-%d:%d:%d:%d:%s' % (d['from'], d['to'], d['sev'], d['code'], d['src'], d['msg'])
                        for d in self.items)
        q = ''
        if query is not None: q = 'q' + ('-' if query is None or query < 0 else str(query)) + ';'
        return ('!' if flag else '') + q + '%d/%d/%d/%d|%s' % (len(self.items), er, wa, ot, body)

    def at(self, pos):
        for i, d in enumerate(self.items):
            if d['from'] <= pos and (pos < d['to'] or (d['from'] == d['to'] and pos == d['from'])): return i
        return -1

    def nxt(self, pos, fwd, wrap):
        n = len(self.items)
        if n == 0: return -1
        if fwd:
            for i, d in enumerate(self.items):
                if d['from'] > pos: return i
            return 0 if wrap else -1
        for i in range(n - 1, -1, -1):
            if self.items[i]['from'] < pos: return i
        return n - 1 if wrap else -1


def lint_brackets_model(doc, lang):
    starts, toks = ext.scan(doc, lang)
    skip = ext.skip_set(toks)
    stack, out = [], []
    for p, c in enumerate(doc):
        if c not in ext.PART or p in skip: continue
        if c in (40, 91, 123):
            if len(stack) < 256: stack.append(p)
        elif not stack:
            out.append((p, 1))
        else:
            o = stack.pop()
            if ext.PART[doc[o]] != c: out.append((p, 2))
    for o in stack: out.append((o, 3))
    out.sort(key=lambda x: x[0])
    return out


def json_error(doc):
    s = doc.decode('utf-8')
    def bad(_): raise ValueError('constant')
    try:
        json.loads(s, parse_constant=bad)
        return None
    except json.JSONDecodeError as e:
        return len(s[:e.pos].encode())
    except ValueError:
        return 'skip'


JSON_BASE = [
    b'{"a": [1, 2.5, -3e+2, true, false, null], "b": {"c": "d\\n\\u00e9", "e": []}, "f": {}}',
    b'[ {"k": 1}, {"k": 2, "v": [[], [{}]]}, "x", 0 ]',
    b'"just a string"', b'123', b'-0.5E-3', b'null', b'{"deep": {"deeper": {"deepest": [1, [2, [3]]]}}}',
    b'  \n{"ws" :\t1 , "x"\r\n: [ 1 , 2 ] }\n',
]


def json_cases(cases):
    docs = list(JSON_BASE)
    docs += [b'', b'   ', b'{', b'[', b'[1,', b'{"a"', b'{"a":', b'{"a":1', b'{"a":1,}', b'[1,]', b'{,}', b'[,]',
             b'"abc', b'"a\nb"', b'"\\q"', b'"\\u12"', b'"\\ud800\\u"', b'01', b'-', b'1.', b'1e', b'tru', b'nulll',
             b'{"a" 1}', b'[1 2]', b'{1:2}', b"['a']", b'[.5]', b'[+1]', b'--1', b'1 2', b'[1]\n\n x', b'{"a":1}x',
             b'[1.e3]', b'"\xc3\xa9\\q"', b'{"\xc3\xa9": nul}']
    chars = b'[]{},:"\\0e-.tfn \n1'
    for base in JSON_BASE:
        for _ in range(9):
            d = bytearray(base)
            for _ in range(rnd.randint(1, 3)):
                k = rnd.random()
                if k < 0.34 and d: del d[rnd.randrange(len(d))]
                elif k < 0.67: d.insert(rnd.randint(0, len(d)), chars[rnd.randrange(len(chars))])
                elif d: d = d[:rnd.randint(0, len(d))]
            docs.append(bytes(d))
    for d in docs:
        if RS in d or US in d or not valid_utf8(d): continue
        r = json_error(d)
        if r == 'skip': continue
        cases.append(([d, b'json', b'J'], b'-' if r is None else str(r).encode()))


def bracket_cases(cases):
    langs = [(b'cpp', ext.C), (b'python', ext.PY), (b'javascript', ext.JS), (b'json', ext.JSON), (b'text', ext.PLAIN)]
    vocab = [b'(', b')', b'{', b'}', b'[', b']', b'a', b' ', b'\n', b'"(', b'")', b'//', b'/*', b'*/', b"'", b'#']
    for i in range(30):
        sid, lang = langs[i % len(langs)]
        doc = b''.join(rnd.choice(vocab) for _ in range(rnd.randint(4, 40)))
        out = lint_brackets_model(doc, lang)
        exp = '%d|%s' % (len(out), ' '.join('%d:%d' % o for o in out[:64]))
        cases.append(([doc, sid, b'B'], exp.encode()))


def diag_cases(cases):
    langs = [(b'cpp', ext.C), (b'json', ext.JSON), (b'javascript', ext.JS), (b'text', ext.PLAIN)]
    msgs = ['bad', 'unclosed', 'maybe', 'x y', 'oops', 'e1']
    for i in range(40):
        sid, lang = langs[i % len(langs)]
        if sid == b'json': doc = rnd.choice(JSON_BASE)
        else: doc = b''.join(rnd.choice([b'(', b')', b'{', b'}', b'foo', b' ', b'\n', b'x1', b';', b'"s"', b'/*c*/']) for _ in range(rnd.randint(6, 30)))
        m = DiagModel(doc, lang)
        ops, outs = [], []
        for _ in range(rnd.randint(4, 10)):
            r = rnd.random()
            n = len(m.doc)
            if r < 0.3:
                src = rnd.choice([3, 4])
                stale = 1 if rnd.random() < 0.15 else 0
                items = []
                for _ in range(rnd.randint(0, 4)):
                    a = rnd.randint(0, n)
                    b = min(n, a + rnd.choice([0, 1, 1, 2, 5]))
                    items.append(dict(**{'from': a, 'to': b}, sev=rnd.randint(1, 4), code=rnd.randint(1, 9), msg=rnd.choice(msgs)))
                body = ';'.join('%d-%d-%d-%d-%s' % (d['from'], d['to'], d['sev'], d['code'], d['msg']) for d in items)
                ops.append('P%d:%d:%s' % (src, stale, body))
                err = m.publish(src, stale, items)
                outs.append(m.report(err is not None))
            elif r < 0.5:
                at = rnd.randint(0, n)
                rem = rnd.choice([0, 0, rnd.randint(0, min(6, n - at))])
                text = rnd.choice([b'', b'ab', b'\n', b'(', b'Z'])
                ops.append('E%d:%d:%s' % (at, rem, text.decode().replace('\n', '\n')))
                ok = m.edit(at, rem, text)
                outs.append(m.report(not ok))
            elif r < 0.58:
                ops.append('Z'); outs.append(m.report(not m.do_undo()))
            elif r < 0.64:
                ops.append('Y'); outs.append(m.report(not m.do_redo()))
            elif r < 0.7:
                src = rnd.choice([3, 4, '*'])
                ops.append('C%s' % src)
                if src == '*': m.items = []
                else: m.items = [d for d in m.items if d['src'] != src]
                outs.append(m.report(False))
            elif r < 0.8:
                ops.append('B')
                found = lint_brackets_model(bytes(m.doc), lang)
                if len(found) > 12:
                    outs.append(m.report(True))
                else:
                    items = [dict(**{'from': p, 'to': p + 1}, sev=1, code=c, msg='') for p, c in found]
                    err = m.publish(1, 0, items)
                    outs.append(m.report(err is not None))
            elif r < 0.88:
                ops.append('J')
                r2 = json_error(bytes(m.doc))
                if r2 == 'skip':
                    ops.pop(); continue
                items = []
                if r2 is not None:
                    to = r2 + 1 if r2 + 1 <= len(m.doc) else r2
                    items = [dict(**{'from': r2, 'to': to}, sev=1, code=10, msg='')]
                err = m.publish(2, 0, items)
                outs.append(m.report(err is not None))
            elif r < 0.94:
                p = rnd.randint(0, n)
                ops.append('Q%d' % p)
                outs.append(m.report(False, m.at(p)))
            else:
                p = rnd.randint(0, n)
                fw, wr = rnd.randint(0, 1), rnd.randint(0, 1)
                ops.append('N%d:%d:%d' % (p, fw, wr))
                outs.append(m.report(False, m.nxt(p, bool(fw), bool(wr))))
        if not ops: continue
        cases.append(([bytes(doc), sid, b'G'] + [o.encode() for o in ops], '|'.join(outs).encode()))


def literal(b):
    parts = []
    for c in b:
        if c == 0x22: parts.append('\\"')
        elif c == 0x5c: parts.append('\\\\')
        elif 0x20 <= c < 0x7f: parts.append(chr(c))
        else: parts.append('\\x%02X' % c)
    return '"' + ''.join(parts) + '"'


def build():
    cases = []
    token_cases(cases)
    suffix_cases(cases)
    wrap_cases(cases)
    fold_cases(cases)
    completion_cases(cases)
    diag_cases(cases)
    json_cases(cases)
    bracket_cases(cases)
    return cases


def main():
    for pid in sorted(set(SEMANTICS) | set(OLD)):
        L = model_pack(pid)
        agree, edge = curated_docs(pid, L)
        for doc in agree:
            bad = cross_check(pid, L, doc)
            if bad:
                raise SystemExit('pygments disagrees on %s %r at %r' % (pid, doc, bad[:5]))
    cases = build()
    script = RS.join(US.join(f) for f, _ in cases)
    expected = RS.join(e for _, e in cases)
    for f, e in cases:
        for part in f + [e]:
            assert RS not in part and US not in part, part
    block = ['// BEGIN GENERATED (scripts/gen_ui_code_editor_svc_test.py)',
             'fn script() -> str { ret %s }' % literal(script),
             'fn expected() -> str { ret %s }' % literal(expected),
             'const CASES: usize = %dusize' % len(cases),
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_code_editor_svc/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8', newline='\n')
    kinds = {}
    for f, _ in cases: kinds[f[2].decode()] = kinds.get(f[2].decode(), 0) + 1
    print('%d cases, script %d bytes, expected %d bytes' % (len(cases), len(script), len(expected)), kinds)


if __name__ == '__main__':
    main()
