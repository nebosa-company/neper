// Virtual filesystems behind one interface in the shape of e.fs (L119): `Vfs` is a context
// and six operations -- stat, read_file, write_file, make_dir, remove, list -- that every
// layer here implements and consumes.
//
//   Mem      an in-memory tree in the caller's arena (`mem_new`, `mem_vfs`);
//   Overlay  a writable upper over a read-only lower with copy-up and whiteouts
//            (`overlay_new`, `overlay_vfs`): a write lands in the upper after the parent
//            directories are copied up, a remove of something the lower has leaves a
//            whiteout, and a directory made again over a whiteout is opaque, so the
//            lower's old contents do not come back;
//   Union    a read-only merge of branches, the first that has a path answering for it
//            and a directory's entries merged by name (`union_new`, `union_vfs`);
//   Sub      another Vfs rooted at a directory of it, which cannot name anything outside
//            (`sub_new`, `sub_vfs`);
//   Host     the real filesystem below a root directory through e.fs, with the same
//            lexical isolation (`host_new`, `host_vfs`).
//
// Paths are `/`-rooted and cleaned before use: empty and `.` segments vanish, `..` pops,
// and a `..` that would leave the root is `Invalid`, as is a NUL byte. The errors are
// e.fs's (`fs.NotFound`, `fs.Exists`, `fs.Denied`, `fs.Invalid`) with `NotEmpty`,
// `NotDirectory`, `IsDirectory` and `TooLarge` added. Nothing is freed: a layer's tables
// and file bodies grow in its arena, and a replaced body stays there until the arena is
// reset. Lookups scan the table, so a Mem is for thousands of entries, not millions.

use e.fs
use e.mem

type Vfs = struct {
    ctx: *void,
    stat_fn: fn(*void, *mem.Arena, str) -> (fs.Entry, err),
    read_fn: fn(*void, *mem.Arena, str, usize) -> ([]u8, err),
    write_fn: fn(*void, *mem.Arena, str, []const u8) -> err,
    make_dir_fn: fn(*void, *mem.Arena, str) -> err,
    remove_fn: fn(*void, *mem.Arena, str) -> err,
    list_fn: fn(*void, *mem.Arena, str) -> ([]fs.Entry, err),
}
type Node = struct { path: str, kind: fs.EntryKind, data: []u8, size: usize }
type Mem = struct { a: *mem.Arena, nodes: []Node, count: usize }
type Mark = struct { path: str, opaque: bool }
type Overlay = struct { a: *mem.Arena, upper: Vfs, lower: Vfs, marks: []Mark, count: usize }
type Union = struct { a: *mem.Arena, branches: []Vfs }
type Sub = struct { inner: Vfs, prefix: str }
type Host = struct { root: str }

error NotEmpty
error NotDirectory
error IsDirectory
error TooLarge

// ---- paths -----------------------------------------------------------------------------

fn same_text(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn is_root(path: str) -> bool { ret path.len == 1usize && path[0] == 47u8 }

// The cleaned form of `text` in the caller's arena: `/`, or `/a/b` with no trailing slash.
fn clean(a: *mem.Arena, text: str) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, text.len + 1usize)
    if buf_error != ok { ret ("", buf_error) }
    var len = 0usize
    var i = 0usize
    while i <= text.len {
        var j = i
        while j < text.len && text[j] != 47u8 {
            if text[j] == 0u8 { ret ("", fs.Invalid) }
            j += 1usize
        }
        let seg = j - i
        if seg == 0usize || (seg == 1usize && text[i] == 46u8) {
            // empty and "." segments are nothing
        } else if seg == 2usize && text[i] == 46u8 && text[i + 1usize] == 46u8 {
            if len == 0usize { ret ("", fs.Invalid) }
            while len > 0usize && buf[len - 1usize] != 47u8 { len -= 1usize }
            len -= 1usize
        } else {
            buf[len] = 47u8
            len += 1usize
            var k = 0usize
            while k < seg {
                buf[len] = text[i + k]
                len += 1usize
                k += 1usize
            }
        }
        i = j + 1usize
    }
    if len == 0usize { ret ("/", ok) }
    ret (buf[..len], ok)
}

// The directory part of a cleaned path; the root's is the root.
fn parent_of(path: str) -> str {
    var i = path.len
    while i > 1usize && path[i - 1usize] != 47u8 { i -= 1usize }
    if i <= 1usize { ret path[..1usize] }
    ret path[..i - 1usize]
}

fn base_of(path: str) -> str {
    var i = path.len
    while i > 0usize && path[i - 1usize] != 47u8 { i -= 1usize }
    ret path[i..]
}

// True when `path` is exactly one name below the directory `dir`.
fn is_child(dir: str, path: str) -> bool {
    if is_root(path) { ret false }
    ret same_text(parent_of(path), dir)
}

