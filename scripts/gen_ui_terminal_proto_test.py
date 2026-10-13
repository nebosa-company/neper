#!/usr/bin/env python3
"""Independent model of the e.ui.terminal protocol additions of D4500 (L136) for
tests/selfhost/fixtures/link/ui_terminal_proto: keypad application mode, modifyOtherKeys, the kitty keyboard
protocol (flag stack per screen, push / pop / set / query, the five progressive-enhancement flags), the 1005 and
1015 mouse encodings, and the selection edge cases of D4500 (a word over a wrap, the wide-character padding blank,
truncation inside a character).

The model is written from the protocol texts -- xterm's ctlseqs for DECKPAM, modifyOtherKeys and the mouse
encodings, kitty's keyboard-protocol page for the CSI-u encoding -- as lists of (key, mods, ...) -> bytes tables,
not from lib/e/ui/terminal.e. It is NOT a capture of a real xterm or kitty (neither is available on this host):
where the texts leave a choice, the choice is the engine's documented contract (see the comments above
`encode_kitty` and `encode_mouse`). Selection text reuses scripts/gen_ui_terminal_ext_test.py's model (updated for
the word and filler rules) over the regex-driven VT model of scripts/gen_ui_terminal_test.py.
Run from the repo root to rewrite the GENERATED block of the fixture's main.e.
"""
import pathlib, random, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_ui_terminal_ext_test as ext

RS, US = b'\x1e', b'\x1f'
KEYBASE = 2097153
KEYNAMES = ['UP', 'DOWN', 'RIGHT', 'LEFT', 'HOME', 'END', 'INSERT', 'DELETE', 'PAGE_UP', 'PAGE_DOWN', 'ENTER', 'TAB',
            'BACKSPACE', 'ESCAPE'] + ['F%d' % i for i in range(1, 13)]
K = {n: KEYBASE + i for i, n in enumerate(KEYNAMES)}
KP0 = 57399          # kitty code points: 0-9, decimal, divide, multiply, subtract, add, enter, equal, separator
SHIFT, ALT, CTRL, META, HYPER, CAPS, NUM = 1, 2, 4, 8, 16, 64, 128


# ---- state set-up: a list of operations -> the bytes fed to the engine, and the model's state ------------------
class State:
    def __init__(self):
        self.stack = [[], []]
        self.alt = 0
        self.mok = 0
        self.keypad = False
        self.app_cursor = False
        self.lnm = False

    @property
    def flags(self):
        s = self.stack[self.alt]
        return s[-1] if s else 0


def apply_ops(ops):
    st, seq = State(), b''
    for op in ops:
        k = op[0]
        if k == 'push':
            seq += b'\x1b[>%du' % op[1]
            s = st.stack[st.alt]
            if len(s) == 16: s.pop(0)
            s.append(op[1] & 31)
        elif k == 'pop':
            seq += b'\x1b[<%du' % op[1]
            s = st.stack[st.alt]
            del s[max(0, len(s) - max(op[1], 1)):]
        elif k == 'set':
            seq += b'\x1b[=%d;%du' % (op[1], op[2])
            s = st.stack[st.alt]
            if not s: s.append(0)
            if op[2] == 1: s[-1] = op[1] & 31
            elif op[2] == 2: s[-1] |= op[1] & 31
            elif op[2] == 3: s[-1] &= ~(op[1] & 31)
        elif k == 'alt':
            seq += b'\x1b[?1049h' if op[1] else b'\x1b[?1049l'
            if op[1] and not st.alt: st.stack[1] = []
            st.alt = op[1]
        elif k == 'mok':
            seq += b'\x1b[>4;%dm' % op[1]
            st.mok = op[1] if op[1] <= 2 else 0
        elif k == 'kp':
            seq += {'esc': b'\x1b=', 'off': b'\x1b>', 'dec': b'\x1b[?66h', 'decoff': b'\x1b[?66l'}[op[1]]
            st.keypad = op[1] in ('esc', 'dec')
        elif k == 'ck':
            seq += b'\x1b[?1h'
            st.app_cursor = True
        elif k == 'lnm':
            seq += b'\x1b[20h'
            st.lnm = True
        elif k == 'reset':
            seq += b'\x1bc'
            st = State()
        else:
            raise ValueError(op)
    return st, seq


