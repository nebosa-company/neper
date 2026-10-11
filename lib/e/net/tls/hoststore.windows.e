// The host's trust roots (L109) on Windows: the system ROOT store ("Trusted Root Certification Authorities"; the
// current user's view, which merges the machine's) read through crypt32. `system_roots` answers the certificates
// `e.crypto.x509` can parse, deduplicated, as a `roots.Bundle`. `SSL_CERT_FILE` is honoured first, as on the other
// hosts, and `from_paths` is the same file reader. A fixture asserts structure only, never which roots a host holds.
use e.mem
use e.net.tls.roots as roots
use e.os
use e.str

error NotFound

// CERT_CONTEXT: encoding type, the encoded certificate, its length, then CertInfo and the store handle.
type CertContext = struct { encoding: u32, encoded: *u8, size: u32, info: usize, store: usize }

@import("crypt32.dll", "CertOpenSystemStoreW")
extern fn raw_open_store(provider: usize, name: *const u16) -> usize

@import("crypt32.dll", "CertEnumCertificatesInStore")
extern fn raw_enum(store: usize, previous: *CertContext) -> *CertContext

@import("crypt32.dll", "CertCloseStore")
extern fn raw_close_store(store: usize, flags: u32) -> i32

fn path_count() -> usize { ret 0usize }

fn path_at(i: usize) -> str { ret "" }

fn from_paths(a: *mem.Arena, paths: []const str, limit: usize) -> (roots.Bundle, err) {
    var none: roots.Bundle = zero
    var i = 0usize
    while i < paths.len {
        let mark = mem.mark(a)
        let (bundle, load_error) = roots.from_pem_file(a, paths[i], limit)
        if load_error == ok { ret (bundle, ok) }
        mem.reset(a, mark)
        i += 1usize
    }
    ret (none, NotFound)
}

// The ROOT store's certificates, back to back; `limit` bounds the total.
fn store_der(a: *mem.Arena, limit: usize) -> ([]const u8, err) {
    let name = "ROOT"
    let (units, units_error) = mem.alloc[u16](a, name.len + 1usize)
    if units_error != ok { ret (zero, units_error) }
    var n = 0usize
    while n < name.len {
        units[n] = u16(name[n])
        n += 1usize
    }
    units[name.len] = 0u16
    let store = raw_open_store(0usize, &units[0usize])
    if store == 0usize { ret (zero, NotFound) }
    let (buffer, buffer_error) = mem.alloc[u8](a, limit)
    if buffer_error != ok {
        let closed = raw_close_store(store, 0u32)
        ret (zero, buffer_error)
    }
    var used = 0usize
    var c = raw_enum(store, nil)
    while c != nil {
        let size = usize(c.size)
        if c.encoded != nil && used + size <= limit {
            var region: mem.Arena = zero
            region.base = c.encoded
            region.cap = size
            region.off = 0usize
            let view = mem.view(&region, 0usize, size)
            mem.copy[u8](buffer[used..used + size], view)
            used += size
        }
        c = raw_enum(store, c)
    }
    let closed_store = raw_close_store(store, 0u32)
    ret (buffer[0usize..used], ok)
}

fn system_roots(a: *mem.Arena, limit: usize) -> (roots.Bundle, err) {
    var none: roots.Bundle = zero
    let (override, env_error) = os.env(a, "SSL_CERT_FILE")
    if env_error == ok && override.len > 0usize {
        let (file_bundle, file_error) = roots.from_pem_file(a, override, limit)
        if file_error == ok { ret (file_bundle, ok) }
    }
    let (der, der_error) = store_der(a, limit)
    if der_error != ok { ret (none, der_error) }
    let (bundle, bundle_error) = roots.from_der(a, der)
    if bundle_error != ok { ret (none, NotFound) }
    ret (bundle, ok)
}
