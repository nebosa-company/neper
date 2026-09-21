// Suffix structures over the bytes of a text: the suffix array by prefix
// doubling with counting sorts (O(n log n)), Kasai's LCP array, pattern
// search by binary search over the array (every occurrence as a range of
// the array), the suffix automaton (the minimal DAWG, edges as per-state
// sibling lists in the arena) and the suffix tree derived from the array
// and LCP array (children as sibling lists, leaves numbered by suffix).
//
// The array and LCP builders write into caller storage; the automaton and
// tree live in the caller's arena.

use e.mem

type Automaton = struct { link: []u32, length: []u32, first_edge: []u32, edge_byte: []u8, edge_to: []u32, edge_next: []u32, states: usize, edges: usize }
type Tree = struct { text: str, parent: []u32, depth: []u32, first_child: []u32, next_sibling: []u32, suffix: []u32, nodes: usize }
error TooSmall
error TooLong

const NONE: u32 = 4294967295u32

// The suffix array of `text` into `sa`; `scratch.len >= 3 * n + 256`.
fn array_build(text: str, sa: []usize, scratch: []usize) -> err {
    let n = text.len
    if sa.len < n || scratch.len < 3usize * n + 256usize { ret TooSmall }
    if n == 0usize { ret ok }
    var rank = scratch[..n]
    var next_rank = scratch[n..2usize * n]
    var order = scratch[2usize * n..3usize * n]
    var bucket = scratch[3usize * n..3usize * n + 256usize]
    // Initial order by first byte, ranks from the byte values.
    var i = 0usize
    while i < 256usize {
        bucket[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        bucket[usize(text[i])] += 1usize
        i += 1usize
    }
    var sum = 0usize
    i = 0usize
    while i < 256usize {
        let c = bucket[i]
        bucket[i] = sum
        sum += c
        i += 1usize
    }
    i = 0usize
    while i < n {
        let b = usize(text[i])
        sa[bucket[b]] = i
        bucket[b] += 1usize
        i += 1usize
    }
    // Ranks are class numbers in 0..n so a counting sort over them fits in n.
    rank[sa[0usize]] = 0usize
    var first_classes = 1usize
    i = 1usize
    while i < n {
        if text[sa[i]] != text[sa[i - 1usize]] { first_classes += 1usize }
        rank[sa[i]] = first_classes - 1usize
        i += 1usize
    }
    if first_classes == n { ret ok }
    var k = 1usize
    while k < n {
        // Sort by (rank[i], rank[i + k]) with two counting passes over ranks in 0..n.
        // Pass 1: by the second key, suffixes past the end first (their key is "-1").
        var m = 0usize
        i = n - k
        while i < n {
            order[m] = i
            m += 1usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            if sa[i] >= k {
                order[m] = sa[i] - k
                m += 1usize
            }
            i += 1usize
        }
        // Pass 2: stable counting sort by the first key.
        i = 0usize
        while i < n {
            next_rank[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            next_rank[rank[i]] += 1usize
            i += 1usize
        }
        sum = 0usize
        i = 0usize
        while i < n {
            let c = next_rank[i]
            next_rank[i] = sum
            sum += c
            i += 1usize
        }
        i = 0usize
        while i < n {
            let s = order[i]
            sa[next_rank[rank[s]]] = s
            next_rank[rank[s]] += 1usize
            i += 1usize
        }
        // New ranks: equal pairs share a rank.
        next_rank[sa[0usize]] = 0usize
        var classes = 1usize
        i = 1usize
        while i < n {
            let a = sa[i - 1usize]
            let b = sa[i]
            var second_a = 0usize -% 1usize
            var second_b = 0usize -% 1usize
            if a + k < n { second_a = rank[a + k] }
            if b + k < n { second_b = rank[b + k] }
            if rank[a] != rank[b] || second_a != second_b { classes += 1usize }
            next_rank[b] = classes - 1usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            rank[i] = next_rank[i]
            i += 1usize
        }
        if classes == n { ret ok }
        k = k * 2usize
    }
    ret ok
}

// Kasai: `lcp[i]` is the longest common prefix of the suffixes at `sa[i - 1]`
// and `sa[i]` (`lcp[0] = 0`); `scratch.len >= n` for the inverse array.
fn lcp_array(text: str, sa: []const usize, lcp: []usize, scratch: []usize) -> err {
    let n = text.len
    if sa.len < n || lcp.len < n || scratch.len < n { ret TooSmall }
    if n == 0usize { ret ok }
    var inverse = scratch[..n]
    var i = 0usize
    while i < n {
        inverse[sa[i]] = i
        i += 1usize
    }
    var h = 0usize
    lcp[0usize] = 0usize
    i = 0usize
    while i < n {
        let r = inverse[i]
        if r > 0usize {
            let j = sa[r - 1usize]
            while i + h < n && j + h < n && text[i + h] == text[j + h] { h += 1usize }
            lcp[r] = h
            if h > 0usize { h -= 1usize }
        } else {
            h = 0usize
        }
        i += 1usize
    }
    ret ok
}

// Compare `pattern` with the suffix at `at`: negative, zero (the suffix
// starts with the pattern) or positive.
fn compare_at(text: str, at: usize, pattern: str) -> i32 {
    var i = 0usize
    while i < pattern.len {
        if at + i >= text.len { ret 1i32 }
        if pattern[i] < text[at + i] { ret 0i32 - 1i32 }
        if pattern[i] > text[at + i] { ret 1i32 }
        i += 1usize
    }
    ret 0i32
}

// The range `[low, high)` of the suffix array whose suffixes start with
// `pattern`; empty when it does not occur.
fn array_search(text: str, sa: []const usize, pattern: str) -> (usize, usize) {
    let n = text.len
    var low = 0usize
    var high = n
    while low < high {
        let mid = low + (high - low) / 2usize
        if compare_at(text, sa[mid], pattern) <= 0i32 { high = mid } else { low = mid + 1usize }
    }
    // low is the first suffix >= pattern; find the first one that is > pattern.
    let first = low
    high = n
    while low < high {
        let mid = low + (high - low) / 2usize
        if compare_at(text, sa[mid], pattern) < 0i32 { high = mid } else { low = mid + 1usize }
    }
    ret (first, low)
}

fn automaton_edge(m: *const Automaton, state: usize, c: u8) -> u32 {
    var e = m.first_edge[state]
    while e != NONE {
        if m.edge_byte[usize(e)] == c { ret m.edge_to[usize(e)] }
        e = m.edge_next[usize(e)]
    }
    ret NONE
}

fn automaton_add_edge(m: *Automaton, from: usize, c: u8, to: u32) {
    let e = m.edges
    m.edge_byte[e] = c
    m.edge_to[e] = to
    m.edge_next[e] = m.first_edge[from]
    m.first_edge[from] = u32(e)
    m.edges += 1usize
}

// Replace the target of the edge `from --c-->` (it exists).
fn automaton_set_edge(m: *Automaton, from: usize, c: u8, to: u32) {
    var e = m.first_edge[from]
    while e != NONE {
        if m.edge_byte[usize(e)] == c {
            m.edge_to[usize(e)] = to
            ret
        }
        e = m.edge_next[usize(e)]
    }
}

// The suffix automaton of `text`: at most `2n` states and `3n` edges.
fn automaton_build(a: *mem.Arena, text: str) -> (Automaton, err) {
    let n = text.len
    if n > 2000000000usize { ret (zero, TooLong) }
    let states_cap = 2usize * n + 2usize
    let edges_cap = 3usize * n + 2usize
    let (link, link_error) = mem.alloc[u32](a, states_cap)
    if link_error != ok { ret (zero, link_error) }
    let (length, length_error) = mem.alloc[u32](a, states_cap)
    if length_error != ok { ret (zero, length_error) }
    let (first_edge, first_error) = mem.alloc[u32](a, states_cap)
    if first_error != ok { ret (zero, first_error) }
    let (edge_byte, byte_error) = mem.alloc[u8](a, edges_cap)
    if byte_error != ok { ret (zero, byte_error) }
    let (edge_to, to_error) = mem.alloc[u32](a, edges_cap)
    if to_error != ok { ret (zero, to_error) }
    let (edge_next, next_error) = mem.alloc[u32](a, edges_cap)
    if next_error != ok { ret (zero, next_error) }
    var m = Automaton { link: link, length: length, first_edge: first_edge, edge_byte: edge_byte, edge_to: edge_to, edge_next: edge_next, states: 1usize, edges: 0usize }
    m.link[0usize] = NONE
    m.length[0usize] = 0u32
    m.first_edge[0usize] = NONE
    var last = 0usize
    var i = 0usize
    while i < n {
        let c = text[i]
        let current = m.states
        m.states += 1usize
        m.length[current] = m.length[last] + 1u32
        m.first_edge[current] = NONE
        m.link[current] = NONE
        var p = last
        var walking = true
        var past_root = false
        while walking {
            if automaton_edge(&m, p, c) != NONE {
                walking = false
            } else {
                automaton_add_edge(&m, p, c, u32(current))
                if m.link[p] == NONE {
                    walking = false
                    past_root = true
                } else {
                    p = usize(m.link[p])
                }
            }
        }
        if past_root {
            m.link[current] = 0u32
        } else {
            let q = usize(automaton_edge(&m, p, c))
            if m.length[p] + 1u32 == m.length[q] {
                m.link[current] = u32(q)
            } else {
                // Clone q with the shorter length; redirect the chain to the clone.
                let clone = m.states
                m.states += 1usize
                m.length[clone] = m.length[p] + 1u32
                m.link[clone] = m.link[q]
                m.first_edge[clone] = NONE
                var e = m.first_edge[q]
                while e != NONE {
                    automaton_add_edge(&m, clone, m.edge_byte[usize(e)], m.edge_to[usize(e)])
                    e = m.edge_next[usize(e)]
                }
                var r = p
                var redirecting = true
                while redirecting {
                    if automaton_edge(&m, r, c) != u32(q) {
                        redirecting = false
                    } else {
                        automaton_set_edge(&m, r, c, u32(clone))
                        if m.link[r] == NONE { redirecting = false } else { r = usize(m.link[r]) }
                    }
                }
                m.link[q] = u32(clone)
                m.link[current] = u32(clone)
            }
        }
        last = current
        i += 1usize
    }
    ret (m, ok)
}

// Does the automaton accept `pattern` as a substring of its text?
fn automaton_contains(m: *const Automaton, pattern: str) -> bool {
    var state = 0usize
    var i = 0usize
    while i < pattern.len {
        let next = automaton_edge(m, state, pattern[i])
        if next == NONE { ret false }
        state = usize(next)
        i += 1usize
    }
    ret true
}

// The number of distinct non-empty substrings, the sum over states other
// than the root of `length - length of link`.
fn automaton_distinct_substrings(m: *const Automaton) -> u64 {
    var total = 0u64
    var s = 1usize
    while s < m.states {
        total += u64(m.length[s] - m.length[usize(m.link[s])])
        s += 1usize
    }
    ret total
}

// The suffix tree from the suffix array and LCP array: node 0 is the root,
// internal nodes carry the string depth, leaves carry their suffix start
// (`NONE` for internal nodes); at most `2n` nodes. Children are a sibling
// list, most recently added first.
fn tree_build(a: *mem.Arena, text: str, sa: []const usize, lcp: []const usize) -> (Tree, err) {
    let n = text.len
    if sa.len < n || lcp.len < n { ret (zero, TooSmall) }
    if n > 2000000000usize { ret (zero, TooLong) }
    let cap = 2usize * n + 1usize
    let (parent, parent_error) = mem.alloc[u32](a, cap)
    if parent_error != ok { ret (zero, parent_error) }
    let (depth, depth_error) = mem.alloc[u32](a, cap)
    if depth_error != ok { ret (zero, depth_error) }
    let (first_child, child_error) = mem.alloc[u32](a, cap)
    if child_error != ok { ret (zero, child_error) }
    let (next_sibling, sibling_error) = mem.alloc[u32](a, cap)
    if sibling_error != ok { ret (zero, sibling_error) }
    let (suffix, suffix_error) = mem.alloc[u32](a, cap)
    if suffix_error != ok { ret (zero, suffix_error) }
    let (stack, stack_error) = mem.alloc[u32](a, n + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    var t = Tree { text: text, parent: parent, depth: depth, first_child: first_child, next_sibling: next_sibling, suffix: suffix, nodes: 1usize }
    t.parent[0usize] = NONE
    t.depth[0usize] = 0u32
    t.first_child[0usize] = NONE
    t.next_sibling[0usize] = NONE
    t.suffix[0usize] = NONE
    // The rightmost path of the tree is the stack; each suffix is added as a leaf
    // after popping to the node whose depth is at most the LCP with the previous.
    var top = 0usize
    stack[0usize] = 0u32
    var i = 0usize
    while i < n {
        var l = 0usize
        if i > 0usize { l = lcp[i] }
        var last_popped = NONE
        while usize(t.depth[usize(stack[top])]) > l {
            last_popped = stack[top]
            top -= 1usize
        }
        // A leaf left on top is a whole suffix that prefixes this one (there is
        // no terminator byte): it becomes the first child of a new internal node.
        if t.suffix[usize(stack[top])] != NONE {
            last_popped = stack[top]
            top -= 1usize
        }
        var attach = usize(stack[top])
        if usize(t.depth[attach]) < l {
            // Split: a new internal node of depth l between the stack top and the popped child.
            let node = t.nodes
            t.nodes += 1usize
            t.depth[node] = u32(l)
            t.suffix[node] = NONE
            t.parent[node] = u32(attach)
            // Move the popped child under the new node.
            let child = usize(last_popped)
            tree_detach(&t, attach, child)
            t.first_child[node] = u32(child)
            t.next_sibling[child] = NONE
            t.parent[child] = u32(node)
            t.next_sibling[node] = t.first_child[attach]
            t.first_child[attach] = u32(node)
            top += 1usize
            stack[top] = u32(node)
            attach = node
        }
        let leaf = t.nodes
        t.nodes += 1usize
        t.depth[leaf] = u32(n - sa[i])
        t.suffix[leaf] = u32(sa[i])
        t.parent[leaf] = u32(attach)
        t.first_child[leaf] = NONE
        t.next_sibling[leaf] = t.first_child[attach]
        t.first_child[attach] = u32(leaf)
        top += 1usize
        stack[top] = u32(leaf)
        i += 1usize
    }
    ret (t, ok)
}

fn tree_detach(t: *Tree, parent: usize, child: usize) {
    if t.first_child[parent] == u32(child) {
        t.first_child[parent] = t.next_sibling[child]
        ret
    }
    var c = t.first_child[parent]
    while c != NONE {
        if t.next_sibling[usize(c)] == u32(child) {
            t.next_sibling[usize(c)] = t.next_sibling[child]
            ret
        }
        c = t.next_sibling[usize(c)]
    }
}

// The bytes on the edge into `node`: the text from the parent's depth to
// the node's depth along any suffix below it.
fn tree_edge(t: *const Tree, node: usize) -> str {
    var leaf = node
    while t.suffix[leaf] == NONE { leaf = usize(t.first_child[leaf]) }
    let start = usize(t.suffix[leaf])
    ret t.text[start + usize(t.depth[usize(t.parent[node])])..start + usize(t.depth[node])]
}

// Does `pattern` occur in the text? Walked down the tree edge by edge.
fn tree_contains(t: *const Tree, pattern: str) -> bool {
    var node = 0usize
    var matched = 0usize
    while matched < pattern.len {
        var child = t.first_child[node]
        var found = NONE
        while child != NONE && found == NONE {
            let edge = tree_edge(t, usize(child))
            if edge.len > 0usize && edge[0usize] == pattern[matched] { found = child }
            child = t.next_sibling[usize(child)]
        }
        if found == NONE { ret false }
        let edge = tree_edge(t, usize(found))
        var k = 0usize
        while k < edge.len && matched < pattern.len {
            if edge[k] != pattern[matched] { ret false }
            k += 1usize
            matched += 1usize
        }
        node = usize(found)
    }
    ret true
}