// True when `path` is anywhere below `base` (not `base` itself).
fn strictly_below(path: str, base: str) -> bool {
    if is_root(base) { ret path.len > 1usize }
    if path.len <= base.len || path[base.len] != 47u8 { ret false }
    ret same_text(path[..base.len], base)
}

fn join_path(a: *mem.Arena, dir: str, name: str) -> (str, err) {
    let extra = 1usize
    if is_root(dir) {
        let (out, out_error) = mem.alloc[u8](a, name.len + extra)
        if out_error != ok { ret ("", out_error) }
        out[0] = 47u8
        mem.copy[u8](out[1..], name)
        ret (out, ok)
    }
    let (out, out_error) = mem.alloc[u8](a, dir.len + name.len + extra)
    if out_error != ok { ret ("", out_error) }
    mem.copy[u8](out[..dir.len], dir)
    out[dir.len] = 47u8
    mem.copy[u8](out[dir.len + 1usize..], name)
    ret (out, ok)
}

fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (out, out_error) = mem.alloc[u8](a, text.len)
    if out_error != ok { ret ("", out_error) }
    mem.copy[u8](out, text)
    ret (out, ok)
}

fn text_less(x: str, y: str) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret x.len < y.len
}

fn sort_entries(entries: []fs.Entry) {
    var i = 1usize
    while i < entries.len {
        let held = entries[i]
        var j = i
        while j > 0usize && text_less(held.path, entries[j - 1usize].path) {
            entries[j] = entries[j - 1usize]
            j -= 1usize
        }
        entries[j] = held
        i += 1usize
    }
}

fn root_entry() -> fs.Entry {
    var e: fs.Entry = zero
    e.path = "/"
    e.kind = .Directory
    ret e
}

fn no_entry() -> fs.Entry {
    var e: fs.Entry = zero
    e.path = ""
    ret e
}

// ---- Mem -------------------------------------------------------------------------------

fn mem_new(a: *mem.Arena, capacity: usize) -> (Mem, err) {
    var m: Mem = zero
    var want = capacity
    if want == 0usize { want = 8usize }
    let (nodes, nodes_error) = mem.alloc[Node](a, want)
    if nodes_error != ok { ret (m, nodes_error) }
    m.a = a
    m.nodes = nodes
    m.count = 0usize
    ret (m, ok)
}

fn mem_find(m: *Mem, path: str) -> (usize, bool) {
    var i = 0usize
    while i < m.count {
        if same_text(m.nodes[i].path, path) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn mem_has_children(m: *Mem, path: str) -> bool {
    var i = 0usize
    while i < m.count {
        if is_child(path, m.nodes[i].path) { ret true }
        i += 1usize
    }
    ret false
}

fn mem_add(m: *Mem, path: str, kind: fs.EntryKind) -> (usize, err) {
    if m.count == m.nodes.len {
        let (bigger, bigger_error) = mem.alloc[Node](m.a, m.nodes.len * 2usize)
        if bigger_error != ok { ret (0usize, bigger_error) }
        var i = 0usize
        while i < m.count {
            bigger[i] = m.nodes[i]
            i += 1usize
        }
        m.nodes = bigger
    }
    let (kept, kept_error) = copy_text(m.a, path)
    if kept_error != ok { ret (0usize, kept_error) }
    let at = m.count
    m.nodes[at].path = kept
    m.nodes[at].kind = kind
    m.nodes[at].size = 0usize
    var empty: []u8 = zero
    m.nodes[at].data = empty
    m.count += 1usize
    ret (at, ok)
}

fn node_entry(n: Node) -> fs.Entry {
    var e: fs.Entry = zero
    e.path = n.path
    e.kind = n.kind
    e.size = u64(n.size)
    ret e
}

// The parent of `path` must be the root or a directory.
fn mem_check_parent(m: *Mem, path: str) -> err {
    let parent = parent_of(path)
    if is_root(parent) { ret ok }
    let (at, found) = mem_find(m, parent)
    if !found { ret fs.NotFound }
    if m.nodes[at].kind != .Directory { ret NotDirectory }
    ret ok
}

fn mem_stat(ctx: *void, a: *mem.Arena, path: str) -> (fs.Entry, err) {
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (no_entry(), clean_error) }
    if is_root(p) { ret (root_entry(), ok) }
    let (at, found) = mem_find(m, p)
    if !found { ret (no_entry(), fs.NotFound) }
    ret (node_entry(m.nodes[at]), ok)
}

fn mem_read(ctx: *void, a: *mem.Arena, path: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (nothing, clean_error) }
    if is_root(p) { ret (nothing, IsDirectory) }
    let (at, found) = mem_find(m, p)
    if !found { ret (nothing, fs.NotFound) }
    if m.nodes[at].kind == .Directory { ret (nothing, IsDirectory) }
    let size = m.nodes[at].size
    if size > limit { ret (nothing, TooLarge) }
    if size == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[u8](a, size)
    if out_error != ok { ret (nothing, out_error) }
    mem.copy[u8](out, m.nodes[at].data[..size])
    ret (out, ok)
}

