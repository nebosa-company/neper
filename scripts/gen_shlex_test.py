"""Generate tests/selfhost/fixtures/link/text_shlex/src/main.e (L135, D2801).

Reference: Python's `shlex.split(s)` (posix mode, no comments), `shlex.quote` and
`shlex.join` on random strings over quotes, backslashes, whitespace and metacharacters.
Inputs and words travel as hex so no byte of them needs escaping in the vector text.
"""
import random
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(136)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'text_shlex' / 'src' / 'main.e'
ALPHA = ["a", "b", "c", "1", " ", " ", "\t", "\n", "'", '"', "\\", "$", "~", "#", "*", ";", "=", "é", "-", "/"]


def hx(s):
    return s.encode('utf-8').hex() or '-'


lines = []
fixed = ['', ' ', 'a b c', "a 'b c' d", 'a "b c" d', 'a\\ b', '"a\\"b"', '"a\\nb"', "''", '""', "a''b", 'a""b',
         "'a", '"a', 'a\\', '"a\\', "it's", "'it'\\''s'", '  lead and trail  ', 'x="y z"', '$HOME ~/x #c', "a\tb\nc"]
inputs = fixed + [''.join(random.choice(ALPHA) for _ in range(random.randint(1, 14))) for _ in range(260)]
for s in inputs:
    try:
        words = shlex.split(s)
        lines.append('S %s => %d %s' % (hx(s), len(words), ' '.join(hx(w) for w in words)))
    except ValueError:
        lines.append('S %s => E' % hx(s))
for _ in range(80):
    w = ''.join(random.choice(ALPHA) for _ in range(random.randint(0, 8)))
    lines.append('Q %s => %s' % (hx(w), hx(shlex.quote(w))))
for _ in range(40):
    ws = [''.join(random.choice(ALPHA) for _ in range(random.randint(0, 5))) for _ in range(random.randint(0, 4))]
    lines.append('J %d %s => %s' % (len(ws), ' '.join(hx(w) for w in ws), hx(shlex.join(ws))))
# round trip through split(join(x)) is checked in the fixture on every J line too.

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

fn same_bytes(got: str, want: []const u8) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check_line(line: str) -> u8 {
    var input: [256]u8 = zero
    var buf: [512]u8 = zero
    var words: [16]str = zero
    var tmp: [512]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    if kind[0usize] == 83u8 {
        let (in_hex, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (count_text, p3) = tok(line, p2)
        let n = unhex(in_hex, input[0usize..256usize])
        let (got, got_error) = shlex.split(input[0usize..n], buf[0usize..512usize], words[0usize..16usize])
        if count_text[0usize] == 69u8 {
            if got_error != shlex.Unterminated { ret 1u8 }
            ret 0u8
        }
        if got_error != ok { ret 2u8 }
        if i64(got) != dec(count_text) { ret 3u8 }
        var k = 0usize
        var p = p3
        while k < got {
            let (word_hex, next) = tok(line, p)
            p = next
            let wn = unhex(word_hex, tmp[0usize..512usize])
            if !same_bytes(words[k], tmp[0usize..wn]) { ret 4u8 }
            k += 1usize
        }
        ret 0u8
    }
    if kind[0usize] == 81u8 {
        let (in_hex, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (want_hex, p3) = tok(line, p2)
        let n = unhex(in_hex, input[0usize..256usize])
        let wn = unhex(want_hex, tmp[0usize..512usize])
        let (got, got_error) = shlex.quote(input[0usize..n], buf[0usize..512usize])
        if got_error != ok { ret 11u8 }
        if !same_bytes(got, tmp[0usize..wn]) { ret 12u8 }
        ret 0u8
    }
    // J count words... => joined
    let (count_text, p1) = tok(line, p0)
    let count = usize(dec(count_text))
    var p = p1
    var offset = 0usize
    var k = 0usize
    while k < count {
        let (word_hex, next) = tok(line, p)
        p = next
        let wn = unhex(word_hex, input[offset..256usize])
        words[k] = input[offset..offset + wn]
        offset += wn
        k += 1usize
    }
    let (arrow, p2) = tok(line, p)
    let (want_hex, p3) = tok(line, p2)
    let wn = unhex(want_hex, tmp[0usize..512usize])
    let (joined, join_error) = shlex.join(words[0usize..count], buf[0usize..512usize])
    if join_error != ok { ret 21u8 }
    if !same_bytes(joined, tmp[0usize..wn]) { ret 22u8 }
    // and splitting it again gives the words back
    var again: [16]str = zero
    var again_buf: [512]u8 = zero
    let (m, split_error) = shlex.split(joined, again_buf[0usize..512usize], again[0usize..16usize])
    if split_error != ok || m != count { ret 23u8 }
    k = 0usize
    while k < count {
        if !same_bytes(again[k], words[k]) { ret 24u8 }
        k += 1usize
    }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // The caller's buffers are the limit: too small is refused, never truncated.
    var tiny: [2]u8 = zero
    var two: [1]str = zero
    let (_, small) = shlex.split("abc def", tiny[0usize..2usize], two[0usize..1usize])
    if small != shlex.TooSmall { os.exit(101i32) }
    var big: [16]u8 = zero
    let (_, few) = shlex.split("a b", big[0usize..16usize], two[0usize..1usize])
    if few != shlex.TooSmall { os.exit(102i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("text shlex ok")
    ret ok
}
'''

src = ('// e.text.shlex against Python shlex.split / shlex.quote / shlex.join (posix, D2801). S split, Q quote,\n'
       '// J join (then split again). Generated by scripts/gen_shlex_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.text.shlex\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
