// The host's OpenSSL libcrypto (OpenSSL 3), looked up at run time by `x.openssl.crypto`; nothing
// here is bound when a program loads (D1646).
fn library() -> str { ret "libcrypto-3-x64.dll" }
