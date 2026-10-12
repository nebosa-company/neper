"""Generate tests/selfhost/fixtures/link/fmt_fixedwidth/src/main.e (L160, D2803).

No FileHelpers (.NET) on this host: the reference is an independent Python model built on
string slicing and `strip`/`ljust`/`rjust` over random layouts (field widths, alignment,
pad byte, trim rule, optional) and records, in the four length modes; refusals are
the modes' own (`Short`, `Long`) and `Overflow` on writing.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(163)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_fixedwidth' / 'src' / 'main.e'


def hx(b):
    return b.hex() or '-'


def model_read(fields, mode, line):
    width = sum(f[0] for f in fields)
    if len(line) > width and mode in ('E', 'L'):
        return 'long'
    if len(line) < width and mode in ('E', 'M'):
        return 'short'
    out = []
    at = 0
    for w, align, pad, trim, optional in fields:
        if at >= len(line):
            if not optional and w > 0:
                return 'short'
            out.append(b'')
        else:
            cut = line[at:at + w]
            p = bytes([pad])
            if trim in ('B', 'L'):
                cut = cut.lstrip(p)
            if trim in ('B', 'R'):
                cut = cut.rstrip(p)
            out.append(cut)
        at += w
    return out


def model_write(fields, values):
    out = b''
    for (w, align, pad, trim, optional), v in zip(fields, values):
        if len(v) > w:
            return 'overflow'
        p = bytes([pad])
        out += v.ljust(w, p) if align == 'L' else v.rjust(w, p)
    return out


def random_layout():
    n = random.randint(1, 5)
    return [(random.choice([1, 2, 3, 5, 8, 10]), random.choice('LR'), random.choice([32, 32, 48, 95, 42]), random.choice('NBLR'), random.random() < 0.3) for _ in range(n)]


def layout_text(fields):
    return ' '.join('%d,%s,%d,%s,%d' % (w, a, p, t, 1 if o else 0) for w, a, p, t, o in fields)


lines = []
for _ in range(300):
    fields = random_layout()
    width = sum(f[0] for f in fields)
    mode = random.choice('EMLV')
    n = max(0, width + random.choice([0, 0, 0, -2, -width, 3, 1, -1]))
    line = bytes(random.choice(b'ab c_*09 ') for _ in range(n))
    got = model_read(fields, mode, line)
    if isinstance(got, str):
        lines.append('R %s %s %s => %s' % (mode, layout_text(fields), hx(line), got))
    else:
        lines.append('R %s %s %s => ok %s' % (mode, layout_text(fields), hx(line), ' '.join(hx(v) for v in got)))
for _ in range(200):
    fields = random_layout()
    values = [bytes(random.choice(b'abxyz 019') for _ in range(random.choice([0, 1, w - 1 if w > 1 else 1, w, w + 1]))) for w, *_ in fields]
    got = model_write(fields, values)
    if isinstance(got, str):
        lines.append('W %s %s => %s' % (layout_text(fields), ' '.join(hx(v) for v in values), got))
    else:
        lines.append('W %s %s => ok %s' % (layout_text(fields), ' '.join(hx(v) for v in values), hx(got)))

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

// `w,A,pad,T,opt` into a Field.
fn parse_field(spec: str) -> fixedwidth.Field {
    var f: fixedwidth.Field = zero
    var parts: [5]str = zero
    var count = 0usize
    var start = 0usize
    var i = 0usize
    while i <= spec.len {
        if i == spec.len || spec[i] == 44u8 {
            parts[count] = spec[start..i]
            count += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    f.width = u32(dec(parts[0usize]))
    if parts[1usize][0usize] == 82u8 { f.align = .Right }
    f.pad = u8(dec(parts[2usize]))
    let t = parts[3usize][0usize]
    if t == 66u8 { f.trim = .Both }
    if t == 76u8 { f.trim = .Left }
    if t == 82u8 { f.trim = .Right }
    f.optional = parts[4usize][0usize] == 49u8
    ret f
}

fn check_line(line: str) -> u8 {
    var fields: [5]fixedwidth.Field = zero
    var count = 0usize
    var store: [4096]u8 = zero
    var used = 0usize
    var values: [5]str = zero
    var out: [512]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    var p = p0
    var mode = fixedwidth.Mode.Exact
    if kind[0usize] == 82u8 {
        let (m, pm) = tok(line, p)
        p = pm
        if m[0usize] == 77u8 { mode = .AllowMore }
        if m[0usize] == 76u8 { mode = .AllowLess }
        if m[0usize] == 86u8 { mode = .AllowVariable }
    }
    // fields: tokens containing a comma, until the first token that has none
    while true {
        let (word, next) = tok(line, p)
        var has_comma = false
        var i = 0usize
        while i < word.len {
            if word[i] == 44u8 { has_comma = true }
            i += 1usize
        }
        if !has_comma || word.len == 0usize { break }
        fields[count] = parse_field(word)
        count += 1usize
        p = next
    }
    if kind[0usize] == 82u8 {
        let (hex_line, p1) = tok(line, p)
        let (arrow, p2) = tok(line, p1)
        let (verdict, p3) = tok(line, p2)
        var bytes: [256]u8 = zero
        let n = unhex(hex_line, bytes[0usize..256usize])
        let e = fixedwidth.read(fields[0usize..count], mode, bytes[0usize..n], values[0usize..5usize])
        if verdict[0usize] == 115u8 {
            if e != fixedwidth.Short { ret 1u8 }
            ret 0u8
        }
        if verdict[0usize] == 108u8 {
            if e != fixedwidth.Long { ret 2u8 }
            ret 0u8
        }
        if e != ok { ret 3u8 }
        var q = p3
        var k = 0usize
        while k < count {
            let (vh, next) = tok(line, q)
            q = next
            var want: [64]u8 = zero
            let wn = unhex(vh, want[0usize..64usize])
            if !text_is(values[k], want[0usize..wn]) { ret 4u8 }
            k += 1usize
        }
        ret 0u8
    }
    // W: values (hex each) then => verdict
    var k = 0usize
    while k < count {
        let (vh, next) = tok(line, p)
        p = next
        let vn = unhex(vh, store[used..4096usize])
        values[k] = store[used..used + vn]
        used += vn
        k += 1usize
    }
    let (arrow, p1) = tok(line, p)
    let (verdict, p2) = tok(line, p1)
    let (rec, e) = fixedwidth.write(fields[0usize..count], values[0usize..count], out[0usize..512usize])
    if verdict[0usize] == 111u8 && verdict[1usize] == 118u8 {
        if e != fixedwidth.Overflow { ret 11u8 }
        ret 0u8
    }
    if e != ok { ret 12u8 }
    let (hex_rec, p3) = tok(line, p2)
    var want: [512]u8 = zero
    let wn = unhex(hex_rec, want[0usize..512usize])
    if !text_is(rec, want[0usize..wn]) { ret 13u8 }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // the FileHelpers-style example: name left, quantity right zero-padded
    var fields: [2]fixedwidth.Field = zero
    fields[0usize].width = 6u32
    fields[0usize].pad = 32u8
    fields[0usize].trim = .Both
    fields[1usize].width = 4u32
    fields[1usize].align = .Right
    fields[1usize].pad = 48u8
    var values: [2]str = zero
    values[0usize] = "ab"
    values[1usize] = "7"
    var out: [16]u8 = zero
    let (rec, e) = fixedwidth.write(fields[0usize..2usize], values[0usize..2usize], out[0usize..16usize])
    if e != ok || !text_is(rec, "ab    0007") { os.exit(101i32) }
    var back: [2]str = zero
    if fixedwidth.read(fields[0usize..2usize], .Exact, rec, back[0usize..2usize]) != ok { os.exit(102i32) }
    if !text_is(back[0usize], "ab") || !text_is(back[1usize], "0007") { os.exit(103i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("fmt fixedwidth ok")
    ret ok
}
'''

src = ('// e.fmt.fixedwidth against an independent Python slicing model: random layouts (width, alignment, pad,\n'
       '// trim, optional) and records in the four length modes, and padded writes with Overflow (D2803).\n'
       '// R read (s short, l long), W write (ov overflow). Generated by scripts/gen_fixedwidth_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.fmt.fixedwidth\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
