// A failed allocation for a quoted SQL column must fail the compiler state;
// falling back to the raw identifier would allow syntax from the schema into SQL.
use e.algo.formula as formula
use e.algo.formula.sql as sql
use e.mem
use e.os
use e.str

fn main() {
    var storage: [1]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var fields: [1]sql.Column = zero
    fields[0usize] = sql.Column { name: "Field", field_type: "text", column: "unsafe\"column" }
    var no_params: []formula.Value = zero
    var c = sql.Comp {
        a: &arena,
        reg: zero,
        schema: fields[0..],
        double_quote: true,
        params: no_params,
        param_count: 0usize,
        failed: false,
        oversize: false,
    }
    let (part, found) = sql.field_part(&c, "Field")
    if !c.failed || found || part.sql.len != 0usize || !str.eq(part.pushdown, "none") { os.exit(1) }
    os.exit(0)
}
