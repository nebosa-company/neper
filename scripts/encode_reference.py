"""Reference and fixture generator for e.fmt.encode (L023).

  python scripts/encode_reference.py

States each function's contract with Python's base64, urllib.parse, json and csv modules: base64 of the text, the
decoded bytes of base64 required to be UTF-8 (fail closed), only the UTF-8 charset names accepted, RFC 3986
percent-encoding, a JSON round trip to compact text, and a CSV with a header row as a list of string-valued
objects (a ragged row is an error). Writes tests/selfhost/fixtures/link/fmt_encode/src/main.e from
scripts/encode_fixture_template.e. Text arguments are hex of their bytes (`_` for empty).
"""
import base64
import csv
import io
import json
import pathlib
import random
import re
import urllib.parse


def hx(b):
    return b.hex() if b else '_'


def line(kind, args, result):
    return '%s %s => %s' % (kind, ' '.join(args), result)


def L_b64enc(raw):
    return line('B', [hx(raw)], hx(base64.b64encode(raw)))


ALPHA = re.compile(r'[A-Za-z0-9+/]*')


def L_b64dec(src):
    t = src.rstrip(b'=')
    result = None
    if not ALPHA.fullmatch(t.decode('latin-1')) or len(t) % 4 == 1:
        result = 'E:BadBase64'
    else:
        decoded = base64.b64decode(t + b'=' * (-len(t) % 4))
        try:
            decoded.decode('utf-8')
            result = hx(decoded)
        except UnicodeDecodeError:
            result = 'E:NotUtf8'
    return line('b', [hx(src)], result)


def is_utf8_name(name):
    return name.strip(' \t\n\r\x0b\x0c').upper() in ('UTF-8', 'UTF8')


def L_text_enc(raw, charset):
    if not is_utf8_name(charset):
        return line('T', [hx(raw), hx(charset.encode())], 'E:UnsupportedEncoding')
    return line('T', [hx(raw), hx(charset.encode())], hx(base64.b64encode(raw)))


def L_text_dec(src, charset):
    if not is_utf8_name(charset):
        return line('t', [hx(src), hx(charset.encode())], 'E:UnsupportedEncoding')
    out = L_b64dec(src).split(' => ')[1]
    return line('t', [hx(src), hx(charset.encode())], out)


def L_url(raw):
    return line('U', [hx(raw)], urllib.parse.quote_from_bytes(raw, safe='') or '')


def L_json(text):
    try:
        value = json.loads(text.decode('utf-8'))
        result = json.dumps(value, separators=(',', ':'), ensure_ascii=False)
    except (ValueError, UnicodeDecodeError):
        result = 'E:Invalid'
    return line('J', [hx(text)], result)


def L_csv(text):
    rows = list(csv.reader(io.StringIO(text.decode('utf-8'), newline='')))
    if not rows:
        return line('C', [hx(text)], '[]')
    header = rows[0]
    out = []
    for r in rows[1:]:
        if len(r) != len(header):
            return line('C', [hx(text)], 'E:Ragged')
        out.append(dict(zip(header, r)))
    return line('C', [hx(text)], json.dumps(out, separators=(',', ':'), ensure_ascii=False))


def random_json(rng, depth=0):
    r = rng.random()
    if depth > 2 or r < 0.35:
        return rng.choice([0, 1, -7, 42, 1.5, -0.25, True, False, None, 'a', '', 'x y', 'é', '日本', 'q"uote', 'back\\slash', 'tab\t', 'nl\n', '\x01', '/'])
    if r < 0.65:
        return [random_json(rng, depth + 1) for _ in range(rng.randint(0, 4))]
    return {rng.choice('abcde') + str(i): random_json(rng, depth + 1) for i in range(rng.randint(0, 4))}


