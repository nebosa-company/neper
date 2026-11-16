// e.time.lubridate against lubridate and timeDate: Easter, month arithmetic, quarter, semester, decimal_date,
// epiweek, isoweek, floor_date and ceiling_date. tests/oracle/lubridate.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lubridate`; the layout is at the top of
// scripts/r_oracle/groups/lubridate.R.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.time.lubridate as lb

fn unit_of(name: str) -> u8 {
    if str.ends_with(name, "week") { ret 0u8 }
    if str.ends_with(name, "month") { ret 1u8 }
    if str.ends_with(name, "quarter") { ret 2u8 }
    if str.ends_with(name, "semester") { ret 3u8 }
    ret 4u8
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = i64(x[0usize])
    if str.eq(c.name, "easter") { ret f64(lb.easter(n)) }
    if str.eq(c.name, "madd") { ret f64(lb.add_months(n, i64(x[1usize]), u8(x[2usize]))) }
    if str.eq(c.name, "quarter") { ret f64(lb.quarter(n)) }
    if str.eq(c.name, "semester") { ret f64(lb.semester(n)) }
    if str.eq(c.name, "decimal") { ret lb.decimal_date(n) }
    if str.eq(c.name, "epiweek") { ret f64(lb.epiweek(n)) }
    if str.eq(c.name, "epiyear") { ret f64(lb.epiyear(n)) }
    if str.eq(c.name, "isoweek") { ret f64(lb.isoweek(n)) }
    if str.eq(c.name, "isoyear") { ret f64(lb.isoyear(n)) }
    if str.starts_with(c.name, "floor_") { ret f64(lb.floor_date(n, unit_of(c.name), i64(x[1usize]))) }
    ret f64(lb.ceiling_date(n, unit_of(c.name), i64(x[1usize])))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lubridate.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
