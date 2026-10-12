// One put/get/stat/delete/list surface over places that hold named blobs, in the manner of
// opendal and fsspec at their portable layer: a `Store` is a context pointer and five
// functions, so a backend is whatever fills them in. This module ships the memory backend
// and the filesystem backend; `e.store.http` is the third, over `e.net.http`. Vendor clouds
// are out of scope by the cloud ruling and ride their own clients.
//
// A key is a `/`-separated name with no empty, `.` or `..` segment, no leading `/` and no
// backslash or NUL: it cannot leave its store. Prefix listing is a plain string prefix
// over keys (`dir/` lists a "directory", `a` lists everything starting with `a`), sorted by
// bytes. Deleting a key that is absent is not an error; reading one is `NotFound`.
// `conformance` is the one script every backend is run through.
use e.fs
use e.mem
use e.str

type Entry = struct { key: str, size: u64 }
type Store = struct { ctx: *void, put: fn(*void, *mem.Arena, str, []const u8) -> err, get: fn(*void, *mem.Arena, str, usize) -> ([]u8, err), stat: fn(*void, *mem.Arena, str) -> (u64, err), delete: fn(*void, *mem.Arena, str) -> err, list: fn(*void, *mem.Arena, str, []Entry) -> (usize, err) }
type MemoryStore = struct { keys: []str, values: []str, count: usize }
type FsStore = struct { root: str }
error NotFound
error Invalid
error TooLarge
error Failed

// ---- keys ----------------------------------------------------------------------------

fn valid_key(key: str) -> bool {
    if key.len == 0usize || key[0] == 47u8 || key[key.len - 1usize] == 47u8 { ret false }
    var seg = 0usize
    var i = 0usize
    while i <= key.len {
        if i == key.len || key[i] == 47u8 {
            let n = i - seg
            if n == 0usize { ret false }
            if n == 1usize && key[seg] == 46u8 { ret false }
            if n == 2usize && key[seg] == 46u8 && key[seg + 1usize] == 46u8 { ret false }
            seg = i + 1usize
        } else {
            if key[i] == 0u8 || key[i] == 92u8 { ret false }
        }
        i += 1usize
    }
    ret true
}

fn has_prefix(key: str, prefix: str) -> bool {
    if prefix.len > key.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if key[i] != prefix[i] { ret false }
        i += 1usize
    }
    ret true
}

fn key_less(x: str, y: str) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret x.len < y.len
}

// ---- the surface ---------------------------------------------------------------------

fn put(s: *Store, a: *mem.Arena, key: str, data: []const u8) -> err {
    if !valid_key(key) { ret Invalid }
    ret s.put(s.ctx, a, key, data)
}

// The whole value; `limit` bounds it (0 for no bound), `TooLarge` past it.
fn get(s: *Store, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err) {
    if !valid_key(key) { ret (zero, Invalid) }
    let (data, e) = s.get(s.ctx, a, key, limit)
    ret (data, e)
}

fn stat(s: *Store, a: *mem.Arena, key: str) -> (u64, err) {
    if !valid_key(key) { ret (0u64, Invalid) }
    let (size, e) = s.stat(s.ctx, a, key)
    ret (size, e)
}

fn exists(s: *Store, a: *mem.Arena, key: str) -> (bool, err) {
    let (_, e) = stat(s, a, key)
    if e == ok { ret (true, ok) }
    if e == NotFound { ret (false, ok) }
    ret (false, e)
}

fn delete(s: *Store, a: *mem.Arena, key: str) -> err {
    if !valid_key(key) { ret Invalid }
    ret s.delete(s.ctx, a, key)
}

// Keys beginning with `prefix`, in byte order, into `out`: the count, `TooLarge` when there
// are more than `out` holds (the first `out.len` are written).
fn list(s: *Store, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err) {
    let (n, e) = s.list(s.ctx, a, prefix, out)
    ret (n, e)
}

// ---- memory --------------------------------------------------------------------------

// A store of at most `capacity` keys; values are copied into the arena, so an overwritten
// value's bytes stay allocated until the arena is reset.
fn memory(a: *mem.Arena, capacity: usize) -> (MemoryStore, err) {
    var m: MemoryStore = zero
    let (keys, ke) = mem.alloc[str](a, capacity + 1usize)
    if ke != ok { ret (m, ke) }
    let (values, ve) = mem.alloc[str](a, capacity + 1usize)
    if ve != ok { ret (m, ve) }
    m.keys = keys[0usize..capacity]
    m.values = values[0usize..capacity]
    ret (m, ok)
}

fn memory_store(m: *MemoryStore) -> Store {
    ret Store { ctx: mem.cast[*void](m), put: memory_put, get: memory_get, stat: memory_stat, delete: memory_delete, list: memory_list }
}

