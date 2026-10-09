"""Reference and fixture generator for e.text.edit (L021).

  python scripts/text_edit_reference.py

Python statements of Terraform's string functions as petcow defines them (src/interp.rs): substr by characters (a
negative length to the end), chomp, indent, trimprefix/trimsuffix, title (first character of each space-separated
word, simple one-to-one uppercase), strrev by code point, and the slash-pure basename/dirname. Python's own
str operations do the work, so nothing is shared with the Neper code. The cases are petcow's own assertions, hand
edges (empty, only slashes, invalid UTF-8, multi-byte characters) and seeded random strings over an alphabet of
ASCII, spaces, newlines, carriage returns, slashes, dots and non-ASCII letters. Every argument string is written
as hex of its UTF-8 bytes so that spaces, newlines and invalid bytes survive the text format. Writes
tests/selfhost/fixtures/link/text_edit/src/main.e.
"""
import pathlib
import random

ALPHABET = list('abcXYZ019 ') + ['\n', '\r', '/', '.', '-', 'é', 'ß', 'ǆ', 'ı', '日', '\U0001F600', '́', 'İ', ' ']


def simple_upper(ch):
    up = ch.upper()
    return up if len(up) == 1 else ch


def py_substr(s, off, length):
    if off < 0 or off > len(s):
        return None
    end = len(s) if length < 0 else min(off + length, len(s))
    return s[off:end]


def py_title(s):
    out = []
    start = True
    for ch in s:
        out.append(simple_upper(ch) if start else ch)
        start = ch == ' '
    return ''.join(out)


def py_basename(p):
    if p == b'':
        return b'.'
    t = p.rstrip(b'/')
    if t == b'':
        return b'/'
    return t.rsplit(b'/', 1)[-1]


def py_dirname(p):
    i = p.rfind(b'/')
    if i < 0:
        return b'.'
    if i == 0:
        return b'/'
    d = p[:i].rstrip(b'/')
    return d if d else b'/'


def hx(b):
    return b.hex() if b else '_'


def text(s):
    return hx(s.encode('utf-8'))


def utf8(b):
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return None


def make_line(kind, raw, *numbers, **kw):
    """raw: bytes argument. Returns the fixture line with the reference's result."""
    extra = kw.get('extra')
    if kind == 'S':
        s = utf8(raw)
        off, length = numbers
        if s is None:
            result = 'E:Invalid'
        else:
            r = py_substr(s, off, length)
            result = 'E:OffsetRange' if r is None else text(r)
        return 'S %s %d %d => %s' % (hx(raw), off, length, result)
    if kind == 'C':
        return 'C %s => %s' % (hx(raw), hx(raw.rstrip(b'\r\n')))
    if kind == 'I':
        (width,) = numbers
        result = 'E:Negative' if width < 0 else hx(raw.replace(b'\n', b'\n' + b' ' * width))
        return 'I %s %d => %s' % (hx(raw), width, result)
    if kind in 'XY':
        pre = extra
        if kind == 'X':
            r = raw[len(pre):] if raw.startswith(pre) else raw
        else:
            r = raw[:len(raw) - len(pre)] if pre and raw.endswith(pre) else raw
            if not pre:
                r = raw
        return '%s %s %s => %s' % (kind, hx(raw), hx(pre), hx(r))
    if kind == 'T':
        s = utf8(raw)
        return 'T %s => %s' % (hx(raw), 'E:Invalid' if s is None else text(py_title(s)))
    if kind == 'R':
        s = utf8(raw)
        return 'R %s => %s' % (hx(raw), 'E:Invalid' if s is None else text(s[::-1]))
    if kind == 'B':
        return 'B %s => %s' % (hx(raw), hx(py_basename(raw)))
    if kind == 'D':
        return 'D %s => %s' % (hx(raw), hx(py_dirname(raw)))
    raise ValueError(kind)


