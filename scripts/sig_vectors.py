# -*- coding: utf-8 -*-
"""Vectors for `e.text.sig` (L053): a YARA-lite rule subset.

There is no yara-python on this host, so the expected results come from an independent matcher: hex strings become
regular expressions (`re`, anchored at every offset), text strings are compared byte by byte with the same modifier
definitions, and conditions are evaluated on the syntax tree the rule text was rendered from (so the parser, precedence
and the string-set forms are all under test). Writes tests/selfhost/fixtures/link/text_sig.
Usage: python scripts/sig_vectors.py
"""
import json
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x5163)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def alnum(b):
    return 48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122


def lower(b):
    return b + 32 if 65 <= b <= 90 else b


# ------------------------------------------------------------------ strings
class Text:
    def __init__(self, raw, nocase, ascii_, wide, fullword):
        self.raw, self.nocase, self.ascii, self.wide, self.fullword = raw, nocase, ascii_, wide, fullword
        self.hex = False

    def source(self):
        out = '"'
        for b in self.raw:
            if b == 34:
                out += '\\"'
            elif b == 92:
                out += '\\\\'
            elif b == 10:
                out += '\\n'
            elif b == 9:
                out += '\\t'
            elif 32 <= b < 127:
                out += chr(b)
            else:
                out += '\\x%02x' % b
        out += '"'
        mods = []
        if self.ascii and self.explicit_ascii:
            mods.append('ascii')
        if self.wide:
            mods.append('wide')
        if self.nocase:
            mods.append('nocase')
        if self.fullword:
            mods.append('fullword')
        return out + ''.join(' ' + m for m in mods)

    def at(self, data, pos):
        for wide in ((False,) if not self.wide else ((False, True) if self.ascii else (True,))):
            if self.literal(data, pos, wide):
                return True
        return False

    def literal(self, data, pos, wide):
        step = 2 if wide else 1
        n = len(self.raw)
        if pos + n * step > len(data):
            return False
        for i, want in enumerate(self.raw):
            got = data[pos + i * step]
            if self.nocase:
                if lower(got) != lower(want):
                    return False
            elif got != want:
                return False
            if wide and data[pos + i * step + 1] != 0:
                return False
        if self.fullword:
            end = pos + n * step
            if wide:
                if pos >= 2 and data[pos - 1] == 0 and alnum(data[pos - 2]):
                    return False
                if end + 2 <= len(data) and alnum(data[end]) and data[end + 1] == 0:
                    return False
            else:
                if pos >= 1 and alnum(data[pos - 1]):
                    return False
                if end < len(data) and alnum(data[end]):
                    return False
        return True


class Hex:
    def __init__(self, tokens):
        self.tokens = tokens  # ('b', value, mask) | ('j', lo, hi)
        self.hex = True
        parts = []
        for t in tokens:
            if t[0] == 'j':
                parts.append('.{%d,%d}?' % (t[1], t[2]))
            else:
                _, v, m = t
                if m == 255:
                    parts.append(re.escape(bytes([v])).decode('latin-1') if False else '\\x%02x' % v)
                elif m == 0:
                    parts.append('.')
                elif m == 240:
                    parts.append('[\\x%02x-\\x%02x]' % (v, v | 15))
                else:
                    parts.append('[' + ''.join('\\x%02x' % (h << 4 | (v & 15)) for h in range(16)) + ']')
        self.rx = re.compile(''.join(parts).encode('latin-1'), re.DOTALL)

    def source(self):
        out = []
        for t in self.tokens:
            if t[0] == 'j':
                out.append('[%d]' % t[1] if t[1] == t[2] else '[%d-%d]' % (t[1], t[2]))
            else:
                _, v, m = t
                hi = '?' if (m & 240) == 0 else '%x' % (v >> 4)
                lo = '?' if (m & 15) == 0 else '%x' % (v & 15)
                out.append(hi + lo)
        return '{ ' + ' '.join(out) + ' }'

    def at(self, data, pos):
        return self.rx.match(data, pos) is not None


