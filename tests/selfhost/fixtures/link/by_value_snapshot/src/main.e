// A by-value aggregate is what the callee sees at the call (D358, H05): `f(x, &x)`
// where `f` writes through the pointer still reads the old `x` in its value
// parameter; the same through a slice the callee writes, and through a field of a
// struct whose address was taken. A copy is shallow: a pointer field inside the
// value still reaches the storage it points at. Built in both modes, so the
// inliner's view is the same.
use e.mem
use dep
use plat

error GenericSnapshot
error GenericMutation
error MultipleSnapshot
error MultipleMutation
error ExternalSnapshot
error ExternalMutation
error ModuleSnapshot
error ModuleMutation

type Big = struct { a: usize, b: usize, c: usize }
type Holder = struct { big: Big, target: *usize }
type Envelope[T: type] = struct { value: T, left: usize, right: usize }

fn overwrite(v: Big, p: *Big) -> usize {
    p.a = 99usize
    p.b = 99usize
    ret v.a + v.b
}

fn overwrite_envelope[T: type](v: Envelope[T], p: *Envelope[T]) -> usize {
    p.left = 0usize
    p.right = 0usize
    ret v.left * 10usize + v.right
}

fn overwrite_element(v: Big, items: []Big) -> usize {
    items[0usize].a = 77usize
    ret v.a
}

fn overwrite_multiple(v: Big, p: *Big) -> (Big, usize) {
    p.a = 0usize
    p.b = 0usize
    p.c = 0usize
    ret (v, v.a + v.b + v.c)
}

fn overwrite_external(v: Big, p: *Big) -> usize {
    plat.fill_zero(mem.cast[*u8](p), mem.size_of[Big]())
    ret read(v)
}

fn through_field(h: Holder, p: *Holder) -> usize {
    p.big.c = 55usize
    *h.target = 12usize
    ret h.big.c
}

fn fresh() -> Big {
    ret Big { a: 5usize, b: 6usize, c: 7usize }
}

fn read(v: Big) -> usize {
    ret v.a * 100usize + v.b * 10usize + v.c
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x = Big { a: 1usize, b: 2usize, c: 3usize }
    if overwrite(x, &x) != 3usize { ret mem.Exhausted }
    if x.a != 99usize { ret mem.Exhausted }
    var generic = Envelope[u8] { value: 8u8, left: 9usize, right: 10usize }
    let generic_before = overwrite_envelope[u8](generic, &generic)
    if generic_before != 100usize { ret GenericSnapshot }
    if generic.left != 0usize || generic.right != 0usize { ret GenericMutation }
    var multiple = Big { a: 11usize, b: 12usize, c: 13usize }
    let (multiple_before, multiple_sum) = overwrite_multiple(multiple, &multiple)
    if read(multiple_before) != 1233usize || multiple_sum != 36usize { ret MultipleSnapshot }
    if read(multiple) != 0usize { ret MultipleMutation }
    var external = Big { a: 14usize, b: 15usize, c: 16usize }
    if overwrite_external(external, &external) != 1566usize { ret ExternalSnapshot }
    if read(external) != 0usize { ret ExternalMutation }
    var module_value = dep.Value { a: 17usize, b: 18usize, c: 19usize }
    if dep.overwrite(module_value, &module_value) != 1899usize { ret ModuleSnapshot }
    if dep.read(module_value) != 0usize { ret ModuleMutation }
    let (items, items_error) = mem.alloc[Big](a, 1usize)
    if items_error != ok { ret items_error }
    items[0usize] = Big { a: 4usize, b: 0usize, c: 0usize }
    if overwrite_element(items[0usize], items) != 4usize { ret mem.Exhausted }
    if items[0usize].a != 77usize { ret mem.Exhausted }
    var counter = 0usize
    var h = Holder { big: Big { a: 0usize, b: 0usize, c: 9usize }, target: &counter }
    if through_field(h, &h) != 9usize { ret mem.Exhausted }
    if h.big.c != 55usize || counter != 12usize { ret mem.Exhausted }
    if read(fresh()) != 567usize { ret mem.Exhausted }
    ret ok
}
