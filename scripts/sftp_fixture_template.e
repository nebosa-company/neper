// `e.net.sftp` against OpenSSH's sftp-server: scripts/sftp_vectors.py drives the server (the sftp-server.exe of Git for
// Windows, or any `sftp-server`) through a scripted session with its own independent encoder and writes one JSON line per
// request: the operation, the request bytes the independent encoder made, the response bytes the server answered and the
// meaning an independent decoder read from them. The fixture encodes each operation with the module and compares the bytes,
// decodes each response and compares the meaning; the decode-only lines are the truncated and corrupted packets.
// Generated; do not edit.
use e.algo.chain as chain
use e.algo.ir as ir
use e.algo.sync as sync
use e.data.list as list
use e.fmt.json as json
use e.io
use e.mem
use e.net.sftp as sftp
use e.os
use e.str

fn field(v: json.Value, key: str) -> (json.Value, bool) {
    let (x, found) = ir.get(v, key)
    ret (x, found)
}

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = field(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn num(v: json.Value, key: str) -> u64 {
    let (x, found) = ir.get(v, key)
    if !found { ret 0u64 }
    switch x {
    case .Number as n:
        let (value, e) = json.number_u64(n)
        if e != ok { ret 0u64 }
        ret value
    default:
        ret 0u64
    }
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn hex_nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn from_hex(a: *mem.Arena, s: str) -> []u8 {
    let (buf, e) = mem.alloc[u8](a, s.len / 2usize + 1usize)
    if e != ok { os.exit(81i32) }
    var i = 0usize
    while i + 1usize < s.len {
        buf[i / 2usize] = (hex_nibble(s[i]) << 4u8) | hex_nibble(s[i + 1usize])
        i += 2usize
    }
    ret buf[0usize..s.len / 2usize]
}

fn to_hex(a: *mem.Arena, b: []const u8) -> str {
    let (buf, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(82i32) }
    let digits = "0123456789abcdef"
    var i = 0usize
    while i < b.len {
        buf[i * 2usize] = digits[usize(b[i] >> 4u8)]
        buf[i * 2usize + 1usize] = digits[usize(b[i] & 15u8)]
        i += 1usize
    }
    let out: str = buf[0usize..b.len * 2usize]
    ret out
}

fn attrs_of(v: json.Value) -> sftp.Attrs {
    ret sftp.Attrs { flags: u32(num(v, "flags")), size: num(v, "size"), uid: u32(num(v, "uid")), gid: u32(num(v, "gid")), permissions: u32(num(v, "permissions")), atime: u32(num(v, "atime")), mtime: u32(num(v, "mtime")), extended: 0u32 }
}

fn put_num(a: *mem.Arena, o: *ir.Obj, key: str, v: u64) {
    let (n, e) = json.number_from_u64(a, v)
    let p = ir.put(o, key, json.Value{ Number: n })
}

fn attrs_json(a: *mem.Arena, x: sftp.Attrs) -> json.Value {
    var o = sync.obj(a)
    put_num(a, &o, "flags", u64(x.flags))
    put_num(a, &o, "size", x.size)
    put_num(a, &o, "uid", u64(x.uid))
    put_num(a, &o, "gid", u64(x.gid))
    put_num(a, &o, "permissions", u64(x.permissions))
    put_num(a, &o, "atime", u64(x.atime))
    put_num(a, &o, "mtime", u64(x.mtime))
    put_num(a, &o, "extended", u64(x.extended))
    ret ir.obj_value(&o)
}

fn error_json(a: *mem.Arena, name: str) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "error", sync.text(name))
    ret ir.obj_value(&o)
}

fn response_json(a: *mem.Arena, r: sftp.Response, names: []const sftp.Name) -> json.Value {
    var o = sync.obj(a)
    put_num(a, &o, "kind", u64(r.kind))
    if r.kind == sftp.FXP_VERSION {
        put_num(a, &o, "version", u64(r.version))
        put_num(a, &o, "extensions", u64(r.extensions))
        ret ir.obj_value(&o)
    }
    put_num(a, &o, "id", u64(r.id))
    if r.kind == sftp.FXP_STATUS {
        put_num(a, &o, "status", u64(r.status))
        sync.put(&o, "message", sync.text(r.message))
        sync.put(&o, "language", sync.text(r.language))
    } else if r.kind == sftp.FXP_HANDLE {
        sync.put(&o, "handle", sync.text(to_hex(a, r.handle)))
    } else if r.kind == sftp.FXP_DATA || r.kind == sftp.FXP_EXTENDED_REPLY {
        sync.put(&o, "data", sync.text(to_hex(a, r.data)))
    } else if r.kind == sftp.FXP_ATTRS {
        sync.put(&o, "attrs", attrs_json(a, r.attrs))
    } else if r.kind == sftp.FXP_NAME {
        var l = sync.empty_list(a)
        var i = 0usize
        while i < r.count {
            var n = sync.obj(a)
            sync.put(&n, "filename", sync.text(names[i].filename))
            sync.put(&n, "longname", sync.text(names[i].longname))
            sync.put(&n, "attrs", attrs_json(a, names[i].attrs))
            sync.push_value(&l, ir.obj_value(&n))
            i += 1usize
        }
        sync.put(&o, "names", json.Value{ Array: list.slice_const[json.Value](&l) })
    }
    ret ir.obj_value(&o)
}

