"""Shared helpers for the lane-J library fixtures: vector chunking and the Neper prelude.

A fixture's expected values are embedded as line-oriented text in `fn vN() -> str`
chunks (a string literal per function keeps each under the emitter's literal limits),
so the compiled fixture needs no Python or file access at run time.
"""
import re

CHUNK = 3500


def neper_str(s):
    """A Neper string literal body for `s` (escapes backslash, quote and newline)."""
    out = []
    for ch in s:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        else:
            out.append(ch)
    return ''.join(out)


def vector_functions(prefix, lines):
    """`fn <prefix>_<i>() -> str` chunks and the list of their names."""
    chunks, cur, size = [], [], 0
    for line in lines:
        if cur and size + len(line) > CHUNK:
            chunks.append(cur)
            cur, size = [], 0
        cur.append(line)
        size += len(line) + 1
    if cur:
        chunks.append(cur)
    src, names = [], []
    for i, c in enumerate(chunks):
        name = '%s_%d' % (prefix, i)
        names.append(name)
        src.append('fn %s() -> str {\n    ret "%s"\n}\n' % (name, neper_str('\n'.join(c) + '\n')))
    return '\n'.join(src), names


PRELUDE = '''fn text_is(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn tok(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn dec(s: str) -> i64 {
    var v = 0i64
    var neg = false
    var i = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        neg = true
        i = 1usize
    }
    while i < s.len {
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    if neg { ret 0i64 - v }
    ret v
}

'''


def run_all(names, check):
    """Neper `fn run_vectors() -> u8` calling `check(line) -> u8` on every line of every chunk."""
    body = ['fn run_text(text: str) -> u8 {', '    var start = 0usize', '    var i = 0usize',
            '    while i < text.len {', '        if text[i] == 10u8 {',
            '            let code = %s(text[start..i])' % check,
            '            if code != 0u8 {', '                let shown = io.print(text[start..i])',
            '                if shown != ok { ret code }', '                ret code', '            }',
            '            start = i + 1usize',
            '        }', '        i += 1usize', '    }', '    ret 0u8', '}', '',
            'fn run_vectors() -> u8 {']
    for n in names:
        body.append('    let r_%s = run_text(%s())' % (n, n))
        body.append('    if r_%s != 0u8 { ret r_%s }' % (n, n))
    body.append('    ret 0u8')
    body.append('}')
    return '\n'.join(body) + '\n'
