"""Build the semantic algorithm/file-format coverage matrix."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
inv = json.loads((ROOT / "docs/rewrite-coverage-inventory.json").read_text())
mods = json.loads((ROOT / "docs/modules.json").read_text())
module_names = {m["name"] for m in mods.get("modules", [])}

details = {
 "crypto.hash": ["SHA-2", "SHA-3", "BLAKE2/3", "incremental hashing"],
 "crypto.mac": ["HMAC", "keyed hash", "constant-time verify"],
 "crypto.aead": ["AES-GCM", "ChaCha20-Poly1305", "nonce", "associated data"],
 "crypto.kdf": ["HKDF", "PBKDF2", "scrypt/Argon2", "parameter limits"],
 "crypto.kx": ["X25519", "key agreement", "transcript binding"],
 "crypto.sign": ["Ed25519", "ECDSA", "RSA", "key serialization"],
 "crypto.random": ["OS entropy", "secure bytes", "failure reporting"],
 "crypto.x509": ["DER", "PEM", "chain validation", "hostname validation"],
 "statistics": ["descriptive", "quantiles", "distributions", "regression", "streaming"],
}
items = [
 ("crypto.hash", "e.crypto.hash", "cryptography", "A1"),
 ("crypto.mac", "e.crypto.mac", "cryptography", "A1"),
 ("crypto.aead", "e.crypto.aead", "cryptography", "A1"),
 ("crypto.kdf", "e.crypto.kdf", "cryptography", "A1"),
 ("crypto.kx", "e.crypto.kx", "cryptography", "A1"),
 ("crypto.sign", "e.crypto.sign", "cryptography", "A1"),
 ("crypto.random", "e.crypto.random", "cryptography", "A1"),
 ("crypto.x509", "e.crypto.x509", "cryptography", "A1"),
 ("statistics", "e.algo.stat", "statistics", "A1"),
]
formats = ["asn1","bson","bzip2","csv","gzip","html","ini","jpeg","json","lzw","mail","mime","mp3","msgpack","multipart","pem","png","protobuf","quoted_printable","tar","uri","wav","webp","xml","yaml","zip","zlib","zstd"]
items += [(f"format.{x}", f"e.fmt.{x}", "format", "A2") for x in formats]

names = []
for repo in inv.values():
    names.extend(repo.get("prototype_names", []))
    names.extend(repo.get("ui_names", []))
text = "\n".join(names).lower()
rows = []
for key, module, family, priority in items:
    token = key.split(".")[-1]
    uses = text.count(token)
    exists = module in module_names
    rows.append({"id": key, "family": family, "priority": priority,
                 "neper_module": module, "module_in_catalog": exists,
                 "observed_name_mentions": uses,
                 "sub_capabilities": details.get(key, [token]),
                 "status": "planned" if exists else "missing",
                 "required_evidence": ["golden vectors", "round-trip tests", "malformed-input tests", "streaming/limits tests"]})
out = {"schema": "neper-semantic-coverage", "version": 1, "generated_by": "scripts/build_algorithm_format_matrix.py", "items": rows}
(ROOT / "docs/algorithm-format-coverage.json").write_text(json.dumps(out, indent=2) + "\n")
print(f"wrote {len(rows)} capability rows")
