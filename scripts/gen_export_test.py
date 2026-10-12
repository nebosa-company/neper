"""Generates tests/selfhost/fixtures/link/metrics_export/src/main.e (L116).

Oracles: prometheus_client (text exposition and OpenMetrics exposition of custom-collector
families) for `render_text`, and the OTLP protobuf definitions of opentelemetry-proto with
google.protobuf's JSON mapping for `render_otlp_metrics` / `render_otlp_spans` (ids switched
from base64 to hex, which the OTLP/JSON spec requires and protobuf's mapping does not do).

    PYTHONPATH=<dir with prometheus_client, opentelemetry-proto, protobuf> python scripts/gen_export_test.py
"""
import base64, json, math, os, random, struct

from google.protobuf.json_format import MessageToDict
from opentelemetry.proto.collector.metrics.v1.metrics_service_pb2 import ExportMetricsServiceRequest
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import ExportTraceServiceRequest
from prometheus_client import generate_latest
from prometheus_client.core import CollectorRegistry, CounterMetricFamily, GaugeMetricFamily, HistogramMetricFamily
from prometheus_client.openmetrics.exposition import generate_latest as om_latest
from prometheus_client.utils import floatToGoString

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "metrics_export", "src", "main.e")


def lit(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif o < 32 or o == 127:
            out.append("\\x%02x" % o)
        elif o < 128:
            out.append(ch)
        else:
            out.append("".join("\\x%02x" % b for b in ch.encode("utf-8")))
    return '"' + "".join(out) + '"'


def f64(v):
    if v != v:
        bits = 0x7FF8000000000000
    else:
        bits = struct.unpack("<Q", struct.pack("<d", v))[0]
    return "mem.bitcast[f64](%du64)" % bits


class Gen:
    def __init__(self):
        self.lines = []
        self.n = 0

    def label_array(self, name, labels):
        size = max(1, len(labels))
        items = ", ".join("x.Label{ name: %s, value: %s }" % (lit(k), lit(v)) for k, v in labels)
        if not labels:
            items = 'x.Label{ name: "", value: "" }'
        return "    let %s: [%d]x.Label = [%d]x.Label{ %s }" % (name, size, size, items)

    def sample_code(self, idx, fam, suffix):
        out = []
        lab = "lab%s%d" % (suffix, idx)
        out.append(self.label_array(lab, fam["labels"]))
        nl = len(fam["labels"])
        if fam["kind"] == "histogram":
            nb = len(fam["bounds"])
            out.append("    let bnd%s%d: [%d]f64 = [%d]f64{ %s }" % (suffix, idx, max(1, nb), max(1, nb), ", ".join(f64(b) for b in fam["bounds"]) or f64(0.0)))
            out.append("    let cum%s%d: [%d]u64 = [%d]u64{ %s }" % (suffix, idx, nb + 1, nb + 1, ", ".join("%du64" % c for c in fam["cum"])))
            bounds = "bnd%s%d[0usize..%dusize]" % (suffix, idx, nb)
            buckets = "cum%s%d[0usize..%dusize]" % (suffix, idx, nb + 1)
            val, sm = f64(0.0), f64(fam["sum"])
        else:
            out.append("    let bnd%s%d: [1]f64 = [1]f64{ %s }" % (suffix, idx, f64(0.0)))
            out.append("    let cum%s%d: [1]u64 = [1]u64{ 0u64 }" % (suffix, idx))
            bounds = "bnd%s%d[0usize..0usize]" % (suffix, idx)
            buckets = "cum%s%d[0usize..0usize]" % (suffix, idx)
            val, sm = f64(fam["value"]), f64(0.0)
        kind = {"counter": "Counter", "gauge": "Gauge", "histogram": "Histogram"}[fam["kind"]]
        expr = "x.Sample{ name: %s, help: %s, kind: x.Kind.%s, labels: %s[0usize..%dusize], value: %s, bounds: %s, buckets: %s, sum: %s }" % (
            lit(fam["name"]), lit(fam["help"]), kind, lab, nl, val, bounds, buckets, sm)
        return out, expr


def pick_value(rnd):
    r = rnd.random()
    if r < 0.25:
        return float(rnd.randint(0, 100000))
    if r < 0.5:
        return round(rnd.uniform(-1000, 1000), rnd.randint(0, 6))
    if r < 0.6:
        return rnd.choice([1e-5, 0.0001, 1e-7, 3.5e-10, 0.00012345])
    if r < 0.7:
        return rnd.choice([1234567.5, 2.5e8, 999999999.0, 1000000.0, 1000001.0, -2500000.0, 4e6])
    if r < 0.8:
        return 0.1 + 0.2
    if r < 0.85:
        return rnd.choice([0.0, -0.0, 1.0, 100.0, 1e15, 12345678.0])
    return round(rnd.random() * 10, 3)


HELPS = ["Total requests", "", "A \"quoted\" help", "back\\slash and\nnewline", "café au lait", "tab\there"]
NAMES = ["http_requests", "queue_depth", "latency_seconds", "x", "jobs_total", "temp_c"]
LABEL_NAMES = ["method", "code", "a", "z", "path", "le_not"]
LABEL_VALUES = ["GET", "200", "/a\"b", "x\ny", "back\\slash", "café", "", "plain value"]


def make_family(rnd, used):
    kind = rnd.choice(["counter", "counter", "gauge", "histogram", "histogram"])
    name = rnd.choice(NAMES)
    while name in used:
        name = name + "_" + str(rnd.randint(0, 99))
    used.add(name)
    if kind == "counter" and rnd.random() < 0.3 and not name.endswith("_total"):
        name += "_total"
    nl = rnd.randint(0, 3)
    lnames = rnd.sample(LABEL_NAMES, nl)
    fam = {"kind": kind, "name": name, "help": rnd.choice(HELPS), "lnames": lnames, "series": []}
    if kind == "histogram":
        nb = rnd.randint(0, 5)
        bounds = sorted(set(round(rnd.choice([0.005, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 100.0, 1e-5, 1e5, 0.3]), 6) for _ in range(nb)))
        fam["bounds"] = bounds
    return fam


def build_prom_case(rnd):
    fams, used = [], set()
    for _ in range(rnd.randint(1, 3)):
        fam = make_family(rnd, used)
        for _ in range(rnd.randint(1, 3)):
            labels = [(k, rnd.choice(LABEL_VALUES)) for k in fam["lnames"]]
            if any(labels == s[0] for s in fam["series"]):
                continue
            if fam["kind"] == "histogram":
                counts = [rnd.randint(0, 50) for _ in range(len(fam["bounds"]) + 1)]
                cum = []
                t = 0
                for c in counts:
                    t += c
                    cum.append(t)
                fam["series"].append((labels, {"cum": cum, "sum": round(rnd.uniform(0, 500), rnd.randint(0, 4)) if t else 0.0}))
            else:
                v = pick_value(rnd)
                fam["series"].append((labels, v))
        fams.append(fam)
    return fams


def python_text(fams):
    class C:
        def collect(self):
            for f in fams:
                if f["kind"] == "counter":
                    m = CounterMetricFamily(f["name"], f["help"], labels=f["lnames"])
                elif f["kind"] == "gauge":
                    m = GaugeMetricFamily(f["name"], f["help"], labels=f["lnames"])
                else:
                    m = HistogramMetricFamily(f["name"], f["help"], labels=f["lnames"])
                for labels, v in f["series"]:
                    vals = [x for _, x in labels]
                    if f["kind"] == "histogram":
                        les = [floatToGoString(b) for b in f["bounds"]] + ["+Inf"]
                        m.add_metric(vals, list(zip(les, v["cum"])), v["sum"])
                    else:
                        m.add_metric(vals, v)
                yield m
    r = CollectorRegistry()
    r.register(C())
    return generate_latest(r).decode(), om_latest(r).decode()


def prom_case_code(g, rnd, k):
    fams = build_prom_case(rnd)
    text, om = python_text(fams)
    body = ["fn case_%d(a: *mem.Arena) -> bool {" % k]
    exprs = []
    idx = 0
    for fam in fams:
        for labels, v in fam["series"]:
            f = {"kind": fam["kind"], "name": fam["name"], "help": fam["help"], "labels": labels}
            if fam["kind"] == "histogram":
                f["bounds"], f["cum"], f["sum"] = fam["bounds"], v["cum"], v["sum"]
            else:
                f["value"] = v
            code, expr = g.sample_code(idx, f, "p")
            body += code
            exprs.append(expr)
            idx += 1
    n = len(exprs)
    body.append("    var samples: [%d]x.Sample = zero" % max(1, n))
    for i, e in enumerate(exprs):
        body.append("    samples[%d] = %s" % (i, e))
    body.append("    let (got, ge) = x.render_text(a, samples[0usize..%dusize], false)" % n)
    body.append("    if ge != ok || !str.eq(got, %s) {\n        show(got, %s)\n        ret false\n    }" % (lit(text), lit(text)))
    body.append("    let (got2, ge2) = x.render_text(a, samples[0usize..%dusize], true)" % n)
    body.append("    if ge2 != ok || !str.eq(got2, %s) {\n        show(got2, %s)\n        ret false\n    }" % (lit(om), lit(om)))
    body.append("    ret true\n}\n")
    return "\n".join(body)


# ---- OTLP ----
START, NOW = 1700000000000000000, 1700000060123456789


def otlp_metrics_json(resource, scope, fams):
    req = ExportMetricsServiceRequest()
    rm = req.resource_metrics.add()
    for k, v in resource:
        rm.resource.attributes.add(key=k).value.string_value = v
    sm = rm.scope_metrics.add()
    if scope:
        sm.scope.name = scope
    for f in fams:
        mt = sm.metrics.add(name=f["name"])
        if f["help"]:
            mt.description = f["help"]
        if f["kind"] == "counter":
            mt.sum.aggregation_temporality = 2
            mt.sum.is_monotonic = True
            dps = mt.sum.data_points
        elif f["kind"] == "gauge":
            dps = mt.gauge.data_points
        else:
            mt.histogram.aggregation_temporality = 2
            dps = mt.histogram.data_points
        for labels, v in f["series"]:
            if f["kind"] == "histogram":
                total = v["cum"][-1]
                dp = dps.add(start_time_unix_nano=START, time_unix_nano=NOW, sum=v["sum"])
                if total:
                    dp.count = total
                prev = 0
                for c in v["cum"]:
                    dp.bucket_counts.append(c - prev)
                    prev = c
                dp.explicit_bounds.extend(f["bounds"])
            else:
                dp = dps.add(start_time_unix_nano=START, time_unix_nano=NOW, as_double=v)
            for k, val in labels:
                dp.attributes.add(key=k).value.string_value = val
    return req


def to_json(req):
    d = MessageToDict(req, use_integers_for_enums=True)

    def fix(o):
        if isinstance(o, dict):
            for k in list(o):
                if k in ("traceId", "spanId", "parentSpanId") and isinstance(o[k], str):
                    o[k] = base64.b64decode(o[k]).hex()
                else:
                    fix(o[k])
        elif isinstance(o, list):
            for i in o:
                fix(i)
    fix(d)
    return json.dumps(d, separators=(",", ":"), ensure_ascii=False)


def otlp_case_code(g, rnd, k):
    fams = build_prom_case(rnd)
    # OTLP keeps one metric per name: families are already distinct by name
    resource = rnd.choice([[], [("service.name", "checkout")], [("service.name", "cart \"x\""), ("host", "café")]])
    scope = rnd.choice(["", "my.lib", "lib\\v1"])
    flat = []
    for fam in fams:
        flat.append({"kind": fam["kind"], "name": fam["name"], "help": fam["help"], "series": fam["series"], "bounds": fam.get("bounds", [])})
    # metrics whose value is not finite are covered separately; keep every value finite here
    expected = to_json(otlp_metrics_json(resource, scope, flat))
    body = ["fn case_%d(a: *mem.Arena) -> bool {" % k]
    exprs = []
    idx = 0
    for fam in fams:
        for labels, v in fam["series"]:
            f = {"kind": fam["kind"], "name": fam["name"], "help": fam["help"], "labels": labels}
            if fam["kind"] == "histogram":
                f["bounds"], f["cum"], f["sum"] = fam["bounds"], v["cum"], v["sum"]
            else:
                f["value"] = v
            code, expr = g.sample_code(idx, f, "o")
            body += code
            exprs.append(expr)
            idx += 1
    n = len(exprs)
    body.append("    var samples: [%d]x.Sample = zero" % max(1, n))
    for i, e in enumerate(exprs):
        body.append("    samples[%d] = %s" % (i, e))
    body.append(g.label_array("res", resource))
    body.append("    let (got, ge) = x.render_otlp_metrics(a, res[0usize..%dusize], %s, samples[0usize..%dusize], %du64, %du64)" % (len(resource), lit(scope), n, START, NOW))
    body.append("    if ge != ok || !str.eq(got, %s) {\n        show(got, %s)\n        ret false\n    }" % (lit(expected), lit(expected)))
    body.append("    ret true\n}\n")
    return "\n".join(body)


def span_case_code(g, rnd, k):
    resource = rnd.choice([[], [("service.name", "api")]])
    scope = rnd.choice(["", "tracer"])
    spans = []
    for _ in range(rnd.randint(1, 3)):
        tid = bytes(rnd.randrange(256) for _ in range(16))
        sid = bytes(rnd.randrange(256) for _ in range(8))
        pid = rnd.choice([bytes(8), bytes(rnd.randrange(256) for _ in range(8))])
        attrs = [(rnd.choice(["http.method", "peer", "k"]) + str(i), rnd.choice(LABEL_VALUES)) for i in range(rnd.randint(0, 3))]
        spans.append({"tid": tid, "sid": sid, "pid": pid, "name": rnd.choice(["GET /a", "db \"query\"", "café", "x"]),
                      "kind": rnd.randint(0, 5), "start": rnd.randint(1, 2 ** 62), "end": rnd.randint(1, 2 ** 62),
                      "attrs": attrs, "code": rnd.randint(0, 2), "msg": rnd.choice(["", "boom", "line\nbreak"])})
    req = ExportTraceServiceRequest()
    rs = req.resource_spans.add()
    for kk, v in resource:
        rs.resource.attributes.add(key=kk).value.string_value = v
    ss = rs.scope_spans.add()
    if scope:
        ss.scope.name = scope
    for s in spans:
        sp = ss.spans.add(trace_id=s["tid"], span_id=s["sid"], name=s["name"], start_time_unix_nano=s["start"], end_time_unix_nano=s["end"])
        if s["pid"] != bytes(8):
            sp.parent_span_id = s["pid"]
        if s["kind"]:
            sp.kind = s["kind"]
        for kk, v in s["attrs"]:
            sp.attributes.add(key=kk).value.string_value = v
        if s["code"] or s["msg"]:
            sp.status.code = s["code"]
            if s["msg"]:
                sp.status.message = s["msg"]
    expected = to_json(req)
    body = ["fn case_%d(a: *mem.Arena) -> bool {" % k]
    body.append("    var spans: [%d]x.Span = zero" % len(spans))
    for i, s in enumerate(spans):
        body.append(g.label_array("sat%d" % i, s["attrs"]))
        t = "[16]u8{ %s }" % ", ".join(str(b) for b in s["tid"])
        sid = "[8]u8{ %s }" % ", ".join(str(b) for b in s["sid"])
        pid = "[8]u8{ %s }" % ", ".join(str(b) for b in s["pid"])
        body.append("    spans[%d] = x.Span{ trace_id: %s, span_id: %s, parent_span_id: %s, name: %s, kind: %du8, start_ns: %du64, end_ns: %du64, attributes: sat%d[0usize..%dusize], status_code: %du8, status_message: %s }" % (
            i, t, sid, pid, lit(s["name"]), s["kind"], s["start"], s["end"], i, len(s["attrs"]), s["code"], lit(s["msg"])))
    body.append(g.label_array("res", resource))
    body.append("    let (got, ge) = x.render_otlp_spans(a, res[0usize..%dusize], %s, spans[0usize..%dusize])" % (len(resource), lit(scope), len(spans)))
    body.append("    if ge != ok || !str.eq(got, %s) {\n        show(got, %s)\n        ret false\n    }" % (lit(expected), lit(expected)))
    body.append("    ret true\n}\n")
    return "\n".join(body)


PRE = '''// `e.metrics.export` against prometheus_client (text and OpenMetrics exposition) and the OTLP protobuf definitions
// (scripts/gen_export_test.py): every case builds samples or spans in source, renders, and compares with the
// reference's bytes. Every check has its own exit code.
use e.io
use e.mem
use e.metrics as metrics
use e.metrics.export as x
use e.net.http as http
use e.os
use e.str

fn show(got: str, want: str) {
    let p = io.print("\\nGOT  ")
    let q = io.print(got)
    let r = io.print("\\nWANT ")
    let s = io.print(want)
}

'''

POST = '''fn static_checks(a: *mem.Arena) -> u32 {
    // values straight from the metric types
    var c = metrics.counter()
    metrics.counter_add(&c, 41u64)
    metrics.counter_add(&c, 1u64)
    var gg = metrics.gauge()
    metrics.gauge_set(&gg, -7i64)
    let bounds: [2]f64 = [2]f64{ 0.5, 1.0 }
    let (h, he) = metrics.histogram(a, bounds[0usize..2usize])
    if he != ok { ret 1u32 }
    var hv = h
    metrics.histogram_observe(&hv, 0.25)
    metrics.histogram_observe(&hv, 0.75)
    metrics.histogram_observe(&hv, 7.0)
    let none: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (hs, hse) = x.histogram_sample(a, "lat", "Latency", none[0usize..0usize], &hv)
    if hse != ok { ret 2u32 }
    var samples: [3]x.Sample = zero
    samples[0] = x.counter_sample("jobs_total", "Jobs", none[0usize..0usize], &c)
    samples[1] = x.gauge_sample("depth", "Depth", none[0usize..0usize], &gg)
    samples[2] = hs
    let (text, te) = x.render_text(a, samples[0usize..3usize], false)
    let want = "# HELP jobs_total Jobs\\n# TYPE jobs_total counter\\njobs_total 42.0\\n# HELP depth Depth\\n# TYPE depth gauge\\ndepth -7.0\\n# HELP lat Latency\\n# TYPE lat histogram\\nlat_bucket{le=\\"0.5\\"} 1.0\\nlat_bucket{le=\\"1.0\\"} 2.0\\nlat_bucket{le=\\"+Inf\\"} 3.0\\nlat_count 3.0\\nlat_sum 8.0\\n"
    if te != ok || !str.eq(text, want) {
        show(text, want)
        ret 3u32
    }
    // negotiation
    let (s1, e1) = x.scrape(a, samples[0usize..1usize], "text/plain")
    if e1 != ok || !str.eq(s1.content_type, "text/plain; version=0.0.4; charset=utf-8") { ret 4u32 }
    let (s2, e2) = x.scrape(a, samples[0usize..1usize], "application/openmetrics-text; version=1.0.0,text/plain;q=0.5")
    if e2 != ok || !str.eq(s2.content_type, "application/openmetrics-text; version=1.0.0; charset=utf-8") { ret 5u32 }
    if !str.eq(s2.body, "# HELP jobs Jobs\\n# TYPE jobs counter\\njobs_total 42.0\\n# EOF\\n") { ret 6u32 }
    // non-finite values and a histogram whose buckets disagree with its bounds
    var nf: [3]x.Sample = zero
    nf[0] = x.Sample{ name: "g", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](9218868437227405312u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    nf[1] = x.Sample{ name: "n", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](9221120237041090560u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    nf[2] = x.Sample{ name: "m", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](18442240474082181120u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    let (t2, e3) = x.render_text(a, nf[0usize..3usize], false)
    let want2 = "# HELP g \\n# TYPE g gauge\\ng +Inf\\n# HELP n \\n# TYPE n gauge\\nn NaN\\n# HELP m \\n# TYPE m gauge\\nm -Inf\\n"
    if e3 != ok || !str.eq(t2, want2) {
        show(t2, want2)
        ret 7u32
    }
    var bad: [1]x.Sample = zero
    bad[0] = x.Sample{ name: "h", help: "", kind: x.Kind.Histogram, labels: none[0usize..0usize], value: 0.0, bounds: bounds[0usize..2usize], buckets: nones(), sum: 0.0 }
    let (_, e4) = x.render_text(a, bad[0usize..1usize], false)
    if e4 != x.Invalid { ret 8u32 }
    // the POST: the request line, headers, and the length the writer adds
    let (req, re) = x.otlp_request(a, "collector:4318", "/v1/metrics", "{}")
    if re != ok { ret 9u32 }
    var storage: [512]u8 = zero
    var state = io.SliceWriter{ data: storage[0usize..512usize], off: 0usize }
    var w = http.writer(io.slice_writer(&state))
    let we = http.write_request(&w, &req)
    let wire = "POST /v1/metrics HTTP/1.1\\r\\nHost: collector:4318\\r\\nContent-Type: application/json\\r\\nAccept: application/json\\r\\nContent-Length: 2\\r\\n\\r\\n{}"
    if we != ok || !str.eq(storage[0usize..state.off], wire) { ret 10u32 }
    ret 0u32
}

fn none2() -> []const f64 {
    let z: [1]f64 = [1]f64{ 0.0 }
    ret z[0usize..0usize]
}

fn nones() -> []const u64 {
    let z: [1]u64 = [1]u64{ 0u64 }
    ret z[0usize..0usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
%(calls)s
    let sc = static_checks(a)
    if sc != 0u32 { os.exit(i32(100u32 + sc)) }
    try io.print("metrics export ok")
    ret ok
}
'''


def main():
    rnd = random.Random(116)
    g = Gen()
    funcs, calls = [], []
    k = 0
    for _ in range(70):
        funcs.append(prom_case_code(g, rnd, k))
        calls.append("    if !case_%d(a) { os.exit(%di32) }" % (k, k + 1))
        k += 1
    for _ in range(35):
        funcs.append(otlp_case_code(g, rnd, k))
        calls.append("    if !case_%d(a) { os.exit(%di32) }" % (k, k + 1))
        k += 1
    for _ in range(25):
        funcs.append(span_case_code(g, rnd, k))
        calls.append("    if !case_%d(a) { os.exit(%di32) }" % (k, k + 1))
        k += 1
    src = PRE + "\n".join(funcs) + "\n" + POST % {"calls": "\n".join(calls)}
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    print("cases:", k)


main()
