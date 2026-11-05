// A rope over caller pools: leaves reference byte ranges of a caller text
// pool (`text`, appended at `used`), internal nodes carry `weight` = the
// length of the left subtree and always have both children. A root of
// `NONE` is the empty rope. `split` and `concat` are the primitives; `insert`,
// `remove`, `byte_at` and `report` (flatten) sit on top, and `rebalance`
// rebuilds a balanced tree from a fresh flat copy. `report` and `split` walk
// with an explicit stack, not one frame per level, so an unbalanced tree does
// not put its depth on the native stack; both answer TooSmall for a tree
// deeper than the stack's 131072 entries.
// ponytail: a fixed depth ceiling, not rebalancing; the upgrade is Boehm's
// fibonacci rebalancing in `concat`, which keeps every legal spine under it.
// The walk stack is 512 KiB in `report` and 1 MiB in `split`, so call these on
// the main stack or a thread's own larger stack, not `e.thread.DEFAULT_STACK`.

type Rope = struct { text: []u8, used: usize, weight: []u32, left: []u32, right: []u32, start: []u32, nodes: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32
const LEAF: usize = 64usize

fn rope(text: []u8, weight: []u32, left: []u32, right: []u32, start: []u32) -> Rope {
    ret Rope { text: text, used: 0usize, weight: weight, left: left, right: right, start: start, nodes: 0usize }
}

// Whether `needed` fresh nodes fit in every caller pool without changing it.
fn has_nodes(r: *const Rope, needed: usize) -> bool {
    if r.nodes > r.weight.len || r.nodes > r.left.len || r.nodes > r.right.len || r.nodes > r.start.len { ret false }
    if needed > r.weight.len - r.nodes || needed > r.left.len - r.nodes || needed > r.right.len - r.nodes || needed > r.start.len - r.nodes { ret false }
    ret true
}

fn new_node(r: *Rope, weight: u32, left: u32, right: u32, start: u32) -> (u32, err) {
    if !has_nodes(r, 1usize) { ret (NONE, TooSmall) }
    let id = r.nodes
    r.nodes += 1usize
    r.weight[id] = weight
    r.left[id] = left
    r.right[id] = right
    r.start[id] = start
    ret (u32(id), ok)
}

// A leaf over `text` appended to the pool; an empty text is `NONE`.
fn from_text(r: *Rope, text: []const u8) -> (u32, err) {
    if text.len == 0usize { ret (NONE, ok) }
    if r.used > r.text.len || text.len > r.text.len - r.used || !has_nodes(r, 1usize) { ret (NONE, TooSmall) }
    let at_start = r.used
    var i = 0usize
    while i < text.len {
        r.text[at_start + i] = text[i]
        i += 1usize
    }
    r.used += text.len
    let (id, e) = new_node(r, u32(text.len), NONE, NONE, u32(at_start))
    ret (id, e)
}

fn len(r: *const Rope, root: u32) -> usize {
    var total = 0usize
    var n = root
    while n != NONE {
        total += usize(r.weight[usize(n)])
        n = r.right[usize(n)]
    }
    ret total
}

fn byte_at(r: *const Rope, root: u32, i: usize) -> (u8, bool) {
    var n = root
    var index = i
    while n != NONE {
        let w = usize(r.weight[usize(n)])
        if r.left[usize(n)] == NONE {
            if index >= w { ret (0u8, false) }
            ret (r.text[usize(r.start[usize(n)]) + index], true)
        }
        if index < w {
            n = r.left[usize(n)]
        } else {
            index -= w
            n = r.right[usize(n)]
        }
    }
    ret (0u8, false)
}

// A split only allocates when its cut falls strictly inside one leaf.
fn split_nodes(r: *const Rope, root: u32, i: usize) -> usize {
    var node = root
    var index = i
    while node != NONE {
        let at = usize(node)
        let width = usize(r.weight[at])
        if r.left[at] == NONE {
            if index > 0usize && index < width { ret 1usize }
            ret 0usize
        }
        if index <= width {
            node = r.left[at]
        } else {
            index -= width
            node = r.right[at]
        }
    }
    ret 0usize
}

// The exact nodes `build` creates for a byte run of this length.
fn build_nodes(length: usize) -> usize {
    if length <= LEAF { ret 1usize }
    let middle = length / 2usize
    ret 1usize + build_nodes(middle) + build_nodes(length - middle)
}

fn concat(r: *Rope, a: u32, b: u32) -> (u32, err) {
    if a == NONE { ret (b, ok) }
    if b == NONE { ret (a, ok) }
    let (id, e) = new_node(r, u32(len(r, a)), a, b, 0u32)
    ret (id, e)
}

// Split `root` into (the first `i` bytes, the rest); nodes are reused in place.
fn split(r: *Rope, root: u32, i: usize) -> (u32, u32, err) {
    if root == NONE {
        if i == 0usize { ret (NONE, NONE, ok) }
        ret (NONE, NONE, Invalid)
    }
    let total = len(r, root)
    if i > total { ret (NONE, NONE, Invalid) }
    if i == 0usize { ret (NONE, root, ok) }
    if i == total { ret (root, NONE, ok) }
    // Walk to the cut, keeping the internal nodes and the index that reached
    // each, then rebuild the cut path on the way back up.
    var nodes: [131072]u32 = undef
    var cuts: [131072]u32 = undef
    var top = 0usize
    var node = root
    var index = i
    while true {
        let at = usize(node)
        let width = usize(r.weight[at])
        if r.left[at] == NONE { break }
        if top >= 131072usize { ret (NONE, NONE, TooSmall) }
        nodes[top] = node
        cuts[top] = u32(index)
        top += 1usize
        if index <= width {
            node = r.left[at]
        } else {
            index -= width
            node = r.right[at]
        }
    }
    let leaf = usize(node)
    let leaf_width = usize(r.weight[leaf])
    if index > leaf_width { ret (NONE, NONE, Invalid) }
    var lo = node
    var hi = NONE
    if index < leaf_width {
        let (tail, tail_error) = new_node(r, u32(leaf_width - index), NONE, NONE, r.start[leaf] + u32(index))
        if tail_error != ok { ret (NONE, NONE, tail_error) }
        r.weight[leaf] = u32(index)
        hi = tail
    }
    while top > 0usize {
        top -= 1usize
        let parent = nodes[top]
        let cut = usize(cuts[top])
        let p = usize(parent)
        let width = usize(r.weight[p])
        if cut <= width {
            if hi == NONE {
                hi = r.right[p]
            } else {
                r.left[p] = hi
                r.weight[p] = u32(width - cut)
                hi = parent
            }
        } else if lo == NONE {
            lo = r.left[p]
        } else {
            r.right[p] = lo
            lo = parent
        }
    }
    ret (lo, hi, ok)
}

// Insert `text` before byte `i` (`i == len` appends).
fn insert(r: *Rope, root: u32, i: usize, text: []const u8) -> (u32, err) {
    let total = len(r, root)
    if i > total { ret (root, Invalid) }
    if text.len > 0usize && (r.used > r.text.len || text.len > r.text.len - r.used) { ret (root, TooSmall) }
    var needed = split_nodes(r, root, i)
    if text.len > 0usize {
        needed += 1usize
        if i > 0usize { needed += 1usize }
        if i < total { needed += 1usize }
    } else if i > 0usize && i < total {
        needed += 1usize
    }
    if !has_nodes(r, needed) { ret (root, TooSmall) }
    let (leaf, leaf_error) = from_text(r, text)
    if leaf_error != ok { ret (root, leaf_error) }
    let (l, rest, split_error) = split(r, root, i)
    if split_error != ok { ret (root, split_error) }
    let (front, front_error) = concat(r, l, leaf)
    if front_error != ok { ret (root, front_error) }
    let (whole, e) = concat(r, front, rest)
    ret (whole, e)
}

// Remove `count` bytes starting at `i`.
fn remove(r: *Rope, root: u32, i: usize, count: usize) -> (u32, err) {
    let total = len(r, root)
    if i > total || count > total - i { ret (root, Invalid) }
    if count == 0usize { ret (root, ok) }
    let end = i + count
    var needed = split_nodes(r, root, i)
    if end < total { needed += split_nodes(r, root, end) }
    if i > 0usize && end < total { needed += 1usize }
    if !has_nodes(r, needed) { ret (root, TooSmall) }
    let (l, rest, split_error) = split(r, root, i)
    if split_error != ok { ret (root, split_error) }
    let (_, tail, cut_error) = split(r, rest, count)
    if cut_error != ok { ret (root, cut_error) }
    let (whole, e) = concat(r, l, tail)
    ret (whole, e)
}

// The bytes of `root` into `out`; answers the count.
fn report(r: *const Rope, root: u32, out: []u8) -> (usize, err) {
    var nodes: [131072]u32 = undef
    var top = 0usize
    var node = root
    var written = 0usize
    while node != NONE || top > 0usize {
        while node != NONE {
            let at = usize(node)
            if r.left[at] == NONE {
                let width = usize(r.weight[at])
                if width > out.len - written { ret (written, TooSmall) }
                let s = usize(r.start[at])
                var i = 0usize
                while i < width {
                    out[written + i] = r.text[s + i]
                    i += 1usize
                }
                written += width
                node = NONE
            } else {
                if top >= 131072usize { ret (written, TooSmall) }
                nodes[top] = r.right[at]
                top += 1usize
                node = r.left[at]
            }
        }
        if top > 0usize {
            top -= 1usize
            node = nodes[top]
        }
    }
    ret (written, ok)
}

fn build(r: *Rope, lo: usize, hi: usize) -> (u32, err) {
    if !has_nodes(r, build_nodes(hi - lo)) { ret (NONE, TooSmall) }
    if hi - lo <= LEAF {
        let (leaf, e) = new_node(r, u32(hi - lo), NONE, NONE, u32(lo))
        ret (leaf, e)
    }
    let mid = lo + (hi - lo) / 2usize
    let (a, a_error) = build(r, lo, mid)
    if a_error != ok { ret (NONE, a_error) }
    let (b, b_error) = build(r, mid, hi)
    if b_error != ok { ret (NONE, b_error) }
    let (id, e) = new_node(r, u32(mid - lo), a, b, 0u32)
    ret (id, e)
}

// A balanced tree over a fresh flat copy of `root` appended to the pool.
// ponytail: rebuild, not Boehm's fibonacci rebalance; the pool grows by len
// each time, so the caller compacts (a new Rope from `report`) when it fills.
fn rebalance(r: *Rope, root: u32) -> (u32, err) {
    let n = len(r, root)
    if n == 0usize { ret (NONE, ok) }
    if r.used > r.text.len || n > r.text.len - r.used || !has_nodes(r, build_nodes(n)) { ret (root, TooSmall) }
    let lo = r.used
    var i = 0usize
    while i < n {
        let (b, _) = byte_at(r, root, i)
        r.text[lo + i] = b
        i += 1usize
    }
    r.used += n
    let (root2, e) = build(r, lo, lo + n)
    ret (root2, e)
}
