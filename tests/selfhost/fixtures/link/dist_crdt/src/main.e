// `e.dist.crdt`: three sites apply LCG operation sequences with occasional
// pairwise merges, and the counters, the LWW register and the OR-set answer
// what a Python replica answers per site and after a full merge; merging in
// every order gives one state (commutativity, associativity) and merging a
// replica with itself changes nothing (idempotence); the `merge` dispatch
// agrees with the typed merges. Each check exits with its own code.

use e.dist.crdt
use e.io
use e.mem
use e.os

fn next(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn mask(s: *const crdt.OrSet) -> u64 {
    var m = 0u64
    var e = 0u64
    while e < 8u64 {
        if crdt.orset_contains(s, e) { m |= 1u64 << u32(e) }
        e += 1u64
    }
    ret m
}

fn copy_set(dst: *crdt.OrSet, src: *const crdt.OrSet) {
    var i = 0usize
    while i < src.count {
        dst.elems[i] = src.elems[i]
        i += 1usize
    }
    dst.count = src.count
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 777u64
    // 1: counters.
    var gc: [9]u64 = zero
    var pp: [9]u64 = zero
    var nn: [9]u64 = zero
    var g: [3]crdt.GCounter = zero
    var p: [3]crdt.PnCounter = zero
    var s = 0usize
    while s < 3usize {
        g[s] = crdt.gcounter(gc[s * 3usize..s * 3usize + 3usize])
        p[s] = crdt.pncounter(pp[s * 3usize..s * 3usize + 3usize], nn[s * 3usize..s * 3usize + 3usize])
        s += 1usize
    }
    var op = 0usize
    while op < 60usize {
        let r = next(&state)
        let site = usize(r % 3u64)
        let delta = (r >> 2u32) % 10u64 + 1u64
        let kind = (r >> 8u32) % 4u64
        crdt.gcounter_increment(&g[site], site, delta)
        if kind < 2u64 { crdt.pncounter_increment(&p[site], site, delta) } else { crdt.pncounter_decrement(&p[site], site, delta) }
        if op % 10usize == 9usize {
            let d = (site + 1usize) % 3usize
            crdt.gcounter_merge(&g[d], &g[site])
            crdt.pncounter_merge(&p[d], &p[site])
        }
        op += 1usize
    }
    let want_g = [3]u64 { 316u64, 185u64, 272u64 }
    let want_p = [3]i64 { 0i64 - 28i64, 0i64 - 43i64, 0i64 - 2i64 }
    s = 0usize
    while s < 3usize {
        if crdt.gcounter_value(&g[s]) != want_g[s] || crdt.pncounter_value(&p[s]) != want_p[s] { os.exit(1i32) }
        s += 1usize
    }
    // Full merge through the dispatch, in two orders, and idempotently.
    var ca: crdt.Crdt = zero
    var cb: crdt.Crdt = zero
    var cc: crdt.Crdt = zero
    ca.kind = .GCounter
    ca.gcounter = g[0usize]
    cb.kind = .GCounter
    cb.gcounter = g[1usize]
    cc.kind = .GCounter
    cc.gcounter = g[2usize]
    if crdt.merge(&ca, &cb) != ok || crdt.merge(&ca, &cc) != ok || crdt.merge(&ca, &ca) != ok { os.exit(1i32) }
    if crdt.merge(&cc, &cb) != ok || crdt.merge(&cc, &ca) != ok { os.exit(1i32) }
    if crdt.gcounter_value(&ca.gcounter) != 348u64 || crdt.gcounter_value(&cc.gcounter) != 348u64 { os.exit(1i32) }
    var pa: crdt.Crdt = zero
    pa.kind = .PnCounter
    pa.pncounter = p[2usize]
    var pb: crdt.Crdt = zero
    pb.kind = .PnCounter
    pb.pncounter = p[0usize]
    var pc: crdt.Crdt = zero
    pc.kind = .PnCounter
    pc.pncounter = p[1usize]
    if crdt.merge(&pa, &pb) != ok || crdt.merge(&pa, &pc) != ok || crdt.merge(&pa, &pa) != ok { os.exit(1i32) }
    if crdt.pncounter_value(&pa.pncounter) != 0i64 - 60i64 { os.exit(1i32) }

    // 2: the LWW register.
    var regs: [3]crdt.Lww = zero
    var took: [3]usize = zero
    s = 0usize
    while s < 3usize {
        regs[s] = crdt.lww()
        s += 1usize
    }
    op = 0usize
    while op < 30usize {
        let r = next(&state)
        let site = usize(r % 3u64)
        if crdt.lww_set(&regs[site], (r >> 8u32) % 1000u64, (r >> 2u32) % 16u64, u32(site)) { took[site] += 1usize }
        op += 1usize
    }
    if took[0usize] != 3usize || took[1usize] != 2usize || took[2usize] != 3usize { os.exit(2i32) }
    if regs[0usize].value != 970u64 || regs[0usize].stamp != 14u64 || regs[1usize].value != 663u64 { os.exit(2i32) }
    var la: crdt.Crdt = zero
    la.kind = .Lww
    la.lww = regs[0usize]
    var lb: crdt.Crdt = zero
    lb.kind = .Lww
    lb.lww = regs[1usize]
    var lc: crdt.Crdt = zero
    lc.kind = .Lww
    lc.lww = regs[2usize]
    if crdt.merge(&la, &lb) != ok || crdt.merge(&la, &lc) != ok || crdt.merge(&lb, &lc) != ok || crdt.merge(&lb, &la) != ok { os.exit(2i32) }
    if la.lww.value != 770u64 || la.lww.stamp != 15u64 || la.lww.site != 2u32 { os.exit(2i32) }
    if lb.lww.value != 770u64 || lb.lww.stamp != 15u64 || lb.lww.site != 2u32 { os.exit(2i32) }
    if crdt.lww_merge(&la.lww, &lc.lww) { os.exit(2i32) }

    // 3: the OR-set.
    var e0: [128]crdt.OrElem = zero
    var e1: [128]crdt.OrElem = zero
    var e2: [128]crdt.OrElem = zero
    var sets: [3]crdt.OrSet = zero
    sets[0usize] = crdt.orset(e0[..], 0u32)
    sets[1usize] = crdt.orset(e1[..], 1u32)
    sets[2usize] = crdt.orset(e2[..], 2u32)
    var removed = 0usize
    op = 0usize
    while op < 120usize {
        let site = op % 3usize
        let r = next(&state)
        let e = r % 8u64
        if (r >> 3u32) % 3u64 < 2u64 {
            if crdt.orset_add(&sets[site], e) != ok { os.exit(3i32) }
        } else {
            removed += crdt.orset_remove(&sets[site], e)
        }
        if op % 10usize == 9usize {
            if crdt.orset_merge(&sets[(site + 1usize) % 3usize], &sets[site]) != ok { os.exit(3i32) }
        }
        op += 1usize
    }
    let want_m = [3]u64 { 191u64, 135u64, 191u64 }
    let want_c = [3]usize { 75usize, 65usize, 72usize }
    s = 0usize
    while s < 3usize {
        if mask(&sets[s]) != want_m[s] || sets[s].count != want_c[s] { os.exit(3i32) }
        s += 1usize
    }
    if removed != 81usize { os.exit(3i32) }

    // 4: every merge order agrees, and a self-merge changes nothing.
    var ex: [128]crdt.OrElem = zero
    var ey: [128]crdt.OrElem = zero
    var ez: [128]crdt.OrElem = zero
    var x = crdt.orset(ex[..], 0u32)
    var y = crdt.orset(ey[..], 0u32)
    var z = crdt.orset(ez[..], 2u32)
    copy_set(&x, &sets[0usize])
    copy_set(&y, &sets[0usize])
    copy_set(&z, &sets[2usize])
    if crdt.orset_merge(&x, &sets[1usize]) != ok || crdt.orset_merge(&x, &sets[2usize]) != ok { os.exit(4i32) }
    if crdt.orset_merge(&y, &sets[2usize]) != ok || crdt.orset_merge(&y, &sets[1usize]) != ok { os.exit(4i32) }
    var oz: crdt.Crdt = zero
    oz.kind = .OrSet
    oz.orset = z
    var o0: crdt.Crdt = zero
    o0.kind = .OrSet
    o0.orset = sets[0usize]
    var o1: crdt.Crdt = zero
    o1.kind = .OrSet
    o1.orset = sets[1usize]
    if crdt.merge(&oz, &o0) != ok || crdt.merge(&oz, &o1) != ok || crdt.merge(&oz, &oz) != ok { os.exit(4i32) }
    if mask(&x) != 191u64 || mask(&y) != 191u64 || mask(&oz.orset) != 191u64 { os.exit(4i32) }
    if x.count != 76usize || y.count != 76usize || oz.orset.count != 76usize { os.exit(4i32) }
    if crdt.orset_merge(&x, &x) != ok || x.count != 76usize || mask(&x) != 191u64 { os.exit(4i32) }
    if crdt.orset_remove(&x, 7u64) == 0usize || crdt.orset_contains(&x, 7u64) || mask(&x) != 63u64 { os.exit(4i32) }
    // A full pool refuses.
    var tiny: [2]crdt.OrElem = zero
    var t = crdt.orset(tiny[..], 9u32)
    if crdt.orset_add(&t, 1u64) != ok || crdt.orset_add(&t, 2u64) != ok || crdt.orset_add(&t, 3u64) != crdt.TooSmall { os.exit(4i32) }
    if crdt.orset_merge(&t, &x) != crdt.TooSmall { os.exit(4i32) }

    try io.print("dist crdt ok\n")
    ret ok
}
