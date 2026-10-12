#!/usr/bin/env python3
"""Write neperos/src/package_test.e: the NeperOS app package (neperos/src/package.e, C124) checked against
Python's cryptography package -- a package built here, signed with Ed25519 from a fixed seed, must parse,
verify, answer its manifest keys and capabilities, and be refused when a byte changes, when another key is
used and when its api is newer. Every check has its own exit code."""
import struct
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def package(manifest: bytes, image: bytes, key: Ed25519PrivateKey) -> bytes:
    body = b"NPKG" + bytes([1]) + struct.pack("<H", len(manifest)) + manifest + struct.pack("<I", len(image)) + image
    return body + key.sign(body)


def array(name: str, data: bytes) -> str:
    return f"    let {name}: [{len(data)}]u8 = [{len(data)}]u8{{ " + ", ".join(str(b) for b in data) + " }\n"


seed = bytes(range(1, 33))
key = Ed25519PrivateKey.from_private_bytes(seed)
public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
other = Ed25519PrivateKey.from_private_bytes(bytes(range(101, 133))).public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)
manifest = b"name=Tip calculator\nversion=1\napi=1\nentry=main\ncapabilities=storage,camera\nicon=icon.svg"
image = bytes((i * 7 + 3) % 256 for i in range(300))
good = package(manifest, image, key)
newer = package(manifest.replace(b"api=1", b"api=2"), image, key)


def revocation_list(text: bytes, signing_key: Ed25519PrivateKey) -> bytes:
    # (C173) "NREV" | version | text length | text | signature over all before.
    body = b"NREV" + bytes([1]) + struct.pack("<H", len(text)) + text
    return body + signing_key.sign(body)


list_text = b"Tip calculator=2\nOther\n"
signed_list = revocation_list(list_text, key)
signed_list_other = revocation_list(list_text, Ed25519PrivateKey.from_private_bytes(bytes(range(101, 133))))
signed_list_damaged = bytearray(signed_list)
signed_list_damaged[9] ^= 1

out = []
out.append("// The NeperOS app package (neperos/src/package.e, C124) against Python's cryptography package (written by\n")
out.append("// scripts/gen_package_test.py): a signed package parses, verifies and answers its manifest; a flipped byte,\n")
out.append("// another key, a truncation and a newer api are refused. Every check has its own exit code.\n")
out.append("use e.os\nuse e.mem\nuse e.crypto.sign as sign\nuse package\n\n")
out.append("fn main(a: *mem.Arena, args: []str) -> err {\n")
out.append(array("good", good))
out.append(array("newer", newer))
out.append(array("public_bytes", public))
out.append(array("other_bytes", other))
LISTS = (
    ("rev_all", b"Tip calculator\n"),
    ("rev_upto1", b"Other\nTip calculator=1\r\n"),
    ("rev_upto0", b"Tip calculator=0\n"),
    ("rev_prefix", b"Tip calcul\nTip calculator2\n=1\n"),
    ("rev_other", b"Other=9\nAnother app\n"),
)
for list_name, list_body in LISTS:
    out.append(array(list_name, list_body))
out.append(array("signed_list", signed_list))
out.append(array("signed_list_other", signed_list_other))
out.append(array("signed_list_damaged", bytes(signed_list_damaged)))
out.append(array("list_text", list_text))
out.append("""    let key = sign.Ed25519PublicKey { bytes: public_bytes }
    let wrong = sign.Ed25519PublicKey { bytes: other_bytes }
    let (p, parse_error) = package.parse(good[0..])
    if parse_error != ok { os.exit(1) }
    if !package.verify(p, good[0..], key) { os.exit(2) }
    if package.verify(p, good[0..], wrong) { os.exit(3) }
    let (name, has_name) = package.value(p, "name")
    if !has_name || !package.text_is(name, "Tip calculator") { os.exit(4) }
    if package.api_of(p) != 1usize { os.exit(5) }
    if !package.declares(p, "camera") || !package.declares(p, "storage") { os.exit(6) }
    if package.declares(p, "network") || package.declares(p, "stor") { os.exit(7) }
    if p.image.len != 300usize || p.image[0usize] != 3u8 || p.image[299usize] != 0u8 + u8((299usize * 7usize + 3usize) %% 256usize) { os.exit(8) }
    let (checked, check_error) = package.check(good[0..], key)
    if check_error != ok { os.exit(9) }
    var damaged: [%d]u8 = zero
    var i = 0usize
    while i < good.len {
        damaged[i] = good[i]
        i += 1usize
    }
    damaged[%d] = damaged[%d] ^ 1u8
    let (d, d_error) = package.parse(damaged[0..])
    if d_error != ok { os.exit(10) }
    if package.verify(d, damaged[0..], key) { os.exit(11) }
    let (c, c_error) = package.check(damaged[0..], key)
    if c_error != package.BadPackage { os.exit(12) }
    let (t, t_error) = package.parse(good[0..%d])
    if t_error != package.BadPackage { os.exit(13) }
    let (n, n_error) = package.check(newer[0..], key)
    if n_error != package.TooNew { os.exit(14) }
    let (w, w_error) = package.check(good[0..], wrong)
    if w_error != package.BadPackage { os.exit(15) }
    if package.version_of(p) != 1usize { os.exit(16) }
    if !package.revoked(p, rev_all[0..]) { os.exit(17) }
    if !package.revoked(p, rev_upto1[0..]) { os.exit(18) }
    if package.revoked(p, rev_upto0[0..]) { os.exit(19) }
    if package.revoked(p, rev_prefix[0..]) { os.exit(20) }
    if package.revoked(p, rev_other[0..]) { os.exit(21) }
    if package.revoked(p, good[0..0]) { os.exit(22) }
    let (r, r_error) = package.check_revocable(good[0..], key, rev_all[0..])
    if r_error != package.Revoked { os.exit(23) }
    let (ok_p, ok_error) = package.check_revocable(good[0..], key, rev_other[0..])
    if ok_error != ok { os.exit(24) }
    let (bad_p, bad_error) = package.check_revocable(damaged[0..], key, rev_other[0..])
    if bad_error != package.BadPackage { os.exit(25) }
    // (C173) A revocation list the server signs: its text when the signature is the server's, nothing when another
    // key signed it, a byte changed or it is cut short; and the text works as the revocation list.
    let (listed, list_error) = package.check_list(signed_list[0..], key)
    if list_error != ok || listed.len != list_text.len { os.exit(26) }
    var same = true
    var li = 0usize
    while li < list_text.len {
        if listed[li] != list_text[li] { same = false }
        li += 1usize
    }
    if !same { os.exit(27) }
    let (other_list, other_error) = package.check_list(signed_list_other[0..], key)
    if other_error != package.BadPackage { os.exit(28) }
    let (damaged_list, damaged_error) = package.check_list(signed_list_damaged[0..], key)
    if damaged_error != package.BadPackage { os.exit(29) }
    let (cut_list, cut_error) = package.check_list(signed_list[0..40], key)
    if cut_error != package.BadPackage { os.exit(30) }
    let (not_list, not_error) = package.check_list(good[0..], key)
    if not_error != package.BadPackage { os.exit(31) }
    if !package.revoked(p, listed) { os.exit(32) }
    ret ok
}
""" % (len(good), 7 + len(manifest) + 4 + 10, 7 + len(manifest) + 4 + 10, len(good) - 5))
dest = Path(__file__).resolve().parent.parent / "neperos" / "src" / "package_test.e"
dest.write_text("".join(out), encoding="utf-8", newline="\n")
print("wrote", dest)
