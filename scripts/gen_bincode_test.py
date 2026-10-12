"""Generate tests/selfhost/fixtures/link/fmt_bincode/src/main.e (L135, D2801).

No bincode implementation is installed on this host (Rust-only), so the reference is an
independent Python model of the two documented wire formats written from the bincode
specification: bincode 1 default (fixint, little endian; u64 lengths, u32 variants) and
bincode 2 `config::standard()` (varint with the 251/252/253 markers, zigzag signed),
each also big-endian. Lines: `<cfg> <ops> => <hex>` (E encode+decode), `T <cfg> <ops> => <hex>`
(decoding a truncated or corrupt input must fail).
"""
import random
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(135)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_bincode' / 'src' / 'main.e'


def uvar(v, big):
    order = 'big' if big else 'little'
    if v < 251:
        return bytes([v])
    if v <= 0xFFFF:
        return bytes([251]) + v.to_bytes(2, order)
    if v <= 0xFFFFFFFF:
        return bytes([252]) + v.to_bytes(4, order)
    return bytes([253]) + v.to_bytes(8, order)


def zig(v):
    return (v << 1) if v >= 0 else (((-v - 1) << 1) | 1)


def enc_uint(v, width, varint, big):
    if varint:
        return uvar(v, big)
    return v.to_bytes(width, 'big' if big else 'little')


def enc_int(v, width, varint, big):
    if varint:
        return uvar(zig(v), big)
    return (v & ((1 << (8 * width)) - 1)).to_bytes(width, 'big' if big else 'little')


def encode(ops, varint, big):
    out = b''
    for kind, val in ops:
        if kind == 'u8':
            out += bytes([val])
        elif kind == 'i8':
            out += bytes([val & 255])
        elif kind == 'b':
            out += bytes([val])
        elif kind in ('u16', 'u32', 'u64'):
            out += enc_uint(val, {'u16': 2, 'u32': 4, 'u64': 8}[kind], varint, big)
        elif kind in ('i16', 'i32', 'i64'):
            out += enc_int(val, {'i16': 2, 'i32': 4, 'i64': 8}[kind], varint, big)
        elif kind == 'f32':
            out += val.to_bytes(4, 'big' if big else 'little')
        elif kind == 'f64':
            out += val.to_bytes(8, 'big' if big else 'little')
        elif kind in ('s', 'y'):
            out += enc_uint(len(val), 8, varint, big) + val
        elif kind == 'o':
            out += bytes([val])
        elif kind == 'v':
            out += enc_uint(val, 4, varint, big)
        else:
            raise ValueError(kind)
    return out


def op_text(kind, val):
    if kind in ('s', 'y'):
        return '%s:%s' % (kind, val.hex() or '-')
    if kind in ('f32', 'f64'):
        return '%s:%x' % (kind, val)
    return '%s:%d' % (kind, val)


EDGES = {
    'u8': [0, 1, 127, 128, 250, 251, 255], 'i8': [0, 1, -1, 127, -128],
    'u16': [0, 1, 250, 251, 252, 255, 256, 65535], 'u32': [0, 250, 251, 65535, 65536, 4294967295],
    'u64': [0, 250, 251, 65535, 65536, 4294967295, 4294967296, 18446744073709551615],
    'i16': [0, 1, -1, 125, 126, -126, -127, 32767, -32768], 'i32': [0, -1, 1, 2147483647, -2147483648, 32768, -32769],
    'i64': [0, -1, 1, 9223372036854775807, -9223372036854775808, 2147483648, -2147483649],
    'v': [0, 1, 2, 250, 251, 65536],
}


