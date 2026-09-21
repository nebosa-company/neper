// `e.algo.exact_cover`: Algorithm X finds the unique cover of the
// six-by-seven matrix of the paper (rows B, D, F), reports an uncoverable
// matrix, and solves the classic Sudoku to its known solution while
// refusing a contradictory grid. Each check exits with its own code.

use e.algo.exact_cover
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the paper's matrix.
    var matrix: [42]u8 = zero
    let ones = "100100110010000001101001011001100110100001"
    var i = 0usize
    while i < 42usize {
        if ones[i] == 49u8 { matrix[i] = 1u8 }
        i += 1usize
    }
    var left: [64]u32 = zero
    var right: [64]u32 = zero
    var up: [64]u32 = zero
    var down: [64]u32 = zero
    var column: [64]u32 = zero
    var row: [64]u32 = zero
    var size: [8]u32 = zero
    let (l0, link_error) = exact_cover.links(matrix[..], 6usize, 7usize, left[..], right[..], up[..], down[..], column[..], row[..], size[..])
    if link_error != ok || l0.nodes != 7usize + 1usize + 17usize { os.exit(1i32) }
    var l = l0
    var chosen: [8]usize = zero
    let (count, solve_error) = exact_cover.solve(&l, chosen[..])
    if solve_error != ok || count != 3usize { os.exit(1i32) }
    // Rows in any order: sort by insertion.
    var picked: [3]usize = zero
    i = 0usize
    while i < 3usize {
        var k = i
        while k > 0usize && picked[k - 1usize] > chosen[i] {
            picked[k] = picked[k - 1usize]
            k -= 1usize
        }
        picked[k] = chosen[i]
        i += 1usize
    }
    if picked[0usize] != 1usize || picked[1usize] != 3usize || picked[2usize] != 5usize { os.exit(1i32) }
    // Removing row F leaves column 1 uncoverable.
    matrix[36usize] = 0u8
    matrix[41usize] = 0u8
    let (l1, link1_error) = exact_cover.links(matrix[..], 6usize, 7usize, left[..], right[..], up[..], down[..], column[..], row[..], size[..])
    if link1_error != ok { os.exit(1i32) }
    var m = l1
    let (_, unsolvable) = exact_cover.solve(&m, chosen[..])
    if unsolvable != exact_cover.Unsolvable { os.exit(1i32) }
    let (_, room) = exact_cover.links(matrix[..], 6usize, 7usize, left[..4usize], right[..], up[..], down[..], column[..], row[..], size[..])
    if room != exact_cover.TooSmall { os.exit(1i32) }

    // 2: Sudoku.
    let puzzle = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
    let solution = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    var grid: [81]u8 = zero
    i = 0usize
    while i < 81usize {
        grid[i] = puzzle[i] - 48u8
        i += 1usize
    }
    let (big, big_error) = mem.alloc[u8](a, 729usize * 324usize)
    if big_error != ok { ret big_error }
    let (links_left, e1) = mem.alloc[u32](a, 3300usize)
    if e1 != ok { ret e1 }
    let (links_right, e2) = mem.alloc[u32](a, 3300usize)
    if e2 != ok { ret e2 }
    let (links_up, e3) = mem.alloc[u32](a, 3300usize)
    if e3 != ok { ret e3 }
    let (links_down, e4) = mem.alloc[u32](a, 3300usize)
    if e4 != ok { ret e4 }
    let (links_column, e5) = mem.alloc[u32](a, 3300usize)
    if e5 != ok { ret e5 }
    let (links_row, e6) = mem.alloc[u32](a, 3300usize)
    if e6 != ok { ret e6 }
    var sizes: [325]u32 = zero
    var cells: [81]usize = zero
    if exact_cover.sudoku(grid[..], big, links_left, links_right, links_up, links_down, links_column, links_row, sizes[..], cells[..]) != ok { os.exit(2i32) }
    i = 0usize
    while i < 81usize {
        if grid[i] != solution[i] - 48u8 { os.exit(2i32) }
        i += 1usize
    }
    // Two fives in the first row cannot be solved.
    i = 0usize
    while i < 81usize {
        grid[i] = puzzle[i] - 48u8
        i += 1usize
    }
    grid[2usize] = 5u8
    if exact_cover.sudoku(grid[..], big, links_left, links_right, links_up, links_down, links_column, links_row, sizes[..], cells[..]) != exact_cover.Unsolvable { os.exit(2i32) }
    grid[2usize] = 12u8
    if exact_cover.sudoku(grid[..], big, links_left, links_right, links_up, links_down, links_column, links_row, sizes[..], cells[..]) != exact_cover.Invalid { os.exit(2i32) }

    try io.print("algo exact cover ok\n")
    ret ok
}
