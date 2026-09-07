// `push_err` writes an error's qualified name (spec section 7). It is the one `e.str`
// declaration a library cannot write: the answer is the merged error table, which is
// a property of the whole program, and a module sees one module at a time.

use e.mem
use e.os
use e.str

error Failed
error Boom

fn named(a: *mem.Arena, v: err) -> (str, err) {
    var (b, builder_error) = str.builder(a, 32usize)
    if builder_error != ok { ret ("", builder_error) }
    let push_error = str.push_err(&b, v)
    if push_error != ok { ret ("", push_error) }
    ret (str.done(&b), ok)
}

fn main(a: *mem.Arena) -> err {
    // An error of this module's own: the qualified name is the module name from
    // section 2 and the declared name.
    let (mine, mine_error) = named(a, Boom)
    if mine_error != ok { ret mine_error }
    if !str.eq(mine, "main.Boom") { ret Failed }

    // One from another module, reached through its `use` qualifier. Same table.
    let (theirs, theirs_error) = named(a, os.Failed)
    if theirs_error != ok { ret theirs_error }
    if !str.eq(theirs, "e.os.Failed") { ret Failed }

    // `ok` is zero and is not a declaration, so it is the one name that is not a
    // qualified one.
    let (fine, fine_error) = named(a, ok)
    if fine_error != ok { ret fine_error }
    if !str.eq(fine, "ok") { ret Failed }

    // Two errors declared in different modules with the same bare name are two
    // errors, and the qualified name is what tells them apart.
    let (library, library_error) = named(a, str.NotOnTop)
    if library_error != ok { ret library_error }
    if !str.eq(library, "e.str.NotOnTop") { ret Failed }
    ret ok
}
