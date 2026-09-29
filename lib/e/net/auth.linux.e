// Integrated authentication on Linux: GSSAPI from MIT Kerberos's `libgssapi_krb5.so.2`, opened
// and looked up at run time by `client` and `server`, so a program that imports this module
// still starts where the library is missing and the call answers `NotFound`. The initiator uses
// the default credential cache (`KRB5CCNAME`, filled by `kinit`) and the acceptor the default
// keytab (`KRB5_KTNAME`). `Negotiate` is SPNEGO, `Kerberos` is krb5 itself, and `Ntlm` is
// `NotFound` unless the host has an NTLM mechanism (gss-ntlmssp). An acceptor takes the
// mechanism its first token names, whichever `server` was given. See `auth.e` for the module's
// contract; this variant is the whole module on Linux.
use e.mem
use e.os
use e.bytes

type Mechanism = enum u8 { Negotiate, Kerberos, Ntlm }
// gss_buffer_desc and gss_OID_desc.
type Buffer = struct { length: usize, value: *u8 }
type Oid = struct { length: u32, elements: *u8 }
type Functions = struct { import_name: fn(minor: *u32, name: *Buffer, name_type: *Oid, output: *usize) -> u32, init: fn(minor: *u32, credential: usize, ctx: *usize, peer: usize, mech: *Oid, flags: u32, time: u32, bindings: usize, input: *Buffer, actual_mech: usize, output: *Buffer, returned_flags: *u32, time_rec: usize) -> u32, accept: fn(minor: *u32, ctx: *usize, credential: usize, input: *Buffer, bindings: usize, source: usize, mech: usize, output: *Buffer, returned_flags: *u32, time_rec: usize, delegated: usize) -> u32, release_buffer: fn(minor: *u32, buffer: *Buffer) -> u32, release_name: fn(minor: *u32, name: *usize) -> u32, display_name: fn(minor: *u32, name: usize, output: *Buffer, name_type: usize) -> u32, inquire: fn(minor: *u32, ctx: usize, source: *usize, peer: *usize, lifetime: usize, mech: usize, flags: usize, local: usize, open: usize) -> u32, delete: fn(minor: *u32, ctx: *usize, output: usize) -> u32, acquire: fn(minor: *u32, desired: usize, time: u32, mechs: usize, usage: u32, credential: *usize, actual_mechs: usize, time_rec: usize) -> u32, release_credential: fn(minor: *u32, credential: *usize) -> u32 }
type Context = struct { library: os.Lib, f: Functions, mechanism: Mechanism, accepting: bool, ctx: usize, name: usize, credential: usize, oid: Oid, oid_bytes: [16]u8, complete: bool, failed: bool }

error NotFound
error Refused
error TooSmall
error Failed
error Invalid

const MAX_TOKEN: usize = 65536usize

// GSS_C_MUTUAL_FLAG.
const REQUEST: u32 = 2u32
// The routine-error half of a major status; the low half is supplementary information, whose
// bit 0 is GSS_S_CONTINUE_NEEDED.
const ROUTINE_ERROR: u32 = 4294901760u32
const CONTINUE_NEEDED: u32 = 1u32
const BAD_MECH: u32 = 1u32
const BAD_SIG: u32 = 6u32
const DEFECTIVE_TOKEN: u32 = 9u32
const DEFECTIVE_CREDENTIAL: u32 = 10u32
const FAILURE: u32 = 13u32
// GSS_C_ACCEPT.
const ACCEPT: u32 = 2u32

