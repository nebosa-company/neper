// Observability export over the values `e.metrics` and `e.trace` produce: the Prometheus text
// exposition (format 0.0.4) and the OpenMetrics text exposition of a list of samples, a scrape
// negotiation helper for an HTTP handler, OTLP/JSON bodies for metrics and spans, and the
// `POST` that carries one to a collector over `e.net.http`.
//
// A `Sample` is a point-in-time reading, not a live metric: `counter_sample`, `gauge_sample`
// and `histogram_sample` take one from the `e.metrics` types, so registries, labels and
// sampling stay with the caller. Samples of one family are listed together; the family's
// `HELP`/`TYPE` header is written when the name changes. Numbers are written the way
// `prometheus_client` and Python's `repr` do (`3.0`, `1e-05`, `1.2345675e+06`) so an
// exposition diffs byte for byte against that reference.
use e.mem
use e.metrics as metrics
use e.net
use e.net.http as http
use e.str

type Kind = enum u8 { Counter, Gauge, Histogram }
type Label = struct { name: str, value: str }
type Sample = struct { name: str, help: str, kind: Kind, labels: []const Label, value: f64, bounds: []const f64, buckets: []const u64, sum: f64 }
type Span = struct { trace_id: [16]u8, span_id: [8]u8, parent_span_id: [8]u8, name: str, kind: u8, start_ns: u64, end_ns: u64, attributes: []const Label, status_code: u8, status_message: str }
type Scrape = struct { content_type: str, body: str }
error Invalid

// ---- samples from the metric types ---------------------------------------------------

fn counter_sample(name: str, help: str, labels: []const Label, c: *metrics.Counter) -> Sample {
    var s: Sample = zero
    s.name = name
    s.help = help
    s.kind = .Counter
    s.labels = labels
    s.value = f64(metrics.counter_get(c))
    ret s
}

fn gauge_sample(name: str, help: str, labels: []const Label, g: *metrics.Gauge) -> Sample {
    var s: Sample = zero
    s.name = name
    s.help = help
    s.kind = .Gauge
    s.labels = labels
    s.value = f64(metrics.gauge_get(g))
    ret s
}

// The cumulative buckets and the sum of a histogram, with its bounds.
fn histogram_sample(a: *mem.Arena, name: str, help: str, labels: []const Label, h: *const metrics.Histogram) -> (Sample, err) {
    var s: Sample = zero
    let (snap, e) = metrics.histogram_snapshot(a, h)
    if e != ok { ret (s, e) }
    s.name = name
    s.help = help
    s.kind = .Histogram
    s.labels = labels
    s.bounds = h.bounds
    s.buckets = snap.buckets
    s.sum = snap.sum
    ret (s, ok)
}

// ---- numbers -------------------------------------------------------------------------

type Digits = struct { text: [24]u8, count: usize, exponent: i32, negative: bool }

// Shortest digits of a finite `v` and its scientific exponent, from `str.push_f64`.
fn digits_of(v: f64) -> (Digits, err) {
    var d: Digits = zero
    var scratch: [96]u8 = zero
    var region = mem.arena_from(scratch[0..])
    let (b0, be) = str.builder(&region, 80usize)
    if be != ok { ret (d, be) }
    var b = b0
    try str.push_f64(&b, v)
    let s = str.done(&b)
    var i = 0usize
    if s.len > 0usize && s[0] == 45u8 {
        d.negative = true
        i = 1usize
    }
    var seen_point = false
    var int_digits = 0i32
    var lead_zero = true
    var zeros_before = 0i32
    var exp_part = 0i32
    var exp_negative = false
    while i < s.len {
        let c = s[i]
        if c == 46u8 {
            seen_point = true
        } else if c == 101u8 || c == 69u8 {
            i += 1usize
            if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
                exp_negative = s[i] == 45u8
                i += 1usize
            }
            while i < s.len {
                exp_part = exp_part * 10i32 + i32(s[i] - 48u8)
                i += 1usize
            }
            break
        } else {
            if lead_zero && c == 48u8 {
                if seen_point { zeros_before += 1i32 }
            } else {
                lead_zero = false
                if d.count < 24usize {
                    d.text[d.count] = c
                    d.count += 1usize
                }
                if !seen_point { int_digits += 1i32 }
            }
        }
        i += 1usize
    }
    if exp_negative { exp_part = 0i32 - exp_part }
    if d.count == 0usize {
        d.text[0] = 48u8
        d.count = 1usize
        d.exponent = 0i32
        ret (d, ok)
    }
    // the scientific exponent: digits before the point less one, or the zeros after it
    if int_digits > 0i32 {
        d.exponent = int_digits - 1i32 + exp_part
    } else {
        d.exponent = 0i32 - zeros_before - 1i32 + exp_part
    }
    while d.count > 1usize && d.text[d.count - 1usize] == 48u8 { d.count -= 1usize }
    ret (d, ok)
}

