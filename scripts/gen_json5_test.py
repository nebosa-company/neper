"""Generate tests/selfhost/fixtures/link/fmt_json5/src/main.e (L152, D2802).

Reference: the `json5` package (`json5.loads`): its verdict (accept / reject) and its value,
rendered with `json.dumps`, which the fixture parses with the strict JSON parser and compares
with `json.values_equal`. Documents are a hand list of JSON5 features and refusals plus
random trees rendered with random decoration (comments, trailing commas, quote and key
styles, hex and signed numbers, exotic whitespace). A final block round-trips values
through `json5.write` -> `json5.parse`.

    PYTHONPATH=<json5 install dir> python scripts/gen_json5_test.py
"""
import json
import random
import sys
from pathlib import Path

import json5 as ref

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(152)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_json5' / 'src' / 'main.e'


def hx(s):
    return s.encode('utf-8').hex() or '-'


lines = []


def add(text):
    try:
        obj = ref.loads(text)
    except Exception:
        lines.append('E %s' % hx(text))
        return 'E'
    try:
        expected = json.dumps(obj, ensure_ascii=True, allow_nan=False)
    except ValueError:
        lines.append('F %s' % hx(text))
        return 'F'
    lines.append('V %s %s' % (hx(text), hx(expected)))
    return 'V'


hand = [
    '{"a":1}', "{a:1}", "{'a':'b'}", '{a:1,}', '[1,2,]', '[,]', '[1,,2]', '{,}', '{a:}', '{:1}', '{a}',
    '// c\n[1]', '/* c */ [/* x */1/* y */]', '/* open', '[1] // tail', "'\\x41\\u0042\\n'", "'it\\'s'", '"say \\"hi\\""',
    "'a\\\nb'", '"a\\\r\nb"', '"\\v\\0"', '"\\0"', '"\\01"', "'\\a\\q'", '"tab\there"', '"line\nbreak"', "'x y'",
    '0xFF', '-0xff', '+0x10', '0X1f', '0x', '0xG', '0x1FFFFFFFFFFFFFFFF', '.5', '5.', '-.5', '+.5e1', '5.e2', '1e5', '1E+5', '1e-5',
    '+1', '-1', '+', '-', '.', '0', '-0', '00', '01', '1.2.3', '1e', '1ee1', '0.5', 'Infinity', '-Infinity', '+Infinity', 'NaN', '-NaN',
    '[Infinity]', 'null', 'true', 'false', 'nul', 'True', '', '   ', '1 2', '[1] 2', '{a:1}{b:2}', '[', ']', '{', '}', '[1}', '{a:1]',
    '{a:1 b:2}', '{a b:1}', '{1:2}', '{"a" 1}', '{$a:1,_b:2,c3:3}', '{\\u0061b:1}', '{a\\u0062:1}', '{\\u0031:1}',
    '{null:1,true:2,if:3}', '{ä:1}', '{"ä":1}', '{a:{b:{c:[1,[2,[3]]]}}}', ' [ 1 ] ', '﻿{"a":1}', '[ 1 ]',
    '[1　2]', '"\\ud83d\\ude00"', "'é€'", '"\\u00e9"', '"\\u00"', '"\\x4"', '"\\xG1"', '"\\', '"abc', "'abc", '["a" "b"]',
    '{a:1,b:[1,2,{c:3,},],}', '[[],{}]', '[[[[[[[[[[1]]]]]]]]]]', '1.7976931348623157e308', '123456789012345678901234567890',
    '[0.1,0.2,0.30000000000000004]', '-0.0', '0e0', '"\\/"', '"\\"', "'\\''", '"\u0000"', '[1,2,3,]//x',
]
for t in hand:
    add(t)

# Random trees rendered with decoration.
def rand_str():
    pool = ['a', 'b', 'xyz', '', 'hello world', 'quote"d', "it's", 'back\\slash', 'tab\t', 'nl\n', 'é', '€', '😀', ' ', '/', 'null', '123']
    return random.choice(pool) + random.choice(['', 'z', 'é'])


def rand_value(depth=0):
    r = random.random()
    if depth > 3 or r < 0.5:
        return random.choice([None, True, False, 0, 1, -7, 255, 65536, 3.5, -0.25, 1e3, rand_str(), rand_str()])
    if r < 0.75:
        return [rand_value(depth + 1) for _ in range(random.randint(0, 4))]
    return {random.choice(['a', 'b', 'key', 'k_1', '$x', 'two words', 'ä', 'if', '1st', 'a-b', 'x']): rand_value(depth + 1) for _ in range(random.randint(0, 4))}


def ws():
    return random.choice(['', '', ' ', '\n', '\t', ' /* c */ ', ' ', ' // x\n', ' ', '\r\n'])


def render_str(s):
    q = random.choice(['"', "'"])
    out = [q]
    for ch in s:
        if ch == q or ch == '\\':
            out.append('\\' + ch)
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append(random.choice(['\\t', '\t']))
        elif ch == ' ':
            out.append(random.choice(['\\u2028', ' ']))
        elif ord(ch) < 32:
            out.append('\\x%02x' % ord(ch))
        elif ch == 'é' and random.random() < 0.3:
            out.append('\\xe9')
        elif ch == '/' and random.random() < 0.3:
            out.append('\\/')
        else:
            out.append(ch)
    out.append(q)
    return ''.join(out)


