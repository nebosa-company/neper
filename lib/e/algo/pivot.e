// Aggregation, charts, KPIs and pivots (L032), after appdor's `src/charts/{aggregate,server-aggregate}.js` and
// `src/pivot/index.js` over `e.algo.view`'s filter engine: `aggregate` over a group of rows, the display order of
// an axis (numeric when every key is a number, "no value" last), `build_chart_data` with x buckets, a split field,
// several series and a top-N with an aggregated "Other", `build_kpi` with a comparison and threshold bands,
// `build_pivot` (rows x columns x measure with totals) and `summary_report` (banded sub-summaries), and the
// server-aggregate planner (`plan_aggregate` says why a widget cannot be computed in the database) with the shaping
// of the database's groups into the same chart and KPI payloads.
//
// Differences from appdor's: a measure report's labels are kept in the order given, not as object keys (so
// integer-like labels do not reorder); an aggregation over a key is by value, so two arrays are the same key only
// if the host gives them the same identity (never, here).

use e.algo.formula as f
use e.algo.view as view
use e.math
use e.mem
use e.str

fn is_nan(x: f64) -> bool { ret x != x }

// A number or nothing: the value of an aggregation.
type Cell = struct { n: f64, none: bool }

fn cell(n: f64) -> Cell { ret Cell { n: n, none: false } }

fn no_cell() -> Cell { ret Cell { n: 0.0f64, none: true } }

// What to aggregate and how: `aggregation` empty means `count`, the one that needs no `field`.
type Series = struct { field: str, aggregation: str, label: str }

fn count_series() -> Series { ret Series { field: "", aggregation: "count", label: "" } }

fn aggregation_of(s: Series) -> str {
    if s.aggregation.len == 0usize { ret "count" }
    ret s.aggregation
}

// The numeric values of a column: empties and non-numbers dropped.
fn numbers_of(a: *mem.Arena, vals: []const f.Value, out: []f64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < vals.len {
        if !view.is_empty(vals[i]) {
            let x = view.js_number(a, vals[i])
            if !is_nan(x) {
                out[n] = x
                n += 1usize
            }
        }
        i += 1usize
    }
    ret n
}

// Aggregate a measure over a group of rows (count, countValues, unique, sum, avg, average, min, max, median).
fn aggregate(a: *mem.Arena, rows: []const view.Row, series: Series) -> Cell {
    let agg = aggregation_of(series)
    if str.eq(agg, "count") { ret cell(f64(rows.len)) }
    let (vals, e) = mem.alloc[f.Value](a, rows.len + 1usize)
    if e != ok { ret no_cell() }
    var i = 0usize
    while i < rows.len {
        vals[i] = view.value_at(rows[i], series.field)
        i += 1usize
    }
    let column = vals[0usize..rows.len]
    if str.eq(agg, "countValues") {
        var n = 0usize
        i = 0usize
        while i < rows.len {
            if !view.is_empty(column[i]) { n += 1usize }
            i += 1usize
        }
        ret cell(f64(n))
    }
    if str.eq(agg, "unique") {
        var seen: []f.Value = zero
        let (cells, ce) = mem.alloc[f.Value](a, rows.len + 1usize)
        if ce != ok { ret no_cell() }
        seen = cells
        var n = 0usize
        i = 0usize
        while i < rows.len {
            if !view.is_empty(column[i]) {
                var found = false
                var k = 0usize
                while k < n {
                    if view.same_value(seen[k], column[i]) { found = true }
                    k += 1usize
                }
                if !found {
                    seen[n] = column[i]
                    n += 1usize
                }
            }
            i += 1usize
        }
        ret cell(f64(n))
    }
    let (buffer, be) = mem.alloc[f64](a, rows.len + 1usize)
    if be != ok { ret no_cell() }
    let n = numbers_of(a, column, buffer)
    if str.eq(agg, "sum") {
        var sum = 0.0f64
        i = 0usize
        while i < n {
            sum += buffer[i]
            i += 1usize
        }
        ret cell(sum)
    }
    if str.eq(agg, "avg") || str.eq(agg, "average") {
        if n == 0usize { ret no_cell() }
        var sum = 0.0f64
        i = 0usize
        while i < n {
            sum += buffer[i]
            i += 1usize
        }
        ret cell(sum / f64(n))
    }
    if str.eq(agg, "min") || str.eq(agg, "max") {
        if n == 0usize { ret no_cell() }
        var best = buffer[0usize]
        i = 1usize
        while i < n {
            if (str.eq(agg, "min") && buffer[i] < best) || (str.eq(agg, "max") && buffer[i] > best) { best = buffer[i] }
            i += 1usize
        }
        ret cell(best)
    }
    if str.eq(agg, "median") {
        if n == 0usize { ret no_cell() }
        var x = 1usize
        while x < n {
            let item = buffer[x]
            var y = x
            while y > 0usize && buffer[y - 1usize] > item {
                buffer[y] = buffer[y - 1usize]
                y -= 1usize
            }
            buffer[y] = item
            x += 1usize
        }
        let mid = n / 2usize
        if n % 2usize == 1usize { ret cell(buffer[mid]) }
        ret cell((buffer[mid - 1usize] + buffer[mid]) / 2.0f64)
    }
    ret no_cell()
}


// --- chart data -------------------------------------------------------------------------------------------------

// A group key on an axis: a raw value, "no value", or the aggregated "Other".
type Label = struct { value: f.Value, none: bool, other: bool, pos: usize, origin: usize }

type Threshold = struct { value: f64, has_value: bool, label: str, color: str, icon: str }

type ChartConfig = struct {
    chart_type: str,
    x_field: str,
    x_bucket: view.Bucket,
    split_field: str,
    series: []const Series,
    has_filter: bool,
    filter: view.Node,
    top_n: usize,
    has_comparison_filter: bool,
    comparison_filter: view.Node,
    thresholds: []const Threshold,
}

type Dataset = struct { label: str, has_split: bool, split_none: bool, split_value: f.Value, data: []const Cell }

// What a bar drills into: `Other`, or the x field being a value (null for "no value").
type Drill = struct { other: bool, field: str, value: f.Value, is_null: bool }

type ChartData = struct { chart_type: str, labels: []const str, datasets: []const Dataset, drilldown: []const Drill }

fn label_text(a: *mem.Arena, l: Label) -> str {
    if l.other { ret "Other" }
    if l.none { ret "No value" }
    ret view.js_string(a, l.value)
}

