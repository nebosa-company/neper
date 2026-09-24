# Writes src/main.e: an Ed25519 chain from the cryptography package -- a root, an
# intermediate, a server leaf with DNS names and serverAuth, a leaf without extended
# usage, an expired leaf, a leaf signed by an unknown CA -- with fixed dates, as DER
# and as one PEM text, and the checks. Run from this directory after a change.
import datetime

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

UTC = datetime.timezone.utc


def key(seed):
    return ed25519.Ed25519PrivateKey.from_private_bytes(bytes([seed]) * 32)


def name(cn, org=None):
    parts = [x509.NameAttribute(NameOID.COMMON_NAME, cn)]
    if org:
        parts.append(x509.NameAttribute(NameOID.ORGANIZATION_NAME, org))
    return x509.Name(parts)


def build(subject, issuer, public, signer, start, end, ca=False, dns=None, eku=None,
          serial=1, algorithm=None, path_length=None, key_usage=None, extra_extensions=()):
    b = (x509.CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(public)
         .serial_number(serial).not_valid_before(start).not_valid_after(end)
         .add_extension(x509.BasicConstraints(ca=ca, path_length=path_length), critical=True))
    if dns:
        b = b.add_extension(x509.SubjectAlternativeName([x509.DNSName(d) for d in dns]), critical=False)
    if eku:
        b = b.add_extension(x509.ExtendedKeyUsage(eku), critical=False)
    if key_usage:
        b = b.add_extension(key_usage, critical=True)
    for extension, critical in extra_extensions:
        b = b.add_extension(extension, critical=critical)
    return b.sign(signer, algorithm)


root_key, mid_key, leaf_key, other_key = key(1), key(2), key(3), key(4)
start = datetime.datetime(2025, 1, 1, tzinfo=UTC)
end = datetime.datetime(2035, 1, 1, tzinfo=UTC)
root = build(name("Neper Root", "Neper"), name("Neper Root", "Neper"), root_key.public_key(), root_key, start, end, ca=True, serial=1)
mid = build(name("Neper Intermediate", "Neper"), root.subject, mid_key.public_key(), root_key, start, end, ca=True, serial=2)
leaf = build(name("example.com"), mid.subject, leaf_key.public_key(), mid_key, start, end, dns=["example.com", "*.example.org"],
             eku=[ExtendedKeyUsageOID.SERVER_AUTH], serial=3)
plain = build(name("plain"), mid.subject, leaf_key.public_key(), mid_key, start, end, serial=4)
expired = build(name("old.example.com"), mid.subject, leaf_key.public_key(), mid_key,
                datetime.datetime(2020, 1, 1, tzinfo=UTC), datetime.datetime(2021, 1, 1, tzinfo=UTC), dns=["old.example.com"], serial=5)
stranger = build(name("stranger"), name("Other CA"), leaf_key.public_key(), other_key, start, end, serial=6)
unknown_critical = build(
    name("unknown-critical"), mid.subject, leaf_key.public_key(), mid_key, start, end, serial=7,
    extra_extensions=[(x509.UnrecognizedExtension(x509.ObjectIdentifier("1.2.3.4"), b"\x05\x00"), True)])
bad_usage_key = key(5)
bad_usage_mid = build(
    name("Bad Usage CA"), root.subject, bad_usage_key.public_key(), root_key, start, end,
    ca=True, serial=8, key_usage=x509.KeyUsage(False, False, False, False, False, False, False, False, False))
bad_usage_leaf = build(name("bad-usage-leaf"), bad_usage_mid.subject, leaf_key.public_key(),
                       bad_usage_key, start, end, serial=9)
zero_key, sub_key = key(6), key(7)
zero_mid = build(name("Zero Path CA"), root.subject, zero_key.public_key(), root_key,
                 start, end, ca=True, path_length=0, serial=10)
sub_mid = build(name("Sub CA"), zero_mid.subject, sub_key.public_key(), zero_key,
                start, end, ca=True, serial=11)