// The index of `key`, or where it would go.
fn memory_find(m: *MemoryStore, key: str) -> (usize, bool) {
    var low = 0usize
    var high = m.count
    while low < high {
        let mid = (low + high) / 2usize
        if key_less(m.keys[mid], key) { low = mid + 1usize } else { high = mid }
    }
    if low < m.count && str.eq(m.keys[low], key) { ret (low, true) }
    ret (low, false)
}

fn copy_str(a: *mem.Arena, s: str) -> (str, err) {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret ("", e) }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    ret (buf[0usize..s.len], ok)
}

fn memory_put(ctx: *void, a: *mem.Arena, key: str, data: []const u8) -> err {
    var m = mem.cast[*MemoryStore](ctx)
    let (at, found) = memory_find(m, key)
    let (value, ve) = copy_str(a, data)
    if ve != ok { ret ve }
    if found {
        m.values[at] = value
        ret ok
    }
    if m.count == m.keys.len { ret TooLarge }
    let (k, ke) = copy_str(a, key)
    if ke != ok { ret ke }
    var i = m.count
    while i > at {
        m.keys[i] = m.keys[i - 1usize]
        m.values[i] = m.values[i - 1usize]
        i -= 1usize
    }
    m.keys[at] = k
    m.values[at] = value
    m.count += 1usize
    ret ok
}

fn memory_get(ctx: *void, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err) {
    var m = mem.cast[*MemoryStore](ctx)
    let (at, found) = memory_find(m, key)
    if !found { ret (zero, NotFound) }
    let v = m.values[at]
    if limit != 0usize && v.len > limit { ret (zero, TooLarge) }
    let (buf, e) = mem.alloc[u8](a, v.len + 1usize)
    if e != ok { ret (zero, e) }
    var i = 0usize
    while i < v.len {
        buf[i] = v[i]
        i += 1usize
    }
    ret (buf[0usize..v.len], ok)
}

fn memory_stat(ctx: *void, a: *mem.Arena, key: str) -> (u64, err) {
    var m = mem.cast[*MemoryStore](ctx)
    let (at, found) = memory_find(m, key)
    if !found { ret (0u64, NotFound) }
    ret (u64(m.values[at].len), ok)
}

fn memory_delete(ctx: *void, a: *mem.Arena, key: str) -> err {
    var m = mem.cast[*MemoryStore](ctx)
    let (at, found) = memory_find(m, key)
    if !found { ret ok }
    var i = at
    while i + 1usize < m.count {
        m.keys[i] = m.keys[i + 1usize]
        m.values[i] = m.values[i + 1usize]
        i += 1usize
    }
    m.count -= 1usize
    ret ok
}