def rand_text():
    kind = rng.randrange(5)
    if kind == 0:
        raw = bytes(pick(b'abc') for _ in range(rng.randrange(1, 4)))
    elif kind == 1:
        raw = pick([b'MZ', b'PE', b'http', b'cmd.exe', b'Admin', b'key', b'GET /'])
    elif kind == 2:
        raw = bytes(rng.randrange(256) for _ in range(rng.randrange(2, 5)))
    elif kind == 3:
        raw = pick([b'a"b', b'x\\y', b'tab\there', b'line\nfeed'])
    else:
        raw = bytes(pick(b'AaBb_9') for _ in range(rng.randrange(1, 5)))
    nocase = chance(0.3)
    wide = chance(0.3)
    ascii_ = (not wide) or chance(0.4)
    t = Text(raw, nocase, ascii_, wide, chance(0.25))
    t.explicit_ascii = ascii_ and (wide or chance(0.3))
    if not t.wide:
        t.ascii = True
    return t


def rand_hex():
    toks = []
    for _ in range(rng.randrange(1, 6)):
        if toks and toks[-1][0] != 'j' and chance(0.3):
            lo = rng.randrange(0, 4)
            toks.append(('j', lo, lo + rng.randrange(0, 4)))
        r = rng.randrange(10)
        v = rng.choice([0x4d, 0x5a, 0x90, 0x00, 0xff, 0x61, 0x62, rng.randrange(256)])
        if r < 6:
            toks.append(('b', v, 255))
        elif r < 8:
            toks.append(('b', 0, 0))
        elif r == 8:
            toks.append(('b', v & 0xf0, 0xf0))
        else:
            toks.append(('b', v & 0x0f, 0x0f))
    return Hex(toks)


def sample(p):
    """Some bytes the string matches (or nearly)."""
    if p.hex:
        out = b''
        for t in p.tokens:
            if t[0] == 'j':
                out += bytes(rng.randrange(256) for _ in range(rng.randrange(t[1], t[2] + 1)))
            else:
                _, v, m = t
                out += bytes([v | (rng.randrange(256) & ~m & 255)])
        return out
    raw = p.raw
    if p.nocase:
        raw = bytes(b ^ 32 if (65 <= b <= 90 or 97 <= b <= 122) and chance(0.5) else b for b in raw)
    if p.wide and (not p.ascii or chance(0.5)):
        return b''.join(bytes([b, 0]) for b in raw)
    return raw


def make_data(patterns):
    parts = []
    for _ in range(rng.randrange(0, 8)):
        r = rng.randrange(5)
        if r == 0 and patterns:
            s = sample(pick(patterns))
            parts.append(s)
            if chance(0.3):
                parts.append(s)
        elif r == 1:
            parts.append(bytes(rng.randrange(256) for _ in range(rng.randrange(0, 12))))
        elif r == 2:
            parts.append(bytes(pick(b'abcAB_ 09') for _ in range(rng.randrange(0, 10))))
        elif r == 3 and patterns:
            s = sample(pick(patterns))
            parts.append(bytes([pick(b'ab_9 ')]) + s + bytes([pick(b'ab_9 .')]))
        else:
            parts.append(b'\x00' * rng.randrange(0, 5))
    return b''.join(parts)[:240]


# ------------------------------------------------------------------ conditions
CMP = {0: '==', 1: '!=', 2: '<', 3: '<=', 4: '>', 5: '>='}


def cmp_eval(op, x, y):
    return [x == y, x != y, x < y, x <= y, x > y, x >= y][op]


def rand_cond(names, depth=0):
    r = rng.randrange(12 if depth < 3 else 7)
    if r == 0:
        return ('true',) if chance(0.7) else ('false',)
    if r <= 3 or depth >= 3:
        return ('str', pick(names))
    if r == 4:
        return ('at', pick(names), rng.randrange(0, 40))
    if r == 5:
        return ('count', pick(names), rng.randrange(6), rng.randrange(0, 4))
    if r == 6:
        return ('size', rng.randrange(6), rng.randrange(0, 120))
    if r == 7:
        quant = pick(['any', 'all', 'none', rng.randrange(1, 4)])
        kind = pick(['them', 'list', 'prefix'])
        return ('of', quant, kind, rng.sample(names, rng.randrange(1, len(names) + 1)))
    if r == 8:
        return ('not', rand_cond(names, depth + 1))
    if r == 9 or r == 10:
        return ('and', rand_cond(names, depth + 1), rand_cond(names, depth + 1))
    return ('or', rand_cond(names, depth + 1), rand_cond(names, depth + 1))


