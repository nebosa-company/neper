// Deterministic target data layout used by lowering and ABI classification.

use check

error InvalidType
error Overflow

type Info = struct {
    size: usize,
    alignment: usize,
}

type Field = struct {
    offset: usize,
    ty: check.Type,
}

fn align_up(value: usize, alignment: usize) -> (usize, err) {
    if alignment == 0usize { ret (0usize, InvalidType) }
    let remainder = value % alignment
    if remainder == 0usize { ret (value, ok) }
    let padding = alignment - remainder
    if value > 18446744073709551615usize - padding { ret (0usize, Overflow) }
    ret (value + padding, ok)
}

fn scalar_size(ty: check.Type) -> usize {
    if ty.kind == .Bool { ret 1usize }
    if ty.kind == .Err { ret 4usize }
    // By the name's shape (D326), as `check.integer_width` decides: two letters are a
    // byte, `bf16` and a `1` in the middle are two, a `3` is four, and the rest --
    // `i64`, `u64`, `f64`, `isize`, `usize` -- are eight.
    if ty.kind == .Integer || ty.kind == .Float {
        if ty.name.len == 2usize { ret 1usize }
        if ty.name.len == 4usize { ret 2usize }
        if ty.name.len == 3usize {
            if ty.name[1usize] == 49u8 { ret 2usize }
            if ty.name[1usize] == 51u8 { ret 4usize }
        }
        ret 8usize
    }
    ret 0usize
}

fn aggregate_index(c: *check.Checker, ty: check.Type) -> (usize, bool) {
    if (ty.kind == .Named || ty.kind == .Tag) && ty.has_element && ty.element < c.aggregate_count { ret (ty.element, true) }
    if ty.kind != .Named && ty.kind != .Tag { ret (0usize, false) }
    // By the checker's (module, name) index (D306); this scanned every aggregate for
    // every type a layout was asked about.
    let (found_at, found) = check.find_aggregate(c, ty.module_index, ty.name)
    ret (found_at, found)
}

// `@reorder` (D239): the fields sorted by descending alignment, declaration order
// breaking ties, so the layout is one deterministic function of the type rather than a
// freedom the compiler may spend differently between versions. Placed one alignment
// class at a time, highest first; the answer is the running size and alignment before
// the tail rounding, plus the offset of `name` when the struct declares it.
// ponytail: one pass per distinct alignment, which is at most a handful for a struct.
fn reordered_struct(c: *check.Checker, aggregate: check.Aggregate, name: str, depth: usize) -> (Info, Field, bool, err) {
    var invalid: Info = zero
    var wanted: Field = zero
    var size = 0usize
    var alignment = 1usize
    var found = false
    var placed = 0usize
    var threshold = 18446744073709551615usize
    while placed < aggregate.field_count {
        var class = 0usize
        var at = 0usize
        while at < aggregate.field_count {
            let field_index = aggregate.first_field + at
            if field_index >= c.aggregate_field_count { ret (invalid, wanted, false, InvalidType) }
            let (info, info_error) = type_info_depth(c, c.aggregate_fields[field_index].ty, depth + 1usize)
            if info_error != ok { ret (invalid, wanted, false, info_error) }
            if info.alignment < threshold && info.alignment > class { class = info.alignment }
            at += 1usize
        }
        if class == 0usize { ret (invalid, wanted, false, InvalidType) }
        at = 0usize
        while at < aggregate.field_count {
            let member = c.aggregate_fields[aggregate.first_field + at]
            let (info, info_error) = type_info_depth(c, member.ty, depth + 1usize)
            if info_error != ok { ret (invalid, wanted, false, info_error) }
            if info.alignment == class {
                let (start, start_error) = align_up(size, class)
                if start_error != ok || start > 18446744073709551615usize - info.size { ret (invalid, wanted, false, Overflow) }
                if check.same(member.name, name) {
                    wanted = Field { offset: start, ty: member.ty }
                    found = true
                }
                size = start + info.size
                if class > alignment { alignment = class }
                placed += 1usize
            }
            at += 1usize
        }
        threshold = class
    }
    ret (Info { size: size, alignment: alignment }, wanted, found, ok)
}

