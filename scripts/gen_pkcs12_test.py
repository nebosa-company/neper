"""Generate tests/selfhost/fixtures/link/crypto_pkcs12/src/main.e (L160, D2803).

Reference: `cryptography`'s PKCS #12 serializer and loader (OpenSSL 3): stores written with
`PrivateFormat.PKCS12.encryption_builder()` (PBES2 AES-256-CBC, PBKDF2-HMAC-SHA256, HMAC-SHA256
MAC) for RSA-2048, P-256 and Ed25519 keys with CA chains and friendly names, under ASCII and
non-ASCII passwords. The fixture reads each (MAC checked), compares keys, certificates and the
friendly name, and refuses a wrong password. `e.crypto.pkcs12.encode` is a pure function of
its inputs (salts and IVs are parameters): its output for fixed inputs is embedded and was
checked at generation with `cryptography.load_pkcs12` and `openssl pkcs12 -info`.

    P12_WORK=<dir> python scripts/gen_pkcs12_test.py [ours.hex]
"""
import datetime
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'crypto_pkcs12' / 'src' / 'main.e'
WORK = Path(os.environ['P12_WORK']) if os.environ.get('P12_WORK') else Path(tempfile.mkdtemp())
WORK.mkdir(parents=True, exist_ok=True)


def hx(b):
    return b.hex() or '-'


def der_children(data):
    """Top-level children of the outermost SEQUENCE of a DER blob (tag, length only)."""
    def header(at):
        tag = data[at]
        n = data[at + 1]
        at += 2
        if n & 0x80:
            c = n & 0x7F
            n = int.from_bytes(data[at:at + c], 'big')
            at += c
        return tag, at, n
    tag, at, n = header(0)
    end = at + n
    kids = 0
    while at < end:
        _, body, length = header(at)
        at = body + length
        kids += 1
    return kids


def make(kind, cn, issuer_key=None, issuer_name=None):
    cache = WORK / (cn.replace(' ', '_') + '.pkcs8')
    if kind == 'rsa':
        gen = lambda: rsa.generate_private_key(public_exponent=65537, key_size=2048)
        algo = hashes.SHA256()
    elif kind == 'ec':
        gen = lambda: ec.generate_private_key(ec.SECP256R1())
        algo = hashes.SHA256()
    else:
        gen = lambda: ed25519.Ed25519PrivateKey.generate()
        algo = None
    if cache.exists():
        key = serialization.load_der_private_key(cache.read_bytes(), None)
    else:
        key = gen()
        cache.write_bytes(key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    when = datetime.datetime(2026, 1, 1)
    signer = issuer_key or key
    sign_algo = algo if issuer_key is None else (hashes.SHA256() if not isinstance(issuer_key, ed25519.Ed25519PrivateKey) else None)
    cert_cache = WORK / (cn.replace(' ', '_') + '.crt')
    if cert_cache.exists():
        cert = x509.load_der_x509_certificate(cert_cache.read_bytes())
    else:
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(issuer_name or name).public_key(key.public_key())
                .serial_number(1000 + len(cn)).not_valid_before(when).not_valid_after(when + datetime.timedelta(days=3650))
                .sign(signer, sign_algo))
        cert_cache.write_bytes(cert.public_bytes(serialization.Encoding.DER))
    return key, cert, name


lines = []
cases = [('rsa', 'password', 'rsa key'), ('ec', 'pässwörd€', 'ec key'), ('ed', 'x\U0001F600y', 'ed key'), ('ec', '', 'no password')]
for kind, password, friendly in cases:
    ca_key, ca_cert, ca_name = make('ec', 'CA of %s' % friendly)
    key, cert, _ = make(kind, 'leaf %s' % friendly, ca_key, ca_name)
    if password:
        enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
               .kdf_rounds(2048).key_cert_algorithm(pkcs12.PBES.PBESv2SHA256AndAES256CBC)
               .hmac_hash(hashes.SHA256()).build(password.encode('utf-8')))
    else:
        enc = serialization.NoEncryption()
    blob = pkcs12.serialize_key_and_certificates(friendly.encode(), key, cert, [ca_cert], enc)
    back = pkcs12.load_pkcs12(blob, password.encode('utf-8'))
    assert back.cert.certificate == cert
    pkcs8 = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    certs = [cert.public_bytes(serialization.Encoding.DER), ca_cert.public_bytes(serialization.Encoding.DER)]
    lines.append('R %d %s %s %s %s %s' % (1 if der_children(blob) == 3 else 0, hx(password.encode('utf-8')), hx(friendly.encode()), hx(pkcs8), ' '.join(hx(c) for c in certs), hx(blob)))