fn mem_write(ctx: *void, a: *mem.Arena, path: str, data: []const u8) -> err {
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret IsDirectory }
    let parent_error = mem_check_parent(m, p)
    if parent_error != ok { ret parent_error }
    var body: []u8 = zero
    if data.len > 0usize {
        let (made, made_error) = mem.alloc[u8](m.a, data.len)
        if made_error != ok { ret made_error }
        mem.copy[u8](made, data)
        body = made
    }
    let (at0, found) = mem_find(m, p)
    var at = at0
    if found {
        if m.nodes[at].kind == .Directory { ret IsDirectory }
    } else {
        let (added, add_error) = mem_add(m, p, .File)
        if add_error != ok { ret add_error }
        at = added
    }
    m.nodes[at].data = body
    m.nodes[at].size = data.len
    ret ok
}

fn mem_make_dir(ctx: *void, a: *mem.Arena, path: str) -> err {
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret fs.Exists }
    let (_, found) = mem_find(m, p)
    if found { ret fs.Exists }
    let parent_error = mem_check_parent(m, p)
    if parent_error != ok { ret parent_error }
    let (_, add_error) = mem_add(m, p, .Directory)
    ret add_error
}

fn mem_remove(ctx: *void, a: *mem.Arena, path: str) -> err {
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret fs.Invalid }
    let (at, found) = mem_find(m, p)
    if !found { ret fs.NotFound }
    if m.nodes[at].kind == .Directory && mem_has_children(m, p) { ret NotEmpty }
    m.nodes[at] = m.nodes[m.count - 1usize]
    m.count -= 1usize
    ret ok
}

fn mem_list(ctx: *void, a: *mem.Arena, path: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    let m = mem.cast[*Mem](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (nothing, clean_error) }
    if !is_root(p) {
        let (at, found) = mem_find(m, p)
        if !found { ret (nothing, fs.NotFound) }
        if m.nodes[at].kind != .Directory { ret (nothing, NotDirectory) }
    }
    var n = 0usize
    var i = 0usize
    while i < m.count {
        if is_child(p, m.nodes[i].path) { n += 1usize }
        i += 1usize
    }
    if n == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[fs.Entry](a, n)
    if out_error != ok { ret (nothing, out_error) }
    var w = 0usize
    i = 0usize
    while i < m.count {
        if is_child(p, m.nodes[i].path) {
            out[w] = node_entry(m.nodes[i])
            w += 1usize
        }
        i += 1usize
    }
    sort_entries(out)
    ret (out, ok)
}

fn mem_vfs(m: *Mem) -> Vfs {
    ret Vfs { ctx: mem.cast[*void](m), stat_fn: mem_stat, read_fn: mem_read, write_fn: mem_write, make_dir_fn: mem_make_dir, remove_fn: mem_remove, list_fn: mem_list }
}

// ---- the interface ---------------------------------------------------------------------

fn stat(a: *mem.Arena, v: *Vfs, path: str) -> (fs.Entry, err) {
    let (e, failure) = v.stat_fn(v.ctx, a, path)
    ret (e, failure)
}

fn read_file(a: *mem.Arena, v: *Vfs, path: str, limit: usize) -> ([]u8, err) {
    let (bytes, failure) = v.read_fn(v.ctx, a, path, limit)
    ret (bytes, failure)
}

fn write_file(a: *mem.Arena, v: *Vfs, path: str, data: []const u8) -> err { ret v.write_fn(v.ctx, a, path, data) }

fn make_dir(a: *mem.Arena, v: *Vfs, path: str) -> err { ret v.make_dir_fn(v.ctx, a, path) }

fn remove(a: *mem.Arena, v: *Vfs, path: str) -> err { ret v.remove_fn(v.ctx, a, path) }

fn list(a: *mem.Arena, v: *Vfs, path: str) -> ([]fs.Entry, err) {
    let (entries, failure) = v.list_fn(v.ctx, a, path)
    ret (entries, failure)
}

fn exists(a: *mem.Arena, v: *Vfs, path: str) -> (bool, err) {
    let (_, failure) = stat(a, v, path)
    if failure == fs.NotFound { ret (false, ok) }
    if failure != ok { ret (false, failure) }
    ret (true, ok)
}

// Makes every missing directory of `path`, parents first; an existing file in the way is
// `NotDirectory`.
fn make_dirs(a: *mem.Arena, v: *Vfs, path: str) -> err {
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    var at = 1usize
    while at <= p.len {
        if at == p.len || p[at] == 47u8 {
            let (e, stat_error) = stat(a, v, p[..at])
            if stat_error == fs.NotFound {
                let made = make_dir(a, v, p[..at])
                if made != ok { ret made }
            } else if stat_error != ok {
                ret stat_error
            } else if e.kind != .Directory {
                ret NotDirectory
            }
        }
        at += 1usize
    }
    ret ok
}

