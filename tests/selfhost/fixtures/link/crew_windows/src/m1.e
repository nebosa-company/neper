// One of six modules that append the same kinds of rows to their worker's parameter
// and return tables (D1670): instances of `tmpl.pick` and `tmpl.wrap` at `i64`, `u8`
// and a struct of its own, a `printf` of its own (a formatter and a sink), and a
// `push_err` of its own, through a pointer to a local builder used after it is taken.

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
    let wide = tmpl.wrap[i64](1i64, 2i64) + tmpl.pick[i64](3i64, 4i64, true)
    let narrow = tmpl.wrap[u8](5u8, 6u8)
    let cell = tmpl.wrap[Cell](Cell { v: 7i64, tag: 1u8 }, Cell { v: 8i64, tag: 2u8 })
    let (name, name_error) = named(a)
    if name_error != ok { ret (0i64, name_error) }
    let print_error = io.printf["m1 {} {} {} {}\n"](wide, narrow, cell.v, name)
    if print_error != ok { ret (0i64, print_error) }
    ret (wide + i64(narrow) + cell.v + i64(cell.tag) + i64(name.len), ok)
}
