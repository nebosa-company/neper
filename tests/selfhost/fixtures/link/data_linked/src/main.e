// `e.data.linked`: stable node identifiers through insertion at both ends and beside a
// node, removal that never reuses an identifier, the neighbours a node reports, and
// `clear` invalidating every identifier. Every check has its own exit code.
use e.os
use e.mem
use e.data.linked as linked

fn main(a: *mem.Arena, args: []str) -> err {
    let (initial, init_error) = linked.init[i32](a, 1usize)
    if init_error != ok { os.exit(1) }
    var l = initial
    let (b, _) = linked.push_back[i32](&l, 2i32)
    let (aid, _) = linked.push_front[i32](&l, 1i32)
    let (c, _) = linked.push_back[i32](&l, 4i32)
    let (m, _) = linked.insert_before[i32](&l, c, 3i32)
    let (z, _) = linked.insert_after[i32](&l, aid, 0i32)
    if linked.len[i32](&l) != 5usize { os.exit(2) }
    var it = linked.iter[i32](&l)
    var order: [5]i32 = zero
    var n = 0usize
    while true {
        let (v, has) = linked.iter_next[i32](&it)
        if !has { break }
        order[n] = v
        n += 1usize
    }
    if n != 5usize || order[0] != 1i32 || order[1] != 0i32 || order[2] != 2i32 || order[3] != 3i32 || order[4] != 4i32 { os.exit(3) }
    let (removed, remove_error) = linked.remove[i32](&l, z)
    if remove_error != ok || removed != 0i32 || linked.len[i32](&l) != 4usize { os.exit(4) }
    let (_, again) = linked.remove[i32](&l, z)
    let (_, bad_node) = linked.node[i32](&l, z)
    if again != linked.InvalidNode || bad_node != linked.InvalidNode { os.exit(5) }
    let (node_b, node_error) = linked.node[i32](&l, b)
    if node_error != ok || node_b.value != 2i32 || node_b.previous != aid || node_b.next != m { os.exit(6) }
    let (f, has_f) = linked.first[i32](&l)
    let (la, has_la) = linked.last[i32](&l)
    if !has_f || f != aid || !has_la || la != c { os.exit(7) }
    let (_, rf) = linked.remove[i32](&l, aid)
    let (_, rl) = linked.remove[i32](&l, c)
    let (f2, _) = linked.first[i32](&l)
    let (l2, _) = linked.last[i32](&l)
    if rf != ok || rl != ok || f2 != b || l2 != m { os.exit(8) }
    linked.clear[i32](&l)
    let (_, has_first) = linked.first[i32](&l)
    let (_, cleared) = linked.node[i32](&l, b)
    if has_first || cleared != linked.InvalidNode || linked.len[i32](&l) != 0usize { os.exit(9) }
    let (nb, _) = linked.push_back[i32](&l, 9i32)
    if nb != 0u32 { os.exit(10) }
    os.exit(0)
    ret ok
}