fn append_file(a: *mem.Arena, v: *Vfs, path: str, data: []const u8, limit: usize) -> err {
    let (old, read_error) = read_file(a, v, path, limit)
    if read_error != ok && read_error != fs.NotFound { ret read_error }
    let total = old.len + data.len
    if total > limit { ret TooLarge }
    if total == 0usize { ret write_file(a, v, path, data) }
    let (joined, joined_error) = mem.alloc[u8](a, total)
    if joined_error != ok { ret joined_error }
    if old.len > 0usize { mem.copy[u8](joined[..old.len], old) }
    if data.len > 0usize { mem.copy[u8](joined[old.len..], data) }
    ret write_file(a, v, path, joined)
}

// Copies one file from `from` to `to`, which may be different layers.
fn copy_file(a: *mem.Arena, from: *Vfs, src: str, to: *Vfs, dst: str, limit: usize) -> err {
    let (bytes, read_error) = read_file(a, from, src, limit)
    if read_error != ok { ret read_error }
    ret write_file(a, to, dst, bytes)
}

// Moves a file or a whole directory within one Vfs: the destination must not exist and
// must not lie inside the source. A directory is copied entry by entry and then removed.
fn move(a: *mem.Arena, v: *Vfs, src: str, dst: str, limit: usize) -> err {
    let (from, from_error) = clean(a, src)
    if from_error != ok { ret from_error }
    let (to, to_error) = clean(a, dst)
    if to_error != ok { ret to_error }
    if is_root(from) || is_root(to) { ret fs.Invalid }
    if same_text(from, to) { ret ok }
    if strictly_below(to, from) { ret fs.Invalid }
    let (e, stat_error) = stat(a, v, from)
    if stat_error != ok { ret stat_error }
    let (present, present_error) = exists(a, v, to)
    if present_error != ok { ret present_error }
    if present { ret fs.Exists }
    if e.kind != .Directory {
        let (bytes, read_error) = read_file(a, v, from, limit)
        if read_error != ok { ret read_error }
        let wrote = write_file(a, v, to, bytes)
        if wrote != ok { ret wrote }
        ret remove(a, v, from)
    }
    let made = make_dir(a, v, to)
    if made != ok { ret made }
    let (children, list_error) = list(a, v, from)
    if list_error != ok { ret list_error }
    var i = 0usize
    while i < children.len {
        let name = base_of(children[i].path)
        let (child_to, join_error) = join_path(a, to, name)
        if join_error != ok { ret join_error }
        let moved = move(a, v, children[i].path, child_to, limit)
        if moved != ok { ret moved }
        i += 1usize
    }
    ret remove(a, v, from)
}

// ---- Overlay ---------------------------------------------------------------------------

fn overlay_new(a: *mem.Arena, upper: Vfs, lower: Vfs, capacity: usize) -> (Overlay, err) {
    var o: Overlay = zero
    var want = capacity
    if want == 0usize { want = 8usize }
    let (marks, marks_error) = mem.alloc[Mark](a, want)
    if marks_error != ok { ret (o, marks_error) }
    o.a = a
    o.upper = upper
    o.lower = lower
    o.marks = marks
    o.count = 0usize
    ret (o, ok)
}

fn mark_find(o: *Overlay, path: str) -> (usize, bool) {
    var i = 0usize
    while i < o.count {
        if same_text(o.marks[i].path, path) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Whether the lower layer's `path` is covered by a whiteout at it or above it, or by an
// opaque directory above it.
fn hidden(o: *Overlay, path: str) -> bool {
    var i = 0usize
    while i < o.count {
        let base = o.marks[i].path
        if same_text(base, path) && !o.marks[i].opaque { ret true }
        if strictly_below(path, base) { ret true }
        i += 1usize
    }
    ret false
}

fn is_opaque(o: *Overlay, path: str) -> bool {
    let (at, found) = mark_find(o, path)
    ret found && o.marks[at].opaque
}

fn mark_set(o: *Overlay, path: str, opaque: bool) -> err {
    let (at, found) = mark_find(o, path)
    if found {
        o.marks[at].opaque = opaque
        ret ok
    }
    if o.count == o.marks.len {
        let (bigger, bigger_error) = mem.alloc[Mark](o.a, o.marks.len * 2usize)
        if bigger_error != ok { ret bigger_error }
        var i = 0usize
        while i < o.count {
            bigger[i] = o.marks[i]
            i += 1usize
        }
        o.marks = bigger
    }
    let (kept, kept_error) = copy_text(o.a, path)
    if kept_error != ok { ret kept_error }
    o.marks[o.count].path = kept
    o.marks[o.count].opaque = opaque
    o.count += 1usize
    ret ok
}

fn mark_clear(o: *Overlay, path: str) {
    let (at, found) = mark_find(o, path)
    if found {
        o.marks[at] = o.marks[o.count - 1usize]
        o.count -= 1usize
    }
}

fn mark_prune_below(o: *Overlay, base: str) {
    var i = 0usize
    while i < o.count {
        if strictly_below(o.marks[i].path, base) {
            o.marks[i] = o.marks[o.count - 1usize]
            o.count -= 1usize
        } else {
            i += 1usize
        }
    }
}

// The merged view's entry for a cleaned path.
fn overlay_lookup(o: *Overlay, a: *mem.Arena, p: str) -> (fs.Entry, err) {
    if is_root(p) { ret (root_entry(), ok) }
    let (e, upper_error) = stat(a, &o.upper, p)
    if upper_error == ok { ret (e, ok) }
    if upper_error != fs.NotFound { ret (no_entry(), upper_error) }
    if hidden(o, p) { ret (no_entry(), fs.NotFound) }
    let (found, lower_error) = stat(a, &o.lower, p)
    if lower_error != ok { ret (no_entry(), lower_error) }
    ret (found, ok)
}

fn overlay_stat(ctx: *void, a: *mem.Arena, path: str) -> (fs.Entry, err) {
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (no_entry(), clean_error) }
    let (e, failure) = overlay_lookup(o, a, p)
    ret (e, failure)
}

fn overlay_read(ctx: *void, a: *mem.Arena, path: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (nothing, clean_error) }
    if is_root(p) { ret (nothing, IsDirectory) }
    let (_, upper_error) = stat(a, &o.upper, p)
    if upper_error == ok {
        let (bytes, failure) = read_file(a, &o.upper, p, limit)
        ret (bytes, failure)
    }
    if upper_error != fs.NotFound { ret (nothing, upper_error) }
    if hidden(o, p) { ret (nothing, fs.NotFound) }
    let (bytes, failure) = read_file(a, &o.lower, p, limit)
    ret (bytes, failure)
}

