# The tokenizer profile (D375, H26): what neper's lexical vocabulary costs in a model
# family's tokens, as data versioned with the grammar, so token cost is a design input.
#
#   python benchmarks/tokens/profile.py                       # write profile-<encoding>.json per family
#   python benchmarks/tokens/profile.py --measure --compiler build/neper-big.exe [--corpus DIR ...]
#
# A profile is one JSON object per model family (tiktoken's `cl100k_base` and
# `o200k_base` today, the encodings of the GPT-4 and GPT-4o/5 families; a family
# without a public tokenizer gets no invented profile): the grammar revision and the
# grammar's SHA-256, the tokenizer identity, and for every terminal of the grammar --
# keywords and operators -- plus the frequent composite forms of the language, the
# model-token count of that spelling at a line start and after a space. `--measure`
# then tokenizes the frozen corpus (tests/conformance/accept by default), counts the
# compiler's lexical tokens over it (`tokens --json`), and reports model tokens per
# lexical token, per non-comment line and per byte, and the share of the corpus's
# model tokens the profile's vocabulary predicts -- the R03 numbers, reproduced from
# the profile and the corpus rather than measured once and remembered.
import argparse, hashlib, json, os, re, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
parser = argparse.ArgumentParser()
parser.add_argument('--measure', action='store_true')
parser.add_argument('--compiler', default=None)
parser.add_argument('--corpus', action='append', default=None)
parser.add_argument('--encodings', default='cl100k_base,o200k_base')
args = parser.parse_args()

try:
    import tiktoken
except ImportError:
    sys.exit('profile.py: tiktoken is not installed (pip install tiktoken); no profile is invented without a tokenizer')

grammar_path = os.path.join(root, 'docs', 'grammar.ebnf')
with open(grammar_path, 'rb') as f:
    grammar_bytes = f.read()
grammar = grammar_bytes.decode('utf-8')
revision = int(re.search(r'revision (\d+)', grammar.splitlines()[0]).group(1))
production_text = '\n'.join(line for line in grammar.splitlines() if not line.startswith('#'))
terminals = sorted(set(re.findall(r'`([^`\s]+)`', production_text)))
# The composite forms a generator writes most: type spellings, signatures, the
# common statement heads. Added to the terminals so their cost is on the page.
COMPOSITES = ['[]const u8', '[]u8', '*const', '*mem.Arena', 'union enum u8', '-> err', '-> (i32, err)',
              'fn main(a: *mem.Arena, args: []str) -> err {', 'let (', 'ret ok', 'ret (', '0usize', '1usize',
              'u8', 'u32', 'u64', 'i32', 'i64', 'usize', 'f32', 'f64', 'bool', 'str', 'err',
              '@unsafe', '@nocheck {', '.len', '[..]', 'mem.alloc[u8](a, n)']

def cost(enc, spelling):
    # After a space the space is part of the first token, as it is in prose.
    return {'line_start': len(enc.encode(spelling)), 'after_space': len(enc.encode(' ' + spelling))}

profiles = {}
for name in args.encodings.split(','):
    enc = tiktoken.get_encoding(name)
    vocabulary = {}
    for spelling in terminals + COMPOSITES:
        vocabulary[spelling] = cost(enc, spelling)
    profile = {
        'schema': 'neper-tokenizer-profile', 'version': 1,
        'grammar_revision': revision, 'grammar_sha256': hashlib.sha256(grammar_bytes).hexdigest(),
        'tokenizer': {'library': 'tiktoken', 'encoding': name, 'vocabulary_size': enc.n_vocab},
        'vocabulary': vocabulary,
    }
    profiles[name] = (enc, profile)
    if not args.measure:
        path = os.path.join(here, 'profile-%s.json' % name)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(profile, f, indent=1, sort_keys=True)
            f.write('\n')
        single = sum(1 for v in vocabulary.values() if v['after_space'] == 1)
        print('wrote %s: %d spellings, %d of them one token after a space' % (os.path.relpath(path, root), len(vocabulary), single))

if not args.measure:
    sys.exit(0)

compiler = os.path.abspath(args.compiler or os.path.join(root, 'build', 'neper-big.exe'))
corpus_dirs = args.corpus or [os.path.join(root, 'tests', 'conformance', 'accept')]
files = []
for d in corpus_dirs:
    for dirpath, _, names in os.walk(d):
        for n in sorted(names):
            if n.endswith('.e'):
                files.append(os.path.join(dirpath, n))
if not files:
    sys.exit('profile.py: no .e files under the corpus')

def lexical(path):
    out = subprocess.run([compiler, 'tokens', '--json', path], capture_output=True, text=True, encoding='utf-8')
    records = [json.loads(l) for l in out.stdout.splitlines() if l.startswith('{"record":"token"')]
    return [(r['kind'], r['lexeme']) for r in records if r['kind'] not in ('NEWLINE', 'EOF')]

totals = {name: {'model': 0, 'predicted': 0, 'predictable': 0} for name in profiles}
lexical_total = 0
lines_total = 0
bytes_total = 0
for path in files:
    with open(path, 'rb') as f:
        data = f.read()
    text = data.decode('utf-8')
    bytes_total += len(data)
    lines_total += sum(1 for l in text.splitlines() if l.strip() and not l.lstrip().startswith('//'))
    tokens = lexical(path)
    lexical_total += len(tokens)
    for name, (enc, profile) in profiles.items():
        totals[name]['model'] += len(enc.encode(text))
        for kind, lexeme in tokens:
            v = profile['vocabulary'].get(lexeme)
            if v is not None:
                totals[name]['predicted'] += v['after_space']
                totals[name]['predictable'] += 1

print('corpus: %d files, %d bytes, %d non-comment lines, %d lexical tokens (grammar revision %d)' % (len(files), bytes_total, lines_total, lexical_total, revision))
for name, t in totals.items():
    print('%s: %d model tokens; %.2f per lexical token, %.2f per line, %.3f per byte; %d of %d lexical tokens are profile vocabulary, costing %d model tokens (%.0f%% of the corpus)' % (
        name, t['model'], t['model'] / lexical_total, t['model'] / lines_total, t['model'] / bytes_total,
        t['predictable'], lexical_total, t['predicted'], 100.0 * t['predicted'] / t['model']))
