// The host's trust roots (L109), the PEM-bundle half: Linux, the BSDs and anything else that keeps a distribution
// bundle in a file. `system_roots` honours `SSL_CERT_FILE` first (OpenSSL's and Go's override) and then tries the
// well-known bundle paths in order, answering the certificates of the first file that yields any. A caller that
// knows its path uses `from_paths`. Windows has its own variant (`hoststore.windows.e`) over the system ROOT store;
// this module's contents on a host are whatever it holds and are never asserted by fixtures, only structure.
use e.mem
use e.net.tls.roots as roots
use e.os
use e.str

error NotFound

// The ordered well-known paths: Debian/Ubuntu/Gentoo, Fedora/RHEL, openSUSE, RHEL extracted, Alpine/macOS/OpenBSD,
// FreeBSD, old Fedora.
fn path_count() -> usize { ret 7usize }

fn path_at(i: usize) -> str {
    if i == 0usize { ret "/etc/ssl/certs/ca-certificates.crt" }
    if i == 1usize { ret "/etc/pki/tls/certs/ca-bundle.crt" }
    if i == 2usize { ret "/etc/ssl/ca-bundle.pem" }
    if i == 3usize { ret "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" }
    if i == 4usize { ret "/etc/ssl/cert.pem" }
    if i == 5usize { ret "/usr/local/share/certs/ca-root-nss.crt" }
    if i == 6usize { ret "/etc/pki/tls/cacert.pem" }
    ret ""
}

// The first of `paths` that reads and holds at least one certificate; `NotFound` when none does.
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

fn system_roots(a: *mem.Arena, limit: usize) -> (roots.Bundle, err) {
    var none: roots.Bundle = zero
    let (override, env_error) = os.env(a, "SSL_CERT_FILE")
    if env_error == ok && override.len > 0usize {
        let (bundle, load_error) = roots.from_pem_file(a, override, limit)
        if load_error == ok { ret (bundle, ok) }
    }
    var i = 0usize
    while i < path_count() {
        let mark = mem.mark(a)
        let (bundle, load_error) = roots.from_pem_file(a, path_at(i), limit)
        if load_error == ok { ret (bundle, ok) }
        mem.reset(a, mark)
        i += 1usize
    }
    ret (none, NotFound)
}
