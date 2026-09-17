// A generated root (D512, H19): the map beside this file says the call below is
// regenerated from `main.input`, so a plan that would rename `deep.pick` at that
// site names the generator as the owner and where in the input the bytes begin,
// and `apply-plan` refuses the plan; the declaration in `deep.e` is a plain edit.
use deep
use e.os

fn main() -> err {
    os.exit(i32(deep.pick(3usize)))
    ret ok
}