deep_leaf = build(name("deep-leaf"), sub_mid.subject, leaf_key.public_key(), sub_key,
                  start, end, serial=12)
constrained_key = key(8)
constrained_mid = build(
    name("Constrained CA"), root.subject, constrained_key.public_key(), root_key,
    start, end, ca=True, serial=13,
    extra_extensions=[(x509.NameConstraints(
        permitted_subtrees=[x509.DNSName(".allowed.example")],
        excluded_subtrees=[x509.DNSName("blocked.allowed.example")]), True)])
allowed_leaf = build(name("allowed"), constrained_mid.subject, leaf_key.public_key(), constrained_key,
                     start, end, dns=["www.allowed.example"], serial=14)
outside_leaf = build(name("outside"), constrained_mid.subject, leaf_key.public_key(), constrained_key,
                     start, end, dns=["www.outside.example"], serial=15)
blocked_leaf = build(name("blocked"), constrained_mid.subject, leaf_key.public_key(), constrained_key,
                     start, end, dns=["blocked.allowed.example"], serial=16)
wildcard_leaf = build(name("wildcard"), constrained_mid.subject, leaf_key.public_key(), constrained_key,
                     start, end, dns=["*.allowed.example"], serial=17)
safe_wildcard_leaf = build(name("safe-wildcard"), constrained_mid.subject, leaf_key.public_key(), constrained_key,
                          start, end, dns=["*.safe.allowed.example"], serial=18)
p256_root_key = ec.derive_private_key(1, ec.SECP256R1())
p256_leaf_key = ec.derive_private_key(2, ec.SECP256R1())
p256_root = build(name("P256 Root"), name("P256 Root"), p256_root_key.public_key(), p256_root_key,
                  start, end, ca=True, serial=101, algorithm=hashes.SHA256())
p256_leaf = build(name("p256.example"), p256_root.subject, p256_leaf_key.public_key(), p256_root_key,
                  start, end, dns=["p256.example"], eku=[ExtendedKeyUsageOID.SERVER_AUTH],
                  serial=102, algorithm=hashes.SHA256())
p384_key = ec.derive_private_key(1, ec.SECP384R1())
p384_suffix = build(name("P384 Suffix"), name("P384 Suffix"), p384_key.public_key(), p384_key,
                    start, end, ca=True, serial=103, algorithm=hashes.SHA384())

# Python checks the chain itself before it is trusted here.
mid.verify_directly_issued_by(root)
leaf.verify_directly_issued_by(mid)

der = {n: c.public_bytes(serialization.Encoding.DER) for n, c in
       [("root", root), ("mid", mid), ("leaf", leaf), ("plain", plain), ("expired", expired),
        ("stranger", stranger), ("unknown_critical", unknown_critical),
        ("bad_usage_mid", bad_usage_mid), ("bad_usage_leaf", bad_usage_leaf),
        ("zero_mid", zero_mid), ("sub_mid", sub_mid), ("deep_leaf", deep_leaf),
        ("constrained_mid", constrained_mid), ("allowed_leaf", allowed_leaf),
        ("outside_leaf", outside_leaf), ("blocked_leaf", blocked_leaf),
        ("wildcard_leaf", wildcard_leaf), ("safe_wildcard_leaf", safe_wildcard_leaf),
        ("p256_root", p256_root), ("p256_leaf", p256_leaf),
        ("p384_suffix", p384_suffix)]}
pem_text = b"".join(c.public_bytes(serialization.Encoding.PEM) for c in [root, mid])


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


now = int(datetime.datetime(2026, 6, 1, tzinfo=UTC).timestamp())
start_ns = int(start.timestamp()) * 1000000000
end_ns = int(end.timestamp()) * 1000000000

