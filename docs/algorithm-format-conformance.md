# A0 Algorithm and Format Conformance Contract

Every `e.crypto.*`, `e.algo.stat`, and `e.fmt.*` implementation must document and
test these shared contracts before it is marked equivalent.

## Byte and text contract

- Binary APIs consume and produce `[]const u8`; no implicit text encoding.
- Text APIs state UTF-8 handling and behavior for invalid sequences.
- Integer encoding states signedness, width, endian, and overflow behavior.
- Canonical output is deterministic unless an API explicitly permits variability.

## Errors and limits

- Malformed input, truncation, unsupported features, limit exhaustion, and I/O
  failure are distinguishable errors.
- Readers expose configurable maximum bytes, nesting depth, members, dimensions,
  and decompression expansion.
- No parser allocates based solely on attacker-controlled lengths.

## Streaming and ownership

- Readers and writers support incremental operation where the format permits it.
- Partial reads/writes report progress and preserve retry semantics.
- Close/finalize behavior is explicit; buffers and keys have documented ownership.
- Cancellation never silently converts a partial result into success.

## Security and numerical behavior

- Cryptographic operations use vetted implementations and state constant-time
  requirements, nonce rules, randomness source, and zeroization policy.
- Statistics and numerical APIs specify NaN, infinity, overflow, precision, and
  deterministic-mode behavior.
- Archive and markup readers defend against traversal, entity expansion, and
  decompression/resource-exhaustion attacks.

## Required evidence

Each matrix row must link to:

1. Golden/reference vectors.
2. Round-trip tests.
3. Malformed-input and limit tests.
4. Streaming/large-input tests where applicable.
5. Fuzz or differential testing for parsers/codecs.
6. Security review for cryptography and attacker-controlled formats.