fn client(a: *mem.Arena, mechanism: Mechanism, service_principal: str) -> (*Context, err) {
    if service_principal.len == 0usize { ret (nil, Invalid) }
    let (c, load_error) = load(a, mechanism, false)
    if load_error != ok { ret (nil, load_error) }
    let (copy, copy_error) = mem.alloc[u8](a, service_principal.len)
    if copy_error != ok {
        let closed_copy = close(c)
        ret (nil, copy_error)
    }
    mem.copy[u8](copy, service_principal)
    // `service/host@REALM` is a Kerberos principal name (1.2.840.113554.1.2.2.1); `service@host`
    // is a host-based service (1.2.840.113554.1.2.1.4) the library qualifies itself.
    var type_bytes: [10]u8 = [10]u8{ 42, 134, 72, 134, 247, 18, 1, 2, 1, 4 }
    var i = 0usize
    while i < copy.len {
        if copy[i] == 47u8 {
            type_bytes[8usize] = 2u8
            type_bytes[9usize] = 1u8
        }
        i += 1usize
    }
    var name_type = Oid { length: 10u32, elements: &type_bytes[0usize] }
    var input = Buffer { length: copy.len, value: &copy[0usize] }
    var minor = 0u32
    var imported = 0usize
    if (c.f.import_name(&minor, &input, &name_type, &imported) & ROUTINE_ERROR) != 0u32 {
        let closed_name = close(c)
        ret (nil, Invalid)
    }
    c.name = imported
    ret (c, ok)
}

// The keytab's credentials are acquired here, so a host with no keytab fails now (`Failed`)
// rather than at the first token.
fn server(a: *mem.Arena, mechanism: Mechanism) -> (*Context, err) {
    let (c, load_error) = load(a, mechanism, true)
    if load_error != ok { ret (nil, load_error) }
    var minor = 0u32
    var credential = 0usize
    if (c.f.acquire(&minor, 0usize, 0u32, 0usize, ACCEPT, &credential, 0usize, 0usize) & ROUTINE_ERROR) != 0u32 {
        let closed = close(c)
        ret (nil, Failed)
    }
    c.credential = credential
    ret (c, ok)
}