HEADER = '''// `e.crypto.x509`: an Ed25519 chain built by Python's cryptography package
// (reference.py beside this fixture) -- names rendered, validity, DNS names and the
// CA bit read; the root and intermediate taken from one PEM text; `verify_signature`
// accepting the real issuer and refusing another; `verify` building the two-link
// chain with a matching name, a wildcard, a bare `Any` usage, and refusing a wrong
// name, a client-auth use, an expired leaf, a leaf from an unknown CA, a missing
// intermediate and a depth of one. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.time
use e.crypto.x509 as x509

fn options(roots: []const x509.Certificate, intermediates: []const x509.Certificate, dns_name: str, usage: x509.KeyUsage, depth: u16) -> x509.VerifyOptions {
    var o: x509.VerifyOptions = zero
    o.roots = x509.Pool { certificates: roots }
    o.intermediates = x509.Pool { certificates: intermediates }
    o.dns_name = dns_name
    o.now = time.Instant { nanos: %di64 * 1000000000i64 }
    o.usage = usage
    o.max_depth = depth
    ret o
}

fn main(a: *mem.Arena, args: []str) -> err {
''' % now

BODY = '''    let (root, e1) = x509.parse(a, root_der)
    if e1 != ok { os.exit(1) }
    if !str.eq(root.subject, "CN=Neper Root, O=Neper") || !str.eq(root.issuer, root.subject) || !root.is_ca { os.exit(2) }
    if root.not_before.nanos != %di64 || root.not_after.nanos != %di64 { os.exit(3) }
    let (mid, e2) = x509.parse(a, mid_der)
    if e2 != ok || !str.eq(mid.subject, "CN=Neper Intermediate, O=Neper") || !str.eq(mid.issuer, root.subject) || !mid.is_ca { os.exit(4) }
    let (leaf, e3) = x509.parse(a, leaf_der)
    if e3 != ok || !str.eq(leaf.subject, "CN=example.com") || leaf.is_ca { os.exit(5) }
    if leaf.dns_names.len != 2usize || !str.eq(leaf.dns_names[0], "example.com") || !str.eq(leaf.dns_names[1], "*.example.org") { os.exit(6) }
    switch leaf.public_key {
    case .Ed25519 as key:
        if key.bytes[0] == 0u8 && key.bytes[1] == 0u8 { os.exit(7) }
    default:
        os.exit(8)
    }
    let (plain, e4) = x509.parse(a, plain_der)
    if e4 != ok || plain.dns_names.len != 0usize { os.exit(9) }
    let (expired, e5) = x509.parse(a, expired_der)
    if e5 != ok { os.exit(10) }
    let (stranger, e6) = x509.parse(a, stranger_der)
    if e6 != ok || !str.eq(stranger.issuer, "CN=Other CA") { os.exit(11) }
    let (broken, e7) = x509.parse(a, root_der[..100])
    if e7 != x509.InvalidCertificate { os.exit(12) }
    // PEM.
    let (from_pem, e8) = x509.parse_pem(a, pem_text)
    if e8 != ok || from_pem.len != 2usize || !str.eq(from_pem[0].subject, root.subject) || !str.eq(from_pem[1].subject, mid.subject) { os.exit(13) }
    // Signatures.
    if x509.verify_signature(mid, root) != ok || x509.verify_signature(leaf, mid) != ok || x509.verify_signature(root, root) != ok { os.exit(14) }
    if x509.verify_signature(leaf, root) != x509.InvalidCertificate { os.exit(15) }
    // Chains.
    var roots: [1]x509.Certificate = zero
    roots[0] = root
    var intermediates: [1]x509.Certificate = zero
    intermediates[0] = mid
    let (chain, e9) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "example.com", .ServerAuth, 4u16))
    if e9 != ok || chain.certificates.len != 3usize || !str.eq(chain.certificates[1].subject, mid.subject) || !str.eq(chain.certificates[2].subject, root.subject) { os.exit(16) }
    let (chain2, e10) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "www.EXAMPLE.org", .Any, 4u16))
    if e10 != ok { os.exit(17) }
    let (chain3, e11) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "", .Any, 4u16))
    if e11 != ok { os.exit(18) }
    let (chain4, e12) = x509.verify(a, plain, options(roots[0..], intermediates[0..], "", .ClientAuth, 4u16))
    if e12 != ok { os.exit(19) }
    let (chain5, e13) = x509.verify(a, mid, options(roots[0..], zero, "", .Any, 4u16))
    if e13 != ok || chain5.certificates.len != 2usize { os.exit(20) }
    let (chain6, e14) = x509.verify(a, root, options(roots[0..], zero, "", .Any, 4u16))
    if e14 != ok || chain6.certificates.len != 1usize { os.exit(21) }
    let (bad1, e15) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "example.org", .Any, 4u16))
    if e15 != x509.NameMismatch { os.exit(22) }
    let (bad2, e16) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "a.b.example.org", .Any, 4u16))
    if e16 != x509.NameMismatch { os.exit(23) }
    let (bad3, e17) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "example.com", .ClientAuth, 4u16))
    if e17 != x509.InvalidUsage { os.exit(24) }
    let (bad4, e18) = x509.verify(a, expired, options(roots[0..], intermediates[0..], "old.example.com", .Any, 4u16))
    if e18 != x509.Expired { os.exit(25) }
    let (bad5, e19) = x509.verify(a, stranger, options(roots[0..], intermediates[0..], "", .Any, 4u16))
    if e19 != x509.UnknownAuthority { os.exit(26) }
    let (bad6, e20) = x509.verify(a, leaf, options(roots[0..], zero, "", .Any, 4u16))
    if e20 != x509.UnknownAuthority { os.exit(27) }
    let (bad7, e21) = x509.verify(a, leaf, options(roots[0..], intermediates[0..], "", .Any, 1u16))
    if e21 != x509.TooDeep { os.exit(28) }
    let (p256_root, e22) = x509.parse(a, p256_root_der)
    let (p256_leaf, e23) = x509.parse(a, p256_leaf_der)
    if e22 != ok || e23 != ok { os.exit(29) }
    switch p256_leaf.public_key {
    case .P256 as key:
        if key.bytes[0] != 4u8 { os.exit(30) }
    default:
        os.exit(31)
    }
    if x509.verify_signature(p256_leaf, p256_root) != ok || x509.verify_signature(p256_root, p256_root) != ok { os.exit(32) }
    var p256_roots: [1]x509.Certificate = zero
    p256_roots[0] = p256_root
    let (p256_chain, e24) = x509.verify(a, p256_leaf, options(p256_roots[0..], zero, "p256.example", .ServerAuth, 2u16))
    if e24 != ok || p256_chain.certificates.len != 2usize { os.exit(33) }
    let (p384_suffix, e25) = x509.parse(a, p384_suffix_der)
    if e25 != ok { os.exit(34) }
    switch p384_suffix.public_key {
    case .Unsupported as raw:
        if raw.len != 97usize { os.exit(35) }
    default:
        os.exit(35)
    }
    if x509.verify_signature(p384_suffix, p384_suffix) != x509.InvalidCertificate { os.exit(36) }
    // Critical extensions and CA constraints fail closed.
    let (unknown_critical, e26) = x509.parse(a, unknown_critical_der)
    if e26 != ok || !unknown_critical.unhandled_critical { os.exit(37) }
    let (bad_critical_chain, e27) = x509.verify(a, unknown_critical, options(roots[0..], intermediates[0..], "", .Any, 4u16))
    if e27 != x509.InvalidCertificate { os.exit(38) }
    let (bad_usage_mid, e28) = x509.parse(a, bad_usage_mid_der)
    let (bad_usage_leaf, e29) = x509.parse(a, bad_usage_leaf_der)
    if e28 != ok || e29 != ok || !bad_usage_mid.has_key_usage || bad_usage_mid.key_cert_sign { os.exit(39) }
    var bad_usage_intermediates: [1]x509.Certificate = zero
    bad_usage_intermediates[0] = bad_usage_mid
    let (bad_usage_chain, e30) = x509.verify(a, bad_usage_leaf, options(roots[0..], bad_usage_intermediates[0..], "", .Any, 4u16))
    if e30 != x509.UnknownAuthority { os.exit(40) }
    let (zero_mid, e31) = x509.parse(a, zero_mid_der)
    let (sub_mid, e32) = x509.parse(a, sub_mid_der)
    let (deep_leaf, e33) = x509.parse(a, deep_leaf_der)
    if e31 != ok || e32 != ok || e33 != ok || !zero_mid.has_path_len || zero_mid.path_len != 0u16 { os.exit(41) }
    var deep_intermediates: [2]x509.Certificate = zero
    deep_intermediates[0] = sub_mid
    deep_intermediates[1] = zero_mid
    let (deep_chain, e34) = x509.verify(a, deep_leaf, options(roots[0..], deep_intermediates[0..], "", .Any, 5u16))
    if e34 != x509.UnknownAuthority { os.exit(42) }
    // DNS name constraints apply to every descendant SAN.
    let (constrained_mid, e35) = x509.parse(a, constrained_mid_der)
    let (allowed_leaf, e36) = x509.parse(a, allowed_leaf_der)
    let (outside_leaf, e37) = x509.parse(a, outside_leaf_der)
    let (blocked_leaf, e38) = x509.parse(a, blocked_leaf_der)
    if e35 != ok || e36 != ok || e37 != ok || e38 != ok { os.exit(43) }
    if constrained_mid.permitted_dns.len != 1usize || !str.eq(constrained_mid.permitted_dns[0], ".allowed.example") { os.exit(44) }
    if constrained_mid.excluded_dns.len != 1usize || !str.eq(constrained_mid.excluded_dns[0], "blocked.allowed.example") { os.exit(45) }
    var constrained_intermediates: [1]x509.Certificate = zero
    constrained_intermediates[0] = constrained_mid
    let (allowed_chain, e39) = x509.verify(a, allowed_leaf, options(roots[0..], constrained_intermediates[0..], "www.allowed.example", .Any, 4u16))
    if e39 != ok || allowed_chain.certificates.len != 3usize { os.exit(46) }
    let (outside_chain, e40) = x509.verify(a, outside_leaf, options(roots[0..], constrained_intermediates[0..], "www.outside.example", .Any, 4u16))
    if e40 != x509.NameMismatch { os.exit(47) }
    let (blocked_chain, e41) = x509.verify(a, blocked_leaf, options(roots[0..], constrained_intermediates[0..], "blocked.allowed.example", .Any, 4u16))
    if e41 != x509.NameMismatch { os.exit(48) }
    // Wildcards cannot grant a hostname excluded by an ancestor constraint.
    let (wildcard_leaf, e42) = x509.parse(a, wildcard_leaf_der)
    let (safe_wildcard_leaf, e43) = x509.parse(a, safe_wildcard_leaf_der)
    if e42 != ok || e43 != ok { os.exit(49) }
    let (_, e44) = x509.verify(a, wildcard_leaf, options(roots[0..], constrained_intermediates[0..], "blocked.allowed.example", .Any, 4u16))
    if e44 != x509.NameMismatch { os.exit(50) }
    let (_, e45) = x509.verify(a, wildcard_leaf, options(roots[0..], constrained_intermediates[0..], "www.allowed.example", .Any, 4u16))
    if e45 != x509.NameMismatch { os.exit(51) }
    let (_, e46) = x509.verify(a, safe_wildcard_leaf, options(roots[0..], constrained_intermediates[0..], "www.safe.allowed.example", .Any, 4u16))
    if e46 != ok { os.exit(52) }
    ret ok
}
''' % (start_ns, end_ns)

parts = ["    let %s_der = %s" % (n, literal(d)) for n, d in der.items()] + ["    let pem_text = " + literal(pem_text)]
open('src/main.e', 'w', encoding='utf-8', newline='\n').write(HEADER + "\n".join(parts) + "\n" + BODY)
print({n: len(d) for n, d in der.items()})
