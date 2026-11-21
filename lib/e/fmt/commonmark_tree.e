// The document tree and parser state of e.fmt.commonmark. Nodes live in one table and refer to each
// other by index, -1 meaning none; nothing is freed until the arena is reset. An allocation that fails
// sets `failed` and the work carries on harmlessly until the entry point reports it.

use e.mem
use e.str
use e.fmt.commonmark_text as ct

const NIL: i32 = -1i32

const K_DOCUMENT: u8 = 1u8
const K_BLOCK_QUOTE: u8 = 2u8
const K_LIST: u8 = 3u8
const K_ITEM: u8 = 4u8
const K_CODE_BLOCK: u8 = 5u8
const K_HTML_BLOCK: u8 = 6u8
const K_PARAGRAPH: u8 = 8u8
const K_HEADING: u8 = 9u8
const K_THEMATIC: u8 = 10u8
const K_TABLE: u8 = 11u8
const K_ROW: u8 = 12u8
const K_CELL: u8 = 13u8
const K_TEXT: u8 = 20u8
const K_SOFTBREAK: u8 = 21u8
const K_LINEBREAK: u8 = 22u8
const K_CODE: u8 = 23u8
const K_HTML_INLINE: u8 = 24u8
const K_EMPH: u8 = 26u8
const K_STRONG: u8 = 27u8
const K_LINK: u8 = 28u8
const K_IMAGE: u8 = 29u8
const K_STRIKE: u8 = 30u8

type Node = struct {
    kind: u8, open: bool, last_blank: bool, last_checked: bool, table_visited: bool,
    parent: i32, first: i32, last: i32, prev: i32, next: i32,
    sl: i32, sc: i32, el: i32, ec: i32,
    cbuf: []u8, clen: usize,
    lit: str, info: str, url: str, title: str,
    level: i32, setext: bool, fenced: bool, fence_char: u8, fence_len: i32, fence_off: i32,
    list_type: u8, delim: u8, bullet: u8, start: i32, tight: bool, marker_off: i32, padding: i32,
    tasklist: bool, checked: bool, html_type: i32, internal_off: i32,
    ncols: i32, aligns: str, is_header: bool, cell_index: i32, nrows: i32, nonempty: i32
}

type Ref = struct { label: str, url: str, title: str }

type Delim = struct { prev: i32, next: i32, inl: i32, position: i32, length: i32, ch: u8, can_open: bool, can_close: bool }

type Bracket = struct { prev: i32, inl: i32, position: i32, image: bool, active: bool, bracket_after: bool, in0: bool, in1: bool }

type Doc = struct {
    a: *mem.Arena, failed: bool,
    nodes: []Node, nn: usize,
    root: i32, current: i32,
    sourcepos: bool, hardbreaks: bool, smart: bool,
    x_table: bool, x_strike: bool, x_autolink: bool, x_tagfilter: bool, x_tasklist: bool,
    line_number: i32, offset: i32, column: i32, first_nonspace: i32, first_nonspace_col: i32, indent: i32,
    blank: bool, partial_tab: bool, thematic_kill: i32, last_line_len: i32,
    line: str, llen: usize,
    refs: []Ref, nrefs: usize,
    delims: []Delim, nd: usize, last_delim: i32,
    brackets: []Bracket, nb: usize, last_bracket: i32
}

fn is_block(kind: u8) -> bool { ret kind < 20u8 }

fn is_inline(kind: u8) -> bool { ret kind >= 20u8 }

// Leaves have no children and no exit event of their own.
fn is_leaf(kind: u8) -> bool {
    ret kind == K_HTML_BLOCK || kind == K_THEMATIC || kind == K_CODE_BLOCK || kind == K_TEXT || kind == K_SOFTBREAK || kind == K_LINEBREAK || kind == K_CODE || kind == K_HTML_INLINE
}

fn new_node(d: *Doc, kind: u8) -> i32 {
    if d.nn >= d.nodes.len {
        var cap = d.nodes.len * 2usize
        if cap < 64usize { cap = 64usize }
        let (t, e) = mem.alloc[Node](d.a, cap)
        if e != ok {
            d.failed = true
            ret 0i32
        }
        var i = 0usize
        while i < d.nn {
            t[i] = d.nodes[i]
            i += 1usize
        }
        d.nodes = t
    }
    let id = i32(d.nn)
    d.nn += 1usize
    var n: Node = zero
    n.kind = kind
    n.parent = NIL
    n.first = NIL
    n.last = NIL
    n.prev = NIL
    n.next = NIL
    d.nodes[usize(id)] = n
    ret id
}

