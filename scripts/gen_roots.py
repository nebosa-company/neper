"""Write the NeperOS trust store, neperos/assets/roots/mozilla.der (D2246, D2247, C117).

  python scripts/gen_roots.py

The Mozilla roots (certifi's cacert.pem) as concatenated DER certificates -- the form the TLS client
takes -- shipped as an initrd archive entry the kernel maps into the network server as an argument.
(It was embedded in the program as a hex string first, but the kernel then wrote a driver server's
aux area over the image bytes at 256 KB, D2248, and a 260 KB literal decoded as garbage after its first
93 KB. The aux area has a page of its own now; an archive entry is still the better home for 130 KB of data.)
Of the Mozilla roots only those the client can verify with are kept: an RSA key, a P-256 key or a P-384 key (C144), since
e.crypto.sign has no P-521 verifier and a root it cannot use only costs parse
time on every handshake.
"""
import pathlib
import warnings

import certifi
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

warnings.simplefilter('ignore')
root = pathlib.Path(__file__).resolve().parent.parent

kept = []
dropped = 0
for cert in x509.load_pem_x509_certificates(pathlib.Path(certifi.where()).read_bytes()):
    key = cert.public_key()
    usable = isinstance(key, rsa.RSAPublicKey) or (isinstance(key, ec.EllipticCurvePublicKey) and key.curve.name in ('secp256r1', 'secp384r1'))
    if usable:
        kept.append(cert.public_bytes(serialization.Encoding.DER))
    else:
        dropped += 1
bundle = b''.join(kept)
(root / 'neperos/assets/roots/mozilla.der').write_bytes(bundle)
print('wrote neperos/assets/roots/mozilla.der:', len(kept), 'roots,', len(bundle), 'bytes;', dropped, 'dropped')