# ---- keys -------------------------------------------------------------------------------------------------------
def legacy_base(key, mods, st):
    return ext.key_bytes(key, mods, 1 if st.app_cursor else 0, 1 if st.lnm else 0)


def keypad_char(idx):
    return [ord(c) for c in '0123456789./*-+'] [idx] if idx < 15 else None


def legacy(key, mods, st):
    if KP0 <= key <= KP0 + 17:
        idx = key - KP0
        if st.keypad:
            fin = 'pqrstuvwxy'[idx] if idx < 10 else {10: 'n', 11: 'o', 12: 'j', 13: 'm', 14: 'k', 15: 'M', 16: 'X', 17: 'l'}[idx]
            m = 1 + (mods & 15)
            return b'\x1bO' + (b'%d' % m if m != 1 else b'') + fin.encode()
        if idx == 15: return legacy(K['ENTER'], mods, st)
        ch = {16: ord('='), 17: ord(',')}.get(idx) or keypad_char(idx)
        return legacy(ch, mods, st)
    if 57344 <= key <= 57454: return b''
    if st.mok:
        c = None
        if key < 0x110000:
            ch = chr(key)
            has_c0 = ch.isascii() and (ch.isalpha() or ch in '@ 2[3\\4]5^6_/7?8')
            if st.mok >= 2: other = bool(mods & (ALT | CTRL | META))
            else: other = bool(mods & CTRL) and (not has_c0 or (bool(mods & SHIFT) and ch.isascii() and ch.isalpha()))
            c = key
        else:
            name = KEYNAMES[key - KEYBASE] if KEYBASE <= key < KEYBASE + len(KEYNAMES) else ''
            other = False
            if name in ('ENTER', 'TAB', 'BACKSPACE', 'ESCAPE'):
                if st.mok >= 2: other = bool(mods & 15)
                elif name == 'ENTER': other = bool(mods & (SHIFT | CTRL))
                elif name == 'TAB': other = bool(mods & CTRL)
                c = {'ENTER': 13, 'TAB': 9, 'BACKSPACE': 127, 'ESCAPE': 27}[name]
        if other: return b'\x1b[27;%d;%d~' % (1 + (mods & 15), c)
    return legacy_base(key, mods, st)


def csi_u(code, shifted, base, mods, event, text):
    s = b'\x1b[%d' % code
    if shifted or base:
        s += b':' + (b'%d' % shifted if shifted else b'')
        if base: s += b':%d' % base
    if mods or event != 1 or text:
        s += b';'
        if mods or event != 1:
            s += b'%d' % (1 + mods)
            if event != 1: s += b':%d' % event
        if text: s += b';%d' % text
    return s + b'u'


def kitty_functional(key, mods, event):
    name = KEYNAMES[key - KEYBASE]
    letters = {'UP': 'A', 'DOWN': 'B', 'RIGHT': 'C', 'LEFT': 'D', 'HOME': 'H', 'END': 'F', 'F1': 'P', 'F2': 'Q', 'F4': 'S'}
    tilde = {'INSERT': 2, 'DELETE': 3, 'PAGE_UP': 5, 'PAGE_DOWN': 6, 'F3': 13, 'F5': 15, 'F6': 17, 'F7': 18, 'F8': 19,
             'F9': 20, 'F10': 21, 'F11': 23, 'F12': 24}
    has = bool(mods) or event != 1
    tail = b';%d' % (1 + mods) + (b':%d' % event if event != 1 else b'') if has else b''
    if name in letters: return b'\x1b[' + (b'1' if has else b'') + tail + letters[name].encode()
    return b'\x1b[%d' % tilde[name] + tail + b'~'


