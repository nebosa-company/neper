"""Generate tests/selfhost/fixtures/link/crypto_cms/src/main.e (L152, D2802).

Reference: OpenSSL (`openssl cms -sign`), run at generation time over fresh RSA-2048, P-256,
P-384 and Ed25519 keys with self-signed certificates: the DER SignedData blobs (attached
and detached, several digests, with and without signed attributes) are embedded and must
verify in `e.crypto.cms`; tampered content or signatures must not. `e.crypto.cms.sign_ed25519`
is deterministic, so its output is embedded as well, and this script checks it with
`openssl cms -verify` (the file `ours.hex`, written by a probe run of the signer, is the
input; without it the signer vector is omitted).

    CMS_WORK=<dir> python scripts/gen_cms_test.py [ours.hex]   (CMS_WORK keeps the keys between the
    first run, the probe run of the signer and the final run)
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'crypto_cms' / 'src' / 'main.e'
SIGN_TIME = 1767323045  # 2026-01-02T03:04:05Z
WORK = Path(os.environ['CMS_WORK']) if os.environ.get('CMS_WORK') else Path(tempfile.mkdtemp())
WORK.mkdir(parents=True, exist_ok=True)


def sh(*args, data=None):
    return subprocess.run(['openssl', *args], input=data, capture_output=True, check=True).stdout


def make_key(kind):
    p = WORK / ('%s.key' % kind)
    c = WORK / ('%s.crt' % kind)
    if p.exists() and c.exists():
        return p, c
    if kind == 'rsa':
        sh('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', str(p))
    elif kind == 'p256':
        sh('genpkey', '-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-256', '-out', str(p))
    elif kind == 'p384':
        sh('genpkey', '-algorithm', 'EC', '-pkeyopt', 'ec_paramgen_curve:P-384', '-out', str(p))
    else:
        sh('genpkey', '-algorithm', 'ED25519', '-out', str(p))
    sh('req', '-x509', '-new', '-key', str(p), '-subj', '/CN=Neper %s signer/O=Neper' % kind, '-days', '36500', '-out', str(c))
    return p, c


def cert_der(c):
    return sh('x509', '-in', str(c), '-outform', 'DER')


def cms_sign(key, crt, content, md=None, attached=False, noattr=False):
    args = ['cms', '-sign', '-binary', '-signer', str(crt), '-inkey', str(key), '-outform', 'DER']
    if attached:
        args.append('-nodetach')
    if noattr:
        args.append('-noattr')
    if md:
        args += ['-md', md]
    return sh(*args, data=content)


def cms_verify(crt, der, content=None):
    sig = WORK / 'v.der'
    sig.write_bytes(der)
    args = ['cms', '-verify', '-binary', '-inform', 'DER', '-in', str(sig), '-CAfile', str(crt), '-purpose', 'any', '-no_check_time', '-out', os.devnull]
    if content is not None:
        c = WORK / 'v.bin'
        c.write_bytes(content)
        args += ['-content', str(c)]
    return subprocess.run(['openssl', *args], capture_output=True).returncode == 0


content = b'Content-Type: text/plain\r\n\r\nHello, S/MIME. The quick brown fox.\r\n'
lines = []
keys = {}
for kind in ('rsa', 'p256', 'p384', 'ed25519'):
    keys[kind] = make_key(kind)

cases = [
    ('rsa', 'sha256', False, False), ('rsa', 'sha256', True, False), ('rsa', 'sha512', True, False), ('rsa', 'sha384', False, False),
    ('rsa', 'sha256', False, True), ('p256', 'sha256', False, False), ('p256', 'sha256', True, False), ('p256', 'sha512', False, False),
    ('p384', 'sha384', False, False), ('p384', 'sha384', True, False), ('ed25519', 'sha512', False, False), ('ed25519', 'sha512', True, False),
]
for kind, md, attached, noattr in cases:
    key, crt = keys[kind]
    der = cms_sign(key, crt, content, md=md, attached=attached, noattr=noattr)
    assert cms_verify(crt, der, None if attached else content), (kind, md, attached, noattr)
    tag = '%s-%s-%s%s' % (kind, md or 'default', 'attached' if attached else 'detached', '-noattr' if noattr else '')
    lines.append('V %s %d %s %s' % (tag, 1 if attached else 0, content.hex(), der.hex()))
    # tampered detached content (or attached content inside the blob) must fail
    if not attached:
        lines.append('%s %s %s %s' % ('N' if noattr else 'B', tag + '-badcontent', (content + b'!').hex(), der.hex()))
    flipped = bytearray(der)
    flipped[-1] ^= 1
    lines.append('S %s %d %s %s' % (tag + '-badsig', 1 if attached else 0, content.hex(), bytes(flipped).hex()))

# our signer
key, crt = keys['ed25519']
seed = sh('pkey', '-in', str(key), '-outform', 'DER')[-32:]
cert = cert_der(crt)
ours_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
ours_note = 'none'
for attached in (False, True):
    if ours_path and ours_path.exists():
        pass
if ours_path and ours_path.exists():
    hexes = ours_path.read_text().split()
    for attached, h in zip((False, True), hexes):
        der = bytes.fromhex(h)
        ok = cms_verify(crt, der, None if attached else content)
        print('openssl verifies our %s signature: %s' % ('attached' if attached else 'detached', ok))
        assert ok
        lines.append('O %d %s' % (1 if attached else 0, h))
    ours_note = 'embedded'
print('our signer vectors:', ours_note)

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn same_bytes(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check_line(line: str) -> u8 {
    var arena_buf: [262144]u8 = zero
    var a = mem.arena_from(arena_buf[0usize..262144usize])
    var der: [4096]u8 = zero
    var body: [256]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let k = kind[0usize]
    if k == 79u8 {
        // O attached hex: our Ed25519 signer reproduces the embedded DER and verifies
        let (att, p1) = tok(line, p0)
        let (h, p2) = tok(line, p1)
        let n = unhex(h, der[0usize..4096usize])
        var out: [4096]u8 = zero
        let (written, sign_error) = cms.sign_ed25519(&a, signed_content(), test_cert(), test_secret(), att[0usize] == 49u8, 1767323045i64, out[0usize..4096usize])
        if sign_error != ok { ret 1u8 }
        if !same_bytes(out[0usize..written], der[0usize..n]) { ret 2u8 }
        let (sd, parse_error) = cms.parse(&a, out[0usize..written])
        if parse_error != ok { ret 3u8 }
        if att[0usize] == 49u8 {
            if cms.verify(&a, &sd, "") != ok { ret 4u8 }
        } else {
            if cms.verify(&a, &sd, signed_content()) != ok { ret 5u8 }
        }
        ret 0u8
    }
    let (tag, p1) = tok(line, p0)
    if k == 66u8 || k == 78u8 {
        let (body_hex, p2) = tok(line, p1)
        let (der_hex, p3) = tok(line, p2)
        let bn = unhex(body_hex, body[0usize..256usize])
        let n = unhex(der_hex, der[0usize..4096usize])
        let (sd, parse_error) = cms.parse(&a, der[0usize..n])
        if parse_error != ok { ret 11u8 }
        let verdict = cms.verify(&a, &sd, body[0usize..bn])
        if k == 66u8 && verdict != cms.BadDigest { ret 12u8 }
        if k == 78u8 && verdict != cms.BadSignature { ret 13u8 }
        ret 0u8
    }
    let (att, p2) = tok(line, p1)
    let (body_hex, p3) = tok(line, p2)
    let (der_hex, p4) = tok(line, p3)
    let bn = unhex(body_hex, body[0usize..256usize])
    let n = unhex(der_hex, der[0usize..4096usize])
    let (sd, parse_error) = cms.parse(&a, der[0usize..n])
    if k == 83u8 {
        // a flipped signature byte: parse may succeed, verification must not
        if parse_error != ok { ret 0u8 }
        var detached: str = ""
        if att[0usize] != 49u8 { detached = body[0usize..bn] }
        if cms.verify(&a, &sd, detached) == ok { ret 21u8 }
        ret 0u8
    }
    if parse_error != ok { ret 31u8 }
    if sd.signers.len != 1usize { ret 32u8 }
    if att[0usize] == 49u8 {
        if !sd.has_content || !same_bytes(sd.content, body[0usize..bn]) { ret 33u8 }
        if cms.verify(&a, &sd, "") != ok { ret 34u8 }
    } else {
        if sd.has_content { ret 35u8 }
        if cms.verify(&a, &sd, body[0usize..bn]) != ok { ret 36u8 }
    }
    let (cert, found) = cms.signer_certificate(&sd, 0usize)
    if !found { ret 37u8 }
    ret 0u8
}

'''

cert_hex = cert.hex()
seed_hex = seed.hex()
extra = '''
fn signed_content() -> str {
    ret "''' + fc.neper_str(content.decode('latin-1')) + '''"
}

fn test_cert() -> []const u8 {
    ret cert_bytes()
}

'''
# the certificate and seed as byte-array functions
cert_fn_parts, cert_names = fc.vector_functions('cert_hex', [cert_hex])
extra += cert_fn_parts + '''
var cert_store: [2048]u8 = zero

fn cert_bytes() -> []const u8 {
    let n = unhex(cert_hex_0(), cert_store[0usize..2048usize])
    ret cert_store[0usize..n]
}

fn test_secret() -> sign.Ed25519SecretKey {
    var s: sign.Ed25519SecretKey = zero
    let h = "''' + seed_hex + '''"
    var i = 0usize
    while i < 32usize {
        s.bytes[i] = hexval(h[i * 2usize]) * 16u8 + hexval(h[i * 2usize + 1usize])
        i += 1usize
    }
    ret s
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // the embedded certificate parses and its issuer-and-serial matching is exercised below
    let (c, c_error) = x509.parse(a, cert_bytes())
    if c_error != ok { os.exit(101i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("crypto cms ok")
    ret ok
}
'''

src = ('// e.crypto.cms against OpenSSL: SignedData blobs from `openssl cms -sign` over RSA, P-256, P-384 and\n'
       '// Ed25519 keys (attached, detached, SHA-256/384/512, with and without signed attributes) verify; tampered\n'
       '// content or signatures do not; the Ed25519 signer is deterministic and its output (checked with\n'
       '// `openssl cms -verify` at generation) is reproduced byte for byte (D2802). V verify, B tampered content,\n'
       '// S tampered signature, O our signer. Generated by scripts/gen_cms_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.crypto.cms\nuse e.crypto.sign\nuse e.crypto.x509\n\n'
       + fc.PRELUDE + extra + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