fn push_zeros(b: *str.Builder, n: i32) -> err {
    var i = 0i32
    while i < n {
        try str.push_byte(b, 48u8)
        i += 1i32
    }
    ret ok
}

fn push_exponent(b: *str.Builder, e: i32) -> err {
    try str.push_byte(b, 101u8)
    var m = e
    if e < 0i32 {
        try str.push_byte(b, 45u8)
        m = 0i32 - e
    } else {
        try str.push_byte(b, 43u8)
    }
    if m < 10i32 { try str.push_byte(b, 48u8) }
    ret str.push_i32(b, m)
}

// A float as Python's `repr` writes it, except that with `prometheus` set a positive value from a
// million up takes the exponent form `prometheus_client` gives it (`1.2345675e+06`).
fn push_number(b: *str.Builder, v: f64, prometheus: bool) -> err {
    if !(v == v) { ret str.push(b, "NaN") }
    let inf = mem.bitcast[f64](9218868437227405312u64)
    if v == inf { ret str.push(b, "+Inf") }
    if v == 0.0f64 - inf { ret str.push(b, "-Inf") }
    let (d, de) = digits_of(v)
    if de != ok { ret de }
    if d.negative { try str.push_byte(b, 45u8) }
    let n = i32(d.count)
    var scientific = d.exponent < -4i32 || d.exponent >= 16i32
    if prometheus && !d.negative && d.exponent >= 6i32 { scientific = true }
    if scientific {
        try str.push_byte(b, d.text[0])
        if n > 1i32 {
            try str.push_byte(b, 46u8)
            try str.push(b, d.text[1usize..d.count])
        }
        ret push_exponent(b, d.exponent)
    }
    if d.exponent < 0i32 {
        try str.push(b, "0.")
        try push_zeros(b, 0i32 - d.exponent - 1i32)
        ret str.push(b, d.text[0usize..d.count])
    }
    // fixed, with at least one fractional digit
    if n <= d.exponent + 1i32 {
        try str.push(b, d.text[0usize..d.count])
        try push_zeros(b, d.exponent + 1i32 - n)
        ret str.push(b, ".0")
    }
    try str.push(b, d.text[0usize..usize(d.exponent + 1i32)])
    try str.push_byte(b, 46u8)
    ret str.push(b, d.text[usize(d.exponent + 1i32)..d.count])
}

// ---- Prometheus and OpenMetrics text ---------------------------------------------------

fn less_bytes(x: str, y: str) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret x.len < y.len
}

fn push_escaped(b: *str.Builder, s: str, quotes: bool) -> err {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 92u8 {
            try str.push(b, "\\\\")
        } else if c == 10u8 {
            try str.push(b, "\\n")
        } else if c == 34u8 && quotes {
            try str.push(b, "\\\"")
        } else {
            try str.push_byte(b, c)
        }
        i += 1usize
    }
    ret ok
}

// `{a="1",le="0.5",z="x"}` -- the labels in name order with `extra` slotted in; nothing at
// all for an empty set.
fn push_labels(b: *str.Builder, labels: []const Label, extra_name: str, extra_value: str) -> err {
    let has_extra = extra_name.len > 0usize
    if labels.len == 0usize && !has_extra { ret ok }
    if labels.len > 64usize { ret Invalid }
    try str.push_byte(b, 123u8)
    var done: u64 = 0u64
    var extra_done = !has_extra
    var first = true
    var written = 0usize
    while written < labels.len || !extra_done {
        // the least name not yet written
        var pick = labels.len
        var k = 0usize
        while k < labels.len {
            if (done & (1u64 << u64(k))) == 0u64 {
                if pick == labels.len || less_bytes(labels[k].name, labels[pick].name) { pick = k }
            }
            k += 1usize
        }
        var take_extra = false
        if !extra_done {
            if pick == labels.len || less_bytes(extra_name, labels[pick].name) { take_extra = true }
        }
        if !first { try str.push_byte(b, 44u8) }
        first = false
        if take_extra {
            try str.push(b, extra_name)
            try str.push(b, "=\"")
            try push_escaped(b, extra_value, true)
            extra_done = true
        } else {
            try str.push(b, labels[pick].name)
            try str.push(b, "=\"")
            try push_escaped(b, labels[pick].value, true)
            done = done | (1u64 << u64(pick))
            written += 1usize
        }
        try str.push_byte(b, 34u8)
    }
    ret str.push_byte(b, 125u8)
}

