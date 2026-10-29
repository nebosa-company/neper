// `e.fmt.xlsx.book` must not write raw malformed bytes into UTF-8 XML parts.
use e.os
use e.mem
use e.fmt.xlsx as xlsx
use e.fmt.xlsx.book as book

fn main(a: *mem.Arena, args: []str) -> err {
    let bad_cells = [1]xlsx.Cell{ xlsx.text_cell("\x80") }
    let bad_grid = [1][]const xlsx.Cell{ bad_cells[0..] }
    let bad_text_sheets = [1]xlsx.Sheet{ xlsx.Sheet { name: "Sheet", grid: bad_grid[0..] } }
    let (_, bad_text_error) = book.encode(a, bad_text_sheets[0..], zero)
    if bad_text_error != book.BadText { os.exit(1) }

    let valid_cells = [1]xlsx.Cell{ xlsx.number_cell(1.0) }
    let valid_grid = [1][]const xlsx.Cell{ valid_cells[0..] }
    let bad_name_sheets = [1]xlsx.Sheet{ xlsx.Sheet { name: "\x80", grid: valid_grid[0..] } }
    let (_, bad_name_error) = book.encode(a, bad_name_sheets[0..], zero)
    if bad_name_error != book.BadSheetName { os.exit(2) }
    ret ok
}