fn load(a: *mem.Arena, mechanism: Mechanism, accepting: bool) -> (*Context, err) {
    let (library, library_error) = os.dlopen(a, "libgssapi_krb5.so.2")
    if library_error != ok { ret (nil, NotFound) }
    let (import_name, e1) = os.dlsym[fn(minor: *u32, name: *Buffer, name_type: *Oid, output: *usize) -> u32](a, library, "gss_import_name")
    let (init, e2) = os.dlsym[fn(minor: *u32, credential: usize, ctx: *usize, peer: usize, mech: *Oid, flags: u32, time: u32, bindings: usize, input: *Buffer, actual_mech: usize, output: *Buffer, returned_flags: *u32, time_rec: usize) -> u32](a, library, "gss_init_sec_context")
    let (accept, e3) = os.dlsym[fn(minor: *u32, ctx: *usize, credential: usize, input: *Buffer, bindings: usize, source: usize, mech: usize, output: *Buffer, returned_flags: *u32, time_rec: usize, delegated: usize) -> u32](a, library, "gss_accept_sec_context")
    let (release_buffer, e4) = os.dlsym[fn(minor: *u32, buffer: *Buffer) -> u32](a, library, "gss_release_buffer")
    let (release_name, e5) = os.dlsym[fn(minor: *u32, name: *usize) -> u32](a, library, "gss_release_name")
    let (display_name, e6) = os.dlsym[fn(minor: *u32, name: usize, output: *Buffer, name_type: usize) -> u32](a, library, "gss_display_name")
    let (inquire, e7) = os.dlsym[fn(minor: *u32, ctx: usize, source: *usize, peer: *usize, lifetime: usize, mech: usize, flags: usize, local: usize, open: usize) -> u32](a, library, "gss_inquire_context")
    let (delete, e8) = os.dlsym[fn(minor: *u32, ctx: *usize, output: usize) -> u32](a, library, "gss_delete_sec_context")
    let (acquire, e9) = os.dlsym[fn(minor: *u32, desired: usize, time: u32, mechs: usize, usage: u32, credential: *usize, actual_mechs: usize, time_rec: usize) -> u32](a, library, "gss_acquire_cred")
    let (release_credential, e10) = os.dlsym[fn(minor: *u32, credential: *usize) -> u32](a, library, "gss_release_cred")
    let (storage, storage_error) = mem.alloc[Context](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || storage_error != ok {
        let unloaded = os.dlclose(library)
        if storage_error != ok { ret (nil, storage_error) }
        ret (nil, NotFound)
    }
    let c = &storage[0usize]
    c.library = library
    c.f = Functions { import_name: import_name, init: init, accept: accept, release_buffer: release_buffer, release_name: release_name, display_name: display_name, inquire: inquire, delete: delete, acquire: acquire, release_credential: release_credential }
    c.mechanism = mechanism
    c.accepting = accepting
    c.ctx = 0usize
    c.name = 0usize
    c.credential = 0usize
    c.complete = false
    c.failed = false
    // SPNEGO 1.3.6.1.5.5.2, krb5 1.2.840.113554.1.2.2, NTLMSSP 1.3.6.1.4.1.311.2.2.10 (net_auth/vectors.py).
    let spnego: [6]u8 = [6]u8{ 43, 6, 1, 5, 5, 2 }
    let krb5: [9]u8 = [9]u8{ 42, 134, 72, 134, 247, 18, 1, 2, 2 }
    let ntlm: [10]u8 = [10]u8{ 43, 6, 1, 4, 1, 130, 55, 2, 2, 10 }
    var n = 6usize
    mem.copy[u8](c.oid_bytes[0usize..6usize], spnego[0..])
    if mechanism == .Kerberos {
        n = 9usize
        mem.copy[u8](c.oid_bytes[0usize..9usize], krb5[0..])
    }
    if mechanism == .Ntlm {
        n = 10usize
        mem.copy[u8](c.oid_bytes[0usize..10usize], ntlm[0..])
    }
    c.oid = Oid { length: u32(n), elements: &c.oid_bytes[0usize] }
    ret (c, ok)
}

fn step(c: *Context, input: []const u8, out: []u8) -> (usize, bool, err) {
    if c.complete || c.failed { ret (0usize, c.complete, Failed) }
    var minor = 0u32
    var in_buffer = Buffer { length: 0usize, value: nil }
    if input.len != 0usize {
        in_buffer.length = input.len
        in_buffer.value = mem.cast[*u8](&input[0usize])
    }
    var out_buffer = Buffer { length: 0usize, value: nil }
    var flags = 0u32
    var major = 0u32
    if c.accepting {
        major = c.f.accept(&minor, &c.ctx, c.credential, &in_buffer, 0usize, 0usize, 0usize, &out_buffer, &flags, 0usize, 0usize)
    } else {
        major = c.f.init(&minor, 0usize, &c.ctx, c.name, &c.oid, REQUEST, 0u32, 0usize, &in_buffer, 0usize, &out_buffer, &flags, 0usize)
    }
    var written = 0usize
    var result: err = ok
    if out_buffer.length != 0usize {
        if out_buffer.length > out.len {
            result = TooSmall
        } else {
            copy_foreign(out, out_buffer.value, out_buffer.length)
            written = out_buffer.length
        }
        let released = c.f.release_buffer(&minor, &out_buffer)
    }
    if (major & ROUTINE_ERROR) != 0u32 { result = refusal((major >> 16u32) & 255u32, c.accepting) }
    if result != ok {
        c.failed = true
        ret (0usize, false, result)
    }
    c.complete = (major & CONTINUE_NEEDED) == 0u32
    ret (written, c.complete, ok)
}

// An acceptor already holds its keytab's credentials (`server` acquired them), so what fails
// there is the token: MIT answers a ticket it cannot decrypt or parse with GSS_S_FAILURE and the
// Kerberos error only in the minor status. An initiator's GSS_S_FAILURE may be an unreachable
// KDC or an empty credential cache, so it stays `Failed`.
fn refusal(routine: u32, accepting: bool) -> err {
    if routine == BAD_MECH { ret NotFound }
    if routine == BAD_SIG || routine == DEFECTIVE_TOKEN || routine == DEFECTIVE_CREDENTIAL { ret Refused }
    if accepting && routine == FAILURE { ret Refused }
    ret Failed
}

fn user_name(c: *Context, dst: []u8) -> (str, err) {
    let (text, text_error) = name_of(c, true, dst)
    ret (text, text_error)
}

fn peer_name(c: *Context, dst: []u8) -> (str, err) {
    let (text, text_error) = name_of(c, c.accepting, dst)
    ret (text, text_error)
}

// The context's initiator (`source`) or acceptor, as the library displays it.
fn name_of(c: *Context, source: bool, dst: []u8) -> (str, err) {
    if !c.complete { ret ("", Failed) }
    var minor = 0u32
    var initiator = 0usize
    var acceptor = 0usize
    if (c.f.inquire(&minor, c.ctx, &initiator, &acceptor, 0usize, 0usize, 0usize, 0usize, 0usize) & ROUTINE_ERROR) != 0u32 { ret ("", Failed) }
    var chosen = acceptor
    if source { chosen = initiator }
    var text = Buffer { length: 0usize, value: nil }
    var result: err = Failed
    var n = 0usize
    if (c.f.display_name(&minor, chosen, &text, 0usize) & ROUTINE_ERROR) == 0u32 {
        result = TooSmall
        if text.length <= dst.len {
            copy_foreign(dst, text.value, text.length)
            n = text.length
            result = ok
        }
        let released_text = c.f.release_buffer(&minor, &text)
    }
    if initiator != 0usize { let released_initiator = c.f.release_name(&minor, &initiator) }
    if acceptor != 0usize { let released_acceptor = c.f.release_name(&minor, &acceptor) }
    if result != ok { ret ("", result) }
    ret (dst[0usize..n], ok)
}

fn close(c: *Context) -> err {
    var minor = 0u32
    if c.ctx != 0usize { let deleted = c.f.delete(&minor, &c.ctx, 0usize) }
    if c.name != 0usize { let released = c.f.release_name(&minor, &c.name) }
    if c.credential != 0usize { let released_credential = c.f.release_credential(&minor, &c.credential) }
    c.ctx = 0usize
    c.name = 0usize
    c.credential = 0usize
    c.failed = true
    ret os.dlclose(c.library)
}

fn copy_foreign(dst: []u8, p: *u8, n: usize) {
    var region: mem.Arena = zero
    region.base = p
    region.cap = n
    region.off = 0usize
    mem.copy[u8](dst[0usize..n], mem.view(&region, 0usize, n))
}

fn negotiate_header(dst: []u8, token: []const u8) -> (str, err) {
    let scheme = "Negotiate"
    if dst.len < scheme.len + 1usize { ret ("", TooSmall) }
    mem.copy[u8](dst[0usize..scheme.len], scheme)
    if token.len == 0usize { ret (dst[0usize..scheme.len], ok) }
    dst[scheme.len] = 32u8
    let (encoded, encode_error) = bytes.base64_encode(dst[scheme.len + 1usize..], token, .Standard, true)
    if encode_error != ok { ret ("", TooSmall) }
    ret (dst[0usize..scheme.len + 1usize + encoded.len], ok)
}

fn parse_negotiate(dst: []u8, value: str) -> ([]u8, err) {
    let scheme = "negotiate"
    var start = 0usize
    var stop = value.len
    while start < stop && value[start] == 32u8 { start += 1usize }
    while stop > start && value[stop - 1usize] == 32u8 { stop -= 1usize }
    if stop - start < scheme.len { ret (zero, Invalid) }
    var i = 0usize
    while i < scheme.len {
        if (value[start + i] | 32u8) != scheme[i] { ret (zero, Invalid) }
        i += 1usize
    }
    var at = start + scheme.len
    if at == stop { ret (dst[0usize..0usize], ok) }
    if value[at] != 32u8 { ret (zero, Invalid) }
    while value[at] == 32u8 { at += 1usize }
    let (token, decode_error) = bytes.base64_decode(dst, value[at..stop], .Standard)
    if decode_error == bytes.TooLarge { ret (zero, TooSmall) }
    if decode_error != ok { ret (zero, Invalid) }
    ret (token, ok)
}
