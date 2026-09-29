# `x.openssl.crypto` — package specification

AES-128-GCM from the host's OpenSSL, as an optional record cipher for `e.net.tls`. This is the
separate package specification that `modules.md` requires of every `x.*` package: upstream
version, targets, ownership and licensing boundary. Decision D1646.

## Why it exists

`e.crypto.aead`'s AES-GCM is portable Neper: a bitsliced AES and a multiplication-based GHASH
(D1645). OpenSSL runs the same cipher on the CPU's AES and carry-less multiply instructions,
and seals a 16 KB TLS record in about 3 µs where the portable code takes 700 µs (C098). A
program that talks to a server over TLS and moves much data can hand record encryption to
OpenSSL. Nothing else moves: the handshake, the certificate checks and the key schedule stay
`e.net.tls`'s.

## Optional, and nothing Neper ships

- **No bundled library.** The package uses whatever libcrypto the host has. On Linux that is the
  distribution's OpenSSL 3 (`libcrypto.so.3`). On Windows it is a `libcrypto-3-x64.dll` the user
  puts on the DLL search path, for example the one Git for Windows installs.
- **No load-time dependency.** Every function is looked up by name at run time (`os.dlopen`,
  `os.dlsym`), so a program that imports the package still starts on a host without OpenSSL.
  `load` answers `NotFound`, and the program keeps the portable cipher.
- **No default.** Nothing in `e.*` uses it unless a caller passes it in.

## Upstream

- **API:** OpenSSL 3's EVP interface: `EVP_CIPHER_CTX_new`, `EVP_CIPHER_CTX_free`,
  `EVP_aes_128_gcm`, `EVP_EncryptInit_ex`, `EVP_EncryptUpdate`, `EVP_EncryptFinal_ex`,
  `EVP_DecryptInit_ex`, `EVP_DecryptUpdate`, `EVP_DecryptFinal_ex` and `EVP_CIPHER_CTX_ctrl`
  (`EVP_CTRL_GCM_GET_TAG`, `EVP_CTRL_GCM_SET_TAG`).
- **Library, not source:** nothing from OpenSSL is vendored or compiled.

| Target | Library |
|---|---|
| x64 Linux | `libcrypto.so.3` |
| x64 Windows | `libcrypto-3-x64.dll` |

Verified when the package was delivered: OpenSSL 3.0.13 on Ubuntu 24.04, and Git for Windows'
OpenSSL 3.5.6 on Windows 11.

## Modules

- `x.openssl.capi` names the library, one variant per OS. It declares no functions.
- `x.openssl.crypto` is portable source.

## Surface

```neper
error NotFound
error Failed
type Crypto = struct { ... }

fn load(a: *mem.Arena) -> (*Crypto, err)
fn aead_of(c: *Crypto) -> tls.Aead
fn close(c: *Crypto) -> err
```

- `load` opens libcrypto and looks up the functions. It answers `NotFound` when the library or
  one of them is missing, and `Failed` when OpenSSL cannot make a context.
- `aead_of` gives the cipher to pass to `tls.use_aead` before a handshake, or to
  `x.microsoft.tds`'s `open_with_cipher`.
- `close` frees the context and closes the library. No stream may use the cipher after it.

The cipher seals and opens exactly as `aead.aes128_gcm_seal` and `aead.aes128_gcm_open` do. The
output is the ciphertext and then the 16-byte tag. A tag that does not match is
`aead.Authentication`, with nothing kept in the output. A short buffer is `aead.TooSmall`.

## Ownership and memory

- The `Crypto` lives in the arena given to `load`, until `close`.
- It holds one EVP context, which it re-keys for every record. So one `Crypto` serves one stream
  on one thread. A program with several connections loads one per connection.

## Licensing boundary

The package contains no OpenSSL code and links nothing at build time. OpenSSL 3 is
Apache-2.0-licensed, and whichever copy the host provides is the host's.

## Verification

`tests/selfhost/fixtures/link/x_openssl` checks the following, with one exit code per check:

- Seal and open agree byte for byte with `e.crypto.aead` over every length from 0 to 300 and up
  to 16,385 bytes, with random keys, nonces and additional data.
- A flipped bit is `aead.Authentication`, and the output is left zeroed.
- A short buffer is `aead.TooSmall`.
- A live TLS 1.3 exchange over pipes moves 100 KB each way. The client seals with OpenSSL, and
  the server uses the portable cipher.
- `use_aead` after the handshake is refused.

Its first argument, `required`, makes a missing library a failure. The suites pass it, with
`D:\tools\openssl` on PATH on Windows. Without it, a host with no libcrypto passes once `load`
has reported `NotFound`.

`link/x_tds` also stores and reads back 100 KB of text and bytes through a SQL Server
connection whose records OpenSSL seals, when the host has libcrypto.
