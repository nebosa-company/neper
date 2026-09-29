// Integrated authentication on Windows: SSPI from secur32.dll, which every Windows has, with the
// logon session's own credentials. `Negotiate` is SPNEGO (Kerberos in a domain, NTLM outside
// one), `Kerberos` and `Ntlm` name their packages directly. See `auth.e` for the module's
// contract; this variant is the whole module on Windows.
use e.mem
use e.bytes
use e.text.utf8

type Mechanism = enum u8 { Negotiate, Kerberos, Ntlm }
// An SSPI credential or context handle, two pointer-sized words.
type Handle = struct { lower: usize, upper: usize }
// SecBuffer and SecBufferDesc: one token buffer in a list of one.
type SecBuffer = struct { size: u32, kind: u32, data: usize }
type SecBufferDesc = struct { version: u32, count: u32, buffers: *SecBuffer }
// SecPkgContext_NamesW.
type Names = struct { name: *u16 }
type Context = struct { mechanism: Mechanism, accepting: bool, credential: Handle, handle: Handle, started: bool, complete: bool, failed: bool, target: []u16, principal: str }

error NotFound
error Refused
error TooSmall
error Failed
error Invalid

const MAX_TOKEN: usize = 65536usize

// SECURITY_STATUS values, as unsigned.
const SEC_E_OK: u32 = 0u32
const SEC_I_CONTINUE_NEEDED: u32 = 590610u32
const SEC_I_COMPLETE_NEEDED: u32 = 590611u32
const SEC_I_COMPLETE_AND_CONTINUE: u32 = 590612u32
const SEC_E_INSUFFICIENT_MEMORY: u32 = 2148074240u32
const SEC_E_SECPKG_NOT_FOUND: u32 = 2148074245u32
const SEC_E_INVALID_TOKEN: u32 = 2148074248u32
const SEC_E_LOGON_DENIED: u32 = 2148074252u32
const SEC_E_MESSAGE_ALTERED: u32 = 2148074255u32
const SEC_E_INCOMPLETE_MESSAGE: u32 = 2148074264u32
const SEC_E_BUFFER_TOO_SMALL: u32 = 2148074273u32

const SECPKG_CRED_INBOUND: u32 = 1u32
const SECPKG_CRED_OUTBOUND: u32 = 2u32
const SECPKG_ATTR_NAMES: u32 = 1u32
const NAME_SAM_COMPATIBLE: u32 = 2u32
const TOKEN_USER: u32 = 1u32
const SECBUFFER_TOKEN: u32 = 2u32
const SECURITY_NATIVE_DREP: u32 = 16u32
// ISC_REQ_/ASC_REQ_ MUTUAL_AUTH | CONNECTION, the same bits on both sides.
const REQUEST: u32 = 2050u32
// The longest name read back, in UTF-16 units.
const NAME_CAP: usize = 1024usize

@import("secur32.dll", "AcquireCredentialsHandleW")
extern fn raw_acquire(principal: usize, package: *const u16, usage: u32, logon_id: usize, auth_data: usize, get_key: usize, get_key_argument: usize, credential: *Handle, expiry: *u64) -> i32

@import("secur32.dll", "InitializeSecurityContextW")
extern fn raw_initialize(credential: *Handle, context: usize, target_name: usize, flags: u32, reserved1: u32, representation: u32, input: usize, reserved2: u32, new_context: *Handle, output: *SecBufferDesc, attributes: *u32, expiry: *u64) -> i32

@import("secur32.dll", "AcceptSecurityContext")
extern fn raw_accept(credential: *Handle, context: usize, input: *SecBufferDesc, flags: u32, representation: u32, new_context: *Handle, output: *SecBufferDesc, attributes: *u32, expiry: *u64) -> i32

@import("secur32.dll", "CompleteAuthToken")
extern fn raw_complete(context: *Handle, token: *SecBufferDesc) -> i32

@import("secur32.dll", "QueryContextAttributesW")
extern fn raw_query(context: *Handle, attribute: u32, buffer: *Names) -> i32

@import("secur32.dll", "FreeContextBuffer")
extern fn raw_free_buffer(buffer: *u16) -> i32

@import("secur32.dll", "QuerySecurityContextToken")
extern fn raw_context_token(context: *Handle, token: *usize) -> i32

@import("secur32.dll", "GetUserNameExW")
extern fn raw_user_name(format: u32, name: *u16, size: *u32) -> u8

@import("advapi32.dll", "GetTokenInformation")
extern fn raw_token_information(token: usize, class: u32, information: *usize, length: u32, returned: *u32) -> i32

@import("advapi32.dll", "LookupAccountSidW")
extern fn raw_account_of(system: usize, sid: usize, name: *u16, name_size: *u32, domain: *u16, domain_size: *u32, kind: *u32) -> i32

@import("kernel32.dll", "CloseHandle")
extern fn raw_close_handle(handle: usize) -> i32

@import("secur32.dll", "DeleteSecurityContext")
extern fn raw_delete(context: *Handle) -> i32

@import("secur32.dll", "FreeCredentialsHandle")
extern fn raw_free_credential(credential: *Handle) -> i32

