// A small in-memory relational executor over caller storage. A `Table` is a
// flat `[]i64` of fixed-width rows; a plan is an array of `Op` nodes (Scan,
// Filter, Project, Join, Limit) that name their inputs by index. `iterator`
// pulls one row at a time (Volcano open/next), `vectorized` pulls batches
// with a selection vector, and the standalone joins (`join_nested_loop`,
// `join_hash`, `join_hash_parallel`, `join_sort_merge`, `join_semi`,
// `join_anti`) append `a`-row ++ `b`-row tuples to `out`. The optimiser
// pieces rewrite a plan in place: `push_predicates`, `push_projections`,
// a Selinger left-deep `join_order` and `optimize` that chains them;
// `estimate_join_size`, `prune_partitions`, `index_only_scan` and
// `materialize_cte` stand on their own.

use e.algo.sort

const SCAN: u8 = 0u8
const FILTER: u8 = 1u8
const PROJECT: u8 = 2u8
const JOIN: u8 = 3u8
const LIMIT: u8 = 4u8
const EQ: u8 = 0u8
const NE: u8 = 1u8
const LT: u8 = 2u8
const LE: u8 = 3u8
const GT: u8 = 4u8
const GE: u8 = 5u8
const STRIDE: usize = 5usize
const MAX_RELATIONS: usize = 8usize

type Table = struct { cells: []const i64, columns: usize }
type Op = struct { kind: u8, cmp: u8, input_a: u32, input_b: u32, column: u32, column_b: u32, value: i64, cols: []const u32 }
type Cursor = struct { plan: []const Op, root: u32, tables: []const Table, state: []usize, buf: []i64, width: usize, batch: usize }
type Planner = struct { plan: []Op, count: usize, tables: []const Table, cols: []u32, cols_used: usize }
type KeyOrder = struct { t: Table, column: usize }
type HashJoin = struct { a: Table, ca: usize, ia: []const u32, b: Table, cb: usize, ib: []const u32, build_a: bool }
error Invalid
error TooSmall

// ---- tables ----

fn table(cells: []const i64, columns: usize) -> Table { ret Table { cells: cells, columns: columns } }

fn rows(t: Table) -> usize {
    if t.columns == 0usize { ret 0usize }
    ret t.cells.len / t.columns
}

fn cell(t: Table, row: usize, col: usize) -> i64 { ret t.cells[row * t.columns + col] }

fn copy_row(t: Table, row: usize, out: []i64) {
    var i = 0usize
    while i < t.columns {
        out[i] = cell(t, row, i)
        i += 1usize
    }
}

// ---- plan nodes ----

fn scan(table_index: u32) -> Op { ret Op { kind: SCAN, cmp: 0u8, input_a: table_index, input_b: 0u32, column: 0u32, column_b: 0u32, value: 0i64, cols: zero } }
fn filter(input: u32, column: u32, cmp: u8, value: i64) -> Op { ret Op { kind: FILTER, cmp: cmp, input_a: input, input_b: 0u32, column: column, column_b: 0u32, value: value, cols: zero } }
fn project(input: u32, cols: []const u32) -> Op { ret Op { kind: PROJECT, cmp: 0u8, input_a: input, input_b: 0u32, column: 0u32, column_b: 0u32, value: 0i64, cols: cols } }
fn join(a: u32, b: u32, column_a: u32, column_b: u32) -> Op { ret Op { kind: JOIN, cmp: 0u8, input_a: a, input_b: b, column: column_a, column_b: column_b, value: 0i64, cols: zero } }
fn limit(input: u32, count: usize) -> Op { ret Op { kind: LIMIT, cmp: 0u8, input_a: input, input_b: 0u32, column: 0u32, column_b: 0u32, value: i64(count), cols: zero } }

// Columns a node produces.
fn output_columns(plan: []const Op, tables: []const Table, node: u32) -> usize {
    let op = plan[usize(node)]
    if op.kind == SCAN { ret tables[usize(op.input_a)].columns }
    if op.kind == PROJECT { ret op.cols.len }
    if op.kind == JOIN { ret output_columns(plan, tables, op.input_a) + output_columns(plan, tables, op.input_b) }
    ret output_columns(plan, tables, op.input_a)
}

// ponytail: a cycle in `plan` recurses forever; a visited mark per node would catch it.
fn validate(plan: []const Op, tables: []const Table) -> err {
    var i = 0usize
    while i < plan.len {
        let op = plan[i]
        if op.kind > LIMIT { ret Invalid }
        if op.kind == SCAN {
            if usize(op.input_a) >= tables.len { ret Invalid }
        } else {
            if usize(op.input_a) >= plan.len { ret Invalid }
            if op.kind == JOIN && usize(op.input_b) >= plan.len { ret Invalid }
        }
        i += 1usize
    }
    i = 0usize
    while i < plan.len {
        let e = validate_columns(plan, tables, u32(i))
        if e != ok { ret e }
        i += 1usize
    }
    ret ok
}

fn validate_columns(plan: []const Op, tables: []const Table, node: u32) -> err {
    let op = plan[usize(node)]
    if op.kind == SCAN { ret ok }
    let w = output_columns(plan, tables, op.input_a)
    if op.kind == FILTER && usize(op.column) >= w { ret Invalid }
    if op.kind == JOIN && (usize(op.column) >= w || usize(op.column_b) >= output_columns(plan, tables, op.input_b)) { ret Invalid }
    if op.kind == PROJECT {
        var i = 0usize
        while i < op.cols.len {
            if usize(op.cols[i]) >= w { ret Invalid }
            i += 1usize
        }
    }
    ret ok
}

fn passes(cmp: u8, x: i64, v: i64) -> bool {
    if cmp == EQ { ret x == v }
    if cmp == NE { ret x != v }
    if cmp == LT { ret x < v }
    if cmp == LE { ret x <= v }
    if cmp == GT { ret x > v }
    ret x >= v
}

