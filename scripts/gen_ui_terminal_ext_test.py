#!/usr/bin/env python3
"""Independent model of the e.ui.terminal additions of D3501 (L136) for
tests/selfhost/fixtures/link/ui_terminal_ext: reflow on resize, key / mouse / focus / paste encoding and the
selection model.

The state before a reflow or a selection comes from scripts/gen_ui_terminal_test.py's regex-driven VT model (the
engine under test is a byte state machine); the reflow and the selection text are computed here from the
contract written in lib/e/ui/terminal.e's comments, on Python lists of cells, building the whole new buffer
forward and cutting it afterwards (the engine fills a scratch from the newest line backwards). Key and mouse
bytes are tabulated from xterm's ctlseqs (the asserts below carry the documented examples).
Run from the repo root to rewrite the GENERATED block of the fixture's main.e.
"""
import pathlib, random, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_ui_terminal_test as gt

RS, US = b'\x1e', b'\x1f'
WIDE, CONT, WRAPPED = 256, 512, 1
BLANK = (32, 0, 0, 0)
MAXC, MAXR = 40, 20


# ---- pre-state ------------------------------------------------------------------------------------------------
def run_model(stream, cols, rows, sb):
    gt.COLS, gt.ROWS, gt.SB = cols, rows, sb
    m = gt.Model()
    m.run(stream)
    if sb == 0: m.sb = []   # the model slices with [-SB:], which keeps everything for SB == 0
    return m


def buffer_of(m):
    return list(m.sb) + list(m.s)


def plain_blank(c): return c[0] in (32, 0) and c[2] == 0 and c[3] == 0


# ---- reflow ---------------------------------------------------------------------------------------------------
def reflow(lines, nsb, cx, cy, pend, old_cols, new_cols, rows, sbcap, max_lines):
    n = len(lines)
    groups, start = [], 0
    for i in range(n):
        if not (lines[i][1] & WRAPPED) or i == n - 1:
            groups.append((start, i)); start = i + 1
    cursor_abs = nsb + cy

    def kept(j, b):
        if j < b:
            tail, head = lines[j][0][old_cols - 1], lines[j + 1][0][0]
            if tail[0] in (32, 0) and tail[3] == 0 and head[3] & WIDE: return old_cols - 1
        return old_cols

    def layout(a, b):
        seq = []
        for j in range(a, b + 1): seq += lines[j][0][:kept(j, b)]
        last_nb = max([i + 1 for i, c in enumerate(seq) if not plain_blank(c)] or [0])
        cur = None
        if a <= cursor_abs <= b:
            cur = sum(kept(j, b) for j in range(a, cursor_abs)) + cx + (1 if pend else 0)
        ln = last_nb if cur is None else max(last_nb, cur + 1)
        rows_out = [[list([BLANK] * new_cols), 0]]
        row = col = 0
        curpos = (0, 0)
        i = 0

        def wrap_row():
            nonlocal row, col
            rows_out[row][1] = WRAPPED
            rows_out.append([list([BLANK] * new_cols), 0])
            row += 1; col = 0
        while i < ln and i < len(seq):
            c = seq[i]
            w, unit, put = 1, 1, [c]
            if c[3] & WIDE and i + 1 < len(seq) and seq[i + 1][3] & CONT:
                w, unit, put = 2, 2, [c, seq[i + 1]]
            if w == 2 and new_cols == 1:
                put, w = [(32, 0, c[2], 0)], 1
            if col + w > new_cols:
                if col < new_cols: rows_out[row][0][col] = (32, 0, c[2], 0)
                wrap_row()
            if cur is not None and (i == cur or (unit == 2 and i + 1 == cur)): curpos = (row, col)
            for k, p in enumerate(put): rows_out[row][0][col + k] = p
            col += w; i += unit
        while i < ln:
            if col + 1 > new_cols: wrap_row()
            if i == cur: curpos = (row, col)
            col += 1; i += 1
        return rows_out, curpos, cur is not None

    out_groups = [layout(a, b) for (a, b) in groups]
    filled, kept_groups, got = 0, [], False
    for g in reversed(out_groups):
        if filled + len(g[0]) > max_lines: break
        kept_groups.append(g); filled += len(g[0])
        if g[2]: got = True
    if not got: return None
    kept_groups.reverse()
    flat, cur_rel = [], 0
    for rws, cpos, has in kept_groups:
        if has: cur_rel = len(flat) + cpos[0]; cur_col = cpos[1]
        flat += [(r[0], r[1]) for r in rws]
    total = len(flat)
    top = 0 if total <= rows else min(total - rows, cur_rel)
    sb_n = min(top, sbcap)
    sb = flat[top - sb_n: top] if sb_n else []
    live = flat[top: top + rows]
    while len(live) < rows: live.append(([BLANK] * new_cols, 0))
    return sb, live, cur_col, cur_rel - top