fn type_info_depth(c: *check.Checker, ty: check.Type, depth: usize) -> (Info, err) {
    var invalid: Info = zero
    let scalar = scalar_size(ty)
    if scalar != 0usize { ret (Info { size: scalar, alignment: scalar }, ok) }
    if ty.kind == .Pointer || ty.kind == .Function { ret (Info { size: 8usize, alignment: 8usize }, ok) }
    if ty.kind == .String || ty.kind == .Slice { ret (Info { size: 16usize, alignment: 8usize }, ok) }
    if ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count || !ty.has_length { ret (invalid, InvalidType) }
        let (element, element_error) = type_info_depth(c, c.types[ty.element], depth + 1usize)
        if element_error != ok { ret (invalid, element_error) }
        if element.size != 0usize && ty.array_length > 18446744073709551615usize / element.size { ret (invalid, Overflow) }
        ret (Info { size: ty.array_length * element.size, alignment: element.alignment }, ok)
    }
    let (index, found) = aggregate_index(c, ty)
    if !found || depth > c.aggregate_count { ret (invalid, InvalidType) }
    let aggregate = c.aggregates[index]
    if aggregate.kind == .Enum || ty.kind == .Tag {
        let (backing, backing_error) = type_info_depth(c, aggregate.backing_type, depth + 1usize)
        ret (backing, backing_error)
    }
    if aggregate.kind == .Struct && aggregate.reorder {
        let (packed, ignored_field, ignored_found, packed_error) = reordered_struct(c, aggregate, "", depth)
        if packed_error != ok { ret (invalid, packed_error) }
        var packed_size = packed.size
        if aggregate.field_count == 0usize { packed_size = 1usize }
        let (packed_rounded, packed_rounded_error) = align_up(packed_size, packed.alignment)
        if packed_rounded_error != ok { ret (invalid, packed_rounded_error) }
        ret (Info { size: packed_rounded, alignment: packed.alignment }, ok)
    }
    var size = 0usize
    var alignment = 1usize
    var payload_size = 0usize
    var payload_alignment = 1usize
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index >= c.aggregate_field_count { ret (invalid, InvalidType) }
        let member = c.aggregate_fields[field_index]
        if aggregate.kind != .TaggedUnion || member.ty.kind != .Void {
            let (field_info, field_error) = type_info_depth(c, member.ty, depth + 1usize)
            if field_error != ok { ret (invalid, field_error) }
            if aggregate.kind == .Struct {
                let (field_start, field_start_error) = align_up(size, field_info.alignment)
                if field_start_error != ok || field_start > 18446744073709551615usize - field_info.size { ret (invalid, Overflow) }
                size = field_start + field_info.size
                if field_info.alignment > alignment { alignment = field_info.alignment }
            } else {
                if field_info.size > payload_size { payload_size = field_info.size }
                if field_info.alignment > payload_alignment { payload_alignment = field_info.alignment }
            }
        }
        field_at += 1usize
    }
    if aggregate.kind == .Struct {
        if aggregate.field_count == 0usize { size = 1usize }
        // Section 4: a `Vec[T, N]` or `Mask[T, N]` is aligned to its own width.
        if c.has_simd && aggregate.module_index == c.simd_module && (check.same(aggregate.name, "Vec") || check.same(aggregate.name, "Mask")) { alignment = size }
        let (rounded, rounded_error) = align_up(size, alignment)
        if rounded_error != ok { ret (invalid, rounded_error) }
        ret (Info { size: rounded, alignment: alignment }, ok)
    }
    if aggregate.kind == .Union {
        let (rounded, rounded_error) = align_up(payload_size, payload_alignment)
        if rounded_error != ok { ret (invalid, rounded_error) }
        ret (Info { size: rounded, alignment: payload_alignment }, ok)
    }
    if aggregate.kind == .TaggedUnion {
        let (tag, tag_error) = type_info_depth(c, aggregate.backing_type, depth + 1usize)
        if tag_error != ok { ret (invalid, tag_error) }
        let (payload_offset, payload_offset_error) = align_up(tag.size, payload_alignment)
        if payload_offset_error != ok || payload_offset > 18446744073709551615usize - payload_size { ret (invalid, Overflow) }
        if payload_alignment > tag.alignment { alignment = payload_alignment } else { alignment = tag.alignment }
        let (rounded, rounded_error) = align_up(payload_offset + payload_size, alignment)
        if rounded_error != ok { ret (invalid, rounded_error) }
        ret (Info { size: rounded, alignment: alignment }, ok)
    }
    ret (invalid, InvalidType)
}