fn same_label(x: Label, y: Label) -> bool {
    if x.other || y.other { ret x.other && y.other }
    if x.none || y.none { ret x.none && y.none }
    // an array or record is the same key only as itself: the row it came from
    if (x.value.kind == .Array || x.value.kind == .Record) || (y.value.kind == .Array || y.value.kind == .Record) {
        ret (x.value.kind == .Array || x.value.kind == .Record) && (y.value.kind == .Array || y.value.kind == .Record) && x.origin == y.origin
    }
    ret view.same_value(x.value, y.value)
}

// The display order of an x axis: numeric when every key is a number, else by UTF-16 code units, "no value" last.
fn sort_labels(a: *mem.Arena, labels: []Label) -> usize {
    var rest = 0usize
    var has_none = false
    var none_label = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize }
    var all_numeric = true
    var i = 0usize
    while i < labels.len {
        if labels[i].none {
            has_none = true
            none_label = labels[i]
        } else {
            rest += 1usize
            if is_nan(view.js_number(a, labels[i].value)) { all_numeric = false }
        }
        i += 1usize
    }
    let (kept, e) = mem.alloc[Label](a, rest + 1usize)
    if e != ok { ret labels.len }
    var n = 0usize
    i = 0usize
    while i < labels.len {
        if !labels[i].none {
            kept[n] = labels[i]
            n += 1usize
        }
        i += 1usize
    }
    var x = 1usize
    while x < n {
        let item = kept[x]
        var y = x
        while y > 0usize && label_after(a, kept[y - 1usize], item, all_numeric) {
            kept[y] = kept[y - 1usize]
            y -= 1usize
        }
        kept[y] = item
        x += 1usize
    }
    i = 0usize
    while i < n {
        labels[i] = kept[i]
        i += 1usize
    }
    if has_none {
        labels[n] = none_label
        n += 1usize
    }
    ret n
}

fn label_after(a: *mem.Arena, left: Label, right: Label, numeric: bool) -> bool {
    if numeric { ret view.js_number(a, left.value) > view.js_number(a, right.value) }
    ret f.compare_utf16(view.js_string(a, left.value), view.js_string(a, right.value)) > 0i32
}

fn series_label(s: Series) -> str {
    if s.label.len > 0usize { ret s.label }
    if s.field.len > 0usize { ret s.field }
    if s.aggregation.len > 0usize { ret s.aggregation }
    ret "count"
}

