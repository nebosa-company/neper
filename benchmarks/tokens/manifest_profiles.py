# The tokenizer profiles a build names (D1551, C051): each committed profile's
# encoding, grammar revision and SHA-256 (of its canonical JSON), as the
# `tokenizer_profiles` member the build manifest carries, so a manifest says which
# token-cost tables describe the grammar it was built under. Reads the profiles
# only (no tokenizer needed).
#
#   python benchmarks/tokens/manifest_profiles.py           # print the member
#   python benchmarks/tokens/manifest_profiles.py --check   # src/tool.e writes it, for this grammar
import hashlib, json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

def member():
    with open(os.path.join(root, 'docs', 'grammar.ebnf'), encoding='utf-8') as f:
        revision = int(re.search(r'revision (\d+)', f.readline()).group(1))
    entries = []
    for name in sorted(os.listdir(here)):
        if not (name.startswith('profile-') and name.endswith('.json')):
            continue
        with open(os.path.join(here, name), 'rb') as f:
            data = f.read()
        profile = json.loads(data)
        if profile['grammar_revision'] != revision:
            sys.exit('manifest_profiles.py: %s is of grammar revision %d, the grammar is %d; rerun profile.py'
                     % (name, profile['grammar_revision'], revision))
        # The digest is of the profile's canonical JSON (sorted keys, no spaces),
        # so a checkout's line endings do not move it.
        canonical = json.dumps(profile, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
        entries.append('{"encoding":"%s","grammar_revision":%d,"sha256":"%s"}'
                       % (profile['tokenizer']['encoding'], revision, hashlib.sha256(canonical).hexdigest()))
    return '"tokenizer_profiles":[' + ','.join(entries) + '],'

if __name__ == '__main__':
    text = member()
    if '--check' not in sys.argv[1:]:
        print(text)
        sys.exit(0)
    with open(os.path.join(root, 'src', 'tool.e'), encoding='utf-8') as f:
        source = f.read()
    # The member is written as one Neper string literal, its quotes escaped.
    if text.replace('"', '\\"') not in source:
        sys.exit('manifest_profiles.py: src/tool.e does not write\n  %s' % text)
    print('src/tool.e writes the tokenizer profiles: %s' % text)
