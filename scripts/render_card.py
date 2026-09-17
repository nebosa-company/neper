"""Render current and language-versioned cards from the registries (D374, H28).

    python scripts/render_card.py            # write the current and versioned cards
    python scripts/render_card.py --check    # exit 1 when either committed card is not the render

The card's syntax sections are the grammar's own productions, copied from
docs/grammar.ebnf; its keyword list is every alphabetic terminal of that grammar; its
diagnostic families are docs/diagnostics.md's registry; documented commands are
marked from the compiler and suites; displayed grammar rules are marked from the
normative grammar; its versions are the ones the compiler writes in every stream
header (src/main.e). The prose around them is
docs/llm-neper-card.src.md. The rendered card carries the grammar revision, the
language and tool versions and a content hash, so a card and the grammar cannot
drift: the suites run --check.
"""
import glob, hashlib, json, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(*parts):
    with open(os.path.join(root, *parts), encoding='utf-8') as f:
        return f.read()

grammar = read('docs', 'grammar.ebnf')
revision = re.search(r'revision (\d+)', grammar.splitlines()[0]).group(1)
main_source = read('src', 'main.e')
tool_version = re.search(r'"tool_version\\":\\"([^\\]+)\\"', main_source).group(1)
language_version = re.search(r'"language_version\\":\\"([^\\]+)\\"', main_source).group(1)

# A production and its continuation lines, verbatim.
productions = {}
current = None
for line in grammar.splitlines():
    m = re.match(r'^([a-z_]+)\s*=', line)
    if m:
        current = m.group(1)
        productions[current] = [line]
    elif current and line.startswith(' ') and line.strip():
        productions[current].append(line)
    else:
        current = None

def block(names):
    out = []
    for name in names:
        out.extend(productions[name])
    return '\n'.join(out)

DECLARATIONS = ['top_decl', 'use_decl', 'attribute', 'type_decl', 'const_decl', 'var_decl', 'error_decl', 'fn_decl', 'extern_decl', 'signature', 'parameter', 'comptime_params', 'comptime_param', 'comptime_kind']
TYPES = ['type_rhs', 'resource_prefix', 'struct_type', 'union_type', 'enum_type', 'union_enum_type', 'field_decl', 'enum_member', 'union_member', 'type_expr', 'pointer_type', 'slice_type', 'array_type', 'function_type', 'named_type']
STATEMENTS = ['statement', 'binding_stmt', 'assignment_stmt', 'try_stmt', 'defer_stmt', 'if_stmt', 'while_stmt', 'for_stmt']
EXPRESSIONS = ['expression', 'postfix', 'postfix_part', 'primary', 'literal']
for name in DECLARATIONS + TYPES + STATEMENTS + EXPRESSIONS:
    if name not in productions:
        sys.exit('render_card: grammar.ebnf has no production %s' % name)

# Rule standing (D567, H11/H28) is deliberately narrower than broad parser-suite
# coverage: without a fixture-to-production map, the grammar proves that a displayed
# rule is present but not that the rule has direct executable evidence.
rule_rows = ['| rule | standing |', '|---|---|']
for name in DECLARATIONS + TYPES + STATEMENTS + EXPRESSIONS:
    rule_rows.append('| `%s` | present |' % name)
rules = '\n'.join(rule_rows)

# Keywords: the alphabetic terminals of the productions, not of the notation comments,
# and not `_`, which is a binding, nor lexer fragments of a number.
production_text = '\n'.join(line for line in grammar.splitlines() if not line.startswith('#'))
keywords = sorted(k for k in set(re.findall(r'`([a-z][a-z_]+)`', production_text)) if len(k) > 1)

codes = re.findall(r'^\| `(E-([A-Z]+)-(\d{4}))` \| ([^|]+) \|', read('docs', 'diagnostics.md'), re.M)
# Each code's standing (D440, H11/H28): `verified` when a conformance golden or a
# suite pins it, `present` when the compiler's source emits it and nothing pins it,
# `planned` when the registry alone names it. Read from the files, never declared.
goldens = ''.join(read(p) for p in sorted(glob.glob(os.path.join(root, 'tests', 'conformance', '**', '*.expected.jsonl'), recursive=True)))
suites = read('tests', 'selfhost', 'run.ps1') + read('tests', 'selfhost', 'run.sh')
sources = ''.join(read(p) for p in sorted(glob.glob(os.path.join(root, 'src', '*.e'))))
def standing(code):
    if '"code":"%s"' % code in goldens or code in suites:
        return 'verified'
    if code in sources:
        return 'present'
    return 'planned'
families = {}
for code, family, number, meaning in codes:
    families.setdefault(family, []).append((code, meaning.strip(), standing(code)))
