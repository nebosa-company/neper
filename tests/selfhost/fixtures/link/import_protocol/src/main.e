// An `@import` extern called from a supplied protocol binds its library from its own
// declaration in every module that calls it (D1664). `direct` is lowered first at
// `-j 1`; `seq` and `tagged` reach the externs only through `T.cmp` and `T.hash`.
use direct
use seq
use tagged

error DirectFailed
error SequenceFailed
error TaggedFailed

fn main() -> err {
    if !direct.run() { ret DirectFailed }
    if !seq.run() { ret SequenceFailed }
    if !tagged.run() { ret TaggedFailed }
    ret ok
}
