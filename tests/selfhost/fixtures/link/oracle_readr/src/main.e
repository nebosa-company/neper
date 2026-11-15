// e.fmt.readr against R's readr: parse_number, parse_double, parse_integer, parse_logical,
// parse_date, parse_time, parse_datetime and read_delim's field splitting. tests/oracle/readr.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R readr`. A parser case holds
// the string (and format) in "in" and answers a number; a "delim" case answers the fields, rows
// joined by U+0001 and fields by U+0002.

use e.fmt.readr as readr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn byte_of(x: f64) -> u8 { ret u8(x) }

fn delim_text(a: *mem.Arena, c: *const oracle.Case) -> []u8 {
    let x = c.args
    let (fields, counts, e) = readr.read_delim(a, c.inputs[0usize], byte_of(x[0usize]), byte_of(x[1usize]), byte_of(x[2usize]), x[3usize] != 0.0f64, x[4usize] != 0.0f64, x[5usize] != 0.0f64, true)
    if e != ok { os.exit(7) }
    var total = 2usize
    var i = 0usize
    while i < fields.len {
        total += fields[i].len + 1usize
        i += 1usize
    }
    let (buf, be) = mem.alloc[u8](a, total + counts.len * (counts[0usize] + 2usize) + 2usize)
    if be != ok { os.exit(5) }
    var at = 0usize
    var fi = 0usize
    var r = 0usize
    while r < counts.len {
        if r > 0usize {
            buf[at] = 1u8
            at += 1usize
        }
        var k = 0usize
        while k < counts[0usize] {
            if k > 0usize {
                buf[at] = 2u8
                at += 1usize
            }
            if k < counts[r] {
                var j = 0usize
                while j < fields[fi + k].len {
                    buf[at + j] = fields[fi + k][j]
                    j += 1usize
                }
                at += fields[fi + k].len
            }
            k += 1usize
        }
        fi += counts[r]
        r += 1usize
    }
    ret buf[0usize..at]
}

fn vis(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c == 1u8 { c = 47u8 }
        if c == 2u8 { c = 126u8 }
        if c == 10u8 { c = 94u8 }
        buf[i] = c
        i += 1usize
    }
    ret buf[0usize..s.len]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "guess") { ret f64(readr.guess_parser(a, c.inputs, c.args[0usize] != 0.0f64)) }
    let s = c.inputs[0usize]
    if str.eq(c.name, "number") { ret readr.parse_number(s, byte_of(c.args[0usize]), byte_of(c.args[1usize])) }
    if str.eq(c.name, "double") { ret readr.parse_double(a, s, byte_of(c.args[0usize])) }
    if str.eq(c.name, "integer") { ret readr.parse_integer(s) }
    if str.eq(c.name, "logical") { ret readr.parse_logical(s) }
    if str.eq(c.name, "date") { ret readr.parse_date(s, c.inputs[1usize]) }
    if str.eq(c.name, "time") { ret readr.parse_time(s, c.inputs[1usize]) }
    ret readr.parse_datetime(s, c.inputs[1usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/readr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var ok_case = false
        if str.eq(c.name, "delim") {
            ok_case = oracle.agrees_text(delim_text(a, c), c)
        } else {
            ok_case = oracle.agrees(answer(a, c), c)
        }
        if !ok_case {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(c.name)
                let _ = io.print(" [")
                let _ = io.print(c.inputs[0usize])
                if c.inputs.len > 1usize {
                    let _ = io.print("|")
                    let _ = io.print(c.inputs[1usize])
                }
                let _ = io.print("] ")
                if str.eq(c.name, "delim") {
                    let _ = io.print(vis(a, c.text))
                    let _ = io.print(" <> ")
                    let _ = io.print(vis(a, delim_text(a, c)))
                    let _ = io.print(" args")
                    var q = 0usize
                    while q < c.args.len {
                        let (initial, be) = str.builder(a, 24usize)
                        if be != ok { os.exit(5) }
                        var nb = initial
                        let _ = str.push_i64(&nb, i64(c.args[q]))
                        let _ = io.print(" ")
                        let _ = io.print(str.done(&nb))
                        q += 1usize
                    }
                    let _ = io.print("\n")
                } else {
                    let _ = io.print(oracle.describe(a, c, answer(a, c)))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
