"""Embed trust roots into neperos/src/roots.e (D2246, C117) as hex, one function per set.

  python scripts/gen_roots.py            the fixture's test root (tests/selfhost/fixtures/neperos/net/ca.der)

The TLS client takes its roots as concatenated DER certificates; hex is the one encoding a Neper
string literal carries without escapes. The decoded bytes are the same whatever the source.
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
test_root = (root / 'tests/selfhost/fixtures/neperos/net/ca.der').read_bytes()
out = ['// Trust roots embedded by scripts/gen_roots.py (D2246). Do not edit by hand.',
       '// Each function is concatenated DER certificates as hex; roots.decode turns it into bytes.',
       '',
       '// The fixture\'s own root: the CA that signed the test server certificate (neper.test).',
       'fn test_root_hex() -> str { ret "%s" }' % test_root.hex(),
       '']
(root / 'neperos/src/roots.e').write_text('\n'.join(out), encoding='utf-8', newline='\n')
print('wrote neperos/src/roots.e', len(test_root), 'bytes of root')