# our writer: fixed inputs
ours_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
key, cert, _ = make('ec', 'ours leaf')
ca_key, ca_cert, _ = make('ec', 'ours ca')
pkcs8 = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
chain = [cert.public_bytes(serialization.Encoding.DER), ca_cert.public_bytes(serialization.Encoding.DER)]
PARAMS = {'key_salt': bytes(range(16)), 'key_iv': bytes(range(16, 32)), 'cert_salt': bytes(range(32, 48)),
          'cert_iv': bytes(range(48, 64)), 'mac_salt': bytes(range(64, 80)), 'iterations': 2048}
OURS_PASSWORD = 'neper'
OURS_NAME = 'neper test'
if ours_path and ours_path.exists():
    blob = bytes.fromhex(ours_path.read_text().strip())
    back = pkcs12.load_pkcs12(blob, OURS_PASSWORD.encode())
    assert back.cert.certificate == cert, 'cryptography does not read our PKCS#12 leaf'
    assert [c.certificate for c in back.additional_certs] == [ca_cert]
    assert back.key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()) == pkcs8
    p = WORK / 'ours.p12'
    p.write_bytes(blob)
    r = subprocess.run(['openssl', 'pkcs12', '-in', str(p), '-passin', 'pass:' + OURS_PASSWORD, '-info', '-noout'], capture_output=True, text=True)
    print('openssl pkcs12 -info on our file:', r.returncode, (r.stderr.strip().splitlines() or [''])[0:3])
    assert r.returncode == 0
    lines.append('O %s' % hx(blob))
    print('our writer vector embedded')

vec, names = fc.vector_functions('v', lines)

# the inputs of the writer are constants in the fixture
const_src = '''
fn ours_pkcs8() -> str {
    ret "%s"
}

fn ours_cert0() -> str {
    ret "%s"
}

fn ours_cert1() -> str {
    ret "%s"
}
''' % (hx(pkcs8), hx(chain[0]), hx(chain[1]))

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

var password_buf: [64]u8 = zero
var name_buf: [64]u8 = zero
var key_buf: [2048]u8 = zero
var cert_a: [1024]u8 = zero
var cert_b: [1024]u8 = zero
var blob_buf: [12288]u8 = zero