fn append_child(d: *Doc, parent: i32, child: i32) {
    let old = d.nodes[usize(parent)].last
    d.nodes[usize(child)].next = NIL
    d.nodes[usize(child)].prev = old
    d.nodes[usize(child)].parent = parent
    d.nodes[usize(parent)].last = child
    if old != NIL {
        d.nodes[usize(old)].next = child
    } else {
        d.nodes[usize(parent)].first = child
    }
}

fn unlink(d: *Doc, id: i32) {
    let p = d.nodes[usize(id)].prev
    let n = d.nodes[usize(id)].next
    let par = d.nodes[usize(id)].parent
    if p != NIL { d.nodes[usize(p)].next = n }
    if n != NIL { d.nodes[usize(n)].prev = p }
    if par != NIL {
        if d.nodes[usize(par)].first == id { d.nodes[usize(par)].first = n }
        if d.nodes[usize(par)].last == id { d.nodes[usize(par)].last = p }
    }
    d.nodes[usize(id)].next = NIL
    d.nodes[usize(id)].prev = NIL
    d.nodes[usize(id)].parent = NIL
}

fn insert_after(d: *Doc, node: i32, sib: i32) {
    let old_next = d.nodes[usize(node)].next
    d.nodes[usize(sib)].prev = node
    d.nodes[usize(sib)].next = old_next
    d.nodes[usize(sib)].parent = d.nodes[usize(node)].parent
    d.nodes[usize(node)].next = sib
    if old_next != NIL {
        d.nodes[usize(old_next)].prev = sib
    } else {
        let par = d.nodes[usize(node)].parent
        if par != NIL { d.nodes[usize(par)].last = sib }
    }
}

fn insert_before(d: *Doc, node: i32, sib: i32) {
    let old_prev = d.nodes[usize(node)].prev
    d.nodes[usize(sib)].next = node
    d.nodes[usize(sib)].prev = old_prev
    d.nodes[usize(sib)].parent = d.nodes[usize(node)].parent
    d.nodes[usize(node)].prev = sib
    if old_prev != NIL {
        d.nodes[usize(old_prev)].next = sib
    } else {
        let par = d.nodes[usize(node)].parent
        if par != NIL { d.nodes[usize(par)].first = sib }
    }
}

// Appends to a block's pending content.
fn content_put(d: *Doc, id: i32, s: str) {
    let at = usize(id)
    let need = d.nodes[at].clen + s.len
    if need > d.nodes[at].cbuf.len {
        var cap = d.nodes[at].cbuf.len * 2usize
        if cap < need { cap = need }
        if cap < 32usize { cap = 32usize }
        let (t, e) = mem.alloc[u8](d.a, cap)
        if e != ok {
            d.failed = true
            ret
        }
        var i = 0usize
        while i < d.nodes[at].clen {
            t[i] = d.nodes[at].cbuf[i]
            i += 1usize
        }
        d.nodes[at].cbuf = t
    }
    var k = 0usize
    while k < s.len {
        d.nodes[at].cbuf[d.nodes[at].clen + k] = s[k]
        k += 1usize
    }
    d.nodes[at].clen += s.len
}

fn content_putc(d: *Doc, id: i32, c: u8) {
    var one: [1]u8 = zero
    one[0usize] = c
    content_put(d, id, one[0usize..1usize])
}

fn content(d: *const Doc, id: i32) -> str {
    let at = usize(id)
    if d.nodes[at].clen == 0usize { ret "" }
    ret d.nodes[at].cbuf[0usize..d.nodes[at].clen]
}

// Replaces the pending content (used after link reference definitions are cut off).
fn content_set(d: *Doc, id: i32, s: str) {
    let at = usize(id)
    var none: []u8 = zero
    d.nodes[at].cbuf = none
    d.nodes[at].clen = 0usize
    content_put(d, id, s)
}