def kitty(key, mods_in, event, shifted, base, text, flags, st):
    disamb, evt, alts, allk, txt = (bool(flags & b) for b in (1, 2, 4, 8, 16))
    if event not in (1, 2, 3): event = 1
    if event == 3 and not evt: return b''
    if event == 2 and not evt: event = 1
    mods = mods_in & 255
    plain = (mods & 31) == 0
    eff = mods & 30
    name = KEYNAMES[key - KEYBASE] if KEYBASE <= key < KEYBASE + len(KEYNAMES) else None
    if name == 'ESCAPE':
        if allk or disamb: return csi_u(27, 0, 0, mods, event, 0)
        return b'' if event == 3 else legacy(key, mods_in, st)
    if name in ('ENTER', 'TAB', 'BACKSPACE'):
        code = {'ENTER': 13, 'TAB': 9, 'BACKSPACE': 127}[name]
        if allk: return csi_u(code, 0, 0, mods, event, 0)
        if event == 3: return b''
        if disamb and not plain: return csi_u(code, 0, 0, mods, event, 0)
        return legacy(key, mods_in, st)
    if name is not None:
        if not allk and event == 1 and plain: return legacy(key, mods_in, st)
        return kitty_functional(key, mods, event)
    if KP0 <= key <= KP0 + 17:
        if not allk and eff == 0:
            return b'' if event == 3 else legacy(key, mods_in, st)
        idx = key - KP0
        t = 0
        if txt and allk and event != 3 and eff == 0:
            t = {14: ord('+'), 16: ord('='), 17: ord(',')}.get(idx) or (keypad_char(idx) if idx != 15 else 0) or 0
            if idx == 15: t = 0
        return csi_u(key, 0, 0, mods, event, t)
    if 57344 <= key <= 57454:
        return csi_u(key, 0, 0, mods, event, 0) if allk else b''
    if key >= 0x110000: return b''
    code, shf = key, shifted
    if 65 <= key <= 90:
        code = key + 32
        if not shf: shf = key
    sh = shf if alts and mods & SHIFT and shf and shf != code else 0
    bs = base if alts and base and base != code else 0
    if allk:
        t = 0
        if txt and event != 3 and eff == 0:
            t = text or (key if key >= 32 and key != 127 else 0)
        return csi_u(code, sh, bs, mods, event, t)
    if event == 3: return b''
    if disamb and eff: return csi_u(code, sh, bs, mods, event, 0)
    if text and eff == 0: return legacy(text, mods_in, st)
    return legacy(key, mods_in, st)


def key_bytes(st, key, mods, event, shifted, base, text):
    if st.flags: return kitty(key, mods, event, shifted, base, text, st.flags, st)
    if event == 3: return b''
    return legacy(key, mods, st)


# ---- mouse ------------------------------------------------------------------------------------------------------
def utf8_cp(v):
    return chr(v).encode('utf-8')


def mouse_bytes(mode, fmt, button, action, mods, x, y):
    if mode == 0 or button > 7 or action > 2: return b''
    wheel = button >= 4
    if wheel and action != 0: return b''
    if action == 2:
        if wheel or mode in (9, 1000): return b''
        if mode == 1002 and button == 3: return b''
    if mode == 9 and (action != 0 or wheel): return b''
    cb = 64 + (button - 4) if wheel else button
    if action == 1 and fmt != 1006: cb = 3
    if mode != 9:
        if mods & 1: cb += 4
        if mods & 10: cb += 8
        if mods & 4: cb += 16
    if action == 2: cb += 32
    if mode != 9 and fmt == 1006:
        return ('\x1b[<%d;%d;%d%s' % (cb, x + 1, y + 1, 'm' if action == 1 else 'M')).encode()
    if mode != 9 and fmt == 1015:
        return ('\x1b[%d;%d;%dM' % (cb + 32, x + 1, y + 1)).encode()
    if mode != 9 and fmt == 1005:
        if x > 2014 or y > 2014: return b''
        return b'\x1b[M' + utf8_cp(cb + 32) + utf8_cp(x + 33) + utf8_cp(y + 33)
    if x > 222 or y > 222: return b''
    return b'\x1b[M' + bytes([cb + 32, x + 33, y + 33])


def apply_mouse(modes):
    """modes: list of ('mode', n, on) / ('fmt', n, on) -> (sequence, mode, fmt); an off resets to the legacy form."""
    seq, mode, fmt = b'', 0, 0
    for k, n, on in modes:
        seq += b'\x1b[?%d%s' % (n, b'h' if on else b'l')
        if k == 'mode': mode = n if on else 0
        else: fmt = n if on else 0
    return seq, mode, fmt


