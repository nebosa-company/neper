// `e.gfx.hclpal_tables`: the generated colorspace data read as text. 97 palette rows of 12
// fields, 19 diverging-x rows of 16, and three CVD matrix sets of 11 matrices of 9 numbers,
// the last of them equal to the numeric tables in `e.gfx.cvd_table`; one named row is
// compared whole. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.gfx.hclpal_tables as tab
use e.gfx.cvd_table as cvd

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The rows of `text` split on `sep`, each counted for its own fields split on `field`.
// Answers the row count, or 0 when a row has other than `fields` fields.
fn rows_of(text: str, sep: str, field: str, fields: usize) -> usize {
    let (rows, re) = str.split(text, sep)
    if re != ok { ret 0usize }
    var it = rows
    var n = 0usize
    while true {
        let (row, more) = str.split_next(&it)
        if !more { break }
        let (cells, ce) = str.split(row, field)
        if ce != ok { ret 0usize }
        var ci = cells
        var count = 0usize
        while true {
            let (cell, cm) = str.split_next(&ci)
            if !cm { break }
            if cell.len == 0usize { ret 0usize }
            count += 1usize
        }
        if count != fields { ret 0usize }
        n += 1usize
    }
    ret n
}

fn near(a: f64, b: f64) -> bool {
    var d = a - b
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000000001f64
}

// Each matrix of `text` equals the same-numbered nine entries of `want`.
fn matches(text: str, want: [99]f64) -> bool {
    let (rows, re) = str.split(text, ";")
    if re != ok { ret false }
    var it = rows
    var m = 0usize
    while true {
        let (row, more) = str.split_next(&it)
        if !more { break }
        let (cells, ce) = str.split(row, ",")
        if ce != ok { ret false }
        var ci = cells
        var k = 0usize
        while true {
            let (cell, cm) = str.split_next(&ci)
            if !cm { break }
            let (v, pe) = str.parse_f64(cell)
            if pe != ok || !near(v, want[m * 9usize + k]) { ret false }
            k += 1usize
        }
        if k != 9usize { ret false }
        m += 1usize
    }
    ret m == 11usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    if rows_of(tab.palettes(), "\n", "|", 12usize) != 97usize { os.exit(1) }
    if rows_of(tab.divergingx_palettes(), "\n", "|", 16usize) != 19usize { os.exit(2) }
    let (h1, t1, found) = str.split_once(tab.palettes(), "Sequential (multi-hue)|Viridis|300|75|40|95|15|90|1|1.1000000000000001|-|1\n")
    if !found { os.exit(3) }
    let (h2, t2, tropic) = str.split_once(tab.divergingx_palettes(), "Tropic|195|-|325|70|-|-|55|95|-|1|-|-|-|-|-")
    if !tropic { os.exit(4) }
    if !matches(tab.deutan_matrices(), cvd.deut_table()) { os.exit(5) }
    if !matches(tab.protan_matrices(), cvd.prot_table()) { os.exit(6) }
    if !matches(tab.tritan_matrices(), cvd.trit_table()) { os.exit(7) }
    if tab.max_chroma_values().len == 0usize { os.exit(8) }
    ret ok
}
