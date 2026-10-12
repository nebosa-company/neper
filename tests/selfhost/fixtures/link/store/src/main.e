// `e.store`: one conformance script (lib/e/store.e) run over the memory backend, the filesystem backend and the
// HTTP backend (through an in-process server over a memory store), then key validity and the HTTP key encoding
// against Python's own rules (scripts/gen_store_test.py). Every check has its own exit code.
use e.fs
use e.io
use e.mem
use e.net.http as http
use e.os
use e.store
use e.store.http as sh
use e.str

type VKey = struct { key: str, good: bool, encoded: str }

fn vectors() -> [100]VKey {
    ret [100]VKey{     VKey{ key: "", good: false, encoded: "" },
    VKey{ key: "/", good: false, encoded: "/" },
    VKey{ key: "a", good: true, encoded: "a" },
    VKey{ key: "a/b", good: true, encoded: "a/b" },
    VKey{ key: "a//b", good: false, encoded: "a//b" },
    VKey{ key: "/a", good: false, encoded: "/a" },
    VKey{ key: "a/", good: false, encoded: "a/" },
    VKey{ key: ".", good: false, encoded: "." },
    VKey{ key: "..", good: false, encoded: ".." },
    VKey{ key: "a/./b", good: false, encoded: "a/./b" },
    VKey{ key: "a/../b", good: false, encoded: "a/../b" },
    VKey{ key: "a/..", good: false, encoded: "a/.." },
    VKey{ key: "...", good: true, encoded: "..." },
    VKey{ key: "a.b", good: true, encoded: "a.b" },
    VKey{ key: ".hidden", good: true, encoded: ".hidden" },
    VKey{ key: "a b", good: true, encoded: "a%20b" },
    VKey{ key: "\xc3\xbc/\xe2\x82\xac", good: true, encoded: "%C3%BC/%E2%82%AC" },
    VKey{ key: "x\\y", good: false, encoded: "x%5Cy" },
    VKey{ key: "a\x00b", good: false, encoded: "" },
    VKey{ key: "~tilde-_.ok", good: true, encoded: "~tilde-_.ok" },
    VKey{ key: "A", good: true, encoded: "A" },
    VKey{ key: "aa", good: true, encoded: "aa" },
    VKey{ key: "%#\xc3\xbc~~", good: true, encoded: "%25%23%C3%BC~~" },
    VKey{ key: "b-~\x01/?/", good: false, encoded: "b-~%01/%3F/" },
    VKey{ key: "\\_", good: false, encoded: "%5C_" },
    VKey{ key: "a= A_?", good: true, encoded: "a%3D%20A_%3F" },
    VKey{ key: "/+/\xe2\x82\xacA", good: false, encoded: "/%2B/%E2%82%ACA" },
    VKey{ key: "\xe2\x82\xac_", good: true, encoded: "%E2%82%AC_" },
    VKey{ key: "\xe2\x82\xac", good: true, encoded: "%E2%82%AC" },
    VKey{ key: "#~#%", good: true, encoded: "%23~%23%25" },
    VKey{ key: "\xe2\x82\xac", good: true, encoded: "%E2%82%AC" },
    VKey{ key: "\\0A", good: false, encoded: "%5C0A" },
    VKey{ key: "\xc3\xbc&%?", good: true, encoded: "%C3%BC%26%25%3F" },
    VKey{ key: ".&\x01", good: true, encoded: ".%26%01" },
    VKey{ key: "/~\\%", good: false, encoded: "/~%5C%25" },
    VKey{ key: "\\#/\\\x01A?", good: false, encoded: "%5C%23/%5C%01A%3F" },
    VKey{ key: "&", good: true, encoded: "%26" },
    VKey{ key: "0\xc3\xbc", good: true, encoded: "0%C3%BC" },
    VKey{ key: "\x01#", good: true, encoded: "%01%23" },
    VKey{ key: "%%.?..", good: true, encoded: "%25%25.%3F.." },
    VKey{ key: "~?\\", good: false, encoded: "~%3F%5C" },
    VKey{ key: "~~_?\x01", good: true, encoded: "~~_%3F%01" },
    VKey{ key: "a..b+\xc3\xbc\xc3\xbc\xc3\xbcb", good: true, encoded: "a..b%2B%C3%BC%C3%BC%C3%BCb" },
    VKey{ key: " ", good: true, encoded: "%20" },
    VKey{ key: "-\xc3\xbc+b-\xe2\x82\xac", good: true, encoded: "-%C3%BC%2Bb-%E2%82%AC" },
    VKey{ key: "ab\x01%a", good: true, encoded: "ab%01%25a" },
    VKey{ key: "\\?", good: false, encoded: "%5C%3F" },
    VKey{ key: "a=-?&", good: true, encoded: "a%3D-%3F%26" },
    VKey{ key: "\xe2\x82\xac\xe2\x82\xac&+", good: true, encoded: "%E2%82%AC%E2%82%AC%26%2B" },
    VKey{ key: " \xc3\xbc~ a+&/", good: false, encoded: "%20%C3%BC~%20a%2B%26/" },
    VKey{ key: "\x01%\xe2\x82\xac#\xe2\x82\xac%", good: true, encoded: "%01%25%E2%82%AC%23%E2%82%AC%25" },
    VKey{ key: "%?..&#..", good: true, encoded: "%25%3F..%26%23.." },
    VKey{ key: "A", good: true, encoded: "A" },
    VKey{ key: "#%&\x01..#", good: true, encoded: "%23%25%26%01..%23" },
    VKey{ key: "\\", good: false, encoded: "%5C" },
    VKey{ key: "\xe2\x82\xac%", good: true, encoded: "%E2%82%AC%25" },
    VKey{ key: "0-_.", good: true, encoded: "0-_." },
    VKey{ key: "A", good: true, encoded: "A" },
    VKey{ key: "#=0", good: true, encoded: "%23%3D0" },
    VKey{ key: "+a_~#", good: true, encoded: "%2Ba_~%23" },
    VKey{ key: ".\xe2\x82\xac=\x01%", good: true, encoded: ".%E2%82%AC%3D%01%25" },
    VKey{ key: "..._a..&", good: true, encoded: "..._a..%26" },
    VKey{ key: "+/==", good: true, encoded: "%2B/%3D%3D" },
    VKey{ key: "&-  b b+", good: true, encoded: "%26-%20%20b%20b%2B" },
    VKey{ key: "+%..\x01+=%", good: true, encoded: "%2B%25..%01%2B%3D%25" },
    VKey{ key: "\xe2\x82\xac&b.+b", good: true, encoded: "%E2%82%AC%26b.%2Bb" },
    VKey{ key: "_= 0_+A", good: true, encoded: "_%3D%200_%2BA" },
    VKey{ key: "\x01#", good: true, encoded: "%01%23" },
    VKey{ key: "-\\~A&", good: false, encoded: "-%5C~A%26" },
    VKey{ key: "a ..A", good: true, encoded: "a%20..A" },
    VKey{ key: "._/A_", good: true, encoded: "._/A_" },
    VKey{ key: "a\\a_\xe2\x82\xac ", good: false, encoded: "a%5Ca_%E2%82%AC%20" },
    VKey{ key: "\xe2\x82\xac-.", good: true, encoded: "%E2%82%AC-." },
    VKey{ key: "+~A", good: true, encoded: "%2B~A" },
    VKey{ key: "=A%\xc3\xbc%._", good: true, encoded: "%3DA%25%C3%BC%25._" },
    VKey{ key: "?._~", good: true, encoded: "%3F._~" },
    VKey{ key: "~b\xc3\xbc-A_\\0", good: false, encoded: "~b%C3%BC-A_%5C0" },
    VKey{ key: "..", good: false, encoded: ".." },
    VKey{ key: "\\&\\\xc3\xbc/a..", good: false, encoded: "%5C%26%5C%C3%BC/a.." },
    VKey{ key: "\xe2\x82\xac?0", good: true, encoded: "%E2%82%AC%3F0" },
    VKey{ key: "/#+a-\x01/", good: false, encoded: "/%23%2Ba-%01/" },
    VKey{ key: " ?#", good: true, encoded: "%20%3F%23" },
    VKey{ key: "?\xe2\x82\xac", good: true, encoded: "%3F%E2%82%AC" },
    VKey{ key: "\xc3\xbc~=A", good: true, encoded: "%C3%BC~%3DA" },
    VKey{ key: "\xc3\xbc/\x010a&b", good: true, encoded: "%C3%BC/%010a%26b" },
    VKey{ key: "b-A", good: true, encoded: "b-A" },
    VKey{ key: "=+\xc3\xbc", good: true, encoded: "%3D%2B%C3%BC" },
    VKey{ key: "/", good: false, encoded: "/" },
    VKey{ key: "%..", good: true, encoded: "%25.." },
    VKey{ key: "..\xc3\xbc\xe2\x82\xac.\\", good: false, encoded: "..%C3%BC%E2%82%AC.%5C" },
    VKey{ key: "\\.~=_#", good: false, encoded: "%5C.~%3D_%23" },
    VKey{ key: ".0", good: true, encoded: ".0" },
    VKey{ key: "?", good: true, encoded: "%3F" },
    VKey{ key: "#", good: true, encoded: "%23" },
    VKey{ key: "b", good: true, encoded: "b" },
    VKey{ key: ".=\xc3\xbc&a", good: true, encoded: ".%3D%C3%BC%26a" },
    VKey{ key: ".", good: false, encoded: "." },
    VKey{ key: "a&=\x01.~ a", good: true, encoded: "a%26%3D%01.~%20a" },
    VKey{ key: "?-b", good: true, encoded: "%3F-b" },
    VKey{ key: "+_ ", good: true, encoded: "%2B_%20" } }
}

