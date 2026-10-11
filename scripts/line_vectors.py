"""Independent model for e.cli.line (L133): a readline-semantics editor over Python
`str` (code points, not bytes) with its own key decoder, driven by random key
sessions. For every session it produces what the editor must answer: the lines
submitted (Enter), the markers for Ctrl-C / Ctrl-L / Ctrl-D, the final text, the
cursor in code points, the kill buffer and the redraw bytes with the history hint.

Capacities mirror the fixture: line 96 bytes, kill buffer 96 bytes, history of at most
6 entries and 120 bytes (the oldest evicted first), 8 completion candidates.

Line: `hex(session bytes)~hex(history seed lines, comma separated hex)~outputs~
final hex~cursor~kill hex~render hex` with outputs a comma list of hex lines, or
`c`, `l`, `d` for Ctrl-C, Ctrl-L, Ctrl-D.
"""
import random
import re
import sys

LINE_CAP = 96
HIST_COUNT = 6
HIST_BYTES = 120
CANDS = 8
WORDS = ['help', 'hello', 'helmet', 'history', 'exit', 'export', 'quit', 'ls', 'list', 'listen', 'cat', 'cd']


def blen(s):
    return len(s.encode('utf-8'))


def isword(c):
    return c.isalnum() or c == '_' or ord(c) >= 128


def isspace(c):
    return c in ' \t\n'


def decode(data):
    """Bytes into keys: (kind, ch, ctrl, alt)."""
    keys = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b == 0x1b:
            m = re.compile(rb'\x1b[\[O]([0-9;]*)([A-Za-z~])').match(data, i)
            if m:
                params = m.group(1).split(b';')
                p0 = int(params[0]) if params[0] else 0
                p1 = int(params[1]) if len(params) > 1 and params[1] else 0
                f = m.group(2).decode()
                kind = {'A': 'up', 'B': 'down', 'C': 'right', 'D': 'left', 'H': 'home', 'F': 'end'}.get(f, 'unknown')
                if f == '~':
                    kind = {1: 'home', 7: 'home', 4: 'end', 8: 'end', 3: 'delete'}.get(p0, 'unknown')
                ctrl = alt = False
                if p1 >= 2:
                    bits = p1 - 1
                    alt = bool(bits & 2)
                    ctrl = bool(bits & 4)
                keys.append((kind, 0, ctrl, alt))
                i = m.end()
                continue
            if i + 1 >= n:
                keys.append(('escape', 0, False, False))
                i += 1
                continue
            nxt = data[i + 1]
            if nxt in (0x7f, 0x08):
                keys.append(('backspace', 0, False, True))
                i += 2
                continue
            # Alt + plain character (ASCII in these sessions).
            if nxt < 0x80 and nxt >= 0x20:
                keys.append(('char', nxt, False, True))
                i += 2
                continue
            keys.append(('unknown', 0, False, False))
            i += 2
            continue
        if b in (13, 10):
            keys.append(('enter', 0, False, False))
        elif b == 9:
            keys.append(('tab', 0, False, False))
        elif b == 127:
            keys.append(('backspace', 0, False, False))
        elif 1 <= b <= 26:
            keys.append(('char', b + 96, True, False))
        elif b < 128:
            keys.append(('char', b, False, False))
        else:
            length = 4 if b >= 240 else 3 if b >= 224 else 2
            keys.append(('char', ord(data[i:i + length].decode('utf-8')), False, False))
            i += length
            continue
        i += 1
    return keys