fn ends_with_total(s: str) -> bool {
    ret s.len > 6usize && str.eq(s[s.len - 6usize..], "_total")
}

fn push_value_line(b: *str.Builder, name: str, suffix: str, labels: []const Label, le: str, v: f64) -> err {
    try str.push(b, name)
    try str.push(b, suffix)
    var le_name = ""
    if le.len > 0usize { le_name = "le" }
    try push_labels(b, labels, le_name, le)
    try str.push_byte(b, 32u8)
    try push_number(b, v, true)
    ret str.push_byte(b, 10u8)
}

// The samples as Prometheus text (`openmetrics` false) or OpenMetrics text with its `# EOF`.
fn render_text(a: *mem.Arena, samples: []const Sample, openmetrics: bool) -> (str, err) {
    var need = 512usize
    var i = 0usize
    while i < samples.len {
        let s = samples[i]
        var label_bytes = 0usize
        var k = 0usize
        while k < s.labels.len {
            label_bytes += s.labels[k].name.len + s.labels[k].value.len * 2usize + 8usize
            k += 1usize
        }
        let lines = s.bounds.len + 4usize
        need += s.name.len * 2usize + s.help.len * 2usize + 96usize + lines * (s.name.len + label_bytes + 64usize)
        i += 1usize
    }
    let (b0, be) = str.builder(a, need)
    if be != ok { ret ("", be) }
    var b = b0
    i = 0usize
    while i < samples.len {
        let s = samples[i]
        var base = s.name
        if s.kind == .Counter && ends_with_total(base) { base = base[0usize..base.len - 6usize] }
        if i == 0usize || !str.eq(samples[i - 1usize].name, s.name) {
            try str.push(&b, "# HELP ")
            try str.push(&b, base)
            if s.kind == .Counter && !openmetrics { try str.push(&b, "_total") }
            try str.push_byte(&b, 32u8)
            try push_escaped(&b, s.help, openmetrics)
            try str.push_byte(&b, 10u8)
            try str.push(&b, "# TYPE ")
            try str.push(&b, base)
            if s.kind == .Counter && !openmetrics { try str.push(&b, "_total") }
            if s.kind == .Counter { try str.push(&b, " counter\n") }
            if s.kind == .Gauge { try str.push(&b, " gauge\n") }
            if s.kind == .Histogram { try str.push(&b, " histogram\n") }
        }
        if s.kind == .Counter {
            try push_value_line(&b, base, "_total", s.labels, "", s.value)
        }
        if s.kind == .Gauge {
            try push_value_line(&b, base, "", s.labels, "", s.value)
        }
        if s.kind == .Histogram {
            if s.buckets.len != s.bounds.len + 1usize { ret ("", Invalid) }
            var k = 0usize
            while k < s.bounds.len {
                // the bound as text: a scratch builder, since `b` is on top of the arena
                var scratch: [96]u8 = zero
                var region = mem.arena_from(scratch[0..])
                let (t0, te) = str.builder(&region, 80usize)
                if te != ok { ret ("", te) }
                var t = t0
                try push_number(&t, s.bounds[k], true)
                let le = str.done(&t)
                try push_value_line(&b, base, "_bucket", s.labels, le, f64(s.buckets[k]))
                k += 1usize
            }
            let total = s.buckets[s.buckets.len - 1usize]
            try push_value_line(&b, base, "_bucket", s.labels, "+Inf", f64(total))
            try push_value_line(&b, base, "_count", s.labels, "", f64(total))
            try push_value_line(&b, base, "_sum", s.labels, "", s.sum)
        }
        i += 1usize
    }
    if openmetrics { try str.push(&b, "# EOF\n") }
    ret (str.done(&b), ok)
}

// The scrape answer for an `Accept` header: OpenMetrics when the client asks for it, else
// Prometheus text 0.0.4.
fn scrape(a: *mem.Arena, samples: []const Sample, accept: str) -> (Scrape, err) {
    var out: Scrape = zero
    let (_, wants) = str.find(accept, "application/openmetrics-text")
    let (body, e) = render_text(a, samples, wants)
    if e != ok { ret (out, e) }
    out.body = body
    if wants {
        out.content_type = "application/openmetrics-text; version=1.0.0; charset=utf-8"
    } else {
        out.content_type = "text/plain; version=0.0.4; charset=utf-8"
    }
    ret (out, ok)
}