def prec(c):
    return {'or': 1, 'and': 2, 'not': 3}.get(c[0], 4)


def render(c, names_by_prefix=None):
    k = c[0]
    if k == 'true':
        return 'true'
    if k == 'false':
        return 'false'
    if k == 'str':
        return '$' + c[1]
    if k == 'at':
        return '$%s at %s' % (c[1], pick([str(c[2]), '0x%x' % c[2]]))
    if k == 'count':
        return '#%s %s %d' % (c[1], CMP[c[2]], c[3])
    if k == 'size':
        return 'filesize %s %d' % (CMP[c[1]], c[2])
    if k == 'of':
        q = c[1] if isinstance(c[1], str) else str(c[1])
        if c[2] == 'them':
            return '%s of them' % q
        return '%s of (%s)' % (q, ', '.join('$' + n for n in c[3]))
    if k == 'not':
        inner = render(c[1])
        if prec(c[1]) < 3:
            inner = '(' + inner + ')'
        return 'not ' + inner
    op = k
    left, right = render(c[1]), render(c[2])
    if prec(c[1]) < prec(c):
        left = '(' + left + ')'
    if prec(c[2]) <= prec(c):
        right = '(' + right + ')'
    if chance(0.1):
        left = '(' + left + ')'
    return '%s %s %s' % (left, op, right)


def evaluate(c, counts, pats, names, data):
    k = c[0]
    if k == 'true':
        return True
    if k == 'false':
        return False
    if k == 'str':
        return counts[names.index(c[1])] > 0
    if k == 'at':
        return c[2] < len(data) and pats[names.index(c[1])].at(data, c[2])
    if k == 'count':
        return cmp_eval(c[2], counts[names.index(c[1])], c[3])
    if k == 'size':
        return cmp_eval(c[1], len(data), c[2])
    if k == 'of':
        members = names if c[2] == 'them' else c[3]
        hit = sum(1 for n in members if counts[names.index(n)] > 0)
        q = c[1]
        if q == 'any':
            return hit >= 1
        if q == 'all':
            return hit == len(members)
        if q == 'none':
            return hit == 0
        return hit >= q
    if k == 'not':
        return not evaluate(c[1], counts, pats, names, data)
    if k == 'and':
        return evaluate(c[1], counts, pats, names, data) and evaluate(c[2], counts, pats, names, data)
    return evaluate(c[1], counts, pats, names, data) or evaluate(c[2], counts, pats, names, data)


cases = []


def make_case():
    nrules = rng.randrange(1, 4)
    source = ''
    all_patterns = []
    results = []
    scopes = []
    for ri in range(nrules):
        n = rng.randrange(1, 5)
        names = [pick(['a', 'b', 'c', 'str1', 'x', 'hdr', 'tail', 'k']) for _ in range(n)]
        names = list(dict.fromkeys(names))
        pats = [rand_hex() if chance(0.4) else rand_text() for _ in names]
        cond = rand_cond(names)
        # prefix sets: $s* form over names sharing a prefix is exercised through lists; keep `them` and lists
        text = 'rule r%d_%s {\n' % (ri, ident())
        if chance(0.3):
            text += '  meta:\n    author = "x y"\n    score = %d\n    ok = true\n' % rng.randrange(100)
        text += '  strings:\n'
        for nm, p in zip(names, pats):
            text += '    $%s = %s\n' % (nm, p.source())
        text += '  condition:\n    %s\n}\n' % render(cond)
        if chance(0.2):
            text = '// header comment\n' + text + '/* trailing */\n'
        source += text
        scopes.append((names, pats, cond))
        all_patterns += pats
    data = make_data(all_patterns)
    counts_all = []
    offs_all = []
    rules = []
    for names, pats, cond in scopes:
        counts = []
        for p in pats:
            offs = [i for i in range(len(data)) if p.at(data, i)]
            counts.append(len(offs))
            counts_all.append(len(offs))
            offs_all.append(offs[:3])
        rules.append(evaluate(cond, counts, pats, names, data))
    cases.append({'op': 'scan', 'rules': source, 'h': data.hex(), 'e': {'ok': True, 'v': {'rules': rules, 'counts': counts_all, 'offs': offs_all}}})


