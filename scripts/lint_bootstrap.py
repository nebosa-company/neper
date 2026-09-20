#!/usr/bin/env python3
"""The bootstrap's rules for `src/` (D794), checked before the ten-minute build finds them.

The C bootstrap compiles `src/*.e` under a narrower language than neper-self: no
`else if`, no `-=`, a `>= CONST {` read as an aggregate literal, an array field of an
indexed slice element misaddressed, and `try` not lowered in a function answering a
tuple; `target`, `shared` and `when` are reserved locals in both. Each finding is
`path:line: rule: text`; exit 1 when any, and `--strict` counts the soft rules too.
Not checked: a module-scope function name shared with another module (`put`, `hex_digit` collided under the bootstrap while
`same` in seven modules does not, so the rule is not a name test), and a bare enum
member as a call argument in the enum's own module, which needs types.

    python scripts/lint_bootstrap.py [src]
"""
import re, sys, os

# A rule is hard, and fails the run, or soft: a shape the rule cannot tell from a
# harmless one, listed for a reader but not counted, unless `--strict`.
RULES = [
    ('else-if', re.compile(r'\belse\s+if\b'), "`else if` is not bootstrap syntax; nest the `if` in the `else` block"),
    ('minus-assign', re.compile(r'(?<![-<>=!])-=(?!=)'), "`-=` has no bootstrap lowering; write `x = x - y`"),
    ('const-compare-brace', re.compile(r'[<>]=?\s+[A-Z][A-Z0-9_]{2,}\s*\{'), "`> CONST {` is read as an aggregate literal; bind the constant to a local first"),
    ('reserved-local', re.compile(r'\b(?:let|var)\s+(?:target|shared|when)\b'), "`target`, `shared` and `when` are reserved names"),
]

def strip(line):
    """The line without its comment and with string literals blanked."""
    out, i, quote = [], 0, None
    while i < len(line):
        c = line[i]
        if quote:
            if c == '\\':
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c == '"' or c == "'":
            quote = c
            out.append(' ')
            i += 1
            continue
        if line.startswith('//', i):
            break
        out.append(c)
        i += 1
    return ''.join(out)

SOFT = [
    ('indexed-element-field-index', re.compile(r'\b\w+\[[^\[\]]+\]\.\w+\[(?![^\]]*\.\.)'), "an array field of an indexed element is misaddressed under the bootstrap; take `let e = &xs[i]` first (a slice field indexed this way is fine, and the rule cannot tell them apart)"),
]

def lint(root, strict):
    findings, notes = [], []
    for name in sorted(os.listdir(root)):
        if not name.endswith('.e'):
            continue
        path = os.path.join(root, name)
        with open(path, encoding='utf-8') as f:
            lines = f.read().split('\n')
        tuple_fn, depth = False, 0
        for number, raw in enumerate(lines, 1):
            line = strip(raw)
            head = re.match(r'fn\s+(\w+)\s*(\[[^\]]*\])?\s*\(', line)
            if head and not raw.startswith(' '):
                tuple_fn = bool(re.search(r'\)\s*->\s*\(', line))
                depth = 0
            for rule, pattern, why in RULES:
                if pattern.search(line):
                    findings.append(f'{path}:{number}: {rule}: {why}')
            for rule, pattern, why in SOFT:
                if pattern.search(line):
                    (findings if strict else notes).append(f'{path}:{number}: {rule}: {why}')
            if tuple_fn and re.search(r'\btry\b', line):
                findings.append(f'{path}:{number}: try-in-tuple: `try` is not lowered in a function answering a tuple; test the error and `ret (zero, e)`')
            depth += line.count('{') - line.count('}')
            if depth <= 0 and head is None and line.strip() == '}':
                tuple_fn = False
    return findings, notes

if __name__ == '__main__':
    strict = '--strict' in sys.argv
    operands = [a for a in sys.argv[1:] if a != '--strict']
    root = operands[0] if operands else 'src'
    found, notes = lint(root, strict)
    for line in found:
        print(line)
    print(f'lint_bootstrap: {len(found)} finding(s), {len(notes)} soft note(s) in {root}' + ('' if strict or not notes else ' (--strict lists them)'))
    sys.exit(1 if found else 0)