// Encode the operation of a line with the module.
fn encode_op(a: *mem.Arena, op: json.Value, dst: []u8) -> (usize, err) {
    let name = text_field(op, "op")
    let id = u32(num(op, "id"))
    if str.eq(name, "init") {
        let (n, e) = sftp.encode_init(dst, u32(num(op, "version")))
        ret (n, e)
    }
    if str.eq(name, "open") {
        let (n, e) = sftp.encode_open(dst, id, text_field(op, "path"), u32(num(op, "flags")), attrs_of(ir.value_of(op, "attrs")))
        ret (n, e)
    }
    if str.eq(name, "close") {
        let (n, e) = sftp.encode_handle(dst, sftp.FXP_CLOSE, id, from_hex(a, text_field(op, "handle")))
        ret (n, e)
    }
    if str.eq(name, "fstat") {
        let (n, e) = sftp.encode_handle(dst, sftp.FXP_FSTAT, id, from_hex(a, text_field(op, "handle")))
        ret (n, e)
    }
    if str.eq(name, "readdir") {
        let (n, e) = sftp.encode_handle(dst, sftp.FXP_READDIR, id, from_hex(a, text_field(op, "handle")))
        ret (n, e)
    }
    if str.eq(name, "read") {
        let (n, e) = sftp.encode_read(dst, id, from_hex(a, text_field(op, "handle")), num(op, "offset"), u32(num(op, "length")))
        ret (n, e)
    }
    if str.eq(name, "write") {
        let (n, e) = sftp.encode_write(dst, id, from_hex(a, text_field(op, "handle")), num(op, "offset"), from_hex(a, text_field(op, "data")))
        ret (n, e)
    }
    if str.eq(name, "stat") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_STAT, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "lstat") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_LSTAT, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "opendir") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_OPENDIR, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "remove") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_REMOVE, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "rmdir") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_RMDIR, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "realpath") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_REALPATH, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "readlink") {
        let (n, e) = sftp.encode_path(dst, sftp.FXP_READLINK, id, text_field(op, "path"))
        ret (n, e)
    }
    if str.eq(name, "mkdir") {
        let (n, e) = sftp.encode_path_attrs(dst, sftp.FXP_MKDIR, id, text_field(op, "path"), attrs_of(ir.value_of(op, "attrs")))
        ret (n, e)
    }
    if str.eq(name, "setstat") {
        let (n, e) = sftp.encode_path_attrs(dst, sftp.FXP_SETSTAT, id, text_field(op, "path"), attrs_of(ir.value_of(op, "attrs")))
        ret (n, e)
    }
    if str.eq(name, "fsetstat") {
        let (n, e) = sftp.encode_fsetstat(dst, id, from_hex(a, text_field(op, "handle")), attrs_of(ir.value_of(op, "attrs")))
        ret (n, e)
    }
    if str.eq(name, "rename") {
        let (n, e) = sftp.encode_two_paths(dst, sftp.FXP_RENAME, id, text_field(op, "first"), text_field(op, "second"))
        ret (n, e)
    }
    if str.eq(name, "symlink") {
        let (n, e) = sftp.encode_two_paths(dst, sftp.FXP_SYMLINK, id, text_field(op, "first"), text_field(op, "second"))
        ret (n, e)
    }
    if str.eq(name, "ext_paths") {
        let (n, e) = sftp.encode_extended_paths(dst, id, text_field(op, "name"), text_field(op, "first"), text_field(op, "second"))
        ret (n, e)
    }
    if str.eq(name, "ext") {
        let (n, e) = sftp.encode_extended(dst, id, text_field(op, "name"), from_hex(a, text_field(op, "data")))
        ret (n, e)
    }
    os.exit(83i32)
    ret (0usize, sftp.Invalid)
}

fn fail(a: *mem.Arena, line: str, what: str, got: str, want: str) -> bool {
    let shown = io.print(join(a, join(a, join(a, "\n", what), " got "), join(a, join(a, got, " want "), join(a, want, join(a, "\n", line)))))
    ret false
}

fn run_case(a: *mem.Arena, line: str, c: json.Value) -> bool {
    let op = ir.value_of(c, "op")
    let req = text_field(c, "req")
    if req.len > 0usize {
        var dst: [262144]u8 = zero
        let (n, e) = encode_op(a, op, dst[0usize..])
        if e != ok { ret fail(a, line, "encode error", "", "") }
        let got = to_hex(a, dst[0usize..n])
        if !str.eq(got, req) { ret fail(a, line, "request bytes", got, req) }
    }
    let resp = text_field(c, "resp")
    if resp.len > 0usize || str.eq(text_field(c, "kind"), "decode") {
        let bytes = from_hex(a, resp)
        var cap = usize(num(c, "names_cap"))
        if cap == 0usize { cap = 64usize }
        let (names, ne) = mem.alloc[sftp.Name](a, cap)
        if ne != ok { os.exit(84i32) }
        let (used, r, de) = sftp.decode(bytes, names)
        var got: json.Value = .Null
        if de == sftp.Incomplete {
            got = error_json(a, "incomplete")
        } else if de == sftp.Invalid {
            got = error_json(a, "invalid")
        } else if de == sftp.TooLarge {
            got = error_json(a, "toolarge")
        } else if de == sftp.TooSmall {
            got = error_json(a, "toosmall")
        } else if de != ok {
            got = error_json(a, "other")
        } else {
            got = response_json(a, r, names)
            if used != bytes.len { got = error_json(a, "trailing") }
        }
        let (got_text, ge) = chain.canonical_json(a, got)
        let (want_text, we) = chain.canonical_json(a, ir.value_of(c, "e"))
        if ge != ok || we != ok { ret false }
        if !str.eq(got_text, want_text) { ret fail(a, line, "response", got_text, want_text) }
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_case(a, line, root) { ret 1u8 }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net sftp ok")
    ret ok
}
