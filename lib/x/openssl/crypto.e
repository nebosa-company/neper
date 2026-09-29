// AES-128-GCM from the host's OpenSSL libcrypto, as an `e.net.tls` record cipher (D1646). It is
// optional and nothing Neper ships: `load` opens whatever libcrypto the host has
// (`libcrypto.so.3`, `libcrypto-3-x64.dll`) and looks up each function by name, so a program
// that imports this package still starts where there is no OpenSSL, and `load` answers
// `NotFound`. A caller that gets `NotFound` keeps `e.crypto.aead`'s portable cipher.
//
//     let (openssl, load_error) = crypto.load(a)
//     if load_error == ok { let used = tls.use_aead(&stream, crypto.aead_of(openssl)) }
//
// Only the record cipher moves to OpenSSL, where it runs on the CPU's AES and carry-less
// multiply instructions; the handshake, the certificate checks and the key schedule stay
// `e.net.tls`'s. One `Crypto` holds one EVP context, so it serves one stream on one thread.
use e.mem
use e.os
use e.net.tls
use e.crypto.aead as aead
use x.openssl.capi

error NotFound
error Failed

type Functions = struct { ctx_new: fn() -> usize, ctx_free: fn(ctx: usize), aes_128_gcm: fn() -> usize, encrypt_init: fn(ctx: usize, cipher: usize, engine: usize, key: usize, iv: usize) -> i32, encrypt_update: fn(ctx: usize, out: usize, out_len: usize, source: usize, source_len: i32) -> i32, encrypt_final: fn(ctx: usize, out: usize, out_len: usize) -> i32, decrypt_init: fn(ctx: usize, cipher: usize, engine: usize, key: usize, iv: usize) -> i32, decrypt_update: fn(ctx: usize, out: usize, out_len: usize, source: usize, source_len: i32) -> i32, decrypt_final: fn(ctx: usize, out: usize, out_len: usize) -> i32, ctrl: fn(ctx: usize, kind: i32, arg: i32, ptr: usize) -> i32 }
type Crypto = struct { library: os.Lib, functions: Functions, ctx: usize, cipher: usize }

// EVP_CTRL_GCM_GET_TAG and EVP_CTRL_GCM_SET_TAG.
const GET_TAG: i32 = 16i32
const SET_TAG: i32 = 17i32
const TAG: usize = 16usize

// Opens the host's libcrypto and looks up the EVP AES-GCM functions. `NotFound` when there is
// no libcrypto or it lacks one of them; the `Crypto` lives in `a` until `close`.
fn load(a: *mem.Arena) -> (*Crypto, err) {
    let (library, library_error) = os.dlopen(a, capi.library())
    if library_error != ok { ret (nil, NotFound) }
    let (ctx_new, e1) = os.dlsym[fn() -> usize](a, library, "EVP_CIPHER_CTX_new")
    let (ctx_free, e2) = os.dlsym[fn(ctx: usize)](a, library, "EVP_CIPHER_CTX_free")
    let (aes_128_gcm, e3) = os.dlsym[fn() -> usize](a, library, "EVP_aes_128_gcm")
    let (encrypt_init, e4) = os.dlsym[fn(ctx: usize, cipher: usize, engine: usize, key: usize, iv: usize) -> i32](a, library, "EVP_EncryptInit_ex")
    let (encrypt_update, e5) = os.dlsym[fn(ctx: usize, out: usize, out_len: usize, source: usize, source_len: i32) -> i32](a, library, "EVP_EncryptUpdate")
    let (encrypt_final, e6) = os.dlsym[fn(ctx: usize, out: usize, out_len: usize) -> i32](a, library, "EVP_EncryptFinal_ex")
    let (decrypt_init, e7) = os.dlsym[fn(ctx: usize, cipher: usize, engine: usize, key: usize, iv: usize) -> i32](a, library, "EVP_DecryptInit_ex")
    let (decrypt_update, e8) = os.dlsym[fn(ctx: usize, out: usize, out_len: usize, source: usize, source_len: i32) -> i32](a, library, "EVP_DecryptUpdate")
    let (decrypt_final, e9) = os.dlsym[fn(ctx: usize, out: usize, out_len: usize) -> i32](a, library, "EVP_DecryptFinal_ex")
    let (ctrl, e10) = os.dlsym[fn(ctx: usize, kind: i32, arg: i32, ptr: usize) -> i32](a, library, "EVP_CIPHER_CTX_ctrl")
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok {
        let unloaded = os.dlclose(library)
        ret (nil, NotFound)
    }
    let (storage, storage_error) = mem.alloc[Crypto](a, 1usize)
    if storage_error != ok {
        let unloaded_storage = os.dlclose(library)
        ret (nil, storage_error)
    }
    let c = &storage[0usize]
    c.library = library
    c.functions = Functions { ctx_new: ctx_new, ctx_free: ctx_free, aes_128_gcm: aes_128_gcm, encrypt_init: encrypt_init, encrypt_update: encrypt_update, encrypt_final: encrypt_final, decrypt_init: decrypt_init, decrypt_update: decrypt_update, decrypt_final: decrypt_final, ctrl: ctrl }
    c.ctx = ctx_new()
    c.cipher = aes_128_gcm()
    if c.ctx == 0usize || c.cipher == 0usize {
        if c.ctx != 0usize { ctx_free(c.ctx) }
        let unloaded_context = os.dlclose(c.library)
        ret (nil, Failed)
    }
    ret (c, ok)
}

