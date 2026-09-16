"""Metamorphic tests of the compiler (D438, H10).

    python benchmarks/metamorphic/metamorphic.py COMPILER ROOT ARCH OS OUTDIR FIXTURE_MAIN...

Four transformations that must not change what a program does, applied to each
fixture's root module and checked against the untouched build:

- `comments`: every comment is removed through the lossless token stream, the
  lines and columns kept, so the image -- debug and release, whose line tables
  name the lines -- must be byte-identical to the original's.
- `reorder`: the top-level declarations after the `use` lines are put in reverse
  order; spec section 14 makes module scope order-independent, so the image may
  differ (functions are laid out in declaration order) but the program must exit
  with the same code and write the same bytes to stdout.
- `renamed` (D477): every local -- a parameter, a `let`, a `var`, a `for`
  binding -- is renamed to a name of the same length through the token stream,
  so the columns are unchanged and the image must be byte-identical.
- `fields` (D477): every `struct { ... }` has its fields reversed; the layout
  changes, so the image may differ, but the program must behave the same.

Exit 1 on the first fixture whose transformed build differs, with what differed.
"""
import json, os, shutil, subprocess, sys

compiler, root, arch, host_os, outdir = sys.argv[1:6]
fixtures = sys.argv[6:]
os.makedirs(outdir, exist_ok=True)
exe = '.exe' if host_os == 'windows' else ''


def run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True)


def build(main, image, release):
    argv = [compiler, 'emit-executable', main, root, arch, host_os, image]
    if release:
        argv.append('--release')
    p = run(argv)
    if p.returncode != 0:
        sys.exit('metamorphic: build of %s failed: %s' % (main, p.stderr.decode('utf-8', 'replace')))
    if host_os != 'windows':
        os.chmod(image, 0o755)
    return open(image, 'rb').read()


def without_comments(main):
    p = run([compiler, 'tokens', main, '--json'])
    if p.returncode != 0:
        sys.exit('metamorphic: tokens of %s failed' % main)
    text = open(main, 'rb').read()
    cuts = []
    for line in p.stdout.decode('utf-8').splitlines():
        record = json.loads(line)
        if record.get('record') != 'token':
            continue
        for trivia in record['leading_trivia']:
            if trivia['kind'] == 'comment':
                cuts.append((trivia['span']['byte_start'], trivia['span']['byte_end']))
    out = bytearray(text)
    for start, end in sorted(cuts, reverse=True):
        del out[start:end]
    return bytes(out)


def reordered(main):
    lines = open(main, 'rb').read().split(b'\n')
    # The `use` lines and what precedes them stay; the rest is split at every line
    # that starts a declaration (column 1, not a comment or blank) and reversed.
    head = 0
    while head < len(lines) and (lines[head].startswith(b'use ') or lines[head].startswith(b'//') or lines[head].strip() == b''):
        head += 1
    blocks, current = [], []
    for line in lines[head:]:
        starts = line[:1] not in (b'', b' ', b'\t', b'}', b'/') and not line.startswith(b'//')
        if starts and current:
            blocks.append(current)
            current = []
        current.append(line)
    if current:
        blocks.append(current)
    blocks.reverse()
    return b'\n'.join(lines[:head] + [l for b in blocks for l in b])


def tokens_of(main):
    p = run([compiler, 'tokens', main, '--json'])
    if p.returncode != 0:
        sys.exit('metamorphic: tokens of %s failed' % main)
    return p.stdout.decode('utf-8').splitlines()


KEYWORDS = set('''fn let var ret if else while for in break continue use type error const struct union
enum true false nil ok zero undef extern unreachable shared own try defer switch case match as
and or not import pub mut static comptime test gpu when is do loop'''.split())