// ---- OTLP / JSON -----------------------------------------------------------------------

fn push_json_string(b: *str.Builder, s: str) -> err {
    try str.push_byte(b, 34u8)
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            try str.push(b, "\\\"")
        } else if c == 92u8 {
            try str.push(b, "\\\\")
        } else if c == 10u8 {
            try str.push(b, "\\n")
        } else if c == 13u8 {
            try str.push(b, "\\r")
        } else if c == 9u8 {
            try str.push(b, "\\t")
        } else if c == 8u8 {
            try str.push(b, "\\b")
        } else if c == 12u8 {
            try str.push(b, "\\f")
        } else if c < 32u8 {
            try str.push(b, "\\u00")
            try str.push_byte(b, 48u8 + (c >> 4u8))
            var low = c & 15u8
            if low < 10u8 { try str.push_byte(b, 48u8 + low) } else { try str.push_byte(b, 87u8 + low) }
        } else {
            try str.push_byte(b, c)
        }
        i += 1usize
    }
    ret str.push_byte(b, 34u8)
}

// A 64-bit integer, quoted the way protobuf's JSON mapping writes it.
fn push_json_u64(b: *str.Builder, v: u64) -> err {
    try str.push_byte(b, 34u8)
    try str.push_u64(b, v)
    ret str.push_byte(b, 34u8)
}

fn push_json_double(b: *str.Builder, v: f64) -> err {
    if !(v == v) { ret str.push(b, "\"NaN\"") }
    let inf = mem.bitcast[f64](9218868437227405312u64)
    if v == inf { ret str.push(b, "\"Infinity\"") }
    if v == 0.0f64 - inf { ret str.push(b, "\"-Infinity\"") }
    ret push_number(b, v, false)
}

// `"attributes":[{"key":..,"value":{"stringValue":..}},..]`, leading comma included, nothing
// for an empty set.
fn push_attributes(b: *str.Builder, labels: []const Label, comma: bool) -> err {
    if labels.len == 0usize { ret ok }
    if comma { try str.push_byte(b, 44u8) }
    try str.push(b, "\"attributes\":[")
    var i = 0usize
    while i < labels.len {
        if i > 0usize { try str.push_byte(b, 44u8) }
        try str.push(b, "{\"key\":")
        try push_json_string(b, labels[i].name)
        try str.push(b, ",\"value\":{\"stringValue\":")
        try push_json_string(b, labels[i].value)
        try str.push(b, "}}")
        i += 1usize
    }
    ret str.push_byte(b, 93u8)
}

fn push_scope_key(b: *str.Builder, scope: str, comma: bool) -> err {
    if scope.len == 0usize { ret ok }
    if comma { try str.push_byte(b, 44u8) }
    try str.push(b, "\"scope\":{\"name\":")
    try push_json_string(b, scope)
    ret str.push_byte(b, 125u8)
}

fn payload_capacity(samples: []const Sample, extra: usize) -> usize {
    var need = 1024usize + extra
    var i = 0usize
    while i < samples.len {
        let s = samples[i]
        var label_bytes = 0usize
        var k = 0usize
        while k < s.labels.len {
            label_bytes += s.labels[k].name.len + s.labels[k].value.len * 2usize + 48usize
            k += 1usize
        }
        need += s.name.len * 2usize + s.help.len * 2usize + 256usize + label_bytes + (s.bounds.len + 2usize) * 48usize
        i += 1usize
    }
    ret need
}