// Build a chart dataset payload from rows and config.
fn build_chart_data(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, config: ChartConfig, fields: []const view.FieldDef, ctx: *const view.Context) -> ChartData {
    var data_rows = rows
    if config.has_filter { data_rows = view.filter_rows(a, reg, rows, config.filter, true, fields, ctx) }
    let n = data_rows.len
    let (keys, ke) = mem.alloc[Label](a, n + 2usize)
    let (member_of, me) = mem.alloc[usize](a, n + 1usize)
    var no_labels: []const str = zero
    var no_sets: []const Dataset = zero
    var no_drills: []const Drill = zero
    if ke != ok || me != ok { ret ChartData { chart_type: config.chart_type, labels: no_labels, datasets: no_sets, drilldown: no_drills } }
    let bucketed = config.x_bucket.name.len > 0usize || config.x_bucket.has_size
    var key_count = 0usize
    var i = 0usize
    while i < n {
        let raw = view.value_at(data_rows[i], config.x_field)
        var key = Label { value: raw, none: false, other: false, pos: 0usize, origin: i }
        if view.is_empty(raw) {
            key = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize }
        } else if bucketed {
            let (text, is_none) = view.bucket_key(a, raw, config.x_bucket)
            if is_none { key = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize } } else { key = Label { value: f.text(text), none: false, other: false, pos: 0usize, origin: 0usize } }
        }
        var at = key_count
        var found = false
        var k = 0usize
        while k < key_count && !found {
            if same_label(keys[k], key) {
                at = k
                found = true
            }
            k += 1usize
        }
        if !found {
            key.pos = key_count
            keys[key_count] = key
            key_count += 1usize
        }
        member_of[i] = at
        i += 1usize
    }
    // group members in row order, per key position
    let (starts, se) = mem.alloc[usize](a, key_count + 2usize)
    let (order, oe) = mem.alloc[usize](a, n + 1usize)
    if se != ok || oe != ok { ret ChartData { chart_type: config.chart_type, labels: no_labels, datasets: no_sets, drilldown: no_drills } }
    var counts_total = 0usize
    var k = 0usize
    while k < key_count {
        starts[k] = counts_total
        i = 0usize
        while i < n {
            if member_of[i] == k {
                order[counts_total] = i
                counts_total += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    starts[key_count] = counts_total
    // the labels in display order, with the key position each came from
    let (labels, le) = mem.alloc[Label](a, key_count + 2usize)
    if le != ok { ret ChartData { chart_type: config.chart_type, labels: no_labels, datasets: no_sets, drilldown: no_drills } }
    k = 0usize
    while k < key_count {
        labels[k] = keys[k]
        k += 1usize
    }
    var label_count = sort_labels(a, labels[0usize..key_count])
    var primary = count_series()
    if config.series.len > 0usize { primary = config.series[0usize] }
    // the group rows of a label
    var other_members: []usize = zero
    var other_count = 0usize
    var has_other = false
    if config.top_n > 0usize && label_count > config.top_n {
        // rank the real labels by their aggregate, largest first (stable)
        let (ranked, re) = mem.alloc[usize](a, label_count + 1usize)
        let (values, ve) = mem.alloc[f64](a, label_count + 1usize)
        if re == ok && ve == ok {
            var rn = 0usize
            var li = 0usize
            while li < label_count {
                if !labels[li].none {
                    values[li] = 0.0f64
                    let g = group_rows(a, data_rows, order, starts, key_position(keys[0usize..key_count], labels[li]))
                    let c = aggregate(a, g, primary)
                    if !c.none && c.n == c.n { values[li] = c.n }
                    ranked[rn] = li
                    rn += 1usize
                }
                li += 1usize
            }
            var x = 1usize
            while x < rn {
                let item = ranked[x]
                var y = x
                while y > 0usize && values[ranked[y - 1usize]] < values[item] {
                    ranked[y] = ranked[y - 1usize]
                    y -= 1usize
                }
                ranked[y] = item
                x += 1usize
            }
            let (kept_labels, kle) = mem.alloc[Label](a, config.top_n + 2usize)
            let (others, ote) = mem.alloc[usize](a, n + 1usize)
            if kle == ok && ote == ok {
                var kept_n = 0usize
                while kept_n < config.top_n && kept_n < rn {
                    kept_labels[kept_n] = labels[ranked[kept_n]]
                    kept_n += 1usize
                }
                // the rows of every label not kept, in label order
                var li2 = 0usize
                while li2 < label_count {
                    var is_kept = false
                    var kk = 0usize
                    while kk < kept_n {
                        if same_label(kept_labels[kk], labels[li2]) { is_kept = true }
                        kk += 1usize
                    }
                    if !is_kept {
                        let pos = key_position(keys[0usize..key_count], labels[li2])
                        var m = starts[pos]
                        while m < starts[pos + 1usize] {
                            others[other_count] = order[m]
                            other_count += 1usize
                            m += 1usize
                        }
                    }
                    li2 += 1usize
                }
                other_members = others
                has_other = true
                var j = 0usize
                while j < kept_n {
                    labels[j] = kept_labels[j]
                    j += 1usize
                }
                labels[kept_n] = Label { value: f.blank(), none: false, other: true, pos: 0usize, origin: 0usize }
                label_count = kept_n + 1usize
            }
        }
    }
    // each label's rows
    let (label_rows, lre) = mem.alloc[[]const view.Row](a, label_count + 1usize)
    let (label_idx, lie) = mem.alloc[[]const usize](a, label_count + 1usize)
    if lre != ok || lie != ok { ret ChartData { chart_type: config.chart_type, labels: no_labels, datasets: no_sets, drilldown: no_drills } }
    var li = 0usize
    while li < label_count {
        if labels[li].other {
            let (members, mre) = mem.alloc[view.Row](a, other_count + 1usize)
            if mre == ok {
                var m = 0usize
                while m < other_count {
                    members[m] = data_rows[other_members[m]]
                    m += 1usize
                }
                label_rows[li] = members[0usize..other_count]
                label_idx[li] = other_members[0usize..other_count]
            }
        } else {
            let pos = key_position(keys[0usize..key_count], labels[li])
            label_rows[li] = group_rows(a, data_rows, order, starts, pos)
            label_idx[li] = order[starts[pos]..starts[pos + 1usize]]
        }
        li += 1usize
    }
    // datasets
    var dataset_count = 0usize
    var datasets: []Dataset = zero
    if config.split_field.len > 0usize {
        // the split values in first-appearance order over the filtered rows
        let (splits, spe) = mem.alloc[Label](a, n + 1usize)
        var split_count = 0usize
        if spe == ok {
            i = 0usize
            while i < n {
                let raw = view.value_at(data_rows[i], config.split_field)
                var s = Label { value: raw, none: false, other: false, pos: 0usize, origin: i }
                if view.is_empty(raw) { s = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize } }
                var found = false
                var q = 0usize
                while q < split_count {
                    if same_label(splits[q], s) { found = true }
                    q += 1usize
                }
                if !found {
                    splits[split_count] = s
                    split_count += 1usize
                }
                i += 1usize
            }
        }
        let (sets, de) = mem.alloc[Dataset](a, split_count + 1usize)
        if de == ok {
            datasets = sets
            var s = 0usize
            while s < split_count {
                let (cells, ce) = mem.alloc[Cell](a, label_count + 1usize)
                if ce == ok {
                    var li3 = 0usize
                    while li3 < label_count {
                        // this label's rows whose split value is s (an array or record is its own row's)
                        let members = label_idx[li3]
                        let (part, pe) = mem.alloc[view.Row](a, members.len + 1usize)
                        var pn = 0usize
                        if pe == ok {
                            var r = 0usize
                            while r < members.len {
                                let raw = view.value_at(data_rows[members[r]], config.split_field)
                                var rs = Label { value: raw, none: false, other: false, pos: 0usize, origin: members[r] }
                                if view.is_empty(raw) { rs = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize } }
                                if same_label(rs, splits[s]) {
                                    part[pn] = data_rows[members[r]]
                                    pn += 1usize
                                }
                                r += 1usize
                            }
                        }
                        cells[li3] = aggregate(a, part[0usize..pn], primary)
                        li3 += 1usize
                    }
                    datasets[s] = Dataset { label: label_text(a, splits[s]), has_split: true, split_none: splits[s].none, split_value: splits[s].value, data: cells[0usize..label_count] }
                }
                s += 1usize
            }
            dataset_count = split_count
        }
    } else {
        var list = config.series
        var single: [1]Series = zero
        if list.len == 0usize {
            single[0usize] = count_series()
            list = single[0..]
        }
        let (sets, de) = mem.alloc[Dataset](a, list.len + 1usize)
        if de == ok {
            datasets = sets
            var s = 0usize
            while s < list.len {
                let (cells, ce) = mem.alloc[Cell](a, label_count + 1usize)
                if ce == ok {
                    var li3 = 0usize
                    while li3 < label_count {
                        cells[li3] = aggregate(a, label_rows[li3], list[s])
                        li3 += 1usize
                    }
                    datasets[s] = Dataset { label: series_label(list[s]), has_split: false, split_none: false, split_value: f.blank(), data: cells[0usize..label_count] }
                }
                s += 1usize
            }
            dataset_count = list.len
        }
    }
    let (texts, te) = mem.alloc[str](a, label_count + 1usize)
    let (drills, de2) = mem.alloc[Drill](a, label_count + 1usize)
    if te != ok || de2 != ok { ret ChartData { chart_type: config.chart_type, labels: no_labels, datasets: datasets[0usize..dataset_count], drilldown: no_drills } }
    li = 0usize
    while li < label_count {
        texts[li] = label_text(a, labels[li])
        if labels[li].other {
            drills[li] = Drill { other: true, field: "", value: f.blank(), is_null: false }
        } else if labels[li].none {
            drills[li] = Drill { other: false, field: config.x_field, value: f.blank(), is_null: true }
        } else {
            drills[li] = Drill { other: false, field: config.x_field, value: labels[li].value, is_null: false }
        }
        li += 1usize
    }
    ret ChartData { chart_type: config.chart_type, labels: texts[0usize..label_count], datasets: datasets[0usize..dataset_count], drilldown: drills[0usize..label_count] }
}


// The position of a label among the group keys.
fn key_position(keys: []const Label, label: Label) -> usize { ret label.pos }

