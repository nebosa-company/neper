#!/usr/bin/env python3
"""Independent model of e.ui.terminal for tests/selfhost/fixtures/link/ui_terminal (D3200, L136).

Written from the VT/xterm behaviour the module documents, not from lib/e/ui/terminal.e: it tokenises a generated
byte stream with a regular expression (the engine is a byte state machine) and keeps rows as Python lists.
Run from the repo root to rewrite the GENERATED block of the fixture's main.e: the stream as a string literal and
the expected FNV-1a hash of the final buffer, cursor, region, reply bytes and title.
"""
import random, re, sys, pathlib

COLS, ROWS, SB = 20, 8, 16
BLANK = (32, 0, 0, 0)
WIDE, CONT, WRAPPED = 256, 512, 1


def width(cp):
    if cp < 32 or 127 <= cp < 160: return 0
    if cp < 768: return 1
    if cp <= 879 or 8203 <= cp <= 8207 or 8400 <= cp <= 8447 or 65024 <= cp <= 65039: return 0
    for lo, hi in ((4352, 4447), (11904, 42191), (44032, 55203), (63744, 64255), (65040, 65049),
                   (65072, 65135), (65280, 65376), (65504, 65510), (127744, 128591), (129280, 129791),
                   (131072, 262141)):
        if lo <= cp <= hi: return 2
    return 1


