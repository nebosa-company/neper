// The SFTP protocol, version 3 (draft-ietf-secsh-filexfer-02, which OpenSSH's sftp-server speaks), as packets over
// caller buffers: the requests a client sends (`encode_*`, each writing one length-prefixed packet to the start of `dst`
// and answering its length) and `decode`, which reads one packet of the server's from the front of `input` (`Incomplete`
// while the length prefix says more bytes than there are) as a `Response`: VERSION, STATUS, HANDLE, DATA, NAME and ATTRS,
// and EXTENDED_REPLY. The transport is the caller's: the `sftp` subsystem of an `e.net.ssh` channel, or a pipe to a
// server; nothing here reads a socket. Request ids are the caller's, and the server may answer out of order.
//
// File attributes are `Attrs` (the flags say which of size, uid and gid, permissions, access and modification times are
// present); an extended-attribute block on a response is skipped and counted, and none is written on a request.
//
// Memory: nothing is allocated. A `Response`'s `message`, `language`, `handle` and `data` are slices of `input`, valid
// while it is; the names of a NAME response are written to the caller's `names` (their strings are slices of `input`),
// and one more than fit is `TooSmall`.

error Incomplete
error Invalid
error TooSmall
error TooLarge

const FXP_INIT: u8 = 1u8
const FXP_VERSION: u8 = 2u8
const FXP_OPEN: u8 = 3u8
const FXP_CLOSE: u8 = 4u8
const FXP_READ: u8 = 5u8
const FXP_WRITE: u8 = 6u8
const FXP_LSTAT: u8 = 7u8
const FXP_FSTAT: u8 = 8u8
const FXP_SETSTAT: u8 = 9u8
const FXP_FSETSTAT: u8 = 10u8
const FXP_OPENDIR: u8 = 11u8
const FXP_READDIR: u8 = 12u8
const FXP_REMOVE: u8 = 13u8
const FXP_MKDIR: u8 = 14u8
const FXP_RMDIR: u8 = 15u8
const FXP_REALPATH: u8 = 16u8
const FXP_STAT: u8 = 17u8
const FXP_RENAME: u8 = 18u8
const FXP_READLINK: u8 = 19u8
const FXP_SYMLINK: u8 = 20u8
const FXP_STATUS: u8 = 101u8
const FXP_HANDLE: u8 = 102u8
const FXP_DATA: u8 = 103u8
const FXP_NAME: u8 = 104u8
const FXP_ATTRS: u8 = 105u8
const FXP_EXTENDED: u8 = 200u8
const FXP_EXTENDED_REPLY: u8 = 201u8

const FX_OK: u32 = 0u32
const FX_EOF: u32 = 1u32
const FX_NO_SUCH_FILE: u32 = 2u32
const FX_PERMISSION_DENIED: u32 = 3u32
const FX_FAILURE: u32 = 4u32
const FX_BAD_MESSAGE: u32 = 5u32
const FX_NO_CONNECTION: u32 = 6u32
const FX_CONNECTION_LOST: u32 = 7u32
const FX_OP_UNSUPPORTED: u32 = 8u32

const OPEN_READ: u32 = 1u32
const OPEN_WRITE: u32 = 2u32
const OPEN_APPEND: u32 = 4u32
const OPEN_CREAT: u32 = 8u32
const OPEN_TRUNC: u32 = 16u32
const OPEN_EXCL: u32 = 32u32

const ATTR_SIZE: u32 = 1u32
const ATTR_UIDGID: u32 = 2u32
const ATTR_PERMISSIONS: u32 = 4u32
const ATTR_ACMODTIME: u32 = 8u32
const ATTR_EXTENDED: u32 = 2147483648u32

const MAX_PACKET: usize = 1048576usize

type Attrs = struct { flags: u32, size: u64, uid: u32, gid: u32, permissions: u32, atime: u32, mtime: u32, extended: u32 }
type Name = struct { filename: str, longname: str, attrs: Attrs }
// `kind` is the packet type. VERSION: `version`, `extensions` (pairs skipped). STATUS: `status`, `message`, `language`.
// HANDLE: `handle`. DATA: `data`. NAME: `count` names written. ATTRS: `attrs`. EXTENDED_REPLY: `data` (the payload).
type Response = struct { kind: u8, id: u32, version: u32, extensions: u32, status: u32, message: str, language: str, handle: []const u8, data: []const u8, count: usize, attrs: Attrs }

fn no_attrs() -> Attrs { ret Attrs { flags: 0u32, size: 0u64, uid: 0u32, gid: 0u32, permissions: 0u32, atime: 0u32, mtime: 0u32, extended: 0u32 } }

