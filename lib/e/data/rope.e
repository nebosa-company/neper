// A rope over caller pools: leaves reference byte ranges of a caller text
// pool (`text`, appended at `used`), internal nodes carry `weight` = the
// length of the left subtree and always have both children. A root of
// `NONE` is the empty rope. `split` and `concat` are the primitives; `insert`,
// `remove`, `byte_at` and `report` (flatten) sit on top, and `rebalance`
// rebuilds a balanced tree from a fresh flat copy.

type Rope = struct { text: []u8, used: usize, weight: []u32, left: []u32, right: []u32, start: []u32, nodes: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32
const LEAF: usize = 64usize

fn rope(text: []u8, weight: []u32, left: []u32, right: []u32, start: []u32) -> Rope {
    ret Rope { text: text, used: 0usize, weight: weight, left: left, right: right, start: start, nodes: 0usize }
}

fn new_node(r: *Rope, weight: u32, left: u32, right: u32, start: u32) -> (u32, err) {
    if r.nodes >= r.weight.len || r.nodes >= r.left.len || r.nodes >= r.right.len || r.nodes >= r.start.len { ret (NONE, TooSmall) }
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
    if r.used + text.len > r.text.len { ret (NONE, TooSmall) }
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
    let n = usize(root)
    let w = usize(r.weight[n])
    if r.left[n] == NONE {
        if i == 0usize { ret (NONE, root, ok) }
        if i == w { ret (root, NONE, ok) }
        if i > w { ret (NONE, NONE, Invalid) }
        let (tail, e) = new_node(r, u32(w - i), NONE, NONE, r.start[n] + u32(i))
        if e != ok { ret (NONE, NONE, e) }
        r.weight[n] = u32(i)
        ret (root, tail, ok)
    }
    if i <= w {
        let (l1, l2, e) = split(r, r.left[n], i)
        if e != ok { ret (NONE, NONE, e) }
        if l2 == NONE { ret (l1, r.right[n], ok) }
        r.left[n] = l2
        r.weight[n] = u32(w - i)
        ret (l1, root, ok)
    }
    let (r1, r2, e) = split(r, r.right[n], i - w)
    if e != ok { ret (NONE, NONE, e) }
    if r1 == NONE { ret (r.left[n], r2, ok) }
    r.right[n] = r1
    ret (root, r2, ok)
}

// Insert `text` before byte `i` (`i == len` appends).
fn insert(r: *Rope, root: u32, i: usize, text: []const u8) -> (u32, err) {
    if i > len(r, root) { ret (root, Invalid) }
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
    if i + count > len(r, root) { ret (root, Invalid) }
    let (l, rest, split_error) = split(r, root, i)
    if split_error != ok { ret (root, split_error) }
    let (_, tail, cut_error) = split(r, rest, count)
    if cut_error != ok { ret (root, cut_error) }
    let (whole, e) = concat(r, l, tail)
    ret (whole, e)
}

// The bytes of `root` into `out`; answers the count.
fn report(r: *const Rope, root: u32, out: []u8) -> (usize, err) {
    if root == NONE { ret (0usize, ok) }
    let n = usize(root)
    let w = usize(r.weight[n])
    if r.left[n] == NONE {
        if w > out.len { ret (0usize, TooSmall) }
        let s = usize(r.start[n])
        var i = 0usize
        while i < w {
            out[i] = r.text[s + i]
            i += 1usize
        }
        ret (w, ok)
    }
    let (before, left_error) = report(r, r.left[n], out)
    if left_error != ok { ret (before, left_error) }
    let (after, right_error) = report(r, r.right[n], out[before..])
    ret (before + after, right_error)
}

fn build(r: *Rope, lo: usize, hi: usize) -> (u32, err) {
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
    if r.used + n > r.text.len { ret (root, TooSmall) }
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
