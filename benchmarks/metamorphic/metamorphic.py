"""Metamorphic tests of the compiler (D438, H10).

    python benchmarks/metamorphic/metamorphic.py COMPILER ROOT ARCH OS OUTDIR FIXTURE_MAIN...

Five transformations that must not change what a program does, applied to each
fixture's root module and checked against the untouched build:

- `comments`: every comment is removed through the lossless token stream, the
  lines and columns kept, so the image -- debug and release, whose line tables
  name the lines -- must be byte-identical to the original's.
- `reorder`: the top-level declarations after the `use` lines are put in reverse
  order; spec section 14 makes module scope order-independent, so the image may
  differ (functions are laid out in declaration order) but the program must exit
  with the same code and write the same bytes to stdout.
- `renamed` (D477, D484): every local and parameter is renamed to a name of
  the same length through the index's symbols and references, so the columns
  are unchanged and the image must be byte-identical.
- `fields` (D477): every `struct { ... }` has its fields reversed; the layout
  changes, so the image may differ, but the program must behave the same.
- `symbols` (D478): every function but `main` and every type is renamed to a
  name of the same length through the index's declaration and reference spans
  (a protocol pair such as `Rec`/`rec_cmp` kept); the names reach the image in
  its trap messages and backtraces, so with them put back it must be
  byte-identical, and the program must behave the same.

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


def renamed(main, index_json_lines, keywords, spelled):
    """Every local and parameter of the root module renamed to a name of the same
    length through the index's `local` and `parameter` symbols and the references
    that target them (D477, D484): the columns are unchanged, so the image must be
    byte-identical. A reference the index missed is a build that fails.
    """
    import json
    text = open(main, 'rb').read()
    symbols, spans = {}, []
    for line in index_json_lines:
        record = json.loads(line)
        if record.get('record') == 'symbol' and record['kind'] in ('local', 'parameter') and record['module'] == 'main' and record.get('selection_span'):
            symbols[record['id']] = record['name'].encode()
            s = record['selection_span']
            spans.append((s['byte_start'], s['byte_end'], record['id']))
        if record.get('record') == 'reference' and record.get('target_id') in symbols and record['role'] in ('read', 'write', 'call', 'address'):
            s = record['source_span']
            if text[s['byte_start']:s['byte_end']] == symbols[record['target_id']]:
                spans.append((s['byte_start'], s['byte_end'], record['target_id']))
    new_names = {sid: same_length_name(name, keywords, spelled) for sid, name in symbols.items()}
    out = bytearray(text)
    for s, e, sid in sorted(set(spans), reverse=True):
        if new_names[sid] != symbols[sid]:
            out[s:e] = new_names[sid]
    return bytes(out)


def same_length_name(name, keywords, spelled):
    """`name` with each letter shifted, again past a keyword or a name the module
    spells; the result is reserved so no two symbols meet."""
    for times in range(1, 26):
        out = bytearray()
        for ch in name:
            if 97 <= ch <= 122:
                out.append((ch - 97 + times) % 26 + 97)
            elif 65 <= ch <= 90:
                out.append((ch - 65 + times) % 26 + 65)
            else:
                out.append(ch)
        candidate = bytes(out)
        if candidate != name and candidate.decode() not in keywords and candidate not in spelled:
            spelled.add(candidate)
            return candidate
    return name


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


def index_of(main):
    p = run([compiler, 'index-file', main, root, arch, host_os, '--json'])
    if p.returncode != 0:
        sys.exit('metamorphic: index-file of %s failed' % main)
    return p.stdout.decode('utf-8').splitlines()


def symbols_renamed(main, index_json_lines, keywords, spelled):
    """Every function but `main` and every type of the root module renamed to a name
    of the same length through the index's declaration and reference spans (D478,
    H10). The names reach the image -- the trap messages and backtraces carry
    them -- so it must be byte-identical once they are put back.
    """
    import json
    text = open(main, 'rb').read()
    symbols, spans = {}, []
    for line in index_json_lines:
        record = json.loads(line)
        if record.get('record') == 'symbol' and record['kind'] in ('fn', 'type') and record['module'] == 'main' and record['name'] != 'main' and record.get('selection_span'):
            symbols[record['id']] = (record['kind'], record['name'].encode())
            s = record['selection_span']
            spans.append((s['byte_start'], s['byte_end'], record['id']))
        if record.get('record') == 'reference' and record.get('target_id') in symbols and record['role'] in ('call', 'type', 'read'):
            s = record['source_span']
            if text[s['byte_start']:s['byte_end']] == symbols[record['target_id']][1]:
                spans.append((s['byte_start'], s['byte_end'], record['target_id']))
    # A protocol function is named after its type (`rec_cmp` for `Rec`): the pair
    # is a name the checker reads, so both keep theirs.
    def snake(name):
        out = bytearray()
        for i, ch in enumerate(name):
            if 65 <= ch <= 90:
                if i:
                    out.append(95)
                out.append(ch + 32)
            else:
                out.append(ch)
        return bytes(out)
    bound = set()
    for sid, (kind, name) in symbols.items():
        if kind != 'type':
            continue
        for other, (other_kind, other_name) in symbols.items():
            if other_kind == 'fn' and other_name.startswith(snake(name) + b'_'):
                bound.add(sid)
                bound.add(other)
    new_names = {}
    for sid, (kind, name) in symbols.items():
        if sid in bound:
            continue
        candidate = same_length_name(name, keywords, spelled)
        if candidate != name:
            new_names[sid] = candidate
    out = bytearray(text)
    for s, e, sid in sorted(set(spans), reverse=True):
        if sid in new_names:
            out[s:e] = new_names[sid]
    renames = {new: symbols[sid][1] for sid, new in new_names.items()}
    return bytes(out), renames


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
    index = index_of(original_main)
    text = open(original_main, 'rb').read()
    spelled = set()
    for line in tokens:
        record = json.loads(line)
        if record.get('record') == 'token' and record['kind'] == 'IDENTIFIER':
            spelled.add(text[record['span']['byte_start']:record['span']['byte_end']])
    aliased = variant_dir(fixture_dir, name + '-renamed')
    aliased_main = os.path.join(aliased, 'src', 'main.e')
    open(aliased_main, 'wb').write(renamed(original_main, index, KEYWORDS, set(spelled)))
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
    # symbols: byte-identical images once the names are put back, the same behaviour.
    resymbolled = variant_dir(fixture_dir, name + '-symbols')
    resymbolled_main = os.path.join(resymbolled, 'src', 'main.e')
    rewritten, renames = symbols_renamed(original_main, index, KEYWORDS, set(spelled))
    open(resymbolled_main, 'wb').write(rewritten)
    for release in (False, True):
        a = os.path.join(outdir, '%s-original-%d%s' % (name, release, exe))
        b = os.path.join(outdir, '%s-symbols-%d%s' % (name, release, exe))
        image = build(resymbolled_main, b, release)
        for new_name, old_name in renames.items():
            image = image.replace(new_name, old_name)
        if image != images[release]:
            sys.exit('metamorphic: %s with renamed symbols builds a different %s image' % (name, 'release' if release else 'debug'))
        ran_a, ran_b = run([a], cwd=outdir), run([b], cwd=outdir)
        if (ran_a.returncode, ran_a.stdout) != (ran_b.returncode, ran_b.stdout):
            sys.exit('metamorphic: %s with renamed symbols behaves differently (%d vs %d)' % (name, ran_a.returncode, ran_b.returncode))
    print('metamorphic: %s holds under comments, reorder, renamed, fields and symbols' % name)