// A copy of `s` in the arena.
fn copy_str(d: *Doc, s: str) -> str {
    if s.len == 0usize { ret "" }
    let (t, e) = mem.alloc[u8](d.a, s.len)
    if e != ok {
        d.failed = true
        ret ""
    }
    var i = 0usize
    while i < s.len {
        t[i] = s[i]
        i += 1usize
    }
    ret t[0usize..s.len]
}

fn can_contain(d: *const Doc, parent: i32, child: u8) -> bool {
    if child == K_DOCUMENT { ret false }
    let pn = &d.nodes[usize(parent)]
    let k = pn.kind
    if k == K_TABLE { ret child == K_ROW }
    if k == K_ROW { ret child == K_CELL }
    if k == K_CELL {
        ret child == K_TEXT || child == K_CODE || child == K_EMPH || child == K_STRONG || child == K_LINK || child == K_IMAGE || child == K_STRIKE || child == K_HTML_INLINE
    }
    if k == K_STRIKE { ret is_inline(child) }
    if k == K_ITEM && pn.tasklist { ret true }
    if k == K_DOCUMENT || k == K_BLOCK_QUOTE || k == K_ITEM {
        ret is_block(child) && child != K_ITEM
    }
    if k == K_LIST { ret child == K_ITEM }
    if k == K_PARAGRAPH || k == K_HEADING || k == K_EMPH || k == K_STRONG || k == K_LINK || k == K_IMAGE { ret is_inline(child) }
    ret false
}

// --- Iteration, with cmark's enter and exit events.

type Iter = struct { root: i32, nx: i32, nx_enter: bool, node: i32, enter: bool }

fn iter_new(root: i32) -> Iter {
    var it: Iter = zero
    it.root = root
    it.nx = root
    it.nx_enter = true
    it.node = NIL
    ret it
}

// Moves to the next event; false at the end. The following event is chosen now, from the tree as it is.
fn iter_next(d: *const Doc, it: *Iter) -> bool {
    if it.nx == NIL { ret false }
    it.node = it.nx
    it.enter = it.nx_enter
    let n = &d.nodes[usize(it.node)]
    if it.enter && !is_leaf(n.kind) {
        if n.first == NIL {
            it.nx = it.node
            it.nx_enter = false
        } else {
            it.nx = n.first
            it.nx_enter = true
        }
    } else {
        if it.node == it.root {
            it.nx = NIL
        } else {
            if n.next != NIL {
                it.nx = n.next
                it.nx_enter = true
            } else {
                if n.parent != NIL {
                    it.nx = n.parent
                    it.nx_enter = false
                } else {
                    it.nx = NIL
                }
            }
        }
    }
    ret true
}

// Skip the node just entered, children and exit event included (cmark's renderers use it for autolinks).
fn iter_skip(d: *const Doc, it: *Iter) {
    let n = &d.nodes[usize(it.node)]
    if it.node == it.root {
        it.nx = NIL
    } else {
        if n.next != NIL {
            it.nx = n.next
            it.nx_enter = true
        } else {
            if n.parent != NIL {
                it.nx = n.parent
                it.nx_enter = false
            } else {
                it.nx = NIL
            }
        }
    }
}

// cmark_consolidate_text_nodes: runs of adjacent text nodes become one.
fn consolidate_text(d: *Doc, root: i32) {
    var it = iter_new(root)
    while iter_next(d, &it) {
        let cur = it.node
        if it.enter && d.nodes[usize(cur)].kind == K_TEXT {
            let nx = d.nodes[usize(cur)].next
            if nx != NIL && d.nodes[usize(nx)].kind == K_TEXT {
                var b = ct.buf_new(d.a, 64usize)
                ct.put(&b, d.nodes[usize(cur)].lit)
                var tmp = nx
                while tmp != NIL && d.nodes[usize(tmp)].kind == K_TEXT {
                    let _ = iter_next(d, &it)
                    ct.put(&b, d.nodes[usize(tmp)].lit)
                    d.nodes[usize(cur)].ec = d.nodes[usize(tmp)].ec
                    let after = d.nodes[usize(tmp)].next
                    unlink(d, tmp)
                    tmp = after
                }
                if b.failed { d.failed = true }
                d.nodes[usize(cur)].lit = ct.view(&b)
            }
        }
    }
}
