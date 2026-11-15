// e.fmt.xls against readxl on the .xls workbooks in tests/data/xls (clippy, datasets, deaths,
// geometry, type-me): every cell of every sheet, its kind, number or text, and the size of each
// sheet's table. tests/oracle/xls.json comes from `Rscript scripts/r_oracle/generate.R xls`; the
// layout is at the top of scripts/r_oracle/groups/xls.R.

use e.fmt.xls as xls
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn kind_code(k: u8) -> f64 {
    if k == xls.TEXT { ret 1.0f64 }
    if k == xls.NUMBER { ret 2.0f64 }
    if k == xls.BOOL { ret 3.0f64 }
    if k == xls.DATE { ret 4.0f64 }
    ret 0.0f64
}

fn sheet_of(books: []const xls.Workbook, x: []const f64) -> *const xls.Sheet {
    ret &books[usize(x[0usize])].sheets[usize(x[1usize])]
}

// The number of rows and columns readxl's table from A1 has: the last cell that holds a value.
fn extent(s: *const xls.Sheet, columns: bool) -> f64 {
    var best = 0u32
    var i = 0usize
    while i < s.cells.len {
        let c = s.cells[i]
        if c.kind != xls.BLANK && c.kind != xls.ERROR {
            var v = c.row + 1u32
            if columns { v = c.col + 1u32 }
            if v > best { best = v }
        }
        i += 1usize
    }
    ret f64(best)
}

// The merged ranges of a sheet sorted by first row, then first column.
fn merged_order(a: *mem.Arena, s: *const xls.Sheet) -> []usize {
    let n = s.merged.len / 4usize
    let (o, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize && (s.merged[4usize * o[j - 1usize]] > s.merged[4usize * i] || (s.merged[4usize * o[j - 1usize]] == s.merged[4usize * i] && s.merged[4usize * o[j - 1usize] + 2usize] > s.merged[4usize * i + 2usize])) {
            o[j] = o[j - 1usize]
            j -= 1usize
        }
        o[j] = i
        i += 1usize
    }
    ret o[0usize..n]
}

fn answer(a: *mem.Arena, books: []const xls.Workbook, c: *const oracle.Case) -> f64 {
    let x = c.args
    let s = sheet_of(books, x)
    if str.eq(c.name, "xls_nmerged") { ret f64(s.merged.len / 4usize) }
    if str.eq(c.name, "xls_merged") {
        let o = merged_order(a, s)
        ret f64(s.merged[4usize * o[usize(x[2usize])] + usize(x[3usize])])
    }
    if str.eq(c.name, "xls_rows") { ret extent(s, false) }
    if str.eq(c.name, "xls_cols") { ret extent(s, true) }
    let cell = xls.cell_at(s, u32(x[2usize]), u32(x[3usize]))
    if str.eq(c.name, "xls_kind") { ret kind_code(cell.kind) }
    if cell.kind == xls.DATE { ret xls.date_serial(&books[usize(x[0usize])], cell.num) }
    ret cell.num
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xls.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (books, be) = mem.alloc[xls.Workbook](a, 9usize)
    if be != ok { os.exit(5) }
    var f = 0usize
    while f < 9usize {
        var name = "clippy"
        if f == 1usize { name = "datasets" }
        if f == 2usize { name = "deaths" }
        if f == 3usize { name = "geometry" }
        if f == 4usize { name = "type-me" }
        if f == 5usize { name = "biff5" }
        if f == 6usize { name = "biff5_mini" }
        if f == 7usize { name = "biff8_sst_continue" }
        if f == 8usize { name = "difat" }
        let (path_b, pe) = str.builder(a, 64usize)
        if pe != ok { os.exit(5) }
        var pb = path_b
        let _ = str.push(&pb, "tests/data/xls/")
        let _ = str.push(&pb, name)
        let _ = str.push(&pb, ".xls")
        let (bytes, re) = fs.read_file(a, str.done(&pb), 16777216usize)
        if re != ok { os.exit(6) }
        let (wb, we) = xls.read(a, bytes)
        if we != ok { os.exit(7) }
        books[f] = wb
        f += 1usize
    }
    // datasets.xls with its three BOUNDSHEET state bytes set, and with its first globals record turned into FILEPASS
    let (ds, dse) = fs.read_file(a, "tests/data/xls/datasets.xls", 16777216usize)
    if dse != ok { os.exit(6) }
    var hid = ds
    hid[11528usize] = 0u8
    hid[11546usize] = 1u8
    hid[11566usize] = 2u8
    let (hidden_book, hbe) = xls.read(a, hid)
    if hbe != ok { os.exit(8) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var good = false
        if str.eq(c.name, "xls_text") {
            let cell = xls.cell_at(sheet_of(books, c.args), u32(c.args[2usize]), u32(c.args[3usize]))
            good = oracle.agrees_text(cell.text, c)
        } else if str.eq(c.name, "xls_hidden_name") {
            good = oracle.agrees_text(hidden_book.sheets[usize(c.args[0usize])].name, c)
        } else if str.eq(c.name, "xls_hidden_n") {
            good = oracle.agrees(f64(hidden_book.sheets.len), c)
        } else if str.eq(c.name, "xls_hidden_state") {
            good = oracle.agrees(f64(hidden_book.sheets[usize(c.args[0usize])].hidden), c)
        } else if str.eq(c.name, "xls_encrypted") {
            var enc = ds
            enc[532usize] = 47u8
            enc[536usize] = u8(c.args[0usize])
            let (_w, ee) = xls.read(a, enc)
            var refused = 0.0f64
            if ee == xls.Encrypted { refused = 1.0f64 }
            good = oracle.agrees(refused, c)
        } else {
            good = oracle.agrees(answer(a, books, c), c)
        }
        if !good {
            failures += 1usize
            if failures <= 20usize {
                if str.eq(c.name, "xls_text") {
                    let cell = xls.cell_at(sheet_of(books, c.args), u32(c.args[2usize]), u32(c.args[3usize]))
                    let _ = io.print(c.name)
                    let _ = io.print(" want ")
                    let _ = io.print(c.text)
                    let _ = io.print(" got ")
                    let _ = io.print(cell.text)
                    let _ = io.print("\n")
                } else {
                    let _ = io.print(oracle.describe(a, c, answer(a, books, c)))
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
