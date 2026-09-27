// Deterministic target data layout used by lowering and ABI classification. The rules
// live in the checker (D1569), whose comptime interpreter lays its memory out the same
// way; these forward to them and keep this module's errors.

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

fn layout_error(failure: err) -> err {
    if failure == check.InvalidType { ret InvalidType }
    if failure == check.LayoutOverflow { ret Overflow }
    ret failure
}

fn align_up(value: usize, alignment: usize) -> (usize, err) {
    let (aligned, aligned_error) = check.layout_align_up(value, alignment)
    ret (aligned, layout_error(aligned_error))
}

fn scalar_size(ty: check.Type) -> usize {
    ret check.layout_scalar_size(ty)
}

fn aggregate_index(c: *check.Checker, ty: check.Type) -> (usize, bool) {
    let (index, found) = check.layout_aggregate_index(c, ty)
    ret (index, found)
}

fn type_info_depth(c: *check.Checker, ty: check.Type, depth: usize) -> (Info, err) {
    let (info, info_error) = check.layout_type_info_depth(c, ty, depth)
    ret (Info { size: info.size, alignment: info.alignment }, layout_error(info_error))
}

fn type_info(c: *check.Checker, ty: check.Type) -> (Info, err) {
    let (info, info_error) = check.layout_type_info(c, ty)
    ret (Info { size: info.size, alignment: info.alignment }, layout_error(info_error))
}

fn field(c: *check.Checker, ty: check.Type, name: str) -> (Field, err) {
    let (found, found_error) = check.layout_field(c, ty, name)
    ret (Field { offset: found.offset, ty: found.ty }, layout_error(found_error))
}