// --- writing -----------------------------------------------------------------------------------------------------------

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8((v >> 24u32) & 255u32)
    b[at + 1usize] = u8((v >> 16u32) & 255u32)
    b[at + 2usize] = u8((v >> 8u32) & 255u32)
    b[at + 3usize] = u8(v & 255u32)
}

fn put64(b: []u8, at: usize, v: u64) {
    put32(b, at, u32(v >> 32u64))
    put32(b, at + 4usize, u32(v & 4294967295u64))
}

// A packet being written: the type and the room for the length, then fields appended at `at`.
fn begin(dst: []u8, kind: u8) -> (usize, err) {
    if dst.len < 5usize { ret (0usize, TooSmall) }
    dst[4usize] = kind
    ret (5usize, ok)
}

fn finish(dst: []u8, at: usize) -> (usize, err) {
    if at - 4usize > MAX_PACKET { ret (0usize, TooLarge) }
    put32(dst, 0usize, u32(at - 4usize))
    ret (at, ok)
}

fn add32(dst: []u8, at: *usize, v: u32) -> err {
    if *at + 4usize > dst.len { ret TooSmall }
    put32(dst, *at, v)
    *at += 4usize
    ret ok
}

fn add64(dst: []u8, at: *usize, v: u64) -> err {
    if *at + 8usize > dst.len { ret TooSmall }
    put64(dst, *at, v)
    *at += 8usize
    ret ok
}

fn add_bytes(dst: []u8, at: *usize, s: []const u8) -> err {
    if *at + 4usize + s.len > dst.len { ret TooSmall }
    put32(dst, *at, u32(s.len))
    var i = 0usize
    while i < s.len {
        dst[*at + 4usize + i] = s[i]
        i += 1usize
    }
    *at += 4usize + s.len
    ret ok
}

fn add_attrs(dst: []u8, at: *usize, a: Attrs) -> err {
    // no extended attributes are written
    let flags = a.flags & (ATTR_SIZE | ATTR_UIDGID | ATTR_PERMISSIONS | ATTR_ACMODTIME)
    var e = add32(dst, at, flags)
    if e != ok { ret e }
    if (flags & ATTR_SIZE) != 0u32 {
        e = add64(dst, at, a.size)
        if e != ok { ret e }
    }
    if (flags & ATTR_UIDGID) != 0u32 {
        e = add32(dst, at, a.uid)
        if e != ok { ret e }
        e = add32(dst, at, a.gid)
        if e != ok { ret e }
    }
    if (flags & ATTR_PERMISSIONS) != 0u32 {
        e = add32(dst, at, a.permissions)
        if e != ok { ret e }
    }
    if (flags & ATTR_ACMODTIME) != 0u32 {
        e = add32(dst, at, a.atime)
        if e != ok { ret e }
        e = add32(dst, at, a.mtime)
        if e != ok { ret e }
    }
    ret ok
}

// SSH_FXP_INIT with the client's version (3).
fn encode_init(dst: []u8, version: u32) -> (usize, err) {
    var (at, e) = begin(dst, FXP_INIT)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, version)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// OPENDIR, REMOVE, RMDIR, REALPATH, STAT, LSTAT and READLINK: a request id and a path.
fn encode_path(dst: []u8, kind: u8, id: u32, path: str) -> (usize, err) {
    var (at, e) = begin(dst, kind)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, path)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// CLOSE, FSTAT and READDIR: a request id and a handle.
fn encode_handle(dst: []u8, kind: u8, id: u32, handle: []const u8) -> (usize, err) {
    var (at, e) = begin(dst, kind)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, handle)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

fn encode_open(dst: []u8, id: u32, path: str, flags: u32, attrs: Attrs) -> (usize, err) {
    var (at, e) = begin(dst, FXP_OPEN)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, path)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, flags)
    if e != ok { ret (0usize, e) }
    e = add_attrs(dst, &at, attrs)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

fn encode_read(dst: []u8, id: u32, handle: []const u8, offset: u64, length: u32) -> (usize, err) {
    var (at, e) = begin(dst, FXP_READ)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, handle)
    if e != ok { ret (0usize, e) }
    e = add64(dst, &at, offset)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, length)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

fn encode_write(dst: []u8, id: u32, handle: []const u8, offset: u64, data: []const u8) -> (usize, err) {
    var (at, e) = begin(dst, FXP_WRITE)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, handle)
    if e != ok { ret (0usize, e) }
    e = add64(dst, &at, offset)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, data)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// MKDIR and SETSTAT: a path and attributes.
