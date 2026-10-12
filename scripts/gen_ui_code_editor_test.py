#!/usr/bin/env python3
"""Independent flat-text model of the e.ui.code_editor engine (D3201, L065) for
tests/selfhost/fixtures/link/ui_code_editor.

The model keeps the document as one Python `bytearray`, positions as byte offsets and history as Python lists; it
shares no code with lib/e/ui/code_editor.e (no gap buffer, no incremental line index, no state cache: lines and
tokens are recomputed from scratch after every operation). A seeded script of editing operations is run through it
and a digest is recorded after EVERY operation: document bytes, selections, dirty/undo/redo state and the full
token stream. The fixture replays the same script through the engine and compares digests, so the first diverging
operation is named by exit code. Run from the repo root to rewrite the GENERATED block of the fixture's main.e.
"""
import random, pathlib

CAP, MAXL, MAXS = 400, 40, 8
HENT, HEDITS, HBYTES = 12, 40, 260
TAB, UNIT = 4, 4
RS, US = b'\x1e', b'\x1f'
KW = set(b'async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof var void while with yield'.split())
FNV = 1099511628211


def lo(r): return min(r[0], r[1])
def hi(r): return max(r[0], r[1])
def is_word(c): return 48 <= c <= 57 or 65 <= c <= 90 or 97 <= c <= 122 or c == 95 or c >= 128


def valid_utf8(b):
    try:
        b.decode('utf-8'); return True
    except UnicodeDecodeError:
        return False


class Stack:
    def __init__(s): s.ents = []

    def counts(s):
        return (len(s.ents), sum(len(e['b']) for e in s.ents), sum(len(b) for e in s.ents for b in e['b']),
                sum(len(t) for e in s.ents for b in e['b'] for (_, _, t) in b), sum(len(e['sels']) for e in s.ents))

    def room(s, nent, nbat, ned, ntext, nsel):
        c = s.counts()
        return (c[0] + nent <= HENT and c[1] + nbat <= HENT * 4 and c[2] + ned <= HEDITS and
                c[3] + ntext <= HBYTES and c[4] + nsel <= HENT * MAXS)

    def make_room(s, nent, nbat, ned, ntext, nsel, keep):
        while not s.room(nent, nbat, ned, ntext, nsel):
            if len(s.ents) <= keep: return False
            s.ents.pop(0)
        return True


