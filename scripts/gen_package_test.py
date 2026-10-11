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
    ret ok
}
""" % (len(good), 7 + len(manifest) + 4 + 10, 7 + len(manifest) + 4 + 10, len(good) - 5))
dest = Path(__file__).resolve().parent.parent / "neperos" / "src" / "package_test.e"
dest.write_text("".join(out), encoding="utf-8", newline="\n")
print("wrote", dest)