// The rows of the group at key position `pos`, in row order.
fn group_rows(a: *mem.Arena, rows: []const view.Row, order: []const usize, starts: []const usize, pos: usize) -> []const view.Row {
    let count = starts[pos + 1usize] - starts[pos]
    let (out, e) = mem.alloc[view.Row](a, count + 1usize)
    if e != ok { ret rows }
    var i = 0usize
    while i < count {
        out[i] = rows[order[starts[pos] + i]]
        i += 1usize
    }
    ret out[0usize..count]
}

// --- KPI ----------------------------------------------------------------------------------------------------------

type Band = struct { label: str, color: str, icon: str, band: usize }

// Which threshold band a finished value falls in (the highest threshold at or below it), or false.
fn evaluate_thresholds(a: *mem.Arena, value: Cell, thresholds: []const Threshold) -> (Band, bool) {
    var none: Band = zero
    if thresholds.len == 0usize { ret (none, false) }
    var v = 0.0f64
    if !value.none { v = value.n }
    if is_nan(v) { ret (none, false) }
    // descending by value, stable; the original index travels with each entry
    let (idx, e) = mem.alloc[usize](a, thresholds.len)
    if e != ok { ret (none, false) }
    var i = 0usize
    while i < thresholds.len {
        idx[i] = i
        i += 1usize
    }
    var x = 1usize
    while x < thresholds.len {
        let item = idx[x]
        var y = x
        while y > 0usize && threshold_value(thresholds[idx[y - 1usize]]) < threshold_value(thresholds[item]) {
            idx[y] = idx[y - 1usize]
            y -= 1usize
        }
        idx[y] = item
        x += 1usize
    }
    i = 0usize
    while i < thresholds.len {
        let t = thresholds[idx[i]]
        if v >= threshold_value(t) {
            var color = t.color
            if color.len == 0usize { color = "#6b7280" }
            ret (Band { label: t.label, color: color, icon: t.icon, band: idx[i] }, true)
        }
        i += 1usize
    }
    ret (none, false)
}

fn threshold_value(t: Threshold) -> f64 {
    if !t.has_value || is_nan(t.value) { ret 0.0f64 }
    ret t.value
}

type Comparison = struct { value: Cell, delta: f64, percent_delta: Cell, direction: str }

type Kpi = struct { value: Cell, row_count: usize, has_comparison: bool, comparison: Comparison, has_threshold: bool, threshold: Band }

// One aggregate over a filtered set, with an optional comparison over a second filter and a threshold band.
fn build_kpi(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, config: ChartConfig, fields: []const view.FieldDef, ctx: *const view.Context) -> Kpi {
    var data_rows = rows
    if config.has_filter { data_rows = view.filter_rows(a, reg, rows, config.filter, true, fields, ctx) }
    var series = count_series()
    if config.series.len > 0usize { series = config.series[0usize] }
    let value = aggregate(a, data_rows, series)
    var out: Kpi = zero
    out.value = value
    out.row_count = data_rows.len
    if config.has_comparison_filter {
        let compare_rows = view.filter_rows(a, reg, rows, config.comparison_filter, true, fields, ctx)
        let compare = aggregate(a, compare_rows, series)
        var left = 0.0f64
        if !value.none && value.n != 0.0f64 { left = value.n }
        var right = 0.0f64
        if !compare.none && compare.n != 0.0f64 { right = compare.n }
        let delta = left - right
        var percent = no_cell()
        if !compare.none && compare.n != 0.0f64 { percent = cell(delta / compare.n * 100.0f64) }
        var direction = "flat"
        if delta > 0.0f64 { direction = "up" }
        if delta < 0.0f64 { direction = "down" }
        out.has_comparison = true
        out.comparison = Comparison { value: compare, delta: delta, percent_delta: percent, direction: direction }
    }
    let (band, has_band) = evaluate_thresholds(a, value, config.thresholds)
    out.has_threshold = has_band
    out.threshold = band
    ret out
}

// --- pivots and summary reports -----------------------------------------------------------------------------------

fn empty_mark() -> str { ret "\xe2\x88\x85" }

// The key of a row over a list of fields: each value as text (an empty one the empty set sign), joined by " / ".
fn key_of(a: *mem.Arena, row: view.Row, names: []const str) -> str {
    var out = ""
    var i = 0usize
    while i < names.len {
        if i > 0usize { out = f.join(a, out, " / ") }
        let v = view.value_at(row, names[i])
        if view.is_empty(v) { out = f.join(a, out, empty_mark()) } else { out = f.join(a, out, view.js_string(a, v)) }
        i += 1usize
    }
    ret out
}

// Pivot and report keys: those not ending in the empty mark, numeric when all are numbers else by code units, then
// the ones that do (in the order given).
fn sort_keys(a: *mem.Arena, keys: []str) {
    let (rest, e) = mem.alloc[str](a, keys.len + 1usize)
    let (empties, ee) = mem.alloc[str](a, keys.len + 1usize)
    if e != ok || ee != ok { ret }
    var rn = 0usize
    var en = 0usize
    var all_numeric = true
    var i = 0usize
    while i < keys.len {
        if str.eq(keys[i], empty_mark()) || str.ends_with(keys[i], empty_mark()) {
            empties[en] = keys[i]
            en += 1usize
        } else {
            rest[rn] = keys[i]
            rn += 1usize
            if is_nan(view.js_number(a, f.text(keys[i]))) { all_numeric = false }
        }
        i += 1usize
    }
    var x = 1usize
    while x < rn {
        let item = rest[x]
        var y = x
        while y > 0usize {
            var after = false
            if all_numeric {
                after = view.js_number(a, f.text(rest[y - 1usize])) > view.js_number(a, f.text(item))
            } else {
                after = f.compare_utf16(rest[y - 1usize], item) > 0i32
            }
            if !after { break }
            rest[y] = rest[y - 1usize]
            y -= 1usize
        }
        rest[y] = item
        x += 1usize
    }
    var w = 0usize
    i = 0usize
    while i < rn {
        keys[w] = rest[i]
        w += 1usize
        i += 1usize
    }
    i = 0usize
    while i < en {
        keys[w] = empties[i]
        w += 1usize
        i += 1usize
    }
}

type PivotRow = struct { key: str, cells: []const Cell, total: Cell }

type Pivot = struct {
    row_keys: []const str,
    column_keys: []const str,
    rows: []const PivotRow,
    column_totals: []const Cell,
    grand_total: Cell,
}