fn type_info(c: *check.Checker, ty: check.Type) -> (Info, err) {
    let (info, info_error) = type_info_depth(c, ty, 0usize)
    ret (info, info_error)
}

fn field(c: *check.Checker, ty: check.Type, name: str) -> (Field, err) {
    var invalid: Field = zero
    var subject = ty
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret (invalid, InvalidType) }
        subject = c.types[subject.element]
    }
    let (index, found) = aggregate_index(c, subject)
    if !found { ret (invalid, InvalidType) }
    let aggregate = c.aggregates[index]
    if check.same(name, "tag") && aggregate.kind == .TaggedUnion { ret (Field { offset: 0usize, ty: aggregate.backing_type }, ok) }
    if aggregate.kind == .Struct && aggregate.reorder {
        let (ignored_info, wanted, found_wanted, packed_error) = reordered_struct(c, aggregate, name, 0usize)
        if packed_error != ok { ret (invalid, packed_error) }
        if !found_wanted { ret (invalid, InvalidType) }
        ret (wanted, ok)
    }
    var offset = 0usize
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index >= c.aggregate_field_count { ret (invalid, InvalidType) }
        let candidate = c.aggregate_fields[field_index]
        if aggregate.kind == .Struct {
            let (candidate_info, candidate_info_error) = type_info(c, candidate.ty)
            if candidate_info_error != ok { ret (invalid, candidate_info_error) }
            let (field_offset, field_offset_error) = align_up(offset, candidate_info.alignment)
            if field_offset_error != ok { ret (invalid, field_offset_error) }
            offset = field_offset
            if check.same(candidate.name, name) { ret (Field { offset: offset, ty: candidate.ty }, ok) }
            if offset > 18446744073709551615usize - candidate_info.size { ret (invalid, Overflow) }
            offset += candidate_info.size
        } else {
            if check.same(candidate.name, name) {
                if aggregate.kind == .Union { ret (Field { offset: 0usize, ty: candidate.ty }, ok) }
                if aggregate.kind == .TaggedUnion {
                    let (tag, tag_error) = type_info(c, aggregate.backing_type)
                    if tag_error != ok { ret (invalid, tag_error) }
                    var payload_alignment = 1usize
                    var payload_at = 0usize
                    while payload_at < aggregate.field_count {
                        let payload = c.aggregate_fields[aggregate.first_field + payload_at]
                        if payload.ty.kind != .Void {
                            let (payload_info, payload_error) = type_info(c, payload.ty)
                            if payload_error != ok { ret (invalid, payload_error) }
                            if payload_info.alignment > payload_alignment { payload_alignment = payload_info.alignment }
                        }
                        payload_at += 1usize
                    }
                    let (payload_offset, payload_offset_error) = align_up(tag.size, payload_alignment)
                    if payload_offset_error != ok { ret (invalid, payload_offset_error) }
                    ret (Field { offset: payload_offset, ty: candidate.ty }, ok)
                }
            }
        }
        field_at += 1usize
    }
    ret (invalid, InvalidType)
}