// An `ExportMetricsServiceRequest` as OTLP/JSON: counters as monotonic cumulative sums,
// gauges, and cumulative-temporality histograms with per-bucket counts. Samples of one name
// become one metric with a data point per series. `start_ns` and `time_ns` are Unix
// nanoseconds, and both stay nonzero.
fn render_otlp_metrics(a: *mem.Arena, resource: []const Label, scope: str, samples: []const Sample, start_ns: u64, time_ns: u64) -> (str, err) {
    var extra = scope.len * 2usize + 64usize
    var r = 0usize
    while r < resource.len {
        extra += resource[r].name.len * 2usize + resource[r].value.len * 2usize + 64usize
        r += 1usize
    }
    let (b0, be) = str.builder(a, payload_capacity(samples, extra))
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, "{\"resourceMetrics\":[{")
    var wrote = false
    if resource.len > 0usize {
        try str.push(&b, "\"resource\":{")
        try push_attributes(&b, resource, false)
        try str.push(&b, "}")
        wrote = true
    }
    if wrote { try str.push_byte(&b, 44u8) }
    try str.push(&b, "\"scopeMetrics\":[{")
    try push_scope_key(&b, scope, false)
    if scope.len > 0usize { try str.push_byte(&b, 44u8) }
    try str.push(&b, "\"metrics\":[")
    var i = 0usize
    while i < samples.len {
        let s = samples[i]
        let starts = i == 0usize || !str.eq(samples[i - 1usize].name, s.name)
        if starts {
            if i > 0usize {
                // close the previous metric
                try close_metric(&b, samples[i - 1usize].kind)
                try str.push_byte(&b, 44u8)
            }
            try str.push(&b, "{\"name\":")
            try push_json_string(&b, s.name)
            if s.help.len > 0usize {
                try str.push(&b, ",\"description\":")
                try push_json_string(&b, s.help)
            }
            if s.kind == .Gauge { try str.push(&b, ",\"gauge\":{\"dataPoints\":[") }
            if s.kind == .Counter { try str.push(&b, ",\"sum\":{\"dataPoints\":[") }
            if s.kind == .Histogram { try str.push(&b, ",\"histogram\":{\"dataPoints\":[") }
        } else {
            try str.push_byte(&b, 44u8)
        }
        try str.push(&b, "{\"startTimeUnixNano\":")
        try push_json_u64(&b, start_ns)
        try str.push(&b, ",\"timeUnixNano\":")
        try push_json_u64(&b, time_ns)
        if s.kind == .Histogram {
            if s.buckets.len != s.bounds.len + 1usize { ret ("", Invalid) }
            let total = s.buckets[s.buckets.len - 1usize]
            if total > 0u64 {
                try str.push(&b, ",\"count\":")
                try push_json_u64(&b, total)
            }
            try str.push(&b, ",\"sum\":")
            try push_json_double(&b, s.sum)
            try str.push(&b, ",\"bucketCounts\":[")
            var k = 0usize
            var previous = 0u64
            while k < s.buckets.len {
                if k > 0usize { try str.push_byte(&b, 44u8) }
                try push_json_u64(&b, s.buckets[k] - previous)
                previous = s.buckets[k]
                k += 1usize
            }
            try str.push_byte(&b, 93u8)
            if s.bounds.len > 0usize {
                try str.push(&b, ",\"explicitBounds\":[")
                k = 0usize
                while k < s.bounds.len {
                    if k > 0usize { try str.push_byte(&b, 44u8) }
                    try push_json_double(&b, s.bounds[k])
                    k += 1usize
                }
                try str.push_byte(&b, 93u8)
            }
        } else {
            try str.push(&b, ",\"asDouble\":")
            try push_json_double(&b, s.value)
        }
        try push_attributes(&b, s.labels, true)
        try str.push_byte(&b, 125u8)
        i += 1usize
    }
    if samples.len > 0usize { try close_metric(&b, samples[samples.len - 1usize].kind) }
    try str.push(&b, "]}]}]}")
    ret (str.done(&b), ok)
}

// The end of one metric object: the data-point list and what follows it.
fn close_metric(b: *str.Builder, kind: Kind) -> err {
    try str.push_byte(b, 93u8)
    if kind == .Counter { try str.push(b, ",\"aggregationTemporality\":2,\"isMonotonic\":true") }
    if kind == .Histogram { try str.push(b, ",\"aggregationTemporality\":2") }
    ret str.push(b, "}}")
}

fn push_hex(b: *str.Builder, bytes: []const u8) -> err {
    var i = 0usize
    while i < bytes.len {
        let hi = bytes[i] >> 4u8
        let lo = bytes[i] & 15u8
        if hi < 10u8 { try str.push_byte(b, 48u8 + hi) } else { try str.push_byte(b, 87u8 + hi) }
        if lo < 10u8 { try str.push_byte(b, 48u8 + lo) } else { try str.push_byte(b, 87u8 + lo) }
        i += 1usize
    }
    ret ok
}

fn all_zero(bytes: []const u8) -> bool {
    var i = 0usize
    while i < bytes.len {
        if bytes[i] != 0u8 { ret false }
        i += 1usize
    }
    ret true
}

