"""Write tests/selfhost/fixtures/link/text_mask/src/main.e (L076, D2266).

  python scripts/text_mask_reference.py

e.text.mask against Python's fnmatch on the syntax the two share, plus hand-written tables for what fnmatch
lacks (backslash escapes, ^ negation, case folding, UTF-8 code points, ; lists, malformed masks). The shared
subset is 600 seeded (mask, text) pairs built by mutating the text (ASCII letters, a few non-ASCII ones, dots
and dashes): `*`, `?`, `[set]`, `[!set]`, ranges, and a leading literal `]`. Every case runs through
`matches`; a mismatch prints its table and index and exits 1.
"""
import fnmatch
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
rng = np.random.default_rng(20261018)
ALPHABET = list('abcxyz09.-_') + ['é', 'ß', '日']


def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def shared_pair():
    n = int(rng.integers(0, 9))
    text = ''.join(ALPHABET[int(rng.integers(0, len(ALPHABET)))] for _ in range(n))
    mask = ''
    for ch in text:
        r = rng.random()
        if r < 0.45:
            mask += ch
        elif r < 0.60:
            mask += '?'
        elif r < 0.72:
            mask += '*'
        elif r < 0.82:
            mask += '[' + ch + 'q]'
        elif r < 0.90:
            mask += '[!' + ch + ']'
        elif r < 0.95:
            lo = chr(max(ord('a'), ord(ch) - 1)) if ch.isascii() and ch.isalpha() else 'a'
            hi = chr(min(ord('z'), ord(ch) + 1)) if ch.isascii() and ch.isalpha() else 'z'
            mask += '[' + lo + '-' + hi + ']'
        else:
            mask += ch + ('*' if rng.random() < 0.5 else '')
    # perturb half the pairs so a good share are non-matches
    if rng.random() < 0.5 and text:
        i = int(rng.integers(0, len(text)))
        text = text[:i] + ALPHABET[int(rng.integers(0, len(ALPHABET)))] + text[i + 1:]
    if rng.random() < 0.15:
        mask = '*' + mask
    if rng.random() < 0.15:
        mask = mask + '*'
    return mask, text


shared = [shared_pair() for _ in range(600)]
shared_expect = [fnmatch.fnmatchcase(t, m) for m, t in shared]
hits = sum(shared_expect)
assert 120 < hits < 480, hits

# hand tables: (mask, text, case_sensitive, expected)
hand = [
    # escapes
    ('a\\*b', 'a*b', True, True), ('a\\*b', 'aXb', True, False), ('a\\?b', 'a?b', True, True), ('a\\?b', 'aXb', True, False),
    ('\\[a\\]', '[a]', True, True), ('\\[a\\]', 'a', True, False), ('[\\]]', ']', True, True), ('[\\]]', 'a', True, False),
    ('[a\\-c]', '-', True, True), ('[a\\-c]', 'b', True, False), ('[a\\-c]', 'c', True, True), ('\\\\', '\\', True, True),
    ('\\a', 'a', True, True), ('*\\.txt', 'notes.txt', True, True), ('*\\.txt', 'notestxt', True, False),
    # negation with ^ as well as !
    ('[^abc]', 'x', True, True), ('[^abc]', 'a', True, False), ('[!abc]', 'x', True, True), ('[!abc]', 'c', True, False),
    ('[^a-c]x', 'dx', True, True), ('[^a-c]x', 'bx', True, False),
    # leading ] and dashes in sets
    ('[]a]', ']', True, True), ('[]a]', 'a', True, True), ('[]a]', 'b', True, False), ('[!]a]', ']', True, False),
    ('[!]a]', 'b', True, True), ('[a-]', '-', True, True), ('[a-]', 'a', True, True), ('[a-]', 'b', True, False),
    ('[-a]', '-', True, True), ('[-a]', 'a', True, True), ('[a-c-e]', 'd', True, False), ('[a-c-e]', '-', True, True),
    # star backtracking and edges
    ('', '', True, True), ('', 'a', True, False), ('*', '', True, True), ('?', '', True, False), ('**', 'abc', True, True),
    ('**a**', 'bab', True, True), ('*a*b*c', 'xaybzc', True, True), ('*a*b*c', 'xaybz', True, False), ('a*b*c', 'abbbc', True, True),
    ('a*aab', 'aaaab', True, True), ('a*aab', 'aaab', True, True), ('a*aab', 'aab', True, False),
    ('*abc', 'abcabc', True, True), ('*abc', 'abcab', True, False), ('a?c', 'abc', True, True), ('a?c', 'ac', True, False),
    ('*?', 'a', True, True), ('*?', '', True, False), ('?*?', 'ab', True, True), ('?*?', 'a', True, False),
    # UTF-8: ? and sets are code points
    ('?', 'é', True, True), ('??', 'é', True, False), ('caf?', 'café', True, True), ('caf?', 'cafe', True, True), ('caf??', 'café', True, False),
    ('?', '日', True, True), ('???', '日本語', True, True), ('?', '日本語', True, False), ('*', '日本語', True, True),
    ('[é-ü]', 'ê', True, True), ('[é-ü]', 'e', True, False), ('[日本]', '本', True, True), ('[^日本]', '語', True, True),
    ('*語', '日本語', True, True), ('日*', '日本語', True, True), ('é', 'é', True, True), ('é', 'e', True, False),
    # case folding: ASCII only
    ('*.TXT', 'readme.txt', False, True), ('*.TXT', 'readme.txt', True, False), ('[A-C]x', 'bx', False, True), ('[A-C]x', 'bx', True, False),
    ('[a-c]x', 'Bx', False, True), ('[a-c]x', 'Bx', True, False), ('ABC', 'abc', False, True), ('ABC', 'abd', False, False),
    ('É', 'é', False, False), ('É', 'É', False, True), ('[!A]', 'a', False, False), ('[!A]', 'b', False, True), ('\\A', 'a', False, True),
]
lists = [
    ('*.c;*.h', 'x.h', True, True), ('*.c;*.h', 'x.o', True, False), ('*.c;*.h', 'x.c', True, True), ('a\\;b', 'a;b', True, True),
    ('a\\;b', 'a', True, False), ('', '', True, True), (';', '', True, True), ('a;', 'a', True, True), (';a', '', True, True),
    ('*.TXT;*.MD', 'r.md', False, True), ('*.TXT;*.MD', 'r.md', True, False), ('[a\;b]', ';', True, True), ('x', 'x', True, True),
]
invalid_masks = ['[abc', '[', '[!', '[^', '[]', '[!]', 'abc\\', '\\', '[c-a]', '[a-', 'a[', 'x[bc', '[a-c', '[\\', '[a\\', 'a*[']
list_invalid = ['*.c;[', '[;a]', 'a\\']
valid_odd = ['[a-]', '[-a]', '[]a]', '[!]a]', '[a-c-e]', '[\\]]', '[^a]', '*', '?', '', '\\\\', '[[]', '[a-a]']