fn client(a: *mem.Arena, mechanism: Mechanism, service_principal: str) -> (*Context, err) {
    let (wide, wide_error) = widen(a, service_principal)
    if wide_error != ok { ret (nil, wide_error) }
    let (principal, principal_error) = mem.alloc[u8](a, service_principal.len)
    if principal_error != ok { ret (nil, principal_error) }
    mem.copy[u8](principal, service_principal)
    let (c, context_error) = acquire(a, mechanism, false)
    if context_error != ok { ret (nil, context_error) }
    c.target = wide
    c.principal = principal
    ret (c, ok)
}

fn server(a: *mem.Arena, mechanism: Mechanism) -> (*Context, err) {
    let (c, context_error) = acquire(a, mechanism, true)
    ret (c, context_error)
}

fn acquire(a: *mem.Arena, mechanism: Mechanism, accepting: bool) -> (*Context, err) {
    let (storage, storage_error) = mem.alloc[Context](a, 1usize)
    if storage_error != ok { ret (nil, storage_error) }
    let c = &storage[0usize]
    c.mechanism = mechanism
    c.accepting = accepting
    c.credential = Handle { lower: 0usize, upper: 0usize }
    c.handle = Handle { lower: 0usize, upper: 0usize }
    c.started = false
    c.complete = false
    c.failed = false
    var none: []u16 = zero
    c.target = none
    c.principal = ""
    var package: [16]u16 = zero
    var name = "Negotiate"
    if mechanism == .Kerberos { name = "Kerberos" }
    if mechanism == .Ntlm { name = "NTLM" }
    var i = 0usize
    while i < name.len {
        package[i] = u16(name[i])
        i += 1usize
    }
    var usage = SECPKG_CRED_OUTBOUND
    if accepting { usage = SECPKG_CRED_INBOUND }
    var expiry = 0u64
    let status = mem.bitcast[u32](raw_acquire(0usize, &package[0usize], usage, 0usize, 0usize, 0usize, 0usize, &c.credential, &expiry))
    if status != SEC_E_OK { ret (nil, refusal(status)) }
    ret (c, ok)
}

fn step(c: *Context, input: []const u8, out: []u8) -> (usize, bool, err) {
    if c.complete || c.failed { ret (0usize, c.complete, Failed) }
    var room = out.len
    if room > MAX_TOKEN { room = MAX_TOKEN }
    var in_buffer = SecBuffer { size: u32(input.len & 2147483647usize), kind: SECBUFFER_TOKEN, data: address(input) }
    var in_desc = SecBufferDesc { version: 0u32, count: 1u32, buffers: &in_buffer }
    var out_buffer = SecBuffer { size: u32(room), kind: SECBUFFER_TOKEN, data: address(out) }
    var out_desc = SecBufferDesc { version: 0u32, count: 1u32, buffers: &out_buffer }
    var attributes = 0u32
    var expiry = 0u64
    var context = 0usize
    if c.started { context = mem.address_of(&c.handle) }
    var status = 0i32
    if c.accepting {
        status = raw_accept(&c.credential, context, &in_desc, REQUEST, SECURITY_NATIVE_DREP, &c.handle, &out_desc, &attributes, &expiry)
    } else {
        var input_desc = 0usize
        if c.started { input_desc = mem.address_of(&in_desc) }
        var spn = 0usize
        if c.target.len > 1usize { spn = mem.address_of(&c.target[0usize]) }
        status = raw_initialize(&c.credential, context, spn, REQUEST, 0u32, SECURITY_NATIVE_DREP, input_desc, 0u32, &c.handle, &out_desc, &attributes, &expiry)
    }
    var code = mem.bitcast[u32](status)
    if code == SEC_I_COMPLETE_NEEDED || code == SEC_I_COMPLETE_AND_CONTINUE {
        c.started = true
        if raw_complete(&c.handle, &out_desc) < 0i32 {
            c.failed = true
            ret (0usize, false, Failed)
        }
        if code == SEC_I_COMPLETE_NEEDED { code = SEC_E_OK } else { code = SEC_I_CONTINUE_NEEDED }
    }
    if code != SEC_E_OK && code != SEC_I_CONTINUE_NEEDED {
        c.failed = true
        ret (0usize, false, refusal(code))
    }
    c.started = true
    c.complete = code == SEC_E_OK
    ret (usize(out_buffer.size), c.complete, ok)
}

// The authenticated client as Windows names the account, `DOMAIN\user` as `whoami` prints it:
// a server reads the account from the context's token, and a client, which logs in with its
// caller's own logon session, names that session's user. When the account cannot be looked up
// (a domain controller out of reach) it is the provider's name, which for an account linked to
// a Microsoft account is `MicrosoftAccount\<address>`.
fn user_name(c: *Context, dst: []u8) -> (str, err) {
    if !c.complete { ret ("", Failed) }
    let (account, account_error) = account_name(c, dst)
    if account_error == ok { ret (account, ok) }
    var names: Names = zero
    if raw_query(&c.handle, SECPKG_ATTR_NAMES, &names) != 0i32 { ret ("", Failed) }
    let (text, text_error) = narrowed(names.name, dst)
    let freed = raw_free_buffer(names.name)
    ret (text, text_error)
}