def ident():
    return ''.join(pick('abcdefghij') for _ in range(rng.randrange(1, 6)))


for _ in range(150):
    make_case()

# list-of forms with a `$prefix*` wildcard
for _ in range(10):
    names = ['str_a', 'str_b', 'other', 'str_c']
    pats = [rand_text() for _ in names]
    wild = pick(['str_*', 'str_a*', 'oth*'])
    data = make_data(pats)
    q = pick(['any', 'all', 'none', '2'])
    text = 'rule w {\n strings:\n' + ''.join('  $%s = %s\n' % (n, p.source()) for n, p in zip(names, pats)) + \
        ' condition:\n  %s of ($%s)\n}\n' % (q, wild + ('' if wild.endswith('*') else ''))
    pre = wild[:-1]
    members = [n for n in names if n.startswith(pre)]
    counts = [sum(1 for i in range(len(data)) if p.at(data, i)) for p in pats]
    hit = sum(1 for n in members if counts[names.index(n)] > 0)
    want = {'any': hit >= 1, 'all': hit == len(members), 'none': hit == 0}.get(q, hit >= 2 if q == '2' else False)
    offs = [[i for i in range(len(data)) if p.at(data, i)][:3] for p in pats]
    cases.append({'op': 'scan', 'rules': text, 'h': data.hex(), 'e': {'ok': True, 'v': {'rules': [want], 'counts': counts, 'offs': offs}}})

bad = [
    'rule a { condition: }',
    'rule a { strings: $x = "abc" }',
    'rule a { strings: $x = "abc condition: $x }',
    'rule a { strings: $x = { 4D 5 } condition: $x }',
    'rule a { strings: $x = { [2] 4D } condition: $x }',
    'rule a { strings: $x = { 4D [2] } condition: $x }',
    'rule a { strings: $x = { 4D [3-1] 5A } condition: $x }',
    'rule a { strings: $x = { 4D [2][3] 5A } condition: $x }',
    'rule a { strings: $x = "a" $x = "b" condition: $x }',
    'rule a { strings: $x = "a" condition: $y }',
    'rule a { strings: $x = "a" condition: $x and }',
    'rule a { strings: $x = "a" condition: ($x }',
    'rule a { strings: $x = "a" condition: 3 of ($q) }',
    'rule a { strings: $x = "a" condition: any of }',
    'rule a { strings: $x = "a" condition: #x }',
    'rule a { strings: $x = "a" bogus condition: $x }',
    'rule a { condition: true } rule a { condition: true }',
    'rul a { condition: true }',
    'rule a { strings: $x = "\\q" condition: $x }',
    'rule a { strings: $x = "" condition: $x }',
    'rule { condition: true }',
    'rule a { condition: true',
]
for b in bad:
    cases.append({'op': 'scan', 'rules': b, 'h': '00', 'e': {'ok': False, 'error': 'syntax'}})
# an empty rule file compiles to nothing
cases.append({'op': 'scan', 'rules': '', 'h': '4d5a', 'e': {'ok': True, 'v': {'rules': [], 'counts': [], 'offs': []}}})

BS = chr(92)
lines = [json.dumps(c, sort_keys=True) for c in cases]
chunks = []
for i in range(0, len(lines), 10):
    body = '\\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"') for l in lines[i:i + 10]) + '\\n'
    chunks.append('"' + body + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'sig_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'text_sig', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d cases in %d chunks -> text_sig' % (len(cases), len(chunks)))
