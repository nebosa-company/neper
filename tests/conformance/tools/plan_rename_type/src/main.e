// A type's rename (D515, D517, H17, H29): the record type of `deep` is spelled
// through the alias `d` in an annotation, a literal and a second annotation here,
// and bare in `deep.e` as a return type and a literal; `sort.in_place` finds the
// type's `cmp` by the spelling `rec_cmp`, so the plan renames that function with
// the type, and the renamed program builds and exits the same.
use deep as d
use e.algo.sort
use e.os

fn total(r: d.Rec) -> usize {
    ret r.left + r.right
}

fn main() -> err {
    var items: [3]d.Rec = zero
    items[0usize] = d.Rec { left: 9usize, right: 1usize }
    items[1usize] = d.Rec { left: 2usize, right: 1usize }
    items[2usize] = d.make(5usize)
    sort.in_place[d.Rec](items[..])
    os.exit(i32(total(items[0usize]) + items[2usize].left))
    ret ok
}