# documented examples, which the model above must reproduce
_st = State()
assert key_bytes(_st, KP0 + 5, 0, 1, 0, 0, 0) == b'5'
_st.keypad = True
assert key_bytes(_st, KP0 + 5, 0, 1, 0, 0, 0) == b'\x1bOu' and key_bytes(_st, KP0 + 15, 0, 1, 0, 0, 0) == b'\x1bOM'
_st = State(); _st.mok = 2
assert key_bytes(_st, ord('a'), CTRL, 1, 0, 0, 0) == b'\x1b[27;5;97~'
assert key_bytes(_st, K['ENTER'], CTRL, 1, 0, 0, 0) == b'\x1b[27;5;13~'
_st = State(); _st.stack[0] = [1]
assert key_bytes(_st, K['ESCAPE'], 0, 1, 0, 0, 0) == b'\x1b[27u'
assert key_bytes(_st, ord('a'), CTRL, 1, 0, 0, 0) == b'\x1b[97;5u'
assert key_bytes(_st, ord('a'), 0, 1, 0, 0, 0) == b'a'
assert key_bytes(_st, K['F3'], 0, 1, 0, 0, 0) == b'\x1bOR' and key_bytes(_st, K['F3'], SHIFT, 1, 0, 0, 0) == b'\x1b[13;2~'
_st.stack[0] = [31]
assert key_bytes(_st, ord('a'), 0, 3, 0, 0, 0) == b'\x1b[97;1:3u'
assert key_bytes(_st, ord('a'), SHIFT, 1, 65, 0, 97) == b'\x1b[97:65;2;97u'
assert mouse_bytes(1000, 1015, 0, 0, 0, 9, 4) == b'\x1b[32;10;5M'
assert mouse_bytes(1000, 1005, 0, 0, 0, 200, 4) == b'\x1b[M \xc3\xa9%'


