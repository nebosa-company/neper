# AES-128-GCM seal, one record, through Python's cryptography (OpenSSL); call overhead included.
import time, os
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
key = bytes((i*29+1) % 256 for i in range(16)); a = AESGCM(key); aad = bytes(13)
for size, runs in ((100, 200000), (16384, 20000)):
    p = bytes((i*7+3) % 256 for i in range(size)); n = bytes(12)
    t = time.perf_counter_ns()
    for _ in range(runs): a.encrypt(n, p, aad)
    ns = (time.perf_counter_ns() - t) / runs
    print(f"openssl-aes128 {size} {ns:.0f} {size*1000/ns:.0f}")
