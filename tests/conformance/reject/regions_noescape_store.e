// A no-escape input stored through another parameter (D1565, H02): `o.name` is
// storage the caller keeps, so the store lets `p` outlive the call as surely as a
// global would, and the contract is E-SAFETY-0020.
type Holder = struct { name: str }

@noescape("p")
fn keep(o: *Holder, p: str) {
    o.name = p
}

fn main() {}
