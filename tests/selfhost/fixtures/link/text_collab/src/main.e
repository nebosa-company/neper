// `e.text.collab`: operational transformation converges on 200 random
// concurrent pairs (both application orders agree, and the results hash to
// the Python replica's value), two RGA replicas that apply a shared prefix
// and then each other's concurrent ops in opposite orders read the same
// text, and fractional-index keys inserted at 100 random positions stay
// strictly ordered and never end in `0`. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.text.collab as collab

type Lcg = struct { state: u64 }

fn draw(l: *Lcg) -> u64 {
    l.state = l.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret l.state >> 33u32
}

fn mix(h: u64, b: u8) -> u64 { ret (h ^ u64(b)) *% 1099511628211u64 }

fn gen_op(l: *Lcg, length: usize, text: []u8) -> collab.Op {
    let kind = draw(l) % 2u64
    if kind == 0u64 || length == 0usize {
        let pos = usize(draw(l) % u64(length + 1usize))
        let tl = 1usize + usize(draw(l) % 3u64)
        var i = 0usize
        while i < tl {
            text[i] = 65u8 + u8(draw(l) % 26u64)
            i += 1usize
        }
        ret collab.insert(pos, text[..tl])
    }
    let pos = usize(draw(l) % u64(length))
    let len = 1usize + usize(draw(l) % u64(length - pos))
    ret collab.delete(pos, len)
}

