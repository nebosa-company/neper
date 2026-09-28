// As m1, with constants of its own (D1670).

use e.io
use e.mem
use e.str
use tmpl

error Odd

type Cell = struct { v: i64, tag: u8 }

fn named(a: *mem.Arena) -> (str, err) {
    var (b, builder_error) = str.builder(a, 32usize)
    if builder_error != ok { ret ("", builder_error) }
    let held = &b
    let push_error = str.push_err(held, Odd)
    if push_error != ok { ret ("", push_error) }
    ret (str.done(held), ok)
}

fn run(a: *mem.Arena) -> (i64, err) {
    let wide = tmpl.wrap[i64](6i64, 7i64) + tmpl.pick[i64](60i64, 0i64, true)
    let narrow = tmpl.wrap[u8](6u8, 12u8)
    let cell = tmpl.wrap[Cell](Cell { v: 600i64, tag: 6u8 }, Cell { v: 601i64, tag: 7u8 })
    let (name, name_error) = named(a)
    if name_error != ok { ret (0i64, name_error) }
    let print_error = io.printf["m6 {} {} {} {}\n"](wide, narrow, cell.v, name)
    if print_error != ok { ret (0i64, print_error) }
    ret (wide + i64(narrow) + cell.v + i64(cell.tag) + i64(name.len), ok)
}
