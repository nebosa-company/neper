// A lowering worker rolls its builder back to the module's mark once the module's artifact
// is written (D1664), and the writer's spans over the builder's rows go with it. At `-j 1`
// one worker lowers these four modules in order, and each lowers at least as many NIR
// functions as the one before: without the spans cleared, the writer would see no shrink
// and leave the module's first rows out of its artifact. The image is the same at `-j 1`,
// at `-j 3 --perturb` and linked from `emit-em-all`'s artifacts, and exits 0.
use m1
use m2
use m3

fn main() -> i64 {
    if m1.step(0i64) != 3i64 { ret 1i64 }
    if m2.check() != 0i64 { ret 2i64 }
    ret m3.check()
}