fn account_name(c: *Context, dst: []u8) -> (str, err) {
    var name: [256]u16 = zero
    if !c.accepting {
        var size = 256u32
        if raw_user_name(NAME_SAM_COMPATIBLE, &name[0usize], &size) == 0u8 { ret ("", Failed) }
        let (own, own_error) = narrowed(&name[0usize], dst)
        ret (own, own_error)
    }
    var token = 0usize
    if raw_context_token(&c.handle, &token) != 0i32 { ret ("", Failed) }
    // TOKEN_USER: the SID's address first, then its attributes and the SID itself.
    var information: [64]usize = zero
    var returned = 0u32
    let got = raw_token_information(token, TOKEN_USER, &information[0usize], 512u32, &returned)
    let closed = raw_close_handle(token)
    if got == 0i32 { ret ("", Failed) }
    var domain: [256]u16 = zero
    var name_size = 256u32
    var domain_size = 256u32
    var kind = 0u32
    if raw_account_of(0usize, information[0usize], &name[0usize], &name_size, &domain[0usize], &domain_size, &kind) == 0i32 { ret ("", Failed) }
    let (prefix, prefix_error) = narrowed(&domain[0usize], dst)
    if prefix_error != ok { ret ("", prefix_error) }
    let n = prefix.len
    if n >= dst.len { ret ("", TooSmall) }
    dst[n] = 92u8
    let (rest, rest_error) = narrowed(&name[0usize], dst[n + 1usize..])
    if rest_error != ok { ret ("", rest_error) }
    ret (dst[0usize..n + 1usize + rest.len], ok)
}

// ponytail: a client's peer is the principal it was made for, which Kerberos's mutual
// authentication proves and NTLM does not; SECPKG_ATTR_NATIVE_NAMES when a caller needs the
// ticket's own server name.
fn peer_name(c: *Context, dst: []u8) -> (str, err) {
    if c.accepting {
        let (text, text_error) = user_name(c, dst)
        ret (text, text_error)
    }
    if !c.complete { ret ("", Failed) }
    if dst.len < c.principal.len { ret ("", TooSmall) }
    mem.copy[u8](dst[0usize..c.principal.len], c.principal)
    ret (dst[0usize..c.principal.len], ok)
}

fn close(c: *Context) -> err {
    var result: err = ok
    if c.started && raw_delete(&c.handle) != 0i32 { result = Failed }
    if raw_free_credential(&c.credential) != 0i32 { result = Failed }
    c.started = false
    c.failed = true
    ret result
}

fn refusal(code: u32) -> err {
    if code == SEC_E_INVALID_TOKEN || code == SEC_E_LOGON_DENIED || code == SEC_E_MESSAGE_ALTERED || code == SEC_E_INCOMPLETE_MESSAGE { ret Refused }
    if code == SEC_E_BUFFER_TOO_SMALL || code == SEC_E_INSUFFICIENT_MEMORY { ret TooSmall }
    if code == SEC_E_SECPKG_NOT_FOUND { ret NotFound }
    ret Failed
}

fn address(b: []const u8) -> usize {
    if b.len == 0usize { ret 0usize }
    ret mem.address_of(&b[0usize])
}

// `s` as NUL-terminated UTF-16 in `a`.
fn widen(a: *mem.Arena, s: str) -> ([]u16, err) {
    let (units, units_error) = mem.alloc[u16](a, s.len + 1usize)
    if units_error != ok { ret (units, units_error) }
    var at = 0usize
    var off = 0usize
    while off < s.len {
        let (d, d_error) = utf8.decode(s, off)
        if d_error != ok { ret (units, Invalid) }
        off += usize(d.width)
        if d.scalar < 65536u32 {
            units[at] = u16(d.scalar)
            at += 1usize
        } else {
            let v = d.scalar - 65536u32
            units[at] = u16(55296u32 + (v >> 10u32))
            units[at + 1usize] = u16(56320u32 + (v & 1023u32))
            at += 2usize
        }
    }
    units[at] = 0u16
    ret (units[0usize..at + 1usize], ok)
}

// A NUL-terminated UTF-16 string the provider owns, as UTF-8 in `dst`.
fn narrowed(p: *u16, dst: []u8) -> (str, err) {
    var region: mem.Arena = zero
    region.base = mem.cast[*u8](p)
    region.cap = NAME_CAP * 2usize
    region.off = 0usize
    let units = mem.view(&region, 0usize, NAME_CAP * 2usize)
    var n = 0usize
    while n < NAME_CAP * 2usize && (units[n] != 0u8 || units[n + 1usize] != 0u8) { n += 2usize }
    let (written, decode_error) = utf8.decode_utf16(units[0usize..n], false, dst)
    if decode_error == utf8.TooSmall { ret ("", TooSmall) }
    if decode_error != ok { ret ("", Invalid) }
    ret (dst[0usize..written], ok)
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
