# Generates the tables in lib/e/text/unicode.e from Python's unicodedata and writes
# src/main.e with expectations drawn from the same source. Run from this directory.
import struct
import unicodedata as ud

CATEGORIES = ["Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
              "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co", "Cn"]
LIMIT = 0x110000


def runs(value_of):
    out = b''
    previous = None
    for c in range(LIMIT):
        v = value_of(c)
        if v != previous:
            out += struct.pack('<I', c)[:3] + bytes([v])
            previous = v
    return out


def pairs(map_of):
    out = b''
    for c in range(LIMIT):
        m = map_of(c)
        if m is not None:
            out += struct.pack('<II', c, m)
    return out


category = runs(lambda c: CATEGORIES.index(ud.category(chr(c))))
combining = runs(lambda c: ud.combining(chr(c)))


def simple(fn):
    def map_of(c):
        m = fn(chr(c))
        return ord(m) if len(m) == 1 and m != chr(c) else None
    return map_of


lower = pairs(simple(str.lower))
upper = pairs(simple(str.upper))
fold = pairs(simple(str.casefold))
multi = b''
for c in range(LIMIT):
    f = chr(c).casefold()
    if len(f) > 1:
        assert len(f) <= 3
        multi += struct.pack('<II', c, len(f)) + b''.join(struct.pack('<I', ord(x)) for x in f) + b'\0' * (4 * (3 - len(f)))


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


path = '../../../../../lib/e/text/unicode.e'
source = open(path, encoding='utf-8').read()
start = source.index('// --- Generated tables')
head = source[:start]
tables = '''// --- Generated tables (tests/selfhost/fixtures/link/text_unicode/reference.py).
fn category_table() -> str { ret %s }
fn combining_table() -> str { ret %s }
fn lower_table() -> str { ret %s }
fn upper_table() -> str { ret %s }
fn fold_table() -> str { ret %s }
fn fold_multi_table() -> str { ret %s }
''' % tuple(literal(t) for t in (category, combining, lower, upper, fold, multi))
head = head.replace('fn version() -> str { ret "15.0.0" }', 'fn version() -> str { ret "%s" }' % ud.unidata_version)
open(path, 'w', encoding='utf-8', newline='\n').write(head + tables)

# Expectations.
samples = [0x41, 0x61, 0x1C5, 0x2B0, 0x4E2D, 0x300, 0x903, 0x20DD, 0x37, 0x2160, 0xBD, 0x5F, 0x2D, 0x28, 0x29, 0xAB, 0xBB, 0x21, 0x2B, 0x24, 0x5E, 0xA9, 0x20,
           0x2028, 0x2029, 0x7, 0xAD, 0xD800, 0xE000, 0x378, 0x10FFFF, 0x1F600, 0x10000, 0xE01EF]
checks = []
code = 10
for s in samples:
    checks.append('    if unicode.category(%du32) != .%s { os.exit(%d) }' % (s, ud.category(chr(s)), code))
    code += 1
for s in [0x300, 0x301, 0x315, 0x31B, 0x3099, 0x41, 0x1DCE, 0x345]:
    checks.append('    if unicode.combining_class(%du32) != %du8 { os.exit(%d) }' % (s, ud.combining(chr(s)), code))
    code += 1
for s in [0x41, 0x61, 0xC9, 0x1E9E, 0x3A3, 0x10400, 0x1C5, 0x130, 0x4E2D]:
    lo = ord(chr(s).lower()) if len(chr(s).lower()) == 1 else s
    up = ord(chr(s).upper()) if len(chr(s).upper()) == 1 else s
    checks.append('    if unicode.to_lower_simple(%du32) != %du32 || unicode.to_upper_simple(%du32) != %du32 { os.exit(%d) }' % (s, lo, s, up, code))
    code += 1
for text in ["Straße", "ΣΊΣΥΦΟΣ", "ǅemal", "İ", "plain ascii", "ﬃ"]:
    checks.append('    let (fold_%d, fe%d) = unicode.casefold(a, %s)\n    if fe%d != ok || !str.eq(fold_%d, %s) { os.exit(%d) }' % (code, code, literal(text.encode()), code, code, literal(text.casefold().encode()), code))
    code += 1
for s, expect in [(0x20, True), (0x9, True), (0xA0, True), (0x3000, True), (0x41, False), (0x200B, False)]:
    checks.append('    if unicode.is_whitespace(%du32) != %s { os.exit(%d) }' % (s, 'true' if expect else 'false', code))
    code += 1
for s, alpha, num in [(0x41, True, False), (0x4E2D, True, False), (0x2160, True, True), (0x37, False, True), (0xBD, False, True), (0x2B, False, False)]:
    checks.append('    if unicode.is_alphabetic(%du32) != %s || unicode.is_numeric(%du32) != %s { os.exit(%d) }' % (s, 'true' if alpha else 'false', s, 'true' if num else 'false', code))
    code += 1
grapheme_cases = [
    ("éa", ["é", "a"]),
    ("\r\nx", ["\r\n", "x"]),
    ("\U0001F1FA\U0001F1F8\U0001F1EC\U0001F1E7", ["\U0001F1FA\U0001F1F8", "\U0001F1EC\U0001F1E7"]),
    ("\U0001F468‍\U0001F469‍\U0001F467!", ["\U0001F468‍\U0001F469‍\U0001F467", "!"]),
    ("각각", ["각", "각"]),
    ("a️b", ["a️", "b"]),
    ("", []),
]
for text, clusters in grapheme_cases:
    it = code
    lines = ['    var it_%d = unicode.graphemes(%s)' % (it, literal(text.encode()))]
    for cluster in clusters:
        lines.append('    let (g_%d, more_%d) = unicode.graphemes_next(&it_%d)\n    if !more_%d || !str.eq(g_%d, %s) { os.exit(%d) }' % (code, code, it, code, code, literal(cluster.encode()), code))
        code += 1
    lines.append('    let (end_%d, more_end_%d) = unicode.graphemes_next(&it_%d)\n    if more_end_%d { os.exit(%d) }' % (code, code, it, code, code))
    code += 1
    checks.append("\n".join(lines))

fixture = '''// `e.text.unicode`: categories, combining classes, simple case mappings, full case
// folding, whitespace, alphabetic and numeric against Python's unicodedata %s
// (reference.py beside this fixture generates the module's tables and these
// expectations), and grapheme clusters over combining marks, CR LF, regional
// indicator pairs, a ZWJ family, decomposed Hangul and a variation selector. Every
// check has its own exit code.
use e.os
use e.mem
use e.str
use e.text.unicode as unicode

fn main(a: *mem.Arena, args: []str) -> err {
    if !str.eq(unicode.version(), "%s") { os.exit(1) }
%s
    ret ok
}
''' % (ud.unidata_version, ud.unidata_version, "\n".join(checks))
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(fixture)
print(len(category), len(combining), len(lower), len(upper), len(fold), len(multi))