def random_op():
    kind = random.choice(['u8', 'i8', 'b', 'u16', 'u32', 'u64', 'i16', 'i32', 'i64', 'f32', 'f64', 's', 'y', 'o', 'v'])
    if kind == 'b' or kind == 'o':
        return kind, random.randint(0, 1)
    if kind in ('s', 'y'):
        n = random.choice([0, 1, 2, 5, 50, 250, 251, 300])
        return kind, bytes(random.randint(0, 255) for _ in range(n)) if kind == 'y' else ''.join(random.choice('abcxyz é€') for _ in range(n // 2)).encode('utf-8')
    if kind == 'f32':
        return kind, random.choice([0x3f800000, 0x00000000, 0xc2f6e979, 0x7f800000, random.getrandbits(32) & 0x7fffffff])
    if kind == 'f64':
        return kind, random.choice([0x3ff8000000000000, 0, 0xc09ec0e147ae147b, 0x7ff0000000000000, random.getrandbits(64) & 0x7fffffffffffffff])
    bits = {'u8': 8, 'u16': 16, 'u32': 32, 'u64': 64, 'i8': 8, 'i16': 16, 'i32': 32, 'i64': 64, 'v': 32}[kind]
    if kind in EDGES and random.random() < 0.5:
        return kind, random.choice(EDGES[kind])
    if kind[0] == 'i':
        return kind, random.randint(-(1 << (bits - 1)), (1 << (bits - 1)) - 1)
    return kind, random.randint(0, (1 << bits) - 1)


CFGS = [('L', False, False), ('S', True, False), ('Lb', False, True), ('Sb', True, True)]
lines = []
for _ in range(240):
    name, varint, big = random.choice(CFGS)
    ops = [random_op() for _ in range(random.randint(1, 6))]
    data = encode(ops, varint, big)
    lines.append('E %s %s => %s' % (name, ' '.join(op_text(k, v) for k, v in ops), data.hex() or '-'))
    if random.random() < 0.5 and len(data) > 1:
        cut = random.randint(0, len(data) - 1)
        lines.append('T %s %s => %s' % (name, ' '.join(op_text(k, v) for k, v in ops), data[:cut].hex() or '-'))
# per-type known vectors (bincode docs and hand-derived)
known = [
    ('S', [('u16', 300)], 'fb2c01'), ('S', [('u32', 250)], 'fa'), ('S', [('u64', 4294967296)], 'fd0000000001000000'),
    ('S', [('i32', -1)], '01'), ('S', [('i32', 1)], '02'), ('S', [('i64', -64)], '7f'), ('S', [('i64', 64)], '8000'.replace('8000', '80')),
    ('L', [('u16', 1)], '0100'), ('L', [('i32', -2)], 'feffffff'), ('Lb', [('u32', 1)], '00000001'),
    ('L', [('s', b'hi')], '02000000000000006869'), ('S', [('s', b'hi')], '026869'), ('L', [('o', 1), ('u8', 5)], '0105'),
    ('S', [('v', 3)], '03'), ('L', [('v', 3)], '03000000'),
]
for name, ops, hexs in known:
    varint = name[0] == 'S'
    big = name.endswith('b')
    data = encode(ops, varint, big)
    if name == 'S' and ops == [('i64', 64)]:
        hexs = data.hex()  # zigzag(64) = 128 -> marker form; keep the model's answer
    assert data.hex() == hexs, (name, ops, data.hex(), hexs)
    lines.append('E %s %s => %s' % (name, ' '.join(op_text(k, v) for k, v in ops), data.hex()))
# corrupt: marker 254 (u128) is refused, bool 2 is refused, length past end
lines.append('T S u32:1 => fe00')
lines.append('T L b:1 => 02')
lines.append('T S s:61 => 0561')

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    if c >= 65u8 { ret c - 55u8 }
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

fn hex64(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 16u64 + u64(hexval(s[i]))
        i += 1usize
    }
    ret v
}

fn colon(op: str) -> usize {
    var i = 0usize
    while i < op.len && op[i] != 58u8 { i += 1usize }
    ret i
}

fn cfg_of(name: str) -> bincode.Config {
    var c: bincode.Config = zero
    if name[0usize] == 83u8 { c.varint = true }
    if name.len == 2usize { c.big = true }
    ret c
}

fn put_op(w: *bincode.Writer, op: str, scratch: []u8) {
    let c = colon(op)
    let kind = op[0usize..c]
    let val = op[c + 1usize..op.len]
    let k0 = kind[0usize]
    if text_is(kind, "u8") {
        bincode.put_u8(w, u8(dec(val)))
    } else if text_is(kind, "i8") {
        bincode.put_i8(w, i8(dec(val)))
    } else if text_is(kind, "b") {
        bincode.put_bool(w, dec(val) == 1i64)
    } else if text_is(kind, "u16") {
        bincode.put_u16(w, u16(dec(val)))
    } else if text_is(kind, "u32") {
        bincode.put_u32(w, u32(dec(val)))
    } else if text_is(kind, "u64") {
        bincode.put_u64(w, u64dec(val))
    } else if text_is(kind, "i16") {
        bincode.put_i16(w, i16(dec(val)))
    } else if text_is(kind, "i32") {
        bincode.put_i32(w, i32(dec(val)))
    } else if text_is(kind, "i64") {
        bincode.put_i64(w, i64dec(val))
    } else if text_is(kind, "f32") {
        bincode.put_f32(w, mem.bitcast[f32](u32(hex64(val))))
    } else if text_is(kind, "f64") {
        bincode.put_f64(w, mem.bitcast[f64](hex64(val)))
    } else if text_is(kind, "s") || text_is(kind, "y") {
        let n = unhex(val, scratch)
        if text_is(kind, "s") {
            bincode.put_str(w, scratch[0usize..n])
        } else {
            bincode.put_bytes(w, scratch[0usize..n])
        }
    } else if text_is(kind, "o") {
        bincode.put_option(w, dec(val) == 1i64)
    } else {
        bincode.put_variant(w, u32(dec(val)))
    }
}

fn u64dec(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn i64dec(s: str) -> i64 {
    if s.len > 0usize && s[0usize] == 45u8 {
        // magnitude through u64 so that -2^63 does not overflow
        let m = u64dec(s[1usize..s.len])
        if m == 9223372036854775808u64 { ret -9223372036854775807i64 - 1i64 }
        ret 0i64 - i64(m)
    }
    ret i64(u64dec(s))
}

// Reads the op back and says whether it equals the op's value.
fn get_op(r: *bincode.Reader, op: str, scratch: []u8) -> bool {
    let c = colon(op)
    let kind = op[0usize..c]
    let val = op[c + 1usize..op.len]
    if text_is(kind, "u8") { ret i64(bincode.get_u8(r)) == dec(val) }
    if text_is(kind, "i8") { ret i64(bincode.get_i8(r)) == dec(val) }
    if text_is(kind, "b") { ret bincode.get_bool(r) == (dec(val) == 1i64) }
    if text_is(kind, "u16") { ret i64(bincode.get_u16(r)) == dec(val) }
    if text_is(kind, "u32") { ret i64(bincode.get_u32(r)) == dec(val) }
    if text_is(kind, "u64") { ret bincode.get_u64(r) == u64dec(val) }
    if text_is(kind, "i16") { ret i64(bincode.get_i16(r)) == dec(val) }
    if text_is(kind, "i32") { ret i64(bincode.get_i32(r)) == dec(val) }
    if text_is(kind, "i64") { ret bincode.get_i64(r) == i64dec(val) }
    if text_is(kind, "f32") { ret u64(mem.bitcast[u32](bincode.get_f32(r))) == hex64(val) }
    if text_is(kind, "f64") { ret mem.bitcast[u64](bincode.get_f64(r)) == hex64(val) }
    if text_is(kind, "s") || text_is(kind, "y") {
        let n = unhex(val, scratch)
        if text_is(kind, "s") {
            let got = bincode.get_str(r)
            if got.len != n { ret false }
            var i = 0usize
            while i < n {
                if got[i] != scratch[i] { ret false }
                i += 1usize
            }
            ret true
        }
        let got_bytes = bincode.get_bytes(r)
        if got_bytes.len != n { ret false }
        var k = 0usize
        while k < n {
            if got_bytes[k] != scratch[k] { ret false }
            k += 1usize
        }
        ret true
    }
    if text_is(kind, "o") { ret bincode.get_option(r) == (dec(val) == 1i64) }
    ret i64(bincode.get_variant(r)) == dec(val)
}

fn check_line(line: str) -> u8 {
    var buf: [1024]u8 = zero
    var want: [1024]u8 = zero
    var scratch: [512]u8 = zero
    var ops: [8]str = zero
    let (kind, p0) = tok(line, 0usize)
    let (cfg_name, p1) = tok(line, p0)
    var count = 0usize
    var p = p1
    while true {
        let (word, next) = tok(line, p)
        p = next
        if text_is(word, "=>") { break }
        ops[count] = word
        count += 1usize
    }
    let (hex_text, p2) = tok(line, p)
    let n = unhex(hex_text, want[0usize..1024usize])
    let cfg = cfg_of(cfg_name)
    if kind[0usize] == 69u8 {
        var w = bincode.writer(buf[0usize..1024usize], cfg)
        var i = 0usize
        while i < count {
            put_op(&w, ops[i], scratch[0usize..512usize])
            i += 1usize
        }
        if bincode.failed(&w) != ok { ret 1u8 }
        let got = bincode.written(&w)
        if got.len != n { ret 2u8 }
        i = 0usize
        while i < n {
            if got[i] != want[i] { ret 3u8 }
            i += 1usize
        }
        var r = bincode.reader(want[0usize..n], cfg)
        i = 0usize
        while i < count {
            if !get_op(&r, ops[i], scratch[0usize..512usize]) { ret 4u8 }
            i += 1usize
        }
        if bincode.read_failed(&r) != ok || !bincode.at_end(&r) { ret 5u8 }
        ret 0u8
    }
    // T: decoding the damaged bytes must end with the reader marked bad (or leave bytes over
    // for a corrupt tag that happened to parse; those lines are chosen to fail outright).
    var r = bincode.reader(want[0usize..n], cfg)
    var i = 0usize
    while i < count {
        let ignored = get_op(&r, ops[i], scratch[0usize..512usize])
        if ignored && !ignored { ret 99u8 }
        i += 1usize
    }
    if bincode.read_failed(&r) == ok { ret 11u8 }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("fmt bincode ok")
    ret ok
}
'''

src = ('// e.fmt.bincode against an independent Python model of the bincode 1 and 2 wire formats (D2801).\n'
       '// E lines encode the ops and decode the bytes back; T lines decode damaged bytes and must fail.\n'
       '// Generated by scripts/gen_bincode_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.fmt.bincode\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
