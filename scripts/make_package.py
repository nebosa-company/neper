#!/usr/bin/env python3
"""NeperOS app packages (neperos/src/package.e, C124).

  make_package.py key                         write neperos/src/server_key.e (the development server's Ed25519
                                              public key, from a fixed seed: the device's trust anchor)
  make_package.py pack IMAGE OUT NAME [CAPS]  build and sign a package of an app image

The signing key is the development server's, from a fixed seed; the real server's key replaces
neperos/src/server_key.e. A package is "NPKG", a version byte, a two-byte manifest length, the manifest,
a four-byte image length, the image and a 64-byte Ed25519 signature over all of it before.
"""
import struct
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

SEED = bytes(range(1, 33))
KEY = Ed25519PrivateKey.from_private_bytes(SEED)


def public_bytes() -> bytes:
    return KEY.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def package(manifest: bytes, image: bytes) -> bytes:
    body = b"NPKG" + bytes([1]) + struct.pack("<H", len(manifest)) + manifest + struct.pack("<I", len(image)) + image
    return body + KEY.sign(body)


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "key":
        dest = Path(__file__).resolve().parent.parent / "neperos" / "src" / "server_key.e"
        digits = ", ".join(str(b) for b in public_bytes())
        dest.write_text(
            "// The device's trust anchor for generated apps (C124): the Ed25519 public key of the server that signs\n"
            "// packages (scripts/make_package.py key writes this file; the development server's key from a fixed seed,\n"
            "// to be replaced by the real server's).\n"
            "use e.crypto.sign as sign\n\n"
            "fn public() -> sign.Ed25519PublicKey {\n"
            f"    ret sign.Ed25519PublicKey {{ bytes: [32]u8{{ {digits} }} }}\n"
            "}\n", encoding="utf-8", newline="\n")
        print("wrote", dest)
        return 0
    if len(sys.argv) >= 5 and sys.argv[1] == "pack":
        image = Path(sys.argv[2]).read_bytes()
        caps = sys.argv[5] if len(sys.argv) > 5 else "storage"
        manifest = f"name={sys.argv[4]}\nversion=1\napi=1\nentry=main\ncapabilities={caps}".encode()
        Path(sys.argv[3]).write_bytes(package(manifest, image))
        print("wrote", sys.argv[3])
        return 0
    print(__doc__)
    return 1


sys.exit(main())