// Makes `dir` (cleaned, already known to be a directory in the merged view) exist in the
// upper layer, parents first.
fn overlay_copy_up_dirs(o: *Overlay, a: *mem.Arena, dir: str) -> err {
    var at = 1usize
    while at <= dir.len {
        if at == dir.len || dir[at] == 47u8 {
            if dir.len > 1usize {
                let (_, upper_error) = stat(a, &o.upper, dir[..at])
                if upper_error == fs.NotFound {
                    let made = make_dir(a, &o.upper, dir[..at])
                    if made != ok { ret made }
                } else if upper_error != ok {
                    ret upper_error
                }
            }
        }
        at += 1usize
    }
    ret ok
}

// A new thing now stands at `p` in the upper: a lower directory there is covered as
// opaque, anything else needs no mark.
fn overlay_settle(o: *Overlay, a: *mem.Arena, p: str) -> err {
    let (at, found) = mark_find(o, p)
    if !found { ret ok }
    let (e, lower_error) = stat(a, &o.lower, p)
    if lower_error == ok && e.kind == .Directory {
        o.marks[at].opaque = true
        ret ok
    }
    mark_clear(o, p)
    ret ok
}

fn overlay_write(ctx: *void, a: *mem.Arena, path: str, data: []const u8) -> err {
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret IsDirectory }
    let (here, here_error) = overlay_lookup(o, a, p)
    if here_error == ok && here.kind == .Directory { ret IsDirectory }
    if here_error != ok && here_error != fs.NotFound { ret here_error }
    let parent = parent_of(p)
    let (par, par_error) = overlay_lookup(o, a, parent)
    if par_error != ok { ret par_error }
    if par.kind != .Directory { ret NotDirectory }
    let up = overlay_copy_up_dirs(o, a, parent)
    if up != ok { ret up }
    let wrote = write_file(a, &o.upper, p, data)
    if wrote != ok { ret wrote }
    ret overlay_settle(o, a, p)
}

fn overlay_make_dir(ctx: *void, a: *mem.Arena, path: str) -> err {
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret fs.Exists }
    let (_, here_error) = overlay_lookup(o, a, p)
    if here_error == ok { ret fs.Exists }
    if here_error != fs.NotFound { ret here_error }
    let parent = parent_of(p)
    let (par, par_error) = overlay_lookup(o, a, parent)
    if par_error != ok { ret par_error }
    if par.kind != .Directory { ret NotDirectory }
    let up = overlay_copy_up_dirs(o, a, parent)
    if up != ok { ret up }
    let made = make_dir(a, &o.upper, p)
    if made != ok { ret made }
    ret overlay_settle(o, a, p)
}