// A pivot: row keys x column keys over one measure, with row, column and grand totals.
fn build_pivot(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, row_fields: []const str, column_fields: []const str, measure: Series, has_filter: bool, filter: view.Node, fields: []const view.FieldDef, ctx: *const view.Context) -> Pivot {
    var data = rows
    if has_filter { data = view.filter_rows(a, reg, rows, filter, true, fields, ctx) }
    let n = data.len
    var empty_keys: []const str = zero
    var empty_rows: []const PivotRow = zero
    var empty_cells: []const Cell = zero
    let (row_key_of, re) = mem.alloc[str](a, n + 1usize)
    let (col_key_of, ce) = mem.alloc[str](a, n + 1usize)
    let (row_keys, rke) = mem.alloc[str](a, n + 1usize)
    let (col_keys, cke) = mem.alloc[str](a, n + 1usize)
    if re != ok || ce != ok || rke != ok || cke != ok { ret Pivot { row_keys: empty_keys, column_keys: empty_keys, rows: empty_rows, column_totals: empty_cells, grand_total: no_cell() } }
    var rkn = 0usize
    var ckn = 0usize
    var i = 0usize
    while i < n {
        var rk = "Total"
        if row_fields.len > 0usize { rk = key_of(a, data[i], row_fields) }
        var ck = "Total"
        if column_fields.len > 0usize { ck = key_of(a, data[i], column_fields) }
        row_key_of[i] = rk
        col_key_of[i] = ck
        var found = false
        var k = 0usize
        while k < rkn && !found {
            if str.eq(row_keys[k], rk) { found = true }
            k += 1usize
        }
        if !found {
            row_keys[rkn] = rk
            rkn += 1usize
        }
        found = false
        k = 0usize
        while k < ckn && !found {
            if str.eq(col_keys[k], ck) { found = true }
            k += 1usize
        }
        if !found {
            col_keys[ckn] = ck
            ckn += 1usize
        }
        i += 1usize
    }
    sort_keys(a, row_keys[0usize..rkn])
    sort_keys(a, col_keys[0usize..ckn])
    let (pivot_rows, pre) = mem.alloc[PivotRow](a, rkn + 1usize)
    let (column_totals, cte) = mem.alloc[Cell](a, ckn + 1usize)
    if pre != ok || cte != ok { ret Pivot { row_keys: empty_keys, column_keys: empty_keys, rows: empty_rows, column_totals: empty_cells, grand_total: no_cell() } }
    var r = 0usize
    while r < rkn {
        let (cells, cee) = mem.alloc[Cell](a, ckn + 1usize)
        if cee != ok { ret Pivot { row_keys: empty_keys, column_keys: empty_keys, rows: empty_rows, column_totals: empty_cells, grand_total: no_cell() } }
        var c = 0usize
        while c < ckn {
            cells[c] = aggregate(a, rows_where(a, data, row_key_of, col_key_of, row_keys[r], true, col_keys[c], true), measure)
            c += 1usize
        }
        pivot_rows[r] = PivotRow { key: row_keys[r], cells: cells[0usize..ckn], total: aggregate(a, rows_where(a, data, row_key_of, col_key_of, row_keys[r], true, "", false), measure) }
        r += 1usize
    }
    var c2 = 0usize
    while c2 < ckn {
        column_totals[c2] = aggregate(a, rows_where(a, data, row_key_of, col_key_of, "", false, col_keys[c2], true), measure)
        c2 += 1usize
    }
    ret Pivot { row_keys: row_keys[0usize..rkn], column_keys: col_keys[0usize..ckn], rows: pivot_rows[0usize..rkn], column_totals: column_totals[0usize..ckn], grand_total: aggregate(a, data, measure) }
}