def renamed(main, tokens_json_lines):
    """Every local -- a parameter, a `let`, a `var`, a `for` binding -- renamed to a
    name of the same length, so the columns the line tables carry are unchanged and
    the image must be byte-identical (D477, H10). The rename shifts each letter by
    one (`z` to `a`), again if the result is a keyword or a name the module spells.
    """
    import json
    text = open(main, 'rb').read()
    toks = []
    for line in tokens_json_lines:
        record = json.loads(line)
        if record.get('record') == 'token':
            toks.append((record['kind'], record['span']['byte_start'], record['span']['byte_end']))
    spelled = set(text[s:e] for k, s, e in toks if k == 'IDENTIFIER')

    def shifted(name, times):
        out = bytearray()
        for ch in name:
            if 97 <= ch <= 122:
                out.append((ch - 97 + times) % 26 + 97)
            else:
                out.append(ch)
        return bytes(out)

    def new_name(name):
        for times in range(1, 26):
            candidate = shifted(name, times)
            if candidate != name and candidate.decode() not in KEYWORDS and candidate not in spelled:
                spelled.add(candidate)
                return candidate
        return name

    def spelling(i):
        k, s, e = toks[i]
        return text[s:e]

    edits = []
    i = 0
    while i < len(toks):
        if spelling(i) != b'fn':
            i += 1
            continue
        # The function runs to the `}` in column 1 that closes it.
        end = i + 1
        while end < len(toks) and not (spelling(end) == b'}' and text.rfind(b'\n', 0, toks[end][1]) == toks[end][1] - 1):
            end += 1
        locals_ = {}
        body_start = end
        j = i + 1
        # Parameters: `name:` inside the signature's parentheses, and `let`/`var`/`for` bindings.
        depth = 0
        while j < end:
            sp = spelling(j)
            kind = toks[j][0]
            if sp == b'(':
                depth += 1
            elif sp == b')':
                depth -= 1
            elif sp == b'{' and depth == 0 and j > i:
                body_start = j
                break
            elif kind == 'IDENTIFIER' and depth >= 1 and j + 1 < end and spelling(j + 1) == b':' and spelling(j - 1) in (b'(', b','):
                locals_[sp] = None
            j += 1
        while j < end:
            sp = spelling(j)
            if sp in (b'let', b'var', b'for'):
                k = j + 1
                if spelling(k) == b'(':
                    k += 1
                    while k < end and spelling(k) != b')':
                        if toks[k][0] == 'IDENTIFIER':
                            locals_[spelling(k)] = None
                        k += 1
                elif toks[k][0] == 'IDENTIFIER':
                    locals_[spelling(k)] = None
            j += 1
        for name in locals_:
            locals_[name] = new_name(name)
        j = i + 1
        while j < end:
            k, s, e = toks[j]
            sp = text[s:e]
            if k == 'IDENTIFIER' and sp in locals_ and locals_[sp] != sp:
                before = spelling(j - 1)
                after = spelling(j + 1) if j + 1 < len(toks) else b''
                field_access = before == b'.'
                literal_field = j > body_start and after == b':' and before in (b'{', b',')
                if not field_access and not literal_field:
                    edits.append((s, e, locals_[sp]))
            j += 1
        i = end + 1
    out = bytearray(text)
    for s, e, new in sorted(edits, reverse=True):
        out[s:e] = new
    return bytes(out)


def fields_reversed(main, tokens_json_lines):
    """Every `struct { ... }` of the module with its fields in reverse order (D477,
    H10): the layout changes, so the image may differ, but a struct is built and
    read by field name, so the program must behave the same.
    """
    import json
    text = open(main, 'rb').read()
    toks = []
    for line in tokens_json_lines:
        record = json.loads(line)
        if record.get('record') == 'token':
            toks.append((record['span']['byte_start'], record['span']['byte_end'], record['kind']))
    edits = []
    i = 0
    while i + 1 < len(toks):
        if text[toks[i][0]:toks[i][1]] != b'struct' or text[toks[i + 1][0]:toks[i + 1][1]] != b'{':
            i += 1
            continue
        # The fields between the braces, split at the commas of depth zero.
        j = i + 2
        depth = 0
        fields, start = [], j
        while j < len(toks):
            sp = text[toks[j][0]:toks[j][1]]
            if sp in (b'{', b'[', b'('):
                depth += 1
            elif sp in (b'}', b']', b')'):
                if depth == 0:
                    break
                depth -= 1
            elif sp == b',' and depth == 0:
                fields.append((start, j))
                start = j + 1
            j += 1
        if start < j:
            fields.append((start, j))
        # A field's span leaves the line breaks around it where they are.
        trimmed = []
        for a, b in fields:
            while a < b and toks[a][2] == 'NEWLINE':
                a += 1
            while b > a and toks[b - 1][2] == 'NEWLINE':
                b -= 1
            if a < b:
                trimmed.append((a, b))
        fields = trimmed
        if len(fields) > 1:
            spans = [(toks[a][0], toks[b - 1][1]) for a, b in fields]
            texts = [text[s:e] for s, e in spans]
            for (s, e), new in zip(spans, reversed(texts)):
                edits.append((s, e, new))
        i = j + 1
    out = bytearray(text)
    for s, e, new in sorted(edits, reverse=True):
        out[s:e] = new
    return bytes(out)


