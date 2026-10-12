"""Generate the net_grpctls fixture: the gRPC TLS dial helper against the TLS 1.3 server of `e.net.tls`.

The credentials (an Ed25519 chain for example.com and its PKCS#8 key) are copied from the `net_tls` fixture, whose
handshake is checked against OpenSSL there; this fixture adds the dial helper's own rules over loopback: ALPN `h2` only,
refusal of a server that offers only `http/1.1` or no ALPN, and refusal of a certificate that does not name the host.

    python scripts/grpctls_vectors.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_tls', 'src', 'main.e')
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpctls', 'src', 'main.e')

text = open(SOURCE, encoding='utf-8').read().replace('\r\n', '\n')
lines = []
for name in ('mid_der', 'leaf_der', 'leaf_pkcs8'):
    m = re.search(r'^    let %s = ".*"$' % name, text, re.M)
    if not m:
        raise SystemExit('credential %s not found in net_tls' % name)
    lines.append(m.group(0).strip().replace('let ', 'let ', 1))
credentials = '\n'.join(lines) + '\n'
# module scope constants are functions in Neper; keep them as locals of a function that returns them
template = open(os.path.join(ROOT, 'scripts', 'grpctls_fixture_template.e'), encoding='utf-8').read().replace('\r\n', '\n')
body = '''fn credentials_mid() -> str {
    %s
    ret mid_der
}

fn credentials_leaf() -> str {
    %s
    ret leaf_der
}

fn credentials_key() -> str {
    %s
    ret leaf_pkcs8
}
''' % tuple(lines)
out = template.replace('@@CREDENTIALS@@\n', body + '\n')
out = out.replace('leaf_der, private_key: leaf_pkcs8', 'credentials_leaf(), private_key: credentials_key()').replace('server_name, mid_der,', 'server_name, credentials_mid(),')
os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
with open(FIXTURE, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(out)
print('credentials of %d bytes -> net_grpctls' % len(credentials))