// The merged listing of a cleaned directory path.
fn overlay_children(o: *Overlay, a: *mem.Arena, p: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    var upper_entries: []fs.Entry = zero
    let (up_list, up_error) = list(a, &o.upper, p)
    if up_error == ok {
        upper_entries = up_list
    } else if up_error != fs.NotFound && up_error != NotDirectory {
        ret (nothing, up_error)
    }
    var lower_entries: []fs.Entry = zero
    if !hidden(o, p) && !is_opaque(o, p) {
        let (low_list, low_error) = list(a, &o.lower, p)
        if low_error == ok {
            lower_entries = low_list
        } else if low_error != fs.NotFound && low_error != NotDirectory {
            ret (nothing, low_error)
        }
    }
    let total = upper_entries.len + lower_entries.len
    if total == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[fs.Entry](a, total)
    if out_error != ok { ret (nothing, out_error) }
    var w = 0usize
    var i = 0usize
    while i < upper_entries.len {
        out[w] = upper_entries[i]
        w += 1usize
        i += 1usize
    }
    i = 0usize
    while i < lower_entries.len {
        var shadowed = hidden(o, lower_entries[i].path)
        var k = 0usize
        while !shadowed && k < upper_entries.len {
            if same_text(upper_entries[k].path, lower_entries[i].path) { shadowed = true }
            k += 1usize
        }
        if !shadowed {
            out[w] = lower_entries[i]
            w += 1usize
        }
        i += 1usize
    }
    sort_entries(out[..w])
    ret (out[..w], ok)
}

fn overlay_list(ctx: *void, a: *mem.Arena, path: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret (nothing, clean_error) }
    let (e, here_error) = overlay_lookup(o, a, p)
    if here_error != ok { ret (nothing, here_error) }
    if e.kind != .Directory { ret (nothing, NotDirectory) }
    let (entries, failure) = overlay_children(o, a, p)
    ret (entries, failure)
}

fn overlay_remove(ctx: *void, a: *mem.Arena, path: str) -> err {
    let o = mem.cast[*Overlay](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret fs.Invalid }
    let (e, here_error) = overlay_lookup(o, a, p)
    if here_error != ok { ret here_error }
    if e.kind == .Directory {
        let (children, children_error) = overlay_children(o, a, p)
        if children_error != ok { ret children_error }
        if children.len > 0usize { ret NotEmpty }
    }
    let (_, upper_error) = stat(a, &o.upper, p)
    if upper_error == ok {
        let removed = remove(a, &o.upper, p)
        if removed != ok { ret removed }
    } else if upper_error != fs.NotFound {
        ret upper_error
    }
    let (_, lower_error) = stat(a, &o.lower, p)
    if lower_error == ok {
        let marked = mark_set(o, p, false)
        if marked != ok { ret marked }
        // the whiteout covers everything below, so the marks below it are redundant
        mark_prune_below(o, p)
        ret ok
    }
    if lower_error != fs.NotFound { ret lower_error }
    mark_clear(o, p)
    ret ok
}

fn overlay_vfs(o: *Overlay) -> Vfs {
    ret Vfs { ctx: mem.cast[*void](o), stat_fn: overlay_stat, read_fn: overlay_read, write_fn: overlay_write, make_dir_fn: overlay_make_dir, remove_fn: overlay_remove, list_fn: overlay_list }
}

// ---- Union -----------------------------------------------------------------------------

fn union_new(a: *mem.Arena, branches: []const Vfs) -> (Union, err) {
    var u: Union = zero
    if branches.len == 0usize { ret (u, fs.Invalid) }
    let (copied, copied_error) = mem.alloc[Vfs](a, branches.len)
    if copied_error != ok { ret (u, copied_error) }
    var i = 0usize
    while i < branches.len {
        copied[i] = branches[i]
        i += 1usize
    }
    u.a = a
    u.branches = copied
    ret (u, ok)
}

fn union_stat(ctx: *void, a: *mem.Arena, path: str) -> (fs.Entry, err) {
    let u = mem.cast[*Union](ctx)
    var i = 0usize
    while i < u.branches.len {
        let (e, failure) = stat(a, &u.branches[i], path)
        if failure == ok { ret (e, ok) }
        if failure != fs.NotFound { ret (no_entry(), failure) }
        i += 1usize
    }
    ret (no_entry(), fs.NotFound)
}

fn union_read(ctx: *void, a: *mem.Arena, path: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let u = mem.cast[*Union](ctx)
    var i = 0usize
    while i < u.branches.len {
        let (_, failure) = stat(a, &u.branches[i], path)
        if failure == ok {
            let (bytes, read_error) = read_file(a, &u.branches[i], path, limit)
            ret (bytes, read_error)
        }
        if failure != fs.NotFound { ret (nothing, failure) }
        i += 1usize
    }
    ret (nothing, fs.NotFound)
}