// The record cipher for `tls.use_aead`.
fn aead_of(c: *Crypto) -> tls.Aead { ret tls.Aead { ctx: mem.cast[*void](c), seal: seal, open: open } }

// Frees the EVP context and closes the library. No stream may use the cipher after it.
fn close(c: *Crypto) -> err {
    c.functions.ctx_free(c.ctx)
    c.ctx = 0usize
    ret os.dlclose(c.library)
}

fn address(bytes: []const u8) -> usize {
    if bytes.len == 0usize { ret 0usize }
    ret mem.address_of(&bytes[0usize])
}

// Ciphertext then the tag, as `aead.aes128_gcm_seal`.
fn seal(ctx: *void, dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    let c = mem.cast[*Crypto](ctx)
    if dst.len < plain.len + TAG { ret (0usize, aead.TooSmall) }
    let f = c.functions
    var k = key
    var iv = nonce
    if f.encrypt_init(c.ctx, c.cipher, 0usize, mem.address_of(&k[0usize]), mem.address_of(&iv[0usize])) != 1i32 { ret (0usize, Failed) }
    var length = 0i32
    if aad.len != 0usize && f.encrypt_update(c.ctx, 0usize, mem.address_of(&length), address(aad), i32(aad.len)) != 1i32 { ret (0usize, Failed) }
    var written = 0usize
    if plain.len != 0usize {
        if f.encrypt_update(c.ctx, address(dst), mem.address_of(&length), address(plain), i32(plain.len)) != 1i32 { ret (0usize, Failed) }
        written = usize(length)
    }
    // GCM's final step writes nothing; it still gets room of its own.
    var rest: [16]u8 = zero
    var rest_length = 0i32
    if f.encrypt_final(c.ctx, mem.address_of(&rest[0usize]), mem.address_of(&rest_length)) != 1i32 || rest_length != 0i32 || written != plain.len { ret (0usize, Failed) }
    if f.ctrl(c.ctx, GET_TAG, 16i32, mem.address_of(&dst[written])) != 1i32 { ret (0usize, Failed) }
    ret (written + TAG, ok)
}

// The plaintext of ciphertext and tag, as `aead.aes128_gcm_open`: `aead.Authentication`, and
// nothing kept in `dst`, when the tag does not match.
fn open(ctx: *void, dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    let c = mem.cast[*Crypto](ctx)
    if sealed.len < TAG { ret (0usize, aead.Authentication) }
    let cipher_len = sealed.len - TAG
    if dst.len < cipher_len { ret (0usize, aead.TooSmall) }
    let f = c.functions
    var k = key
    var iv = nonce
    if f.decrypt_init(c.ctx, c.cipher, 0usize, mem.address_of(&k[0usize]), mem.address_of(&iv[0usize])) != 1i32 { ret (0usize, Failed) }
    var length = 0i32
    if aad.len != 0usize && f.decrypt_update(c.ctx, 0usize, mem.address_of(&length), address(aad), i32(aad.len)) != 1i32 { ret (0usize, Failed) }
    var written = 0usize
    if cipher_len != 0usize {
        if f.decrypt_update(c.ctx, address(dst), mem.address_of(&length), address(sealed[0usize..cipher_len]), i32(cipher_len)) != 1i32 { ret (0usize, Failed) }
        written = usize(length)
    }
    var tag: [16]u8 = zero
    mem.copy[u8](tag[0..], sealed[cipher_len..])
    if f.ctrl(c.ctx, SET_TAG, 16i32, mem.address_of(&tag[0usize])) != 1i32 { ret (0usize, Failed) }
    var rest: [16]u8 = zero
    var rest_length = 0i32
    if f.decrypt_final(c.ctx, mem.address_of(&rest[0usize]), mem.address_of(&rest_length)) != 1i32 || written != cipher_len {
        var i = 0usize
        while i < written {
            dst[i] = 0u8
            i += 1usize
        }
        ret (0usize, aead.Authentication)
    }
    ret (written, ok)
}
