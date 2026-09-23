// A hash index over a table of named declarations (D303). Named `lookup` because
// `index` and `names` are locals in the modules that use it, and a qualifier may not be.
//
// The resolver's symbols and the checker's functions, aggregates, aliases, constants
// and globals are flat arrays searched by (module, name), and every search walked the
// whole array -- adding N symbols was N^2, and every name in every body paid a walk
// over every declaration in the program. This is the index those walks become: open
// addressing over (module, table, name), sized to the pool it shadows.
//
// It is filled lazily. A finder compares the table's count against what is indexed and
// appends the tail before probing, so the tables' append sites are untouched, and a
// caller that never attaches an index keeps the linear scan. First match wins on a
// duplicate key, as the scans did.
//
// The entries array is reserved at twice the final size but only the live region is
// ever touched: the table starts small at the front and, when half full, moves to the
// region after itself at double the size, zeroing only that region. The regions sum to
// under twice the last one, and a small program commits a few pages.

type Entry = struct {
    hash: usize,
    module_index: usize,
    table: usize,
    name: str,
    value: usize,
    used: bool,
}

type Index = struct {
    entries: []Entry,
    start: usize,
    size: usize,
    count: usize,
    // How many of each source table's rows are indexed, by table tag.
    indexed: [8]usize,
}

error Capacity

fn attach(x: *Index, entries: []Entry) -> err {
    if entries.len < 64usize { ret Capacity }
    x.entries = entries
    x.start = 0usize
    x.size = 64usize
    x.count = 0usize
    var t = 0usize
    while t < 8usize {
        x.indexed[t] = 0usize
        t += 1usize
    }
    ret clear(x, 0usize, 64usize)
}

fn attached(x: *Index) -> bool {
    ret x.entries.len != 0usize
}

fn clear(x: *Index, from: usize, count: usize) -> err {
    if from + count > x.entries.len { ret Capacity }
    var at = from
    while at < from + count {
        x.entries[at].used = false
        at += 1usize
    }
    ret ok
}

fn hash_of(module_index: usize, table: usize, name: str) -> usize {
    var h = 14695981039346656037usize
    var at = 0usize
    while at < name.len {
        h = (h ^ usize(name[at])) *% 1099511628211usize
        at += 1usize
    }
    h = (h ^ module_index) *% 1099511628211usize
    h = (h ^ table) *% 1099511628211usize
    // Fold the high bits down so a power-of-two mask sees them.
    ret h ^ (h >> 29usize)
}

fn same_name(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

// The slot holding this key, or the empty slot it would go in.
fn slot(x: *Index, h: usize, module_index: usize, table: usize, name: str) -> usize {
    let mask = x.size - 1usize
    // The live region as a local view, read field by field (D931): each probe copied a
    // whole entry through the index.
    let entries = x.entries[x.start..x.start + x.size]
    var at = h & mask
    while true {
        if !entries[at].used { ret x.start + at }
        if entries[at].hash == h && entries[at].module_index == module_index && entries[at].table == table && same_name(entries[at].name, name) { ret x.start + at }
        at = (at + 1usize) & mask
    }
    ret 0usize
}

fn grow(x: *Index) -> err {
    let old_start = x.start
    let old_size = x.size
    let new_start = old_start + old_size
    let new_size = old_size * 2usize
    if new_start + new_size > x.entries.len { ret Capacity }
    try clear(x, new_start, new_size)
    x.start = new_start
    x.size = new_size
    var at = old_start
    while at < old_start + old_size {
        let e = x.entries[at]
        if e.used {
            let to = slot(x, e.hash, e.module_index, e.table, e.name)
            x.entries[to] = e
        }
        at += 1usize
    }
    ret ok
}

// Records value under the key unless the key is present, so the first row wins.
fn insert(x: *Index, module_index: usize, table: usize, name: str, value: usize) -> err {
    if x.count * 2usize >= x.size { try grow(x) }
    let h = hash_of(module_index, table, name)
    let at = slot(x, h, module_index, table, name)
    if x.entries[at].used { ret ok }
    x.entries[at] = Entry { hash: h, module_index: module_index, table: table, name: name, value: value, used: true }
    x.count += 1usize
    ret ok
}

fn find(x: *Index, module_index: usize, table: usize, name: str) -> (usize, bool) {
    let h = hash_of(module_index, table, name)
    let at = slot(x, h, module_index, table, name)
    if !x.entries[at].used { ret (0usize, false) }
    ret (x.entries[at].value, true)
}