fn gen_crdt(l: *Lcg, d: *collab.Doc, site: u32, counter: u32) -> collab.CrdtOp {
    let kind = draw(l) % 4u64
    let visible = collab.crdt_len(d)
    if kind < 3u64 || visible == 0usize {
        let slot = usize(draw(l) % u64(d.used))
        let after = collab.Id { site: d.site[slot], counter: d.counter[slot] }
        let byte = 97u8 + u8(draw(l) % 26u64)
        ret collab.CrdtOp { insert: true, after: after, id: collab.Id { site: site, counter: counter }, byte: byte }
    }
    let k = usize(draw(l) % u64(visible))
    let (id, _) = collab.crdt_id_at(d, k)
    ret collab.CrdtOp { insert: false, after: collab.Id { site: 0u32, counter: 0u32 }, id: id, byte: 0u8 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var l = Lcg { state: 1u64 }

    // 1: OT convergence on 200 random pairs.
    var h = 14695981039346656037u64
    var base: [16]u8 = zero
    var atext: [4]u8 = zero
    var btext: [4]u8 = zero
    var t1: [24]u8 = zero
    var t2: [24]u8 = zero
    var r1: [32]u8 = zero
    var r2: [32]u8 = zero
    var pair = 0usize
    while pair < 200usize {
        let length = usize(draw(&l) % 12u64)
        var i = 0usize
        while i < length {
            base[i] = 97u8 + u8(draw(&l) % 26u64)
            i += 1usize
        }
        let op_a = gen_op(&l, length, atext[..])
        let op_b = gen_op(&l, length, btext[..])
        let a_wins = draw(&l) % 2u64 == 0u64
        let (n1, e1) = collab.apply(base[..length], op_a, t1[..])
        let (m1, f1) = collab.apply(t1[..n1], collab.transform(op_b, op_a, !a_wins), r1[..])
        let (n2, e2) = collab.apply(base[..length], op_b, t2[..])
        let (m2, f2) = collab.apply(t2[..n2], collab.transform(op_a, op_b, a_wins), r2[..])
        if e1 != ok || f1 != ok || e2 != ok || f2 != ok { os.exit(1i32) }
        if m1 != m2 || !mem.eq[u8](r1[..m1], r2[..m2]) { os.exit(1i32) }
        i = 0usize
        while i < m1 {
            h = mix(h, r1[i])
            i += 1usize
        }
        h = mix(h, 10u8)
        pair += 1usize
    }
    if h != 13949744748781019158u64 { os.exit(1i32) }
    let (_, past) = collab.apply(base[..4usize], collab.insert(5usize, "x"), t1[..])
    if past != collab.Invalid { os.exit(1i32) }
    let (_, room) = collab.apply(base[..4usize], collab.insert(0usize, "xyz"), t1[..6usize])
    if room != collab.TooSmall { os.exit(1i32) }

    // 2: RGA convergence: a shared prefix, then 12 concurrent ops per site
    // applied in opposite orders.
    var site_a: [64]u32 = zero
    var counter_a: [64]u32 = zero
    var byte_a: [64]u8 = zero
    var dead_a: [64]u8 = zero
    var link_a: [64]u32 = zero
    var site_b: [64]u32 = zero
    var counter_b: [64]u32 = zero
    var byte_b: [64]u8 = zero
    var dead_b: [64]u8 = zero
    var link_b: [64]u32 = zero
    var doc_a = collab.doc(site_a[..], counter_a[..], byte_a[..], dead_a[..], link_a[..])
    var doc_b = collab.doc(site_b[..], counter_b[..], byte_b[..], dead_b[..], link_b[..])
    var clock = 0u32
    var i = 0usize
    while i < 10usize {
        clock += 1u32
        let op = gen_crdt(&l, &doc_a, u32(i % 2usize), clock)
        if collab.crdt_apply(&doc_a, op) != ok || collab.crdt_apply(&doc_b, op) != ok { os.exit(2i32) }
        i += 1usize
    }
    var ops0: [12]collab.CrdtOp = zero
    var ops1: [12]collab.CrdtOp = zero
    var c0 = clock
    i = 0usize
    while i < 12usize {
        c0 += 1u32
        ops0[i] = gen_crdt(&l, &doc_a, 0u32, c0)
        if collab.crdt_apply(&doc_a, ops0[i]) != ok { os.exit(2i32) }
        i += 1usize
    }
    var c1 = clock
    i = 0usize
    while i < 12usize {
        c1 += 1u32
        ops1[i] = gen_crdt(&l, &doc_b, 1u32, c1)
        if collab.crdt_apply(&doc_b, ops1[i]) != ok { os.exit(2i32) }
        i += 1usize
    }
    i = 0usize
    while i < 12usize {
        if collab.crdt_apply(&doc_a, ops1[i]) != ok || collab.crdt_apply(&doc_b, ops0[i]) != ok { os.exit(2i32) }
        i += 1usize
    }
    let (ta, ea) = collab.crdt_text(&doc_a, r1[..])
    let (tb, eb) = collab.crdt_text(&doc_b, r2[..])
    if ea != ok || eb != ok || ta != 22usize || tb != ta || !mem.eq[u8](r1[..ta], r2[..tb]) { os.exit(2i32) }
    if collab.crdt_len(&doc_a) != 22usize || doc_a.used != 29usize || doc_b.used != 29usize { os.exit(2i32) }
    h = 14695981039346656037u64
    i = 0usize
    while i < ta {
        h = mix(h, r1[i])
        i += 1usize
    }
    if h != 2566888816437191092u64 { os.exit(2i32) }
    let (id0, id_error) = collab.crdt_id_at(&doc_a, 0usize)
    if id_error != ok || collab.crdt_find(&doc_a, id0) >= doc_a.used || dead_a[collab.crdt_find(&doc_a, id0)] != 0u8 { os.exit(2i32) }
    if collab.crdt_insert(&doc_a, collab.Id { site: 9u32, counter: 9u32 }, collab.Id { site: 0u32, counter: 99u32 }, 120u8) != collab.Invalid { os.exit(2i32) }
    if collab.crdt_insert(&doc_a, collab.Id { site: 0u32, counter: 0u32 }, id0, 120u8) != collab.Invalid { os.exit(2i32) }
    if collab.crdt_delete(&doc_a, collab.Id { site: 9u32, counter: 9u32 }) != collab.Invalid { os.exit(2i32) }
    var tiny = collab.doc(site_a[..2usize], counter_a[..2usize], byte_a[..2usize], dead_a[..2usize], link_a[..2usize])
    if collab.crdt_insert(&tiny, collab.Id { site: 0u32, counter: 0u32 }, collab.Id { site: 1u32, counter: 1u32 }, 65u8) != ok { os.exit(2i32) }
    if collab.crdt_insert(&tiny, collab.Id { site: 0u32, counter: 0u32 }, collab.Id { site: 1u32, counter: 2u32 }, 66u8) != collab.TooSmall { os.exit(2i32) }

    // 3: fractional indexing at 100 random positions.
    var keys: [3072]u8 = zero
    var klen: [128]usize = zero
    var order: [128]usize = zero
    let (n0, e0) = collab.order_key_between("", "", keys[..24usize])
    if e0 != ok || n0 != 1usize || keys[0usize] != 86u8 { os.exit(3i32) }
    klen[0usize] = n0
    var count = 1usize
    var step = 0usize
    while step < 100usize {
        let p = usize(draw(&l) % u64(count + 1usize))
        var left = keys[..0usize]
        var right = keys[..0usize]
        if p > 0usize {
            let o = order[p - 1usize]
            left = keys[o * 24usize..o * 24usize + klen[o]]
        }
        if p < count {
            let o = order[p]
            right = keys[o * 24usize..o * 24usize + klen[o]]
        }
        let r = count
        let (n, e) = collab.order_key_between(left, right, keys[r * 24usize..(r + 1usize) * 24usize])
        if e != ok || n == 0usize { os.exit(3i32) }
        klen[r] = n
        let fresh = keys[r * 24usize..r * 24usize + n]
        if p > 0usize && str.compare(left, fresh) >= 0i32 { os.exit(3i32) }
        if p < count && str.compare(fresh, right) >= 0i32 { os.exit(3i32) }
        if fresh[n - 1usize] == 48u8 { os.exit(3i32) }
        var j = count
        while j > p {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[p] = r
        count += 1usize
        step += 1usize
    }
    h = 14695981039346656037u64
    i = 0usize
    while i < count {
        let o = order[i]
        var j = 0usize
        while j < klen[o] {
            h = mix(h, keys[o * 24usize + j])
            j += 1usize
        }
        h = mix(h, 10u8)
        i += 1usize
    }
    if h != 10394832022157560623u64 { os.exit(3i32) }
    let (n_ab, e_ab) = collab.order_key_between("a", "b", t1[..])
    if e_ab != ok || !mem.eq[u8](t1[..n_ab], "aV") { os.exit(3i32) }
    let (n_a1, e_a1) = collab.order_key_between("a", "a1", t1[..])
    if e_a1 != ok || !mem.eq[u8](t1[..n_a1], "a0V") { os.exit(3i32) }
    let (_, same) = collab.order_key_between("a", "a", t1[..])
    let (_, reversed) = collab.order_key_between("b", "a", t1[..])
    let (_, trailing) = collab.order_key_between("a0", "b", t1[..])
    let (_, foreign) = collab.order_key_between("a-", "b", t1[..])
    let (_, tight) = collab.order_key_between("a", "a1", t1[..2usize])
    if same != collab.Invalid || reversed != collab.Invalid || trailing != collab.Invalid || foreign != collab.Invalid || tight != collab.TooSmall { os.exit(3i32) }

    try io.print("text collab ok\n")
    ret ok
}