// ---- cursor (shared by the row iterator and the batch executor) ----

// `state` needs STRIDE entries per node; `buf` needs (2 * plan.len + 1) * W * batch cells,
// W being the widest node: two row buffers per node plus one staging area.
fn cursor(plan: []const Op, root: u32, tables: []const Table, batch: usize, state: []usize, buf: []i64) -> (Cursor, err) {
    let e = validate(plan, tables)
    if e != ok { ret (zero, e) }
    if usize(root) >= plan.len || batch == 0usize { ret (zero, Invalid) }
    var w = 0usize
    var i = 0usize
    while i < plan.len {
        let wi = output_columns(plan, tables, u32(i))
        if wi > w { w = wi }
        i += 1usize
    }
    if state.len < STRIDE * plan.len || buf.len < (2usize * plan.len + 1usize) * w * batch { ret (zero, TooSmall) }
    i = 0usize
    while i < STRIDE * plan.len {
        state[i] = 0usize
        i += 1usize
    }
    ret (Cursor { plan: plan, root: root, tables: tables, state: state, buf: buf, width: w, batch: batch }, ok)
}

// A Volcano cursor pulling one row per `next`.
fn iterator(plan: []const Op, root: u32, tables: []const Table, state: []usize, buf: []i64) -> (Cursor, err) {
    let (c, e) = cursor(plan, root, tables, 1usize, state, buf)
    ret (c, e)
}

fn slot(c: *Cursor, node: u32, side: usize, w: usize) -> []i64 {
    let start = (2usize * usize(node) + side) * c.width * c.batch
    ret c.buf[start..start + w * c.batch]
}

// open(): rewind a subtree.
fn reset(c: *Cursor, node: u32) {
    let base = usize(node) * STRIDE
    var i = 0usize
    while i < STRIDE {
        c.state[base + i] = 0usize
        i += 1usize
    }
    let op = c.plan[usize(node)]
    if op.kind == SCAN { ret }
    reset(c, op.input_a)
    if op.kind == JOIN { reset(c, op.input_b) }
}

// The next row of the root into `out` (its width in cells); false at the end.
fn next(c: *Cursor, out: []i64) -> (bool, err) {
    if out.len < output_columns(c.plan, c.tables, c.root) { ret (false, TooSmall) }
    let (got, e) = pull(c, c.root, out)
    ret (got, e)
}

fn pull(c: *Cursor, node: u32, out: []i64) -> (bool, err) {
    let op = c.plan[usize(node)]
    if op.kind == SCAN {
        let t = c.tables[usize(op.input_a)]
        let base = usize(node) * STRIDE
        let r = c.state[base]
        if r >= rows(t) { ret (false, ok) }
        c.state[base] = r + 1usize
        copy_row(t, r, out)
        ret (true, ok)
    }
    if op.kind == FILTER {
        let (gf, ef) = pull_filter(c, op, out)
        ret (gf, ef)
    }
    if op.kind == PROJECT {
        let (gp, ep) = pull_project(c, node, op, out)
        ret (gp, ep)
    }
    if op.kind == JOIN {
        let (gj, ej) = pull_join(c, node, op, out)
        ret (gj, ej)
    }
    let (gl, el) = pull_limit(c, node, op, out)
    ret (gl, el)
}

fn pull_filter(c: *Cursor, op: Op, out: []i64) -> (bool, err) {
    while true {
        let (got, e) = pull(c, op.input_a, out)
        if e != ok || !got { ret (false, e) }
        if passes(op.cmp, out[usize(op.column)], op.value) { ret (true, ok) }
    }
    ret (false, ok)
}

fn pull_project(c: *Cursor, node: u32, op: Op, out: []i64) -> (bool, err) {
    let w = output_columns(c.plan, c.tables, op.input_a)
    let row = slot(c, node, 0usize, w)
    let (got, e) = pull(c, op.input_a, row)
    if e != ok || !got { ret (false, e) }
    var i = 0usize
    while i < op.cols.len {
        out[i] = row[usize(op.cols[i])]
        i += 1usize
    }
    ret (true, ok)
}

fn pull_join(c: *Cursor, node: u32, op: Op, out: []i64) -> (bool, err) {
    let base = usize(node) * STRIDE
    let wa = output_columns(c.plan, c.tables, op.input_a)
    let wb = output_columns(c.plan, c.tables, op.input_b)
    let outer = slot(c, node, 0usize, wa)
    let inner = slot(c, node, 1usize, wb)
    while true {
        if c.state[base + 1usize] == 0usize {
            let (got_a, ea) = pull(c, op.input_a, outer)
            if ea != ok || !got_a { ret (false, ea) }
            c.state[base + 1usize] = 1usize
            reset(c, op.input_b)
        }
        let (got_b, eb) = pull(c, op.input_b, inner)
        if eb != ok { ret (false, eb) }
        if !got_b {
            c.state[base + 1usize] = 0usize
            continue
        }
        if outer[usize(op.column)] == inner[usize(op.column_b)] {
            var i = 0usize
            while i < wa {
                out[i] = outer[i]
                i += 1usize
            }
            i = 0usize
            while i < wb {
                out[wa + i] = inner[i]
                i += 1usize
            }
            ret (true, ok)
        }
    }
    ret (false, ok)
}

fn pull_limit(c: *Cursor, node: u32, op: Op, out: []i64) -> (bool, err) {
    let base = usize(node) * STRIDE
    if op.value <= 0i64 || c.state[base] >= usize(op.value) { ret (false, ok) }
    let (got, e) = pull(c, op.input_a, out)
    if e != ok || !got { ret (false, e) }
    c.state[base] += 1usize
    ret (true, ok)
}

// ---- vectorized ----

