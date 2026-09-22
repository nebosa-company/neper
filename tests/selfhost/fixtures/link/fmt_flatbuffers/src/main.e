// `e.fmt.flatbuffers`: the classic Monster built by the Python `flatbuffers`
// package reads back field by field (root and identifier, scalars with
// defaults, an inline struct, a byte vector, strings, a vector of tables, a
// union, an absent table), a truncated buffer and an out-of-range vector
// index answer `Invalid`, and the same Monster built with the Neper builder
// reads back to the same values. Each check exits with its own code.

use e.fmt.flatbuffers as fb
use e.io
use e.mem
use e.os

// Monster fields: 0 pos, 1 mana, 2 hp, 3 name, 4 friendly, 5 inventory,
// 6 color, 7 weapons, 8 equipped_type, 9 equipped, 10 enemy. Weapon: 0 name, 1 damage.
fn check_monster(buf: []const u8, code: i32) {
    let (root, root_error) = fb.root_with_identifier(buf, "MONS")
    if root_error != ok || root == 0usize { os.exit(code) }
    let (hp, hp_error) = fb.get_i16(buf, root, 2usize, 100i16)
    if hp_error != ok || hp != 300i16 { os.exit(code) }
    let (mana, mana_error) = fb.get_i16(buf, root, 1usize, 150i16)
    if mana_error != ok || mana != 150i16 { os.exit(code) }
    let (friendly, friendly_error) = fb.get_bool(buf, root, 4usize, false)
    if friendly_error != ok || friendly { os.exit(code) }
    let (pos, pos_error) = fb.get_struct(buf, root, 0usize)
    if pos_error != ok || pos == 0usize { os.exit(code) }
    let (x, x_error) = fb.load[f32](buf, pos)
    let (y, y_error) = fb.load[f32](buf, pos + 4usize)
    let (z, z_error) = fb.load[f32](buf, pos + 8usize)
    if x_error != ok || y_error != ok || z_error != ok { os.exit(code) }
    if x != 1.0f32 || y != 2.0f32 || z != 3.0f32 { os.exit(code) }
    let (name, name_error) = fb.get_string(buf, root, 3usize)
    if name_error != ok || !mem.eq[u8](name, "Orc") { os.exit(code) }
    let (inv, inv_error) = fb.get_vector(buf, root, 5usize)
    if inv_error != ok || inv.len != 10usize { os.exit(code) }
    let (inv_bytes, inv_bytes_error) = fb.vector_u8(buf, inv)
    if inv_bytes_error != ok || inv_bytes.len != 10usize { os.exit(code) }
    var i = 0usize
    while i < 10usize {
        if inv_bytes[i] != u8(i & 255usize) { os.exit(code) }
        i += 1usize
    }
    let (color, color_error) = fb.get_u8(buf, root, 6usize, 0u8)
    if color_error != ok || color != 2u8 { os.exit(code) }
    let (weapons, weapons_error) = fb.get_vector(buf, root, 7usize)
    if weapons_error != ok || weapons.len != 2usize { os.exit(code) }
    let (sword, sword_error) = fb.vector_table_at(buf, weapons, 0usize)
    if sword_error != ok { os.exit(code) }
    let (sword_name, sword_name_error) = fb.get_string(buf, sword, 0usize)
    if sword_name_error != ok || !mem.eq[u8](sword_name, "Sword") { os.exit(code) }
    let (sword_damage, sword_damage_error) = fb.get_i16(buf, sword, 1usize, 0i16)
    if sword_damage_error != ok || sword_damage != 3i16 { os.exit(code) }
    let (axe, axe_error) = fb.vector_table_at(buf, weapons, 1usize)
    if axe_error != ok { os.exit(code) }
    let (axe_name, axe_name_error) = fb.get_string(buf, axe, 0usize)
    if axe_name_error != ok || !mem.eq[u8](axe_name, "Axe") { os.exit(code) }
    let (axe_damage, axe_damage_error) = fb.get_i16(buf, axe, 1usize, 0i16)
    if axe_damage_error != ok || axe_damage != 5i16 { os.exit(code) }
    let (kind, kind_error) = fb.union_type(buf, root, 8usize)
    if kind_error != ok || kind != 1u8 { os.exit(code) }
    let (equipped, equipped_error) = fb.union_value(buf, root, 9usize)
    if equipped_error != ok || equipped != axe { os.exit(code) }
    let (enemy, enemy_error) = fb.get_table(buf, root, 10usize)
    if enemy_error != ok || enemy != 0usize { os.exit(code) }
    let (beyond, beyond_error) = fb.get_table(buf, root, 11usize)
    if beyond_error != ok || beyond != 0usize { os.exit(code) }
}

