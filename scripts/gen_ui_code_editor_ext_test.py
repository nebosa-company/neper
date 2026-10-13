#!/usr/bin/env python3
"""Independent model of the e.ui.code_editor additions of D3500 (L065) for
tests/selfhost/fixtures/link/ui_code_editor_ext: language packs and suffix map, bracket matching, folds, soft wrap,
regular-expression search and replace, multiple cursors and rectangular selection.

The model works on Python `bytes` and `str` with no shared code with lib/e/ui/code_editor.e. Regular expressions
are answered by Python's `re` (ASCII mode) -- the engine under test is e.text.regex over the same documents. The
GENERATED block of the fixture's main.e carries the cases (script) and the expected output of each (expected).
Run from the repo root to rewrite it.
"""
import pathlib, random, re

RS, US = b'\x1e', b'\x1f'
TOK_KEYWORD, TOK_TYPE, TOK_IDENT, TOK_NUMBER, TOK_STRING, TOK_COMMENT, TOK_OPERATOR, TOK_PUNCT = 1, 2, 3, 4, 5, 6, 7, 8
CAPSEL = 12


def words(s): return set(s.split())


# ---- language table: written from each language's reference, not from the engine ------------------------------
def L(kw, ty, lc, bo, bc, q, mq): return dict(kw=words(kw), ty=words(ty), lc=lc, bo=bo, bc=bc, q=q, mq=mq)

C = L('auto break case catch class const constexpr continue default delete do else enum explicit extern false for friend goto if inline namespace new noexcept nullptr operator private protected public register return sizeof static struct switch template this throw true try typedef typename union using virtual volatile while',
      'bool char double float int int8_t int16_t int32_t int64_t long short signed size_t uint8_t uint16_t uint32_t uint64_t unsigned void wchar_t', '//', '/*', '*/', '"\'', '')
RUST = L('as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while',
         'bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize String Vec Option Result Box', '//', '/*', '*/', '"', '"')
GO = L('break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil',
       'bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr', '//', '/*', '*/', '"\'`', '`')
JAVA = L('abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while true false null',
         'boolean byte char double float int long short void String', '//', '/*', '*/', '"\'', '')
TS = L('abstract as async await break case catch class const continue debugger declare default delete do else enum export extends false finally for from function if implements import in instanceof interface is keyof let namespace new null of private protected public readonly return static super switch this throw true try type typeof var void while with yield',
       'any bigint boolean never number object string symbol undefined unknown', '//', '/*', '*/', '"\'`', '`')
JSON = L('true false null', '', '', '', '', '"', '')
SHELL = L('if then else elif fi case esac for select while until do done in function time return exit break continue export local readonly declare unset shift source alias echo',
          '', '#', '', '', '"\'`', '"\'')
SQL = L('select SELECT from FROM where WHERE insert INSERT into INTO values VALUES update UPDATE set SET delete DELETE create CREATE table TABLE drop DROP alter ALTER index INDEX join JOIN left LEFT right RIGHT inner INNER outer OUTER on ON group GROUP by BY order ORDER having HAVING limit LIMIT union UNION and AND or OR not NOT null NULL as AS distinct DISTINCT primary PRIMARY key KEY foreign FOREIGN references REFERENCES',
        'int INT integer INTEGER text TEXT varchar VARCHAR char CHAR date DATE timestamp TIMESTAMP boolean BOOLEAN real REAL numeric NUMERIC', '--', '/*', '*/', '"\'`', '')
CSS = L('important', '', '', '/*', '*/', '"\'', '')
HTML = L('', '', '', '<!--', '-->', '"\'', '')
YAML = L('true false null yes no on off', '', '#', '', '', '"\'', '')
TOML = L('true false', '', '#', '', '', '"\'', '')
LUA = L('and break do else elseif end false for function goto if in local nil not or repeat return then true until while', '', '--', '--[[', ']]', '"\'', '')
PY = L('and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield', '', '#', '', '', '"\'', '')
JS = L('async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof var void while with yield', '', '//', '/*', '*/', '"\'`', '`')
PLAIN = L('', '', '', '', '', '', '')
SUFFIX = {}
for names, lang in ((('c', 'h', 'cc', 'cpp', 'cxx', 'hpp'), C), (('rs',), RUST), (('go',), GO), (('java',), JAVA), (('ts', 'tsx'), TS),
                    (('json',), JSON), (('sh', 'bash'), SHELL), (('sql',), SQL), (('css',), CSS), (('html', 'htm', 'xml'), HTML),
                    (('yaml', 'yml'), YAML), (('toml',), TOML), (('lua',), LUA), (('py', 'pyw'), PY), (('js', 'mjs', 'cjs'), JS)):
    for n in names: SUFFIX[n] = lang