def main():
    rng = random.Random(2105)
    # petcow's assertions
    assert py_substr('hello world', 0, 5) == 'hello'
    assert py_basename(b'/var/log/app.log') == b'app.log' and py_basename(b'/var/log/') == b'log' and py_basename(b'/') == b'/'
    assert py_dirname(b'/var/log/app.log') == b'/var/log' and py_dirname(b'/foo') == b'/' and py_dirname(b'foo') == b'.' and py_dirname(b'/') == b'/'
    assert b'trimprefix' and b'v1.2.3'.removeprefix(b'v') == b'1.2.3'
    assert 'abc'[::-1] == 'cba' and 'line\n\n'.rstrip('\r\n') == 'line'
    assert 'a\n  b' == 'a\nb'.replace('\n', '\n  ')
    lines = []
    for p in ('/var/log/app.log', 'foo/bar/baz', '/var/log/', 'single', '/', '', '//', '///a//', 'a//b', '/a/', 'a/', '/a//b///', '.', '..', './x'):
        lines.append(make_line('B', p.encode()))
        lines.append(make_line('D', p.encode()))
    for s, off, length in (('hello world', 0, 5), ('hello world', 6, -1), ('hello world', 6, 100), ('hello world', 11, 3), ('hello world', 12, 1),
                           ('hello world', -1, 2), ('', 0, 0), ('', 0, -1), ('', 1, 0), ('héllo', 1, 3), ('日本語', 1, 1),
                           ('\U0001F600a', 1, 1), ('abc', 3, -1), ('abc', 0, 0), ('abc', 1, 9223372036854775807)):
        lines.append(make_line('S', s.encode(), off, length))
    for raw in (b'\xff', b'a\xc3', b'\xe6\x97', b'ok\xf0\x9f\x98'):
        lines.append(make_line('S', raw, 0, 1))
        lines.append(make_line('T', raw))
        lines.append(make_line('R', raw))
    for s in ('line\n\n', 'line\r\n', 'a\r\n\r\n', '\n', '', 'x', 'a\nb\n', '\r\n\r\n x'):
        lines.append(make_line('C', s.encode()))
    for s, width in (('a\nb', 2), ('a\nb\n', 3), ('abc', 4), ('', 2), ('\n', 0), ('a\n\nb', 1), ('a\nb', -1), ('x\ny', 0)):
        lines.append(make_line('I', s.encode(), width))
    for s, pre in (('v1.2.3', 'v'), ('v1.2.3', 'x'), ('abc', 'abc'), ('abc', 'abcd'), ('abc', ''), ('', ''), ('', 'a'), ('éa', 'é')):
        lines.append(make_line('X', s.encode(), extra=pre.encode()))
        lines.append(make_line('Y', s.encode(), extra=pre.encode()))
    for s in ('hello world', 'hello  world', ' x', 'x ', '', 'école ß ǆx ı', 'a-b c.d', 'ab\ncd ef', '日 本', '́e ́x'):
        lines.append(make_line('T', s.encode()))
        lines.append(make_line('R', s.encode()))
    for _ in range(500):
        n = rng.randint(0, 12)
        s = ''.join(rng.choice(ALPHABET) for _ in range(n))
        raw = s.encode()
        lines.append(make_line('S', raw, rng.randint(-1, n + 2), rng.choice([-1, 0, 1, 2, 5, rng.randint(0, n + 3)])))
        lines.append(make_line('C', raw))
        lines.append(make_line('I', raw, rng.randint(-1, 5)))
        pre = ''.join(rng.choice(ALPHABET) for _ in range(rng.randint(0, 3)))
        if rng.random() < 0.5 and s:
            pre = s[:rng.randint(0, len(s))]
        lines.append(make_line('X', raw, extra=pre.encode()))
        lines.append(make_line('Y', raw, extra=(s[-rng.randint(0, len(s)):] if (rng.random() < 0.5 and s) else pre).encode()))
        lines.append(make_line('T', raw))
        lines.append(make_line('R', raw))
        lines.append(make_line('B', raw))
        lines.append(make_line('D', raw))
    here = pathlib.Path(__file__).resolve().parent
    chunks = ['"' + '\\n'.join(lines[i:i + 80]) + '\\n"' for i in range(0, len(lines), 80)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    template = (here / 'text_edit_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'text_edit' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', len(lines), 'cases in', len(chunks), 'chunks')


main()