L = []


def table(name, rows, fn):
    L.append('    let %s_masks = [%d]str{ %s }' % (name, len(rows), ', '.join(quote(r[0]) for r in rows)))
    L.append('    let %s_texts = [%d]str{ %s }' % (name, len(rows), ', '.join(quote(r[1]) for r in rows)))
    L.append('    let %s_cs = [%d]bool{ %s }' % (name, len(rows), ', '.join('true' if r[2] else 'false' for r in rows)))
    L.append('    let %s_want = [%d]bool{ %s }' % (name, len(rows), ', '.join('true' if r[3] else 'false' for r in rows)))
    L.append('    var %s_i = 0usize' % name)
    L.append('    while %s_i < %d {' % (name, len(rows)))
    L.append('        let (%s_hit, %s_error) = mask.%s(%s_masks[%s_i], %s_texts[%s_i], %s_cs[%s_i])' % (name, name, fn, name, name, name, name, name, name))
    L.append('        if %s_error != ok || %s_hit != %s_want[%s_i] { try report("%s", %s_i) }' % (name, name, name, name, name, name))
    L.append('        %s_i += 1usize' % name)
    L.append('    }')


chunks = [shared[i:i + 100] for i in range(0, 600, 100)]
for k, chunk in enumerate(chunks):
    rows = [(m, t, True, shared_expect[k * 100 + j]) for j, (m, t) in enumerate(chunk)]
    table('shared%d' % k, rows, 'matches')
table('hand', hand, 'matches')
table('list', lists, 'matches_any')
# every mask is refused by valid and by matches (even when matching would fail early), and the odd-but-valid
# ones are accepted
L.append('    let invalid_masks = [%d]str{ %s }' % (len(invalid_masks), ', '.join(quote(m) for m in invalid_masks)))
L.append('    var invalid_i = 0usize')
L.append('    while invalid_i < %d {' % len(invalid_masks))
L.append('        let (invalid_hit, invalid_error) = mask.matches(invalid_masks[invalid_i], "zzz", true)')
L.append('        if invalid_error != mask.Invalid || invalid_hit || mask.valid(invalid_masks[invalid_i]) != mask.Invalid { try report("invalid", invalid_i) }')
L.append('        let (invalid_empty_hit, invalid_empty_error) = mask.matches(invalid_masks[invalid_i], "", true)')
L.append('        if invalid_empty_error != mask.Invalid || invalid_empty_hit { try report("invalid-empty", invalid_i) }')
L.append('        invalid_i += 1usize')
L.append('    }')
L.append('    let list_invalid = [%d]str{ %s }' % (len(list_invalid), ', '.join(quote(m) for m in list_invalid)))
L.append('    var list_invalid_i = 0usize')
L.append('    while list_invalid_i < %d {' % len(list_invalid))
L.append('        let (list_hit, list_error) = mask.matches_any(list_invalid[list_invalid_i], "a", true)')
L.append('        if list_error != mask.Invalid || list_hit { try report("list-invalid", list_invalid_i) }')
L.append('        list_invalid_i += 1usize')
L.append('    }')
L.append('    let valid_odd = [%d]str{ %s }' % (len(valid_odd), ', '.join(quote(m) for m in valid_odd)))
L.append('    var valid_i = 0usize')
L.append('    while valid_i < %d {' % len(valid_odd))
L.append('        if mask.valid(valid_odd[valid_i]) != ok { try report("valid-odd", valid_i) }')
L.append('        valid_i += 1usize')
L.append('    }')
body = '\n'.join(L)
source = '''// e.text.mask against Python's fnmatch on the shared syntax (600 seeded pairs) and hand tables for
// escapes, ^ negation, ASCII case folding, UTF-8 code points, ; lists and malformed masks (L076, D2266;
// scripts/text_mask_reference.py writes this file). A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.text.mask

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 48u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = 48u8 + u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("text mask mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i] - 48u8)..usize(digits[i] - 48u8) + 1usize])
    }
    try io.print("\\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("text mask ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'text_mask' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
for m, t, cs, want in hand:
    if cs and chr(92) not in m and '^' not in m and fnmatch.fnmatchcase(t, m) != want:
        print('hand case differs from fnmatch (check by hand):', repr(m), repr(t), want)
print('wrote text_mask: %d shared (%d match), %d hand, %d list, %d invalid' % (len(shared), hits, len(hand), len(lists), len(invalid_masks)))