// ---- the in-process server behind the HTTP transport ----
type Server = struct { kv: store.MemoryStore, requests: u32, last_target: str }

fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    if c >= 65u8 { ret c - 55u8 }
    ret c - 48u8
}

// Percent-decoding of a target's path part into `a`.
fn decode(a: *mem.Arena, s: str) -> (str, err) {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret ("", e) }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 37u8 && i + 2usize < s.len {
            buf[n] = (hexval(s[i + 1usize]) << 4u8) | hexval(s[i + 2usize])
            i += 3usize
        } else {
            buf[n] = s[i]
            i += 1usize
        }
        n += 1usize
    }
    ret (buf[0usize..n], ok)
}

fn reply(a: *mem.Arena, status: u16, headers: []const http.Header, body: []const u8) -> http.Response {
    var r: http.Response = zero
    r.version = .Http11
    r.status = status
    r.reason = "x"
    r.headers = headers
    r.body = body
    ret r
}

fn serve(ctx: *void, a: *mem.Arena, req: *const http.Request) -> (http.Response, err) {
    var s = mem.cast[*Server](ctx)
    s.requests += 1u32
    s.last_target = req.target
    var none: [1]http.Header = zero
    let prefix = "/bucket/"
    if !str.starts_with(req.target, prefix) { ret (reply(a, 400u16, none[0usize..0usize], ""), ok) }
    let rest = req.target[prefix.len..]
    var kv = store.memory_store(&s.kv)
    if req.method == .Get && str.starts_with(rest, "?prefix=") {
        let (p, pe) = decode(a, rest[8usize..])
        if pe != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        var entries: [32]store.Entry = zero
        let (n, le) = store.list(&kv, a, p, entries[0usize..32usize])
        if le != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        let (b0, be) = str.builder(a, 4096usize)
        if be != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        var b = b0
        var i = 0usize
        while i < n {
            try str.push(&b, entries[i].key)
            try str.push_byte(&b, 9u8)
            try str.push_u64(&b, entries[i].size)
            try str.push_byte(&b, 10u8)
            i += 1usize
        }
        ret (reply(a, 200u16, none[0usize..0usize], str.done(&b)), ok)
    }
    let (key, ke) = decode(a, rest)
    if ke != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
    if req.method == .Put {
        let pe = store.put(&kv, a, key, req.body)
        if pe != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        ret (reply(a, 201u16, none[0usize..0usize], ""), ok)
    }
    if req.method == .Get {
        let (data, ge) = store.get(&kv, a, key, 0usize)
        if ge == store.NotFound { ret (reply(a, 404u16, none[0usize..0usize], ""), ok) }
        if ge != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        ret (reply(a, 200u16, none[0usize..0usize], data), ok)
    }
    if req.method == .Head {
        let (size, se) = store.stat(&kv, a, key)
        if se == store.NotFound { ret (reply(a, 404u16, none[0usize..0usize], ""), ok) }
        if se != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        let (hb0, hbe) = str.builder(a, 24usize)
        if hbe != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        var hb = hb0
        try str.push_u64(&hb, size)
        let (hdrs, he) = mem.alloc[http.Header](a, 1usize)
        if he != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        hdrs[0] = http.Header{ name: "Content-Length", value: str.done(&hb) }
        ret (reply(a, 200u16, hdrs[0usize..1usize], ""), ok)
    }
    if req.method == .Delete {
        let de = store.delete(&kv, a, key)
        if de != ok { ret (reply(a, 500u16, none[0usize..0usize], ""), ok) }
        ret (reply(a, 204u16, none[0usize..0usize], ""), ok)
    }
    ret (reply(a, 405u16, none[0usize..0usize], ""), ok)
}

