// A byte trie over caller storage: keys are byte strings, each terminal node
// carries a `u64` value, and children hang off a node as a sibling list, so a
// node costs a handful of words rather than 256 slots.
//
// Node `0` is the root; the five slices need `capacity` entries and a full pool
// answers `TooSmall`. `remove` clears a terminal without reclaiming its nodes
// (a trie that churns should be rebuilt now and then), and `prefix_iter` walks
// every key under a prefix in byte order, handing the visitor the key bytes
// assembled in caller scratch sized for the longest key.

type Trie = struct { bytes: []u8, first: []u32, next: []u32, terminal: []u8, values: []u64, used: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

fn init(bytes: []u8, first: []u32, next: []u32, terminal: []u8, values: []u64, capacity: usize) -> (Trie, err) {
    if capacity == 0usize || capacity >= 4294967295usize { ret (zero, Invalid) }
    if bytes.len < capacity || first.len < capacity || next.len < capacity || terminal.len < capacity || values.len < capacity { ret (zero, TooSmall) }
    var t = Trie { bytes: bytes[..capacity], first: first[..capacity], next: next[..capacity], terminal: terminal[..capacity], values: values[..capacity], used: 1usize }
    t.first[0usize] = NONE
    t.next[0usize] = NONE
    t.terminal[0usize] = 0u8
    ret (t, ok)
}

fn len(t: *const Trie) -> usize { ret t.used }

// The child of `node` on `b`, if any.
fn child(t: *const Trie, node: u32, b: u8) -> u32 {
    var at = t.first[usize(node)]
    while at != NONE {
        if t.bytes[usize(at)] == b { ret at }
        at = t.next[usize(at)]
    }
    ret NONE
}

// Stores `value` under `key`, replacing an earlier value; answers whether the
// key was new.
fn insert(t: *Trie, key: []const u8, value: u64) -> (bool, err) {
    var node = 0u32
    var i = 0usize
    while i < key.len {
        var here = child(t, node, key[i])
        if here == NONE {
            if t.used >= t.bytes.len { ret (false, TooSmall) }
            here = u32(t.used)
            t.used += 1usize
            t.bytes[usize(here)] = key[i]
            t.first[usize(here)] = NONE
            t.terminal[usize(here)] = 0u8
            t.next[usize(here)] = t.first[usize(node)]
            t.first[usize(node)] = here
        }
        node = here
        i += 1usize
    }
    let fresh = t.terminal[usize(node)] == 0u8
    t.terminal[usize(node)] = 1u8
    t.values[usize(node)] = value
    ret (fresh, ok)
}

fn get(t: *const Trie, key: []const u8) -> (u64, bool) {
    var node = 0u32
    var i = 0usize
    while i < key.len {
        node = child(t, node, key[i])
        if node == NONE { ret (0u64, false) }
        i += 1usize
    }
    if t.terminal[usize(node)] == 0u8 { ret (0u64, false) }
    ret (t.values[usize(node)], true)
}

fn contains(t: *const Trie, key: []const u8) -> bool {
    let (_, found) = get(t, key)
    ret found
}

// Whether any stored key starts with `prefix`.
fn has_prefix(t: *const Trie, prefix: []const u8) -> bool {
    var node = 0u32
    var i = 0usize
    while i < prefix.len {
        node = child(t, node, prefix[i])
        if node == NONE { ret false }
        i += 1usize
    }
    ret any_terminal(t, node)
}

// Whether `node` or anything below it is a stored key (a removed key's nodes
// remain, so the children are searched rather than counted).
fn any_terminal(t: *const Trie, node: u32) -> bool {
    if t.terminal[usize(node)] != 0u8 { ret true }
    var at = t.first[usize(node)]
    while at != NONE {
        if any_terminal(t, at) { ret true }
        at = t.next[usize(at)]
    }
    ret false
}

fn remove(t: *Trie, key: []const u8) -> bool {
    var node = 0u32
    var i = 0usize
    while i < key.len {
        node = child(t, node, key[i])
        if node == NONE { ret false }
        i += 1usize
    }
    if t.terminal[usize(node)] == 0u8 { ret false }
    t.terminal[usize(node)] = 0u8
    ret true
}

// The longest stored key that is a prefix of `text`: its length and value.
fn longest_prefix(t: *const Trie, text: []const u8) -> (usize, u64, bool) {
    var node = 0u32
    var best_len = 0usize
    var best_value = 0u64
    var any = t.terminal[0usize] != 0u8
    if any { best_value = t.values[0usize] }
    var i = 0usize
    while i < text.len {
        node = child(t, node, text[i])
        if node == NONE { break }
        i += 1usize
        if t.terminal[usize(node)] != 0u8 {
            best_len = i
            best_value = t.values[usize(node)]
            any = true
        }
    }
    ret (best_len, best_value, any)
}

// Visits every key under `prefix` in byte order with `visit(ctx, key, value)`;
// `scratch` holds the key being assembled and must fit the longest key. Stops
// when the visitor answers `false`, which is then returned.
fn prefix_iter[Ctx: type](t: *const Trie, prefix: []const u8, scratch: []u8, ctx: *Ctx, visit: fn(*Ctx, []const u8, u64) -> bool) -> (bool, err) {
    if scratch.len < prefix.len { ret (true, TooSmall) }
    var node = 0u32
    var i = 0usize
    while i < prefix.len {
        node = child(t, node, prefix[i])
        if node == NONE { ret (true, ok) }
        scratch[i] = prefix[i]
        i += 1usize
    }
    let (finished, walk_error) = walk[Ctx](t, node, prefix.len, scratch, ctx, visit)
    ret (finished, walk_error)
}

// Depth-first from `node`, whose key occupies `scratch[..depth]`. Siblings are
// visited smallest byte first by scanning the list for the next larger byte.
fn walk[Ctx: type](t: *const Trie, node: u32, depth: usize, scratch: []u8, ctx: *Ctx, visit: fn(*Ctx, []const u8, u64) -> bool) -> (bool, err) {
    if t.terminal[usize(node)] != 0u8 {
        if !visit(ctx, scratch[..depth], t.values[usize(node)]) { ret (false, ok) }
    }
    var previous = 0u32
    var have_previous = false
    while true {
        // The smallest child byte greater than the last one visited.
        var pick = NONE
        var at = t.first[usize(node)]
        while at != NONE {
            let b = t.bytes[usize(at)]
            if !have_previous || b > t.bytes[usize(previous)] {
                if pick == NONE || b < t.bytes[usize(pick)] { pick = at }
            }
            at = t.next[usize(at)]
        }
        if pick == NONE { break }
        if depth >= scratch.len { ret (true, TooSmall) }
        scratch[depth] = t.bytes[usize(pick)]
        let (go_on, walk_error) = walk[Ctx](t, pick, depth + 1usize, scratch, ctx, visit)
        if walk_error != ok || !go_on { ret (go_on, walk_error) }
        previous = pick
        have_previous = true
    }
    ret (true, ok)
}

// A radix (Patricia) view of a trie: every chain of single-child, non-terminal
// nodes is one edge whose label is a run of `labels`. Node `0` is the root;
// `starts`/`lens` locate a node's label, and the rest is as `Trie`.
type Radix = struct { labels: []u8, starts: []u32, lens: []u32, first: []u32, next: []u32, terminal: []u8, values: []u64, used: usize }

// Compresses `t` into the seven slices; `capacity` nodes and `labels.len >= t.used` suffice.
fn compact(t: *const Trie, labels: []u8, starts: []u32, lens: []u32, first: []u32, next: []u32, terminal: []u8, values: []u64, capacity: usize) -> (Radix, err) {
    if capacity == 0usize || capacity >= 4294967295usize { ret (zero, Invalid) }
    if starts.len < capacity || lens.len < capacity || first.len < capacity || next.len < capacity || terminal.len < capacity || values.len < capacity { ret (zero, TooSmall) }
    var r = Radix { labels: labels, starts: starts[..capacity], lens: lens[..capacity], first: first[..capacity], next: next[..capacity], terminal: terminal[..capacity], values: values[..capacity], used: 1usize }
    r.starts[0usize] = 0u32
    r.lens[0usize] = 0u32
    r.first[0usize] = NONE
    r.next[0usize] = NONE
    r.terminal[0usize] = t.terminal[0usize]
    r.values[0usize] = t.values[0usize]
    var written = 0usize
    let e = compact_children(t, 0u32, &r, 0u32, &written)
    if e != ok { ret (zero, e) }
    r.labels = labels[..written]
    ret (r, ok)
}

// Every child of trie node `from` becomes a radix child of `into`, its label the
// chain down to the first branching or terminal node.
fn compact_children(t: *const Trie, from: u32, r: *Radix, into: u32, written: *usize) -> err {
    var child_node = t.first[usize(from)]
    while child_node != NONE {
        if r.used >= r.starts.len { ret TooSmall }
        let fresh = u32(r.used)
        r.used += 1usize
        r.starts[usize(fresh)] = u32(*written)
        var end = child_node
        while true {
            if *written >= r.labels.len { ret TooSmall }
            r.labels[*written] = t.bytes[usize(end)]
            *written += 1usize
            if t.terminal[usize(end)] != 0u8 { break }
            let only = t.first[usize(end)]
            if only == NONE || t.next[usize(only)] != NONE { break }
            end = only
        }
        r.lens[usize(fresh)] = u32(*written) - r.starts[usize(fresh)]
        r.terminal[usize(fresh)] = t.terminal[usize(end)]
        r.values[usize(fresh)] = t.values[usize(end)]
        r.first[usize(fresh)] = NONE
        r.next[usize(fresh)] = r.first[usize(into)]
        r.first[usize(into)] = fresh
        let e = compact_children(t, end, r, fresh, written)
        if e != ok { ret e }
        child_node = t.next[usize(child_node)]
    }
    ret ok
}

fn radix_len(r: *const Radix) -> usize { ret r.used }

// The value under `key`, following whole labels.
fn radix_get(r: *const Radix, key: []const u8) -> (u64, bool) {
    var node = 0u32
    var i = 0usize
    while i < key.len {
        var pick = r.first[usize(node)]
        while pick != NONE && r.labels[usize(r.starts[usize(pick)])] != key[i] { pick = r.next[usize(pick)] }
        if pick == NONE { ret (0u64, false) }
        let start = usize(r.starts[usize(pick)])
        let length = usize(r.lens[usize(pick)])
        if i + length > key.len { ret (0u64, false) }
        var k = 0usize
        while k < length {
            if r.labels[start + k] != key[i + k] { ret (0u64, false) }
            k += 1usize
        }
        i += length
        node = pick
    }
    if r.terminal[usize(node)] == 0u8 { ret (0u64, false) }
    ret (r.values[usize(node)], true)
}