fn memory_list(ctx: *void, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err) {
    var m = mem.cast[*MemoryStore](ctx)
    var n = 0usize
    var i = 0usize
    while i < m.count {
        if has_prefix(m.keys[i], prefix) {
            if n == out.len { ret (n, TooLarge) }
            out[n] = Entry{ key: m.keys[i], size: u64(m.values[i].len) }
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// ---- filesystem ----------------------------------------------------------------------

fn fs_store(f: *FsStore) -> Store {
    ret Store { ctx: mem.cast[*void](f), put: fs_put, get: fs_get, stat: fs_stat, delete: fs_delete, list: fs_list }
}

fn fs_error(e: err) -> err {
    if e == ok { ret ok }
    if e == fs.NotFound { ret NotFound }
    if e == fs.Invalid { ret Invalid }
    if e == mem.Exhausted { ret e }
    ret Failed
}

// `root` + `/` + the key; a Windows host takes the forward slash as it takes its own.
fn fs_path(a: *mem.Arena, f: *FsStore, key: str) -> (str, err) {
    let (b0, be) = str.builder(a, f.root.len + key.len + 2usize)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, f.root)
    try str.push_byte(&b, 47u8)
    try str.push(&b, key)
    ret (str.done(&b), ok)
}

fn fs_put(ctx: *void, a: *mem.Arena, key: str, data: []const u8) -> err {
    var f = mem.cast[*FsStore](ctx)
    let (full, pe) = fs_path(a, f, key)
    if pe != ok { ret pe }
    // the parent directories of a nested key
    var last = 0usize
    var i = 0usize
    while i < key.len {
        if key[i] == 47u8 { last = i }
        i += 1usize
    }
    if last > 0usize {
        let (dir, de) = fs_path(a, f, key[0usize..last])
        if de != ok { ret de }
        let me = fs.make_dirs(a, dir)
        if me != ok { ret fs_error(me) }
    }
    ret fs_error(fs.write_file(a, full, data))
}

fn fs_get(ctx: *void, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err) {
    var f = mem.cast[*FsStore](ctx)
    let (full, pe) = fs_path(a, f, key)
    if pe != ok { ret (zero, pe) }
    let (info, se) = fs.stat(a, full)
    if se != ok { ret (zero, fs_error(se)) }
    if info.kind != .File { ret (zero, NotFound) }
    if limit != 0usize && info.size > u64(limit) { ret (zero, TooLarge) }
    let (data, re) = fs.read_file(a, full, 0usize)
    if re != ok { ret (zero, fs_error(re)) }
    ret (data, ok)
}

fn fs_stat(ctx: *void, a: *mem.Arena, key: str) -> (u64, err) {
    var f = mem.cast[*FsStore](ctx)
    let (full, pe) = fs_path(a, f, key)
    if pe != ok { ret (0u64, pe) }
    let (info, se) = fs.stat(a, full)
    if se != ok { ret (0u64, fs_error(se)) }
    if info.kind != .File { ret (0u64, NotFound) }
    ret (info.size, ok)
}

fn fs_delete(ctx: *void, a: *mem.Arena, key: str) -> err {
    var f = mem.cast[*FsStore](ctx)
    let (full, pe) = fs_path(a, f, key)
    if pe != ok { ret pe }
    let e = fs.remove_file(a, full)
    if e == fs.NotFound { ret ok }
    ret fs_error(e)
}

// A walk of the root, each file's path relative to it with `/` separators.
fn fs_list(ctx: *void, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err) {
    var f = mem.cast[*FsStore](ctx)
    let options = fs.WalkOptions{ recursive: true, follow_symlinks: false }
    let (w0, we) = fs.walk(a, f.root, options)
    if we != ok { ret (0usize, fs_error(we)) }
    var w = w0
    var n = 0usize
    var more = true
    while more {
        let (entry, has, ne) = fs.walk_next_err(&w)
        if ne != ok { ret (n, fs_error(ne)) }
        if !has { break }
        if entry.kind != .File { continue }
        if entry.path.len <= f.root.len + 1usize { continue }
        // the key: everything after the root and its separator, normalised to `/`
        let tail = entry.path[f.root.len + 1usize..]
        let (raw, ce) = mem.alloc[u8](a, tail.len + 1usize)
        if ce != ok { ret (n, ce) }
        var i = 0usize
        while i < tail.len {
            raw[i] = tail[i]
            if tail[i] == 92u8 { raw[i] = 47u8 }
            i += 1usize
        }
        let rel = raw[0usize..tail.len]
        if !has_prefix(rel, prefix) { continue }
        if n == out.len { ret (n, TooLarge) }
        // insertion into byte order
        var at = n
        while at > 0usize && key_less(rel, out[at - 1usize].key) {
            out[at] = out[at - 1usize]
            at -= 1usize
        }
        out[at] = Entry{ key: rel, size: entry.size }
        n += 1usize
    }
    ret (n, ok)
}

// ---- conformance ---------------------------------------------------------------------

fn bytes_equal(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// The behaviours every backend promises, in one script over an empty store. 0 when all hold,
// else the number of the first step that did not.
fn conformance(s: *Store, a: *mem.Arena) -> u32 {
    let hello = "hello"
    if put(s, a, "a.txt", hello) != ok { ret 1u32 }
    let (got, ge) = get(s, a, "a.txt", 0usize)
    if ge != ok || !bytes_equal(got, hello) { ret 2u32 }
    let (size, se) = stat(s, a, "a.txt")
    if se != ok || size != 5u64 { ret 3u32 }
    if put(s, a, "a.txt", "hello world!") != ok { ret 4u32 }
    let (got2, ge2) = get(s, a, "a.txt", 0usize)
    if ge2 != ok || !bytes_equal(got2, "hello world!") { ret 5u32 }
    // binary, nested
    var blob: [6]u8 = [6]u8{ 0, 255, 10, 13, 0, 128 }
    if put(s, a, "dir/sub/b.bin", blob[0usize..6usize]) != ok { ret 6u32 }
    let (got3, ge3) = get(s, a, "dir/sub/b.bin", 0usize)
    if ge3 != ok || !bytes_equal(got3, blob[0usize..6usize]) { ret 7u32 }
    if put(s, a, "empty", "") != ok { ret 8u32 }
    let (got4, ge4) = get(s, a, "empty", 0usize)
    if ge4 != ok || got4.len != 0usize { ret 9u32 }
    // a key with spaces and a non-ASCII name
    if put(s, a, "\xc3\xbc \xc3\xbc/x y.txt", "u") != ok { ret 10u32 }
    let (got5, ge5) = get(s, a, "\xc3\xbc \xc3\xbc/x y.txt", 0usize)
    if ge5 != ok || !bytes_equal(got5, "u") { ret 11u32 }
    // a bound on the read
    let (_, le) = get(s, a, "a.txt", 4usize)
    if le != TooLarge { ret 12u32 }
    // listing: all keys in byte order, then prefixes
    var entries: [16]Entry = zero
    let (all, ae) = list(s, a, "", entries[0usize..16usize])
    if ae != ok || all != 4usize { ret 13u32 }
    if !str.eq(entries[0].key, "a.txt") || entries[0].size != 12u64 { ret 14u32 }
    if !str.eq(entries[1].key, "dir/sub/b.bin") || entries[1].size != 6u64 { ret 15u32 }
    if !str.eq(entries[2].key, "empty") || entries[2].size != 0u64 { ret 16u32 }
    if !str.eq(entries[3].key, "\xc3\xbc \xc3\xbc/x y.txt") { ret 17u32 }
    let (d, de) = list(s, a, "dir/", entries[0usize..16usize])
    if de != ok || d != 1usize || !str.eq(entries[0].key, "dir/sub/b.bin") { ret 18u32 }
    let (p, pe) = list(s, a, "a", entries[0usize..16usize])
    if pe != ok || p != 1usize { ret 19u32 }
    let (z, ze) = list(s, a, "zzz", entries[0usize..16usize])
    if ze != ok || z != 0usize { ret 20u32 }
    let (_, te) = list(s, a, "", entries[0usize..2usize])
    if te != TooLarge { ret 21u32 }
    // byte order: "k.b" < "k/b" < "k0" ('.' is 46, '/' 47, '0' 48), and no key is another's directory
    if put(s, a, "b", "1") != ok || put(s, a, "k/b", "1") != ok || put(s, a, "k.b", "1") != ok || put(s, a, "k0", "1") != ok { ret 22u32 }
    let (ordered, oe) = list(s, a, "", entries[0usize..16usize])
    if oe != ok || ordered != 8usize { ret 23u32 }
    if !str.eq(entries[0].key, "a.txt") || !str.eq(entries[1].key, "b") || !str.eq(entries[2].key, "dir/sub/b.bin") || !str.eq(entries[3].key, "empty") { ret 24u32 }
    if !str.eq(entries[4].key, "k.b") || !str.eq(entries[5].key, "k/b") || !str.eq(entries[6].key, "k0") { ret 48u32 }
    // absent keys
    let (_, me) = get(s, a, "nope", 0usize)
    if me != NotFound { ret 25u32 }
    let (_, mse) = stat(s, a, "nope/deeper")
    if mse != NotFound { ret 26u32 }
    let (there, ee) = exists(s, a, "a.txt")
    let (gone, ge6) = exists(s, a, "nothing")
    if ee != ok || !there || ge6 != ok || gone { ret 27u32 }
    // delete is idempotent
    if delete(s, a, "a.txt") != ok { ret 28u32 }
    let (_, de2) = get(s, a, "a.txt", 0usize)
    if de2 != NotFound { ret 29u32 }
    if delete(s, a, "a.txt") != ok { ret 30u32 }
    if delete(s, a, "never-there") != ok { ret 31u32 }
    // keys that would leave the store
    if put(s, a, "", "x") != Invalid { ret 32u32 }
    if put(s, a, "/abs", "x") != Invalid { ret 33u32 }
    if put(s, a, "a//b", "x") != Invalid { ret 34u32 }
    if put(s, a, "../x", "x") != Invalid { ret 35u32 }
    if put(s, a, "a/./b", "x") != Invalid { ret 36u32 }
    if put(s, a, "a/..", "x") != Invalid { ret 37u32 }
    if put(s, a, "a\\b", "x") != Invalid { ret 38u32 }
    if put(s, a, "trail/", "x") != Invalid { ret 39u32 }
    let (_, ie) = get(s, a, "../etc/passwd", 0usize)
    if ie != Invalid { ret 40u32 }
    if delete(s, a, "x/../y") != Invalid { ret 41u32 }
    // a value of some size, byte for byte
    var big: [70000]u8 = zero
    var i = 0usize
    while i < 70000usize {
        big[i] = u8((i * 7usize + i / 251usize) & 255usize)
        i += 1usize
    }
    if put(s, a, "big/blob", big[0usize..70000usize]) != ok { ret 42u32 }
    let (back, be) = get(s, a, "big/blob", 0usize)
    if be != ok || !bytes_equal(back, big[0usize..70000usize]) { ret 43u32 }
    let (bs, bse) = stat(s, a, "big/blob")
    if bse != ok || bs != 70000u64 { ret 44u32 }
    // clean up so the next script starts from empty
    let (rest, re) = list(s, a, "", entries[0usize..16usize])
    if re != ok { ret 45u32 }
    var k = 0usize
    while k < rest {
        if delete(s, a, entries[k].key) != ok { ret 46u32 }
        k += 1usize
    }
    let (left, le2) = list(s, a, "", entries[0usize..16usize])
    if le2 != ok || left != 0usize { ret 47u32 }
    ret 0u32
}