def main():
    rng = random.Random(2305)
    lines = []
    # petcow's assertions
    assert base64.b64encode(b'hello') == b'aGVsbG8='
    for raw in (b'', b'f', b'fo', b'foo', b'foob', b'fooba', b'foobar', 'héllo wörld'.encode(), '日本語'.encode(), b'\x00', bytes(range(32, 127))):
        lines.append(L_b64enc(raw))
        lines.append(L_b64dec(base64.b64encode(raw)))
        lines.append(L_b64dec(base64.b64encode(raw).rstrip(b'=')))
        lines.append(L_text_enc(raw, 'UTF-8'))
        lines.append(L_text_dec(base64.b64encode(raw), 'utf8'))
    for src in (b'Zm9v', b'Zm9v\n', b'Zm9v YmFy', b'Z', b'Zg=', b'Zg==', b'Zg===', b'Zg=x', b'Z=g=', b'////', b'++++', b'-_-_', b'Zm9', b'gA==', b'/w==', b'/+8=', b'4pyT', b'4py', b'w6k=', b'wA==', b'7e5=', b'', b'=', b'==', b'!!!!'):
        lines.append(L_b64dec(src))
    for charset in ('UTF-8', 'utf-8', 'UTF8', 'utf8', ' UTF-8 ', '\tutf8\n', 'UTF-16', 'latin1', 'ISO-8859-1', '', 'UTF_8', 'utf-88', 'UTF', 'ASCII', 'Utf-8'):
        lines.append(L_text_enc(b'abc', charset))
        lines.append(L_text_dec(b'YWJj', charset))
        lines.append(L_text_dec(b'/w==', charset))
    for raw in (b'', b'abc', b'hello world', b'a/b?c=d&e', b'~-_.', b'\x00\xff', 'é日'.encode(), b'%', b' ', b'+', b'ABCxyz019', bytes(range(256))):
        lines.append(L_url(raw))
    for text in (b'{"a":1,"b":[1,2,{"c":null}]}', b' [ 1 , 2 ,\n 3 ] ', b'"x"', b'123', b'true', b'null', b'{}', b'[]', b'{"k":"v"}'):
        lines.append(L_json(text))
    for text in (b'{', b'[1,]', b"{'a':1}", b'', b'nul', b'[1 2]', b'{"a"}', b'"unterminated', b'\xff\xfe'):
        lines.append(L_json(text))
    # petcow's csv assertions and edges
    for text in ('name,port\nweb,80\ndb,5432', 'a,b\n"x,y",z', 'a,b\n1', '', 'a,b', 'a,b\n', 'a,b\r\n1,2\r\n3,4\r\n', 'a\n"line1\nline2"\n', 'a,b\n"q""uote",\n,\n',
                 'a,b\n"x",\n', 'h\n日本\né', 'a,b\n1,2,3'):
        lines.append(L_csv(text.encode()))
    for _ in range(250):
        v = random_json(rng)
        compact = json.dumps(v, separators=(',', ':'), ensure_ascii=False)
        spaced = json.dumps(v, indent=rng.choice([None, 1, 2]), separators=rng.choice([(',', ':'), (', ', ': ')]), ensure_ascii=rng.random() < 0.3)
        lines.append(L_json(spaced.encode()))
        raw = bytes(rng.getrandbits(8) for _ in range(rng.randint(0, 24))) if rng.random() < 0.4 else ''.join(rng.choice('abc XYZ019+/=é日\n') for _ in range(rng.randint(0, 20))).encode()
        lines.append(L_b64enc(raw))
        lines.append(L_b64dec(base64.b64encode(raw)))
        lines.append(L_url(raw))
        mangled = bytearray(base64.b64encode(raw))
        if mangled and rng.random() < 0.5:
            mangled[rng.randrange(len(mangled))] = rng.choice(b'!= \n-_*%')
        if mangled and rng.random() < 0.3:
            del mangled[rng.randrange(len(mangled))]
        lines.append(L_b64dec(bytes(mangled)))
        width = rng.randint(1, 4)
        header = ['c%d' % i for i in range(width)]
        rows = [header]
        for _ in range(rng.randint(0, 4)):
            rows.append([rng.choice(['', 'a', 'b c', 'x,y', 'q"q', 'l1\nl2', 'é', '日本', ' sp ']) for _ in range(width if rng.random() < 0.9 else width + rng.choice([-1, 1]))])
        if rng.random() < 0.15:
            rows = []
        buf = io.StringIO(newline='')
        w = csv.writer(buf, lineterminator=rng.choice(['\n', '\r\n']))
        for r in rows:
            if len(r) == 0:
                continue
            w.writerow(r)
        text = buf.getvalue()
        if rows and rng.random() < 0.3:
            text = text.rstrip('\r\n')
        lines.append(L_csv(text.encode()))
    here = pathlib.Path(__file__).resolve().parent
    chunks = ['"' + '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"') for l in lines[i:i + 60]) + '\\n"' for i in range(0, len(lines), 60)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    template = (here / 'encode_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_encode' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', len(lines), 'cases in', len(chunks), 'chunks')


main()