// Runs the plan in batches of `batch_size` rows and appends every root row to `out`.
fn vectorized(plan: []const Op, root: u32, tables: []const Table, batch_size: usize, state: []usize, buf: []i64, out: []i64) -> (usize, err) {
    let (c0, e) = cursor(plan, root, tables, batch_size, state, buf)
    if e != ok { ret (0usize, e) }
    var c = c0
    let w = output_columns(plan, tables, root)
    var total = 0usize
    while true {
        let (n, en) = pull_batch(&c, root, slot(&c, u32(plan.len), 0usize, w))
        if en != ok || n == 0usize { ret (total, en) }
        if (total + n) * w > out.len { ret (total, TooSmall) }
        let staging = slot(&c, u32(plan.len), 0usize, w)
        var i = 0usize
        while i < n * w {
            out[total * w + i] = staging[i]
            i += 1usize
        }
        total += n
    }
    ret (total, ok)
}

// The next batch of root rows into `out` (batch * width cells); 0 at the end.
fn next_batch(c: *Cursor, out: []i64) -> (usize, err) {
    if out.len < c.batch * output_columns(c.plan, c.tables, c.root) { ret (0usize, TooSmall) }
    let (n, e) = pull_batch(c, c.root, out)
    ret (n, e)
}

fn pull_batch(c: *Cursor, node: u32, out: []i64) -> (usize, err) {
    let op = c.plan[usize(node)]
    if op.kind == SCAN {
        let t = c.tables[usize(op.input_a)]
        let base = usize(node) * STRIDE
        let pos = c.state[base]
        let total = rows(t)
        var n = 0usize
        while n < c.batch && pos + n < total {
            copy_row(t, pos + n, out[n * t.columns..])
            n += 1usize
        }
        c.state[base] = pos + n
        ret (n, ok)
    }
    if op.kind == FILTER {
        let (nf, ef) = filter_batch(c, node, op, out)
        ret (nf, ef)
    }
    if op.kind == PROJECT {
        let (np, ep) = project_batch(c, node, op, out)
        ret (np, ep)
    }
    if op.kind == JOIN {
        let (nj, ej) = join_batch(c, node, op, out)
        ret (nj, ej)
    }
    let (nl, el) = limit_batch(c, node, op, out)
    ret (nl, el)
}

// The selection vector lives in the node's (otherwise unused) inner slot.
fn filter_batch(c: *Cursor, node: u32, op: Op, out: []i64) -> (usize, err) {
    let w = output_columns(c.plan, c.tables, node)
    let in_rows = slot(c, node, 0usize, w)
    let sel = slot(c, node, 1usize, w)
    while true {
        let (n, e) = pull_batch(c, op.input_a, in_rows)
        if e != ok || n == 0usize { ret (0usize, e) }
        var kept = 0usize
        var i = 0usize
        while i < n {
            if passes(op.cmp, in_rows[i * w + usize(op.column)], op.value) {
                sel[kept] = i64(i)
                kept += 1usize
            }
            i += 1usize
        }
        if kept > 0usize {
            var k = 0usize
            while k < kept {
                let src = usize(sel[k]) * w
                var j = 0usize
                while j < w {
                    out[k * w + j] = in_rows[src + j]
                    j += 1usize
                }
                k += 1usize
            }
            ret (kept, ok)
        }
    }
    ret (0usize, ok)
}

