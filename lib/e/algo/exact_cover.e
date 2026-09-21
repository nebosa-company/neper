// Exact cover by Knuth's Algorithm X with dancing links over caller
// arrays: a 0/1 matrix of `rows × columns` (row-major bytes) is threaded
// into circular doubly linked lists of its ones, and `solve` searches for
// a set of rows covering every column exactly once, the column with the
// fewest ones chosen first. `sudoku` maps a 9 × 9 grid onto the 729 × 324
// cover matrix and reads the solution back.

error TooSmall
error Invalid
error Unsolvable

type Links = struct { left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32, columns: usize, nodes: usize }

// The node arrays each need `columns + 1 + ones` entries; `size` needs
// `columns + 1`. Answers the threaded structure.
fn links(matrix: []const u8, rows: usize, columns: usize, left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32) -> (Links, err) {
    if matrix.len < rows * columns { ret (zero, TooSmall) }
    var ones = 0usize
    var i = 0usize
    while i < rows * columns {
        if matrix[i] != 0u8 { ones += 1usize }
        i += 1usize
    }
    let total = columns + 1usize + ones
    if left.len < total || right.len < total || up.len < total || down.len < total || column.len < total || row.len < total || size.len < columns + 1usize { ret (zero, TooSmall) }
    // Node 0 is the root; 1..=columns are the column headers.
    var c = 0usize
    while c <= columns {
        left[c] = u32((c + columns) % (columns + 1usize))
        right[c] = u32((c + 1usize) % (columns + 1usize))
        up[c] = u32(c)
        down[c] = u32(c)
        column[c] = u32(c)
        row[c] = 0u32
        size[c] = 0u32
        c += 1usize
    }
    var next = columns + 1usize
    var r = 0usize
    while r < rows {
        var first = 0usize
        c = 0usize
        while c < columns {
            if matrix[r * columns + c] != 0u8 {
                let node = next
                next += 1usize
                let header = c + 1usize
                column[node] = u32(header)
                row[node] = u32(r)
                // Bottom of the column.
                up[node] = up[header]
                down[node] = u32(header)
                down[usize(up[header])] = u32(node)
                up[header] = u32(node)
                size[header] += 1u32
                if first == 0usize {
                    first = node
                    left[node] = u32(node)
                    right[node] = u32(node)
                } else {
                    left[node] = left[first]
                    right[node] = u32(first)
                    right[usize(left[first])] = u32(node)
                    left[first] = u32(node)
                }
            }
            c += 1usize
        }
        r += 1usize
    }
    ret (Links { left: left, right: right, up: up, down: down, column: column, row: row, size: size, columns: columns, nodes: next }, ok)
}

fn cover(l: *Links, header: u32) {
    let c = usize(header)
    l.right[usize(l.left[c])] = l.right[c]
    l.left[usize(l.right[c])] = l.left[c]
    var i = l.down[c]
    while i != header {
        var j = l.right[usize(i)]
        while j != i {
            l.down[usize(l.up[usize(j)])] = l.down[usize(j)]
            l.up[usize(l.down[usize(j)])] = l.up[usize(j)]
            l.size[usize(l.column[usize(j)])] -= 1u32
            j = l.right[usize(j)]
        }
        i = l.down[usize(i)]
    }
}

fn uncover(l: *Links, header: u32) {
    let c = usize(header)
    var i = l.up[c]
    while i != header {
        var j = l.left[usize(i)]
        while j != i {
            l.size[usize(l.column[usize(j)])] += 1u32
            l.down[usize(l.up[usize(j)])] = j
            l.up[usize(l.down[usize(j)])] = j
            j = l.left[usize(j)]
        }
        i = l.up[usize(i)]
    }
    l.right[usize(l.left[c])] = header
    l.left[usize(l.right[c])] = header
}

// Search from depth `depth`; `chosen` collects the rows. Answers whether a
// cover was found (the first one).
fn search(l: *Links, chosen: []usize, depth: usize) -> (usize, bool) {
    if l.right[0usize] == 0u32 { ret (depth, true) }
    // The column with the fewest ones.
    var best = l.right[0usize]
    var c = best
    while c != 0u32 {
        if l.size[usize(c)] < l.size[usize(best)] { best = c }
        c = l.right[usize(c)]
    }
    if l.size[usize(best)] == 0u32 { ret (depth, false) }
    if depth >= chosen.len { ret (depth, false) }
    cover(l, best)
    var r = l.down[usize(best)]
    while r != best {
        chosen[depth] = usize(l.row[usize(r)])
        var j = l.right[usize(r)]
        while j != r {
            cover(l, l.column[usize(j)])
            j = l.right[usize(j)]
        }
        let (found_depth, found) = search(l, chosen, depth + 1usize)
        j = l.left[usize(r)]
        while j != r {
            uncover(l, l.column[usize(j)])
            j = l.left[usize(j)]
        }
        if found {
            uncover(l, best)
            ret (found_depth, true)
        }
        r = l.down[usize(r)]
    }
    uncover(l, best)
    ret (depth, false)
}

// The first exact cover of the threaded matrix as row indices into
// `chosen`; answers the row count or `Unsolvable`.
fn solve(l: *Links, chosen: []usize) -> (usize, err) {
    let (count, found) = search(l, chosen, 0usize)
    if !found { ret (0usize, Unsolvable) }
    ret (count, ok)
}

// Solve a Sudoku `grid` (81 bytes, 0 for empty, else 1..9) in place. The
// cover matrix has a row per (cell, digit) and columns for cell filled,
// row-digit, column-digit and box-digit; `matrix.len >= 729 * 324`, the
// link arrays `>= 324 + 1 + 2916`, `size.len >= 325`, `chosen.len >= 81`.
fn sudoku(grid: []u8, matrix: []u8, left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32, chosen: []usize) -> err {
    if grid.len < 81usize || matrix.len < 729usize * 324usize || chosen.len < 81usize { ret TooSmall }
    var i = 0usize
    while i < 729usize * 324usize {
        matrix[i] = 0u8
        i += 1usize
    }
    var cell = 0usize
    while cell < 81usize {
        let r = cell / 9usize
        let c = cell % 9usize
        if grid[cell] > 9u8 { ret Invalid }
        var d = 0usize
        while d < 9usize {
            // A given digit keeps only its own row of the matrix.
            if grid[cell] == 0u8 || usize(grid[cell]) == d + 1usize {
                let matrix_row = cell * 9usize + d
                matrix[matrix_row * 324usize + cell] = 1u8
                matrix[matrix_row * 324usize + 81usize + r * 9usize + d] = 1u8
                matrix[matrix_row * 324usize + 162usize + c * 9usize + d] = 1u8
                matrix[matrix_row * 324usize + 243usize + (r / 3usize * 3usize + c / 3usize) * 9usize + d] = 1u8
            }
            d += 1usize
        }
        cell += 1usize
    }
    let (l0, link_error) = links(matrix, 729usize, 324usize, left, right, up, down, column, row, size)
    if link_error != ok { ret link_error }
    var l = l0
    let (count, solve_error) = solve(&l, chosen)
    if solve_error != ok { ret solve_error }
    if count != 81usize { ret Unsolvable }
    i = 0usize
    while i < 81usize {
        grid[chosen[i] / 9usize] = u8(chosen[i] % 9usize + 1usize)
        i += 1usize
    }
    ret ok
}