fn union_list(ctx: *void, a: *mem.Arena, path: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    let u = mem.cast[*Union](ctx)
    let (first, first_error) = union_stat(ctx, a, path)
    if first_error != ok { ret (nothing, first_error) }
    if first.kind != .Directory { ret (nothing, NotDirectory) }
    var total = 0usize
    var i = 0usize
    while i < u.branches.len {
        let (entries, failure) = list(a, &u.branches[i], path)
        if failure == ok { total += entries.len }
        i += 1usize
    }
    if total == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[fs.Entry](a, total)
    if out_error != ok { ret (nothing, out_error) }
    var w = 0usize
    i = 0usize
    while i < u.branches.len {
        let (entries, failure) = list(a, &u.branches[i], path)
        if failure == ok {
            var k = 0usize
            while k < entries.len {
                var seen = false
                var s = 0usize
                while !seen && s < w {
                    if same_text(out[s].path, entries[k].path) { seen = true }
                    s += 1usize
                }
                if !seen {
                    out[w] = entries[k]
                    w += 1usize
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    sort_entries(out[..w])
    ret (out[..w], ok)
}

fn union_write(ctx: *void, a: *mem.Arena, path: str, data: []const u8) -> err { ret fs.Denied }

fn union_make_dir(ctx: *void, a: *mem.Arena, path: str) -> err { ret fs.Denied }

fn union_remove(ctx: *void, a: *mem.Arena, path: str) -> err { ret fs.Denied }

fn union_vfs(u: *Union) -> Vfs {
    ret Vfs { ctx: mem.cast[*void](u), stat_fn: union_stat, read_fn: union_read, write_fn: union_write, make_dir_fn: union_make_dir, remove_fn: union_remove, list_fn: union_list }
}

// ---- Sub -------------------------------------------------------------------------------

fn sub_new(a: *mem.Arena, inner: Vfs, prefix: str) -> (Sub, err) {
    var s: Sub = zero
    let (p, clean_error) = clean(a, prefix)
    if clean_error != ok { ret (s, clean_error) }
    s.inner = inner
    s.prefix = p
    ret (s, ok)
}

// The inner path of a path given to the Sub: cleaned inside the Sub's own root first, so
// a `..` cannot climb out of the prefix.
fn sub_inner_path(s: *Sub, a: *mem.Arena, path: str) -> (str, err) {
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret ("", clean_error) }
    if is_root(s.prefix) { ret (p, ok) }
    if is_root(p) { ret (s.prefix, ok) }
    let (joined, joined_error) = mem.alloc[u8](a, s.prefix.len + p.len)
    if joined_error != ok { ret ("", joined_error) }
    mem.copy[u8](joined[..s.prefix.len], s.prefix)
    mem.copy[u8](joined[s.prefix.len..], p)
    ret (joined, ok)
}

fn sub_outer_entry(s: *Sub, e: fs.Entry) -> fs.Entry {
    var out = e
    if is_root(s.prefix) { ret out }
    if e.path.len <= s.prefix.len {
        out.path = "/"
    } else {
        out.path = e.path[s.prefix.len..]
    }
    ret out
}

fn sub_stat(ctx: *void, a: *mem.Arena, path: str) -> (fs.Entry, err) {
    let s = mem.cast[*Sub](ctx)
    let (q, path_error) = sub_inner_path(s, a, path)
    if path_error != ok { ret (no_entry(), path_error) }
    let (e, failure) = stat(a, &s.inner, q)
    if failure != ok { ret (no_entry(), failure) }
    ret (sub_outer_entry(s, e), ok)
}

fn sub_read(ctx: *void, a: *mem.Arena, path: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let s = mem.cast[*Sub](ctx)
    let (q, path_error) = sub_inner_path(s, a, path)
    if path_error != ok { ret (nothing, path_error) }
    let (bytes, failure) = read_file(a, &s.inner, q, limit)
    ret (bytes, failure)
}

fn sub_write(ctx: *void, a: *mem.Arena, path: str, data: []const u8) -> err {
    let s = mem.cast[*Sub](ctx)
    let (q, path_error) = sub_inner_path(s, a, path)
    if path_error != ok { ret path_error }
    ret write_file(a, &s.inner, q, data)
}

fn sub_make_dir(ctx: *void, a: *mem.Arena, path: str) -> err {
    let s = mem.cast[*Sub](ctx)
    let (q, path_error) = sub_inner_path(s, a, path)
    if path_error != ok { ret path_error }
    ret make_dir(a, &s.inner, q)
}

fn sub_remove(ctx: *void, a: *mem.Arena, path: str) -> err {
    let s = mem.cast[*Sub](ctx)
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret clean_error }
    if is_root(p) { ret fs.Invalid }
    let (q, path_error) = sub_inner_path(s, a, p)
    if path_error != ok { ret path_error }
    ret remove(a, &s.inner, q)
}

fn sub_list(ctx: *void, a: *mem.Arena, path: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    let s = mem.cast[*Sub](ctx)
    let (q, path_error) = sub_inner_path(s, a, path)
    if path_error != ok { ret (nothing, path_error) }
    let (entries, failure) = list(a, &s.inner, q)
    if failure != ok { ret (nothing, failure) }
    var i = 0usize
    while i < entries.len {
        entries[i] = sub_outer_entry(s, entries[i])
        i += 1usize
    }
    ret (entries, ok)
}

fn sub_vfs(s: *Sub) -> Vfs {
    ret Vfs { ctx: mem.cast[*void](s), stat_fn: sub_stat, read_fn: sub_read, write_fn: sub_write, make_dir_fn: sub_make_dir, remove_fn: sub_remove, list_fn: sub_list }
}

// ---- Host ------------------------------------------------------------------------------

// `root` is a real directory; a trailing separator is dropped.
fn host_new(root: str) -> Host {
    var h: Host = zero
    var n = root.len
    while n > 1usize && (root[n - 1usize] == 47u8 || root[n - 1usize] == 92u8) { n -= 1usize }
    h.root = root[..n]
    ret h
}

// The host path of a cleaned Vfs path, refusing a backslash or a colon, which a host may
// read as a separator or a drive.
fn host_path(h: *Host, a: *mem.Arena, path: str) -> (str, str, err) {
    let (p, clean_error) = clean(a, path)
    if clean_error != ok { ret ("", "", clean_error) }
    var i = 0usize
    while i < p.len {
        if p[i] == 92u8 || p[i] == 58u8 { ret ("", "", fs.Invalid) }
        i += 1usize
    }
    if is_root(p) { ret (p, h.root, ok) }
    let (full, full_error) = mem.alloc[u8](a, h.root.len + p.len)
    if full_error != ok { ret ("", "", full_error) }
    mem.copy[u8](full[..h.root.len], h.root)
    mem.copy[u8](full[h.root.len..], p)
    ret (p, full, ok)
}

fn host_stat(ctx: *void, a: *mem.Arena, path: str) -> (fs.Entry, err) {
    let h = mem.cast[*Host](ctx)
    let (p, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret (no_entry(), path_error) }
    let (e, failure) = fs.stat(a, full)
    if failure != ok { ret (no_entry(), failure) }
    var out = e
    out.path = p
    ret (out, ok)
}

fn host_read(ctx: *void, a: *mem.Arena, path: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let h = mem.cast[*Host](ctx)
    let (_, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret (nothing, path_error) }
    let (bytes, failure) = fs.read_file(a, full, limit)
    ret (bytes, failure)
}

fn host_write(ctx: *void, a: *mem.Arena, path: str, data: []const u8) -> err {
    let h = mem.cast[*Host](ctx)
    let (p, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret path_error }
    if is_root(p) { ret IsDirectory }
    ret fs.write_file(a, full, data)
}

fn host_make_dir(ctx: *void, a: *mem.Arena, path: str) -> err {
    let h = mem.cast[*Host](ctx)
    let (p, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret path_error }
    if is_root(p) { ret fs.Exists }
    ret fs.make_dir(a, full)
}

fn host_remove(ctx: *void, a: *mem.Arena, path: str) -> err {
    let h = mem.cast[*Host](ctx)
    let (p, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret path_error }
    if is_root(p) { ret fs.Invalid }
    let (e, stat_error) = fs.stat(a, full)
    if stat_error != ok { ret stat_error }
    if e.kind == .Directory { ret fs.remove_dir(a, full) }
    ret fs.remove_file(a, full)
}

fn host_list(ctx: *void, a: *mem.Arena, path: str) -> ([]fs.Entry, err) {
    var nothing: []fs.Entry = zero
    let h = mem.cast[*Host](ctx)
    let (p, full, path_error) = host_path(h, a, path)
    if path_error != ok { ret (nothing, path_error) }
    let (root_entry_of, stat_error) = fs.stat(a, full)
    if stat_error != ok { ret (nothing, stat_error) }
    if root_entry_of.kind != .Directory { ret (nothing, NotDirectory) }
    let (it0, walk_error) = fs.walk(a, full, fs.WalkOptions { recursive: false, follow_symlinks: false })
    if walk_error != ok { ret (nothing, walk_error) }
    var it = it0
    var n = 0usize
    var staging: [256]fs.Entry = zero
    while true {
        let (e, more, next_error) = fs.walk_next_err(&it)
        if next_error != ok { ret (nothing, next_error) }
        if !more { break }
        if n == staging.len { ret (nothing, TooLarge) }
        staging[n] = e
        n += 1usize
    }
    if n == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[fs.Entry](a, n)
    if out_error != ok { ret (nothing, out_error) }
    var i = 0usize
    while i < n {
        var cut = staging[i].path.len
        while cut > 0usize && staging[i].path[cut - 1usize] != 47u8 && staging[i].path[cut - 1usize] != 92u8 { cut -= 1usize }
        let (joined, join_error) = join_path(a, p, staging[i].path[cut..])
        if join_error != ok { ret (nothing, join_error) }
        out[i] = staging[i]
        out[i].path = joined
        i += 1usize
    }
    sort_entries(out)
    ret (out, ok)
}

fn host_vfs(h: *Host) -> Vfs {
    ret Vfs { ctx: mem.cast[*void](h), stat_fn: host_stat, read_fn: host_read, write_fn: host_write, make_dir_fn: host_make_dir, remove_fn: host_remove, list_fn: host_list }
}