fn project_batch(c: *Cursor, node: u32, op: Op, out: []i64) -> (usize, err) {
    let wc = output_columns(c.plan, c.tables, op.input_a)
    let in_rows = slot(c, node, 0usize, wc)
    let (n, e) = pull_batch(c, op.input_a, in_rows)
    if e != ok || n == 0usize { ret (0usize, e) }
    let w = op.cols.len
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < w {
            out[i * w + k] = in_rows[i * wc + usize(op.cols[k])]
            k += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// Block nested loop: every outer batch is matched against every inner batch (the inner
// side is re-opened per outer batch); the (outer, inner) position resumes across calls.
fn join_batch(c: *Cursor, node: u32, op: Op, out: []i64) -> (usize, err) {
    let base = usize(node) * STRIDE
    let wa = output_columns(c.plan, c.tables, op.input_a)
    let wb = output_columns(c.plan, c.tables, op.input_b)
    let outer = slot(c, node, 0usize, wa)
    let inner = slot(c, node, 1usize, wb)
    var produced = 0usize
    while produced < c.batch {
        if c.state[base + 1usize] == 0usize {
            let (na, ea) = pull_batch(c, op.input_a, outer)
            if ea != ok || na == 0usize { ret (produced, ea) }
            c.state[base + 1usize] = na
            c.state[base + 2usize] = 0usize
            reset(c, op.input_b)
        }
        if c.state[base + 2usize] == 0usize {
            let (nb, eb) = pull_batch(c, op.input_b, inner)
            if eb != ok { ret (produced, eb) }
            if nb == 0usize {
                c.state[base + 1usize] = 0usize
                continue
            }
            c.state[base + 2usize] = nb
            c.state[base + 3usize] = 0usize
            c.state[base + 4usize] = 0usize
        }
        let no = c.state[base + 1usize]
        let ni = c.state[base + 2usize]
        var oi = c.state[base + 3usize]
        var ii = c.state[base + 4usize]
        while oi < no && produced < c.batch {
            while ii < ni && produced < c.batch {
                if outer[oi * wa + usize(op.column)] == inner[ii * wb + usize(op.column_b)] {
                    emit_pair(outer[oi * wa..oi * wa + wa], inner[ii * wb..ii * wb + wb], out[produced * (wa + wb)..])
                    produced += 1usize
                }
                ii += 1usize
            }
            if ii == ni {
                ii = 0usize
                oi += 1usize
            }
        }
        c.state[base + 3usize] = oi
        c.state[base + 4usize] = ii
        if oi == no { c.state[base + 2usize] = 0usize }
    }
    ret (produced, ok)
}

fn emit_pair(left: []const i64, right: []const i64, out: []i64) {
    var i = 0usize
    while i < left.len {
        out[i] = left[i]
        i += 1usize
    }
    i = 0usize
    while i < right.len {
        out[left.len + i] = right[i]
        i += 1usize
    }
}

fn limit_batch(c: *Cursor, node: u32, op: Op, out: []i64) -> (usize, err) {
    let base = usize(node) * STRIDE
    if op.value <= 0i64 || c.state[base] >= usize(op.value) { ret (0usize, ok) }
    let remaining = usize(op.value) - c.state[base]
    let (n0, e) = pull_batch(c, op.input_a, out)
    if e != ok { ret (0usize, e) }
    var n = n0
    if n > remaining { n = remaining }
    c.state[base] += n
    ret (n, ok)
}

// ---- standalone joins ----

fn emit(a: Table, ra: usize, b: Table, rb: usize, out: []i64, n: usize) -> err {
    let w = a.columns + b.columns
    if (n + 1usize) * w > out.len { ret TooSmall }
    copy_row(a, ra, out[n * w..])
    copy_row(b, rb, out[n * w + a.columns..])
    ret ok
}

// Every (a, b) pair with a[ca] == b[cb], as a-row ++ b-row; answers the row count.
fn join_nested_loop(a: Table, ca: usize, b: Table, cb: usize, out: []i64) -> (usize, err) {
    if ca >= a.columns || cb >= b.columns { ret (0usize, Invalid) }
    var n = 0usize
    var i = 0usize
    while i < rows(a) {
        var j = 0usize
        while j < rows(b) {
            if cell(a, i, ca) == cell(b, j, cb) {
                let e = emit(a, i, b, j, out, n)
                if e != ok { ret (n, e) }
                n += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

fn hash_key(k: i64) -> u64 {
    var h = u64(k & 9223372036854775807i64)
    if k < 0i64 { h = h | (1u64 << 63u32) }
    h = (h ^ (h >> 33u32)) *% 6364136223846793005u64
    ret h ^ (h >> 29u32)
}

fn bucket_of(key: i64, buckets: usize) -> usize { ret usize(hash_key(key) % u64(buckets)) }

// An empty index list stands for every row of that side.
fn count_of(t: Table, index: []const u32) -> usize {
    if index.len == 0usize { ret rows(t) }
    ret index.len
}

fn row_at(index: []const u32, i: usize) -> usize {
    if index.len == 0usize { ret i }
    ret usize(index[i])
}

fn side_key(j: *const HashJoin, from_a: bool, i: usize) -> (usize, i64) {
    if from_a {
        let ra = row_at(j.ia, i)
        ret (ra, cell(j.a, ra, j.ca))
    }
    let rb = row_at(j.ib, i)
    ret (rb, cell(j.b, rb, j.cb))
}

fn side_count(j: *const HashJoin, from_a: bool) -> usize {
    if from_a { ret count_of(j.a, j.ia) }
    ret count_of(j.b, j.ib)
}

// Chains the build side's rows through `buckets` (row + 1, 0 = empty) and `chain`.
fn build_side(j: *const HashJoin, buckets: []u32, chain: []u32) -> err {
    let build_n = side_count(j, j.build_a)
    if buckets.len == 0usize || chain.len < build_n { ret TooSmall }
    var i = 0usize
    while i < buckets.len {
        buckets[i] = 0u32
        i += 1usize
    }
    i = 0usize
    while i < build_n {
        let (_, key) = side_key(j, j.build_a, i)
        let h = bucket_of(key, buckets.len)
        chain[i] = buckets[h]
        buckets[h] = u32(i + 1usize)
        i += 1usize
    }
    ret ok
}

fn hash_join_rows(j: *const HashJoin, out: []i64, buckets: []u32, chain: []u32, start: usize) -> (usize, err) {
    let build_error = build_side(j, buckets, chain)
    if build_error != ok { ret (start, build_error) }
    var n = start
    let probe_n = side_count(j, !j.build_a)
    var p = 0usize
    while p < probe_n {
        let (pr, key) = side_key(j, !j.build_a, p)
        var hit = buckets[bucket_of(key, buckets.len)]
        while hit != 0u32 {
            let bi = usize(hit) - 1usize
            let (br, bkey) = side_key(j, j.build_a, bi)
            if bkey == key {
                var e = ok
                if j.build_a { e = emit(j.a, br, j.b, pr, out, n) } else { e = emit(j.a, pr, j.b, br, out, n) }
                if e != ok { ret (n, e) }
                n += 1usize
            }
            hit = chain[bi]
        }
        p += 1usize
    }
    ret (n, ok)
}

// Hash join building on the smaller side; `buckets` is any non-empty bucket array and
// `chain` holds one link per build row.
fn join_hash(a: Table, ca: usize, b: Table, cb: usize, out: []i64, buckets: []u32, chain: []u32) -> (usize, err) {
    if ca >= a.columns || cb >= b.columns { ret (0usize, Invalid) }
    var j = HashJoin { a: a, ca: ca, ia: buckets[..0usize], b: b, cb: cb, ib: buckets[..0usize], build_a: rows(a) <= rows(b) }
    let (n, e) = hash_join_rows(&j, out, buckets, chain, 0usize)
    ret (n, e)
}

// ponytail: one pass per partition (O(P * rows)); a counting sort into `index` does it in two.
fn gather(t: Table, col: usize, part: usize, partitions: usize, index: []u32) -> usize {
    var n = 0usize
    var r = 0usize
    let total = rows(t)
    while r < total {
        if usize((hash_key(cell(t, r, col)) >> 32u32) % u64(partitions)) == part {
            index[n] = u32(r)
            n += 1usize
        }
        r += 1usize
    }
    ret n
}

// Radix-partitions both sides by key hash into `partitions` and hash-joins partition-wise;
// the result set equals `join_hash` in partition order. `index_a`/`index_b` hold one entry per row.
// ponytail: partitions run one after another on this thread; each `p` is independent and
// could go to a worker with its own `out` and scratch.
fn join_hash_parallel(a: Table, ca: usize, b: Table, cb: usize, out: []i64, partitions: usize, index_a: []u32, index_b: []u32, buckets: []u32, chain: []u32) -> (usize, err) {
    if ca >= a.columns || cb >= b.columns || partitions == 0usize { ret (0usize, Invalid) }
    if index_a.len < rows(a) || index_b.len < rows(b) { ret (0usize, TooSmall) }
    var n = 0usize
    var p = 0usize
    while p < partitions {
        let na = gather(a, ca, p, partitions, index_a)
        let nb = gather(b, cb, p, partitions, index_b)
        if na > 0usize && nb > 0usize {
            var j = HashJoin { a: a, ca: ca, ia: index_a[..na], b: b, cb: cb, ib: index_b[..nb], build_a: na <= nb }
            let (m, e) = hash_join_rows(&j, out, buckets, chain, n)
            if e != ok { ret (m, e) }
            n = m
        }
        p += 1usize
    }
    ret (n, ok)
}

fn key_order(k: *KeyOrder, x: u32, y: u32) -> i32 {
    let kx = cell(k.t, usize(x), k.column)
    let ky = cell(k.t, usize(y), k.column)
    if kx < ky { ret 0i32 - 1i32 }
    if kx > ky { ret 1i32 }
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sorted_rows(t: Table, col: usize, index: []u32) -> usize {
    let n = rows(t)
    var i = 0usize
    while i < n {
        index[i] = u32(i)
        i += 1usize
    }
    var k = KeyOrder { t: t, column: col }
    sort.in_place_by[u32, KeyOrder](index[..n], &k, key_order)
    ret n
}

// A covering index over `col`: `index_keys` sorted with the matching row ids in `index_rows`
// (one entry per row); answers the entry count.
fn build_index(t: Table, col: usize, index_keys: []i64, index_rows: []u32) -> (usize, err) {
    if col >= t.columns { ret (0usize, Invalid) }
    if index_keys.len < rows(t) || index_rows.len < rows(t) { ret (0usize, TooSmall) }
    let n = sorted_rows(t, col, index_rows)
    var i = 0usize
    while i < n {
        index_keys[i] = cell(t, usize(index_rows[i]), col)
        i += 1usize
    }
    ret (n, ok)
}

// Sorts both sides' row indices by key (into `index_a`/`index_b`, one entry per row) and
// merges; equal-key runs on both sides produce their cross product.
fn join_sort_merge(a: Table, ca: usize, b: Table, cb: usize, out: []i64, index_a: []u32, index_b: []u32) -> (usize, err) {
    if ca >= a.columns || cb >= b.columns { ret (0usize, Invalid) }
    if index_a.len < rows(a) || index_b.len < rows(b) { ret (0usize, TooSmall) }
    let na = sorted_rows(a, ca, index_a)
    let nb = sorted_rows(b, cb, index_b)
    var n = 0usize
    var i = 0usize
    var j = 0usize
    while i < na && j < nb {
        let ka = cell(a, usize(index_a[i]), ca)
        let kb = cell(b, usize(index_b[j]), cb)
        if ka < kb {
            i += 1usize
        } else if ka > kb {
            j += 1usize
        } else {
            var j2 = j
            while j2 < nb && cell(b, usize(index_b[j2]), cb) == kb { j2 += 1usize }
            while i < na && cell(a, usize(index_a[i]), ca) == ka {
                var k = j
                while k < j2 {
                    let e = emit(a, usize(index_a[i]), b, usize(index_b[k]), out, n)
                    if e != ok { ret (n, e) }
                    n += 1usize
                    k += 1usize
                }
                i += 1usize
            }
            j = j2
        }
    }
    ret (n, ok)
}

fn semi_anti(a: Table, ca: usize, b: Table, cb: usize, out: []i64, buckets: []u32, chain: []u32, want: bool) -> (usize, err) {
    if ca >= a.columns || cb >= b.columns { ret (0usize, Invalid) }
    var j = HashJoin { a: a, ca: ca, ia: buckets[..0usize], b: b, cb: cb, ib: buckets[..0usize], build_a: false }
    let build_error = build_side(&j, buckets, chain)
    if build_error != ok { ret (0usize, build_error) }
    var n = 0usize
    var i = 0usize
    while i < rows(a) {
        let key = cell(a, i, ca)
        var hit = buckets[bucket_of(key, buckets.len)]
        var found = false
        while hit != 0u32 && !found {
            let bi = usize(hit) - 1usize
            if cell(b, bi, cb) == key { found = true }
            hit = chain[bi]
        }
        if found == want {
            if (n + 1usize) * a.columns > out.len { ret (n, TooSmall) }
            copy_row(a, i, out[n * a.columns..])
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// Rows of `a` with at least one match in `b` (hash on `b`; `chain` holds one link per b row).
fn join_semi(a: Table, ca: usize, b: Table, cb: usize, out: []i64, buckets: []u32, chain: []u32) -> (usize, err) {
    let (n, e) = semi_anti(a, ca, b, cb, out, buckets, chain, true)
    ret (n, e)
}

// Rows of `a` with no match in `b`.
fn join_anti(a: Table, ca: usize, b: Table, cb: usize, out: []i64, buckets: []u32, chain: []u32) -> (usize, err) {
    let (n, e) = semi_anti(a, ca, b, cb, out, buckets, chain, false)
    ret (n, e)
}

// ---- statistics and access paths ----

// |A| * |B| / max(V(A, x), V(B, y)); 0 when neither side has a distinct value.
fn estimate_join_size(rows_a: u64, rows_b: u64, distinct_a: u64, distinct_b: u64) -> f64 {
    var d = distinct_a
    if distinct_b > d { d = distinct_b }
    if d == 0u64 { ret 0.0f64 }
    ret f64(rows_a) * f64(rows_b) / f64(d)
}

// Indices of the partitions whose [min, max] meets [lo, hi].
fn prune_partitions(partition_min: []const i64, partition_max: []const i64, lo: i64, hi: i64, out: []u32) -> (usize, err) {
    if partition_max.len != partition_min.len { ret (0usize, Invalid) }
    var n = 0usize
    var i = 0usize
    while i < partition_min.len {
        if partition_max[i] >= lo && partition_min[i] <= hi {
            if n >= out.len { ret (n, TooSmall) }
            out[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

fn lower_bound(keys: []const i64, key: i64) -> usize {
    var lo = 0usize
    var hi = keys.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if keys[mid] < key { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

fn upper_bound(keys: []const i64, key: i64) -> usize {
    var lo = 0usize
    var hi = keys.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if keys[mid] <= key { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

// The row ids whose key lies in [lo, hi], answered from a sorted index alone.
fn index_only_scan(index_keys: []const i64, index_rows: []const u32, lo: i64, hi: i64, out_rows: []u32) -> (usize, err) {
    if index_rows.len != index_keys.len { ret (0usize, Invalid) }
    let start = lower_bound(index_keys, lo)
    let stop = upper_bound(index_keys, hi)
    if stop <= start { ret (0usize, ok) }
    if stop - start > out_rows.len { ret (0usize, TooSmall) }
    var i = start
    while i < stop {
        out_rows[i - start] = index_rows[i]
        i += 1usize
    }
    ret (stop - start, ok)
}

// Evaluates `cte_root` once into `out_cells`; the answer is a Table other nodes can scan.
fn materialize_cte(plan: []const Op, cte_root: u32, tables: []const Table, state: []usize, buf: []i64, out_cells: []i64) -> (Table, err) {
    let (c0, e) = iterator(plan, cte_root, tables, state, buf)
    if e != ok { ret (zero, e) }
    var c = c0
    let w = output_columns(plan, tables, cte_root)
    var n = 0usize
    while true {
        let (got, en) = next(&c, slot(&c, u32(plan.len), 0usize, w))
        if en != ok { ret (zero, en) }
        if !got { ret (table(out_cells[..n * w], w), ok) }
        if (n + 1usize) * w > out_cells.len { ret (zero, TooSmall) }
        let staging = slot(&c, u32(plan.len), 0usize, w)
        var i = 0usize
        while i < w {
            out_cells[n * w + i] = staging[i]
            i += 1usize
        }
        n += 1usize
    }
    ret (zero, ok)
}

// ---- optimiser ----

fn subset_size(cards: []const u64, sel: []const f64, s: usize) -> f64 {
    let n = cards.len
    var card = 1.0f64
    var i = 0usize
    while i < n {
        if ((s >> u32(i)) & 1usize) == 1usize {
            card = card * f64(cards[i])
            var j = 0usize
            while j < i {
                if ((s >> u32(j)) & 1usize) == 1usize { card = card * sel[j * n + i] }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret card
}

// Selinger left-deep join ordering by dynamic programming over subsets (n <= 8) with the
// C_out model: a plan costs the sum of its intermediate result sizes, a size being the
// product of the cardinalities and the pairwise selectivities (`selectivities[i * n + j]`,
// 1.0 for unrelated pairs). `cost` and `best` need 2^n entries; `out_order` lists the
// relations left to right; answers the cost.
fn join_order(cardinalities: []const u64, selectivities: []const f64, out_order: []u32, cost: []f64, best: []u32) -> (f64, err) {
    let n = cardinalities.len
    if n == 0usize || n > MAX_RELATIONS || selectivities.len != n * n || out_order.len < n { ret (0.0f64, Invalid) }
    let subsets = 1usize << u32(n)
    if cost.len < subsets || best.len < subsets { ret (0.0f64, TooSmall) }
    var s = 1usize
    while s < subsets {
        if (s & (s - 1usize)) == 0usize {
            cost[s] = 0.0f64
            best[s] = 0u32
        } else {
            let size = subset_size(cardinalities, selectivities, s)
            var bc = 0.0f64
            var br = 0usize
            var first = true
            var r = 0usize
            while r < n {
                if ((s >> u32(r)) & 1usize) == 1usize {
                    let c = cost[s ^ (1usize << u32(r))]
                    if first || c < bc {
                        bc = c
                        br = r
                        first = false
                    }
                }
                r += 1usize
            }
            cost[s] = size + bc
            best[s] = u32(br)
        }
        s += 1usize
    }
    var remaining = subsets - 1usize
    var k = n
    while (remaining & (remaining - 1usize)) != 0usize {
        let last = usize(best[remaining])
        k -= 1usize
        out_order[k] = u32(last)
        remaining = remaining ^ (1usize << u32(last))
    }
    var lone = 0usize
    while (1usize << u32(lone)) != remaining { lone += 1usize }
    out_order[0usize] = u32(lone)
    ret (cost[subsets - 1usize], ok)
}

// Moves every Filter that sits on a Join down to the join input its column belongs to
// (rewriting the column for the right side) and keeps pushing; answers the new root.
// ponytail: a Filter above a Project stays where it is; mapping its column back through
// the Project would let it sink further.
fn push_predicates(plan: []Op, root: u32, tables: []const Table) -> u32 {
    let op = plan[usize(root)]
    if op.kind == SCAN { ret root }
    if op.kind == FILTER && plan[usize(op.input_a)].kind == JOIN {
        let j = usize(op.input_a)
        let cols_a = output_columns(plan, tables, plan[j].input_a)
        let cols_b = output_columns(plan, tables, plan[j].input_b)
        if usize(op.column) < cols_a {
            plan[usize(root)].input_a = plan[j].input_a
            plan[j].input_a = root
        } else if usize(op.column) < cols_a + cols_b {
            plan[usize(root)].column = op.column - u32(cols_a)
            plan[usize(root)].input_a = plan[j].input_b
            plan[j].input_b = root
        } else {
            ret root
        }
        plan[j].input_a = push_predicates(plan, plan[j].input_a, tables)
        plan[j].input_b = push_predicates(plan, plan[j].input_b, tables)
        ret op.input_a
    }
    plan[usize(root)].input_a = push_predicates(plan, op.input_a, tables)
    if op.kind == JOIN { plan[usize(root)].input_b = push_predicates(plan, op.input_b, tables) }
    ret root
}

// A planner over a plan array with spare slots after `count` and a `cols` scratch that
// the appended Project nodes carve their column lists from.
fn planner(plan: []Op, count: usize, tables: []const Table, cols: []u32) -> Planner {
    ret Planner { plan: plan, count: count, tables: tables, cols: cols, cols_used: 0usize }
}

fn needed(c: usize, base: usize, key: u32, cols: []const u32) -> bool {
    if c == usize(key) { ret true }
    var i = 0usize
    while i < cols.len {
        if usize(cols[i]) >= base && usize(cols[i]) - base == c { ret true }
        i += 1usize
    }
    ret false
}

fn position_of(list: []const u32, c: usize) -> usize {
    var i = 0usize
    while i < list.len && usize(list[i]) != c { i += 1usize }
    ret i
}

fn take_cols(p: *Planner, n: usize) -> ([]u32, err) {
    if p.cols_used + n > p.cols.len { ret (zero, TooSmall) }
    let list = p.cols[p.cols_used..p.cols_used + n]
    p.cols_used += n
    ret (list, ok)
}

// Narrows one join input to the columns the parent Project or the join key needs;
// answers (the input to use, the key column's new position).
fn narrow_side(p: *Planner, side: u32, width: usize, base: usize, key: u32, cols: []const u32) -> (u32, usize, err) {
    var kept = 0usize
    var c = 0usize
    while c < width {
        if needed(c, base, key, cols) { kept += 1usize }
        c += 1usize
    }
    if kept == width { ret (side, usize(key), ok) }
    if p.count >= p.plan.len { ret (side, usize(key), TooSmall) }
    let (list, e) = take_cols(p, kept)
    if e != ok { ret (side, usize(key), e) }
    var k = 0usize
    c = 0usize
    while c < width {
        if needed(c, base, key, cols) {
            list[k] = u32(c)
            k += 1usize
        }
        c += 1usize
    }
    let idx = p.count
    p.plan[idx] = project(side, list)
    p.count += 1usize
    ret (u32(idx), position_of(list, usize(key)), ok)
}

fn new_position(p: *const Planner, side_new: u32, side_old: u32, c: usize) -> usize {
    if side_new == side_old { ret c }
    ret position_of(p.plan[usize(side_new)].cols, c)
}

// `project_index` is a Project directly over a Join: both join inputs get a Project of
// the needed columns and the parent's list is rewritten to the narrowed positions.
fn narrow_join(p: *Planner, project_index: u32) -> err {
    let pr = p.plan[usize(project_index)]
    let j = usize(pr.input_a)
    let jop = p.plan[j]
    let wa = output_columns(p.plan, p.tables, jop.input_a)
    let wb = output_columns(p.plan, p.tables, jop.input_b)
    let (na, ka, ea) = narrow_side(p, jop.input_a, wa, 0usize, jop.column, pr.cols)
    if ea != ok { ret ea }
    let (nb, kb, eb) = narrow_side(p, jop.input_b, wb, wa, jop.column_b, pr.cols)
    if eb != ok { ret eb }
    let (fresh, ef) = take_cols(p, pr.cols.len)
    if ef != ok { ret ef }
    let new_wa = output_columns(p.plan, p.tables, na)
    var i = 0usize
    while i < pr.cols.len {
        let c = usize(pr.cols[i])
        if c < wa { fresh[i] = u32(new_position(p, na, jop.input_a, c)) } else { fresh[i] = u32(new_wa + new_position(p, nb, jop.input_b, c - wa)) }
        i += 1usize
    }
    p.plan[j].input_a = na
    p.plan[j].input_b = nb
    p.plan[j].column = u32(ka)
    p.plan[j].column_b = u32(kb)
    p.plan[usize(project_index)].cols = fresh
    ret ok
}

// Inserts Projects under every Project-over-Join so only needed columns flow; the root
// keeps its index and the plan grows in place (`p.count`).
// ponytail: a Project over a Filter over a Join is left alone; carrying the filter column
// into the needed set would narrow that shape too.
fn push_projections(p: *Planner, root: u32) -> err {
    let op = p.plan[usize(root)]
    if op.kind == SCAN { ret ok }
    if op.kind == PROJECT && p.plan[usize(op.input_a)].kind == JOIN {
        let e = narrow_join(p, root)
        if e != ok { ret e }
    }
    let ea = push_projections(p, p.plan[usize(root)].input_a)
    if ea != ok || op.kind != JOIN { ret ea }
    ret push_projections(p, op.input_b)
}

// Left-deep chain of joins under `top`: `joins` top first, `leaves` bottom-left first;
// answers the leaf count, 0 unless the shape is a chain of at least two joins.
fn chain_of(p: *const Planner, top: u32, joins: []u32, leaves: []u32) -> usize {
    var node = top
    var nj = 0usize
    while p.plan[usize(node)].kind == JOIN {
        if nj + 1usize >= joins.len { ret 0usize }
        if p.plan[usize(p.plan[usize(node)].input_b)].kind == JOIN { ret 0usize }
        joins[nj] = node
        nj += 1usize
        node = p.plan[usize(node)].input_a
    }
    if nj < 2usize { ret 0usize }
    leaves[0usize] = node
    var k = 0usize
    while k < nj {
        leaves[nj - k] = p.plan[usize(joins[k])].input_b
        k += 1usize
    }
    ret nj + 1usize
}

// ponytail: a leaf's cardinality is its underlying scan's row count; filters do not shrink it.
fn leaf_rows(p: *const Planner, leaf: u32) -> usize {
    var node = leaf
    while p.plan[usize(node)].kind != SCAN { node = p.plan[usize(node)].input_a }
    ret rows(p.tables[usize(p.plan[usize(node)].input_a)])
}

fn locate(offsets: []const usize, widths: []const usize, q: usize) -> (usize, usize) {
    var i = 0usize
    while i + 1usize < offsets.len && q >= offsets[i] + widths[i] { i += 1usize }
    ret (i, q - offsets[i])
}

fn in_prefix(order: []const u32, k: usize, leaf: usize) -> bool {
    var j = 0usize
    while j < k {
        if usize(order[j]) == leaf { ret true }
        j += 1usize
    }
    ret false
}

// An equality edge joining order[k] to a leaf among order[0..k): (found, left leaf, left col, right col).
fn connecting_edge(order: []const u32, k: usize, edge_leaf: []const usize, edge_col: []const usize, edge_right: []const usize) -> (bool, usize, usize, usize) {
    let right = usize(order[k])
    var m = 1usize
    while m < order.len {
        if m == right && in_prefix(order, k, edge_leaf[m]) { ret (true, edge_leaf[m], edge_col[m], edge_right[m]) }
        if edge_leaf[m] == right && in_prefix(order, k, m) { ret (true, m, edge_right[m], edge_col[m]) }
        m += 1usize
    }
    ret (false, 0usize, 0usize, 0usize)
}

fn remap_above(p: *Planner, root: u32, top: u32, old_off: []const usize, widths: []const usize, new_off: []const usize) -> err {
    var node = root
    while node != top {
        let op = p.plan[usize(node)]
        if op.kind == FILTER {
            let (lf, lc) = locate(old_off, widths, usize(op.column))
            p.plan[usize(node)].column = u32(new_off[lf] + lc)
        }
        if op.kind == PROJECT {
            let (fresh, e) = take_cols(p, op.cols.len)
            if e != ok { ret e }
            var i = 0usize
            while i < op.cols.len {
                let (pf, pc) = locate(old_off, widths, usize(op.cols[i]))
                fresh[i] = u32(new_off[pf] + pc)
                i += 1usize
            }
            p.plan[usize(node)].cols = fresh
            ret ok
        }
        node = op.input_a
    }
    ret ok
}

// Reorders a left-deep chain of two or more joins under the unary ops above `root` by
// `join_order` (`selectivities` is n x n over the chain's leaves, bottom-left first) and
// rewires the join keys and the column references above; a plan whose best order would
// need a cross product is left as it is.
fn reorder_joins(p: *Planner, root: u32, selectivities: []const f64, cost: []f64, best: []u32) -> err {
    var top = root
    while p.plan[usize(top)].kind != JOIN && p.plan[usize(top)].kind != SCAN { top = p.plan[usize(top)].input_a }
    if p.plan[usize(top)].kind != JOIN { ret ok }
    var joins: [8]u32 = zero
    var leaves: [8]u32 = zero
    let n = chain_of(p, top, joins[..], leaves[..])
    if n == 0usize { ret ok }
    if selectivities.len != n * n { ret Invalid }
    var widths: [8]usize = zero
    var old_off: [8]usize = zero
    var cards: [8]u64 = zero
    var i = 0usize
    while i < n {
        widths[i] = output_columns(p.plan, p.tables, leaves[i])
        if i > 0usize { old_off[i] = old_off[i - 1usize] + widths[i - 1usize] }
        cards[i] = u64(leaf_rows(p, leaves[i]))
        i += 1usize
    }
    var edge_leaf: [8]usize = zero
    var edge_col: [8]usize = zero
    var edge_right: [8]usize = zero
    var k = 1usize
    while k < n {
        let jop = p.plan[usize(joins[n - 1usize - k])]
        let (lf, lc) = locate(old_off[..n], widths[..n], usize(jop.column))
        edge_leaf[k] = lf
        edge_col[k] = lc
        edge_right[k] = usize(jop.column_b)
        k += 1usize
    }
    var order: [8]u32 = zero
    let (_, oe) = join_order(cards[..n], selectivities, order[..n], cost, best)
    if oe != ok { ret oe }
    var left_leaf: [8]usize = zero
    var left_col: [8]usize = zero
    var right_col: [8]usize = zero
    k = 1usize
    while k < n {
        let (found, ll, lc2, rc) = connecting_edge(order[..n], k, edge_leaf[..n], edge_col[..n], edge_right[..n])
        if !found { ret ok }
        left_leaf[k] = ll
        left_col[k] = lc2
        right_col[k] = rc
        k += 1usize
    }
    var new_off: [8]usize = zero
    var acc = 0usize
    k = 0usize
    while k < n {
        new_off[usize(order[k])] = acc
        acc += widths[usize(order[k])]
        k += 1usize
    }
    k = 1usize
    while k < n {
        let j = usize(joins[n - 1usize - k])
        if k == 1usize { p.plan[j].input_a = leaves[usize(order[0usize])] } else { p.plan[j].input_a = joins[n - k] }
        p.plan[j].input_b = leaves[usize(order[k])]
        p.plan[j].column = u32(new_off[left_leaf[k]] + left_col[k])
        p.plan[j].column_b = u32(right_col[k])
        k += 1usize
    }
    ret remap_above(p, root, top, old_off[..n], widths[..n], new_off[..n])
}

// push_predicates, then (with two or more joins in a left-deep chain) reorder them by
// `join_order`, then push_projections; answers the new root. `selectivities` is n x n over
// the chain's leaves (bottom-left first) and may be empty when the plan has fewer than two
// joins; `cost`/`best` are the DP tables (2^n entries).
fn optimize(p: *Planner, root: u32, selectivities: []const f64, cost: []f64, best: []u32) -> (u32, err) {
    let pushed = push_predicates(p.plan[..p.count], root, p.tables)
    let e = reorder_joins(p, pushed, selectivities, cost, best)
    if e != ok { ret (pushed, e) }
    let ep = push_projections(p, pushed)
    ret (pushed, ep)
}