def lang_of(suffix): return SUFFIX.get(suffix.lower(), PLAIN)


def is_word(c): return 48 <= c <= 57 or 65 <= c <= 90 or 97 <= c <= 122 or c == 95 or c >= 128


def scan(doc, lang):
    """Tokens per line as [(kind, start, end)], from scratch. Block comments and multiline quotes carry over."""
    lines, starts = [], [0]
    for i, c in enumerate(doc):
        if c == 10: starts.append(i + 1)
    out, state = [], ('n',)
    for li, s in enumerate(starts):
        e = starts[li + 1] - 1 if li + 1 < len(starts) else len(doc)
        toks, p = [], s
        while p < e:
            t0 = p
            if state[0] == 'b':
                j = doc.find(lang['bc'].encode(), p, e) if lang['bc'] else -1
                if j >= 0: p = j + len(lang['bc']); state = ('n',)
                else: p = e
                toks.append((TOK_COMMENT, t0, p))
            elif state[0] == 'q':
                q = state[1]
                closed = False
                while p < e and not closed:
                    if doc[p] == 92 and p + 1 < e: p += 2
                    elif doc[p] == q: p += 1; closed = True
                    else: p += 1
                if closed: state = ('n',)
                toks.append((TOK_STRING, t0, p))
            else:
                c = doc[p]
                if c in (32, 9, 13): p += 1
                elif lang['bo'] and doc.startswith(lang['bo'].encode(), p, e):
                    p += len(lang['bo'])
                    j = doc.find(lang['bc'].encode(), p, e)
                    if j >= 0: p = j + len(lang['bc'])
                    else: p = e; state = ('b',)
                    toks.append((TOK_COMMENT, t0, p))
                elif lang['lc'] and doc.startswith(lang['lc'].encode(), p, e):
                    p = e; toks.append((TOK_COMMENT, t0, p))
                elif chr(c) in lang['q']:
                    p += 1
                    closed = False
                    while p < e and not closed:
                        if doc[p] == 92 and p + 1 < e: p += 2
                        elif doc[p] == c: p += 1; closed = True
                        else: p += 1
                    if not closed and chr(c) in lang['mq']: state = ('q', c)
                    toks.append((TOK_STRING, t0, p))
                elif is_word(c) and not 48 <= c <= 57:
                    while p < e and is_word(doc[p]): p += 1
                    w = doc[t0:p].decode('latin-1')
                    k = TOK_KEYWORD if w in lang['kw'] else TOK_TYPE if w in lang['ty'] else TOK_IDENT
                    toks.append((k, t0, p))
                elif 48 <= c <= 57:
                    while p < e and (is_word(doc[p]) or doc[p] == 46): p += 1
                    toks.append((TOK_NUMBER, t0, p))
                else:
                    p += 1
                    toks.append((TOK_PUNCT if chr(c) in '()[]{},;' else TOK_OPERATOR, t0, p))
        out.append(toks)
    return starts, out


def line_end(doc, starts, ln): return starts[ln + 1] - 1 if ln + 1 < len(starts) else len(doc)
def line_of(starts, pos):
    r = 0
    for i, v in enumerate(starts):
        if v <= pos: r = i
    return r


def skipped_at(toks_by_line, starts, pos):
    for toks in toks_by_line:
        for (k, s, e) in toks:
            if k in (TOK_COMMENT, TOK_STRING) and s <= pos < e: return True
    return False


# ---- brackets and folds ---------------------------------------------------------------------------------------
PART = {40: 41, 41: 40, 91: 93, 93: 91, 123: 125, 125: 123}


def partner_of(doc, skip, at):
    if at >= len(doc) or doc[at] not in PART or at in skip: return None
    c = doc[at]; want = PART[c]
    depth = 0
    rng = range(at + 1, len(doc)) if c in (40, 91, 123) else range(at - 1, -1, -1)
    for p in rng:
        d = doc[p]
        if d in (c, want) and p not in skip:
            if d == c: depth += 1
            elif depth == 0: return p
            else: depth -= 1
    return None


def skip_set(toks):
    s = set()
    for line in toks:
        for (k, a, b) in line:
            if k in (TOK_COMMENT, TOK_STRING): s.update(range(a, b))
    return s


def match_bracket(doc, skip, pos):
    if pos > 0 and doc[pos - 1] in PART:
        m = partner_of(doc, skip, pos - 1)
        if m is not None: return (pos - 1, m)
    if pos < len(doc) and doc[pos] in PART:
        m = partner_of(doc, skip, pos)
        if m is not None: return (pos, m)
    return None