class Editor:
    def __init__(self, history):
        self.buf = []
        self.cur = 0
        self.kill = ''
        self.last_kill = False
        self.hist = []
        for h in history:
            self.add_history(h)
        self.pos = len(self.hist)
        self.draft = ''
        self.cycling = False
        self.cands = []
        self.cand_i = 0
        self.cand_start = 0
        self.cand_len = 0

    def s(self):
        return ''.join(self.buf)

    def bytes_used(self):
        return blen(self.s())

    def add_history(self, line):
        if not line or blen(line) > HIST_BYTES:
            return
        if self.hist and self.hist[-1] == line:
            return
        while len(self.hist) >= HIST_COUNT or sum(blen(h) for h in self.hist) + blen(line) > HIST_BYTES:
            self.hist.pop(0)
        self.hist.append(line)
        self.pos = len(self.hist)

    def insert(self, at, text):
        if self.bytes_used() + blen(text) > LINE_CAP:
            return False
        self.buf[at:at] = list(text)
        if self.cur >= at:
            self.cur += len(text)
        return True

    def delete(self, start, end):
        if end <= start:
            return
        n = end - start
        del self.buf[start:end]
        if self.cur > end:
            self.cur -= n
        elif self.cur > start:
            self.cur = start

    def set_text(self, text):
        if blen(text) > LINE_CAP:
            return False
        self.buf = list(text)
        self.cur = len(self.buf)
        return True

    def word_start(self, i):
        while i > 0 and not isword(self.buf[i - 1]):
            i -= 1
        while i > 0 and isword(self.buf[i - 1]):
            i -= 1
        return i

    def word_end(self, i):
        while i < len(self.buf) and not isword(self.buf[i]):
            i += 1
        while i < len(self.buf) and isword(self.buf[i]):
            i += 1
        return i

    def do_kill(self, start, end, forward, was_kill):
        self.last_kill = True
        if end <= start:
            return
        piece = ''.join(self.buf[start:end])
        if was_kill:
            if blen(self.kill) + blen(piece) > LINE_CAP:
                return
            self.kill = self.kill + piece if forward else piece + self.kill
        else:
            if blen(piece) > LINE_CAP:
                return
            self.kill = piece
        self.delete(start, end)

    def hist_prev(self):
        if not self.hist or self.pos == 0:
            return False
        if self.pos == len(self.hist):
            self.draft = self.s()
        self.pos -= 1
        return self.set_text(self.hist[self.pos])

    def hist_next(self):
        if self.pos >= len(self.hist):
            return False
        self.pos += 1
        if self.pos == len(self.hist):
            return self.set_text(self.draft)
        return self.set_text(self.hist[self.pos])

    def hint(self):
        text = self.s()
        if not text:
            return ''
        for entry in reversed(self.hist):
            if len(entry) > len(text) and entry.startswith(text) and blen(entry) > blen(text):
                return entry[len(text):]
        return ''

    def tab(self):
        if self.cycling and self.cands:
            self.cand_i = (self.cand_i + 1) % len(self.cands)
            c = self.cands[self.cand_i]
            self.replace(self.cand_start, self.cand_start + self.cand_len, c)
            self.cand_len = len(c)
            return
        start = self.cur
        while start > 0 and not isspace(self.buf[start - 1]):
            start -= 1
        word = ''.join(self.buf[start:self.cur])
        cands = [w for w in WORDS if w.startswith(word)][:CANDS]
        if not cands:
            return
        common = cands[0]
        for c in cands[1:]:
            k = 0
            while k < len(common) and k < len(c) and common[k] == c[k]:
                k += 1
            common = common[:k]
        self.cand_start = start
        self.cands = cands
        if len(common) > len(word):
            if self.replace(start, self.cur, common) and len(cands) > 1:
                self.cycling = True
                self.cand_i = len(cands) - 1
                self.cand_len = len(common)
            return
        if len(cands) == 1 and len(cands[0]) == len(word):
            return
        self.cycling = True
        self.cand_i = 0
        if self.replace(start, self.cur, cands[0]):
            self.cand_len = len(cands[0])

    def replace(self, start, end, text):
        if self.bytes_used() - blen(''.join(self.buf[start:end])) + blen(text) > LINE_CAP:
            return False
        self.delete(start, end)
        self.cur = start
        return self.insert(start, text)

    def key(self, k):
        """Apply a key; returns None or one of 'accept', 'interrupt', 'eof', 'clear'."""
        kind, ch, ctrl, alt = k
        was_kill = self.last_kill
        self.last_kill = False
        if kind != 'tab':
            self.cycling = False
        if kind == 'tab':
            self.tab()
            return None
        if kind == 'enter':
            return 'accept'
        n = len(self.buf)
        if kind == 'left':
            self.cur = self.word_start(self.cur) if (ctrl or alt) else max(0, self.cur - 1)
        elif kind == 'right':
            self.cur = self.word_end(self.cur) if (ctrl or alt) else min(n, self.cur + 1)
        elif kind == 'home':
            self.cur = 0
        elif kind == 'end':
            self.cur = n
        elif kind == 'up':
            self.hist_prev()
        elif kind == 'down':
            self.hist_next()
        elif kind == 'backspace':
            if alt:
                self.do_kill(self.word_start(self.cur), self.cur, False, was_kill)
            elif self.cur > 0:
                self.delete(self.cur - 1, self.cur)
        elif kind == 'delete':
            if self.cur < n:
                self.delete(self.cur, self.cur + 1)
        elif kind == 'char' and ctrl:
            c = chr(ch)
            if c == 'a':
                self.cur = 0
            elif c == 'e':
                self.cur = n
            elif c == 'b':
                self.cur = max(0, self.cur - 1)
            elif c == 'f':
                self.cur = min(n, self.cur + 1)
            elif c == 'd':
                if n == 0:
                    return 'eof'
                if self.cur < n:
                    self.delete(self.cur, self.cur + 1)
            elif c == 'h':
                if self.cur > 0:
                    self.delete(self.cur - 1, self.cur)
            elif c == 'k':
                self.do_kill(self.cur, n, True, was_kill)
            elif c == 'u':
                self.do_kill(0, self.cur, False, was_kill)
            elif c == 'w':
                s = self.cur
                while s > 0 and isspace(self.buf[s - 1]):
                    s -= 1
                while s > 0 and not isspace(self.buf[s - 1]):
                    s -= 1
                self.do_kill(s, self.cur, False, was_kill)
            elif c == 'y':
                if self.kill:
                    self.insert(self.cur, self.kill)
            elif c == 't':
                if n >= 2 and self.cur > 0:
                    if self.cur == n:
                        self.buf[n - 2], self.buf[n - 1] = self.buf[n - 1], self.buf[n - 2]
                    else:
                        self.buf[self.cur - 1], self.buf[self.cur] = self.buf[self.cur], self.buf[self.cur - 1]
                        self.cur += 1
            elif c == 'p':
                self.hist_prev()
            elif c == 'n':
                self.hist_next()
            elif c == 'c':
                return 'interrupt'
            elif c == 'l':
                return 'clear'
        elif kind == 'char' and alt:
            c = chr(ch)
            if c == 'b':
                self.cur = self.word_start(self.cur)
            elif c == 'f':
                self.cur = self.word_end(self.cur)
            elif c == 'd':
                self.do_kill(self.cur, self.word_end(self.cur), True, was_kill)
        elif kind == 'char':
            self.insert(self.cur, chr(ch))
        return None

    def render(self, prompt='> '):
        hint = self.hint()
        out = '\r' + prompt + self.s()
        if hint:
            out += '\x1b[2m' + hint + '\x1b[0m'
        out += '\x1b[K\r'
        cols = len(prompt) + self.cur
        if cols > 0:
            out += '\x1b[%dC' % cols
        return out