// An `ExportTraceServiceRequest` as OTLP/JSON: ids as lowercase hex, 64-bit times quoted, the
// parent id and a default kind or status left out.
fn render_otlp_spans(a: *mem.Arena, resource: []const Label, scope: str, spans: []const Span) -> (str, err) {
    var need = 1024usize + scope.len * 2usize
    var r = 0usize
    while r < resource.len {
        need += resource[r].name.len * 2usize + resource[r].value.len * 2usize + 64usize
        r += 1usize
    }
    var i = 0usize
    while i < spans.len {
        need += spans[i].name.len * 2usize + spans[i].status_message.len * 2usize + 384usize
        var k = 0usize
        while k < spans[i].attributes.len {
            need += spans[i].attributes[k].name.len * 2usize + spans[i].attributes[k].value.len * 2usize + 64usize
            k += 1usize
        }
        i += 1usize
    }
    let (b0, be) = str.builder(a, need)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, "{\"resourceSpans\":[{")
    if resource.len > 0usize {
        try str.push(&b, "\"resource\":{")
        try push_attributes(&b, resource, false)
        try str.push(&b, "},")
    }
    try str.push(&b, "\"scopeSpans\":[{")
    try push_scope_key(&b, scope, false)
    if scope.len > 0usize { try str.push_byte(&b, 44u8) }
    try str.push(&b, "\"spans\":[")
    i = 0usize
    while i < spans.len {
        let s = spans[i]
        if i > 0usize { try str.push_byte(&b, 44u8) }
        try str.push(&b, "{\"traceId\":\"")
        try push_hex(&b, s.trace_id[0usize..16usize])
        try str.push(&b, "\",\"spanId\":\"")
        try push_hex(&b, s.span_id[0usize..8usize])
        try str.push_byte(&b, 34u8)
        if !all_zero(s.parent_span_id[0usize..8usize]) {
            try str.push(&b, ",\"parentSpanId\":\"")
            try push_hex(&b, s.parent_span_id[0usize..8usize])
            try str.push_byte(&b, 34u8)
        }
        try str.push(&b, ",\"name\":")
        try push_json_string(&b, s.name)
        if s.kind != 0u8 {
            try str.push(&b, ",\"kind\":")
            try str.push_u8(&b, s.kind)
        }
        try str.push(&b, ",\"startTimeUnixNano\":")
        try push_json_u64(&b, s.start_ns)
        try str.push(&b, ",\"endTimeUnixNano\":")
        try push_json_u64(&b, s.end_ns)
        try push_attributes(&b, s.attributes, true)
        if s.status_code != 0u8 || s.status_message.len > 0usize {
            try str.push(&b, ",\"status\":{")
            var comma = false
            if s.status_message.len > 0usize {
                try str.push(&b, "\"message\":")
                try push_json_string(&b, s.status_message)
                comma = true
            }
            if s.status_code != 0u8 {
                if comma { try str.push_byte(&b, 44u8) }
                try str.push(&b, "\"code\":")
                try str.push_u8(&b, s.status_code)
            }
            try str.push_byte(&b, 125u8)
        }
        try str.push_byte(&b, 125u8)
        i += 1usize
    }
    try str.push(&b, "]}]}]}")
    ret (str.done(&b), ok)
}

// ---- carrying a body to a collector ----------------------------------------------------

// A `POST` of `body` to `path` of `host`, as OTLP/HTTP specifies for the JSON encoding
// (`/v1/metrics`, `/v1/traces`). Content-Length is added when the request is written.
fn otlp_request(a: *mem.Arena, host: str, path: str, body: str) -> (http.Request, err) {
    var r: http.Request = zero
    let (headers, he) = mem.alloc[http.Header](a, 3usize)
    if he != ok { ret (r, he) }
    headers[0] = http.Header{ name: "Host", value: host }
    headers[1] = http.Header{ name: "Content-Type", value: "application/json" }
    headers[2] = http.Header{ name: "Accept", value: "application/json" }
    r.method = .Post
    r.target = path
    r.version = .Http11
    r.headers = headers[0usize..3usize]
    r.body = body
    ret (r, ok)
}

// Sends `req` to `endpoint` and answers the collector's response; a 2xx status is success.
fn post(a: *mem.Arena, endpoint: net.Endpoint, req: *const http.Request) -> (http.Response, err) {
    let limits = http.Limits{ start_line: 1024usize, header_bytes: 16384usize, header_count: 64usize, body_bytes: 1048576usize }
    let (response, e) = http.request(a, endpoint, req, limits)
    ret (response, e)
}
