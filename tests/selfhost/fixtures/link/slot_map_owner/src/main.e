// Generation-tagged handles with their owner (D1560, H02): a key answers only in the
// map that issued it, only while its slot holds the value it was issued for. A key
// from another map, a key after `remove` or `clear`, and a key from a map whose arena
// was reset and whose storage a new map reuses all answer nothing.
use e.mem
use e.os
use e.data.slot_map

fn main(a: *mem.Arena, args: []str) -> err {
    let (first_map, first_error) = slot_map.init[i64](a, 4usize)
    if first_error != ok { ret first_error }
    var first = first_map
    let (second_map, second_error) = slot_map.init[i64](a, 4usize)
    if second_error != ok { ret second_error }
    var second = second_map
    let (k1, e1) = slot_map.insert[i64](&first, 11i64)
    let (k2, e2) = slot_map.insert[i64](&second, 22i64)
    if e1 != ok || e2 != ok { os.exit(2i32) }
    // Same slot and generation in both maps; only the owner tells them apart.
    if k1.slot != k2.slot || k1.generation != k2.generation || k1.owner == k2.owner { os.exit(3i32) }
    let (v1, h1) = slot_map.get[i64](&first, k1)
    let (_, crossed) = slot_map.get[i64](&second, k1)
    if !h1 || *v1 != 11i64 || crossed { os.exit(4i32) }
    let (removed, was) = slot_map.remove[i64](&first, k1)
    let (_, stale) = slot_map.get[i64](&first, k1)
    if !was || removed != 11i64 || stale { os.exit(5i32) }
    slot_map.clear[i64](&second)
    let (_, cleared) = slot_map.get[i64](&second, k2)
    if cleared { os.exit(6i32) }
    // A map made after a reset reuses the storage a key's map had.
    let mark = mem.mark(a)
    let (old_map, old_error) = slot_map.init[i64](a, 2usize)
    if old_error != ok { os.exit(7i32) }
    var old = old_map
    let (old_key, old_insert) = slot_map.insert[i64](&old, 5i64)
    if old_insert != ok { os.exit(7i32) }
    mem.reset(a, mark)
    let (new_map, new_error) = slot_map.init[i64](a, 2usize)
    if new_error != ok { os.exit(8i32) }
    var fresh = new_map
    let (new_key, new_insert) = slot_map.insert[i64](&fresh, 6i64)
    if new_insert != ok || new_key.slot != old_key.slot || new_key.generation != old_key.generation { os.exit(9i32) }
    let (_, reused) = slot_map.get[i64](&fresh, old_key)
    if reused { os.exit(10i32) }
    ret ok
}
