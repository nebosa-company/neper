// A Fenwick (binary indexed) tree over caller storage: point updates and prefix
// sums in `O(log n)`, and the search for the first prefix reaching a total.
//
// `tree.len` is the element count; index `i` in `0..len` is the element, stored
// internally at `i + 1`. Sums are `i64` and wrap on overflow like any other.

type Fenwick = struct { tree: []i64 }
error TooSmall

// Zeroes the storage; `tree.len` elements, all zero.
fn init(tree: []i64) -> Fenwick {
    var i = 0usize
    while i < tree.len {
        tree[i] = 0i64
        i += 1usize
    }
    ret Fenwick { tree: tree }
}

// Builds the tree over `values` in place in `O(n)`: `tree` must alias or copy them.
fn from_values(tree: []i64) -> Fenwick {
    var i = 0usize
    while i < tree.len {
        let parent = i | (i + 1usize)
        if parent < tree.len { tree[parent] += tree[i] }
        i += 1usize
    }
    ret Fenwick { tree: tree }
}

fn len(f: *const Fenwick) -> usize { ret f.tree.len }

// Adds `delta` to element `index`.
fn add(f: *Fenwick, index: usize, delta: i64) {
    var i = index
    while i < f.tree.len {
        f.tree[i] += delta
        i = i | (i + 1usize)
    }
}

// The sum of elements `0..count`.
fn prefix_sum(f: *const Fenwick, count: usize) -> i64 {
    var sum = 0i64
    var i = count
    while i > 0usize {
        sum += f.tree[i - 1usize]
        i = i & (i - 1usize)
    }
    ret sum
}

// The sum of elements `low..high`.
fn range_sum(f: *const Fenwick, low: usize, high: usize) -> i64 {
    if high <= low { ret 0i64 }
    ret prefix_sum(f, high) - prefix_sum(f, low)
}

// The current value of one element.
fn get(f: *const Fenwick, index: usize) -> i64 { ret range_sum(f, index, index + 1usize) }

fn set(f: *Fenwick, index: usize, value: i64) { add(f, index, value - get(f, index)) }

// For non-negative elements: the least `count` whose prefix sum reaches `total`,
// or `len + 1` when no prefix does. A binary descent over the tree, `O(log n)`.
fn lower_bound(f: *const Fenwick, total: i64) -> usize {
    var remaining = total
    var position = 0usize
    var step = 1usize
    while step * 2usize <= f.tree.len { step = step * 2usize }
    while step > 0usize {
        let next = position + step
        if next <= f.tree.len && f.tree[next - 1usize] < remaining {
            position = next
            remaining -= f.tree[next - 1usize]
        }
        step = step / 2usize
    }
    ret position + 1usize
}