def indent_of(doc, starts, ln, tab=4):
    p, e, col = starts[ln], line_end(doc, starts, ln), 0
    while p < e and doc[p] in (32, 9):
        col = (col // tab + 1) * tab if doc[p] == 9 else col + 1
        p += 1
    return col, p - starts[ln]


def blank(doc, starts, ln): return indent_of(doc, starts, ln)[1] == line_end(doc, starts, ln) - starts[ln]


def folds(doc, lang):
    starts, toks = scan(doc, lang)
    skip = skip_set(toks)
    res = []
    for ln in range(len(starts)):
        t = toks[ln]
        got = None
        if 0 < len(t) <= 128:
            k = len(t)
            while k > 0 and t[k - 1][0] == TOK_COMMENT: k -= 1
            if k > 0:
                kind, a, b = t[k - 1]
                if b - a == 1 and kind == TOK_PUNCT and doc[a] in (40, 91, 123):
                    m = partner_of(doc, skip, a)
                    if m is not None and line_of(starts, m) > ln: got = (a + 1, m)
        if got is None and lang['lc'] == '#' and not blank(doc, starts, ln):
            base = indent_of(doc, starts, ln)[0]
            last = None
            for l in range(ln + 1, len(starts)):
                if blank(doc, starts, l): continue
                if indent_of(doc, starts, l)[0] > base: last = l
                else: break
            if last is not None: got = (line_end(doc, starts, ln), line_end(doc, starts, last))
        if got: res.append(got)
    return res


# ---- soft wrap ------------------------------------------------------------------------------------------------
def ext_cp(cp): return 768 <= cp <= 879 or 8400 <= cp <= 8447 or 65024 <= cp <= 65039 or 127995 <= cp <= 127999 or cp == 8205


def clusters(doc, s, e):
    """Byte offsets of the grapheme-ish stops in [s, e): a scalar plus following extenders and ZWJ-joined scalars."""
    text = doc[s:e].decode('utf-8')
    stops, off, prev = [], s, None
    for ch in text:
        cp = ord(ch)
        n = len(ch.encode())
        if prev is not None and (ext_cp(cp) or prev == 8205): pass
        else: stops.append(off)
        off += n; prev = cp
    return stops


def next_row(doc, stops, k0, e, width, tab):
    """Row starting at stop index k0: returns (index of the next row's first stop, or None when the line ends)."""
    if width == 0: return None
    col, brk, k = 0, None, k0
    while k < len(stops):
        c = doc[stops[k]]
        w = tab - col % tab if c == 9 else 1
        if col + w > width and k > k0:
            return brk if brk is not None else k
        col += w; k += 1
        if c in (32, 9): brk = k
    return None


def wrap_report(doc, width, tab, positions):
    starts = [0] + [i + 1 for i, c in enumerate(doc) if c == 10]
    per_line, total, rowinfo = [], 0, {}
    for ln in range(len(starts)):
        e = line_end(doc, starts, ln)
        stops = clusters(doc, starts[ln], e)
        k, rows = 0, [starts[ln]]
        while True:
            nk = next_row(doc, stops, k, e, width, tab)
            if nk is None: break
            k = nk; rows.append(stops[k])
        per_line.append(rows); total += len(rows)
        rowinfo[ln] = (stops, rows, e)
    loc = []
    for pos in positions:
        ln = line_of(starts, pos)
        stops, rows, e = rowinfo[ln]
        row = 0
        for i, rs in enumerate(rows):
            nxt = rows[i + 1] if i + 1 < len(rows) else None
            if nxt is None or pos < nxt: row = i; break
        rs = rows[row]
        col = 0
        for s in stops:
            if s >= pos or s < rs: continue
            col = col + tab - col % tab if doc[s] == 9 else col + 1
        loc.append((pos, row, col))
    return per_line, loc, total


# ---- regular expressions --------------------------------------------------------------------------------------
def boffs(text):
    offs = [0]
    for ch in text: offs.append(offs[-1] + len(ch.encode()))
    return offs


def rx_flags(f):
    fl = re.ASCII
    if 'i' in f: fl |= re.I
    if 'm' in f: fl |= re.M
    return fl


def rx_matches(pat, text, start=0):
    p = start
    while p <= len(text):
        m = pat.search(text, p)
        if not m: return
        if m.end() > m.start():
            yield m; p = m.end()
        else:
            if m.start() >= len(text): return
            p = m.start() + 1


def expand(repl, m):
    out, i = [], 0
    while i < len(repl):
        c = repl[i]
        if c == '$' and i + 1 < len(repl):
            d = repl[i + 1]
            if d == '$': out.append('$'); i += 2; continue
            if d.isdigit():
                g = int(d)
                if g <= (m.re.groups):
                    out.append(m.group(g) or '')
                i += 2; continue
        out.append(c); i += 1
    return ''.join(out)


def rx_find(doc, pattern, flags, frm, fwd):
    text = doc.decode('utf-8'); offs = boffs(text)
    pat = re.compile(pattern, rx_flags(flags))
    if fwd:
        # a forward search starts at `frm` itself (not at the previous match of a run from the top)
        ci = offs.index(frm)
        for m in rx_matches(pat, text, ci):
            return '%d-%d' % (offs[m.start()], offs[m.end()])
        return '-'
    ms = [(offs[m.start()], offs[m.end()]) for m in rx_matches(pat, text)]
    best = None
    for s, e in ms:
        if s < frm: best = (s, e)
    return '-' if best is None else '%d-%d' % best


def rx_count(doc, pattern, flags, limit):
    text = doc.decode('utf-8')
    pat = re.compile(pattern, rx_flags(flags))
    n = 0
    for _ in rx_matches(pat, text):
        n += 1
        if n >= limit: return '%d,1' % n
    return '%d,0' % n


def rx_replace(doc, pattern, flags, repl):
    text = doc.decode('utf-8')
    pat = re.compile(pattern, rx_flags(flags))
    out, last, n = [], 0, 0
    for m in rx_matches(pat, text):
        out.append(text[last:m.start()]); out.append(expand(repl, m)); last = m.end(); n += 1
    out.append(text[last:])
    return ('%d|' % n).encode() + ''.join(out).encode()


# ---- selections -----------------------------------------------------------------------------------------------
class Sel:
    def __init__(s, doc, tab=4):
        s.doc = doc
        s.starts = [0] + [i + 1 for i, c in enumerate(doc) if c == 10]
        s.r = [(0, 0, None)]   # (anchor, head, goal)
        s.p = 0

    def lend(s, ln): return line_end(s.doc, s.starts, ln)

    def scalars(s, a, b):
        """Scalar start offsets in [a, b)."""
        return [i for i in range(a, b) if (s.doc[i] & 0xC0) != 0x80]

    def col(s, pos):
        ln = line_of(s.starts, pos)
        return len([i for i in range(s.starts[ln], pos) if (s.doc[i] & 0xC0) != 0x80])

    def pos_col(s, ln, col):
        sc = s.scalars(s.starts[ln], s.lend(ln))
        if col < len(sc): return sc[col]
        return s.lend(ln)

    def normalize(s, rs, primary):
        if not rs: return [], 0
        mark = rs[min(primary, len(rs) - 1)][1]
        f = lambda r: min(r[0], r[1]); t = lambda r: max(r[0], r[1])
        rs = sorted(rs, key=lambda r: (f(r), t(r)))
        out = [rs[0]]
        for cur in rs[1:]:
            prev = out[-1]
            merge = f(cur) < t(prev) or (f(cur) == t(prev) and (cur[0] == cur[1] or prev[0] == prev[1]))
            if merge:
                lo, hi = f(prev), max(t(prev), t(cur))
                fwd = (prev[1] >= prev[0] and cur[1] >= cur[0]) or prev[0] == prev[1]
                out[-1] = (lo, hi, None) if fwd else (hi, lo, None)
            else: out.append(cur)
        pi = 0
        for i, r in enumerate(out):
            if f(r) <= mark <= t(r): pi = i
        return out, pi

    def set(s, rs, primary):
        s.r, s.p = s.normalize(rs, primary)

    def cursor(s, up):
        n = len(s.r); added = []; newp = s.p
        for i, (a, h, g) in enumerate(s.r):
            ln = line_of(s.starts, h)
            goal = g if g is not None else s.col(h)
            tl = ln - 1 if up else ln + 1
            if tl < 0 or tl >= len(s.starts): continue
            if n + len(added) + 1 > CAPSEL: return False
            q = s.pos_col(tl, goal)
            added.append((q, q, goal))
            if i == s.p: newp = n + len(added) - 1
        if not added: return True
        s.r, s.p = s.normalize(s.r + added, newp)
        return True

    def rect(s, a, b):
        la, lb = line_of(s.starts, a), line_of(s.starts, b)
        ca, cb = s.col(a), s.col(b)
        lo, hi = min(ca, cb), max(ca, cb)
        first, last = min(la, lb), max(la, lb)
        if last - first + 1 > CAPSEL: return False
        rs, prim = [], 0
        for l in range(first, last + 1):
            ll = s.col(s.lend(l))
            if lo == hi or ll > lo:
                p_lo, p_hi = s.pos_col(l, lo), s.pos_col(l, hi)
                rs.append((p_lo, p_hi, None) if ca <= cb else (p_hi, p_lo, None))
                if l == lb: prim = len(rs) - 1
        if not rs: rs = [(b, b, None)]; prim = 0
        s.set(rs, prim)
        return True

    def wordc(s, p):
        return s.doc[p] >= 128 or is_word(s.doc[p])

    def word_bounds(s, pos):
        st = pos
        while st > 0:
            q = st - 1
            while q > 0 and (s.doc[q] & 0xC0) == 0x80: q -= 1
            if not s.wordc(q): break
            st = q
        f = pos
        while f < len(s.doc) and s.wordc(f):
            f += 1
            while f < len(s.doc) and (s.doc[f] & 0xC0) == 0x80: f += 1   # no combining marks in these documents
        return st, f

    def match_at(s, q, p, cs, ww):
        if p + len(q) > len(s.doc) or not q: return False
        seg = s.doc[p:p + len(q)]
        if cs:
            if seg != q: return False
        elif seg.lower() != q.lower(): return False
        if ww:
            if p > 0:
                b = p - 1
                while b > 0 and (s.doc[b] & 0xC0) == 0x80: b -= 1
                if s.wordc(b): return False
            if p + len(q) < len(s.doc) and s.wordc(p + len(q)): return False
        return True

    def find(s, q, frm, cs, ww):
        p = frm
        while p + len(q) <= len(s.doc):
            if ((s.doc[p] & 0xC0) != 0x80 if p < len(s.doc) else True) and s.match_at(q, p, cs, ww): return p
            p += 1
        return None

    def next_occ(s, cs, ww):
        a, h, g = s.r[s.p]
        lo, hi = min(a, h), max(a, h)
        if lo == hi:
            ws, we = s.word_bounds(lo)
            if ws == we: return True
            s.r[s.p] = (ws, we, None)
            s.r, s.p = s.normalize(s.r, s.p)
            return True
        q = s.doc[lo:hi]
        at = s.find(q, hi, cs, ww)
        if at is None: at = s.find(q, 0, cs, ww)
        if at is None: return True
        for (x, y, _) in s.r:
            if min(x, y) == at and max(x, y) == at + len(q): return True
        if len(s.r) >= CAPSEL: return False
        s.r, s.p = s.normalize(s.r + [(at, at + len(q), None)], len(s.r))
        return True

    def all_occ(s, cs, ww):
        a, h, g = s.r[s.p]
        lo, hi = min(a, h), max(a, h)
        if lo == hi: lo, hi = s.word_bounds(lo)
        if lo == hi: return True
        q = s.doc[lo:hi]; n = len(q)
        rs, prim, p = [], 0, 0
        while p + n <= len(s.doc):
            if (s.doc[p] & 0xC0) != 0x80 and s.match_at(q, p, cs, ww):
                if len(rs) >= CAPSEL: return False
                rs.append((p, p + n, None))
                if p <= lo < p + n: prim = len(rs) - 1
                p += n
            else: p += 1
        if not rs: return True
        s.set(rs, prim)
        return True

    def split(s):
        rs, prim = [], 0
        for i, (a, h, g) in enumerate(s.r):
            lo, hi = min(a, h), max(a, h)
            if lo == hi:
                rs.append((a, h, g))
                if i == s.p: prim = len(rs) - 1
                if len(rs) > CAPSEL: return False
            else:
                pos = lo
                while True:
                    ln = line_of(s.starts, pos)
                    rs.append((max(lo, s.starts[ln]), min(hi, s.lend(ln)), None))
                    if i == s.p: prim = len(rs) - 1
                    if len(rs) > CAPSEL: return False
                    pos = s.lend(ln) + 1
                    if pos > hi: break
        s.set(rs, prim)
        return True


def multi_report(doc, cmds):
    s = Sel(doc)
    out = []
    for c in cmds:
        parts = c.split(' ')
        op = parts[0]
        good = True
        if op == 'S':
            nums = [int(x) for x in parts[1:]]
            rs = [(nums[i], nums[i + 1], None) for i in range(0, len(nums) - 1, 2)]
            s.set(rs, 0)
        elif op == 'U': good = s.cursor(True)
        elif op == 'D': good = s.cursor(False)
        elif op == 'R': good = s.rect(int(parts[1]), int(parts[2]))
        elif op == 'N': good = s.next_occ(parts[1] == '1', parts[2] == '1')
        elif op == 'A': good = s.all_occ(parts[1] == '1', parts[2] == '1')
        elif op == 'L': good = s.split()
        out.append(('' if good else '!') + ','.join('%d.%d' % (a, h) for (a, h, _) in s.r) + '/%d' % s.p)
    return '|'.join(out).encode()


# ---- case generation ------------------------------------------------------------------------------------------
def token_report(doc, suffix):
    starts, toks = scan(doc, lang_of(suffix))
    return '|'.join(' '.join('%d:%d-%d' % t for t in line) for line in toks).encode()


def bracket_report(doc, suffix):
    starts, toks = scan(doc, lang_of(suffix))
    skip = skip_set(toks)
    out = []
    for pos in range(len(doc) + 1):
        if pos < len(doc) and (doc[pos] & 0xC0) == 0x80: continue
        m = match_bracket(doc, skip, pos)
        if m: out.append('%d:%d>%d' % (pos, m[0], m[1]))
    return ' '.join(out).encode()


def fold_report(doc, suffix):
    return ' '.join('%d-%d' % f for f in folds(doc, lang_of(suffix))).encode()


def wrap_text(doc, width, tab, positions):
    per_line, loc, total = wrap_report(doc, width, tab, positions)
    a = ';'.join('%d:%s' % (len(r), ','.join(str(x) for x in r)) for r in per_line)
    b = ' '.join('%d:%d.%d' % x for x in loc)
    return ('%s|%s|%d' % (a, b, total)).encode()


def build():
    rnd = random.Random(3500)
    cases = []   # (fields[list of bytes], expected bytes)

    def add(doc, suffix, op, args, expected):
        f = [doc, suffix.encode(), op.encode()] + [a if isinstance(a, bytes) else str(a).encode() for a in args]
        cases.append((f, expected))

    # languages: one hand-written snippet each
    samples = {
        'c': b'#include <x.h>\nint main(void) { /* c\n c */ return 0; } // end\nchar *s = "a\\"b";\nu8 x = 0x1F + 3.5;',
        'rs': b'fn main() { let x: u32 = 5; // c\n    "multi\nline" } /* b */ \'a',
        'go': b'func f() { s := `raw\nstr` ; var x int = 3 }',
        'java': b'public class A { String s = "x"; /* c */ int n = 1; }',
        'ts': b'const a: number = `t\nm`; interface I { x: string }',
        'json': b'{"a": [1, 2.5, true, null], "b": {"c": "d\\"e"}}',
        'sh': b'if [ -f "$x" ]; then echo \'hi\'; fi # done\nexport A=1',
        'sql': b'SELECT a, b FROM t WHERE x = \'o\' -- c\n/* b */ select 1',
        'css': b'a { color: red !important; } /* c\n d */ b { }',
        'html': b'<!-- c\n --><a href="x">t</a>',
        'yaml': b'a: true # c\nb: "s"\nc: [1, 2]',
        'toml': b'[t]\nk = "v" # c\nb = true',
        'lua': b'local x = 1 -- c\nfunction f() return nil end',
        'py': b'def f(x):\n    # c\n    return "s" + \'t\'\n',
        'js': b'let x = `a\nb`; // c\n/* d */',
        'txt': b'plain (text) {here} 12',
        'XML': b'<!-- X --><b/>',
    }
    for suf, doc in samples.items():
        add(doc, suf, 'T', [], token_report(doc, suf))
    # random token soup per language
    vocab = [b'foo', b'if', b'return', b'int', b'u8', b'12', b'3.5', b' ', b' ', b'\t', b'\n', b'\n', b'(', b')', b'{', b'}', b'[', b']',
             b'"s"', b'"a{b', b"'c'", b'//c', b'/*', b'*/', b'#', b'--', b'<!--', b'-->', b'`', b'+', b',', b';', b'\xc3\xa9', b'SELECT', b'true']
    suffixes = ['c', 'rs', 'go', 'java', 'ts', 'json', 'sh', 'sql', 'css', 'html', 'yaml', 'toml', 'lua', 'py', 'js', 'txt']
    for i in range(48):
        doc = b''.join(rnd.choice(vocab) for _ in range(rnd.randint(4, 40)))[:300]
        if not valid(doc): continue
        suf = suffixes[i % len(suffixes)]
        add(doc, suf, 'T', [], token_report(doc, suf))

    # brackets
    bsrc = [b'f(a[1], {b: (c)})', b'{ "}" ; ( } ) ]', b'a /* ( */ ) ( // )\n)', b'((((', b'))))', b'{[(])}', b'x = (1 + (2 * 3)) * [4]',
            b'if (a) {\n  b();\n}\n', b'"(" ( ")" )', b'(\n{\n(\n)\n}\n)']
    for i, doc in enumerate(bsrc):
        suf = 'c' if i % 2 == 0 else 'js'
        add(doc, suf, 'B', [], bracket_report(doc, suf))
    bvocab = [b'(', b')', b'{', b'}', b'[', b']', b'a', b' ', b'\n', b'"(', b'")', b'//', b'/*', b'*/', b"'", b'\xc3\xa9']
    for i in range(16):
        doc = b''.join(rnd.choice(bvocab) for _ in range(rnd.randint(6, 40)))
        add(doc, ['c', 'py', 'json', 'rs'][i % 4], 'B', [], bracket_report(doc, ['c', 'py', 'json', 'rs'][i % 4]))

    # folds
    fsrc = [(b'fn a() {\n  if x {\n    y\n  }\n}\nfn b() { z }\n', 'rs'),
            (b'def f(x):\n    a = 1\n\n    if a:\n        b\n    return a\nx = {\n  1,\n}\n', 'py'),
            (b'a: 1\nb:\n  c: 2\n  d:\n    e: 3\nf: 4\n', 'yaml'),
            (b'{ // open\n  "k": [\n    1,\n    2\n  ]\n}', 'json'),
            (b'int f() {\n}\nint g() { return 0; }\nvoid h(\n  int a,\n  int b\n);', 'c'),
            (b'#!/bin/sh\nif true; then\n  echo hi\nfi\nf() {\n  :\n}\n', 'sh'),
            (b'\n\nx\n  \n  y\n', 'py')]
    for doc, suf in fsrc:
        add(doc, suf, 'F', [], fold_report(doc, suf))
    for i in range(14):
        lines = []
        for _ in range(rnd.randint(3, 12)):
            ind = ' ' * (rnd.choice([0, 0, 2, 4, 6]))
            body = rnd.choice(['x', 'f(', 'if y {', '}', ')', 'a = 1', '', 'k: v', 'z: {', '// c', '# c', 'w {  // t'])
            lines.append(ind + body)
        doc = '\n'.join(lines).encode()
        suf = ['c', 'py', 'yaml', 'js'][i % 4]
        add(doc, suf, 'F', [], fold_report(doc, suf))

    # wrap
    wsrc = [b'the quick brown fox jumps over the lazy dog', b'aaaaaaaaaaaaaaaaaaaaaaaaa', b'ab cd\tef gh ij', b'\n\nshort\n',
            b'long word_without_breaks_at_all and more   spaces   here', b'e\xcc\x81e\xcc\x81e\xcc\x81 x\xcc\x81y', b'\t\tindented text wraps\n  next',
            b'caf\xc3\xa9 \xc3\xa9t\xc3\xa9 na\xc3\xafve r\xc3\xa9sum\xc3\xa9']
    for i, doc in enumerate(wsrc):
        for width in (0, 1, 4, 7, 12):
            tab = 4 if i % 2 == 0 else 8
            pos = clusters(doc, 0, len(doc)) + [len(doc)]
            starts = [0] + [j + 1 for j, c in enumerate(doc) if c == 10]
            pos = sorted(set(pos) | set(starts) | {line_end(doc, starts, l) for l in range(len(starts))})
            pos = [p for p in pos if p <= len(doc) and valid(doc[:p]) and (p == len(doc) or (doc[p] & 0xC0) != 0x80)]
            # keep only cluster boundaries: engine locate steps by clusters
            cb = set()
            for l in range(len(starts)):
                cb.update(clusters(doc, starts[l], line_end(doc, starts, l))); cb.add(line_end(doc, starts, l)); cb.add(starts[l])
            pos = [p for p in pos if p in cb]
            add(doc, 'txt', 'W', [width, tab, ','.join(map(str, pos))], wrap_text(doc, width, tab, pos))
    for i in range(10):
        vocab2 = [b'word', b'wo', b'a', b' ', b'  ', b'\t', b'\n', b'x\xcc\x81', b'\xc3\xa9', b'longerwordhere']
        doc = b''.join(rnd.choice(vocab2) for _ in range(rnd.randint(5, 30)))
        starts = [0] + [j + 1 for j, c in enumerate(doc) if c == 10]
        cb = set()
        for l in range(len(starts)):
            cb.update(clusters(doc, starts[l], line_end(doc, starts, l))); cb.add(line_end(doc, starts, l)); cb.add(starts[l])
        pos = sorted(cb)
        width = rnd.choice([2, 3, 5, 8, 10])
        add(doc, 'txt', 'W', [width, 4, ','.join(map(str, pos))], wrap_text(doc, width, 4, pos))

    # regex
    rdocs = [b'foo Foo bar12 a1b2 hello world\nfoo-bar  x1y22z333\n\xc3\xa9t\xc3\xa9 foo. end', b'aaa bbb aab abab\nxx', b'one\ntwo\nthree\n', b'', b'abcabcabc\n12 345 6789']
    pats = [('foo', ''), ('foo', 'i'), (r'o+', ''), (r'\d+', ''), (r'[a-c]x*', ''), (r'(\w)(\d)', ''), (r'\bfoo\b', ''), (r'^\w+', 'm'), (r'\w+$', 'm'),
            (r'(a|b)+', ''), (r'x*', ''), (r'(?:fo)+', ''), (r'fo{1,2}', ''), (r'(?<=o)\w', ''), (r'(\w)\1', ''), (r'.', ''), (r'[^ ]+', ''),
            (r'o+?', ''), (r'(a)(b)?', ''), (r'\s+', ''), (r'^', 'm'), (r'(?=b)', '')]
    for di, doc in enumerate(rdocs):
        for pi, (pat, fl) in enumerate(pats):
            if (di * 7 + pi) % 3 != 0 and not (di == 0): continue
            if '$' in pat and 'm' not in fl and doc.endswith(b'\n'): continue
            half = len(doc) // 2
            while half > 0 and (doc[half] & 0xC0) == 0x80: half -= 1
            for frm, fwd in ((0, 1), (half, 1), (len(doc), 0)):
                if len(cases) > 0 and (pi + frm) % 4 != 0: continue
                add(doc, 'txt', 'X', [pat, fl, frm, 'f' if fwd else 'b'], rx_find(doc, pat, fl, frm, fwd).encode())
            add(doc, 'txt', 'C', [pat, fl, 100], rx_count(doc, pat, fl, 100).encode())
            add(doc, 'txt', 'C', [pat, fl, 2], rx_count(doc, pat, fl, 2).encode())
    repls = ['<$0>', '$2$1', '[$$]', '', 'x$9y', '$1-$1', '$']
    for di, doc in enumerate(rdocs):
        for pi, (pat, fl) in enumerate(pats):
            if (di + pi) % 4 != 0: continue
            if '$' in pat and 'm' not in fl and doc.endswith(b'\n'): continue
            r = repls[(di + pi) % len(repls)]
            add(doc, 'txt', 'P', [pat, fl, r], rx_replace(doc, pat, fl, r))

    # multi-cursor
    mdocs = [b'alpha beta\ngamma\n\ndelta epsilon zeta\nab', b'foo Foo foo foobar foo\nfoo\n\xc3\xa9foo foo', b'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\n',
             b'\ttabbed\n  spaces here\nx', b'12345\n123\n1234567\n\n12']
    for di, doc in enumerate(mdocs):
        n = len(doc)
        sc = [i for i in range(n + 1) if i == n or (doc[i] & 0xC0) != 0x80]
        for trial in range(12):
            cmds = []
            k = rnd.randint(1, 3)
            cmds.append('S ' + ' '.join('%d %d' % (rnd.choice(sc), rnd.choice(sc)) for _ in range(k)))
            for _ in range(rnd.randint(2, 6)):
                op = rnd.choice('UDUDRNNALN')
                if op == 'R': cmds.append('R %d %d' % (rnd.choice(sc), rnd.choice(sc)))
                elif op in 'NA': cmds.append('%s %d %d' % (op, rnd.randint(0, 1), rnd.randint(0, 1)))
                else: cmds.append(op)
            add(doc, 'txt', 'M', cmds, multi_report(doc, cmds))
    # fixed: capacity refusals
    doc = b'\n'.join(b'x%d' % i for i in range(20))
    cmds = ['S 0 0'] + ['D'] * 15
    add(doc, 'txt', 'M', cmds, multi_report(doc, cmds))
    cmds = ['S 0 0', 'R 0 %d' % (len(doc) - 1), 'U', 'L']
    add(doc, 'txt', 'M', cmds, multi_report(doc, cmds))
    cmds = ['S 0 %d' % len(doc), 'L', 'U']
    add(doc, 'txt', 'M', cmds, multi_report(doc, cmds))
    return cases


def valid(b):
    try: b.decode('utf-8'); return True
    except UnicodeDecodeError: return False


def literal(b):
    parts = []
    for c in b:
        if c == 0x22: parts.append('\\"')
        elif c == 0x5c: parts.append('\\\\')
        elif 0x20 <= c < 0x7f: parts.append(chr(c))
        else: parts.append('\\x%02X' % c)
    return '"' + ''.join(parts) + '"'


def main():
    cases = build()
    script = RS.join(US.join(f) for f, _ in cases)
    expected = RS.join(e for _, e in cases)
    for f, e in cases:
        for part in f + [e]:
            assert RS not in part and (US not in part), part
    block = ['// BEGIN GENERATED (scripts/gen_ui_code_editor_ext_test.py)',
             'fn script() -> str { ret %s }' % literal(script),
             'fn expected() -> str { ret %s }' % literal(expected),
             'const CASES: usize = %dusize' % len(cases),
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_code_editor_ext/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8', newline='\n')
    kinds = {}
    for f, _ in cases: kinds[f[2].decode()] = kinds.get(f[2].decode(), 0) + 1
    print('%d cases, script %d bytes, expected %d bytes' % (len(cases), len(script), len(expected)), kinds)


if __name__ == '__main__':
    main()