fn weapon(b: *fb.Builder, name: str, damage: i16) -> (usize, err) {
    let (n, n_error) = fb.create_string(b, name)
    if n_error != ok { ret (0usize, n_error) }
    let start_error = fb.start_table(b, 2usize)
    if start_error != ok { ret (0usize, start_error) }
    let name_error = fb.add_offset(b, 0usize, n)
    if name_error != ok { ret (0usize, name_error) }
    let damage_error = fb.add_i16(b, 1usize, damage, 0i16)
    if damage_error != ok { ret (0usize, damage_error) }
    let (off, end_error) = fb.end_table(b)
    ret (off, end_error)
}

fn build_monster(storage: []u8) -> ([]const u8, err) {
    var b = fb.builder(storage)
    let (sword, sword_error) = weapon(&b, "Sword", 3i16)
    if sword_error != ok { ret (zero, sword_error) }
    let (axe, axe_error) = weapon(&b, "Axe", 5i16)
    if axe_error != ok { ret (zero, axe_error) }
    let (name, name_error) = fb.create_string(&b, "Orc")
    if name_error != ok { ret (zero, name_error) }
    let inventory: [10]u8 = [10]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    let (inv, inv_error) = fb.create_vector_u8(&b, inventory[..])
    if inv_error != ok { ret (zero, inv_error) }
    let start_vector_error = fb.start_vector(&b, 4usize, 2usize, 4usize)
    if start_vector_error != ok { ret (zero, start_vector_error) }
    let axe_offset_error = fb.put_offset(&b, axe)
    if axe_offset_error != ok { ret (zero, axe_offset_error) }
    let sword_offset_error = fb.put_offset(&b, sword)
    if sword_offset_error != ok { ret (zero, sword_offset_error) }
    let (weapons, weapons_error) = fb.end_vector(&b)
    if weapons_error != ok { ret (zero, weapons_error) }

    let start_error = fb.start_table(&b, 11usize)
    if start_error != ok { ret (zero, start_error) }
    let prep_error = fb.prep(&b, 4usize, 12usize)
    if prep_error != ok { ret (zero, prep_error) }
    let z_error = fb.put[f32](&b, 3.0f32)
    let y_error = fb.put[f32](&b, 2.0f32)
    let x_error = fb.put[f32](&b, 1.0f32)
    if z_error != ok || y_error != ok || x_error != ok { ret (zero, x_error) }
    fb.slot(&b, 0usize)
    let hp_error = fb.add_i16(&b, 2usize, 300i16, 100i16)
    if hp_error != ok { ret (zero, hp_error) }
    let mana_error = fb.add_i16(&b, 1usize, 150i16, 150i16)
    if mana_error != ok { ret (zero, mana_error) }
    let name_slot_error = fb.add_offset(&b, 3usize, name)
    if name_slot_error != ok { ret (zero, name_slot_error) }
    let inv_slot_error = fb.add_offset(&b, 5usize, inv)
    if inv_slot_error != ok { ret (zero, inv_slot_error) }
    let color_error = fb.add_u8(&b, 6usize, 2u8, 0u8)
    if color_error != ok { ret (zero, color_error) }
    let weapons_slot_error = fb.add_offset(&b, 7usize, weapons)
    if weapons_slot_error != ok { ret (zero, weapons_slot_error) }
    let kind_error = fb.add_u8(&b, 8usize, 1u8, 0u8)
    if kind_error != ok { ret (zero, kind_error) }
    let equipped_error = fb.add_offset(&b, 9usize, axe)
    if equipped_error != ok { ret (zero, equipped_error) }
    let (orc, end_error) = fb.end_table(&b)
    if end_error != ok { ret (zero, end_error) }
    let finish_error = fb.finish(&b, orc, "MONS")
    if finish_error != ok { ret (zero, finish_error) }
    ret (fb.bytes(&b), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Built by the Python `flatbuffers` package (scratchpad ref.py).
    let python: [164]u8 = [164]u8{ 32, 0, 0, 0, 77, 79, 78, 83, 24, 0, 44, 0, 32, 0, 0, 0, 30, 0, 24, 0, 0, 0, 20, 0, 19, 0, 12, 0, 11, 0, 4, 0, 24, 0, 0, 0, 76, 0, 0, 0, 0, 0, 0, 1, 32, 0, 0, 0, 0, 0, 0, 2, 36, 0, 0, 0, 48, 0, 0, 0, 0, 0, 44, 1, 0, 0, 128, 63, 0, 0, 0, 64, 0, 0, 64, 64, 2, 0, 0, 0, 60, 0, 0, 0, 28, 0, 0, 0, 10, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 3, 0, 0, 0, 79, 114, 99, 0, 236, 255, 255, 255, 0, 0, 5, 0, 4, 0, 0, 0, 3, 0, 0, 0, 65, 120, 101, 0, 8, 0, 12, 0, 8, 0, 6, 0, 8, 0, 0, 0, 0, 0, 3, 0, 4, 0, 0, 0, 5, 0, 0, 0, 83, 119, 111, 114, 100, 0, 0, 0 }
    let buf: []const u8 = python[..]

    // 1: root and identifier.
    let (root, root_error) = fb.root(buf)
    if root_error != ok || root != 32usize { os.exit(1i32) }
    if !fb.has_identifier(buf, "MONS") || fb.has_identifier(buf, "MONX") { os.exit(1i32) }
    let (_, wrong_ident) = fb.root_with_identifier(buf, "MONX")
    if wrong_ident != fb.Invalid { os.exit(1i32) }

    // 2: every field of the Python buffer.
    check_monster(buf, 2i32)

    // 3: field_offset answers the absolute position of hp and 0 for mana.
    let (hp_at, hp_at_error) = fb.field_offset(buf, root, 2usize)
    if hp_at_error != ok || hp_at == 0usize || buf[hp_at] != 44u8 || buf[hp_at + 1usize] != 1u8 { os.exit(3i32) }
    let (mana_at, mana_at_error) = fb.field_offset(buf, root, 1usize)
    if mana_at_error != ok || mana_at != 0usize { os.exit(3i32) }

    // 4: a truncated buffer answers Invalid, never a trap.
    let cut = buf[..40usize]
    let (cut_root, cut_root_error) = fb.root(cut)
    if cut_root_error != ok || cut_root != 32usize { os.exit(4i32) }
    let (_, cut_name_error) = fb.get_string(cut, cut_root, 3usize)
    if cut_name_error != fb.Invalid { os.exit(4i32) }
    let (_, cut_vector_error) = fb.get_vector(cut, cut_root, 7usize)
    if cut_vector_error != fb.Invalid { os.exit(4i32) }
    let (_, short_root_error) = fb.root(buf[..3usize])
    if short_root_error != fb.Invalid { os.exit(4i32) }
    let (_, bad_table_error) = fb.field_offset(buf, 2usize, 0usize)
    if bad_table_error != fb.Invalid { os.exit(4i32) }

    // 5: a vector index out of range answers Invalid.
    let (weapons, weapons_error) = fb.get_vector(buf, root, 7usize)
    if weapons_error != ok { os.exit(5i32) }
    let (_, out_of_range) = fb.vector_table_at(buf, weapons, 2usize)
    if out_of_range != fb.Invalid { os.exit(5i32) }
    let (_, string_out_of_range) = fb.vector_string_at(buf, weapons, 2usize)
    if string_out_of_range != fb.Invalid { os.exit(5i32) }
    let (inv, inv_error) = fb.get_vector(buf, root, 5usize)
    if inv_error != ok { os.exit(5i32) }
    let (_, scalar_out_of_range) = fb.vector_at[u8](buf, inv, 10usize)
    if scalar_out_of_range != fb.Invalid { os.exit(5i32) }
    let (ninth, ninth_error) = fb.vector_at[u8](buf, inv, 9usize)
    if ninth_error != ok || ninth != 9u8 { os.exit(5i32) }

    // 6: the Neper builder's Monster reads back to the same values.
    var storage: [256]u8 = zero
    let (built, build_error) = build_monster(storage[..])
    if build_error != ok || built.len == 0usize || built.len % 4usize != 0usize { os.exit(6i32) }
    check_monster(built, 7i32)

    // 8: a builder that runs out of room answers TooSmall.
    var tiny: [8]u8 = zero
    var tb = fb.builder(tiny[..])
    let (_, tiny_error) = fb.create_string(&tb, "too long for eight bytes")
    if tiny_error != fb.TooSmall { os.exit(8i32) }

    try io.print("fmt flatbuffers ok\n")
    ret ok
}
