"""Generates tests/selfhost/fixtures/link/store/src/main.e (L127).

The conformance script lives in lib/e/store.e and is run over the memory, filesystem and HTTP
backends. The oracles for the pure parts are Python's own: `urllib.parse.quote` for the
HTTP backend's key encoding and an independent segment-based validator for key validity.

    python scripts/gen_store_test.py
"""
import os
import random
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "store", "src", "main.e")


def lit(s):
    out = []
    for b in s.encode("utf-8"):
        c = chr(b)
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif b < 32 or b >= 127:
            out.append("\\x%02x" % b)
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def valid(key):
    if not key or "\x00" in key or "\\" in key or key.startswith("/") or key.endswith("/"):
        return False
    return all(seg not in ("", ".", "..") for seg in key.split("/"))


def main():
    rnd = random.Random(127)
    alphabet = ["a", "b", ".", "/", "..", " ", "%", "ü", "€", "~", "-", "_", "?", "#", "&", "=", "+", "\x01", "\\", "A", "0"]
    keys = ["", "/", "a", "a/b", "a//b", "/a", "a/", ".", "..", "a/./b", "a/../b", "a/..", "...", "a.b", ".hidden", "a b", "ü/€", "x\\y", "a\x00b", "~tilde-_.ok"]
    for _ in range(80):
        keys.append("".join(rnd.choice(alphabet) for _ in range(rnd.randint(1, 8))))
    vec = []
    for k in keys:
        enc = quote(k.encode("utf-8"), safe="/-._~") if k and "\x00" not in k else None
        vec.append((k, valid(k), enc))
    rows = []
    for k, v, enc in vec:
        rows.append("    VKey{ key: %s, good: %s, encoded: %s }" % (lit(k), "true" if v else "false", lit(enc if enc is not None else "")))
    src = TEMPLATE.replace("@COUNT@", str(len(rows))).replace("@ROWS@", ",\n".join(rows))
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    print("key vectors:", len(rows))


TEMPLATE = r'''// `e.store`: one conformance script (lib/e/store.e) run over the memory backend, the filesystem backend and the
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

fn vectors() -> [@COUNT@]VKey {
    ret [@COUNT@]VKey{ @ROWS@ }
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
    while i < @COUNT@usize {
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
'''

main()