// The rows with a given row key and/or column key.
fn rows_where(a: *mem.Arena, data: []const view.Row, row_keys: []const str, col_keys: []const str, row_key: str, by_row: bool, col_key: str, by_col: bool) -> []const view.Row {
    let (out, e) = mem.alloc[view.Row](a, data.len + 1usize)
    if e != ok { ret data }
    var n = 0usize
    var i = 0usize
    while i < data.len {
        if (!by_row || str.eq(row_keys[i], row_key)) && (!by_col || str.eq(col_keys[i], col_key)) {
            out[n] = data[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

type Measure = struct { series: Series, label: str }

fn measure_label(m: Measure) -> str {
    if m.label.len > 0usize { ret m.label }
    if m.series.field.len > 0usize { ret m.series.field }
    ret aggregation_of(m.series)
}

type Band2 = struct { key: str, count: usize, values: []const Cell }

type Report = struct { labels: []const str, groups: []const Band2, grand_total: []const Cell, total: usize }

// A grouped sub-summary report: one band per group-by key (sorted as pivot keys are), each carrying the measures.
fn summary_report(a: *mem.Arena, reg: *const f.Registry, rows: []const view.Row, group_by: []const str, measures: []const Measure, has_filter: bool, filter: view.Node, fields: []const view.FieldDef, ctx: *const view.Context) -> Report {
    var data = rows
    if has_filter { data = view.filter_rows(a, reg, rows, filter, true, fields, ctx) }
    let n = data.len
    var list = measures
    var single: [1]Measure = zero
    if list.len == 0usize {
        single[0usize] = Measure { series: count_series(), label: "Count" }
        list = single[0..]
    }
    var none_labels: []const str = zero
    var none_bands: []const Band2 = zero
    var none_cells: []const Cell = zero
    let (key_of_row, ke) = mem.alloc[str](a, n + 1usize)
    let (keys, kse) = mem.alloc[str](a, n + 1usize)
    let (labels, le) = mem.alloc[str](a, list.len + 1usize)
    if ke != ok || kse != ok || le != ok { ret Report { labels: none_labels, groups: none_bands, grand_total: none_cells, total: 0usize } }
    var key_count = 0usize
    var i = 0usize
    while i < n {
        var key = "All"
        if group_by.len > 0usize { key = key_of(a, data[i], group_by) }
        key_of_row[i] = key
        var found = false
        var k = 0usize
        while k < key_count && !found {
            if str.eq(keys[k], key) { found = true }
            k += 1usize
        }
        if !found {
            keys[key_count] = key
            key_count += 1usize
        }
        i += 1usize
    }
    sort_keys(a, keys[0usize..key_count])
    var m = 0usize
    while m < list.len {
        labels[m] = measure_label(list[m])
        m += 1usize
    }
    let (bands, be) = mem.alloc[Band2](a, key_count + 1usize)
    let (grand, ge) = mem.alloc[Cell](a, list.len + 1usize)
    if be != ok || ge != ok { ret Report { labels: none_labels, groups: none_bands, grand_total: none_cells, total: 0usize } }
    var g = 0usize
    while g < key_count {
        let members = rows_where(a, data, key_of_row, key_of_row, keys[g], true, "", false)
        let (values, ve) = mem.alloc[Cell](a, list.len + 1usize)
        if ve != ok { ret Report { labels: none_labels, groups: none_bands, grand_total: none_cells, total: 0usize } }
        m = 0usize
        while m < list.len {
            values[m] = aggregate(a, members, list[m].series)
            m += 1usize
        }
        bands[g] = Band2 { key: keys[g], count: members.len, values: values[0usize..list.len] }
        g += 1usize
    }
    m = 0usize
    while m < list.len {
        grand[m] = aggregate(a, data, list[m].series)
        m += 1usize
    }
    ret Report { labels: labels[0usize..list.len], groups: bands[0usize..key_count], grand_total: grand[0usize..list.len], total: n }
}

// --- server-side aggregation: planning and shaping ------------------------------------------------------------------

// A filter condition as the database route takes it.
type Condition = struct {
    field: str,
    op: str,
    type_name: str,
    value: str,
    has_value: bool,
    is_bucket: bool,
    bucket: str,
    has_bucket: bool,
    bucket_value: f.Value,
    bucket_values: []const f.Value,
}

type Flattened = struct { usable: bool, reason: str, conditions: []const Condition }

fn server_ops(family: str) -> str {
    if str.eq(family, "number") { ret "= != < <= > >= isEmpty isNotEmpty" }
    if str.eq(family, "select") { ret "is isNot isEmpty isNotEmpty" }
    ret "contains notContains is isNot startsWith endsWith isEmpty isNotEmpty"
}

// The operator family of a field type, or empty when the route has none for it.
fn op_family(type_name: str) -> str {
    if str.eq(type_name, "number") || str.eq(type_name, "currency") || str.eq(type_name, "percent") || str.eq(type_name, "rating") { ret "number" }
    if str.eq(type_name, "select") || str.eq(type_name, "user") { ret "select" }
    if type_name.len == 0usize || str.eq(type_name, "text") || str.eq(type_name, "longtext") { ret "text" }
    ret ""
}

fn flatten_into(node: view.Node, out: []view.Node, n: usize) -> usize {
    if str.eq(node.operator, "and") {
        var count = n
        var i = 0usize
        while i < node.children.len {
            count = flatten_into(node.children[i], out, count)
            i += 1usize
        }
        ret count
    }
    if n < out.len { out[n] = node }
    ret n + 1usize
}

fn node_total(node: view.Node) -> usize {
    var n = 1usize
    var i = 0usize
    while i < node.children.len {
        n += node_total(node.children[i])
        i += 1usize
    }
    ret n
}

fn refuse(reason: str) -> Flattened {
    var none: []const Condition = zero
    ret Flattened { usable: false, reason: reason, conditions: none }
}

// A widget's filter as the flat AND-list the database route accepts, or the reason it cannot be.
fn flatten_filter(a: *mem.Arena, has_filter: bool, filter: view.Node) -> Flattened {
    var none: []const Condition = zero
    if !has_filter { ret Flattened { usable: true, reason: "", conditions: none } }
    let (parts, pe) = mem.alloc[view.Node](a, node_total(filter) + 1usize)
    if pe != ok { ret refuse("not_a_condition") }
    let count = flatten_into(filter, parts, 0usize)
    let (out, e) = mem.alloc[Condition](a, count + 1usize)
    if e != ok { ret refuse("not_a_condition") }
    var n = 0usize
    var i = 0usize
    while i < count {
        let raw = parts[i]
        i += 1usize
        if view.is_group(raw) { ret refuse("nested_group") }
        if raw.expr.len > 0usize { ret refuse("formula_condition") }
        if str.eq(raw.op, "inBucket") || str.eq(raw.op, "notInBuckets") {
            var bucket = raw.bucket.name
            var has_bucket = raw.bucket.name.len > 0usize
            if raw.bucket.has_size {
                bucket = f.number_text(a, raw.bucket.size)
                has_bucket = true
            }
            out[n] = Condition { field: raw.field, op: raw.op, type_name: raw.type_name, value: "", has_value: false, is_bucket: true, bucket: bucket, has_bucket: has_bucket, bucket_value: raw.operand.value, bucket_values: raw.values }
            n += 1usize
            continue
        }
        let family = op_family(raw.type_name)
        if family.len == 0usize { ret refuse("unsupported_type") }
        if !view.op_known(server_ops(family), raw.op) { ret refuse("unsupported_operator") }
        let nullary = str.eq(raw.op, "isEmpty") || str.eq(raw.op, "isNotEmpty")
        let v = raw.operand.value
        if !nullary && (!raw.operand.present || v.kind == .Blank || (v.kind == .Text && v.s.len == 0usize)) { ret refuse("no_value") }
        var type_name = raw.type_name
        if type_name.len == 0usize { type_name = "text" }
        if nullary {
            out[n] = Condition { field: raw.field, op: raw.op, type_name: type_name, value: "", has_value: false, is_bucket: false, bucket: "", has_bucket: false, bucket_value: f.blank(), bucket_values: f.zero_items() }
        } else {
            out[n] = Condition { field: raw.field, op: raw.op, type_name: type_name, value: view.js_string(a, v), has_value: true, is_bucket: false, bucket: "", has_bucket: false, bucket_value: f.blank(), bucket_values: f.zero_items() }
        }
        n += 1usize
    }
    ret Flattened { usable: true, reason: "", conditions: out[0usize..n] }
}

// What to plan: the widget's effective config.
type PlanConfig = struct {
    table_id: str,
    series: []const Series,
    aggregation: str,
    field: str,
    measure_field: str,
    x_field: str,
    x_bucket: view.Bucket,
    x_bucket_invalid: bool,
    x_bucket_size_text: str,
    split_field: str,
    top_n: usize,
    has_comparison_filter: bool,
    has_filter: bool,
    filter: view.Node,
}

type PlanArgs = struct {
    table_id: str,
    x_field: str,
    has_x_field: bool,
    x_bucket: str,
    has_x_bucket: bool,
    aggregation: str,
    measure_field: str,
    has_measure_field: bool,
    split_field: str,
    has_split_field: bool,
    conditions: []const Condition,
    limit: usize,
}

type Plan = struct { usable: bool, reason: str, args: PlanArgs }

fn server_aggregation(name: str) -> bool {
    ret str.eq(name, "count") || str.eq(name, "countValues") || str.eq(name, "unique") || str.eq(name, "sum") || str.eq(name, "avg") || str.eq(name, "average") || str.eq(name, "min") || str.eq(name, "max")
}

fn additive(name: str) -> bool { ret str.eq(name, "count") || str.eq(name, "countValues") || str.eq(name, "sum") }

fn plan_refusal(reason: str) -> Plan {
    var none: PlanArgs = zero
    ret Plan { usable: false, reason: reason, args: none }
}

// Can the widget's numbers be computed in the database, and with what call? `kind` is `chart` or `kpi`.
fn plan_aggregate(a: *mem.Arena, config: PlanConfig, kind: str) -> Plan {
    if config.table_id.len == 0usize { ret plan_refusal("no_table") }
    let chart = str.eq(kind, "chart")
    var aggregation = "count"
    var measure_field = ""
    var has_series = config.series.len > 0usize
    if has_series && config.series[0usize].aggregation.len > 0usize {
        aggregation = config.series[0usize].aggregation
    } else if config.aggregation.len > 0usize {
        aggregation = config.aggregation
    }
    if !server_aggregation(aggregation) { ret plan_refusal("unsupported_aggregation") }
    if has_series && config.series[0usize].field.len > 0usize {
        measure_field = config.series[0usize].field
    } else if config.field.len > 0usize {
        measure_field = config.field
    } else {
        measure_field = config.measure_field
    }
    if !str.eq(aggregation, "count") && measure_field.len == 0usize { ret plan_refusal("no_measure_field") }
    if chart && config.series.len > 1usize { ret plan_refusal("multi_series") }
    if chart && config.x_field.len == 0usize { ret plan_refusal("no_x_field") }
    if config.top_n > 0usize && !additive(aggregation) { ret plan_refusal("top_n_not_additive") }
    if !chart && config.has_comparison_filter { ret plan_refusal("comparison") }
    let flat = flatten_filter(a, config.has_filter, config.filter)
    if !flat.usable { ret plan_refusal(flat.reason) }
    var bucket = ""
    var has_bucket = false
    if config.x_bucket_invalid { ret plan_refusal("unsupported_bucket") }
    if config.x_bucket.name.len > 0usize {
        bucket = config.x_bucket.name
        has_bucket = true
    } else if config.x_bucket.has_size {
        bucket = config.x_bucket_size_text
        has_bucket = true
    }
    var args: PlanArgs = zero
    args.table_id = config.table_id
    if chart {
        args.x_field = config.x_field
        args.has_x_field = true
    }
    args.x_bucket = bucket
    args.has_x_bucket = has_bucket
    args.aggregation = aggregation
    args.measure_field = measure_field
    args.has_measure_field = measure_field.len > 0usize
    if chart && config.split_field.len > 0usize {
        args.split_field = config.split_field
        args.has_split_field = true
    }
    args.conditions = flat.conditions
    args.limit = 5000usize
    ret Plan { usable: true, reason: "", args: args }
}

// One group as the route returns it: bucket and split text (or none), the measure, and how many rows.
type Group = struct { bucket: str, has_bucket: bool, split: str, has_split: bool, measure: Cell, row_count: f64 }

type ServerChart = struct { data: ChartData, total: f64 }

fn group_bucket(g: Group) -> str {
    if g.has_bucket { ret g.bucket }
    ret view.no_value()
}

fn group_split(g: Group) -> str {
    if g.has_split { ret g.split }
    ret view.no_value()
}

fn text_label(key: str) -> str {
    if str.eq(key, view.no_value()) { ret "No value" }
    ret key
}

// Shape the database's groups into `build_chart_data`'s payload (labels ordered as the axis orders them, top-N
// folded into Other, one dataset per split).
fn chart_data_from_groups(a: *mem.Arena, groups: []const Group, config: PlanConfig, chart_type: str) -> ServerChart {
    var no_texts: []const str = zero
    var no_sets: []const Dataset = zero
    var no_drills: []const Drill = zero
    let failed = ServerChart { data: ChartData { chart_type: chart_type, labels: no_texts, datasets: no_sets, drilldown: no_drills }, total: 0.0f64 }
    var aggregation = "count"
    if config.series.len > 0usize && config.series[0usize].aggregation.len > 0usize {
        aggregation = config.series[0usize].aggregation
    } else if config.aggregation.len > 0usize {
        aggregation = config.aggregation
    }
    let additive_agg = additive(aggregation)
    let (labels, le) = mem.alloc[Label](a, groups.len + 2usize)
    if le != ok { ret failed }
    var label_count = 0usize
    var i = 0usize
    while i < groups.len {
        let b = group_bucket(groups[i])
        var found = false
        var k = 0usize
        while k < label_count && !found {
            if !labels[k].none && str.eq(labels[k].value.s, b) { found = true }
            if labels[k].none && str.eq(b, view.no_value()) { found = true }
            k += 1usize
        }
        if !found {
            if str.eq(b, view.no_value()) {
                labels[label_count] = Label { value: f.blank(), none: true, other: false, pos: 0usize, origin: 0usize }
            } else {
                labels[label_count] = Label { value: f.text(b), none: false, other: false, pos: 0usize, origin: 0usize }
            }
            label_count += 1usize
        }
        i += 1usize
    }
    label_count = sort_labels(a, labels[0usize..label_count])
    // top-N, folded rather than re-aggregated: the buckets that are not kept form "Other"
    var dropped_keys: []str = zero
    var dropped_count = 0usize
    if config.top_n > 0usize && label_count > config.top_n {
        let (values, ve) = mem.alloc[f64](a, label_count + 1usize)
        let (ranked, re) = mem.alloc[usize](a, label_count + 1usize)
        let (drops, de) = mem.alloc[str](a, label_count + 1usize)
        let (kept, ke) = mem.alloc[Label](a, config.top_n + 2usize)
        if ve == ok && re == ok && de == ok && ke == ok {
            var rn = 0usize
            var li = 0usize
            while li < label_count {
                if !labels[li].none {
                    var sum = 0.0f64
                    var g = 0usize
                    while g < groups.len {
                        if groups[g].has_bucket && str.eq(groups[g].bucket, labels[li].value.s) && !groups[g].measure.none { sum += groups[g].measure.n }
                        g += 1usize
                    }
                    values[li] = sum
                    ranked[rn] = li
                    rn += 1usize
                }
                li += 1usize
            }
            var x = 1usize
            while x < rn {
                let item = ranked[x]
                var y = x
                while y > 0usize && values[ranked[y - 1usize]] < values[item] {
                    ranked[y] = ranked[y - 1usize]
                    y -= 1usize
                }
                ranked[y] = item
                x += 1usize
            }
            var kn = 0usize
            while kn < config.top_n && kn < rn {
                kept[kn] = labels[ranked[kn]]
                kn += 1usize
            }
            li = 0usize
            while li < label_count {
                var is_kept = false
                var q = 0usize
                while q < kn {
                    if same_label(kept[q], labels[li]) { is_kept = true }
                    q += 1usize
                }
                if !is_kept {
                    if labels[li].none { drops[dropped_count] = view.no_value() } else { drops[dropped_count] = labels[li].value.s }
                    dropped_count += 1usize
                }
                li += 1usize
            }
            var j = 0usize
            while j < kn {
                labels[j] = kept[j]
                j += 1usize
            }
            labels[kn] = Label { value: f.blank(), none: false, other: true, pos: 0usize, origin: 0usize }
            label_count = kn + 1usize
            dropped_keys = drops
        }
    }
    let (texts, te) = mem.alloc[str](a, label_count + 1usize)
    let (drills, dre) = mem.alloc[Drill](a, label_count + 1usize)
    if te != ok || dre != ok { ret failed }
    var li2 = 0usize
    while li2 < label_count {
        texts[li2] = label_text(a, labels[li2])
        if labels[li2].other {
            drills[li2] = Drill { other: true, field: "", value: f.blank(), is_null: false }
        } else if labels[li2].none {
            drills[li2] = Drill { other: false, field: config.x_field, value: f.blank(), is_null: true }
        } else {
            drills[li2] = Drill { other: false, field: config.x_field, value: labels[li2].value, is_null: false }
        }
        li2 += 1usize
    }
    var datasets: []Dataset = zero
    var dataset_count = 0usize
    if config.split_field.len > 0usize {
        // the splits in the order the route returned them
        let (splits, spe) = mem.alloc[str](a, groups.len + 1usize)
        if spe != ok { ret failed }
        var sn = 0usize
        var g = 0usize
        while g < groups.len {
            let s = group_split(groups[g])
            var found = false
            var q = 0usize
            while q < sn {
                if str.eq(splits[q], s) { found = true }
                q += 1usize
            }
            if !found {
                splits[sn] = s
                sn += 1usize
            }
            g += 1usize
        }
        let (sets, de) = mem.alloc[Dataset](a, sn + 1usize)
        if de != ok { ret failed }
        datasets = sets
        var s = 0usize
        while s < sn {
            let (cells, ce) = mem.alloc[Cell](a, label_count + 1usize)
            if ce != ok { ret failed }
            var l = 0usize
            while l < label_count {
                cells[l] = server_cell(groups, labels[l], true, splits[s], dropped_keys[0usize..dropped_count], additive_agg)
                l += 1usize
            }
            var split_value = f.text(splits[s])
            var split_none = false
            if str.eq(splits[s], view.no_value()) {
                split_none = true
                split_value = f.blank()
            }
            datasets[s] = Dataset { label: text_label(splits[s]), has_split: true, split_none: split_none, split_value: split_value, data: cells[0usize..label_count] }
            s += 1usize
        }
        dataset_count = sn
    } else {
        let (sets, de) = mem.alloc[Dataset](a, 2usize)
        let (cells, ce) = mem.alloc[Cell](a, label_count + 1usize)
        if de != ok || ce != ok { ret failed }
        datasets = sets
        var l = 0usize
        while l < label_count {
            cells[l] = server_cell(groups, labels[l], false, "", dropped_keys[0usize..dropped_count], additive_agg)
            l += 1usize
        }
        var series = count_series()
        if config.series.len > 0usize { series = config.series[0usize] }
        datasets[0usize] = Dataset { label: series_label(series), has_split: false, split_none: false, split_value: f.blank(), data: cells[0usize..label_count] }
        dataset_count = 1usize
    }
    var total = 0.0f64
    var t = 0usize
    while t < groups.len {
        total += groups[t].row_count
        t += 1usize
    }
    ret ServerChart { data: ChartData { chart_type: chart_type, labels: texts[0usize..label_count], datasets: datasets[0usize..dataset_count], drilldown: drills[0usize..label_count] }, total: total }
}

// The measure for one (label, split) pair; Other folds the dropped buckets. A group the route did not return has no
// rows: an additive aggregation answers 0 for it and the rest nothing.
fn server_cell(groups: []const Group, label: Label, by_split: bool, split: str, dropped: []const str, additive_agg: bool) -> Cell {
    var found = 0usize
    var sum = 0.0f64
    var first = no_cell()
    var g = 0usize
    while g < groups.len {
        var in_label = false
        let b = group_bucket(groups[g])
        if label.other {
            var q = 0usize
            while q < dropped.len {
                if str.eq(dropped[q], b) { in_label = true }
                q += 1usize
            }
        } else if label.none {
            in_label = !groups[g].has_bucket
        } else {
            in_label = groups[g].has_bucket && str.eq(b, label.value.s)
        }
        if in_label && (!by_split || str.eq(group_split(groups[g]), split)) {
            if found == 0usize { first = groups[g].measure }
            found += 1usize
            if !groups[g].measure.none { sum += groups[g].measure.n }
        }
        g += 1usize
    }
    if found == 0usize {
        if additive_agg { ret cell(0.0f64) }
        ret no_cell()
    }
    if !label.other && found == 1usize { ret first }
    ret cell(sum)
}

type ServerKpi = struct { value: Cell, row_count: f64, has_threshold: bool, threshold: Band }

// The same for a KPI: one number over the whole table (no groups means no rows matched).
fn kpi_from_groups(a: *mem.Arena, groups: []const Group, aggregation: str, thresholds: []const Threshold) -> ServerKpi {
    var row_count = 0.0f64
    var i = 0usize
    while i < groups.len {
        row_count += groups[i].row_count
        i += 1usize
    }
    var value = no_cell()
    if groups.len == 0usize {
        if additive(aggregation) { value = cell(0.0f64) }
    } else if groups.len == 1usize {
        value = groups[0usize].measure
    } else {
        var sum = 0.0f64
        i = 0usize
        while i < groups.len {
            if !groups[i].measure.none { sum += groups[i].measure.n }
            i += 1usize
        }
        value = cell(sum)
    }
    let (band, has_band) = evaluate_thresholds(a, value, thresholds)
    ret ServerKpi { value: value, row_count: row_count, has_threshold: has_band, threshold: band }
}
