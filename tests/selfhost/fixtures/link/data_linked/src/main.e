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
    let (_, stale_after_clear) = linked.node[i32](&l, b)
    if nb != 5u32 || stale_after_clear != linked.InvalidNode { os.exit(10) }

    // 11: an iterator skips a node removed after it was created.
    let (iter0, iter_init_error) = linked.init[i32](a, 1usize)
    if iter_init_error != ok { os.exit(11) }
    var iter_list = iter0
    let (iter_id, iter_push_error) = linked.push_back[i32](&iter_list, 7i32)
    if iter_push_error != ok { os.exit(11) }
    var stale = linked.iter[i32](&iter_list)
    let (_, iter_remove_error) = linked.remove[i32](&iter_list, iter_id)
    let (_, stale_has) = linked.iter_next[i32](&stale)
    if iter_remove_error != ok || stale_has { os.exit(11) }

    // 12: a cross-list splice that cannot reserve every destination id leaves
    // both lists intact and the source identifiers live.
    let (source0, source_init_error) = linked.init[i32](a, 2usize)
    if source_init_error != ok { os.exit(12) }
    var source = source0
    let (source_first, source_first_error) = linked.push_back[i32](&source, 10i32)
    let (source_last, source_last_error) = linked.push_back[i32](&source, 20i32)
    if source_first_error != ok || source_last_error != ok { os.exit(12) }
    var splice_bytes: [48]u8 = zero
    var splice_arena = mem.arena_from(splice_bytes[..])
    let (destination0, destination_init_error) = linked.init[i32](&splice_arena, 1usize)
    if destination_init_error != ok { os.exit(12) }
    var destination = destination0
    let (destination_id, destination_push_error) = linked.push_back[i32](&destination, 99i32)
    if destination_push_error != ok { os.exit(12) }
    let splice_error = linked.splice[i32](&destination, linked.NONE, &source, source_first, source_last)
    let (source_first_node, source_first_node_error) = linked.node[i32](&source, source_first)
    let (source_last_node, source_last_node_error) = linked.node[i32](&source, source_last)
    let (destination_node, destination_node_error) = linked.node[i32](&destination, destination_id)
    let (destination_first, has_destination_first) = linked.first[i32](&destination)
    let (destination_last, has_destination_last) = linked.last[i32](&destination)
    if splice_error != mem.Exhausted || linked.len[i32](&source) != 2usize || linked.len[i32](&destination) != 1usize { os.exit(12) }
    if source_first_node_error != ok || source_last_node_error != ok || destination_node_error != ok || source_first_node.value != 10i32 || source_last_node.value != 20i32 || destination_node.value != 99i32 { os.exit(12) }
    if !has_destination_first || !has_destination_last || destination_first != destination_id || destination_last != destination_id { os.exit(12) }
    var source_iter = linked.iter[i32](&source)
    let (first_value, first_has) = linked.iter_next[i32](&source_iter)
    let (last_value, last_has) = linked.iter_next[i32](&source_iter)
    let (_, source_done) = linked.iter_next[i32](&source_iter)
    if !first_has || !last_has || source_done || first_value != 10i32 || last_value != 20i32 { os.exit(12) }
    var destination_iter = linked.iter[i32](&destination)
    let (destination_value, destination_has) = linked.iter_next[i32](&destination_iter)
    let (_, destination_done) = linked.iter_next[i32](&destination_iter)
    if !destination_has || destination_done || destination_value != 99i32 { os.exit(12) }
    os.exit(0)
    ret ok
}
