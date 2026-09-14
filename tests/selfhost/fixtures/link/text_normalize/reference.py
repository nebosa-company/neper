# Generates the tables in lib/e/text/normalize.e from Python's unicodedata (the same
# Unicode version e.text.unicode reports) and prints the fixture's expectations from the
# same source. Run from this directory.
import struct
import unicodedata as ud

LIMIT = 0x110000
S_BASE, S_COUNT = 0xAC00, 11172
V_BASE, V_COUNT = 0x1161, 21
T_BASE, T_COUNT = 0x11A7, 28


def u24(v):
    return struct.pack('<I', v)[:3]


# Single-level decompositions, as UnicodeData carries them: the module recurses.
canon, compat = {}, {}
for c in range(LIMIT):
    if S_BASE <= c < S_BASE + S_COUNT:
        continue
    d = ud.decomposition(chr(c))
    if not d:
        continue
    if d.startswith('<'):
        compat[c] = [int(x, 16) for x in d.split('>')[1].split()]
    else:
        canon[c] = [int(x, 16) for x in d.split()]
assert max(len(v) for v in canon.values()) == 2
assert max(len(v) for v in compat.values()) <= 18

# Index: scalar(3) kind(1: 0 canonical, 1 compatibility) offset(3) count(1), sorted by
# scalar. Pool: 3 bytes per scalar.
index, pool, offset = b'', b'', 0
for c in sorted(set(canon) | set(compat)):
    kind, seq = (0, canon[c]) if c in canon else (1, compat[c])
    index += u24(c) + bytes([kind]) + u24(offset) + bytes([len(seq)])
    pool += b''.join(u24(x) for x in seq)
    offset += len(seq)

# Primary composites: canonical pairs that NFC recomposes, which leaves out the
# composition exclusions, singletons and non-starter decompositions.
pairs = {}
for c, v in canon.items():
    if len(v) == 2 and ud.normalize('NFC', chr(v[0]) + chr(v[1])) == chr(c):
        pairs[(v[0], v[1])] = c
composition = b''.join(u24(a) + u24(b) + u24(pairs[(a, b)]) for (a, b) in sorted(pairs))

# Starters that can be the second of a composition: a segment may not be cut before one.
# Hangul V and T jamo compose algorithmically and are listed here so the cut rule has no
# special case.
seconds = {b for (a, b) in pairs if ud.combining(chr(b)) == 0}
seconds |= set(range(V_BASE, V_BASE + V_COUNT)) | set(range(T_BASE + 1, T_BASE + T_COUNT))
starter_seconds = b''.join(u24(x) for x in sorted(seconds))


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


path = '../../../../../lib/e/text/normalize.e'
source = open(path, encoding='utf-8').read()
start = source.index('// --- Generated tables')
tables = '''// --- Generated tables (tests/selfhost/fixtures/link/text_normalize/reference.py):
// %d decompositions over a pool of %d scalars, %d composition pairs, %d starter seconds.
fn decomposition_table() -> str { ret %s }
fn decomposition_pool() -> str { ret %s }
fn composition_table() -> str { ret %s }
fn starter_seconds_table() -> str { ret %s }
''' % (len(index) // 8, len(pool) // 3, len(pairs), len(seconds),
       literal(index), literal(pool), literal(composition), literal(starter_seconds))
open(path, 'w', encoding='utf-8', newline='\n').write(source[:start] + tables)
print("tables: index %d B, pool %d B, composition %d B, seconds %d B" % (len(index), len(pool), len(composition), len(starter_seconds)))


# Expectations: every sample under every form, as byte literals for the fixture.
def lit(s):
    return literal(s.encode('utf-8'))


samples = {
    'e_acute': 'é',
    'e_combining': 'é',
    'reorder': 'á̧',
    'ordered': 'á̧',
    'marks_only': '̧́',
    'hangul': '한글',
    'jamo': '각',
    'lv_plus_t': '각',
    'ligature': 'ﬁ',
    'circled': '①',
    'fullwidth': 'Ａ',
    'excluded': 'क़',
    'singleton': 'Ω',
    'two_levels': 'ṩ',
    'four_deep': 'ᾂ',
    'widest': 'ﷺ',
    'blocked': 'é́',
    'tibetan': 'ཱི',
    'mixed': 'café ﬁn 한',
    'ascii': 'plain ascii',
}
print()
for name, s in samples.items():
    print("%-12s %s" % (name, lit(s)))
    for form in ('NFC', 'NFD', 'NFKC', 'NFKD'):
        n = ud.normalize(form, s)
        print("    %-4s %-3s %s%s" % (form, 'yes' if n == s else 'no', lit(n), '' if n != s else ' (same)'))