def is_ident(k):
    return k.isidentifier() or k.startswith('$') and k[1:].replace('_', 'a').isalnum() or k in ('if',)


def render_num(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        r = random.random()
        if v >= 0 and r < 0.3:
            return '0x%X' % v
        if r < 0.45:
            return ('+' if v >= 0 else '') + str(v)
        return str(v)
    if v == int(v) and random.random() < 0.3:
        return '%d.' % v
    s = repr(v)
    if s.startswith('0.') and random.random() < 0.5:
        s = s[1:]
    if s.startswith('-0.') and random.random() < 0.5:
        s = '-' + s[2:]
    return s


def render(v):
    if v is None:
        return 'null'
    if isinstance(v, (bool, int, float)):
        return render_num(v)
    if isinstance(v, str):
        return render_str(v)
    trailing = random.choice(['', ',', ',']) if True else ''
    if isinstance(v, list):
        return '[' + ws() + (',' + ws()).join(render(x) for x in v) + (trailing if v else '') + ws() + ']'
    parts = []
    for k, x in v.items():
        if (k.isidentifier() or k in ('if', '$x')) and k.isascii() and random.random() < 0.7:
            key = k
        else:
            key = render_str(k)
        parts.append(key + ws() + ':' + ws() + render(x))
    return '{' + ws() + (',' + ws()).join(parts) + (trailing if parts else '') + ws() + '}'


made = 0
while made < 230:
    v = rand_value()
    text = ws() + render(v) + ws()
    r = add(text)
    if r == 'E':
        # the generator only produces valid JSON5; show it if the reference disagrees
        print('reference rejected generated text:', repr(text)[:100])
    made += 1

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn check_line(line: str) -> u8 {
    var arena_buf: [262144]u8 = zero
    var a = mem.arena_from(arena_buf[0usize..262144usize])
    var text: [4096]u8 = zero
    var want: [4096]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let (in_hex, p1) = tok(line, p0)
    let n = unhex(in_hex, text[0usize..4096usize])
    var options: json.Options = zero
    options.allow_duplicate_keys = true
    let (got, got_error) = json5.parse(&a, text[0usize..n], options)
    if kind[0usize] == 69u8 {
        if got_error == ok { ret 1u8 }
        ret 0u8
    }
    if kind[0usize] == 70u8 {
        if got_error != json5.NonFinite { ret 2u8 }
        ret 0u8
    }
    if got_error != ok { ret 3u8 }
    let (want_hex, p2) = tok(line, p1)
    let wn = unhex(want_hex, want[0usize..4096usize])
    let (expected, expected_error) = json.parse(&a, want[0usize..wn], options)
    if expected_error != ok { ret 4u8 }
    if !json.values_equal(&got, &expected) { ret 5u8 }
    // and the JSON5 writer's output reads back to the same tree
    var out: [8192]u8 = zero
    var sw: io.SliceWriter = zero
    sw.data = out[0usize..8192usize]
    var writer = io.slice_writer(&sw)
    if json5.write(&writer, &got) != ok { ret 7u8 }
    let (again, again_error) = json5.parse(&a, out[0usize..sw.off], options)
    if again_error != ok { ret 8u8 }
    if !json.values_equal(&got, &again) { ret 9u8 }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // Exact writer output on a small tree.
    var arena_buf: [65536]u8 = zero
    var arena = mem.arena_from(arena_buf[0usize..65536usize])
    var options: json.Options = zero
    let (v, v_error) = json5.parse(&arena, "{a: [1, 'x', +2.5], 'two words': null, if: true, '7up': 0xA,}", options)
    if v_error != ok { os.exit(101i32) }
    // duplicate keys are the JSON module's decision: refused unless the options allow them
    let (_, dup_error) = json5.parse(&arena, "{a:1,'a':2}", options)
    if dup_error != json.DuplicateKey { os.exit(105i32) }
    var out: [1024]u8 = zero
    var sw: io.SliceWriter = zero
    sw.data = out[0usize..1024usize]
    var writer = io.slice_writer(&sw)
    if json5.write(&writer, &v) != ok { os.exit(103i32) }
    if !text_is(out[0usize..sw.off],"{a:[1,\\"x\\",2.5],\\"two words\\":null,if:true,\\"7up\\":10}") { os.exit(104i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("fmt json5 ok")
    ret ok
}
'''

src = ('// e.fmt.json5 against the json5 package: its accept/reject verdict and its value (as strict JSON,\n'
       '// compared structurally) over hand-listed features and refusals and random decorated trees (D2802).\n'
       '// V ok with expected JSON, E refused, F non-finite. Generated by scripts/gen_json5_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.fmt.json\nuse e.fmt.json5\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors', len([l for l in lines if l[0] == 'V']), 'valid')
