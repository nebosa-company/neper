// A type's rename (D515, H17, H29): the record type of `deep` is spelled through
// the alias `d` in an annotation, a literal and a second annotation here, and bare
// in `deep.e` as a return type and a literal; the plan renames every one and the
// declaration, and the renamed program builds and exits the same.
use deep as d
use e.os

fn total(r: d.Rec) -> usize {
    ret r.left + r.right
}

fn main() -> err {
    let r = d.Rec { left: 3usize, right: 5usize }
    var s: d.Rec = zero
    s.left = total(r)
    os.exit(i32(s.left))
    ret ok
}