def variant_dir(fixture_dir, name):
    d = os.path.join(outdir, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(fixture_dir, d)
    return d


for main in fixtures:
    fixture_dir = os.path.dirname(os.path.dirname(os.path.abspath(main)))
    name = os.path.basename(fixture_dir)
    original = variant_dir(fixture_dir, name + '-original')
    original_main = os.path.join(original, 'src', 'main.e')
    images = {}
    for release in (False, True):
        images[release] = build(original_main, os.path.join(outdir, '%s-original-%d%s' % (name, release, exe)), release)
    # comments: byte-identical images.
    stripped = variant_dir(fixture_dir, name + '-comments')
    stripped_main = os.path.join(stripped, 'src', 'main.e')
    open(stripped_main, 'wb').write(without_comments(original_main))
    for release in (False, True):
        image = build(stripped_main, os.path.join(outdir, '%s-comments-%d%s' % (name, release, exe)), release)
        if image != images[release]:
            sys.exit('metamorphic: %s without comments builds a different %s image' % (name, 'release' if release else 'debug'))
    # reorder: the same behaviour.
    shuffled = variant_dir(fixture_dir, name + '-reorder')
    shuffled_main = os.path.join(shuffled, 'src', 'main.e')
    open(shuffled_main, 'wb').write(reordered(original_main))
    for release in (False, True):
        a = os.path.join(outdir, '%s-original-%d%s' % (name, release, exe))
        b = os.path.join(outdir, '%s-reorder-%d%s' % (name, release, exe))
        build(shuffled_main, b, release)
        ran_a, ran_b = run([a], cwd=outdir), run([b], cwd=outdir)
        if (ran_a.returncode, ran_a.stdout) != (ran_b.returncode, ran_b.stdout):
            sys.exit('metamorphic: %s reordered behaves differently (%d vs %d)' % (name, ran_a.returncode, ran_b.returncode))
    # renamed: byte-identical images.
    tokens = tokens_of(original_main)
    aliased = variant_dir(fixture_dir, name + '-renamed')
    aliased_main = os.path.join(aliased, 'src', 'main.e')
    open(aliased_main, 'wb').write(renamed(original_main, tokens))
    for release in (False, True):
        image = build(aliased_main, os.path.join(outdir, '%s-renamed-%d%s' % (name, release, exe)), release)
        if image != images[release]:
            sys.exit('metamorphic: %s with renamed locals builds a different %s image' % (name, 'release' if release else 'debug'))
    # fields: the same behaviour.
    turned = variant_dir(fixture_dir, name + '-fields')
    turned_main = os.path.join(turned, 'src', 'main.e')
    open(turned_main, 'wb').write(fields_reversed(original_main, tokens))
    for release in (False, True):
        a = os.path.join(outdir, '%s-original-%d%s' % (name, release, exe))
        b = os.path.join(outdir, '%s-fields-%d%s' % (name, release, exe))
        build(turned_main, b, release)
        ran_a, ran_b = run([a], cwd=outdir), run([b], cwd=outdir)
        if (ran_a.returncode, ran_a.stdout) != (ran_b.returncode, ran_b.stdout):
            sys.exit('metamorphic: %s with reversed fields behaves differently (%d vs %d)' % (name, ran_a.returncode, ran_b.returncode))
    print('metamorphic: %s holds under comments, reorder, renamed and fields' % name)
