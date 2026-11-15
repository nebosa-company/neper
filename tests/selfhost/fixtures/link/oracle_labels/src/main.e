// e.text.labels against R's scales: number (every option, scale cuts), comma, percent,
// dollar, bytes, ordinal, scientific and label_date/label_time in UTC.
// tests/oracle/labels.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R labels`;
// the case layouts are written at the top of scripts/r_oracle/groups/labels.R.

use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.labels as labels

fn join(a: *mem.Arena, parts: []const str) -> []u8 {
    var total = 0usize
    var i = 0usize
    while i < parts.len {
        total += parts[i].len + 1usize
        i += 1usize
    }
    let (buf, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { os.exit(5) }
    var at = 0usize
    i = 0usize
    while i < parts.len {
        if i > 0usize {
            buf[at] = 1u8
            at += 1usize
        }
        var k = 0usize
        while k < parts[i].len {
            buf[at + k] = parts[i][k]
            k += 1usize
        }
        at += parts[i].len
        i += 1usize
    }
    ret buf[0usize..at]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> []u8 {
    let x = c.args
    let s = c.inputs
    if str.eq(c.name, "number") {
        var o = labels.defaults()
        o.accuracy = x[0usize]
        o.scale = x[1usize]
        o.positive = u8(x[2usize])
        o.negative = u8(x[3usize])
        o.prefix = s[0usize]
        o.suffix = s[1usize]
        o.big_mark = s[2usize]
        o.decimal_mark = s[3usize]
        let kind = u8(x[4usize])
        if kind >= 1u8 && kind <= 3u8 {
            let (cuts, ce) = labels.scale_cuts(a, kind - 1u8, false)
            if ce != ok { os.exit(5) }
            o.cuts = cuts
        }
        if kind == 4u8 {
            let (cuts, ce) = labels.cut_si(a, s[4usize])
            if ce != ok { os.exit(5) }
            o.cuts = cuts
        }
        let n = usize(x[5usize])
        let (r, e) = labels.number(a, x[6usize..6usize + n], &o)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "comma") {
        var o = labels.comma_options()
        o.accuracy = x[0usize]
        let n = usize(x[1usize])
        let (r, e) = labels.number(a, x[2usize..2usize + n], &o)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "percent") {
        var o = labels.percent_options()
        o.accuracy = x[0usize]
        let n = usize(x[1usize])
        let (r, e) = labels.number(a, x[2usize..2usize + n], &o)
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "dollar") {
        var o = labels.dollar_options()
        o.accuracy = x[0usize]
        let n = usize(x[2usize])
        let (r, e) = labels.dollar(a, x[3usize..3usize + n], &o, x[1usize])
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "bytes") {
        let n = usize(x[2usize])
        let (r, e) = labels.bytes(a, x[3usize..3usize + n], s[0usize], x[0usize], x[1usize])
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "ordinal") {
        let n = usize(x[0usize])
        let (r, e) = labels.ordinal(a, x[1usize..1usize + n], s[0usize], s[1usize], s[2usize])
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    if str.eq(c.name, "scientific") {
        let n = usize(x[2usize])
        let (r, e) = labels.scientific(a, x[3usize..3usize + n], i64(x[0usize]), x[1usize], s[0usize], s[1usize], s[2usize])
        if e != ok { os.exit(7) }
        ret join(a, r)
    }
    let n = usize(x[0usize])
    var moments = x[1usize..1usize + n]
    if str.eq(c.name, "day") {
        let (days, de) = mem.alloc[f64](a, n)
        if de != ok { os.exit(5) }
        var k = 0usize
        while k < n {
            days[k] = math.floor[f64](moments[k] / 86400.0f64) * 86400.0f64
            k += 1usize
        }
        moments = days
    }
    let (r, e) = labels.date_time(a, moments, s[0usize])
    if e != ok { os.exit(7) }
    ret join(a, r)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/labels.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(c.name)
                let _ = io.print(" args=")
                var k = 0usize
                while k < c.args.len && k < 14usize {
                    let (initial, be) = str.builder(a, 32usize)
                    if be != ok { os.exit(5) }
                    var b = initial
                    let _ = str.push_f64(&b, c.args[k])
                    let _ = str.push_byte(&b, 32u8)
                    let _ = io.print(str.done(&b))
                    k += 1usize
                }
                let _ = io.print("\n got [")
                let _ = io.print(text)
                let _ = io.print("]\n  R  [")
                let _ = io.print(c.text)
                let _ = io.print("]\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