# ---- generation -------------------------------------------------------------------------------------------------
def build():
    rnd = random.Random(4500)
    cases = []

    def add(op, args, expected):
        cases.append(([op.encode()] + [a if isinstance(a, bytes) else str(a).encode() for a in args], expected))

    text_keys = [(97, 65, 0, 97), (65, 0, 0, 65), (49, 33, 0, 49), (233, 201, 0, 233), (1089, 1057, 99, 1089), (32, 0, 0, 32),
                 (0x4E16, 0, 0, 0x4E16), (91, 123, 0, 91), (47, 63, 0, 47), (122, 90, 0, 122)]
    func_keys = [KEYBASE + i for i in range(len(KEYNAMES))]
    kp_keys = [KP0 + i for i in range(18)]
    mod_keys = [57441, 57442, 57443, 57444, 57454, 57428]
    mod_sets = [0, 1, 2, 4, 5, 6, 3, 7, 8, 16, 64, 128, 65, 130, 12, 15]

    def kcase(ops, key, mods, event=1, shifted=0, base=0, text=0):
        st, seq = apply_ops(ops)
        add('K', [seq, key, mods, event, shifted, base, text], key_bytes(st, key, mods, event, shifted, base, text).hex().encode())

    # keypad: every key, every modifier set, both modes, both newline modes
    for key in kp_keys:
        for mods in (0, 1, 2, 4, 5, 8, 15):
            for ops in ([], [('kp', 'esc')], [('kp', 'dec')], [('kp', 'esc'), ('kp', 'off')], [('lnm',)], [('kp', 'dec'), ('kp', 'decoff')]):
                kcase(ops, key, mods)
    # modifyOtherKeys: levels 0-3, text keys and the four special keys
    for lvl in (0, 1, 2, 3):
        for key, _, _, _ in text_keys + [(ord('Q'), 0, 0, 0), (ord('h'), 0, 0, 0), (ord('5'), 0, 0, 0), (ord('?'), 0, 0, 0)]:
            for mods in (0, 1, 2, 4, 5, 6, 8, 7):
                kcase([('mok', lvl)], key, mods)
        for key in (K['ENTER'], K['TAB'], K['BACKSPACE'], K['ESCAPE'], K['UP'], K['F5']):
            for mods in (0, 1, 2, 4, 5, 8, 15):
                kcase([('mok', lvl)], key, mods)
    kcase([('mok', 2), ('mok', 0)], ord('a'), CTRL)
    kcase([('mok', 2), ('reset',)], ord('a'), CTRL)
    # kitty: stack operations observed through a probe key (ctrl+a is 0x01 or CSI 97;5u by the flags)
    probe = lambda ops: kcase(ops, ord('a'), CTRL)
    probe([('push', 1)])
    probe([('push', 1), ('push', 0)])
    probe([('push', 1), ('push', 0), ('pop', 1)])
    probe([('push', 1), ('pop', 5)])
    probe([('pop', 3)])
    probe([('set', 1, 1)])
    probe([('push', 8), ('set', 1, 2)])
    probe([('push', 9), ('set', 8, 3)])
    probe([('push', 9), ('set', 8, 3), ('set', 2, 2)])
    probe([('push', 1), ('alt', 1)])
    probe([('push', 1), ('alt', 1), ('push', 8), ('alt', 0)])
    probe([('push', 1), ('alt', 1), ('push', 8), ('alt', 0), ('alt', 1)])
    probe([('push', 1), ('reset',)])
    probe([('push', 33)])   # only the five defined bits are kept
    probe([('push', 1)] * 20 + [('push', 0), ('pop', 1)])
    probe([('push', 1)] + [('push', 2)] * 17 + [('pop', 16)])
    probe([('push', 1)] + [('push', 2)] * 17 + [('pop', 17)])
    # kitty: every flag set against every key class
    for flags in range(32):
        ops = [('push', flags)]
        for key, shifted, base, text in text_keys:
            for mods in rnd.sample(mod_sets, 5):
                event = rnd.choice((1, 1, 2, 3))
                kcase(ops, key, mods, event, shifted, base, text)
        for key in func_keys:
            for mods in rnd.sample(mod_sets, 2):
                kcase(ops, key, mods, rnd.choice((1, 2, 3)))
            kcase(ops, key, 0, 1)
        for key in kp_keys:
            kcase(ops + [('kp', 'esc')] if flags & 1 else ops, key, rnd.choice(mod_sets), rnd.choice((1, 2, 3)))
        for key in mod_keys:
            kcase(ops, key, rnd.choice((0, 1, 2, 4)), rnd.choice((1, 3)))
    # kitty with app-cursor and newline modes and modifyOtherKeys underneath
    for flags in (1, 3, 9, 31):
        for key in (K['UP'], K['HOME'], K['F1'], K['ENTER'], ord('a')):
            for mods in (0, 4):
                kcase([('ck',), ('lnm',), ('mok', 2), ('push', flags)], key, mods)
    # query replies: kitty flags, modifyOtherKeys, and a mix
    def qcase(ops, query):
        st, seq = apply_ops(ops)
        if query == 'kitty': exp = b'\x1b[?%du' % st.flags
        else: exp = b'\x1b[>4;%dm' % st.mok
        q = b'\x1b[?u' if query == 'kitty' else b'\x1b[?4m'
        add('Q', [seq + q], exp.hex().encode())
    for ops in ([], [('push', 5)], [('push', 5), ('push', 31), ('pop', 1)], [('push', 3), ('alt', 1), ('push', 8)],
                [('push', 3), ('alt', 1), ('push', 8), ('alt', 0)], [('set', 16, 2)], [('push', 7), ('set', 7, 3), ('reset',)]):
        qcase(ops, 'kitty')
    for ops in ([], [('mok', 1)], [('mok', 2)], [('mok', 3)], [('mok', 2), ('mok', 0)], [('mok', 2), ('reset',)]):
        qcase(ops, 'mok')
    # a CSI ? u must not restore the cursor, and CSI ? 4 m must not underline
    add('Q', [b'ab\x1b[s\x1b[3Ccd\x1b[?u\x1b[6n'], (b'\x1b[?0u' + b'\x1b[1;8R').hex().encode())
    # mouse: 1005 / 1015 against every mode, with set / reset sequences
    fmts = [[], [('fmt', 1006, 1)], [('fmt', 1015, 1)], [('fmt', 1005, 1)], [('fmt', 1006, 1), ('fmt', 1015, 1)],
            [('fmt', 1015, 1), ('fmt', 1005, 1)], [('fmt', 1005, 1), ('fmt', 1005, 0)], [('fmt', 1006, 1), ('fmt', 1015, 0)]]
    for mode in (0, 9, 1000, 1002, 1003):
        for fm in fmts:
            for button in range(8):
                for action in range(3):
                    if rnd.random() < 0.55: continue
                    mods = rnd.choice([0, 0, 1, 4, 6, 12])
                    x, y = rnd.choice([(0, 0), (10, 5), (79, 23), (222, 222), (223, 4), (4, 300), (500, 3), (2014, 2014), (2015, 3), (127, 94), (95, 96)])
                    seq, m, f = apply_mouse(([('mode', mode, 1)] if mode else []) + fm)
                    add('M', [seq, button, action, mods, x, y], mouse_bytes(m, f, button, action, mods, x, y).hex().encode())
    # selection edge cases (model: scripts/gen_ui_terminal_ext_test.py)
    sel = []
    wide = '世界'.encode()
    streams = [
        (b'aaaaaaaaaaXXXXXX bbb', 10, 4), (b'abcdefghi!jklmn', 10, 4), (b'abcd' + wide + b'ef', 5, 4),
        (b'abcd' + wide + wide + b'x', 5, 5), (b'ab' + wide + wide + wide, 6, 4), (b'abc ' + wide + b' d', 5, 4),
        (b'\x1b[31mred word\x1b[0m split over rows', 8, 5), (b'one two\r\nthree four five six', 9, 5),
        (b'xxxxxxxxx' + wide + b'yyyyyyyy', 10, 4), (b'a' * 25, 10, 4), (b'a' * 10 + b' ' + b'b' * 10, 10, 4),
    ]
    for stream, cols, rows in streams:
        m = ext.run_model(stream, cols, rows, 8)
        n = len(m.sb) + rows
        for mode in (1, 2, 3, 4):
            for _ in range(5):
                al, hl = rnd.randrange(n), rnd.randrange(n)
                ac, hc = rnd.randrange(cols), rnd.randrange(cols)
                sel.append((stream, cols, rows, 8, mode, al, ac, hl, hc))
    for stream, cols, rows, sbc, mode, al, ac, hl, hc in sel:
        add('S', [stream, cols, rows, sbc, mode, al, ac, hl, hc, 0], ext.select_text(stream, cols, rows, sbc, mode, al, ac, hl, hc))
    # truncation: the engine stops before a character that does not fit and never splits one
    for stream, cols, rows in ((b'abc ' + wide + b' d\r\nxyz', 5, 4), (b'\xc3\xa9t\xc3\xa9 ' + wide + b'\r\nzz', 8, 4)):
        for cap in range(1, 14):
            full = ext.select_text(stream, cols, rows, 8, 3, 0, 0, rows - 1, 0)
            s = full.decode('utf-8')
            out, used = '', 0
            for ch in s:
                if used + len(ch.encode()) > cap: break
                out += ch
                used += len(ch.encode())
            add('S', [stream, cols, rows, 8, 3, 0, 0, rows - 1, 0, cap], out.encode())
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
    block = ['// BEGIN GENERATED (scripts/gen_ui_terminal_proto_test.py)',
             'fn script() -> str { ret %s }' % literal(script),
             'fn expected() -> str { ret %s }' % literal(expected),
             'const CASES: usize = %dusize' % len(cases),
             '// END GENERATED']
    path = pathlib.Path('tests/selfhost/fixtures/link/ui_terminal_proto/src/main.e')
    src = path.read_text(encoding='utf-8')
    a = src.index('// BEGIN GENERATED'); b = src.index('// END GENERATED') + len('// END GENERATED')
    path.write_text(src[:a] + '\n'.join(block) + src[b:], encoding='utf-8', newline='\n')
    kinds = {}
    for f, _ in cases: kinds[f[0].decode()] = kinds.get(f[0].decode(), 0) + 1
    print('%d cases, script %d bytes, expected %d bytes' % (len(cases), len(script), len(expected)), kinds)


if __name__ == '__main__':
    main()