fn encode_path_attrs(dst: []u8, kind: u8, id: u32, path: str, attrs: Attrs) -> (usize, err) {
    var (at, e) = begin(dst, kind)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, path)
    if e != ok { ret (0usize, e) }
    e = add_attrs(dst, &at, attrs)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

fn encode_fsetstat(dst: []u8, id: u32, handle: []const u8, attrs: Attrs) -> (usize, err) {
    var (at, e) = begin(dst, FXP_FSETSTAT)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, handle)
    if e != ok { ret (0usize, e) }
    e = add_attrs(dst, &at, attrs)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// RENAME and SYMLINK: a request id and two strings (old and new path; link path and target).
fn encode_two_paths(dst: []u8, kind: u8, id: u32, first: str, second: str) -> (usize, err) {
    var (at, e) = begin(dst, kind)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, first)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, second)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// SSH_FXP_EXTENDED: a request id, the extension's name and its data as it is (OpenSSH's `posix-rename@openssh.com` is
// two strings: `encode_extended_paths` writes that shape).
fn encode_extended(dst: []u8, id: u32, name: str, data: []const u8) -> (usize, err) {
    var (at, e) = begin(dst, FXP_EXTENDED)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, name)
    if e != ok { ret (0usize, e) }
    if at + data.len > dst.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < data.len {
        dst[at + i] = data[i]
        i += 1usize
    }
    at += data.len
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// An extension whose data is two strings (`posix-rename@openssh.com`, `hardlink@openssh.com`).
fn encode_extended_paths(dst: []u8, id: u32, name: str, first: str, second: str) -> (usize, err) {
    var (at, e) = begin(dst, FXP_EXTENDED)
    if e != ok { ret (0usize, e) }
    e = add32(dst, &at, id)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, name)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, first)
    if e != ok { ret (0usize, e) }
    e = add_bytes(dst, &at, second)
    if e != ok { ret (0usize, e) }
    let (total, fe) = finish(dst, at)
    ret (total, fe)
}

// --- reading -----------------------------------------------------------------------------------------------------------

fn get32(b: []const u8, at: usize) -> u32 {
    ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize])
}

fn get64(b: []const u8, at: usize) -> u64 {
    ret (u64(get32(b, at)) << 32u64) | u64(get32(b, at + 4usize))
}

// A length-prefixed string at `at` inside `p`: the bytes, and `at` moved past them.
fn take_bytes(p: []const u8, at: *usize) -> ([]const u8, err) {
    if *at + 4usize > p.len { ret (p[0usize..0usize], Invalid) }
    let n = usize(get32(p, *at))
    if n > p.len - (*at + 4usize) { ret (p[0usize..0usize], Invalid) }
    let out = p[*at + 4usize..*at + 4usize + n]
    *at += 4usize + n
    ret (out, ok)
}

fn take_attrs(p: []const u8, at: *usize) -> (Attrs, err) {
    var a = no_attrs()
    if *at + 4usize > p.len { ret (a, Invalid) }
    a.flags = get32(p, *at)
    *at += 4usize
    if (a.flags & ATTR_SIZE) != 0u32 {
        if *at + 8usize > p.len { ret (a, Invalid) }
        a.size = get64(p, *at)
        *at += 8usize
    }
    if (a.flags & ATTR_UIDGID) != 0u32 {
        if *at + 8usize > p.len { ret (a, Invalid) }
        a.uid = get32(p, *at)
        a.gid = get32(p, *at + 4usize)
        *at += 8usize
    }
    if (a.flags & ATTR_PERMISSIONS) != 0u32 {
        if *at + 4usize > p.len { ret (a, Invalid) }
        a.permissions = get32(p, *at)
        *at += 4usize
    }
    if (a.flags & ATTR_ACMODTIME) != 0u32 {
        if *at + 8usize > p.len { ret (a, Invalid) }
        a.atime = get32(p, *at)
        a.mtime = get32(p, *at + 4usize)
        *at += 8usize
    }
    if (a.flags & ATTR_EXTENDED) != 0u32 {
        if *at + 4usize > p.len { ret (a, Invalid) }
        let count = get32(p, *at)
        *at += 4usize
        a.extended = count
        var i = 0u32
        while i < count {
            let (k, ke) = take_bytes(p, at)
            if ke != ok { ret (a, Invalid) }
            let (v, ve) = take_bytes(p, at)
            if ve != ok { ret (a, Invalid) }
            i += 1u32
        }
    }
    ret (a, ok)
}