def dump_lines(lines, cx, cy, nsb):
    out = []
    for cells, fl in lines:
        text = ''.join('_' if c[3] & CONT else ' ' if c[0] in (32, 0) else chr(c[0]) if 33 <= c[0] <= 126 else '#' for c in cells)
        h = 14695981039346656037
        for c in cells:
            for v in (c[1], c[2], c[3]):
                h = ((h ^ (v & 0xFFFFFFFF)) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
        out.append('%s|%d|%016x' % (text, fl & 1, h))
    return (';'.join(out) + '@%d,%d,%d' % (cx, cy, nsb)).encode()


def reflow_case(stream, cols0, rows0, sbcap, ncols, nrows, max_lines):
    m = run_model(stream, cols0, rows0, sbcap)
    lines = buffer_of(m)
    r = reflow(lines, len(m.sb), m.cx, m.cy, m.pend, cols0, ncols, nrows, sbcap, max_lines)
    if r is None: return b'EXHAUSTED'
    sb, live, cx, cy = r
    return dump_lines(sb + live, cx, cy, len(sb))


# ---- selection ------------------------------------------------------------------------------------------------
def cls(c):
    if c[0] in (32, 0): return 0
    if 48 <= c[0] <= 57 or 65 <= c[0] <= 90 or 97 <= c[0] <= 122 or c[0] == 95 or c[0] >= 128: return 1
    return 2


def select_text(stream, cols, rows, sbcap, mode, al, ac, hl, hc):
    m = run_model(stream, cols, rows, sbcap)
    L = buffer_of(m)
    n = len(L)
    if mode == 0: return b''
    al, hl = min(al, n - 1), min(hl, n - 1)

    def snap(line, col):
        col = min(col, cols - 1)
        if col > 0 and L[line][0][col][3] & CONT: col -= 1
        return col

    def wbounds(line, col):
        c0 = snap(line, col)
        k = cls(L[line][0][c0])
        s = c0
        while s > 0:
            p = s - 1
            if p > 0 and L[line][0][p][3] & CONT: p -= 1
            if cls(L[line][0][p]) != k: break
            s = p
        f = c0
        while f < cols:
            cell = L[line][0][f]
            if not cell[3] & CONT and cls(cell) != k: break
            f += 1
        return s, f

    def wrapped(l): return bool(L[l][1] & WRAPPED)

    def first_of(l):
        while l > 0 and wrapped(l - 1): l -= 1
        return l

    def last_of(l):
        while l + 1 < n and wrapped(l): l += 1
        return l
    a_c, h_c = snap(al, ac), snap(hl, hc)
    if mode == 4:
        sl, sc, el, ec = min(al, hl), min(a_c, h_c), max(al, hl), max(a_c, h_c) + 1
    else:
        (fl_, fc), (ll_, lc) = ((al, a_c), (hl, h_c)) if (al, a_c) <= (hl, h_c) else ((hl, h_c), (al, a_c))
        if mode == 3: sl, sc, el, ec = first_of(fl_), 0, last_of(ll_), cols
        elif mode == 2:
            # D4500: a word runs over a wrap -- model it on the flattened logical line, head cells only
            def run(line, col):
                col = snap(line, col)
                flat = [(l, c) for l in range(first_of(line), last_of(line) + 1) for c in range(cols) if not L[l][0][c][3] & CONT]
                i = flat.index((line, col))
                k = cls(L[line][0][col])
                s = f = i
                while s > 0 and cls(L[flat[s - 1][0]][0][flat[s - 1][1]]) == k: s -= 1
                while f + 1 < len(flat) and cls(L[flat[f + 1][0]][0][flat[f + 1][1]]) == k: f += 1
                el_, ec_ = flat[f]
                return flat[s], (el_, ec_ + (2 if L[el_][0][ec_][3] & WIDE else 1))
            (sl, sc), _ = run(fl_, fc)
            _, (el, ec) = run(ll_, lc)
        else: sl, sc, el, ec = fl_, fc, ll_, lc + 1
    out = []
    for l in range(sl, el + 1):
        c0, c1 = 0, cols
        if mode == 4: c0, c1 = sc, ec
        elif mode != 3:
            if l == sl: c0 = sc
            if l == el: c1 = ec
        last = c1
        trim = mode == 4 or (c1 == cols and not wrapped(l))
        if trim:
            while last > c0:
                cell = L[l][0][last - 1]
                if cell[3] & CONT or cell[0] not in (32, 0): break
                last -= 1
        def filler(c):   # D4500: the blank that pads a wide character moved to the next row is layout, not text
            cell = L[l][0][c]
            return (c == cols - 1 and wrapped(l) and l + 1 < n and cell[0] in (32, 0) and cell[3] == 0
                    and bool(L[l + 1][0][0][3] & WIDE))
        txt = ''.join(chr(L[l][0][c][0] or 32) for c in range(c0, last) if not L[l][0][c][3] & CONT and not filler(c))
        out.append(txt)
        if l != el and not (wrapped(l) and l != el): out.append('\n')
    return ''.join(out).encode('utf-8')


# ---- keys, mouse, paste ---------------------------------------------------------------------------------------
KEYS = ['UP', 'DOWN', 'RIGHT', 'LEFT', 'HOME', 'END', 'INSERT', 'DELETE', 'PAGE_UP', 'PAGE_DOWN', 'ENTER', 'TAB', 'BACKSPACE', 'ESCAPE'] + ['F%d' % i for i in range(1, 13)]
KEYBASE = 2097153


def key_bytes(key, mods, app, lnm):
    m = 1 + (mods & 15)
    alt = bool(mods & 10)
    ctrl, shift = bool(mods & 4), bool(mods & 1)
    pre = b'\x1b' if alt else b''
    if key < 0x110000:
        c = key
        if ctrl:
            ch = chr(c)
            if 'a' <= ch <= 'z': c -= 96
            elif 'A' <= ch <= 'Z': c -= 64
            elif ch in '@ 2': c = 0
            elif ch in '[3': c = 27
            elif ch in '\\4': c = 28
            elif ch in ']5': c = 29
            elif ch in '^6': c = 30
            elif ch in '_/7': c = 31
            elif ch in '?8': c = 127
            else: return pre + chr(c).encode()
            return pre + bytes([c])
        return pre + chr(c).encode()
    name = KEYS[key - KEYBASE]
    if name == 'ENTER': return pre + b'\r' + (b'\n' if lnm else b'')
    if name == 'TAB': return pre + (b'\x1b[Z' if shift else b'\t')
    if name == 'BACKSPACE': return pre + (b'\x08' if ctrl else b'\x7f')
    if name == 'ESCAPE': return pre + b'\x1b'
    letters = {'UP': 'A', 'DOWN': 'B', 'RIGHT': 'C', 'LEFT': 'D', 'HOME': 'H', 'END': 'F'}
    if name in letters:
        if m == 1: return (b'\x1bO' if app else b'\x1b[') + letters[name].encode()
        return ('\x1b[1;%d%s' % (m, letters[name])).encode()
    tild = {'INSERT': 2, 'DELETE': 3, 'PAGE_UP': 5, 'PAGE_DOWN': 6, 'F5': 15, 'F6': 17, 'F7': 18, 'F8': 19, 'F9': 20, 'F10': 21, 'F11': 23, 'F12': 24}
    if name in ('F1', 'F2', 'F3', 'F4'):
        f = 'PQRS'['F1 F2 F3 F4'.split().index(name)]
        if m == 1: return ('\x1bO' + f).encode()
        return ('\x1b[1;%d%s' % (m, f)).encode()
    n = tild[name]
    return (('\x1b[%d~' % n) if m == 1 else ('\x1b[%d;%d~' % (n, m))).encode()


def mouse_bytes(mode, sgr, button, action, mods, x, y):
    if mode == 0 or button > 7 or action > 2: return b''
    wheel = button >= 4
    if wheel and action != 0: return b''
    if action == 2:
        if wheel or mode in (9, 1000): return b''
        if mode == 1002 and button == 3: return b''
    if mode == 9 and (action != 0 or wheel): return b''
    cb = 64 + (button - 4) if wheel else button
    if action == 1 and not sgr: cb = 3
    if mode != 9:
        if mods & 1: cb += 4
        if mods & 10: cb += 8
        if mods & 4: cb += 16
    if action == 2: cb += 32
    if sgr and mode != 9:
        return ('\x1b[<%d;%d;%d%s' % (cb, x + 1, y + 1, 'm' if action == 1 else 'M')).encode()
    if x > 222 or y > 222: return b''
    return b'\x1b[M' + bytes([cb + 32, x + 33, y + 33])


def paste_bytes(bracketed, data):
    if bracketed: return b'\x1b[200~' + data.replace(b'\x1b', b'') + b'\x1b[201~'
    return data.replace(b'\r\n', b'\r').replace(b'\n', b'\r')


# documented examples (xterm ctlseqs): the table above must reproduce them
assert key_bytes(KEYBASE, 0, 0, 0) == b'\x1b[A' and key_bytes(KEYBASE, 0, 1, 0) == b'\x1bOA'
assert key_bytes(KEYBASE + 3, 4, 0, 0) == b'\x1b[1;5D' and key_bytes(KEYBASE + 6, 0, 0, 0) == b'\x1b[2~'
assert key_bytes(KEYBASE + 14, 0, 0, 0) == b'\x1bOP' and key_bytes(KEYBASE + 18, 0, 0, 0) == b'\x1b[15~'
assert key_bytes(KEYBASE + 14, 1, 0, 0) == b'\x1b[1;2P' and key_bytes(ord('c'), 4, 0, 0) == b'\x03'
assert mouse_bytes(1000, 1, 0, 0, 0, 1, 1) == b'\x1b[<0;2;2M' and mouse_bytes(1000, 1, 0, 1, 0, 1, 1) == b'\x1b[<0;2;2m'
assert mouse_bytes(1000, 0, 0, 0, 0, 0, 0) == b'\x1b[M !!' and mouse_bytes(1000, 0, 0, 1, 0, 0, 0) == b'\x1b[M#!!'
assert mouse_bytes(1000, 1, 4, 0, 0, 5, 5) == b'\x1b[<64;6;6M' and mouse_bytes(1003, 1, 3, 2, 0, 5, 5) == b'\x1b[<35;6;6M'


# ---- generation -----------------------------------------------------------------------------------------------
WORDS = ['alpha', 'be', 'gamma12', 'x', 'delta_epsilon', 'zeta', 'e', 'foo.bar', 'a-b', '世界', 'été', 'hello', 'w']
EXTRA = ['\x1b[31m', '\x1b[0m', '\x1b[44m', '\x1b[1m', '\x1b[2D', '\r', '\x1b[K', '\x1b[3C']


def gen_stream(rnd, n):
    parts = []
    for _ in range(n):
        r = rnd.random()
        if r < 0.55: parts.append(rnd.choice(WORDS) + ' ')
        elif r < 0.72: parts.append('\r\n')
        elif r < 0.84: parts.append(rnd.choice(WORDS))
        else: parts.append(rnd.choice(EXTRA))
    return ''.join(parts).encode('utf-8')


def build():
    rnd = random.Random(3501)
    cases = []

    def add(op, args, expected):
        cases.append(([op.encode()] + [a if isinstance(a, bytes) else str(a).encode() for a in args], expected))

    # reflow
    hand = [(b'abcdefghijklmnopqrstuvwxyz0123456789', 10, 4, 20, 20, 6, 20), (b'one\r\ntwo three four five six seven\r\nx', 12, 5, 20, 7, 5, 20),
            (b'\xe4\xb8\x96\xe7\x95\x8c\xe4\xb8\x96\xe7\x95\x8c\xe4\xb8\x96\xe7\x95\x8c\xe4\xb8\x96', 8, 4, 10, 5, 6, 20),
            (b'\xe4\xb8\x96\xe4\xb8\x96\xe4\xb8\x96', 7, 3, 4, 2, 6, 20), (b'\xe4\xb8\x96\xe4\xb8\x96', 4, 3, 4, 1, 5, 20),
            (b'x' * 60, 10, 3, 3, 4, 3, 20), (b'', 10, 4, 5, 20, 4, 20), (b'ab\r\n', 5, 3, 5, 12, 3, 20),
            (b'\x1b[31mred \x1b[44mblue text that wraps around\x1b[0m end', 9, 6, 20, 14, 6, 20)]
    for stream, c0, r0, sbc, nc, nr, ml in hand:
        add('R', [stream, c0, r0, sbc, nc, nr, ml], reflow_case(stream, c0, r0, sbc, nc, nr, ml))
    for _ in range(70):
        stream = gen_stream(rnd, rnd.randint(4, 60))
        c0 = rnd.choice([6, 9, 12, 16, 20, 30])
        nc = rnd.choice([c for c in (4, 5, 8, 11, 17, 25, 33, 40) if c != c0])
        r0, nr = rnd.randint(3, 10), rnd.randint(2, 12)
        sbc = rnd.choice([0, 4, 40])
        ml = rnd.choice([200, 200, nr + 2, max(nr, 8)])
        add('R', [stream, c0, r0, sbc, nc, nr, ml], reflow_case(stream, c0, r0, sbc, nc, nr, ml))

    # selection
    for i in range(80):
        stream = gen_stream(rnd, rnd.randint(8, 50))
        c0, r0 = rnd.choice([10, 14, 20]), rnd.randint(4, 8)
        sbc = rnd.choice([0, 12])
        m = run_model(stream, c0, r0, sbc)
        n = len(m.sb) + r0
        mode = rnd.choice([1, 1, 2, 3, 4])
        al, hl = rnd.randrange(n), rnd.randrange(n)
        ac, hc = rnd.randrange(c0), rnd.randrange(c0)
        add('S', [stream, c0, r0, sbc, mode, al, ac, hl, hc], select_text(stream, c0, r0, sbc, mode, al, ac, hl, hc))
    add('S', [b'x', 10, 3, 0, 0, 0, 0, 0, 0], b'')

    # keys
    chars = [ord(c) for c in 'aAzZ019@ []\\^_/?-'] + [0xE9, 0x4E16, 0x1F600]
    for mods in (0, 1, 2, 4, 5, 6, 8, 15):
        for ch in chars:
            add('K', [ch, mods, 0, 0], key_bytes(ch, mods, 0, 0).hex().encode())
    for k in range(len(KEYS)):
        for mods in (0, 1, 2, 4, 5, 7, 8, 15):
            for app in (0, 1):
                lnm = 1 if (k + mods) % 5 == 0 else 0
                add('K', [KEYBASE + k, mods, app, lnm], key_bytes(KEYBASE + k, mods, app, lnm).hex().encode())
    add('K', [KEYBASE + 100, 0, 0, 0], b'')

    # mouse
    for mode in (0, 9, 1000, 1002, 1003):
        for sgr in (0, 1):
            for button in range(8):
                for action in range(3):
                    mods = rnd.choice([0, 0, 1, 4, 6, 12])
                    x, y = rnd.choice([(0, 0), (10, 5), (79, 23), (222, 222), (223, 4), (4, 300)])
                    add('M', [mode, sgr, button, action, mods, x, y], mouse_bytes(mode, sgr, button, action, mods, x, y).hex().encode())
    add('M', [1000, 1, 9, 0, 0, 1, 1], b'')

    # focus and paste
    for on in (0, 1):
        for foc in (0, 1):
            e = (b'\x1b[I' if foc else b'\x1b[O') if on else b''
            add('F', [on, foc], e.hex().encode())
    datas = [b'plain', b'a\nb\r\nc', b'esc\x1b[201~injected', b'', b'\r\r\n\n', b'tab\there']
    for br in (0, 1):
        for d in datas:
            add('P', [br, d], paste_bytes(br, d).hex().encode())

    # selection_adjust
    for al, hl, dr in ((5, 9, 2), (1, 9, 3), (1, 2, 3), (0, 0, 0), (7, 3, 4), (3, 3, 4)):
        sel = [al, 4, hl, 6]
        m = 1
        if hl < dr and al < dr: out = 'gone'
        else:
            a_l, a_c, h_l, h_c = sel
            if al < dr: a_l, a_c = 0, 0
            else: a_l = al - dr
            if hl < dr: h_l, h_c = 0, 0
            else: h_l = hl - dr
            out = '%d,%d,%d,%d' % (a_l, a_c, h_l, h_c)
        add('J', [al, 4, hl, 6, dr], out.encode())
    return cases


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
    for f, e in cases:
        for part in f + [e]:
            assert RS not in part and US not in part, part
    script = RS.join(US.join(f) for f, _ in cases)
    expected = RS.join(e for _, e in cases)
    block = ['// BEGIN GENERATED (scripts/gen_ui_terminal_ext_test.py)',
             'fn script() -> str { ret %s }' % literal(script),
             'fn expected() -> str { ret %s }' % literal(expected),
             'const CASES: usize = %dusize' % len(cases),
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_terminal_ext/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8', newline='\n')
    kinds = {}
    for f, _ in cases: kinds[f[0].decode()] = kinds.get(f[0].decode(), 0) + 1
    print('%d cases, script %d bytes, expected %d bytes' % (len(cases), len(script), len(expected)), kinds)


if __name__ == '__main__':
    main()
