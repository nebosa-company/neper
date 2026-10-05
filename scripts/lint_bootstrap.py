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

Two rules are the crew's, not the bootstrap's (D1671): a crew worker's own function rows
follow the other workers' windows in one table, which no image comparison sees a scan
walk into. An instance scan starts at `check.own_rows`, not at the declarations' end,
and a walk over every function row from zero steps with `check.function_row`. The two
shapes are caught; a scan of another shape is the reviewer's.

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
    ('instance-scan', re.compile(r'\b(?:var|let)\s+\w+\s*=\s*(?:c|checker)\.signature_function_count\s*$|\b\w+\s*=\s*(?:c|checker)\.signature_function_count\s*\}|\bwhile\s+\w+\s*>\s*(?:c|checker)\.signature_function_count\b|\.function_count\s*-\s*\S*\.signature_function_count\b'), "an instance scan starts at `check.own_rows` (D1671): a crew worker's own rows follow the other workers' windows"),
]

# (D1671) A walk from zero over every function row, in the files a crew worker runs.
FUNCTION_SCAN = re.compile(r'\bwhile\s+(\w+)\s*<\s*(?:c|checker)\.function_count\b')
FUNCTION_SCAN_FILES = ('check.e', 'lower.e', 'em.e', 'main.e')

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
        recent = []
        for number, raw in enumerate(lines, 1):
            line = strip(raw)
            scan = FUNCTION_SCAN.search(line) if name in FUNCTION_SCAN_FILES else None
            if scan and any(re.search(r'\bvar\s+%s\s*=\s*0usize\b' % scan.group(1), p) for p in recent):
                findings.append(f'{path}:{number}: function-scan: a walk over every function row steps with `check.function_row` (D1671)')
            recent = (recent + [line])[-3:]
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