def family_line(family, entries):
    counts = {}
    for code, meaning, state in entries:
        counts[state] = counts.get(state, 0) + 1
    parts = ', '.join('%d %s' % (counts[s], s) for s in ('verified', 'present', 'planned') if s in counts)
    unverified = ', '.join('`%s` %s' % (code, state) for code, meaning, state in entries if state != 'verified')
    line = '- `E-%s-*`: %d codes (%s); `%s` is the catch-all' % (family, len(entries), parts, entries[-1][0])
    if unverified:
        line += '; ' + unverified
    return line
diagnostics = '\n'.join(family_line(family, entries) for family, entries in sorted(families.items()))

# The compact card's command surface and its standing (D566, H11/H28), by the same
# rule as diagnostics: source plus suite is verified, source alone is present, and a
# documented command absent from the compiler is planned.
COMMANDS = ['index', 'tokens', 'parse', 'fmt', 'context-file', 'uses-file',
            'explain-file', 'plan-rename-file', 'plan-add-parameter-file',
            'plan-change-signature-file', 'plan-replace-expression-file',
            'apply-plan', 'test-impact-file', 'test-file', 'query-batch', 'check-file']
command_rows = ['| command | standing |', '|---|---|']
for command in COMMANDS:
    implemented = '"%s"' % command in main_source
    state = 'verified' if implemented and command in suites else ('present' if implemented else 'planned')
    command_rows.append('| `%s` | %s |' % (command, state))
commands = '\n'.join(command_rows)

# The token cost of the grammar's terminals per public tokenizer (D429, H26), from the
# profiles D375 writes: every profile must be of this grammar revision, or the card
# would state a cost the grammar no longer has.
PROFILES = ['cl100k_base', 'o200k_base']
SAMPLES = [('keyword (`fn`, `let`, `ret`, ...)', None), ('`usize`', 'usize'), ('`i32` / `u8` / `f64`', 'i32'),
           ('`1usize`', '1usize'), ('`[]u8`', '[]u8'), ('`[]const u8`', '[]const u8'),
           ('`->`, `==`, `+=`, `..`', '->')]
profiles = {}
for encoding in PROFILES:
    profile = json.loads(read('benchmarks', 'tokens', 'profile-%s.json' % encoding))
    if str(profile.get('grammar_revision')) != revision:
        sys.exit('render_card: benchmarks/tokens/profile-%s.json is of grammar revision %s, not %s: re-run benchmarks/tokens/profile.py' % (encoding, profile.get('grammar_revision'), revision))
    profiles[encoding] = profile['vocabulary']
rows = ['| terminal | ' + ' | '.join(PROFILES) + ' |', '|---|' + '---|' * len(PROFILES)]
for label, sample in SAMPLES:
    cells = []
    for encoding in PROFILES:
        vocabulary = profiles[encoding]
        if sample is None:
            costs = sorted(set(vocabulary[k]['after_space'] for k in keywords if k in vocabulary))
            cells.append('%d' % costs[0] if len(costs) == 1 else '%d-%d' % (costs[0], costs[-1]))
        else:
            cells.append('%d' % vocabulary[sample]['after_space'])
    rows.append('| %s | %s |' % (label, ' | '.join(cells)))
token_costs = '\n'.join(rows)

template = read('docs', 'llm-neper-card.src.md')
body = template
for key, value in [
    ('{{revision}}', revision), ('{{language_version}}', language_version), ('{{tool_version}}', tool_version),
    ('{{keywords}}', ' '.join('`%s`' % k for k in keywords)),
    ('{{rules}}', rules),
    ('{{declarations}}', block(DECLARATIONS)), ('{{types}}', block(TYPES)),
    ('{{statements}}', block(STATEMENTS)), ('{{expressions}}', block(EXPRESSIONS)),
    ('{{diagnostics}}', diagnostics), ('{{commands}}', commands), ('{{token_costs}}', token_costs),
]:
    body = body.replace(key, value)
if '{{' in body:
    sys.exit('render_card: an unfilled placeholder: %s' % re.search(r'\{\{[^}]*\}\}', body).group(0))
digest = hashlib.sha256(body.encode('utf-8')).hexdigest()
card = ('<!-- generated by scripts/render_card.py from docs/grammar.ebnf revision %s, language %s, tool %s; content sha256 %s. Do not edit: edit docs/llm-neper-card.src.md and re-render. -->\n' % (revision, language_version, tool_version, digest)) + body

names = ['llm-neper-card.md', 'llm-neper-card-%s.md' % language_version]
if '--check' in sys.argv:
    for name in names:
        path = os.path.join(root, 'docs', name)
        if not os.path.exists(path) or read('docs', name) != card:
            print('render_card: docs/%s is not the render of grammar.ebnf revision %s; run python scripts/render_card.py' % (name, revision))
            sys.exit(1)
    print('cards current: language %s, grammar revision %s, sha256 %s' % (language_version, revision, digest[:12]))
else:
    for name in names:
        with open(os.path.join(root, 'docs', name), 'w', encoding='utf-8', newline='\n') as f:
            f.write(card)
    print('wrote %s (grammar revision %s, sha256 %s)' % (', '.join('docs/' + name for name in names), revision, digest[:12]))