fn check_line(a: *mem.Arena, line: str) -> u8 {
    let (kind, p0) = tok(line, 0usize)
    if kind[0usize] == 79u8 {
        // O: our writer reproduces the embedded file and it reads back
        let (blob_hex, p1) = tok(line, p0)
        let bn = unhex(blob_hex, blob_buf[0usize..12288usize])
        var key_der: [2048]u8 = zero
        let kn = unhex(ours_pkcs8(), key_der[0usize..2048usize])
        var c0: [1024]u8 = zero
        var c1: [1024]u8 = zero
        let n0 = unhex(ours_cert0(), c0[0usize..1024usize])
        let n1 = unhex(ours_cert1(), c1[0usize..1024usize])
        var chain: [2][]const u8 = zero
        chain[0usize] = c0[0usize..n0]
        chain[1usize] = c1[0usize..n1]
        var params: pkcs12.Params = zero
        var i = 0usize
        while i < 16usize {
            params.key_salt[i] = u8(i)
            params.key_iv[i] = u8(16usize + i)
            params.cert_salt[i] = u8(32usize + i)
            params.cert_iv[i] = u8(48usize + i)
            params.mac_salt[i] = u8(64usize + i)
            i += 1usize
        }
        params.iterations = 2048u32
        var out: [12288]u8 = zero
        let (n, e) = pkcs12.encode(a, key_der[0usize..kn], chain[0usize..2usize], "neper test", "neper", params, out[0usize..12288usize])
        if e != ok { ret 1u8 }
        if !same_bytes(out[0usize..n], blob_buf[0usize..bn]) { ret 2u8 }
        let (store, parse_error) = pkcs12.parse(a, out[0usize..n], "neper")
        if parse_error != ok { ret 3u8 }
        if store.keys.len != 1usize || store.certs.len != 2usize || !store.had_mac { ret 4u8 }
        if !same_bytes(store.keys[0usize].pkcs8, key_der[0usize..kn]) { ret 5u8 }
        if !text_is(store.keys[0usize].friendly_name, "neper test") { ret 6u8 }
        ret 0u8
    }
    let (mac_flag, pf) = tok(line, p0)
    let (pw_hex, p1) = tok(line, pf)
    let (name_hex, p2) = tok(line, p1)
    let (key_hex, p3) = tok(line, p2)
    let (cert1_hex, p4) = tok(line, p3)
    let (cert2_hex, p5) = tok(line, p4)
    let (blob_hex, p6) = tok(line, p5)
    let pn = unhex(pw_hex, password_buf[0usize..64usize])
    let nn = unhex(name_hex, name_buf[0usize..64usize])
    let kn = unhex(key_hex, key_buf[0usize..2048usize])
    let an = unhex(cert1_hex, cert_a[0usize..1024usize])
    let bn = unhex(cert2_hex, cert_b[0usize..1024usize])
    let blob_n = unhex(blob_hex, blob_buf[0usize..12288usize])
    let password: str = password_buf[0usize..pn]
    let (store, e) = pkcs12.parse(a, blob_buf[0usize..blob_n], password)
    if e != ok { ret 11u8 }
    if store.had_mac != (mac_flag[0usize] == 49u8) { ret 12u8 }
    if store.keys.len != 1usize { ret 13u8 }
    if store.certs.len != 2usize { ret 14u8 }
    if !same_bytes(store.keys[0usize].pkcs8, key_buf[0usize..kn]) { ret 15u8 }
    if !text_is(store.keys[0usize].friendly_name, name_buf[0usize..nn]) { ret 16u8 }
    var found_a = false
    var found_b = false
    var i = 0usize
    while i < 2usize {
        if same_bytes(store.certs[i].der, cert_a[0usize..an]) { found_a = true }
        if same_bytes(store.certs[i].der, cert_b[0usize..bn]) { found_b = true }
        i += 1usize
    }
    if !found_a || !found_b { ret 17u8 }
    if mac_flag[0usize] == 49u8 {
        let (_, wrong) = pkcs12.parse(a, blob_buf[0usize..blob_n], "not the password")
        if wrong != pkcs12.BadPassword { ret 18u8 }
    }
    ret 0u8
}

fn run_chunk(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_line(a, text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..start + 20usize])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

'''

calls = '\n'.join('    let r_%s = run_chunk(a, %s())\n    if r_%s != 0u8 { os.exit(i32(r_%s)) }' % (n, n, n, n) for n in names)

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
''' + calls + '''
    try io.print("crypto pkcs12 ok")
    ret ok
}
'''

src = ('// e.crypto.pkcs12 against cryptography/OpenSSL 3: PBES2 AES-256-CBC stores with an HMAC-SHA256 MAC (RSA,\n'
       '// P-256 and Ed25519 keys, CA chains, ASCII, non-BMP and empty passwords) read back key, certificates and\n'
       '// friendly name, and a wrong password is BadPassword; the writer is a pure function of its inputs and its\n'
       '// file, verified at generation with cryptography and `openssl pkcs12`, is reproduced byte for byte (D2803).\n'
       '// Generated by scripts/gen_pkcs12_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.crypto.pkcs12\n\n'
       + fc.PRELUDE + const_src + CHECK + vec + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