def run_session(data, history):
    e = Editor(history)
    outputs = []
    for k in decode(data):
        r = e.key(k)
        if r == 'accept':
            line = e.s()
            e.add_history(line)
            e.buf = []
            e.cur = 0
            e.pos = len(e.hist)
            e.cycling = False
            outputs.append(line.encode().hex())
        elif r == 'interrupt':
            e.buf = []
            e.cur = 0
            e.pos = len(e.hist)
            e.cycling = False
            outputs.append('c')
        elif r == 'clear':
            outputs.append('l')
        elif r == 'eof':
            outputs.append('d')
            break
    return outputs, e


SPECIAL = [b'\x01', b'\x02', b'\x04', b'\x05', b'\x06', b'\x0b', b'\x15', b'\x17', b'\x19', b'\x14',
           b'\x10', b'\x0e', b'\x08', b'\x7f', b'\x1b[A', b'\x1b[B', b'\x1b[C', b'\x1b[D', b'\x1b[H', b'\x1b[F',
           b'\x1b[3~', b'\x1b[1;5C', b'\x1b[1;5D', b'\x1b[1;3C', b'\x1bb', b'\x1bf', b'\x1bd', b'\x1b\x7f',
           b'\x1bOH', b'\x1bOF', b'\t', b'\t', b'\r', b'\x03', b'\x0c', b'\x1b[7~', b'\x1b[8~']
TEXT = ['h', 'e', 'l', 'p', ' ', 'x', 'y', 'ls', 'hel', 'lis', 'cat', 'a_b', 'café', '日本', '\U0001F600', 'ex']


def make_session(rng):
    parts = []
    for _ in range(rng.randint(3, 40)):
        if rng.random() < 0.55:
            parts.append(rng.choice(TEXT).encode('utf-8'))
        else:
            parts.append(rng.choice(SPECIAL))
    return b''.join(parts)


def emit_lines():
    rng = random.Random(133)
    seeds = [[], ['ls -la', 'cat notes', 'help me'], ['exit', 'history', 'hello world', 'x', 'listen up', 'ls', 'cd /tmp']]
    lines = []
    for n in range(120):
        history = rng.choice(seeds)
        data = make_session(rng)
        outputs, e = run_session(data, history)
        lines.append('~'.join([
            data.hex(), ','.join(h.encode().hex() for h in history), ','.join(outputs),
            e.s().encode().hex(), str(e.cur), e.kill.encode().hex(), e.render().encode().hex()]))
    return lines


def selfcheck():
    # Documented readline behaviours, from the manual's command list.
    def run(keys, history=()):
        e = Editor(list(history))
        for k in decode(keys):
            e.key(k)
        return e
    e = run(b'hello world\x17')
    assert e.s() == 'hello ' and e.kill == 'world'
    e = run(b'ab\x14')
    assert e.s() == 'ba' and e.cur == 2
    e = run(b'abc\x02\x14')
    assert e.s() == 'acb' and e.cur == 3
    e = run(b'one two\x0b\x1bb\x0b\x19')
    assert e.s() == 'one two', e.s()
    e = run(b'ab cd\x01\x1bd\x1bd')
    assert e.s() == '' and e.kill == 'ab cd'
    e = run(b'abc\x1b[A', ['old'])
    assert e.s() == 'old'
    e = run(b'abc\x1b[A\x1b[B', ['old'])
    assert e.s() == 'abc'


if __name__ == '__main__':
    selfcheck()
    lines = emit_lines()
    if '--emit' in sys.argv:
        print('\n'.join(lines))
    else:
        print('line_vectors: %d sessions' % len(lines))