class Model:
    def __init__(s):
        s.t = bytearray()
        s.sels = [(0, 0, None)]   # (anchor, head, goal column or None)
        s.prim = 0
        s.undo, s.redo = Stack(), Stack()
        s.cid, s.nid, s.saved = 1, 2, 1
        s.merge, s.mkind = False, 0
        s.tabs = False

    # -- text helpers (everything recomputed from the flat bytes)
    def lines(s): return [0] + [i + 1 for i, c in enumerate(s.t) if c == 10]

    def line_of(s, pos):
        r = 0
        for i, v in enumerate(s.lines()):
            if v <= pos: r = i
        return r

    def lstart(s, ln): return s.lines()[ln]

    def lend(s, ln):
        st = s.lines()
        return st[ln + 1] - 1 if ln + 1 < len(st) else len(s.t)

    def boundary(s, p): return p == 0 or p == len(s.t) or (p < len(s.t) and (s.t[p] & 0xC0) != 0x80)

    def dec(s, p):
        if p >= len(s.t): return (0, 0)
        b = s.t[p]
        need = 1 if 192 <= b <= 223 else 2 if 224 <= b <= 239 else 3 if 240 <= b <= 247 else 0
        if need == 0 or p + need >= len(s.t): return (b, 1)
        return (ord(bytes(s.t[p:p + need + 1]).decode('utf-8', 'replace')[0]), need + 1)

    @staticmethod
    def ext(cp):
        return 768 <= cp <= 879 or 8400 <= cp <= 8447 or 65024 <= cp <= 65039 or 127995 <= cp <= 127999 or cp == 8205

    def nextb(s, p):
        c0, n0 = s.dec(p)
        if n0 == 0: return p
        q, prev = p + n0, c0
        while q < len(s.t):
            c, n = s.dec(q)
            if prev == 8205 or s.ext(c):
                q += n; prev = c
            else: break
        return q

    def cpstart(s, p):
        if p == 0: return 0
        q = p - 1; g = 0
        while q > 0 and (s.t[q] & 0xC0) == 0x80 and g < 3: q -= 1; g += 1
        return q

    def prevb(s, p):
        q = s.cpstart(p)
        while q > 0:
            c, _ = s.dec(q)
            before = s.cpstart(q)
            bc, _ = s.dec(before)
            if s.ext(c) or bc == 8205: q = before
            else: break
        return q

    def col(s, pos):
        p, c = s.lstart(s.line_of(pos)), 0
        while p < pos:
            _, n = s.dec(p)
            if n == 0: return c
            p += n; c += 1
        return c

    def pos_col(s, ln, col):
        p, end, c = s.lstart(ln), s.lend(ln), 0
        while c < col and p < end:
            _, n = s.dec(p)
            if n == 0: return p
            p += n; c += 1
        return min(p, end)

    def wordc(s, p):
        c, n = s.dec(p)
        return n != 0 and (c >= 128 or is_word(c))

    def wend(s, p):
        while p < len(s.t) and not s.wordc(p) and s.t[p] != 10: p = s.nextb(p)
        while p < len(s.t) and s.wordc(p): p = s.nextb(p)
        return p

    def wstart(s, p):
        while p > 0 and not s.wordc(s.prevb(p)) and s.t[s.prevb(p)] != 10: p = s.prevb(p)
        while p > 0 and s.wordc(s.prevb(p)): p = s.prevb(p)
        return p

    # -- selections
    def normalize(s, rs, prim):
        mark = rs[min(prim, len(rs) - 1)][1]
        rs = sorted(rs, key=lambda r: (lo(r), hi(r)))
        out = [rs[0]]
        for cur in rs[1:]:
            prev = out[-1]
            merge = lo(cur) < hi(prev) or (lo(cur) == hi(prev) and (cur[0] == cur[1] or prev[0] == prev[1]))
            if merge:
                l_, h_ = lo(prev), max(hi(prev), hi(cur))
                if (prev[1] >= prev[0] and cur[1] >= cur[0]) or prev[0] == prev[1]: out[-1] = (l_, h_, None)
                else: out[-1] = (h_, l_, None)
            else: out.append(cur)
        pi = 0
        for i, r in enumerate(out):
            if lo(r) <= mark <= hi(r): pi = i
        return out, pi

    # -- commit
    @staticmethod
    def mappos(edits, pos, assoc):
        add = sub = 0
        for (at, rem, ins) in edits:
            if pos < at: break
            if pos <= at + rem:
                r = at + add - sub
                if assoc > 0: r += len(ins)
                return r
            add += len(ins); sub += rem
        return pos + add - sub

    def validate(s, edits):
        prev_end = 0; trem = tins = nlr = nli = 0
        for (at, rem, ins) in edits:
            if at < prev_end: return False
            if at > len(s.t) or rem > len(s.t) - at: return False
            if not s.boundary(at) or not s.boundary(at + rem): return False
            if not valid_utf8(ins): return False
            nli += ins.count(b'\n'); nlr += s.t[at:at + rem].count(b'\n')
            trem += rem; tins += len(ins); prev_end = at + rem
        if len(s.t) - trem + tins > CAP: return False
        if len(s.lines()) - nlr + nli > MAXL: return False
        return True

    def apply_raw(s, edits, to_stack):
        inv, add, sub = [], 0, 0
        for (at, rem, ins) in edits:
            inv.append((at + add - sub, len(ins), bytes(s.t[at:at + rem])))
            add += len(ins); sub += rem
        to_stack.ents[-1]['b'].append(inv)
        for (at, rem, ins) in reversed(edits):
            s.t[at:at + rem] = ins

    def commit(s, edits, new_sels, kind):
        if not s.validate(edits): return False
        new_len = len(s.t) + sum(len(i) - r for (_, r, i) in edits)
        if any(a > new_len or h > new_len for (a, h, _g) in new_sels): return False
        if not edits:
            if new_sels: s.sels, s.prim = s.normalize(list(new_sels), 0)
            return True
        trem = sum(r for (_, r, _) in edits)
        merge = kind != 0 and s.merge and s.mkind == kind and len(s.undo.ents) > 0
        if merge:
            if not s.undo.make_room(0, 1, len(edits), trem, 0, 1): return False
        else:
            if not s.undo.make_room(1, 1, len(edits), trem, len(s.sels), 0): return False
            s.undo.ents.append({'b': [], 'sels': list(s.sels), 'id': s.cid, 'kind': kind})
        s.redo.ents.clear()
        s.apply_raw(edits, s.undo)
        s.cid = s.nid; s.nid += 1
        if new_sels: s.sels, s.prim = s.normalize(list(new_sels), 0)
        s.merge = kind != 0
        s.mkind = kind
        return True

    def apply_as(s, edits, kind, assoc):
        mapped = []
        for (a, h, _g) in s.sels:
            l_, h_ = min(a, h), max(a, h)
            if l_ == h_:
                x = s.mappos(edits, l_, assoc); mapped.append((x, x, None))
            else:
                mlo, mhi = s.mappos(edits, l_, 1), s.mappos(edits, h_, -1)
                if a <= h: mapped.append((mlo, max(mlo, mhi), None))
                else: mapped.append((max(mlo, mhi), mlo, None))
        return s.commit(edits, mapped, kind)

    def step(s, frm, to):
        if not frm.ents: return True
        ent = frm.ents[-1]
        nb = len(ent['b']); ned = sum(len(b) for b in ent['b'])
        nrem = sum(r for b in ent['b'] for (_, r, _) in b)
        if not to.make_room(1, nb, ned, nrem, len(s.sels), 0): return False
        to.ents.append({'b': [], 'sels': list(s.sels), 'id': s.cid, 'kind': 0})
        for b in reversed(ent['b']):
            s.apply_raw(list(b), to)
        s.sels = list(ent['sels']); s.prim = min(s.prim, len(s.sels) - 1)
        s.cid = ent['id']
        frm.ents.pop()
        s.merge = False
        return True

    # -- commands
    def type_text(s, txt):
        edits, sels, shift = [], [], 0
        for (a, h, _g) in s.sels:
            l_, h_ = min(a, h), max(a, h)
            edits.append((l_, h_ - l_, txt)); x = l_ + shift + len(txt); sels.append((x, x, None))
            shift += len(txt) - (h_ - l_)
        return s.commit(edits, sels, 1)

    def delete_char(s, fwd):
        edits, sels, shift = [], [], 0
        for (a, h, _g) in s.sels:
            l_, h_ = min(a, h), max(a, h)
            if l_ == h_:
                if fwd: h_ = s.nextb(l_)
                else: l_ = s.prevb(h_)
            skip = False
            if edits:
                pat, prem, _ = edits[-1]
                if l_ < pat + prem:
                    l_ = pat + prem
                    if h_ < l_: skip = True
            if not skip:
                edits.append((l_, h_ - l_, b'')); x = l_ - shift; sels.append((x, x, None)); shift += h_ - l_
        return s.commit(edits, sels, 3 if fwd else 2)

    def indent_of(s, ln):
        p, end, col = s.lstart(ln), s.lend(ln), 0
        st = p
        while p < end and s.t[p] in (32, 9):
            col = (col // TAB + 1) * TAB if s.t[p] == 9 else col + 1
            p += 1
        return col, p - st

    def wr_indent(s, w):
        if s.tabs: return b'\t' * (w // TAB) + b' ' * (w % TAB)
        return b' ' * w

    def newline_indent(s):
        edits, sels, shift = [], [], 0
        for (a, h, _g) in s.sels:
            lo_, hi_ = min(a, h), max(a, h)
            ln = s.line_of(lo_)
            width, _ = s.indent_of(ln)
            b = lo_
            while b > s.lstart(ln) and s.t[b - 1] in (32, 9): b -= 1
            last = s.t[b - 1] if b > s.lstart(ln) else 0
            f, hend = hi_, s.lend(s.line_of(hi_))
            while f < hend and s.t[f] in (32, 9): f += 1
            first = s.t[f] if f < hend else 0
            deeper = last in b'{(['
            inner = width + (UNIT if deeper else 0)
            ins = b'\n' + s.wr_indent(inner)
            coff = len(ins)
            if deeper and (last, first) in ((123, 125), (40, 41), (91, 93)): ins += b'\n' + s.wr_indent(width)
            edits.append((lo_, hi_ - lo_, ins)); x = lo_ + shift + coff; sels.append((x, x, None))
            shift += len(ins) - (hi_ - lo_)
        return s.commit(edits, sels, 0)

    def sel_lines(s, cap=64):
        out = []
        for (a, h, _g) in s.sels:
            lo_, hi_ = min(a, h), max(a, h)
            l0, l1 = s.line_of(lo_), s.line_of(hi_)
            if hi_ > lo_ and l1 > l0 and s.lstart(l1) == hi_: l1 -= 1
            if out and out[-1] >= l0: l0 = out[-1] + 1
            l = l0
            while l <= l1 and len(out) < cap: out.append(l); l += 1
        return out

    def indent_lines(s, dedent):
        edits = []
        for ln in s.sel_lines():
            st = s.lstart(ln)
            if not dedent:
                if s.lend(ln) > st: edits.append((st, 0, s.wr_indent(UNIT)))
            else:
                if st < s.lend(ln) and s.t[st] == 9: rm = 1
                else:
                    rm = 0
                    while rm < UNIT and st + rm < s.lend(ln) and s.t[st + rm] == 32: rm += 1
                if rm > 0: edits.append((st, rm, b''))
        if not edits: return True
        return s.apply_as(edits, 0, 1)

    def toggle_comment(s):
        cm = b'//'
        lines = s.sel_lines()
        allc, anyc, minind = True, False, 1000000
        for ln in lines:
            _, nb = s.indent_of(ln)
            p = s.lstart(ln) + nb
            if p < s.lend(ln):
                anyc = True; minind = min(minind, nb)
                if bytes(s.t[p:p + 2]) != cm or p + 2 > s.lend(ln): allc = False
        if not anyc: return True
        edits = []
        for ln in lines:
            _, nb = s.indent_of(ln)
            p = s.lstart(ln) + nb
            if p < s.lend(ln):
                if allc:
                    rm = 2
                    if p + rm < s.lend(ln) and s.t[p + rm] == 32: rm += 1
                    edits.append((p, rm, b''))
                else:
                    edits.append((s.lstart(ln) + minind, 0, cm + b' '))
        return s.apply_as(edits, 0, 1)

    def move(s, d, ext):
        out = []
        for (a, h, g) in s.sels:
            l_, h_ = min(a, h), max(a, h)
            empty = l_ == h_
            nh, ng = h, g
            if d == 1: nh = l_ if (not ext and not empty) else s.prevb(h); ng = None
            elif d == 2: nh = h_ if (not ext and not empty) else s.nextb(h); ng = None
            elif d in (3, 4):
                ln = s.line_of(h)
                if ng is None: ng = s.col(h)
                if d == 3: nh = 0 if ln == 0 else s.pos_col(ln - 1, ng)
                else: nh = len(s.t) if ln + 1 >= len(s.lines()) else s.pos_col(ln + 1, ng)
            elif d == 5: nh = s.lstart(s.line_of(h)); ng = None
            elif d == 6: nh = s.lend(s.line_of(h)); ng = None
            elif d == 9: nh = s.wstart(h); ng = None
            elif d == 10: nh = s.wend(h); ng = None
            out.append((nh if not ext else a, nh, ng))
        s.sels, s.prim = s.normalize(out, s.prim)
        s.merge = False
        return True

    def find_all(s, q, cs, ww):
        qq = q if cs else q.lower()
        res, p = [], 0
        while p + len(q) <= len(s.t):
            seg = bytes(s.t[p:p + len(q)])
            seg = seg if cs else seg.lower()
            ok = seg == qq and s.boundary(p)
            if ok and ww:
                if p > 0 and s.wordc(s.cpstart(p)): ok = False
                if p + len(q) < len(s.t) and s.wordc(p + len(q)): ok = False
            if ok: res.append(p); p += len(q)
            else: p += 1
        return res

    def replace_all(s, q, repl, cs, ww):
        ms = s.find_all(q, cs, ww)
        if not ms: return True
        if len(ms) > HEDITS: return False
        return s.apply_as([(p, len(q), repl) for p in ms], 0, -1)

    # -- tokens (JavaScript language of the fixture), recomputed from nothing every time
    def tokens(s):
        out, st = [], 0
        lines = s.lines()
        for ln in range(len(lines)):
            p, end = lines[ln], s.lend(ln)
            while p < end:
                t0 = p
                if st == 1:
                    closed = False
                    while p < end and not closed:
                        if s.t[p:p + 2] == b'*/' and p + 2 <= end: p += 2; closed = True
                        else: p += 1
                    if closed: st = 0
                    out.append((t0, p, 6))
                elif st >= 2:
                    closed = False
                    while p < end and not closed:
                        c = s.t[p]
                        if c == 92 and p + 1 < end: p += 2
                        elif c == 96: p += 1; closed = True
                        else: p += 1
                    if closed: st = 0
                    out.append((t0, p, 5))
                else:
                    c = s.t[p]
                    if c in (32, 9, 13): p += 1
                    elif s.t[p:p + 2] == b'//' and p + 2 <= end: p = end; out.append((t0, p, 6))
                    elif s.t[p:p + 2] == b'/*' and p + 2 <= end:
                        p += 2; closed = False
                        while p < end and not closed:
                            if s.t[p:p + 2] == b'*/' and p + 2 <= end: p += 2; closed = True
                            else: p += 1
                        if not closed: st = 1
                        out.append((t0, p, 6))
                    elif c in b'"\'`':
                        p += 1; closed = False
                        while p < end and not closed:
                            d = s.t[p]
                            if d == 92 and p + 1 < end: p += 2
                            elif d == c: p += 1; closed = True
                            else: p += 1
                        if not closed and c == 96: st = 2
                        out.append((t0, p, 5))
                    elif is_word(c) and not (48 <= c <= 57):
                        while p < end and is_word(s.t[p]): p += 1
                        out.append((t0, p, 1 if bytes(s.t[t0:p]) in KW else 3))
                    elif 48 <= c <= 57:
                        while p < end and (is_word(s.t[p]) or s.t[p] == 46): p += 1
                        out.append((t0, p, 4))
                    else:
                        p += 1
                        out.append((t0, p, 8 if c in b'()[]{},;' else 7))
        return out

    def digest(s, result):
        h = 14695981039346656037
        def mix(v):
            nonlocal h
            h = ((h ^ (v & 0xFFFFFFFF)) * FNV) & 0xFFFFFFFFFFFFFFFF
        mix(result); mix(len(s.t))
        for b in s.t: mix(b)
        mix(len(s.sels))
        for (a, hd, _g) in s.sels: mix(a); mix(hd)
        mix(s.prim)
        mix(1 if s.cid != s.saved else 0)
        mix(len(s.undo.ents)); mix(len(s.redo.ents))
        for (a, b, k) in s.tokens(): mix(a); mix(b); mix(k)
        return h


WORDS = [b'let', b'x', b'foo', b'if', b'return', b'value', b'3.14', b'"str"', b"'c'", b'`tpl', b'tpl`', b'/*', b'*/', b'// note',
         'été'.encode(), '世界'.encode(), 'é'.encode(), b'{', b'}', b'(', b')', b'a_b', b'  ', b'\t']


def gen(seed=11, n=520):
    r = random.Random(seed)
    m = Model()
    ops, digs = [], []
    def run(op, args, fn):
        res = 0 if fn() else 1
        ops.append((op, args)); digs.append(m.digest(res))
    def brk():
        m.merge = False
        return True
    def sv():
        m.saved = m.cid
        return True
    for _ in range(n):
        k = r.randrange(100)
        L = len(m.t)
        if k < 26:
            txt = b''.join(r.choice(WORDS) for _ in range(r.randrange(1, 4)))
            if r.random() < 0.25: txt += b'\n'
            run('T', [txt], lambda txt=txt: m.type_text(txt))
        elif k < 33: run('B', [], lambda: m.delete_char(False))
        elif k < 37: run('F', [], lambda: m.delete_char(True))
        elif k < 45: run('U', [], lambda: m.step(m.undo, m.redo))
        elif k < 50: run('R', [], lambda: m.step(m.redo, m.undo))
        elif k < 56:
            a, h = r.randrange(L + 1), r.randrange(L + 1)
            def f(a=a, h=h):
                if not (m.boundary(a) and m.boundary(h)): return False
                m.sels, m.prim = m.normalize([(a, h, None)], 0); m.merge = False
                return True
            run('S', [a, h], f)
        elif k < 60:
            ps = sorted({r.randrange(L + 1) for _ in range(r.randrange(1, 5))})
            def f(ps=ps):
                if len(ps) > MAXS or not all(m.boundary(p) for p in ps): return False
                m.sels, m.prim = m.normalize([(p, p, None) for p in ps], 0); m.merge = False
                return True
            run('M', ps, f)
        elif k < 66:
            es, p = [], 0
            for _ in range(r.randrange(1, 4)):
                if p > L: break
                at = r.randrange(p, min(L, p + 20) + 1)
                rem = r.randrange(0, min(6, L - at) + 1)
                ins = r.choice([b'', b'XY', b'\n', b'{\n', 'ü'.encode()])
                es.append((at, rem, ins)); p = at + rem
            run('X', [es], lambda es=es: m.apply_as(es, 0, -1))
        elif k < 72: run('N', [], m.newline_indent)
        elif k < 76: run('I', [], lambda: m.indent_lines(False))
        elif k < 79: run('D', [], lambda: m.indent_lines(True))
        elif k < 83: run('C', [], m.toggle_comment)
        elif k < 85: run('G', [], brk)
        elif k < 89:
            q = r.choice([b'x', b'foo', b'let', b'e', b'a', b'AB', b'if'])
            repl = r.choice([b'', b'Z', b'qq', b'\n'])
            cs, ww = r.randrange(2), r.randrange(2)
            run('W', [q, repl, cs, ww], lambda: m.replace_all(q, repl, bool(cs), bool(ww)))
        elif k < 96:
            d = r.choice([1, 2, 3, 4, 5, 6, 9, 10]); ext = r.randrange(2)
            run('K', [d, ext], lambda d=d, ext=ext: m.move(d, bool(ext)))
        elif k < 98: run('Z', [], sv)
        else:
            tb = r.randrange(2)
            def f(tb=tb):
                m.tabs = bool(tb)
                return True
            run('O', [tb], f)
    return ops, digs, m


def encode(ops):
    out = bytearray()
    for op, args in ops:
        out += op.encode()
        if op == 'X':
            for (at, rem, ins) in args[0]:
                out += US + str(at).encode() + US + str(rem).encode() + US + ins
        else:
            for a in args:
                out += US + (a if isinstance(a, bytes) else str(a).encode())
        out += RS
    return bytes(out)


def literal(b):
    parts = []
    for c in b:
        if c == 0x22: parts.append('\\"')
        elif c == 0x5c: parts.append('\\\\')
        elif 0x20 <= c < 0x7f: parts.append(chr(c))
        else: parts.append('\\x%02X' % c)
    return '"' + ''.join(parts) + '"'


def main():
    ops, digs, m = gen()
    script = encode(ops)
    hexes = ''.join('%016x' % d for d in digs)
    block = ['// BEGIN GENERATED (scripts/gen_ui_code_editor_test.py)',
             'fn script() -> str { ret %s }' % literal(script),
             'fn expected() -> str { ret "%s" }' % hexes,
             'const OPS: usize = %dusize' % len(ops),
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_code_editor/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8', newline='\n')
    kinds = {}
    for op, _ in ops: kinds[op] = kinds.get(op, 0) + 1
    print('%d ops, script %d bytes, final doc %d bytes, undo %d redo %d' % (len(ops), len(script), len(m.t), len(m.undo.ents), len(m.redo.ents)), kinds)


if __name__ == '__main__':
    main()
