// The whole formula library in one registry (L027): the language forms LET and LETS and every function group,
// 279 functions with 330 names, the same set as appdor's default registry.

use e.algo.formula as f
use e.algo.formula.basic as basic
use e.algo.formula.convert as convert
use e.algo.formula.datetime as datetime
use e.algo.formula.math as fmath
use e.algo.formula.misc as misc
use e.algo.formula.text as ftext
use e.mem

// A registry holding LET, LETS and every function of the library.
fn build(a: *mem.Arena) -> (f.Registry, err) {
    let (made, e) = f.registry(a, 300usize)
    var r = made
    if e != ok { ret (r, e) }
    try f.register_core(&r, a)
    try basic.register(&r, a)
    try fmath.register(&r, a)
    try ftext.register(&r, a)
    try datetime.register(&r, a)
    try convert.register(&r, a)
    try misc.register(&r, a)
    ret (r, ok)
}