// One packet of the server's from the front of `input`: how many bytes it took, and what it says. `Incomplete` for a
// partial packet (read more and call again), `TooLarge` past `MAX_PACKET`, `Invalid` for a packet that does not parse.
fn decode(input: []const u8, names: []Name) -> (usize, Response, err) {
    var r = Response { kind: 0u8, id: 0u32, version: 0u32, extensions: 0u32, status: 0u32, message: "", language: "", handle: input[0usize..0usize], data: input[0usize..0usize], count: 0usize, attrs: no_attrs() }
    if input.len < 4usize { ret (0usize, r, Incomplete) }
    let length = usize(get32(input, 0usize))
    if length > MAX_PACKET { ret (0usize, r, TooLarge) }
    if length < 1usize { ret (0usize, r, Invalid) }
    if input.len < 4usize + length { ret (0usize, r, Incomplete) }
    let p = input[4usize..4usize + length]
    r.kind = p[0usize]
    var at = 1usize
    if r.kind == FXP_VERSION {
        if p.len < 5usize { ret (0usize, r, Invalid) }
        r.version = get32(p, at)
        at += 4usize
        while at < p.len {
            let (k, ke) = take_bytes(p, &at)
            if ke != ok { ret (0usize, r, Invalid) }
            let (v, ve) = take_bytes(p, &at)
            if ve != ok { ret (0usize, r, Invalid) }
            r.extensions += 1u32
        }
        ret (4usize + length, r, ok)
    }
    if p.len < 5usize { ret (0usize, r, Invalid) }
    r.id = get32(p, at)
    at += 4usize
    if r.kind == FXP_STATUS {
        if at + 4usize > p.len { ret (0usize, r, Invalid) }
        r.status = get32(p, at)
        at += 4usize
        // a version 3 server sends the message and the language tag; older ones may stop after the code
        if at < p.len {
            let (m, me) = take_bytes(p, &at)
            if me != ok { ret (0usize, r, Invalid) }
            r.message = m
            let (l, le) = take_bytes(p, &at)
            if le != ok { ret (0usize, r, Invalid) }
            r.language = l
        }
    } else if r.kind == FXP_HANDLE {
        let (h, he) = take_bytes(p, &at)
        if he != ok { ret (0usize, r, Invalid) }
        r.handle = h
    } else if r.kind == FXP_DATA {
        let (d, de) = take_bytes(p, &at)
        if de != ok { ret (0usize, r, Invalid) }
        r.data = d
    } else if r.kind == FXP_NAME {
        if at + 4usize > p.len { ret (0usize, r, Invalid) }
        let count = usize(get32(p, at))
        at += 4usize
        if count > names.len { ret (0usize, r, TooSmall) }
        var i = 0usize
        while i < count {
            let (f, fe) = take_bytes(p, &at)
            if fe != ok { ret (0usize, r, Invalid) }
            let (l, le) = take_bytes(p, &at)
            if le != ok { ret (0usize, r, Invalid) }
            let (a, ae) = take_attrs(p, &at)
            if ae != ok { ret (0usize, r, Invalid) }
            names[i] = Name { filename: f, longname: l, attrs: a }
            i += 1usize
        }
        r.count = count
    } else if r.kind == FXP_ATTRS {
        let (a, ae) = take_attrs(p, &at)
        if ae != ok { ret (0usize, r, Invalid) }
        r.attrs = a
    } else if r.kind == FXP_EXTENDED_REPLY {
        r.data = p[at..p.len]
        at = p.len
    } else {
        ret (0usize, r, Invalid)
    }
    if at != p.len { ret (0usize, r, Invalid) }
    ret (4usize + length, r, ok)
}

// The text of a status code, as the protocol names it.
fn status_name(code: u32) -> str {
    if code == FX_OK { ret "OK" }
    if code == FX_EOF { ret "EOF" }
    if code == FX_NO_SUCH_FILE { ret "NO_SUCH_FILE" }
    if code == FX_PERMISSION_DENIED { ret "PERMISSION_DENIED" }
    if code == FX_FAILURE { ret "FAILURE" }
    if code == FX_BAD_MESSAGE { ret "BAD_MESSAGE" }
    if code == FX_NO_CONNECTION { ret "NO_CONNECTION" }
    if code == FX_CONNECTION_LOST { ret "CONNECTION_LOST" }
    if code == FX_OP_UNSUPPORTED { ret "OP_UNSUPPORTED" }
    ret "UNKNOWN"
}
