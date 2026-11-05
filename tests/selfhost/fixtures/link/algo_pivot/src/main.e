// `e.algo.pivot`: group keys keep a separator inside one value distinct from the same
// text split across fields (#731), and a KPI comparison against a negative baseline
// reports the delta's own sign (#252). `group`/`kpi` select one check for pre-fix
// evidence; both run by default.

use e.algo.formula as f
use e.algo.pivot as pivot
use e.algo.view as view
use e.io
use e.mem
use e.os
use e.str

fn text_cell(name: str, value: str) -> f.Field {
    ret f.Field { name: name, value: f.text(value) }
}

fn number_cell(name: str, value: f64) -> f.Field {
    ret f.Field { name: name, value: f.number(value) }
}

fn field_def(name: str, type_name: str) -> view.FieldDef {
    var d: view.FieldDef = zero
    d.name = name
    d.type_name = type_name
    ret d
}

fn leaf_filter(name: str, op: str, value: str) -> view.Node {
    var n: view.Node = zero
    n.field = name
    n.op = op
    n.type_name = "text"
    n.operand = view.plain_operand(f.text(value))
    ret n
}

fn row_with(fields: []const f.Field) -> view.Row {
    var r: view.Row = zero
    r.fields = fields
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    var mode: str = ""
    if args.len > 1usize { mode = args[1usize] }
    var reg: f.Registry = zero
    var ctx: view.Context = zero
    ctx.user_id = f.blank()
    var no_filter: view.Node = zero
    var defs: [2]view.FieldDef = zero
    defs[0usize] = field_def("a", "text")
    defs[1usize] = field_def("b", "text")
    var group: [2]str = zero
    group[0usize] = "a"
    group[1usize] = "b"
    var no_columns: [0]str = zero

    if mode.len == 0usize || str.eq(mode, "group") {
        // 1: #731. "x / y" as one value and "x", "y / z" as two are different groups,
        // not the same "x / y / z" bucket; a literal separator must not merge them.
        var left: [2]f.Field = zero
        left[0usize] = text_cell("a", "x / y")
        left[1usize] = text_cell("b", "z")
        var right: [2]f.Field = zero
        right[0usize] = text_cell("a", "x")
        right[1usize] = text_cell("b", "y / z")
        var rows: [2]view.Row = zero
        rows[0usize] = row_with(left[0usize..2usize])
        rows[1usize] = row_with(right[0usize..2usize])
        let p = pivot.build_pivot(a, &reg, rows[..], group[..], no_columns[..], pivot.count_series(), false, no_filter, defs[..], &ctx)
        if p.row_keys.len != 2usize { os.exit(1i32) }
        var measures: [1]pivot.Measure = zero
        measures[0usize] = pivot.Measure { series: pivot.count_series(), label: "Count" }
        let report = pivot.summary_report(a, &reg, rows[..], group[..], measures[..], false, no_filter, defs[..], &ctx)
        if report.groups.len != 2usize { os.exit(1i32) }
        if report.groups[0usize].count != 1usize || report.groups[1usize].count != 1usize { os.exit(1i32) }
    }

    if mode.len == 0usize || str.eq(mode, "kpi") {
        // 2: #252. -50 against a -100 baseline is up 50%, not "up -50%": the percent
        // divides by the baseline's magnitude, like the direction divides by its sign.
        var now_cells: [2]f.Field = zero
        now_cells[0usize] = text_cell("tag", "now")
        now_cells[1usize] = number_cell("v", -50.0f64)
        var was_cells: [2]f.Field = zero
        was_cells[0usize] = text_cell("tag", "was")
        was_cells[1usize] = number_cell("v", -100.0f64)
        var krows: [2]view.Row = zero
        krows[0usize] = row_with(now_cells[0usize..2usize])
        krows[1usize] = row_with(was_cells[0usize..2usize])
        var kdefs: [2]view.FieldDef = zero
        kdefs[0usize] = field_def("tag", "text")
        kdefs[1usize] = field_def("v", "number")
        var cfg: pivot.ChartConfig = zero
        cfg.has_filter = true
        cfg.filter = leaf_filter("tag", "is", "now")
        cfg.has_comparison_filter = true
        cfg.comparison_filter = leaf_filter("tag", "is", "was")
        var series: [1]pivot.Series = zero
        series[0usize] = pivot.Series { field: "v", aggregation: "sum", label: "V" }
        cfg.series = series[0usize..1usize]
        let kpi = pivot.build_kpi(a, &reg, krows[..], cfg, kdefs[..], &ctx)
        if !kpi.has_comparison { os.exit(2i32) }
        if !str.eq(kpi.comparison.direction, "up") { os.exit(2i32) }
        if kpi.comparison.percent_delta.none { os.exit(2i32) }
        if kpi.comparison.percent_delta.n != 50.0f64 { os.exit(2i32) }
    }

    try io.print("algo pivot ok")
    ret ok
}
