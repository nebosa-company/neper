// A matching selector cannot hide an invalid later arm in a non-forgiving
// selector list. This exercises matches directly, before select can visit a
// non-matching element first.
use e.fmt.css
use e.os

fn main() {
    var elements: [1]css.Element = zero
    elements[0usize] = css.Element { tag: "div", id: "", class_lo: 0u32, class_hi: 0u32, attr_lo: 0u32, attr_hi: 0u32, parent: css.NONE, prev: css.NONE }
    var no_classes: []const str = zero
    var no_attributes: []const css.Attribute = zero
    let d = css.Dom { elements: elements[0..], classes: no_classes, attributes: no_attributes }
    let (matched, match_error) = css.matches(&d, 0usize, "div, [")
    if matched || match_error != css.Invalid { os.exit(1) }
    os.exit(0)
}