fn hex_name(a: *mem.Arena, root: str) -> (str, err) {
    var rnd: [8]u8 = zero
    let re = os.random(rnd[0usize..8usize])
    if re != ok { ret ("", re) }
    let (b0, be) = str.builder(a, root.len + 40usize)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, root)
    try str.push(&b, "/neper-store-")
    var i = 0usize
    while i < 8usize {
        try str.push_hex_u32(&b, u32(rnd[i]))
        i += 1usize
    }
    ret (str.done(&b), ok)
}

// Removes a directory tree: the walk lists a directory before what is in it, so the
// directories are removed in reverse after the files.
fn rm_tree(a: *mem.Arena, root: str) -> err {
    let options = fs.WalkOptions{ recursive: true, follow_symlinks: false }
    let (w0, we) = fs.walk(a, root, options)
    if we != ok { ret we }
    var w = w0
    var dirs: [64]str = zero
    var count = 0usize
    while true {
        let (entry, has, ne) = fs.walk_next_err(&w)
        if ne != ok { ret ne }
        if !has { break }
        if entry.kind == .File {
            let fe = fs.remove_file(a, entry.path)
            if fe != ok { ret fe }
        } else {
            if count == 64usize { ret fs.Invalid }
            dirs[count] = entry.path
            count += 1usize
        }
    }
    while count > 0usize {
        count -= 1usize
        let de = fs.remove_dir(a, dirs[count])
        if de != ok { ret de }
    }
    ret fs.remove_dir(a, root)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1. memory
    let (m0, me) = store.memory(a, 64usize)
    if me != ok { os.exit(1i32) }
    var memory = m0
    var ms = store.memory_store(&memory)
    let c1 = store.conformance(&ms, a)
    if c1 != 0u32 { os.exit(i32(10u32 + c1)) }
    // capacity
    let (m1, me1) = store.memory(a, 2usize)
    if me1 != ok { os.exit(2i32) }
    var small = m1
    var ss = store.memory_store(&small)
    if store.put(&ss, a, "a", "1") != ok || store.put(&ss, a, "b", "1") != ok { os.exit(3i32) }
    if store.put(&ss, a, "c", "1") != store.TooLarge { os.exit(4i32) }
    if store.put(&ss, a, "a", "22") != ok { os.exit(5i32) }
    // 2. filesystem
    let (tmp, te) = fs.temp_dir(a)
    if te != ok { os.exit(6i32) }
    let (root, re) = hex_name(a, tmp)
    if re != ok { os.exit(7i32) }
    if fs.make_dirs(a, root) != ok { os.exit(8i32) }
    var fstore = store.FsStore{ root: root }
    var fs_s = store.fs_store(&fstore)
    let c2 = store.conformance(&fs_s, a)
    if c2 != 0u32 { os.exit(i32(70u32 + c2)) }
    // a stray directory or foreign file under the root is not a key, and deleting through
    // the store leaves the empty directories (listing is files only)
    let (_, nf) = store.get(&fs_s, a, "dir", 0usize)
    if nf != store.NotFound { os.exit(9i32) }
    let cleanup = rm_tree(a, root)
    // 3. HTTP through the in-process server
    let (kv0, kve) = store.memory(a, 64usize)
    if kve != ok { os.exit(130i32) }
    var server = Server{ kv: kv0, requests: 0u32, last_target: "" }
    var hs = sh.HttpStore{ transport: sh.Transport{ ctx: mem.cast[*void](&server), send: serve }, host: "objects.test", base: "/bucket" }
    var hst = sh.http_store(&hs)
    let c3 = store.conformance(&hst, a)
    if c3 != 0u32 { os.exit(i32(130u32 + c3)) }
    if server.requests < 30u32 { os.exit(131i32) }
    if store.put(&hst, a, "q/\xc3\xbc x%.txt", "v") != ok { os.exit(132i32) }
    if !str.eq(server.last_target, "/bucket/q/%C3%BC%20x%25.txt") { os.exit(133i32) }
    var entries: [4]store.Entry = zero
    let (n, ln) = store.list(&hst, a, "q/\xc3\xbc", entries[0usize..4usize])
    if ln != ok || n != 1usize || !str.eq(server.last_target, "/bucket/?prefix=q/%C3%BC") { os.exit(134i32) }
    // 4. keys: validity and the HTTP encoding against Python
    let table = vectors()
    var i = 0usize
    while i < 100usize {
        let row = table[i]
        if store.valid_key(row.key) != row.good { os.exit(140i32) }
        if row.good {
            let (enc, ee) = sh.encoded(a, row.key)
            if ee != ok || !str.eq(enc, row.encoded) { os.exit(141i32) }
        }
        i += 1usize
    }
    try io.print("store ok")
    ret ok
}