class Model:
    def __init__(self):
        self.reset()

    @staticmethod
    def new_screen():
        return [([BLANK] * COLS, 0) for _ in range(ROWS)]  # (cells, flags)

    def reset(self):
        self.scr = [self.new_screen(), self.new_screen()]
        self.alt = 0
        self.sb = []
        self.cx = self.cy = 0
        self.pend = False
        self.top, self.bot = 0, ROWS - 1
        self.fg = self.bg = self.at = 0
        self.saved = (0, 0, 0, 0, 0, False, False)
        self.autowrap, self.origin, self.insert = True, False, False
        self.out = b''
        self.title = b''
        self.last = 32

    @property
    def s(self):
        return self.scr[self.alt]

    def blank(self):
        return (32, 0, self.bg, 0)

    def clear_row(self, r):
        self.s[r] = ([self.blank() for _ in range(COLS)], 0)

    def scroll_up(self, top, bot, n, keep):
        k = min(n, bot - top + 1)
        if k == 0: return
        if keep and top == 0 and not self.alt:
            for i in range(k):
                self.sb.append(self.s[i])
            self.sb = self.sb[-SB:]
        for r in range(top, bot - k + 1):
            self.s[r] = self.s[r + k]
        for r in range(bot - k + 1, bot + 1):
            self.clear_row(r)

    def scroll_down(self, top, bot, n):
        k = min(n, bot - top + 1)
        for r in range(bot, top + k - 1, -1):
            self.s[r] = self.s[r - k]
        for r in range(top, top + k):
            self.clear_row(r)

    def index(self):
        if self.cy == self.bot: self.scroll_up(self.top, self.bot, 1, True)
        elif self.cy + 1 < ROWS: self.cy += 1

    def rindex(self):
        if self.cy == self.top: self.scroll_down(self.top, self.bot, 1)
        elif self.cy > 0: self.cy -= 1

    def norm(self, r):  # a wide character's halves live and die together
        cells = self.s[r][0]
        for x in range(COLS):
            a = cells[x][3]
            if a & CONT and (x == 0 or not cells[x - 1][3] & WIDE):
                cells[x] = (32, 0, cells[x][2], 0)
            elif a & WIDE and (x + 1 >= COLS or not cells[x + 1][3] & CONT):
                cells[x] = (32, 0, cells[x][2], 0)

    def setflag(self, r):
        c, f = self.s[r]
        self.s[r] = (c, f | WRAPPED)

    def erase(self, r, x0, x1):
        cells = self.s[r][0]
        for x in range(x0, x1): cells[x] = self.blank()
        self.norm(r)

    def put(self, cp):
        w = width(cp)
        if w == 0: return
        self.last = cp
        if self.pend:
            self.pend = False
            if self.autowrap:
                self.setflag(self.cy); self.cx = 0; self.index()
        if w == 2 and self.cx + 1 >= COLS:
            if not self.autowrap: return
            self.erase(self.cy, self.cx, COLS); self.setflag(self.cy); self.cx = 0; self.index()
        cells = self.s[self.cy][0]
        if self.insert:
            for x in range(COLS - 1, self.cx + w - 1, -1): cells[x] = cells[x - w]
            for x in range(self.cx, min(COLS, self.cx + w)): cells[x] = self.blank()
        cells[self.cx] = (cp, self.fg, self.bg, self.at | (WIDE if w == 2 else 0))
        if w == 2: cells[self.cx + 1] = (0, self.fg, self.bg, self.at | CONT)
        self.norm(self.cy)
        self.cx += w
        if self.cx >= COLS:
            self.cx = COLS - 1; self.pend = True

    def lo(self): return self.top if self.origin else 0
    def hi(self): return self.bot if self.origin else ROWS - 1

    def move_to(self, r, c):
        self.cy = min(self.lo() + r, self.hi()); self.cx = min(c, COLS - 1); self.pend = False

    def save(self):
        self.saved = (self.cx, self.cy, self.fg, self.bg, self.at, self.pend, self.origin)

    def restore(self):
        self.cx, self.cy, self.fg, self.bg, self.at, self.pend, self.origin = self.saved
        self.cx = min(self.cx, COLS - 1); self.cy = min(self.cy, ROWS - 1)

    def set_mode(self, priv, m, on):
        if not priv:
            if m == 4: self.insert = on
            return
        if m == 7: self.autowrap = on
        elif m == 6: self.origin = on; self.move_to(0, 0)
        elif m == 1049:
            if on and not self.alt:
                self.save(); self.alt = 1; self.scr[1] = self.new_screen()
            elif not on and self.alt:
                self.alt = 0; self.restore()
            self.pend = False

    def sgr(self, p):
        if not p:
            self.fg = self.bg = self.at = 0; return
        bits = {1: 1, 2: 2, 3: 4, 4: 8, 21: 8, 5: 16, 6: 16, 7: 32, 8: 64, 9: 128}
        clear = {22: 3, 23: 4, 24: 8, 25: 16, 27: 32, 28: 64, 29: 128}
        i = 0
        while i < len(p):
            v = p[i]
            if v == 0: self.fg = self.bg = self.at = 0
            elif v in bits: self.at |= bits[v]
            elif v in clear: self.at &= ~clear[v] & 0xFFFFFFFF
            elif 30 <= v <= 37: self.fg = (1 << 24) | (v - 30)
            elif v == 39: self.fg = 0
            elif 40 <= v <= 47: self.bg = (1 << 24) | (v - 40)
            elif v == 49: self.bg = 0
            elif 90 <= v <= 97: self.fg = (1 << 24) | (v - 90 + 8)
            elif 100 <= v <= 107: self.bg = (1 << 24) | (v - 100 + 8)
            elif v in (38, 48):
                col, used = 0, 0
                if i + 2 < len(p) and p[i + 1] == 5:
                    col, used = (1 << 24) | (p[i + 2] & 255), 2
                elif i + 4 < len(p) and p[i + 1] == 2:
                    col, used = (2 << 24) | ((p[i + 2] & 255) << 16) | ((p[i + 3] & 255) << 8) | (p[i + 4] & 255), 4
                if used:
                    if v == 38: self.fg = col
                    else: self.bg = col
                    i += used
                else:
                    i = len(p)
            i += 1

    def csi(self, params, priv, f):
        p = [int(x) if x else 0 for x in params.split(';')] if params != '' else []
        def a(i, d=1):
            return p[i] if i < len(p) and p[i] != 0 else d
        n = a(0)
        lo, hi = self.lo(), self.hi()
        if f == 'A': self.cy = max(lo, self.cy - min(n, self.cy)); self.pend = False
        elif f in 'Be': self.cy = min(self.cy + n, hi); self.pend = False
        elif f in 'Ca': self.cx = min(self.cx + n, COLS - 1); self.pend = False
        elif f == 'D': self.cx -= min(n, self.cx); self.pend = False
        elif f == 'E': self.cy = min(self.cy + n, hi); self.cx = 0; self.pend = False
        elif f == 'F': self.cy = max(lo, self.cy - min(n, self.cy)); self.cx = 0; self.pend = False
        elif f in 'G`': self.cx = min(n - 1, COLS - 1); self.pend = False
        elif f in 'Hf': self.move_to(a(0) - 1, a(1) - 1)
        elif f == 'd': self.cy = min(lo + n - 1, hi); self.pend = False
        elif f == 'J':
            m = a(0, 0)
            if m == 0:
                self.erase(self.cy, self.cx, COLS)
                for r in range(self.cy + 1, ROWS): self.clear_row(r)
            elif m == 1:
                for r in range(0, self.cy): self.clear_row(r)
                self.erase(self.cy, 0, self.cx + 1)
            elif m == 2:
                for r in range(ROWS): self.clear_row(r)
            elif m == 3: self.sb = []
        elif f == 'K':
            m = a(0, 0)
            if m == 0: self.erase(self.cy, self.cx, COLS)
            elif m == 1: self.erase(self.cy, 0, self.cx + 1)
            elif m == 2: self.erase(self.cy, 0, COLS)
        elif f == 'L':
            if self.top <= self.cy <= self.bot:
                self.scroll_down(self.cy, self.bot, n); self.cx = 0; self.pend = False
        elif f == 'M':
            if self.top <= self.cy <= self.bot:
                self.scroll_up(self.cy, self.bot, n, False); self.cx = 0; self.pend = False
        elif f == '@':
            cells = self.s[self.cy][0]; k = min(n, COLS - self.cx)
            for x in range(COLS - 1, self.cx + k - 1, -1): cells[x] = cells[x - k]
            for x in range(self.cx, self.cx + k): cells[x] = self.blank()
            self.norm(self.cy)
        elif f == 'P':
            cells = self.s[self.cy][0]; k = min(n, COLS - self.cx)
            for x in range(self.cx, COLS - k): cells[x] = cells[x + k]
            for x in range(COLS - k, COLS): cells[x] = self.blank()
            self.norm(self.cy)
        elif f == 'X': self.erase(self.cy, self.cx, min(self.cx + n, COLS))
        elif f == 'S': self.scroll_up(self.top, self.bot, n, True)
        elif f == 'T': self.scroll_down(self.top, self.bot, n)
        elif f == 'b':
            for _ in range(n): self.put(self.last)
        elif f in 'hl':
            for m in p: self.set_mode(priv, m, f == 'h')
        elif f == 'm': self.sgr(p)
        elif f == 'n':
            m = a(0, 0)
            if m == 5: self.out += b'\x1b[0n'
            elif m == 6: self.out += b'\x1b[%d;%dR' % (self.cy - lo + 1, self.cx + 1)
        elif f == 'r':
            t, b = a(0) - 1, a(1, ROWS) - 1
            if t < b < ROWS: self.top, self.bot = t, b
            else: self.top, self.bot = 0, ROWS - 1
            self.move_to(0, 0)
        elif f == 's': self.save()
        elif f == 'u': self.restore()

    TOK = re.compile(rb'\x1b\[(\?)?([0-9;]*)([@-~])|\x1b\]([^\x07]*)\x07|\x1b([78MDEc])|([\x00-\x1f])|([\x20-\x7e])'
                     rb'|([\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf]{2})', re.S)

    def run(self, data):
        pos = 0
        while pos < len(data):
            m = self.TOK.match(data, pos)
            if not m: raise SystemExit('model: stream does not tokenise at %d' % pos)
            pos = m.end()
            g = m.groups()
            if g[2] is not None:
                self.csi(g[1].decode(), g[0] is not None, g[2].decode())
            elif g[3] is not None:
                if g[3][:2] in (b'0;', b'2;'): self.title = g[3][2:][:128]
            elif g[4] is not None:
                e = g[4]
                if e == b'7': self.save()
                elif e == b'8': self.restore()
                elif e == b'M': self.rindex(); self.pend = False
                elif e == b'D': self.index(); self.pend = False
                elif e == b'E': self.index(); self.cx = 0; self.pend = False
                elif e == b'c': self.reset()
            elif g[5] is not None:
                c = g[5][0]
                if c == 8:
                    if self.cx > 0: self.cx -= 1
                    self.pend = False
                elif c == 9:
                    x = self.cx + 1
                    while x < COLS - 1 and x % 8: x += 1
                    self.cx = min(x, COLS - 1); self.pend = False
                elif c in (10, 11, 12): self.index(); self.pend = False
                elif c == 13: self.cx = 0; self.pend = False
            elif g[6] is not None: self.put(g[6][0])
            else: self.put(ord(g[7].decode('utf-8')))

    def digest(self):
        h = 14695981039346656037
        def mix(v):
            nonlocal h
            h = ((h ^ (v & 0xFFFFFFFF)) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
        lines = self.sb + self.s
        for cells, fl in lines:
            for c in cells:
                for v in c: mix(v)
            mix(fl)
        for v in (self.cx, self.cy, len(self.sb), self.top, self.bot, self.alt): mix(v)
        for b in self.out: mix(b)
        for b in self.title: mix(b)
        return h, len(lines)


def gen_stream(seed=7, n=900):
    rnd = random.Random(seed)
    out = bytearray()
    words = ['hello', 'world', 'neper', 'terminal', 'xx', 'ABCDEFGHIJ', '0123456789']
    csis = list('ABCDEFGHdJKLM@PXSTmrnsub')
    for _ in range(n):
        k = rnd.randrange(100)
        if k < 38: out += rnd.choice(words).encode()
        elif k < 46: out += b'\r\n'
        elif k < 49: out += b'\x08'
        elif k < 52: out += b'\t'
        elif k < 55: out += rnd.choice(['é', '世', '界', 'ü']).encode()
        elif k < 58: out += b'\x1b' + rnd.choice([b'7', b'8', b'M', b'D', b'E'])
        elif k < 59: out += b'\x1b]0;t%d\x07' % rnd.randrange(100)
        elif k < 61: out += rnd.choice([b'\x1b[?7l', b'\x1b[?7h', b'\x1b[4h', b'\x1b[4l', b'\x1b[?6h', b'\x1b[?6l', b'\x1b[?1049h', b'\x1b[?1049l'])
        else:
            f = rnd.choice(csis)
            if f == 'm':
                kinds = [b'0', b'1', b'3', b'4', b'7', b'22', b'31', b'44', b'92', b'39', b'49', b'38;5;%d' % rnd.randrange(256),
                         b'48;2;%d;%d;%d' % (rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)), b'']
                out += b'\x1b[' + rnd.choice(kinds) + b'm'
            elif f == 'r':
                out += (b'\x1b[%d;%dr' % (rnd.randrange(1, 4), rnd.randrange(4, 9))) if rnd.random() < 0.7 else b'\x1b[r'
            elif f in 'Hf': out += b'\x1b[%d;%dH' % (rnd.randrange(1, 10), rnd.randrange(1, 24))
            elif f == 'G': out += b'\x1b[%dG' % rnd.randrange(1, 24)
            elif f == 'n': out += b'\x1b[6n'
            elif f in 'su': out += b'\x1b[' + f.encode()
            else: out += b'\x1b[%d%s' % (rnd.randrange(1, 5), f.encode())
    out += b'[?1049l'  # end on the main screen so its content is part of the hash
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
    stream = gen_stream()
    m = Model()
    m.run(stream)
    h, lines = m.digest()
    block = ['// BEGIN GENERATED (scripts/gen_ui_terminal_test.py)',
             'fn model_stream() -> str { ret %s }' % literal(stream),
             'const MODEL_HASH: u64 = %du64' % h,
             'const MODEL_LINES: usize = %dusize' % lines,
             'const MODEL_CX: usize = %dusize' % m.cx,
             'const MODEL_CY: usize = %dusize' % m.cy,
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_terminal/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8')
    print('stream %d bytes, %d lines, sb %d, cursor %d,%d, out %r, title %r alt=%d' % (
        len(stream), lines, len(m.sb), m.cx, m.cy, m.out[:20], m.title, m.alt))


if __name__ == '__main__':
    main()
