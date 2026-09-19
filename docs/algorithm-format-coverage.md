# Algorithms and File Formats Coverage Plan

This is the first semantic-rewrite workstream. The shared A0 contract is defined in
[`algorithm-format-conformance.md`](algorithm-format-conformance.md). A source API is considered covered
only when Neper provides equivalent results, failure behavior, streaming behavior,
resource ownership, and documented security guarantees. Similar names are not
enough: for example, a `DIV` can map to `Panel`, and a platform JSON type can map
to `e.fmt.json`, when the observable contract is preserved.

## Priority order

### A0 — conformance foundations

- [ ] Define canonical byte/string, endian, numeric, and Unicode policies.
- [ ] Define error taxonomy and malformed-input behavior for every format.
- [ ] Add golden vectors and differential tests against reference implementations.
- [ ] Add streaming reader/writer contracts, cancellation, limits, and truncation tests.
- [ ] Record constant-time and randomness requirements for security-sensitive APIs.
- [ ] Expose version, feature, and target availability in module metadata.

### A1 — cryptography

Modules: `e.crypto.random`, `hash`, `mac`, `aead`, `kdf`, `kx`, `sign`, `x509`.

- [ ] Hashes: SHA-2, SHA-3, BLAKE2/3, incremental hashing, tree hashing.
- [ ] MACs: HMAC, keyed hashes, verification without timing leaks.
- [ ] AEAD: AES-GCM, ChaCha20-Poly1305, nonce discipline, associated data.
- [ ] KDFs: HKDF, PBKDF2, scrypt/Argon2 policy and parameter validation.
- [ ] Key exchange: X25519 and approved platform-backed alternatives.
- [ ] Signatures: Ed25519/ECDSA/RSA verification and key serialization.
- [ ] Secure random generation, entropy failure reporting, zeroization policy.
- [ ] PEM/DER certificate parsing, chain validation, hostname and time checks.
- [ ] Explicitly exclude unaudited homemade primitives; bind vetted backends.

### A1 — statistics and numerical algorithms

Module: `e.algo.stat` plus numeric foundations.

- [ ] Descriptive statistics, weighted statistics, streaming/online aggregates.
- [ ] Quantiles, histograms, covariance, correlation, and robust estimators.
- [ ] Probability distributions, sampling, RNG injection, and reproducible seeds.
- [ ] Linear algebra, decompositions, interpolation, numerical integration.
- [ ] Hypothesis tests, confidence intervals, regression, and outlier handling.
- [ ] NaN, infinity, overflow, precision, and deterministic-mode contracts.
- [ ] Property tests and reference comparisons for representative data sizes.

### A2 — serialization and interchange

Modules: `e.fmt.json`, `yaml`, `xml`, `csv`, `ini`, `toml` (if added), `bson`,
`msgpack`, `protobuf`, `asn1`, `pem`, `uri`, `mime`, `multipart`, `mail`, and
`quoted_printable`.

- [ ] Round-trip tests, canonical output, duplicate-key policy, and limits.
- [ ] Schema/version handling and unknown-field preservation policy.
- [ ] Unicode normalization and invalid encoding behavior.
- [ ] Streaming APIs for large documents and incremental parsing.
- [ ] Security tests for entity expansion, nesting bombs, and resource exhaustion.

### A2 — compression, archives, media, and binary formats

Modules: `e.fmt.gzip`, `zlib`, `zstd`, `bzip2`, `lzw`, `zip`, `tar`, `png`,
`jpeg`, `webp`, `wav`, `mp3`.

- [ ] Compression/decompression streaming and bounded-memory behavior.
- [ ] Archive path traversal, symlink, permissions, timestamp, and bomb defenses.
- [ ] Endianness, metadata, checksums, partial input, and corruption reporting.
- [ ] Image dimensions, color profiles, orientation, animation, and decoding limits.
- [ ] Audio sample formats, channels, duration, seeking, and metadata behavior.
- [ ] Fuzz and differential tests against established native libraries.

## Verification record

The initial machine-readable matrix is [`algorithm-format-coverage.json`](algorithm-format-coverage.json)
and can be regenerated with `rtk python scripts/build_algorithm_format_matrix.py`.

For each capability, record: Neper module/API, source-library equivalents, status
(`equivalent`, `adaptation`, `partial`, `missing`, or `unknown`), reference vectors,
security review, and target-specific exceptions. This record feeds the rewrite
coverage inventory and must be completed before claiming an application can be
rewritten completely in Neper.
