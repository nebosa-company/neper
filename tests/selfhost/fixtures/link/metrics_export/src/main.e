// `e.metrics.export` against prometheus_client (text and OpenMetrics exposition) and the OTLP protobuf definitions
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
    let p = io.print("\nGOT  ")
    let q = io.print(got)
    let r = io.print("\nWANT ")
    let s = io.print(want)
}

fn case_0(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "x\ny" }, x.Label{ name: "le_not", value: "back\\slash" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [2]u64 = [2]u64{ 26u64, 63u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "200" }, x.Label{ name: "le_not", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4621819117588971520u64) }
    let cump1: [2]u64 = [2]u64{ 4u64, 24u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "plain value" }, x.Label{ name: "z", value: "x\ny" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 36u64 }
    let labp4: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 2u64 }
    let labp5: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "" }, x.Label{ name: "z", value: "x\ny" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 21u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4641657512650347853u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4647091577071356346u64) }
    samples[2] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp2[0usize..0usize], value: mem.bitcast[f64](4677506083000942592u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..1usize], sum: mem.bitcast[f64](4641332722193158636u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp4[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..1usize], sum: mem.bitcast[f64](4641627919074983936u64) }
    samples[5] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp5[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..1usize], sum: mem.bitcast[f64](4645234317214089216u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"10.0\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 26.0\njobs_total_bucket{le=\"+Inf\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_count{le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_sum{le_not=\"back\\\\slash\",method=\"x\\ny\"} 211.8411\njobs_total_bucket{le=\"10.0\",le_not=\"plain value\",method=\"200\"} 4.0\njobs_total_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_count{le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_sum{le_not=\"plain value\",method=\"200\"} 476.573\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx 52920.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",z=\"x\\ny\"} 36.0\nqueue_depth_count{code=\"plain value\",z=\"x\\ny\"} 36.0\nqueue_depth_sum{code=\"plain value\",z=\"x\\ny\"} 202.61\nqueue_depth_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"\"} 2.0\nqueue_depth_count{code=\"caf\xc3\xa9\",z=\"\"} 2.0\nqueue_depth_sum{code=\"caf\xc3\xa9\",z=\"\"} 211.0\nqueue_depth_bucket{code=\"\",le=\"+Inf\",z=\"x\\ny\"} 21.0\nqueue_depth_count{code=\"\",z=\"x\\ny\"} 21.0\nqueue_depth_sum{code=\"\",z=\"x\\ny\"} 371.0\n") {
        show(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"10.0\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 26.0\njobs_total_bucket{le=\"+Inf\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_count{le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_sum{le_not=\"back\\\\slash\",method=\"x\\ny\"} 211.8411\njobs_total_bucket{le=\"10.0\",le_not=\"plain value\",method=\"200\"} 4.0\njobs_total_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_count{le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_sum{le_not=\"plain value\",method=\"200\"} 476.573\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx 52920.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",z=\"x\\ny\"} 36.0\nqueue_depth_count{code=\"plain value\",z=\"x\\ny\"} 36.0\nqueue_depth_sum{code=\"plain value\",z=\"x\\ny\"} 202.61\nqueue_depth_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"\"} 2.0\nqueue_depth_count{code=\"caf\xc3\xa9\",z=\"\"} 2.0\nqueue_depth_sum{code=\"caf\xc3\xa9\",z=\"\"} 211.0\nqueue_depth_bucket{code=\"\",le=\"+Inf\",z=\"x\\ny\"} 21.0\nqueue_depth_count{code=\"\",z=\"x\\ny\"} 21.0\nqueue_depth_sum{code=\"\",z=\"x\\ny\"} 371.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"10.0\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 26.0\njobs_total_bucket{le=\"+Inf\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_count{le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_sum{le_not=\"back\\\\slash\",method=\"x\\ny\"} 211.8411\njobs_total_bucket{le=\"10.0\",le_not=\"plain value\",method=\"200\"} 4.0\njobs_total_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_count{le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_sum{le_not=\"plain value\",method=\"200\"} 476.573\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx 52920.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",z=\"x\\ny\"} 36.0\nqueue_depth_count{code=\"plain value\",z=\"x\\ny\"} 36.0\nqueue_depth_sum{code=\"plain value\",z=\"x\\ny\"} 202.61\nqueue_depth_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"\"} 2.0\nqueue_depth_count{code=\"caf\xc3\xa9\",z=\"\"} 2.0\nqueue_depth_sum{code=\"caf\xc3\xa9\",z=\"\"} 211.0\nqueue_depth_bucket{code=\"\",le=\"+Inf\",z=\"x\\ny\"} 21.0\nqueue_depth_count{code=\"\",z=\"x\\ny\"} 21.0\nqueue_depth_sum{code=\"\",z=\"x\\ny\"} 371.0\n# EOF\n") {
        show(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"10.0\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 26.0\njobs_total_bucket{le=\"+Inf\",le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_count{le_not=\"back\\\\slash\",method=\"x\\ny\"} 63.0\njobs_total_sum{le_not=\"back\\\\slash\",method=\"x\\ny\"} 211.8411\njobs_total_bucket{le=\"10.0\",le_not=\"plain value\",method=\"200\"} 4.0\njobs_total_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_count{le_not=\"plain value\",method=\"200\"} 24.0\njobs_total_sum{le_not=\"plain value\",method=\"200\"} 476.573\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx 52920.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",z=\"x\\ny\"} 36.0\nqueue_depth_count{code=\"plain value\",z=\"x\\ny\"} 36.0\nqueue_depth_sum{code=\"plain value\",z=\"x\\ny\"} 202.61\nqueue_depth_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"\"} 2.0\nqueue_depth_count{code=\"caf\xc3\xa9\",z=\"\"} 2.0\nqueue_depth_sum{code=\"caf\xc3\xa9\",z=\"\"} 211.0\nqueue_depth_bucket{code=\"\",le=\"+Inf\",z=\"x\\ny\"} 21.0\nqueue_depth_count{code=\"\",z=\"x\\ny\"} 21.0\nqueue_depth_sum{code=\"\",z=\"x\\ny\"} 371.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_1(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "GET" }, x.Label{ name: "a", value: "" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump0: [4]u64 = [4]u64{ 24u64, 30u64, 32u64, 50u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "a", value: "GET" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump1: [4]u64 = [4]u64{ 31u64, 33u64, 42u64, 58u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "a", value: "plain value" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump2: [4]u64 = [4]u64{ 14u64, 49u64, 80u64, 106u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4628312745301686354u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4643070478330626048u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4645058940711412433u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.25\"} 24.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.3\"} 30.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\"} 32.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\"} 50.0\nlatency_seconds_count{a=\"\",code=\"GET\"} 50.0\nlatency_seconds_sum{a=\"\",code=\"GET\"} 27.07\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.25\"} 31.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.3\"} 33.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"1.0\"} 42.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"+Inf\"} 58.0\nlatency_seconds_count{a=\"GET\",code=\"back\\\\slash\"} 58.0\nlatency_seconds_sum{a=\"GET\",code=\"back\\\\slash\"} 252.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.25\"} 14.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.3\"} 49.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"1.0\"} 80.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"+Inf\"} 106.0\nlatency_seconds_count{a=\"plain value\",code=\"/a\\\"b\"} 106.0\nlatency_seconds_sum{a=\"plain value\",code=\"/a\\\"b\"} 361.031\n") {
        show(got, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.25\"} 24.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.3\"} 30.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\"} 32.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\"} 50.0\nlatency_seconds_count{a=\"\",code=\"GET\"} 50.0\nlatency_seconds_sum{a=\"\",code=\"GET\"} 27.07\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.25\"} 31.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.3\"} 33.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"1.0\"} 42.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"+Inf\"} 58.0\nlatency_seconds_count{a=\"GET\",code=\"back\\\\slash\"} 58.0\nlatency_seconds_sum{a=\"GET\",code=\"back\\\\slash\"} 252.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.25\"} 14.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.3\"} 49.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"1.0\"} 80.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"+Inf\"} 106.0\nlatency_seconds_count{a=\"plain value\",code=\"/a\\\"b\"} 106.0\nlatency_seconds_sum{a=\"plain value\",code=\"/a\\\"b\"} 361.031\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.25\"} 24.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.3\"} 30.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\"} 32.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\"} 50.0\nlatency_seconds_count{a=\"\",code=\"GET\"} 50.0\nlatency_seconds_sum{a=\"\",code=\"GET\"} 27.07\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.25\"} 31.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.3\"} 33.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"1.0\"} 42.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"+Inf\"} 58.0\nlatency_seconds_count{a=\"GET\",code=\"back\\\\slash\"} 58.0\nlatency_seconds_sum{a=\"GET\",code=\"back\\\\slash\"} 252.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.25\"} 14.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.3\"} 49.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"1.0\"} 80.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"+Inf\"} 106.0\nlatency_seconds_count{a=\"plain value\",code=\"/a\\\"b\"} 106.0\nlatency_seconds_sum{a=\"plain value\",code=\"/a\\\"b\"} 361.031\n# EOF\n") {
        show(got2, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.25\"} 24.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.3\"} 30.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\"} 32.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\"} 50.0\nlatency_seconds_count{a=\"\",code=\"GET\"} 50.0\nlatency_seconds_sum{a=\"\",code=\"GET\"} 27.07\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.25\"} 31.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"0.3\"} 33.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"1.0\"} 42.0\nlatency_seconds_bucket{a=\"GET\",code=\"back\\\\slash\",le=\"+Inf\"} 58.0\nlatency_seconds_count{a=\"GET\",code=\"back\\\\slash\"} 58.0\nlatency_seconds_sum{a=\"GET\",code=\"back\\\\slash\"} 252.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.25\"} 14.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"0.3\"} 49.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"1.0\"} 80.0\nlatency_seconds_bucket{a=\"plain value\",code=\"/a\\\"b\",le=\"+Inf\"} 106.0\nlatency_seconds_count{a=\"plain value\",code=\"/a\\\"b\"} 106.0\nlatency_seconds_sum{a=\"plain value\",code=\"/a\\\"b\"} 361.031\n# EOF\n")
        ret false
    }
    ret true
}

fn case_2(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "z", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 40u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "200" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 22u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 49u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    let labp5: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..1usize], sum: mem.bitcast[f64](4639505995333990194u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..1usize], sum: mem.bitcast[f64](4645498200004755456u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..1usize], sum: mem.bitcast[f64](4637360265846841147u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Gauge, labels: labp3[0usize..0usize], value: mem.bitcast[f64](4670653101902921728u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp4[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp5[0usize..1usize], value: mem.bitcast[f64](4634626229029306368u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"200\",le=\"+Inf\",z=\"x\\ny\"} 40.0\njobs_total_count{a=\"200\",z=\"x\\ny\"} 40.0\njobs_total_sum{a=\"200\",z=\"x\\ny\"} 150.6913\njobs_total_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",z=\"200\"} 22.0\njobs_total_count{a=\"caf\xc3\xa9\",z=\"200\"} 22.0\njobs_total_sum{a=\"caf\xc3\xa9\",z=\"200\"} 386.0\njobs_total_bucket{a=\"back\\\\slash\",le=\"+Inf\",z=\"back\\\\slash\"} 49.0\njobs_total_count{a=\"back\\\\slash\",z=\"back\\\\slash\"} 49.0\njobs_total_sum{a=\"back\\\\slash\",z=\"back\\\\slash\"} 108.853\n# HELP latency_seconds Total requests\n# TYPE latency_seconds gauge\nlatency_seconds 17913.0\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests{a=\"/a\\\"b\"} 0.30000000000000004\nhttp_requests{a=\"\"} 70.0\n") {
        show(got, "# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"200\",le=\"+Inf\",z=\"x\\ny\"} 40.0\njobs_total_count{a=\"200\",z=\"x\\ny\"} 40.0\njobs_total_sum{a=\"200\",z=\"x\\ny\"} 150.6913\njobs_total_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",z=\"200\"} 22.0\njobs_total_count{a=\"caf\xc3\xa9\",z=\"200\"} 22.0\njobs_total_sum{a=\"caf\xc3\xa9\",z=\"200\"} 386.0\njobs_total_bucket{a=\"back\\\\slash\",le=\"+Inf\",z=\"back\\\\slash\"} 49.0\njobs_total_count{a=\"back\\\\slash\",z=\"back\\\\slash\"} 49.0\njobs_total_sum{a=\"back\\\\slash\",z=\"back\\\\slash\"} 108.853\n# HELP latency_seconds Total requests\n# TYPE latency_seconds gauge\nlatency_seconds 17913.0\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests{a=\"/a\\\"b\"} 0.30000000000000004\nhttp_requests{a=\"\"} 70.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"200\",le=\"+Inf\",z=\"x\\ny\"} 40.0\njobs_total_count{a=\"200\",z=\"x\\ny\"} 40.0\njobs_total_sum{a=\"200\",z=\"x\\ny\"} 150.6913\njobs_total_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",z=\"200\"} 22.0\njobs_total_count{a=\"caf\xc3\xa9\",z=\"200\"} 22.0\njobs_total_sum{a=\"caf\xc3\xa9\",z=\"200\"} 386.0\njobs_total_bucket{a=\"back\\\\slash\",le=\"+Inf\",z=\"back\\\\slash\"} 49.0\njobs_total_count{a=\"back\\\\slash\",z=\"back\\\\slash\"} 49.0\njobs_total_sum{a=\"back\\\\slash\",z=\"back\\\\slash\"} 108.853\n# HELP latency_seconds Total requests\n# TYPE latency_seconds gauge\nlatency_seconds 17913.0\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests{a=\"/a\\\"b\"} 0.30000000000000004\nhttp_requests{a=\"\"} 70.0\n# EOF\n") {
        show(got2, "# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"200\",le=\"+Inf\",z=\"x\\ny\"} 40.0\njobs_total_count{a=\"200\",z=\"x\\ny\"} 40.0\njobs_total_sum{a=\"200\",z=\"x\\ny\"} 150.6913\njobs_total_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",z=\"200\"} 22.0\njobs_total_count{a=\"caf\xc3\xa9\",z=\"200\"} 22.0\njobs_total_sum{a=\"caf\xc3\xa9\",z=\"200\"} 386.0\njobs_total_bucket{a=\"back\\\\slash\",le=\"+Inf\",z=\"back\\\\slash\"} 49.0\njobs_total_count{a=\"back\\\\slash\",z=\"back\\\\slash\"} 49.0\njobs_total_sum{a=\"back\\\\slash\",z=\"back\\\\slash\"} 108.853\n# HELP latency_seconds Total requests\n# TYPE latency_seconds gauge\nlatency_seconds 17913.0\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests{a=\"/a\\\"b\"} 0.30000000000000004\nhttp_requests{a=\"\"} 70.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_3(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "a", value: "200" }, x.Label{ name: "le_not", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump1: [4]u64 = [4]u64{ 27u64, 56u64, 57u64, 82u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump2: [4]u64 = [4]u64{ 1u64, 15u64, 27u64, 50u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4705844345939427328u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp1[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4645748009046586163u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Histogram, labels: labp2[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4643447302955697439u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total counter\njobs_total{a=\"200\",le_not=\"200\",z=\"back\\\\slash\"} 4e+06\n# HELP http_requests A \"quoted\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"1e-05\"} 27.0\nhttp_requests_bucket{le=\"0.3\"} 56.0\nhttp_requests_bucket{le=\"100.0\"} 57.0\nhttp_requests_bucket{le=\"+Inf\"} 82.0\nhttp_requests_count 82.0\nhttp_requests_sum 400.2\n# HELP queue_depth tab\there\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.25\"} 1.0\nqueue_depth_bucket{le=\"0.5\"} 15.0\nqueue_depth_bucket{le=\"100.0\"} 27.0\nqueue_depth_bucket{le=\"+Inf\"} 50.0\nqueue_depth_count 50.0\nqueue_depth_sum 269.42\n") {
        show(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total counter\njobs_total{a=\"200\",le_not=\"200\",z=\"back\\\\slash\"} 4e+06\n# HELP http_requests A \"quoted\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"1e-05\"} 27.0\nhttp_requests_bucket{le=\"0.3\"} 56.0\nhttp_requests_bucket{le=\"100.0\"} 57.0\nhttp_requests_bucket{le=\"+Inf\"} 82.0\nhttp_requests_count 82.0\nhttp_requests_sum 400.2\n# HELP queue_depth tab\there\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.25\"} 1.0\nqueue_depth_bucket{le=\"0.5\"} 15.0\nqueue_depth_bucket{le=\"100.0\"} 27.0\nqueue_depth_bucket{le=\"+Inf\"} 50.0\nqueue_depth_count 50.0\nqueue_depth_sum 269.42\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs back\\\\slash and\\nnewline\n# TYPE jobs counter\njobs_total{a=\"200\",le_not=\"200\",z=\"back\\\\slash\"} 4e+06\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"1e-05\"} 27.0\nhttp_requests_bucket{le=\"0.3\"} 56.0\nhttp_requests_bucket{le=\"100.0\"} 57.0\nhttp_requests_bucket{le=\"+Inf\"} 82.0\nhttp_requests_count 82.0\nhttp_requests_sum 400.2\n# HELP queue_depth tab\there\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.25\"} 1.0\nqueue_depth_bucket{le=\"0.5\"} 15.0\nqueue_depth_bucket{le=\"100.0\"} 27.0\nqueue_depth_bucket{le=\"+Inf\"} 50.0\nqueue_depth_count 50.0\nqueue_depth_sum 269.42\n# EOF\n") {
        show(got2, "# HELP jobs back\\\\slash and\\nnewline\n# TYPE jobs counter\njobs_total{a=\"200\",le_not=\"200\",z=\"back\\\\slash\"} 4e+06\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"1e-05\"} 27.0\nhttp_requests_bucket{le=\"0.3\"} 56.0\nhttp_requests_bucket{le=\"100.0\"} 57.0\nhttp_requests_bucket{le=\"+Inf\"} 82.0\nhttp_requests_count 82.0\nhttp_requests_sum 400.2\n# HELP queue_depth tab\there\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.25\"} 1.0\nqueue_depth_bucket{le=\"0.5\"} 15.0\nqueue_depth_bucket{le=\"100.0\"} 27.0\nqueue_depth_bucket{le=\"+Inf\"} 50.0\nqueue_depth_count 50.0\nqueue_depth_sum 269.42\n# EOF\n")
        ret false
    }
    ret true
}

fn case_4(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "code", value: "GET" }, x.Label{ name: "z", value: "200" } }
    let bndp0: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump0: [5]u64 = [5]u64{ 44u64, 67u64, 113u64, 155u64, 161u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "GET" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump1: [5]u64 = [5]u64{ 29u64, 59u64, 70u64, 81u64, 94u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..4usize], buckets: cump0[0usize..5usize], sum: mem.bitcast[f64](4646311838609309696u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4646377809306976256u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.005\",z=\"200\"} 44.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.1\",z=\"200\"} 67.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.5\",z=\"200\"} 113.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\",z=\"200\"} 155.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\",z=\"200\"} 161.0\nlatency_seconds_count{a=\"\",code=\"GET\",z=\"200\"} 161.0\nlatency_seconds_sum{a=\"\",code=\"GET\",z=\"200\"} 432.25\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.005\",z=\"GET\"} 29.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.1\",z=\"GET\"} 59.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.5\",z=\"GET\"} 70.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"1.0\",z=\"GET\"} 81.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"GET\"} 94.0\nlatency_seconds_count{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 94.0\nlatency_seconds_sum{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 436.0\n") {
        show(got, "# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.005\",z=\"200\"} 44.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.1\",z=\"200\"} 67.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.5\",z=\"200\"} 113.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\",z=\"200\"} 155.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\",z=\"200\"} 161.0\nlatency_seconds_count{a=\"\",code=\"GET\",z=\"200\"} 161.0\nlatency_seconds_sum{a=\"\",code=\"GET\",z=\"200\"} 432.25\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.005\",z=\"GET\"} 29.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.1\",z=\"GET\"} 59.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.5\",z=\"GET\"} 70.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"1.0\",z=\"GET\"} 81.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"GET\"} 94.0\nlatency_seconds_count{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 94.0\nlatency_seconds_sum{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 436.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.005\",z=\"200\"} 44.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.1\",z=\"200\"} 67.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.5\",z=\"200\"} 113.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\",z=\"200\"} 155.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\",z=\"200\"} 161.0\nlatency_seconds_count{a=\"\",code=\"GET\",z=\"200\"} 161.0\nlatency_seconds_sum{a=\"\",code=\"GET\",z=\"200\"} 432.25\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.005\",z=\"GET\"} 29.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.1\",z=\"GET\"} 59.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.5\",z=\"GET\"} 70.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"1.0\",z=\"GET\"} 81.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"GET\"} 94.0\nlatency_seconds_count{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 94.0\nlatency_seconds_sum{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 436.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.005\",z=\"200\"} 44.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.1\",z=\"200\"} 67.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"0.5\",z=\"200\"} 113.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"1.0\",z=\"200\"} 155.0\nlatency_seconds_bucket{a=\"\",code=\"GET\",le=\"+Inf\",z=\"200\"} 161.0\nlatency_seconds_count{a=\"\",code=\"GET\",z=\"200\"} 161.0\nlatency_seconds_sum{a=\"\",code=\"GET\",z=\"200\"} 432.25\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.005\",z=\"GET\"} 29.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.1\",z=\"GET\"} 59.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"0.5\",z=\"GET\"} 70.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"1.0\",z=\"GET\"} 81.0\nlatency_seconds_bucket{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"GET\"} 94.0\nlatency_seconds_count{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 94.0\nlatency_seconds_sum{a=\"caf\xc3\xa9\",code=\"caf\xc3\xa9\",z=\"GET\"} 436.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_5(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump0: [4]u64 = [4]u64{ 45u64, 86u64, 115u64, 119u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4638989091168321536u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.3\"} 45.0\nlatency_seconds_bucket{le=\"10.0\"} 86.0\nlatency_seconds_bucket{le=\"100.0\"} 115.0\nlatency_seconds_bucket{le=\"+Inf\"} 119.0\nlatency_seconds_count 119.0\nlatency_seconds_sum 136.0\n") {
        show(got, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.3\"} 45.0\nlatency_seconds_bucket{le=\"10.0\"} 86.0\nlatency_seconds_bucket{le=\"100.0\"} 115.0\nlatency_seconds_bucket{le=\"+Inf\"} 119.0\nlatency_seconds_count 119.0\nlatency_seconds_sum 136.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.3\"} 45.0\nlatency_seconds_bucket{le=\"10.0\"} 86.0\nlatency_seconds_bucket{le=\"100.0\"} 115.0\nlatency_seconds_bucket{le=\"+Inf\"} 119.0\nlatency_seconds_count 119.0\nlatency_seconds_sum 136.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.3\"} 45.0\nlatency_seconds_bucket{le=\"10.0\"} 86.0\nlatency_seconds_bucket{le=\"100.0\"} 115.0\nlatency_seconds_bucket{le=\"+Inf\"} 119.0\nlatency_seconds_count 119.0\nlatency_seconds_sum 136.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_6(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "GET" }, x.Label{ name: "code", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "plain value" }, x.Label{ name: "code", value: "200" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "code", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4651197188673844019u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](13870383164859351040u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4618149809792571408u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total Total requests\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"GET\",code=\"plain value\"} 907.9\nlatency_seconds_total{a=\"plain value\",code=\"200\"} -472.0\nlatency_seconds_total{a=\"/a\\\"b\",code=\"GET\"} 5.741\n") {
        show(got, "# HELP latency_seconds_total Total requests\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"GET\",code=\"plain value\"} 907.9\nlatency_seconds_total{a=\"plain value\",code=\"200\"} -472.0\nlatency_seconds_total{a=\"/a\\\"b\",code=\"GET\"} 5.741\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds Total requests\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"GET\",code=\"plain value\"} 907.9\nlatency_seconds_total{a=\"plain value\",code=\"200\"} -472.0\nlatency_seconds_total{a=\"/a\\\"b\",code=\"GET\"} 5.741\n# EOF\n") {
        show(got2, "# HELP latency_seconds Total requests\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"GET\",code=\"plain value\"} 907.9\nlatency_seconds_total{a=\"plain value\",code=\"200\"} -472.0\nlatency_seconds_total{a=\"/a\\\"b\",code=\"GET\"} 5.741\n# EOF\n")
        ret false
    }
    ret true
}

fn case_7(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "path", value: "plain value" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump0: [4]u64 = [4]u64{ 50u64, 54u64, 55u64, 104u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "path", value: "GET" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump1: [4]u64 = [4]u64{ 41u64, 78u64, 89u64, 139u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump2: [4]u64 = [4]u64{ 21u64, 42u64, 70u64, 74u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4631800079525643026u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4646737217667863675u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4619176630507611881u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp3[0usize..2usize], value: mem.bitcast[f64](4648705478325688745u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\",path=\"plain value\",z=\"/a\\\"b\"} 50.0\njobs_total_bucket{le=\"0.1\",path=\"plain value\",z=\"/a\\\"b\"} 54.0\njobs_total_bucket{le=\"100000.0\",path=\"plain value\",z=\"/a\\\"b\"} 55.0\njobs_total_bucket{le=\"+Inf\",path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_count{path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_sum{path=\"plain value\",z=\"/a\\\"b\"} 46.919\njobs_total_bucket{le=\"1e-05\",path=\"GET\",z=\"GET\"} 41.0\njobs_total_bucket{le=\"0.1\",path=\"GET\",z=\"GET\"} 78.0\njobs_total_bucket{le=\"100000.0\",path=\"GET\",z=\"GET\"} 89.0\njobs_total_bucket{le=\"+Inf\",path=\"GET\",z=\"GET\"} 139.0\njobs_total_count{path=\"GET\",z=\"GET\"} 139.0\njobs_total_sum{path=\"GET\",z=\"GET\"} 456.43\njobs_total_bucket{le=\"1e-05\",path=\"/a\\\"b\",z=\"x\\ny\"} 21.0\njobs_total_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 42.0\njobs_total_bucket{le=\"100000.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 70.0\njobs_total_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_count{path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 6.653\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds gauge\nlatency_seconds{a=\"/a\\\"b\",code=\"caf\xc3\xa9\"} 624.62533\n") {
        show(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\",path=\"plain value\",z=\"/a\\\"b\"} 50.0\njobs_total_bucket{le=\"0.1\",path=\"plain value\",z=\"/a\\\"b\"} 54.0\njobs_total_bucket{le=\"100000.0\",path=\"plain value\",z=\"/a\\\"b\"} 55.0\njobs_total_bucket{le=\"+Inf\",path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_count{path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_sum{path=\"plain value\",z=\"/a\\\"b\"} 46.919\njobs_total_bucket{le=\"1e-05\",path=\"GET\",z=\"GET\"} 41.0\njobs_total_bucket{le=\"0.1\",path=\"GET\",z=\"GET\"} 78.0\njobs_total_bucket{le=\"100000.0\",path=\"GET\",z=\"GET\"} 89.0\njobs_total_bucket{le=\"+Inf\",path=\"GET\",z=\"GET\"} 139.0\njobs_total_count{path=\"GET\",z=\"GET\"} 139.0\njobs_total_sum{path=\"GET\",z=\"GET\"} 456.43\njobs_total_bucket{le=\"1e-05\",path=\"/a\\\"b\",z=\"x\\ny\"} 21.0\njobs_total_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 42.0\njobs_total_bucket{le=\"100000.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 70.0\njobs_total_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_count{path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 6.653\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds gauge\nlatency_seconds{a=\"/a\\\"b\",code=\"caf\xc3\xa9\"} 624.62533\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\",path=\"plain value\",z=\"/a\\\"b\"} 50.0\njobs_total_bucket{le=\"0.1\",path=\"plain value\",z=\"/a\\\"b\"} 54.0\njobs_total_bucket{le=\"100000.0\",path=\"plain value\",z=\"/a\\\"b\"} 55.0\njobs_total_bucket{le=\"+Inf\",path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_count{path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_sum{path=\"plain value\",z=\"/a\\\"b\"} 46.919\njobs_total_bucket{le=\"1e-05\",path=\"GET\",z=\"GET\"} 41.0\njobs_total_bucket{le=\"0.1\",path=\"GET\",z=\"GET\"} 78.0\njobs_total_bucket{le=\"100000.0\",path=\"GET\",z=\"GET\"} 89.0\njobs_total_bucket{le=\"+Inf\",path=\"GET\",z=\"GET\"} 139.0\njobs_total_count{path=\"GET\",z=\"GET\"} 139.0\njobs_total_sum{path=\"GET\",z=\"GET\"} 456.43\njobs_total_bucket{le=\"1e-05\",path=\"/a\\\"b\",z=\"x\\ny\"} 21.0\njobs_total_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 42.0\njobs_total_bucket{le=\"100000.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 70.0\njobs_total_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_count{path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 6.653\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds gauge\nlatency_seconds{a=\"/a\\\"b\",code=\"caf\xc3\xa9\"} 624.62533\n# EOF\n") {
        show(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\",path=\"plain value\",z=\"/a\\\"b\"} 50.0\njobs_total_bucket{le=\"0.1\",path=\"plain value\",z=\"/a\\\"b\"} 54.0\njobs_total_bucket{le=\"100000.0\",path=\"plain value\",z=\"/a\\\"b\"} 55.0\njobs_total_bucket{le=\"+Inf\",path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_count{path=\"plain value\",z=\"/a\\\"b\"} 104.0\njobs_total_sum{path=\"plain value\",z=\"/a\\\"b\"} 46.919\njobs_total_bucket{le=\"1e-05\",path=\"GET\",z=\"GET\"} 41.0\njobs_total_bucket{le=\"0.1\",path=\"GET\",z=\"GET\"} 78.0\njobs_total_bucket{le=\"100000.0\",path=\"GET\",z=\"GET\"} 89.0\njobs_total_bucket{le=\"+Inf\",path=\"GET\",z=\"GET\"} 139.0\njobs_total_count{path=\"GET\",z=\"GET\"} 139.0\njobs_total_sum{path=\"GET\",z=\"GET\"} 456.43\njobs_total_bucket{le=\"1e-05\",path=\"/a\\\"b\",z=\"x\\ny\"} 21.0\njobs_total_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 42.0\njobs_total_bucket{le=\"100000.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 70.0\njobs_total_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_count{path=\"/a\\\"b\",z=\"x\\ny\"} 74.0\njobs_total_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 6.653\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds gauge\nlatency_seconds{a=\"/a\\\"b\",code=\"caf\xc3\xa9\"} 624.62533\n# EOF\n")
        ret false
    }
    ret true
}

fn case_8(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "a", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4676333728727826432u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4616315718844324774u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total back\\\\slash and\\nnewline\n# TYPE temp_c_total counter\ntemp_c_total 44390.0\n# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total{a=\"back\\\\slash\",method=\"/a\\\"b\"} 4.112\n") {
        show(got, "# HELP temp_c_total back\\\\slash and\\nnewline\n# TYPE temp_c_total counter\ntemp_c_total 44390.0\n# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total{a=\"back\\\\slash\",method=\"/a\\\"b\"} 4.112\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c back\\\\slash and\\nnewline\n# TYPE temp_c counter\ntemp_c_total 44390.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total{a=\"back\\\\slash\",method=\"/a\\\"b\"} 4.112\n# EOF\n") {
        show(got2, "# HELP temp_c back\\\\slash and\\nnewline\n# TYPE temp_c counter\ntemp_c_total 44390.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total{a=\"back\\\\slash\",method=\"/a\\\"b\"} 4.112\n# EOF\n")
        ret false
    }
    ret true
}

fn case_9(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "GET" }, x.Label{ name: "a", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "a", value: "GET" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labp0[0usize..2usize], value: mem.bitcast[f64](13871838038645224243u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4668329009199710208u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP x \n# TYPE x gauge\nx{a=\"200\",code=\"GET\"} -597.4\nx{a=\"GET\",code=\"caf\xc3\xa9\"} 12921.0\n") {
        show(got, "# HELP x \n# TYPE x gauge\nx{a=\"200\",code=\"GET\"} -597.4\nx{a=\"GET\",code=\"caf\xc3\xa9\"} 12921.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x \n# TYPE x gauge\nx{a=\"200\",code=\"GET\"} -597.4\nx{a=\"GET\",code=\"caf\xc3\xa9\"} 12921.0\n# EOF\n") {
        show(got2, "# HELP x \n# TYPE x gauge\nx{a=\"200\",code=\"GET\"} -597.4\nx{a=\"GET\",code=\"caf\xc3\xa9\"} 12921.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_10(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labp1[0usize..1usize], value: mem.bitcast[f64](13864437005976338432u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total 0.30000000000000004\n# HELP http_requests A \"quoted\" help\n# TYPE http_requests gauge\nhttp_requests{path=\"caf\xc3\xa9\"} -195.0\n") {
        show(got, "# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total 0.30000000000000004\n# HELP http_requests A \"quoted\" help\n# TYPE http_requests gauge\nhttp_requests{path=\"caf\xc3\xa9\"} -195.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total 0.30000000000000004\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests gauge\nhttp_requests{path=\"caf\xc3\xa9\"} -195.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total 0.30000000000000004\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests gauge\nhttp_requests{path=\"caf\xc3\xa9\"} -195.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_11(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "plain value" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "/a\"b" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump2: [4]u64 = [4]u64{ 41u64, 56u64, 82u64, 132u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "plain value" } }
    let bndp3: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [4]u64 = [4]u64{ 22u64, 39u64, 62u64, 105u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "GET" } }
    let bndp4: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump4: [4]u64 = [4]u64{ 16u64, 65u64, 109u64, 146u64 }
    let labp5: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp5: [4]f64 = [4]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump5: [5]u64 = [5]u64{ 30u64, 36u64, 81u64, 104u64, 153u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds_total", help: "", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds_total", help: "", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4680161815898882048u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp2[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4621256167635550208u64) }
    samples[3] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..3usize], buckets: cump3[0usize..4usize], sum: mem.bitcast[f64](4637727661060192731u64) }
    samples[4] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp4[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..3usize], buckets: cump4[0usize..4usize], sum: mem.bitcast[f64](4638813063754761110u64) }
    samples[5] = x.Sample{ name: "x_59", help: "Total requests", kind: x.Kind.Histogram, labels: labp5[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp5[0usize..4usize], buckets: cump5[0usize..5usize], sum: mem.bitcast[f64](4643512042200340890u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"plain value\"} 0.30000000000000004\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"back\\\\slash\"} 78950.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x histogram\nx_bucket{le=\"0.1\",z=\"/a\\\"b\"} 41.0\nx_bucket{le=\"5.0\",z=\"/a\\\"b\"} 56.0\nx_bucket{le=\"100.0\",z=\"/a\\\"b\"} 82.0\nx_bucket{le=\"+Inf\",z=\"/a\\\"b\"} 132.0\nx_count{z=\"/a\\\"b\"} 132.0\nx_sum{z=\"/a\\\"b\"} 9.0\nx_bucket{le=\"0.1\",z=\"plain value\"} 22.0\nx_bucket{le=\"5.0\",z=\"plain value\"} 39.0\nx_bucket{le=\"100.0\",z=\"plain value\"} 62.0\nx_bucket{le=\"+Inf\",z=\"plain value\"} 105.0\nx_count{z=\"plain value\"} 105.0\nx_sum{z=\"plain value\"} 114.074\nx_bucket{le=\"0.1\",z=\"GET\"} 16.0\nx_bucket{le=\"5.0\",z=\"GET\"} 65.0\nx_bucket{le=\"100.0\",z=\"GET\"} 109.0\nx_bucket{le=\"+Inf\",z=\"GET\"} 146.0\nx_count{z=\"GET\"} 146.0\nx_sum{z=\"GET\"} 130.997\n# HELP x_59 Total requests\n# TYPE x_59 histogram\nx_59_bucket{le=\"0.5\"} 30.0\nx_59_bucket{le=\"2.5\"} 36.0\nx_59_bucket{le=\"100.0\"} 81.0\nx_59_bucket{le=\"100000.0\"} 104.0\nx_59_bucket{le=\"+Inf\"} 153.0\nx_59_count 153.0\nx_59_sum 273.1\n") {
        show(got, "# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"plain value\"} 0.30000000000000004\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"back\\\\slash\"} 78950.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x histogram\nx_bucket{le=\"0.1\",z=\"/a\\\"b\"} 41.0\nx_bucket{le=\"5.0\",z=\"/a\\\"b\"} 56.0\nx_bucket{le=\"100.0\",z=\"/a\\\"b\"} 82.0\nx_bucket{le=\"+Inf\",z=\"/a\\\"b\"} 132.0\nx_count{z=\"/a\\\"b\"} 132.0\nx_sum{z=\"/a\\\"b\"} 9.0\nx_bucket{le=\"0.1\",z=\"plain value\"} 22.0\nx_bucket{le=\"5.0\",z=\"plain value\"} 39.0\nx_bucket{le=\"100.0\",z=\"plain value\"} 62.0\nx_bucket{le=\"+Inf\",z=\"plain value\"} 105.0\nx_count{z=\"plain value\"} 105.0\nx_sum{z=\"plain value\"} 114.074\nx_bucket{le=\"0.1\",z=\"GET\"} 16.0\nx_bucket{le=\"5.0\",z=\"GET\"} 65.0\nx_bucket{le=\"100.0\",z=\"GET\"} 109.0\nx_bucket{le=\"+Inf\",z=\"GET\"} 146.0\nx_count{z=\"GET\"} 146.0\nx_sum{z=\"GET\"} 130.997\n# HELP x_59 Total requests\n# TYPE x_59 histogram\nx_59_bucket{le=\"0.5\"} 30.0\nx_59_bucket{le=\"2.5\"} 36.0\nx_59_bucket{le=\"100.0\"} 81.0\nx_59_bucket{le=\"100000.0\"} 104.0\nx_59_bucket{le=\"+Inf\"} 153.0\nx_59_count 153.0\nx_59_sum 273.1\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"plain value\"} 0.30000000000000004\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"back\\\\slash\"} 78950.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x histogram\nx_bucket{le=\"0.1\",z=\"/a\\\"b\"} 41.0\nx_bucket{le=\"5.0\",z=\"/a\\\"b\"} 56.0\nx_bucket{le=\"100.0\",z=\"/a\\\"b\"} 82.0\nx_bucket{le=\"+Inf\",z=\"/a\\\"b\"} 132.0\nx_count{z=\"/a\\\"b\"} 132.0\nx_sum{z=\"/a\\\"b\"} 9.0\nx_bucket{le=\"0.1\",z=\"plain value\"} 22.0\nx_bucket{le=\"5.0\",z=\"plain value\"} 39.0\nx_bucket{le=\"100.0\",z=\"plain value\"} 62.0\nx_bucket{le=\"+Inf\",z=\"plain value\"} 105.0\nx_count{z=\"plain value\"} 105.0\nx_sum{z=\"plain value\"} 114.074\nx_bucket{le=\"0.1\",z=\"GET\"} 16.0\nx_bucket{le=\"5.0\",z=\"GET\"} 65.0\nx_bucket{le=\"100.0\",z=\"GET\"} 109.0\nx_bucket{le=\"+Inf\",z=\"GET\"} 146.0\nx_count{z=\"GET\"} 146.0\nx_sum{z=\"GET\"} 130.997\n# HELP x_59 Total requests\n# TYPE x_59 histogram\nx_59_bucket{le=\"0.5\"} 30.0\nx_59_bucket{le=\"2.5\"} 36.0\nx_59_bucket{le=\"100.0\"} 81.0\nx_59_bucket{le=\"100000.0\"} 104.0\nx_59_bucket{le=\"+Inf\"} 153.0\nx_59_count 153.0\nx_59_sum 273.1\n# EOF\n") {
        show(got2, "# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"plain value\"} 0.30000000000000004\nlatency_seconds_total{le_not=\"caf\xc3\xa9\",method=\"back\\\\slash\"} 78950.0\n# HELP x caf\xc3\xa9 au lait\n# TYPE x histogram\nx_bucket{le=\"0.1\",z=\"/a\\\"b\"} 41.0\nx_bucket{le=\"5.0\",z=\"/a\\\"b\"} 56.0\nx_bucket{le=\"100.0\",z=\"/a\\\"b\"} 82.0\nx_bucket{le=\"+Inf\",z=\"/a\\\"b\"} 132.0\nx_count{z=\"/a\\\"b\"} 132.0\nx_sum{z=\"/a\\\"b\"} 9.0\nx_bucket{le=\"0.1\",z=\"plain value\"} 22.0\nx_bucket{le=\"5.0\",z=\"plain value\"} 39.0\nx_bucket{le=\"100.0\",z=\"plain value\"} 62.0\nx_bucket{le=\"+Inf\",z=\"plain value\"} 105.0\nx_count{z=\"plain value\"} 105.0\nx_sum{z=\"plain value\"} 114.074\nx_bucket{le=\"0.1\",z=\"GET\"} 16.0\nx_bucket{le=\"5.0\",z=\"GET\"} 65.0\nx_bucket{le=\"100.0\",z=\"GET\"} 109.0\nx_bucket{le=\"+Inf\",z=\"GET\"} 146.0\nx_count{z=\"GET\"} 146.0\nx_sum{z=\"GET\"} 130.997\n# HELP x_59 Total requests\n# TYPE x_59 histogram\nx_59_bucket{le=\"0.5\"} 30.0\nx_59_bucket{le=\"2.5\"} 36.0\nx_59_bucket{le=\"100.0\"} 81.0\nx_59_bucket{le=\"100000.0\"} 104.0\nx_59_bucket{le=\"+Inf\"} 153.0\nx_59_count 153.0\nx_59_sum 273.1\n# EOF\n")
        ret false
    }
    ret true
}

fn case_12(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Gauge, labels: labp0[0usize..0usize], value: mem.bitcast[f64](13861662995278879856u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP x Total requests\n# TYPE x gauge\nx -122.078937\n") {
        show(got, "# HELP x Total requests\n# TYPE x gauge\nx -122.078937\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x Total requests\n# TYPE x gauge\nx -122.078937\n# EOF\n") {
        show(got2, "# HELP x Total requests\n# TYPE x gauge\nx -122.078937\n# EOF\n")
        ret false
    }
    ret true
}

fn case_13(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "method", value: "GET" }, x.Label{ name: "le_not", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "le_not", value: "GET" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4831355200913801216u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..1usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](13925995157322203136u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp3[0usize..3usize], value: mem.bitcast[f64](4678148472669470720u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP x back\\\\slash and\\nnewline\n# TYPE x gauge\nx 1e+15\n# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\n# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total{le_not=\"GET\",method=\"GET\",z=\"x\\ny\"} -2500000.0\nqueue_depth_total{le_not=\"GET\",method=\"/a\\\"b\",z=\"x\\ny\"} 57594.0\n") {
        show(got, "# HELP x back\\\\slash and\\nnewline\n# TYPE x gauge\nx 1e+15\n# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\n# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total{le_not=\"GET\",method=\"GET\",z=\"x\\ny\"} -2500000.0\nqueue_depth_total{le_not=\"GET\",method=\"/a\\\"b\",z=\"x\\ny\"} 57594.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x back\\\\slash and\\nnewline\n# TYPE x gauge\nx 1e+15\n# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total{le_not=\"GET\",method=\"GET\",z=\"x\\ny\"} -2500000.0\nqueue_depth_total{le_not=\"GET\",method=\"/a\\\"b\",z=\"x\\ny\"} 57594.0\n# EOF\n") {
        show(got2, "# HELP x back\\\\slash and\\nnewline\n# TYPE x gauge\nx 1e+15\n# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"GET\",z=\"/a\\\"b\"} 0.0\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total{le_not=\"GET\",method=\"GET\",z=\"x\\ny\"} -2500000.0\nqueue_depth_total{le_not=\"GET\",method=\"/a\\\"b\",z=\"x\\ny\"} 57594.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_14(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "code", value: "back\\slash" } }
    let bndp1: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump1: [3]u64 = [3]u64{ 26u64, 56u64, 76u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4645426278926081233u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..2usize], buckets: cump1[0usize..3usize], sum: mem.bitcast[f64](4646712060841820160u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4676034661565071360u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp3[0usize..1usize], value: mem.bitcast[f64](4680239606346547200u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total 381.91176\n# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.3\",le_not=\"plain value\"} 26.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"5.0\",le_not=\"plain value\"} 56.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"plain value\"} 76.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"plain value\"} 76.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"plain value\"} 455.0\n# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth gauge\nqueue_depth{a=\"GET\"} 42214.0\nqueue_depth{a=\"caf\xc3\xa9\"} 80082.0\n") {
        show(got, "# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total 381.91176\n# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.3\",le_not=\"plain value\"} 26.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"5.0\",le_not=\"plain value\"} 56.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"plain value\"} 76.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"plain value\"} 76.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"plain value\"} 455.0\n# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth gauge\nqueue_depth{a=\"GET\"} 42214.0\nqueue_depth{a=\"caf\xc3\xa9\"} 80082.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total 381.91176\n# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.3\",le_not=\"plain value\"} 26.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"5.0\",le_not=\"plain value\"} 56.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"plain value\"} 76.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"plain value\"} 76.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"plain value\"} 455.0\n# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth gauge\nqueue_depth{a=\"GET\"} 42214.0\nqueue_depth{a=\"caf\xc3\xa9\"} 80082.0\n# EOF\n") {
        show(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total 381.91176\n# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.3\",le_not=\"plain value\"} 26.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"5.0\",le_not=\"plain value\"} 56.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",le_not=\"plain value\"} 76.0\njobs_total_count{code=\"back\\\\slash\",le_not=\"plain value\"} 76.0\njobs_total_sum{code=\"back\\\\slash\",le_not=\"plain value\"} 455.0\n# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth gauge\nqueue_depth{a=\"GET\"} 42214.0\nqueue_depth{a=\"caf\xc3\xa9\"} 80082.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_15(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "" }, x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "x\ny" } }
    let bndp0: [2]f64 = [2]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4612811918334230528u64) }
    let cump0: [3]u64 = [3]u64{ 27u64, 36u64, 44u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "code", value: "x\ny" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "path", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "code", value: "" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..2usize], buckets: cump0[0usize..3usize], sum: mem.bitcast[f64](4646887982702264320u64) }
    samples[1] = x.Sample{ name: "x_34", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp1[0usize..3usize], value: mem.bitcast[f64](4632131657048208179u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4637159503819702272u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests", help: "", kind: x.Kind.Counter, labels: labp3[0usize..3usize], value: mem.bitcast[f64](4696837146684686336u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP x tab\there\n# TYPE x histogram\nx_bucket{a=\"x\\ny\",le=\"0.1\",method=\"\",path=\"back\\\\slash\"} 27.0\nx_bucket{a=\"x\\ny\",le=\"2.5\",method=\"\",path=\"back\\\\slash\"} 36.0\nx_bucket{a=\"x\\ny\",le=\"+Inf\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_count{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_sum{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 465.0\n# HELP x_34 caf\xc3\xa9 au lait\n# TYPE x_34 gauge\nx_34{a=\"/a\\\"b\",code=\"x\\ny\",method=\"back\\\\slash\"} 49.275\n# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{code=\"back\\\\slash\",path=\"GET\",z=\"/a\\\"b\"} 106.0\nhttp_requests_total{code=\"\",path=\"back\\\\slash\",z=\"200\"} 1e+06\n") {
        show(got, "# HELP x tab\there\n# TYPE x histogram\nx_bucket{a=\"x\\ny\",le=\"0.1\",method=\"\",path=\"back\\\\slash\"} 27.0\nx_bucket{a=\"x\\ny\",le=\"2.5\",method=\"\",path=\"back\\\\slash\"} 36.0\nx_bucket{a=\"x\\ny\",le=\"+Inf\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_count{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_sum{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 465.0\n# HELP x_34 caf\xc3\xa9 au lait\n# TYPE x_34 gauge\nx_34{a=\"/a\\\"b\",code=\"x\\ny\",method=\"back\\\\slash\"} 49.275\n# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{code=\"back\\\\slash\",path=\"GET\",z=\"/a\\\"b\"} 106.0\nhttp_requests_total{code=\"\",path=\"back\\\\slash\",z=\"200\"} 1e+06\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x tab\there\n# TYPE x histogram\nx_bucket{a=\"x\\ny\",le=\"0.1\",method=\"\",path=\"back\\\\slash\"} 27.0\nx_bucket{a=\"x\\ny\",le=\"2.5\",method=\"\",path=\"back\\\\slash\"} 36.0\nx_bucket{a=\"x\\ny\",le=\"+Inf\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_count{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_sum{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 465.0\n# HELP x_34 caf\xc3\xa9 au lait\n# TYPE x_34 gauge\nx_34{a=\"/a\\\"b\",code=\"x\\ny\",method=\"back\\\\slash\"} 49.275\n# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{code=\"back\\\\slash\",path=\"GET\",z=\"/a\\\"b\"} 106.0\nhttp_requests_total{code=\"\",path=\"back\\\\slash\",z=\"200\"} 1e+06\n# EOF\n") {
        show(got2, "# HELP x tab\there\n# TYPE x histogram\nx_bucket{a=\"x\\ny\",le=\"0.1\",method=\"\",path=\"back\\\\slash\"} 27.0\nx_bucket{a=\"x\\ny\",le=\"2.5\",method=\"\",path=\"back\\\\slash\"} 36.0\nx_bucket{a=\"x\\ny\",le=\"+Inf\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_count{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 44.0\nx_sum{a=\"x\\ny\",method=\"\",path=\"back\\\\slash\"} 465.0\n# HELP x_34 caf\xc3\xa9 au lait\n# TYPE x_34 gauge\nx_34{a=\"/a\\\"b\",code=\"x\\ny\",method=\"back\\\\slash\"} 49.275\n# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{code=\"back\\\\slash\",path=\"GET\",z=\"/a\\\"b\"} 106.0\nhttp_requests_total{code=\"\",path=\"back\\\\slash\",z=\"200\"} 1e+06\n# EOF\n")
        ret false
    }
    ret true
}

fn case_16(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "le_not", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "le_not", value: "/a\"b" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 27u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Gauge, labels: labp0[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests_55", help: "", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4618641828051861635u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests_55", help: "", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4698053238757261312u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests_55", help: "", kind: x.Kind.Counter, labels: labp3[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "jobs_total", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp4[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..1usize], sum: mem.bitcast[f64](4619326375195221950u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests Total requests\n# TYPE http_requests gauge\nhttp_requests{z=\"plain value\"} 0.30000000000000004\n# HELP http_requests_55_total \n# TYPE http_requests_55_total counter\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"\"} 6.178\nhttp_requests_55_total{a=\"/a\\\"b\",le_not=\"/a\\\"b\"} 1.2345675e+06\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\"} 0.30000000000000004\n# HELP jobs_total A \"quoted\" help\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"+Inf\"} 27.0\njobs_total_count 27.0\njobs_total_sum 6.786\n") {
        show(got, "# HELP http_requests Total requests\n# TYPE http_requests gauge\nhttp_requests{z=\"plain value\"} 0.30000000000000004\n# HELP http_requests_55_total \n# TYPE http_requests_55_total counter\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"\"} 6.178\nhttp_requests_55_total{a=\"/a\\\"b\",le_not=\"/a\\\"b\"} 1.2345675e+06\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\"} 0.30000000000000004\n# HELP jobs_total A \"quoted\" help\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"+Inf\"} 27.0\njobs_total_count 27.0\njobs_total_sum 6.786\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests Total requests\n# TYPE http_requests gauge\nhttp_requests{z=\"plain value\"} 0.30000000000000004\n# HELP http_requests_55 \n# TYPE http_requests_55 counter\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"\"} 6.178\nhttp_requests_55_total{a=\"/a\\\"b\",le_not=\"/a\\\"b\"} 1.2345675e+06\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\"} 0.30000000000000004\n# HELP jobs_total A \\\"quoted\\\" help\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"+Inf\"} 27.0\njobs_total_count 27.0\njobs_total_sum 6.786\n# EOF\n") {
        show(got2, "# HELP http_requests Total requests\n# TYPE http_requests gauge\nhttp_requests{z=\"plain value\"} 0.30000000000000004\n# HELP http_requests_55 \n# TYPE http_requests_55 counter\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"\"} 6.178\nhttp_requests_55_total{a=\"/a\\\"b\",le_not=\"/a\\\"b\"} 1.2345675e+06\nhttp_requests_55_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\"} 0.30000000000000004\n# HELP jobs_total A \\\"quoted\\\" help\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"+Inf\"} 27.0\njobs_total_count 27.0\njobs_total_sum 6.786\n# EOF\n")
        ret false
    }
    ret true
}

fn case_17(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "code", value: "GET" }, x.Label{ name: "a", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "" }, x.Label{ name: "code", value: "x\ny" }, x.Label{ name: "a", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4615230351334128484u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp1[0usize..3usize], value: mem.bitcast[f64](13925995157322203136u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total caf\xc3\xa9 au lait\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"x\\ny\",code=\"GET\",le_not=\"plain value\"} 3.574\nlatency_seconds_total{a=\"\",code=\"x\\ny\",le_not=\"\"} -2500000.0\n") {
        show(got, "# HELP latency_seconds_total caf\xc3\xa9 au lait\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"x\\ny\",code=\"GET\",le_not=\"plain value\"} 3.574\nlatency_seconds_total{a=\"\",code=\"x\\ny\",le_not=\"\"} -2500000.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"x\\ny\",code=\"GET\",le_not=\"plain value\"} 3.574\nlatency_seconds_total{a=\"\",code=\"x\\ny\",le_not=\"\"} -2500000.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"x\\ny\",code=\"GET\",le_not=\"plain value\"} 3.574\nlatency_seconds_total{a=\"\",code=\"x\\ny\",le_not=\"\"} -2500000.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_18(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "200" }, x.Label{ name: "z", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump1: [5]u64 = [5]u64{ 23u64, 56u64, 71u64, 114u64, 160u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c_20", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4644407484470001664u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{le_not=\"200\",z=\"plain value\"} 1e-07\n# HELP temp_c_20 back\\\\slash and\\nnewline\n# TYPE temp_c_20 histogram\ntemp_c_20_bucket{le=\"1e-05\"} 23.0\ntemp_c_20_bucket{le=\"0.3\"} 56.0\ntemp_c_20_bucket{le=\"1.0\"} 71.0\ntemp_c_20_bucket{le=\"100.0\"} 114.0\ntemp_c_20_bucket{le=\"+Inf\"} 160.0\ntemp_c_20_count 160.0\ntemp_c_20_sum 324.0\n") {
        show(got, "# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{le_not=\"200\",z=\"plain value\"} 1e-07\n# HELP temp_c_20 back\\\\slash and\\nnewline\n# TYPE temp_c_20 histogram\ntemp_c_20_bucket{le=\"1e-05\"} 23.0\ntemp_c_20_bucket{le=\"0.3\"} 56.0\ntemp_c_20_bucket{le=\"1.0\"} 71.0\ntemp_c_20_bucket{le=\"100.0\"} 114.0\ntemp_c_20_bucket{le=\"+Inf\"} 160.0\ntemp_c_20_count 160.0\ntemp_c_20_sum 324.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{le_not=\"200\",z=\"plain value\"} 1e-07\n# HELP temp_c_20 back\\\\slash and\\nnewline\n# TYPE temp_c_20 histogram\ntemp_c_20_bucket{le=\"1e-05\"} 23.0\ntemp_c_20_bucket{le=\"0.3\"} 56.0\ntemp_c_20_bucket{le=\"1.0\"} 71.0\ntemp_c_20_bucket{le=\"100.0\"} 114.0\ntemp_c_20_bucket{le=\"+Inf\"} 160.0\ntemp_c_20_count 160.0\ntemp_c_20_sum 324.0\n# EOF\n") {
        show(got2, "# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{le_not=\"200\",z=\"plain value\"} 1e-07\n# HELP temp_c_20 back\\\\slash and\\nnewline\n# TYPE temp_c_20 histogram\ntemp_c_20_bucket{le=\"1e-05\"} 23.0\ntemp_c_20_bucket{le=\"0.3\"} 56.0\ntemp_c_20_bucket{le=\"1.0\"} 71.0\ntemp_c_20_bucket{le=\"100.0\"} 114.0\ntemp_c_20_bucket{le=\"+Inf\"} 160.0\ntemp_c_20_count 160.0\ntemp_c_20_sum 324.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_19(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump0: [4]u64 = [4]u64{ 19u64, 54u64, 65u64, 111u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "200" }, x.Label{ name: "a", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "200" }, x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "a", value: "plain value" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4645617422249578463u64) }
    samples[1] = x.Sample{ name: "x", help: "tab\there", kind: x.Kind.Counter, labels: labp1[0usize..0usize], value: mem.bitcast[f64](4698053238757261312u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4613332084091191820u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "temp_c_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp3[0usize..3usize], value: mem.bitcast[f64](13869710119487226564u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total \n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 19.0\njobs_total_bucket{le=\"0.3\"} 54.0\njobs_total_bucket{le=\"1.0\"} 65.0\njobs_total_bucket{le=\"+Inf\"} 111.0\njobs_total_count 111.0\njobs_total_sum 392.777\n# HELP x_total tab\there\n# TYPE x_total counter\nx_total 1.2345675e+06\n# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\",z=\"200\"} 2.731\ntemp_c_total{a=\"plain value\",le_not=\"200\",z=\"back\\\\slash\"} -433.7418\n") {
        show(got, "# HELP jobs_total \n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 19.0\njobs_total_bucket{le=\"0.3\"} 54.0\njobs_total_bucket{le=\"1.0\"} 65.0\njobs_total_bucket{le=\"+Inf\"} 111.0\njobs_total_count 111.0\njobs_total_sum 392.777\n# HELP x_total tab\there\n# TYPE x_total counter\nx_total 1.2345675e+06\n# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\",z=\"200\"} 2.731\ntemp_c_total{a=\"plain value\",le_not=\"200\",z=\"back\\\\slash\"} -433.7418\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total \n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 19.0\njobs_total_bucket{le=\"0.3\"} 54.0\njobs_total_bucket{le=\"1.0\"} 65.0\njobs_total_bucket{le=\"+Inf\"} 111.0\njobs_total_count 111.0\njobs_total_sum 392.777\n# HELP x tab\there\n# TYPE x counter\nx_total 1.2345675e+06\n# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\",z=\"200\"} 2.731\ntemp_c_total{a=\"plain value\",le_not=\"200\",z=\"back\\\\slash\"} -433.7418\n# EOF\n") {
        show(got2, "# HELP jobs_total \n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 19.0\njobs_total_bucket{le=\"0.3\"} 54.0\njobs_total_bucket{le=\"1.0\"} 65.0\njobs_total_bucket{le=\"+Inf\"} 111.0\njobs_total_count 111.0\njobs_total_sum 392.777\n# HELP x tab\there\n# TYPE x counter\nx_total 1.2345675e+06\n# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{a=\"back\\\\slash\",le_not=\"caf\xc3\xa9\",z=\"200\"} 2.731\ntemp_c_total{a=\"plain value\",le_not=\"200\",z=\"back\\\\slash\"} -433.7418\n# EOF\n")
        ret false
    }
    ret true
}

fn case_20(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "GET" }, x.Label{ name: "a", value: "GET" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump1: [4]u64 = [4]u64{ 40u64, 72u64, 101u64, 121u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "200" }, x.Label{ name: "a", value: "200" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump2: [4]u64 = [4]u64{ 50u64, 96u64, 123u64, 171u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "a", value: "" } }
    let bndp3: [3]f64 = [3]f64{ mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump3: [4]u64 = [4]u64{ 5u64, 37u64, 77u64, 115u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4609204535032706761u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4621965484576861061u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4628723417292707201u64) }
    samples[3] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..3usize], buckets: cump3[0usize..4usize], sum: mem.bitcast[f64](4643885700231924285u64) }
    samples[4] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp4[0usize..0usize], value: mem.bitcast[f64](4732664617111650304u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total tab\there\n# TYPE latency_seconds_total counter\nlatency_seconds_total 1.449\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"GET\",le=\"2.5\",path=\"GET\"} 40.0\ntemp_c_bucket{a=\"GET\",le=\"100.0\",path=\"GET\"} 72.0\ntemp_c_bucket{a=\"GET\",le=\"100000.0\",path=\"GET\"} 101.0\ntemp_c_bucket{a=\"GET\",le=\"+Inf\",path=\"GET\"} 121.0\ntemp_c_count{a=\"GET\",path=\"GET\"} 121.0\ntemp_c_sum{a=\"GET\",path=\"GET\"} 10.26\ntemp_c_bucket{a=\"200\",le=\"2.5\",path=\"200\"} 50.0\ntemp_c_bucket{a=\"200\",le=\"100.0\",path=\"200\"} 96.0\ntemp_c_bucket{a=\"200\",le=\"100000.0\",path=\"200\"} 123.0\ntemp_c_bucket{a=\"200\",le=\"+Inf\",path=\"200\"} 171.0\ntemp_c_count{a=\"200\",path=\"200\"} 171.0\ntemp_c_sum{a=\"200\",path=\"200\"} 28.529\ntemp_c_bucket{a=\"\",le=\"2.5\",path=\"caf\xc3\xa9\"} 5.0\ntemp_c_bucket{a=\"\",le=\"100.0\",path=\"caf\xc3\xa9\"} 37.0\ntemp_c_bucket{a=\"\",le=\"100000.0\",path=\"caf\xc3\xa9\"} 77.0\ntemp_c_bucket{a=\"\",le=\"+Inf\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_count{a=\"\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_sum{a=\"\",path=\"caf\xc3\xa9\"} 294.34\n# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total counter\njobs_total 2.5e+08\n") {
        show(got, "# HELP latency_seconds_total tab\there\n# TYPE latency_seconds_total counter\nlatency_seconds_total 1.449\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"GET\",le=\"2.5\",path=\"GET\"} 40.0\ntemp_c_bucket{a=\"GET\",le=\"100.0\",path=\"GET\"} 72.0\ntemp_c_bucket{a=\"GET\",le=\"100000.0\",path=\"GET\"} 101.0\ntemp_c_bucket{a=\"GET\",le=\"+Inf\",path=\"GET\"} 121.0\ntemp_c_count{a=\"GET\",path=\"GET\"} 121.0\ntemp_c_sum{a=\"GET\",path=\"GET\"} 10.26\ntemp_c_bucket{a=\"200\",le=\"2.5\",path=\"200\"} 50.0\ntemp_c_bucket{a=\"200\",le=\"100.0\",path=\"200\"} 96.0\ntemp_c_bucket{a=\"200\",le=\"100000.0\",path=\"200\"} 123.0\ntemp_c_bucket{a=\"200\",le=\"+Inf\",path=\"200\"} 171.0\ntemp_c_count{a=\"200\",path=\"200\"} 171.0\ntemp_c_sum{a=\"200\",path=\"200\"} 28.529\ntemp_c_bucket{a=\"\",le=\"2.5\",path=\"caf\xc3\xa9\"} 5.0\ntemp_c_bucket{a=\"\",le=\"100.0\",path=\"caf\xc3\xa9\"} 37.0\ntemp_c_bucket{a=\"\",le=\"100000.0\",path=\"caf\xc3\xa9\"} 77.0\ntemp_c_bucket{a=\"\",le=\"+Inf\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_count{a=\"\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_sum{a=\"\",path=\"caf\xc3\xa9\"} 294.34\n# HELP jobs_total caf\xc3\xa9 au lait\n# TYPE jobs_total counter\njobs_total 2.5e+08\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds counter\nlatency_seconds_total 1.449\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"GET\",le=\"2.5\",path=\"GET\"} 40.0\ntemp_c_bucket{a=\"GET\",le=\"100.0\",path=\"GET\"} 72.0\ntemp_c_bucket{a=\"GET\",le=\"100000.0\",path=\"GET\"} 101.0\ntemp_c_bucket{a=\"GET\",le=\"+Inf\",path=\"GET\"} 121.0\ntemp_c_count{a=\"GET\",path=\"GET\"} 121.0\ntemp_c_sum{a=\"GET\",path=\"GET\"} 10.26\ntemp_c_bucket{a=\"200\",le=\"2.5\",path=\"200\"} 50.0\ntemp_c_bucket{a=\"200\",le=\"100.0\",path=\"200\"} 96.0\ntemp_c_bucket{a=\"200\",le=\"100000.0\",path=\"200\"} 123.0\ntemp_c_bucket{a=\"200\",le=\"+Inf\",path=\"200\"} 171.0\ntemp_c_count{a=\"200\",path=\"200\"} 171.0\ntemp_c_sum{a=\"200\",path=\"200\"} 28.529\ntemp_c_bucket{a=\"\",le=\"2.5\",path=\"caf\xc3\xa9\"} 5.0\ntemp_c_bucket{a=\"\",le=\"100.0\",path=\"caf\xc3\xa9\"} 37.0\ntemp_c_bucket{a=\"\",le=\"100000.0\",path=\"caf\xc3\xa9\"} 77.0\ntemp_c_bucket{a=\"\",le=\"+Inf\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_count{a=\"\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_sum{a=\"\",path=\"caf\xc3\xa9\"} 294.34\n# HELP jobs caf\xc3\xa9 au lait\n# TYPE jobs counter\njobs_total 2.5e+08\n# EOF\n") {
        show(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds counter\nlatency_seconds_total 1.449\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"GET\",le=\"2.5\",path=\"GET\"} 40.0\ntemp_c_bucket{a=\"GET\",le=\"100.0\",path=\"GET\"} 72.0\ntemp_c_bucket{a=\"GET\",le=\"100000.0\",path=\"GET\"} 101.0\ntemp_c_bucket{a=\"GET\",le=\"+Inf\",path=\"GET\"} 121.0\ntemp_c_count{a=\"GET\",path=\"GET\"} 121.0\ntemp_c_sum{a=\"GET\",path=\"GET\"} 10.26\ntemp_c_bucket{a=\"200\",le=\"2.5\",path=\"200\"} 50.0\ntemp_c_bucket{a=\"200\",le=\"100.0\",path=\"200\"} 96.0\ntemp_c_bucket{a=\"200\",le=\"100000.0\",path=\"200\"} 123.0\ntemp_c_bucket{a=\"200\",le=\"+Inf\",path=\"200\"} 171.0\ntemp_c_count{a=\"200\",path=\"200\"} 171.0\ntemp_c_sum{a=\"200\",path=\"200\"} 28.529\ntemp_c_bucket{a=\"\",le=\"2.5\",path=\"caf\xc3\xa9\"} 5.0\ntemp_c_bucket{a=\"\",le=\"100.0\",path=\"caf\xc3\xa9\"} 37.0\ntemp_c_bucket{a=\"\",le=\"100000.0\",path=\"caf\xc3\xa9\"} 77.0\ntemp_c_bucket{a=\"\",le=\"+Inf\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_count{a=\"\",path=\"caf\xc3\xa9\"} 115.0\ntemp_c_sum{a=\"\",path=\"caf\xc3\xa9\"} 294.34\n# HELP jobs caf\xc3\xa9 au lait\n# TYPE jobs counter\njobs_total 2.5e+08\n# EOF\n")
        ret false
    }
    ret true
}

fn case_21(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "le_not", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "plain value" }, x.Label{ name: "le_not", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "le_not", value: "plain value" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4621748748844793856u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4671038755606364160u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total back\\\\slash and\\nnewline\n# TYPE http_requests_total counter\nhttp_requests_total{a=\"\",le_not=\"x\\ny\"} 0.30000000000000004\nhttp_requests_total{a=\"plain value\",le_not=\"\"} 9.875\nhttp_requests_total{a=\"/a\\\"b\",le_not=\"plain value\"} 19316.0\n") {
        show(got, "# HELP http_requests_total back\\\\slash and\\nnewline\n# TYPE http_requests_total counter\nhttp_requests_total{a=\"\",le_not=\"x\\ny\"} 0.30000000000000004\nhttp_requests_total{a=\"plain value\",le_not=\"\"} 9.875\nhttp_requests_total{a=\"/a\\\"b\",le_not=\"plain value\"} 19316.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests counter\nhttp_requests_total{a=\"\",le_not=\"x\\ny\"} 0.30000000000000004\nhttp_requests_total{a=\"plain value\",le_not=\"\"} 9.875\nhttp_requests_total{a=\"/a\\\"b\",le_not=\"plain value\"} 19316.0\n# EOF\n") {
        show(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests counter\nhttp_requests_total{a=\"\",le_not=\"x\\ny\"} 0.30000000000000004\nhttp_requests_total{a=\"plain value\",le_not=\"\"} 9.875\nhttp_requests_total{a=\"/a\\\"b\",le_not=\"plain value\"} 19316.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_22(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "code", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](13925995157322203136u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth_total back\\\\slash and\\nnewline\n# TYPE queue_depth_total counter\nqueue_depth_total{code=\"200\",path=\"/a\\\"b\"} -2500000.0\n") {
        show(got, "# HELP queue_depth_total back\\\\slash and\\nnewline\n# TYPE queue_depth_total counter\nqueue_depth_total{code=\"200\",path=\"/a\\\"b\"} -2500000.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth counter\nqueue_depth_total{code=\"200\",path=\"/a\\\"b\"} -2500000.0\n# EOF\n") {
        show(got2, "# HELP queue_depth back\\\\slash and\\nnewline\n# TYPE queue_depth counter\nqueue_depth_total{code=\"200\",path=\"/a\\\"b\"} -2500000.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_23(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4591870180066957722u64) }
    let cump0: [2]u64 = [2]u64{ 14u64, 54u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "" }, x.Label{ name: "path", value: "200" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4591870180066957722u64) }
    let cump1: [2]u64 = [2]u64{ 25u64, 31u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "z", value: "GET" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](4591870180066957722u64) }
    let cump2: [2]u64 = [2]u64{ 30u64, 62u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4637280073625976281u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4644880186509015122u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..1usize], buckets: cump2[0usize..2usize], sum: mem.bitcast[f64](4635779572746378281u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.1\",path=\"200\",z=\"x\\ny\"} 14.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_count{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_sum{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 107.7134\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",path=\"200\",z=\"\"} 25.0\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",path=\"200\",z=\"\"} 31.0\njobs_total_count{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 31.0\njobs_total_sum{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 350.87\njobs_total_bucket{code=\"/a\\\"b\",le=\"0.1\",path=\"back\\\\slash\",z=\"GET\"} 30.0\njobs_total_bucket{code=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_count{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_sum{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 86.39\n") {
        show(got, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.1\",path=\"200\",z=\"x\\ny\"} 14.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_count{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_sum{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 107.7134\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",path=\"200\",z=\"\"} 25.0\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",path=\"200\",z=\"\"} 31.0\njobs_total_count{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 31.0\njobs_total_sum{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 350.87\njobs_total_bucket{code=\"/a\\\"b\",le=\"0.1\",path=\"back\\\\slash\",z=\"GET\"} 30.0\njobs_total_bucket{code=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_count{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_sum{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 86.39\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.1\",path=\"200\",z=\"x\\ny\"} 14.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_count{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_sum{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 107.7134\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",path=\"200\",z=\"\"} 25.0\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",path=\"200\",z=\"\"} 31.0\njobs_total_count{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 31.0\njobs_total_sum{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 350.87\njobs_total_bucket{code=\"/a\\\"b\",le=\"0.1\",path=\"back\\\\slash\",z=\"GET\"} 30.0\njobs_total_bucket{code=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_count{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_sum{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 86.39\n# EOF\n") {
        show(got2, "# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"back\\\\slash\",le=\"0.1\",path=\"200\",z=\"x\\ny\"} 14.0\njobs_total_bucket{code=\"back\\\\slash\",le=\"+Inf\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_count{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 54.0\njobs_total_sum{code=\"back\\\\slash\",path=\"200\",z=\"x\\ny\"} 107.7134\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",path=\"200\",z=\"\"} 25.0\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",path=\"200\",z=\"\"} 31.0\njobs_total_count{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 31.0\njobs_total_sum{code=\"caf\xc3\xa9\",path=\"200\",z=\"\"} 350.87\njobs_total_bucket{code=\"/a\\\"b\",le=\"0.1\",path=\"back\\\\slash\",z=\"GET\"} 30.0\njobs_total_bucket{code=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_count{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 62.0\njobs_total_sum{code=\"/a\\\"b\",path=\"back\\\\slash\",z=\"GET\"} 86.39\n# EOF\n")
        ret false
    }
    ret true
}

fn case_24(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "le_not", value: "GET" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "200" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests_total", help: "", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4676207147451678720u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds_total", help: "", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](4696837155274620928u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds_total", help: "", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4674488748216418304u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"GET\",path=\"back\\\\slash\"} 43469.0\n# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"plain value\"} 1.000001e+06\nlatency_seconds_total{a=\"200\"} 31867.0\n") {
        show(got, "# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"GET\",path=\"back\\\\slash\"} 43469.0\n# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"plain value\"} 1.000001e+06\nlatency_seconds_total{a=\"200\"} 31867.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{le_not=\"GET\",path=\"back\\\\slash\"} 43469.0\n# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"plain value\"} 1.000001e+06\nlatency_seconds_total{a=\"200\"} 31867.0\n# EOF\n") {
        show(got2, "# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{le_not=\"GET\",path=\"back\\\\slash\"} 43469.0\n# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"plain value\"} 1.000001e+06\nlatency_seconds_total{a=\"200\"} 31867.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_25(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "200" }, x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "x\ny" }, x.Label{ name: "a", value: "200" }, x.Label{ name: "path", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "code", value: "x\ny" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 43u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4705844345939427328u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "", kind: x.Kind.Counter, labels: labp1[0usize..3usize], value: mem.bitcast[f64](4548686525128629352u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "Total requests", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..1usize], sum: mem.bitcast[f64](4644224631288256004u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{a=\"/a\\\"b\",method=\"200\",path=\"back\\\\slash\"} 4e+06\nhttp_requests_total{a=\"200\",method=\"x\\ny\",path=\"plain value\"} 0.00012345\n# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"200\",code=\"x\\ny\",le=\"+Inf\"} 43.0\ntemp_c_count{a=\"200\",code=\"x\\ny\"} 43.0\ntemp_c_sum{a=\"200\",code=\"x\\ny\"} 313.606\n") {
        show(got, "# HELP http_requests_total \n# TYPE http_requests_total counter\nhttp_requests_total{a=\"/a\\\"b\",method=\"200\",path=\"back\\\\slash\"} 4e+06\nhttp_requests_total{a=\"200\",method=\"x\\ny\",path=\"plain value\"} 0.00012345\n# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"200\",code=\"x\\ny\",le=\"+Inf\"} 43.0\ntemp_c_count{a=\"200\",code=\"x\\ny\"} 43.0\ntemp_c_sum{a=\"200\",code=\"x\\ny\"} 313.606\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{a=\"/a\\\"b\",method=\"200\",path=\"back\\\\slash\"} 4e+06\nhttp_requests_total{a=\"200\",method=\"x\\ny\",path=\"plain value\"} 0.00012345\n# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"200\",code=\"x\\ny\",le=\"+Inf\"} 43.0\ntemp_c_count{a=\"200\",code=\"x\\ny\"} 43.0\ntemp_c_sum{a=\"200\",code=\"x\\ny\"} 313.606\n# EOF\n") {
        show(got2, "# HELP http_requests \n# TYPE http_requests counter\nhttp_requests_total{a=\"/a\\\"b\",method=\"200\",path=\"back\\\\slash\"} 4e+06\nhttp_requests_total{a=\"200\",method=\"x\\ny\",path=\"plain value\"} 0.00012345\n# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{a=\"200\",code=\"x\\ny\",le=\"+Inf\"} 43.0\ntemp_c_count{a=\"200\",code=\"x\\ny\"} 43.0\ntemp_c_sum{a=\"200\",code=\"x\\ny\"} 313.606\n# EOF\n")
        ret false
    }
    ret true
}

fn case_26(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "plain value" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "/a\"b" }, x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "200" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4668444457920626688u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..0usize], value: mem.bitcast[f64](4698053238757261312u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4677172243782959104u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labp3[0usize..3usize], value: mem.bitcast[f64](4663597260909576192u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth_total A \"quoted\" help\n# TYPE queue_depth_total counter\nqueue_depth_total{a=\"\",code=\"caf\xc3\xa9\"} 13131.0\n# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total 1.2345675e+06\n# HELP x \n# TYPE x gauge\nx{le_not=\"back\\\\slash\",path=\"plain value\",z=\"back\\\\slash\"} 50491.0\nx{le_not=\"/a\\\"b\",path=\"200\",z=\"x\\ny\"} 6253.0\n") {
        show(got, "# HELP queue_depth_total A \"quoted\" help\n# TYPE queue_depth_total counter\nqueue_depth_total{a=\"\",code=\"caf\xc3\xa9\"} 13131.0\n# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total 1.2345675e+06\n# HELP x \n# TYPE x gauge\nx{le_not=\"back\\\\slash\",path=\"plain value\",z=\"back\\\\slash\"} 50491.0\nx{le_not=\"/a\\\"b\",path=\"200\",z=\"x\\ny\"} 6253.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth counter\nqueue_depth_total{a=\"\",code=\"caf\xc3\xa9\"} 13131.0\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total 1.2345675e+06\n# HELP x \n# TYPE x gauge\nx{le_not=\"back\\\\slash\",path=\"plain value\",z=\"back\\\\slash\"} 50491.0\nx{le_not=\"/a\\\"b\",path=\"200\",z=\"x\\ny\"} 6253.0\n# EOF\n") {
        show(got2, "# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth counter\nqueue_depth_total{a=\"\",code=\"caf\xc3\xa9\"} 13131.0\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total 1.2345675e+06\n# HELP x \n# TYPE x gauge\nx{le_not=\"back\\\\slash\",path=\"plain value\",z=\"back\\\\slash\"} 50491.0\nx{le_not=\"/a\\\"b\",path=\"200\",z=\"x\\ny\"} 6253.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_27(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "a", value: "GET" }, x.Label{ name: "z", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4617315517961601024u64) }
    let cump0: [2]u64 = [2]u64{ 9u64, 13u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "plain value" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4617315517961601024u64) }
    let cump1: [2]u64 = [2]u64{ 6u64, 39u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "a", value: "plain value" }, x.Label{ name: "code", value: "200" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "x\ny" }, x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp3: [2]f64 = [2]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump3: [3]u64 = [3]u64{ 21u64, 55u64, 66u64 }
    let labp4: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "x\ny" }, x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndp4: [2]f64 = [2]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump4: [3]u64 = [3]u64{ 37u64, 64u64, 77u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4645808526166578954u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4629783452054999532u64) }
    samples[2] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Gauge, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4619434461586278842u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..2usize], buckets: cump3[0usize..3usize], sum: mem.bitcast[f64](4637258174872788192u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp4[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..2usize], buckets: cump4[0usize..3usize], sum: mem.bitcast[f64](4645640696711715226u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",le=\"5.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 9.0\njobs_total_bucket{a=\"GET\",le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_count{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_sum{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 403.64\njobs_total_bucket{a=\"plain value\",le=\"5.0\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 6.0\njobs_total_bucket{a=\"plain value\",le=\"+Inf\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_count{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_sum{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 32.59\n# HELP x Total requests\n# TYPE x gauge\nx{a=\"plain value\",code=\"200\",z=\"/a\\\"b\"} 6.882\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.005\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 21.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 55.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_count{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_sum{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 107.4022\nqueue_depth_bucket{le=\"0.005\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 37.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 64.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_count{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_sum{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 394.1\n") {
        show(got, "# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",le=\"5.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 9.0\njobs_total_bucket{a=\"GET\",le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_count{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_sum{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 403.64\njobs_total_bucket{a=\"plain value\",le=\"5.0\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 6.0\njobs_total_bucket{a=\"plain value\",le=\"+Inf\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_count{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_sum{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 32.59\n# HELP x Total requests\n# TYPE x gauge\nx{a=\"plain value\",code=\"200\",z=\"/a\\\"b\"} 6.882\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.005\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 21.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 55.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_count{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_sum{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 107.4022\nqueue_depth_bucket{le=\"0.005\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 37.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 64.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_count{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_sum{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 394.1\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",le=\"5.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 9.0\njobs_total_bucket{a=\"GET\",le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_count{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_sum{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 403.64\njobs_total_bucket{a=\"plain value\",le=\"5.0\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 6.0\njobs_total_bucket{a=\"plain value\",le=\"+Inf\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_count{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_sum{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 32.59\n# HELP x Total requests\n# TYPE x gauge\nx{a=\"plain value\",code=\"200\",z=\"/a\\\"b\"} 6.882\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.005\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 21.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 55.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_count{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_sum{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 107.4022\nqueue_depth_bucket{le=\"0.005\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 37.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 64.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_count{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_sum{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 394.1\n# EOF\n") {
        show(got2, "# HELP jobs_total Total requests\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",le=\"5.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 9.0\njobs_total_bucket{a=\"GET\",le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_count{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 13.0\njobs_total_sum{a=\"GET\",path=\"/a\\\"b\",z=\"x\\ny\"} 403.64\njobs_total_bucket{a=\"plain value\",le=\"5.0\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 6.0\njobs_total_bucket{a=\"plain value\",le=\"+Inf\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_count{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 39.0\njobs_total_sum{a=\"plain value\",path=\"back\\\\slash\",z=\"back\\\\slash\"} 32.59\n# HELP x Total requests\n# TYPE x gauge\nx{a=\"plain value\",code=\"200\",z=\"/a\\\"b\"} 6.882\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.005\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 21.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 55.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_count{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 66.0\nqueue_depth_sum{le_not=\"plain value\",path=\"x\\ny\",z=\"caf\xc3\xa9\"} 107.4022\nqueue_depth_bucket{le=\"0.005\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 37.0\nqueue_depth_bucket{le=\"5.0\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 64.0\nqueue_depth_bucket{le=\"+Inf\",le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_count{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 77.0\nqueue_depth_sum{le_not=\"GET\",path=\"x\\ny\",z=\"back\\\\slash\"} 394.1\n# EOF\n")
        ret false
    }
    ret true
}

fn case_28(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 17u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "le_not", value: "x\ny" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "le_not", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..1usize], sum: mem.bitcast[f64](4646147052602631651u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](13869591516487352320u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4608799211066243416u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp3[0usize..2usize], value: mem.bitcast[f64](4646758852714182958u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests A \"quoted\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"+Inf\"} 17.0\nhttp_requests_count 17.0\nhttp_requests_sum 422.883\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{le_not=\"x\\ny\",method=\"back\\\\slash\"} -427.0\njobs_total{le_not=\"GET\",method=\"/a\\\"b\"} 1.359\njobs_total{le_not=\"caf\xc3\xa9\",method=\"\"} 457.65981\n") {
        show(got, "# HELP http_requests A \"quoted\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"+Inf\"} 17.0\nhttp_requests_count 17.0\nhttp_requests_sum 422.883\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{le_not=\"x\\ny\",method=\"back\\\\slash\"} -427.0\njobs_total{le_not=\"GET\",method=\"/a\\\"b\"} 1.359\njobs_total{le_not=\"caf\xc3\xa9\",method=\"\"} 457.65981\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"+Inf\"} 17.0\nhttp_requests_count 17.0\nhttp_requests_sum 422.883\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{le_not=\"x\\ny\",method=\"back\\\\slash\"} -427.0\njobs_total{le_not=\"GET\",method=\"/a\\\"b\"} 1.359\njobs_total{le_not=\"caf\xc3\xa9\",method=\"\"} 457.65981\n# EOF\n") {
        show(got2, "# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"+Inf\"} 17.0\nhttp_requests_count 17.0\nhttp_requests_sum 422.883\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{le_not=\"x\\ny\",method=\"back\\\\slash\"} -427.0\njobs_total{le_not=\"GET\",method=\"/a\\\"b\"} 1.359\njobs_total{le_not=\"caf\xc3\xa9\",method=\"\"} 457.65981\n# EOF\n")
        ret false
    }
    ret true
}

fn case_29(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "code", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "code", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "x_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4679431534019608576u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4680226549645967360u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total{a=\"200\",code=\"x\\ny\"} 68323.0\nx_total{a=\"/a\\\"b\",code=\"/a\\\"b\"} 79892.0\n") {
        show(got, "# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total{a=\"200\",code=\"x\\ny\"} 68323.0\nx_total{a=\"/a\\\"b\",code=\"/a\\\"b\"} 79892.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total{a=\"200\",code=\"x\\ny\"} 68323.0\nx_total{a=\"/a\\\"b\",code=\"/a\\\"b\"} 79892.0\n# EOF\n") {
        show(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total{a=\"200\",code=\"x\\ny\"} 68323.0\nx_total{a=\"/a\\\"b\",code=\"/a\\\"b\"} 79892.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_30(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "a", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "a", value: "x\ny" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "tab\there", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4741671816358002688u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x", help: "tab\there", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4465333615686632963u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "tab\there", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4677842670997995520u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP x_total tab\there\n# TYPE x_total counter\nx_total{a=\"\",z=\"x\\ny\"} 9.99999999e+08\nx_total{a=\"/a\\\"b\",z=\"\"} 3.5e-10\nx_total{a=\"x\\ny\",z=\"/a\\\"b\"} 55369.0\n") {
        show(got, "# HELP x_total tab\there\n# TYPE x_total counter\nx_total{a=\"\",z=\"x\\ny\"} 9.99999999e+08\nx_total{a=\"/a\\\"b\",z=\"\"} 3.5e-10\nx_total{a=\"x\\ny\",z=\"/a\\\"b\"} 55369.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x tab\there\n# TYPE x counter\nx_total{a=\"\",z=\"x\\ny\"} 9.99999999e+08\nx_total{a=\"/a\\\"b\",z=\"\"} 3.5e-10\nx_total{a=\"x\\ny\",z=\"/a\\\"b\"} 55369.0\n# EOF\n") {
        show(got2, "# HELP x tab\there\n# TYPE x counter\nx_total{a=\"\",z=\"x\\ny\"} 9.99999999e+08\nx_total{a=\"/a\\\"b\",z=\"\"} 3.5e-10\nx_total{a=\"x\\ny\",z=\"/a\\\"b\"} 55369.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_31(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "back\\slash" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..1usize], value: mem.bitcast[f64](13870420108450044314u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](4548686525128629352u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4649069413771771904u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Gauge, labels: labp3[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Gauge, labels: labp4[0usize..1usize], value: mem.bitcast[f64](4465333615686632963u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{path=\"plain value\"} -474.1\ntemp_c_total{path=\"/a\\\"b\"} 0.00012345\ntemp_c_total{path=\"GET\"} 666.0\n# HELP queue_depth Total requests\n# TYPE queue_depth gauge\nqueue_depth{z=\"back\\\\slash\"} 0.30000000000000004\nqueue_depth{z=\"/a\\\"b\"} 3.5e-10\n") {
        show(got, "# HELP temp_c_total caf\xc3\xa9 au lait\n# TYPE temp_c_total counter\ntemp_c_total{path=\"plain value\"} -474.1\ntemp_c_total{path=\"/a\\\"b\"} 0.00012345\ntemp_c_total{path=\"GET\"} 666.0\n# HELP queue_depth Total requests\n# TYPE queue_depth gauge\nqueue_depth{z=\"back\\\\slash\"} 0.30000000000000004\nqueue_depth{z=\"/a\\\"b\"} 3.5e-10\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{path=\"plain value\"} -474.1\ntemp_c_total{path=\"/a\\\"b\"} 0.00012345\ntemp_c_total{path=\"GET\"} 666.0\n# HELP queue_depth Total requests\n# TYPE queue_depth gauge\nqueue_depth{z=\"back\\\\slash\"} 0.30000000000000004\nqueue_depth{z=\"/a\\\"b\"} 3.5e-10\n# EOF\n") {
        show(got2, "# HELP temp_c caf\xc3\xa9 au lait\n# TYPE temp_c counter\ntemp_c_total{path=\"plain value\"} -474.1\ntemp_c_total{path=\"/a\\\"b\"} 0.00012345\ntemp_c_total{path=\"GET\"} 666.0\n# HELP queue_depth Total requests\n# TYPE queue_depth gauge\nqueue_depth{z=\"back\\\\slash\"} 0.30000000000000004\nqueue_depth{z=\"/a\\\"b\"} 3.5e-10\n# EOF\n")
        ret false
    }
    ret true
}

fn case_32(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "GET" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "code", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "code", value: "GET" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "" } }
    let bndp3: [3]f64 = [3]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64) }
    let cump3: [4]u64 = [4]u64{ 30u64, 41u64, 77u64, 118u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "plain value" } }
    let bndp4: [3]f64 = [3]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64) }
    let cump4: [4]u64 = [4]u64{ 33u64, 80u64, 112u64, 113u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4646179351856209199u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp1[0usize..3usize], value: mem.bitcast[f64](4619213785204537688u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4642953068080965616u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests_47", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp3[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..3usize], buckets: cump3[0usize..4usize], sum: mem.bitcast[f64](4645721620767519539u64) }
    samples[4] = x.Sample{ name: "http_requests_47", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp4[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..3usize], buckets: cump4[0usize..4usize], sum: mem.bitcast[f64](4635945642982637568u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total back\\\\slash and\\nnewline\n# TYPE http_requests_total counter\nhttp_requests_total{code=\"GET\",method=\"caf\xc3\xa9\",z=\"GET\"} 424.719\nhttp_requests_total{code=\"/a\\\"b\",method=\"back\\\\slash\",z=\"caf\xc3\xa9\"} 6.686\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\",z=\"200\"} 248.663\n# HELP http_requests_47 A \"quoted\" help\n# TYPE http_requests_47 histogram\nhttp_requests_47_bucket{le=\"0.005\",path=\"\"} 30.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"\"} 41.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"\"} 77.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"\"} 118.0\nhttp_requests_47_count{path=\"\"} 118.0\nhttp_requests_47_sum{path=\"\"} 398.7\nhttp_requests_47_bucket{le=\"0.005\",path=\"plain value\"} 33.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"plain value\"} 80.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"plain value\"} 112.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"plain value\"} 113.0\nhttp_requests_47_count{path=\"plain value\"} 113.0\nhttp_requests_47_sum{path=\"plain value\"} 88.75\n") {
        show(got, "# HELP http_requests_total back\\\\slash and\\nnewline\n# TYPE http_requests_total counter\nhttp_requests_total{code=\"GET\",method=\"caf\xc3\xa9\",z=\"GET\"} 424.719\nhttp_requests_total{code=\"/a\\\"b\",method=\"back\\\\slash\",z=\"caf\xc3\xa9\"} 6.686\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\",z=\"200\"} 248.663\n# HELP http_requests_47 A \"quoted\" help\n# TYPE http_requests_47 histogram\nhttp_requests_47_bucket{le=\"0.005\",path=\"\"} 30.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"\"} 41.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"\"} 77.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"\"} 118.0\nhttp_requests_47_count{path=\"\"} 118.0\nhttp_requests_47_sum{path=\"\"} 398.7\nhttp_requests_47_bucket{le=\"0.005\",path=\"plain value\"} 33.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"plain value\"} 80.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"plain value\"} 112.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"plain value\"} 113.0\nhttp_requests_47_count{path=\"plain value\"} 113.0\nhttp_requests_47_sum{path=\"plain value\"} 88.75\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests counter\nhttp_requests_total{code=\"GET\",method=\"caf\xc3\xa9\",z=\"GET\"} 424.719\nhttp_requests_total{code=\"/a\\\"b\",method=\"back\\\\slash\",z=\"caf\xc3\xa9\"} 6.686\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\",z=\"200\"} 248.663\n# HELP http_requests_47 A \\\"quoted\\\" help\n# TYPE http_requests_47 histogram\nhttp_requests_47_bucket{le=\"0.005\",path=\"\"} 30.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"\"} 41.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"\"} 77.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"\"} 118.0\nhttp_requests_47_count{path=\"\"} 118.0\nhttp_requests_47_sum{path=\"\"} 398.7\nhttp_requests_47_bucket{le=\"0.005\",path=\"plain value\"} 33.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"plain value\"} 80.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"plain value\"} 112.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"plain value\"} 113.0\nhttp_requests_47_count{path=\"plain value\"} 113.0\nhttp_requests_47_sum{path=\"plain value\"} 88.75\n# EOF\n") {
        show(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests counter\nhttp_requests_total{code=\"GET\",method=\"caf\xc3\xa9\",z=\"GET\"} 424.719\nhttp_requests_total{code=\"/a\\\"b\",method=\"back\\\\slash\",z=\"caf\xc3\xa9\"} 6.686\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\",z=\"200\"} 248.663\n# HELP http_requests_47 A \\\"quoted\\\" help\n# TYPE http_requests_47 histogram\nhttp_requests_47_bucket{le=\"0.005\",path=\"\"} 30.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"\"} 41.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"\"} 77.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"\"} 118.0\nhttp_requests_47_count{path=\"\"} 118.0\nhttp_requests_47_sum{path=\"\"} 398.7\nhttp_requests_47_bucket{le=\"0.005\",path=\"plain value\"} 33.0\nhttp_requests_47_bucket{le=\"0.25\",path=\"plain value\"} 80.0\nhttp_requests_47_bucket{le=\"2.5\",path=\"plain value\"} 112.0\nhttp_requests_47_bucket{le=\"+Inf\",path=\"plain value\"} 113.0\nhttp_requests_47_count{path=\"plain value\"} 113.0\nhttp_requests_47_sum{path=\"plain value\"} 88.75\n# EOF\n")
        ret false
    }
    ret true
}

fn case_33(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "back\\slash" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "" }, x.Label{ name: "a", value: "200" } }
    let bndp3: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [3]u64 = [3]u64{ 28u64, 58u64, 74u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp0[0usize..1usize], value: mem.bitcast[f64](4611809867417140593u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](13868316046143502397u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp2[0usize..0usize], value: mem.bitcast[f64](4705844345939427328u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..2usize], buckets: cump3[0usize..3usize], sum: mem.bitcast[f64](4646325032748843008u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{le_not=\"back\\\\slash\"} 2.055\njobs_total{le_not=\"caf\xc3\xa9\"} -354.497905\n# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total 4e+06\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"200\",le=\"0.3\",z=\"\"} 28.0\nqueue_depth_bucket{a=\"200\",le=\"100.0\",z=\"\"} 58.0\nqueue_depth_bucket{a=\"200\",le=\"+Inf\",z=\"\"} 74.0\nqueue_depth_count{a=\"200\",z=\"\"} 74.0\nqueue_depth_sum{a=\"200\",z=\"\"} 433.0\n") {
        show(got, "# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{le_not=\"back\\\\slash\"} 2.055\njobs_total{le_not=\"caf\xc3\xa9\"} -354.497905\n# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total 4e+06\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"200\",le=\"0.3\",z=\"\"} 28.0\nqueue_depth_bucket{a=\"200\",le=\"100.0\",z=\"\"} 58.0\nqueue_depth_bucket{a=\"200\",le=\"+Inf\",z=\"\"} 74.0\nqueue_depth_count{a=\"200\",z=\"\"} 74.0\nqueue_depth_sum{a=\"200\",z=\"\"} 433.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{le_not=\"back\\\\slash\"} 2.055\njobs_total{le_not=\"caf\xc3\xa9\"} -354.497905\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total 4e+06\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"200\",le=\"0.3\",z=\"\"} 28.0\nqueue_depth_bucket{a=\"200\",le=\"100.0\",z=\"\"} 58.0\nqueue_depth_bucket{a=\"200\",le=\"+Inf\",z=\"\"} 74.0\nqueue_depth_count{a=\"200\",z=\"\"} 74.0\nqueue_depth_sum{a=\"200\",z=\"\"} 433.0\n# EOF\n") {
        show(got2, "# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{le_not=\"back\\\\slash\"} 2.055\njobs_total{le_not=\"caf\xc3\xa9\"} -354.497905\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total 4e+06\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"200\",le=\"0.3\",z=\"\"} 28.0\nqueue_depth_bucket{a=\"200\",le=\"100.0\",z=\"\"} 58.0\nqueue_depth_bucket{a=\"200\",le=\"+Inf\",z=\"\"} 74.0\nqueue_depth_count{a=\"200\",z=\"\"} 74.0\nqueue_depth_sum{a=\"200\",z=\"\"} 433.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_34(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](9223372036854775808u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4678319859044450304u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{code=\"200\"} 0.0\ntemp_c_total{code=\"\"} -0.0\ntemp_c_total{code=\"caf\xc3\xa9\"} 58841.0\n") {
        show(got, "# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{code=\"200\"} 0.0\ntemp_c_total{code=\"\"} -0.0\ntemp_c_total{code=\"caf\xc3\xa9\"} 58841.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{code=\"200\"} 0.0\ntemp_c_total{code=\"\"} -0.0\ntemp_c_total{code=\"caf\xc3\xa9\"} 58841.0\n# EOF\n") {
        show(got2, "# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{code=\"200\"} 0.0\ntemp_c_total{code=\"\"} -0.0\ntemp_c_total{code=\"caf\xc3\xa9\"} 58841.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_35(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "plain value" }, x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "z", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump2: [4]u64 = [4]u64{ 6u64, 51u64, 78u64, 126u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](13872280728414845927u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labp1[0usize..3usize], value: mem.bitcast[f64](13873752068486856704u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labp2[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4647310195167330304u64) }
    samples[3] = x.Sample{ name: "latency_seconds_78_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp3[0usize..0usize], value: mem.bitcast[f64](13874463924578748092u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds_total Total requests\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"x\\ny\",code=\"plain value\",z=\"plain value\"} -647.728\nlatency_seconds_total{a=\"/a\\\"b\",code=\"back\\\\slash\",z=\"caf\xc3\xa9\"} -815.0\n# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.1\"} 6.0\nqueue_depth_bucket{le=\"0.3\"} 51.0\nqueue_depth_bucket{le=\"100.0\"} 78.0\nqueue_depth_bucket{le=\"+Inf\"} 126.0\nqueue_depth_count 126.0\nqueue_depth_sum 489.0\n# HELP latency_seconds_78_total caf\xc3\xa9 au lait\n# TYPE latency_seconds_78_total counter\nlatency_seconds_78_total -895.928668\n") {
        show(got, "# HELP latency_seconds_total Total requests\n# TYPE latency_seconds_total counter\nlatency_seconds_total{a=\"x\\ny\",code=\"plain value\",z=\"plain value\"} -647.728\nlatency_seconds_total{a=\"/a\\\"b\",code=\"back\\\\slash\",z=\"caf\xc3\xa9\"} -815.0\n# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.1\"} 6.0\nqueue_depth_bucket{le=\"0.3\"} 51.0\nqueue_depth_bucket{le=\"100.0\"} 78.0\nqueue_depth_bucket{le=\"+Inf\"} 126.0\nqueue_depth_count 126.0\nqueue_depth_sum 489.0\n# HELP latency_seconds_78_total caf\xc3\xa9 au lait\n# TYPE latency_seconds_78_total counter\nlatency_seconds_78_total -895.928668\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds Total requests\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"x\\ny\",code=\"plain value\",z=\"plain value\"} -647.728\nlatency_seconds_total{a=\"/a\\\"b\",code=\"back\\\\slash\",z=\"caf\xc3\xa9\"} -815.0\n# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.1\"} 6.0\nqueue_depth_bucket{le=\"0.3\"} 51.0\nqueue_depth_bucket{le=\"100.0\"} 78.0\nqueue_depth_bucket{le=\"+Inf\"} 126.0\nqueue_depth_count 126.0\nqueue_depth_sum 489.0\n# HELP latency_seconds_78 caf\xc3\xa9 au lait\n# TYPE latency_seconds_78 counter\nlatency_seconds_78_total -895.928668\n# EOF\n") {
        show(got2, "# HELP latency_seconds Total requests\n# TYPE latency_seconds counter\nlatency_seconds_total{a=\"x\\ny\",code=\"plain value\",z=\"plain value\"} -647.728\nlatency_seconds_total{a=\"/a\\\"b\",code=\"back\\\\slash\",z=\"caf\xc3\xa9\"} -815.0\n# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"0.1\"} 6.0\nqueue_depth_bucket{le=\"0.3\"} 51.0\nqueue_depth_bucket{le=\"100.0\"} 78.0\nqueue_depth_bucket{le=\"+Inf\"} 126.0\nqueue_depth_count 126.0\nqueue_depth_sum 489.0\n# HELP latency_seconds_78 caf\xc3\xa9 au lait\n# TYPE latency_seconds_78 counter\nlatency_seconds_78_total -895.928668\n# EOF\n")
        ret false
    }
    ret true
}

fn case_36(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [4]u64 = [4]u64{ 31u64, 40u64, 87u64, 92u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump1: [4]u64 = [4]u64{ 3u64, 28u64, 46u64, 84u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4646193091353509888u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4645832451539599360u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 31.0\nhttp_requests_bucket{le=\"2.5\",path=\"/a\\\"b\",z=\"x\\ny\"} 40.0\nhttp_requests_bucket{le=\"10.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 87.0\nhttp_requests_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_count{path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 425.5\nhttp_requests_bucket{le=\"0.1\",path=\"caf\xc3\xa9\",z=\"GET\"} 3.0\nhttp_requests_bucket{le=\"2.5\",path=\"caf\xc3\xa9\",z=\"GET\"} 28.0\nhttp_requests_bucket{le=\"10.0\",path=\"caf\xc3\xa9\",z=\"GET\"} 46.0\nhttp_requests_bucket{le=\"+Inf\",path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_count{path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_sum{path=\"caf\xc3\xa9\",z=\"GET\"} 405.0\n") {
        show(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 31.0\nhttp_requests_bucket{le=\"2.5\",path=\"/a\\\"b\",z=\"x\\ny\"} 40.0\nhttp_requests_bucket{le=\"10.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 87.0\nhttp_requests_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_count{path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 425.5\nhttp_requests_bucket{le=\"0.1\",path=\"caf\xc3\xa9\",z=\"GET\"} 3.0\nhttp_requests_bucket{le=\"2.5\",path=\"caf\xc3\xa9\",z=\"GET\"} 28.0\nhttp_requests_bucket{le=\"10.0\",path=\"caf\xc3\xa9\",z=\"GET\"} 46.0\nhttp_requests_bucket{le=\"+Inf\",path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_count{path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_sum{path=\"caf\xc3\xa9\",z=\"GET\"} 405.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 31.0\nhttp_requests_bucket{le=\"2.5\",path=\"/a\\\"b\",z=\"x\\ny\"} 40.0\nhttp_requests_bucket{le=\"10.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 87.0\nhttp_requests_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_count{path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 425.5\nhttp_requests_bucket{le=\"0.1\",path=\"caf\xc3\xa9\",z=\"GET\"} 3.0\nhttp_requests_bucket{le=\"2.5\",path=\"caf\xc3\xa9\",z=\"GET\"} 28.0\nhttp_requests_bucket{le=\"10.0\",path=\"caf\xc3\xa9\",z=\"GET\"} 46.0\nhttp_requests_bucket{le=\"+Inf\",path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_count{path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_sum{path=\"caf\xc3\xa9\",z=\"GET\"} 405.0\n# EOF\n") {
        show(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",path=\"/a\\\"b\",z=\"x\\ny\"} 31.0\nhttp_requests_bucket{le=\"2.5\",path=\"/a\\\"b\",z=\"x\\ny\"} 40.0\nhttp_requests_bucket{le=\"10.0\",path=\"/a\\\"b\",z=\"x\\ny\"} 87.0\nhttp_requests_bucket{le=\"+Inf\",path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_count{path=\"/a\\\"b\",z=\"x\\ny\"} 92.0\nhttp_requests_sum{path=\"/a\\\"b\",z=\"x\\ny\"} 425.5\nhttp_requests_bucket{le=\"0.1\",path=\"caf\xc3\xa9\",z=\"GET\"} 3.0\nhttp_requests_bucket{le=\"2.5\",path=\"caf\xc3\xa9\",z=\"GET\"} 28.0\nhttp_requests_bucket{le=\"10.0\",path=\"caf\xc3\xa9\",z=\"GET\"} 46.0\nhttp_requests_bucket{le=\"+Inf\",path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_count{path=\"caf\xc3\xa9\",z=\"GET\"} 84.0\nhttp_requests_sum{path=\"caf\xc3\xa9\",z=\"GET\"} 405.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_37(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4636737291354636288u64) }
    let cump1: [2]u64 = [2]u64{ 2u64, 43u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "a", value: "plain value" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](4636737291354636288u64) }
    let cump2: [2]u64 = [2]u64{ 1u64, 10u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "a", value: "" }, x.Label{ name: "z", value: "200" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [2]u64 = [2]u64{ 25u64, 30u64 }
    let labp4: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "GET" }, x.Label{ name: "method", value: "200" }, x.Label{ name: "le_not", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](4599075939470750515u64) }
    let cump4: [2]u64 = [2]u64{ 29u64, 75u64 }
    let labp5: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "200" }, x.Label{ name: "le_not", value: "plain value" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](4599075939470750515u64) }
    let cump5: [2]u64 = [2]u64{ 0u64, 43u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp0[0usize..1usize], value: mem.bitcast[f64](4547007122018943789u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4646500954609287168u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..1usize], buckets: cump2[0usize..2usize], sum: mem.bitcast[f64](4646464098979524116u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..1usize], buckets: cump3[0usize..2usize], sum: mem.bitcast[f64](4647161099631385274u64) }
    samples[4] = x.Sample{ name: "x", help: "", kind: x.Kind.Histogram, labels: labp4[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..1usize], buckets: cump4[0usize..2usize], sum: mem.bitcast[f64](4632187248356108534u64) }
    samples[5] = x.Sample{ name: "x", help: "", kind: x.Kind.Histogram, labels: labp5[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp5[0usize..1usize], buckets: cump5[0usize..2usize], sum: mem.bitcast[f64](4634907704006017024u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total counter\njobs_total{code=\"plain value\"} 0.0001\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"x\\ny\",le=\"100.0\",le_not=\"plain value\",z=\"back\\\\slash\"} 2.0\nlatency_seconds_bucket{a=\"x\\ny\",le=\"+Inf\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_count{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_sum{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 443.0\nlatency_seconds_bucket{a=\"plain value\",le=\"100.0\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 1.0\nlatency_seconds_bucket{a=\"plain value\",le=\"+Inf\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_count{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_sum{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 440.905\nlatency_seconds_bucket{a=\"\",le=\"100.0\",le_not=\"back\\\\slash\",z=\"200\"} 25.0\nlatency_seconds_bucket{a=\"\",le=\"+Inf\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_count{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_sum{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 480.5249\n# HELP x \n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 29.0\nx_bucket{le=\"+Inf\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_count{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_sum{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 49.67\nx_bucket{le=\"0.3\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 0.0\nx_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_count{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_sum{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 74.0\n") {
        show(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total counter\njobs_total{code=\"plain value\"} 0.0001\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"x\\ny\",le=\"100.0\",le_not=\"plain value\",z=\"back\\\\slash\"} 2.0\nlatency_seconds_bucket{a=\"x\\ny\",le=\"+Inf\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_count{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_sum{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 443.0\nlatency_seconds_bucket{a=\"plain value\",le=\"100.0\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 1.0\nlatency_seconds_bucket{a=\"plain value\",le=\"+Inf\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_count{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_sum{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 440.905\nlatency_seconds_bucket{a=\"\",le=\"100.0\",le_not=\"back\\\\slash\",z=\"200\"} 25.0\nlatency_seconds_bucket{a=\"\",le=\"+Inf\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_count{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_sum{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 480.5249\n# HELP x \n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 29.0\nx_bucket{le=\"+Inf\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_count{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_sum{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 49.67\nx_bucket{le=\"0.3\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 0.0\nx_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_count{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_sum{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 74.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs back\\\\slash and\\nnewline\n# TYPE jobs counter\njobs_total{code=\"plain value\"} 0.0001\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"x\\ny\",le=\"100.0\",le_not=\"plain value\",z=\"back\\\\slash\"} 2.0\nlatency_seconds_bucket{a=\"x\\ny\",le=\"+Inf\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_count{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_sum{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 443.0\nlatency_seconds_bucket{a=\"plain value\",le=\"100.0\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 1.0\nlatency_seconds_bucket{a=\"plain value\",le=\"+Inf\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_count{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_sum{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 440.905\nlatency_seconds_bucket{a=\"\",le=\"100.0\",le_not=\"back\\\\slash\",z=\"200\"} 25.0\nlatency_seconds_bucket{a=\"\",le=\"+Inf\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_count{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_sum{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 480.5249\n# HELP x \n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 29.0\nx_bucket{le=\"+Inf\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_count{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_sum{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 49.67\nx_bucket{le=\"0.3\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 0.0\nx_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_count{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_sum{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 74.0\n# EOF\n") {
        show(got2, "# HELP jobs back\\\\slash and\\nnewline\n# TYPE jobs counter\njobs_total{code=\"plain value\"} 0.0001\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"x\\ny\",le=\"100.0\",le_not=\"plain value\",z=\"back\\\\slash\"} 2.0\nlatency_seconds_bucket{a=\"x\\ny\",le=\"+Inf\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_count{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 43.0\nlatency_seconds_sum{a=\"x\\ny\",le_not=\"plain value\",z=\"back\\\\slash\"} 443.0\nlatency_seconds_bucket{a=\"plain value\",le=\"100.0\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 1.0\nlatency_seconds_bucket{a=\"plain value\",le=\"+Inf\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_count{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 10.0\nlatency_seconds_sum{a=\"plain value\",le_not=\"GET\",z=\"caf\xc3\xa9\"} 440.905\nlatency_seconds_bucket{a=\"\",le=\"100.0\",le_not=\"back\\\\slash\",z=\"200\"} 25.0\nlatency_seconds_bucket{a=\"\",le=\"+Inf\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_count{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 30.0\nlatency_seconds_sum{a=\"\",le_not=\"back\\\\slash\",z=\"200\"} 480.5249\n# HELP x \n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 29.0\nx_bucket{le=\"+Inf\",le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_count{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 75.0\nx_sum{le_not=\"/a\\\"b\",method=\"200\",path=\"GET\"} 49.67\nx_bucket{le=\"0.3\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 0.0\nx_bucket{le=\"+Inf\",le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_count{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 43.0\nx_sum{le_not=\"plain value\",method=\"200\",path=\"caf\xc3\xa9\"} 74.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_38(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4741671816358002688u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total 9.99999999e+08\n") {
        show(got, "# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total 9.99999999e+08\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total 9.99999999e+08\n# EOF\n") {
        show(got2, "# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total 9.99999999e+08\n# EOF\n")
        ret false
    }
    ret true
}

fn case_39(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "path", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "x\ny" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Gauge, labels: labp0[0usize..2usize], value: mem.bitcast[f64](13867228885901587251u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Gauge, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4620340811011287155u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4532020583610935537u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp3[0usize..1usize], value: mem.bitcast[f64](13925995157322203136u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labp4[0usize..0usize], value: mem.bitcast[f64](4547007122018943789u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests tab\there\n# TYPE http_requests gauge\nhttp_requests{a=\"\",path=\"x\\ny\"} -292.7\nhttp_requests{a=\"back\\\\slash\",path=\"back\\\\slash\"} 7.687\n# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"back\\\\slash\"} 1e-05\nlatency_seconds_total{le_not=\"x\\ny\"} -2500000.0\n# HELP queue_depth A \"quoted\" help\n# TYPE queue_depth gauge\nqueue_depth 0.0001\n") {
        show(got, "# HELP http_requests tab\there\n# TYPE http_requests gauge\nhttp_requests{a=\"\",path=\"x\\ny\"} -292.7\nhttp_requests{a=\"back\\\\slash\",path=\"back\\\\slash\"} 7.687\n# HELP latency_seconds_total back\\\\slash and\\nnewline\n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"back\\\\slash\"} 1e-05\nlatency_seconds_total{le_not=\"x\\ny\"} -2500000.0\n# HELP queue_depth A \"quoted\" help\n# TYPE queue_depth gauge\nqueue_depth 0.0001\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests tab\there\n# TYPE http_requests gauge\nhttp_requests{a=\"\",path=\"x\\ny\"} -292.7\nhttp_requests{a=\"back\\\\slash\",path=\"back\\\\slash\"} 7.687\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"back\\\\slash\"} 1e-05\nlatency_seconds_total{le_not=\"x\\ny\"} -2500000.0\n# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth gauge\nqueue_depth 0.0001\n# EOF\n") {
        show(got2, "# HELP http_requests tab\there\n# TYPE http_requests gauge\nhttp_requests{a=\"\",path=\"x\\ny\"} -292.7\nhttp_requests{a=\"back\\\\slash\",path=\"back\\\\slash\"} 7.687\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"back\\\\slash\"} 1e-05\nlatency_seconds_total{le_not=\"x\\ny\"} -2500000.0\n# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth gauge\nqueue_depth 0.0001\n# EOF\n")
        ret false
    }
    ret true
}

fn case_40(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4741671816358002688u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "queue_depth_54", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](13871639370088224653u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total 9.99999999e+08\n# HELP queue_depth_54_total A \"quoted\" help\n# TYPE queue_depth_54_total counter\nqueue_depth_54_total{method=\"back\\\\slash\"} -574.814\n") {
        show(got, "# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total 9.99999999e+08\n# HELP queue_depth_54_total A \"quoted\" help\n# TYPE queue_depth_54_total counter\nqueue_depth_54_total{method=\"back\\\\slash\"} -574.814\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total 9.99999999e+08\n# HELP queue_depth_54 A \\\"quoted\\\" help\n# TYPE queue_depth_54 counter\nqueue_depth_54_total{method=\"back\\\\slash\"} -574.814\n# EOF\n") {
        show(got2, "# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total 9.99999999e+08\n# HELP queue_depth_54 A \\\"quoted\\\" help\n# TYPE queue_depth_54 counter\nqueue_depth_54_total{method=\"back\\\\slash\"} -574.814\n# EOF\n")
        ret false
    }
    ret true
}

fn case_41(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "/a\"b" }, x.Label{ name: "z", value: "" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "method", value: "/a\"b" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "method", value: "back\\slash" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    let labp5: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "GET" }, x.Label{ name: "method", value: "back\\slash" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Gauge, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4650881607989931845u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Counter, labels: labp1[0usize..3usize], value: mem.bitcast[f64](4617940392409898680u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4741671816358002688u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp3[0usize..2usize], value: mem.bitcast[f64](4607182418800017408u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp4[0usize..2usize], value: mem.bitcast[f64](4621646291953271177u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp5[0usize..2usize], value: mem.bitcast[f64](4696837146684686336u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total \n# TYPE jobs_total gauge\njobs_total 872.02263\n# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"back\\\\slash\",path=\"caf\xc3\xa9\",z=\"back\\\\slash\"} 5.555\nlatency_seconds_total{le_not=\"/a\\\"b\",path=\"caf\xc3\xa9\",z=\"\"} 9.99999999e+08\n# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total{code=\"back\\\\slash\",method=\"/a\\\"b\"} 1.0\nhttp_requests_total{code=\"back\\\\slash\",method=\"back\\\\slash\"} 9.693\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\"} 1e+06\n") {
        show(got, "# HELP jobs_total \n# TYPE jobs_total gauge\njobs_total 872.02263\n# HELP latency_seconds_total \n# TYPE latency_seconds_total counter\nlatency_seconds_total{le_not=\"back\\\\slash\",path=\"caf\xc3\xa9\",z=\"back\\\\slash\"} 5.555\nlatency_seconds_total{le_not=\"/a\\\"b\",path=\"caf\xc3\xa9\",z=\"\"} 9.99999999e+08\n# HELP http_requests_total A \"quoted\" help\n# TYPE http_requests_total counter\nhttp_requests_total{code=\"back\\\\slash\",method=\"/a\\\"b\"} 1.0\nhttp_requests_total{code=\"back\\\\slash\",method=\"back\\\\slash\"} 9.693\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\"} 1e+06\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total \n# TYPE jobs_total gauge\njobs_total 872.02263\n# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"back\\\\slash\",path=\"caf\xc3\xa9\",z=\"back\\\\slash\"} 5.555\nlatency_seconds_total{le_not=\"/a\\\"b\",path=\"caf\xc3\xa9\",z=\"\"} 9.99999999e+08\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total{code=\"back\\\\slash\",method=\"/a\\\"b\"} 1.0\nhttp_requests_total{code=\"back\\\\slash\",method=\"back\\\\slash\"} 9.693\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\"} 1e+06\n# EOF\n") {
        show(got2, "# HELP jobs_total \n# TYPE jobs_total gauge\njobs_total 872.02263\n# HELP latency_seconds \n# TYPE latency_seconds counter\nlatency_seconds_total{le_not=\"back\\\\slash\",path=\"caf\xc3\xa9\",z=\"back\\\\slash\"} 5.555\nlatency_seconds_total{le_not=\"/a\\\"b\",path=\"caf\xc3\xa9\",z=\"\"} 9.99999999e+08\n# HELP http_requests A \\\"quoted\\\" help\n# TYPE http_requests counter\nhttp_requests_total{code=\"back\\\\slash\",method=\"/a\\\"b\"} 1.0\nhttp_requests_total{code=\"back\\\\slash\",method=\"back\\\\slash\"} 9.693\nhttp_requests_total{code=\"GET\",method=\"back\\\\slash\"} 1e+06\n# EOF\n")
        ret false
    }
    ret true
}

fn case_42(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "GET" } }
    let bndp0: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump0: [3]u64 = [3]u64{ 10u64, 45u64, 63u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "x\ny" } }
    let bndp1: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump1: [3]u64 = [3]u64{ 17u64, 37u64, 57u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "x\ny" }, x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "le_not", value: "200" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "200" }, x.Label{ name: "le_not", value: "back\\slash" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "GET" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    let labp5: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..2usize], buckets: cump0[0usize..3usize], sum: mem.bitcast[f64](4636483963875596698u64) }
    samples[1] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..2usize], buckets: cump1[0usize..3usize], sum: mem.bitcast[f64](4640903121009953997u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4696837146684686336u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp3[0usize..3usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Counter, labels: labp4[0usize..1usize], value: mem.bitcast[f64](4651061153576818364u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Counter, labels: labp5[0usize..1usize], value: mem.bitcast[f64](4621681194850383299u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP x A \"quoted\" help\n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"GET\"} 10.0\nx_bucket{le=\"5.0\",le_not=\"GET\"} 45.0\nx_bucket{le=\"+Inf\",le_not=\"GET\"} 63.0\nx_count{le_not=\"GET\"} 63.0\nx_sum{le_not=\"GET\"} 96.4\nx_bucket{le=\"0.3\",le_not=\"x\\ny\"} 17.0\nx_bucket{le=\"5.0\",le_not=\"x\\ny\"} 37.0\nx_bucket{le=\"+Inf\",le_not=\"x\\ny\"} 57.0\nx_count{le_not=\"x\\ny\"} 57.0\nx_sum{le_not=\"x\\ny\"} 190.4\n# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"x\\ny\",le_not=\"200\",path=\"back\\\\slash\"} 1e+06\nhttp_requests{code=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",path=\"200\"} 0.30000000000000004\n# HELP temp_c_total tab\there\n# TYPE temp_c_total counter\ntemp_c_total{code=\"GET\"} 892.4346\ntemp_c_total{code=\"200\"} 9.755\n") {
        show(got, "# HELP x A \"quoted\" help\n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"GET\"} 10.0\nx_bucket{le=\"5.0\",le_not=\"GET\"} 45.0\nx_bucket{le=\"+Inf\",le_not=\"GET\"} 63.0\nx_count{le_not=\"GET\"} 63.0\nx_sum{le_not=\"GET\"} 96.4\nx_bucket{le=\"0.3\",le_not=\"x\\ny\"} 17.0\nx_bucket{le=\"5.0\",le_not=\"x\\ny\"} 37.0\nx_bucket{le=\"+Inf\",le_not=\"x\\ny\"} 57.0\nx_count{le_not=\"x\\ny\"} 57.0\nx_sum{le_not=\"x\\ny\"} 190.4\n# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"x\\ny\",le_not=\"200\",path=\"back\\\\slash\"} 1e+06\nhttp_requests{code=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",path=\"200\"} 0.30000000000000004\n# HELP temp_c_total tab\there\n# TYPE temp_c_total counter\ntemp_c_total{code=\"GET\"} 892.4346\ntemp_c_total{code=\"200\"} 9.755\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"GET\"} 10.0\nx_bucket{le=\"5.0\",le_not=\"GET\"} 45.0\nx_bucket{le=\"+Inf\",le_not=\"GET\"} 63.0\nx_count{le_not=\"GET\"} 63.0\nx_sum{le_not=\"GET\"} 96.4\nx_bucket{le=\"0.3\",le_not=\"x\\ny\"} 17.0\nx_bucket{le=\"5.0\",le_not=\"x\\ny\"} 37.0\nx_bucket{le=\"+Inf\",le_not=\"x\\ny\"} 57.0\nx_count{le_not=\"x\\ny\"} 57.0\nx_sum{le_not=\"x\\ny\"} 190.4\n# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"x\\ny\",le_not=\"200\",path=\"back\\\\slash\"} 1e+06\nhttp_requests{code=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",path=\"200\"} 0.30000000000000004\n# HELP temp_c tab\there\n# TYPE temp_c counter\ntemp_c_total{code=\"GET\"} 892.4346\ntemp_c_total{code=\"200\"} 9.755\n# EOF\n") {
        show(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x histogram\nx_bucket{le=\"0.3\",le_not=\"GET\"} 10.0\nx_bucket{le=\"5.0\",le_not=\"GET\"} 45.0\nx_bucket{le=\"+Inf\",le_not=\"GET\"} 63.0\nx_count{le_not=\"GET\"} 63.0\nx_sum{le_not=\"GET\"} 96.4\nx_bucket{le=\"0.3\",le_not=\"x\\ny\"} 17.0\nx_bucket{le=\"5.0\",le_not=\"x\\ny\"} 37.0\nx_bucket{le=\"+Inf\",le_not=\"x\\ny\"} 57.0\nx_count{le_not=\"x\\ny\"} 57.0\nx_sum{le_not=\"x\\ny\"} 190.4\n# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"x\\ny\",le_not=\"200\",path=\"back\\\\slash\"} 1e+06\nhttp_requests{code=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",path=\"200\"} 0.30000000000000004\n# HELP temp_c tab\there\n# TYPE temp_c counter\ntemp_c_total{code=\"GET\"} 892.4346\ntemp_c_total{code=\"200\"} 9.755\n# EOF\n")
        ret false
    }
    ret true
}

fn case_43(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [3]u64 = [3]u64{ 23u64, 69u64, 71u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [2]f64 = [2]f64{ mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump1: [3]u64 = [3]u64{ 5u64, 42u64, 68u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "z", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "" } }
    let bndp2: [2]f64 = [2]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump2: [3]u64 = [3]u64{ 30u64, 47u64, 82u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..2usize], buckets: cump0[0usize..3usize], sum: mem.bitcast[f64](4645402146668952945u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..2usize], buckets: cump1[0usize..3usize], sum: mem.bitcast[f64](4641005155689011610u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..2usize], buckets: cump2[0usize..3usize], sum: mem.bitcast[f64](4643176031446892544u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.3\"} 23.0\ntemp_c_bucket{le=\"10.0\"} 69.0\ntemp_c_bucket{le=\"+Inf\"} 71.0\ntemp_c_count 71.0\ntemp_c_sum 380.54\n# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"5.0\"} 5.0\nlatency_seconds_bucket{le=\"100000.0\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\"} 68.0\nlatency_seconds_count 68.0\nlatency_seconds_sum 193.3\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests histogram\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"0.3\",method=\"\",z=\"caf\xc3\xa9\"} 30.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"100000.0\",method=\"\",z=\"caf\xc3\xa9\"} 47.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"+Inf\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_count{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_sum{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 255.0\n") {
        show(got, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.3\"} 23.0\ntemp_c_bucket{le=\"10.0\"} 69.0\ntemp_c_bucket{le=\"+Inf\"} 71.0\ntemp_c_count 71.0\ntemp_c_sum 380.54\n# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"5.0\"} 5.0\nlatency_seconds_bucket{le=\"100000.0\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\"} 68.0\nlatency_seconds_count 68.0\nlatency_seconds_sum 193.3\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests histogram\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"0.3\",method=\"\",z=\"caf\xc3\xa9\"} 30.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"100000.0\",method=\"\",z=\"caf\xc3\xa9\"} 47.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"+Inf\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_count{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_sum{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 255.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.3\"} 23.0\ntemp_c_bucket{le=\"10.0\"} 69.0\ntemp_c_bucket{le=\"+Inf\"} 71.0\ntemp_c_count 71.0\ntemp_c_sum 380.54\n# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"5.0\"} 5.0\nlatency_seconds_bucket{le=\"100000.0\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\"} 68.0\nlatency_seconds_count 68.0\nlatency_seconds_sum 193.3\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests histogram\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"0.3\",method=\"\",z=\"caf\xc3\xa9\"} 30.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"100000.0\",method=\"\",z=\"caf\xc3\xa9\"} 47.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"+Inf\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_count{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_sum{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 255.0\n# EOF\n") {
        show(got2, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.3\"} 23.0\ntemp_c_bucket{le=\"10.0\"} 69.0\ntemp_c_bucket{le=\"+Inf\"} 71.0\ntemp_c_count 71.0\ntemp_c_sum 380.54\n# HELP latency_seconds tab\there\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"5.0\"} 5.0\nlatency_seconds_bucket{le=\"100000.0\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\"} 68.0\nlatency_seconds_count 68.0\nlatency_seconds_sum 193.3\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests histogram\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"0.3\",method=\"\",z=\"caf\xc3\xa9\"} 30.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"100000.0\",method=\"\",z=\"caf\xc3\xa9\"} 47.0\nhttp_requests_bucket{a=\"back\\\\slash\",le=\"+Inf\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_count{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 82.0\nhttp_requests_sum{a=\"back\\\\slash\",method=\"\",z=\"caf\xc3\xa9\"} 255.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_44(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "GET" }, x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "200" }, x.Label{ name: "code", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "GET" }, x.Label{ name: "code", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "" }, x.Label{ name: "a", value: "back\\slash" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    let labp5: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "a", value: "caf\xc3\xa9" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 0u64 }
    let labp6: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp6: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump6: [1]u64 = [1]u64{ 0u64 }
    var samples: [7]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4677454680832344064u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4651447877324976947u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labp2[0usize..2usize], value: mem.bitcast[f64](13875264035689435664u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp3[0usize..2usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp4[0usize..2usize], value: mem.bitcast[f64](4696837155274620928u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp5[0usize..2usize], value: mem.bitcast[f64](4619889325148643262u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[6] = x.Sample{ name: "http_requests_5", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp6[0usize..0usize], value: mem.bitcast[f64](9223372036854775808u64), bounds: bndp6[0usize..0usize], buckets: cump6[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..7usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"caf\xc3\xa9\",method=\"GET\"} 52546.0\nhttp_requests{code=\"plain value\",method=\"200\"} 936.4\nhttp_requests{code=\"\",method=\"GET\"} -986.89077\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth gauge\nqueue_depth{a=\"back\\\\slash\",z=\"\"} 1e-07\nqueue_depth{a=\"/a\\\"b\",z=\"GET\"} 1.000001e+06\nqueue_depth{a=\"caf\xc3\xa9\",z=\"x\\ny\"} 7.286\n# HELP http_requests_5 caf\xc3\xa9 au lait\n# TYPE http_requests_5 gauge\nhttp_requests_5 -0.0\n") {
        show(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"caf\xc3\xa9\",method=\"GET\"} 52546.0\nhttp_requests{code=\"plain value\",method=\"200\"} 936.4\nhttp_requests{code=\"\",method=\"GET\"} -986.89077\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth gauge\nqueue_depth{a=\"back\\\\slash\",z=\"\"} 1e-07\nqueue_depth{a=\"/a\\\"b\",z=\"GET\"} 1.000001e+06\nqueue_depth{a=\"caf\xc3\xa9\",z=\"x\\ny\"} 7.286\n# HELP http_requests_5 caf\xc3\xa9 au lait\n# TYPE http_requests_5 gauge\nhttp_requests_5 -0.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..7usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"caf\xc3\xa9\",method=\"GET\"} 52546.0\nhttp_requests{code=\"plain value\",method=\"200\"} 936.4\nhttp_requests{code=\"\",method=\"GET\"} -986.89077\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth gauge\nqueue_depth{a=\"back\\\\slash\",z=\"\"} 1e-07\nqueue_depth{a=\"/a\\\"b\",z=\"GET\"} 1.000001e+06\nqueue_depth{a=\"caf\xc3\xa9\",z=\"x\\ny\"} 7.286\n# HELP http_requests_5 caf\xc3\xa9 au lait\n# TYPE http_requests_5 gauge\nhttp_requests_5 -0.0\n# EOF\n") {
        show(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests gauge\nhttp_requests{code=\"caf\xc3\xa9\",method=\"GET\"} 52546.0\nhttp_requests{code=\"plain value\",method=\"200\"} 936.4\nhttp_requests{code=\"\",method=\"GET\"} -986.89077\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth gauge\nqueue_depth{a=\"back\\\\slash\",z=\"\"} 1e-07\nqueue_depth{a=\"/a\\\"b\",z=\"GET\"} 1.000001e+06\nqueue_depth{a=\"caf\xc3\xa9\",z=\"x\\ny\"} 7.286\n# HELP http_requests_5 caf\xc3\xa9 au lait\n# TYPE http_requests_5 gauge\nhttp_requests_5 -0.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_45(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "plain value" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "x\ny" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labp0[0usize..3usize], value: mem.bitcast[f64](13873650663995087574u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labp1[0usize..3usize], value: mem.bitcast[f64](4679327561451307008u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labp2[0usize..3usize], value: mem.bitcast[f64](13874279834068189184u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds tab\there\n# TYPE latency_seconds gauge\nlatency_seconds{code=\"\",method=\"caf\xc3\xa9\",path=\"caf\xc3\xa9\"} -803.471644\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"plain value\",path=\"caf\xc3\xa9\"} 66810.0\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"caf\xc3\xa9\",path=\"x\\ny\"} -875.0\n") {
        show(got, "# HELP latency_seconds tab\there\n# TYPE latency_seconds gauge\nlatency_seconds{code=\"\",method=\"caf\xc3\xa9\",path=\"caf\xc3\xa9\"} -803.471644\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"plain value\",path=\"caf\xc3\xa9\"} 66810.0\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"caf\xc3\xa9\",path=\"x\\ny\"} -875.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds gauge\nlatency_seconds{code=\"\",method=\"caf\xc3\xa9\",path=\"caf\xc3\xa9\"} -803.471644\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"plain value\",path=\"caf\xc3\xa9\"} 66810.0\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"caf\xc3\xa9\",path=\"x\\ny\"} -875.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds tab\there\n# TYPE latency_seconds gauge\nlatency_seconds{code=\"\",method=\"caf\xc3\xa9\",path=\"caf\xc3\xa9\"} -803.471644\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"plain value\",path=\"caf\xc3\xa9\"} 66810.0\nlatency_seconds{code=\"caf\xc3\xa9\",method=\"caf\xc3\xa9\",path=\"x\\ny\"} -875.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_46(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "x\ny" } }
    let bndp0: [5]f64 = [5]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump0: [6]u64 = [6]u64{ 27u64, 43u64, 93u64, 131u64, 146u64, 171u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndp1: [5]f64 = [5]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump1: [6]u64 = [6]u64{ 0u64, 13u64, 51u64, 94u64, 113u64, 126u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "plain value" } }
    let bndp2: [5]f64 = [5]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump2: [6]u64 = [6]u64{ 17u64, 39u64, 88u64, 138u64, 155u64, 185u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "/a\"b" } }
    let bndp3: [4]f64 = [4]f64{ mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [5]u64 = [5]u64{ 10u64, 14u64, 14u64, 60u64, 61u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    let labp5: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..5usize], buckets: cump0[0usize..6usize], sum: mem.bitcast[f64](4646174619558163251u64) }
    samples[1] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..5usize], buckets: cump1[0usize..6usize], sum: mem.bitcast[f64](4641346444098273280u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labp2[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..5usize], buckets: cump2[0usize..6usize], sum: mem.bitcast[f64](4644422687637181248u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..4usize], buckets: cump3[0usize..5usize], sum: mem.bitcast[f64](4635139920861803315u64) }
    samples[4] = x.Sample{ name: "latency_seconds_59", help: "tab\there", kind: x.Kind.Gauge, labels: labp4[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "latency_seconds_59", help: "tab\there", kind: x.Kind.Gauge, labels: labp5[0usize..1usize], value: mem.bitcast[f64](13863669562693118224u64), bounds: bndp5[0usize..0usize], buckets: cump5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..6usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"x\\ny\",le=\"1e-05\"} 27.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.1\"} 43.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.25\"} 93.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"2.5\"} 131.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"100.0\"} 146.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"+Inf\"} 171.0\nqueue_depth_count{code=\"x\\ny\"} 171.0\nqueue_depth_sum{code=\"x\\ny\"} 424.45\nqueue_depth_bucket{code=\"200\",le=\"1e-05\"} 0.0\nqueue_depth_bucket{code=\"200\",le=\"0.1\"} 13.0\nqueue_depth_bucket{code=\"200\",le=\"0.25\"} 51.0\nqueue_depth_bucket{code=\"200\",le=\"2.5\"} 94.0\nqueue_depth_bucket{code=\"200\",le=\"100.0\"} 113.0\nqueue_depth_bucket{code=\"200\",le=\"+Inf\"} 126.0\nqueue_depth_count{code=\"200\"} 126.0\nqueue_depth_sum{code=\"200\"} 203.0\nqueue_depth_bucket{code=\"plain value\",le=\"1e-05\"} 17.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.1\"} 39.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.25\"} 88.0\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\"} 138.0\nqueue_depth_bucket{code=\"plain value\",le=\"100.0\"} 155.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\"} 185.0\nqueue_depth_count{code=\"plain value\"} 185.0\nqueue_depth_sum{code=\"plain value\"} 324.8642\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"1.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 10.0\nlatency_seconds_bucket{le=\"5.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"10.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"100.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 60.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_count{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_sum{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 77.3\n# HELP latency_seconds_59 tab\there\n# TYPE latency_seconds_59 gauge\nlatency_seconds_59{z=\"/a\\\"b\"} 0.30000000000000004\nlatency_seconds_59{z=\"caf\xc3\xa9\"} -173.18795\n") {
        show(got, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"x\\ny\",le=\"1e-05\"} 27.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.1\"} 43.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.25\"} 93.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"2.5\"} 131.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"100.0\"} 146.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"+Inf\"} 171.0\nqueue_depth_count{code=\"x\\ny\"} 171.0\nqueue_depth_sum{code=\"x\\ny\"} 424.45\nqueue_depth_bucket{code=\"200\",le=\"1e-05\"} 0.0\nqueue_depth_bucket{code=\"200\",le=\"0.1\"} 13.0\nqueue_depth_bucket{code=\"200\",le=\"0.25\"} 51.0\nqueue_depth_bucket{code=\"200\",le=\"2.5\"} 94.0\nqueue_depth_bucket{code=\"200\",le=\"100.0\"} 113.0\nqueue_depth_bucket{code=\"200\",le=\"+Inf\"} 126.0\nqueue_depth_count{code=\"200\"} 126.0\nqueue_depth_sum{code=\"200\"} 203.0\nqueue_depth_bucket{code=\"plain value\",le=\"1e-05\"} 17.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.1\"} 39.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.25\"} 88.0\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\"} 138.0\nqueue_depth_bucket{code=\"plain value\",le=\"100.0\"} 155.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\"} 185.0\nqueue_depth_count{code=\"plain value\"} 185.0\nqueue_depth_sum{code=\"plain value\"} 324.8642\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"1.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 10.0\nlatency_seconds_bucket{le=\"5.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"10.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"100.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 60.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_count{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_sum{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 77.3\n# HELP latency_seconds_59 tab\there\n# TYPE latency_seconds_59 gauge\nlatency_seconds_59{z=\"/a\\\"b\"} 0.30000000000000004\nlatency_seconds_59{z=\"caf\xc3\xa9\"} -173.18795\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..6usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"x\\ny\",le=\"1e-05\"} 27.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.1\"} 43.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.25\"} 93.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"2.5\"} 131.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"100.0\"} 146.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"+Inf\"} 171.0\nqueue_depth_count{code=\"x\\ny\"} 171.0\nqueue_depth_sum{code=\"x\\ny\"} 424.45\nqueue_depth_bucket{code=\"200\",le=\"1e-05\"} 0.0\nqueue_depth_bucket{code=\"200\",le=\"0.1\"} 13.0\nqueue_depth_bucket{code=\"200\",le=\"0.25\"} 51.0\nqueue_depth_bucket{code=\"200\",le=\"2.5\"} 94.0\nqueue_depth_bucket{code=\"200\",le=\"100.0\"} 113.0\nqueue_depth_bucket{code=\"200\",le=\"+Inf\"} 126.0\nqueue_depth_count{code=\"200\"} 126.0\nqueue_depth_sum{code=\"200\"} 203.0\nqueue_depth_bucket{code=\"plain value\",le=\"1e-05\"} 17.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.1\"} 39.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.25\"} 88.0\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\"} 138.0\nqueue_depth_bucket{code=\"plain value\",le=\"100.0\"} 155.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\"} 185.0\nqueue_depth_count{code=\"plain value\"} 185.0\nqueue_depth_sum{code=\"plain value\"} 324.8642\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"1.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 10.0\nlatency_seconds_bucket{le=\"5.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"10.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"100.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 60.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_count{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_sum{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 77.3\n# HELP latency_seconds_59 tab\there\n# TYPE latency_seconds_59 gauge\nlatency_seconds_59{z=\"/a\\\"b\"} 0.30000000000000004\nlatency_seconds_59{z=\"caf\xc3\xa9\"} -173.18795\n# EOF\n") {
        show(got2, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"x\\ny\",le=\"1e-05\"} 27.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.1\"} 43.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"0.25\"} 93.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"2.5\"} 131.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"100.0\"} 146.0\nqueue_depth_bucket{code=\"x\\ny\",le=\"+Inf\"} 171.0\nqueue_depth_count{code=\"x\\ny\"} 171.0\nqueue_depth_sum{code=\"x\\ny\"} 424.45\nqueue_depth_bucket{code=\"200\",le=\"1e-05\"} 0.0\nqueue_depth_bucket{code=\"200\",le=\"0.1\"} 13.0\nqueue_depth_bucket{code=\"200\",le=\"0.25\"} 51.0\nqueue_depth_bucket{code=\"200\",le=\"2.5\"} 94.0\nqueue_depth_bucket{code=\"200\",le=\"100.0\"} 113.0\nqueue_depth_bucket{code=\"200\",le=\"+Inf\"} 126.0\nqueue_depth_count{code=\"200\"} 126.0\nqueue_depth_sum{code=\"200\"} 203.0\nqueue_depth_bucket{code=\"plain value\",le=\"1e-05\"} 17.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.1\"} 39.0\nqueue_depth_bucket{code=\"plain value\",le=\"0.25\"} 88.0\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\"} 138.0\nqueue_depth_bucket{code=\"plain value\",le=\"100.0\"} 155.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\"} 185.0\nqueue_depth_count{code=\"plain value\"} 185.0\nqueue_depth_sum{code=\"plain value\"} 324.8642\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"1.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 10.0\nlatency_seconds_bucket{le=\"5.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"10.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 14.0\nlatency_seconds_bucket{le=\"100.0\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 60.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_count{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 61.0\nlatency_seconds_sum{le_not=\"caf\xc3\xa9\",method=\"/a\\\"b\"} 77.3\n# HELP latency_seconds_59 tab\there\n# TYPE latency_seconds_59 gauge\nlatency_seconds_59{z=\"/a\\\"b\"} 0.30000000000000004\nlatency_seconds_59{z=\"caf\xc3\xa9\"} -173.18795\n# EOF\n")
        ret false
    }
    ret true
}

fn case_47(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "a", value: "GET" }, x.Label{ name: "method", value: "" } }
    let bndp0: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump0: [5]u64 = [5]u64{ 11u64, 25u64, 58u64, 104u64, 116u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..4usize], buckets: cump0[0usize..5usize], sum: mem.bitcast[f64](4646025965586087936u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"GET\",le=\"1e-05\",method=\"\",z=\"plain value\"} 11.0\nqueue_depth_bucket{a=\"GET\",le=\"0.1\",method=\"\",z=\"plain value\"} 25.0\nqueue_depth_bucket{a=\"GET\",le=\"0.3\",method=\"\",z=\"plain value\"} 58.0\nqueue_depth_bucket{a=\"GET\",le=\"100.0\",method=\"\",z=\"plain value\"} 104.0\nqueue_depth_bucket{a=\"GET\",le=\"+Inf\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_count{a=\"GET\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_sum{a=\"GET\",method=\"\",z=\"plain value\"} 416.0\n") {
        show(got, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"GET\",le=\"1e-05\",method=\"\",z=\"plain value\"} 11.0\nqueue_depth_bucket{a=\"GET\",le=\"0.1\",method=\"\",z=\"plain value\"} 25.0\nqueue_depth_bucket{a=\"GET\",le=\"0.3\",method=\"\",z=\"plain value\"} 58.0\nqueue_depth_bucket{a=\"GET\",le=\"100.0\",method=\"\",z=\"plain value\"} 104.0\nqueue_depth_bucket{a=\"GET\",le=\"+Inf\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_count{a=\"GET\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_sum{a=\"GET\",method=\"\",z=\"plain value\"} 416.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"GET\",le=\"1e-05\",method=\"\",z=\"plain value\"} 11.0\nqueue_depth_bucket{a=\"GET\",le=\"0.1\",method=\"\",z=\"plain value\"} 25.0\nqueue_depth_bucket{a=\"GET\",le=\"0.3\",method=\"\",z=\"plain value\"} 58.0\nqueue_depth_bucket{a=\"GET\",le=\"100.0\",method=\"\",z=\"plain value\"} 104.0\nqueue_depth_bucket{a=\"GET\",le=\"+Inf\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_count{a=\"GET\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_sum{a=\"GET\",method=\"\",z=\"plain value\"} 416.0\n# EOF\n") {
        show(got2, "# HELP queue_depth Total requests\n# TYPE queue_depth histogram\nqueue_depth_bucket{a=\"GET\",le=\"1e-05\",method=\"\",z=\"plain value\"} 11.0\nqueue_depth_bucket{a=\"GET\",le=\"0.1\",method=\"\",z=\"plain value\"} 25.0\nqueue_depth_bucket{a=\"GET\",le=\"0.3\",method=\"\",z=\"plain value\"} 58.0\nqueue_depth_bucket{a=\"GET\",le=\"100.0\",method=\"\",z=\"plain value\"} 104.0\nqueue_depth_bucket{a=\"GET\",le=\"+Inf\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_count{a=\"GET\",method=\"\",z=\"plain value\"} 116.0\nqueue_depth_sum{a=\"GET\",method=\"\",z=\"plain value\"} 416.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_48(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "x\ny" } }
    let bndp0: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [5]u64 = [5]u64{ 23u64, 28u64, 70u64, 96u64, 108u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "/a\"b" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump1: [5]u64 = [5]u64{ 7u64, 22u64, 56u64, 88u64, 135u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "200" } }
    let bndp2: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump2: [5]u64 = [5]u64{ 6u64, 8u64, 58u64, 77u64, 109u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..4usize], buckets: cump0[0usize..5usize], sum: mem.bitcast[f64](4645545698907075379u64) }
    samples[1] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4635470653959438336u64) }
    samples[2] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labp2[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..4usize], buckets: cump2[0usize..5usize], sum: mem.bitcast[f64](4646142958900939116u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"1e-05\",method=\"x\\ny\"} 23.0\nx_bucket{le=\"0.1\",method=\"x\\ny\"} 28.0\nx_bucket{le=\"0.3\",method=\"x\\ny\"} 70.0\nx_bucket{le=\"10.0\",method=\"x\\ny\"} 96.0\nx_bucket{le=\"+Inf\",method=\"x\\ny\"} 108.0\nx_count{method=\"x\\ny\"} 108.0\nx_sum{method=\"x\\ny\"} 388.7\nx_bucket{le=\"1e-05\",method=\"/a\\\"b\"} 7.0\nx_bucket{le=\"0.1\",method=\"/a\\\"b\"} 22.0\nx_bucket{le=\"0.3\",method=\"/a\\\"b\"} 56.0\nx_bucket{le=\"10.0\",method=\"/a\\\"b\"} 88.0\nx_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 135.0\nx_count{method=\"/a\\\"b\"} 135.0\nx_sum{method=\"/a\\\"b\"} 82.0\nx_bucket{le=\"1e-05\",method=\"200\"} 6.0\nx_bucket{le=\"0.1\",method=\"200\"} 8.0\nx_bucket{le=\"0.3\",method=\"200\"} 58.0\nx_bucket{le=\"10.0\",method=\"200\"} 77.0\nx_bucket{le=\"+Inf\",method=\"200\"} 109.0\nx_count{method=\"200\"} 109.0\nx_sum{method=\"200\"} 422.6503\n") {
        show(got, "# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"1e-05\",method=\"x\\ny\"} 23.0\nx_bucket{le=\"0.1\",method=\"x\\ny\"} 28.0\nx_bucket{le=\"0.3\",method=\"x\\ny\"} 70.0\nx_bucket{le=\"10.0\",method=\"x\\ny\"} 96.0\nx_bucket{le=\"+Inf\",method=\"x\\ny\"} 108.0\nx_count{method=\"x\\ny\"} 108.0\nx_sum{method=\"x\\ny\"} 388.7\nx_bucket{le=\"1e-05\",method=\"/a\\\"b\"} 7.0\nx_bucket{le=\"0.1\",method=\"/a\\\"b\"} 22.0\nx_bucket{le=\"0.3\",method=\"/a\\\"b\"} 56.0\nx_bucket{le=\"10.0\",method=\"/a\\\"b\"} 88.0\nx_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 135.0\nx_count{method=\"/a\\\"b\"} 135.0\nx_sum{method=\"/a\\\"b\"} 82.0\nx_bucket{le=\"1e-05\",method=\"200\"} 6.0\nx_bucket{le=\"0.1\",method=\"200\"} 8.0\nx_bucket{le=\"0.3\",method=\"200\"} 58.0\nx_bucket{le=\"10.0\",method=\"200\"} 77.0\nx_bucket{le=\"+Inf\",method=\"200\"} 109.0\nx_count{method=\"200\"} 109.0\nx_sum{method=\"200\"} 422.6503\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"1e-05\",method=\"x\\ny\"} 23.0\nx_bucket{le=\"0.1\",method=\"x\\ny\"} 28.0\nx_bucket{le=\"0.3\",method=\"x\\ny\"} 70.0\nx_bucket{le=\"10.0\",method=\"x\\ny\"} 96.0\nx_bucket{le=\"+Inf\",method=\"x\\ny\"} 108.0\nx_count{method=\"x\\ny\"} 108.0\nx_sum{method=\"x\\ny\"} 388.7\nx_bucket{le=\"1e-05\",method=\"/a\\\"b\"} 7.0\nx_bucket{le=\"0.1\",method=\"/a\\\"b\"} 22.0\nx_bucket{le=\"0.3\",method=\"/a\\\"b\"} 56.0\nx_bucket{le=\"10.0\",method=\"/a\\\"b\"} 88.0\nx_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 135.0\nx_count{method=\"/a\\\"b\"} 135.0\nx_sum{method=\"/a\\\"b\"} 82.0\nx_bucket{le=\"1e-05\",method=\"200\"} 6.0\nx_bucket{le=\"0.1\",method=\"200\"} 8.0\nx_bucket{le=\"0.3\",method=\"200\"} 58.0\nx_bucket{le=\"10.0\",method=\"200\"} 77.0\nx_bucket{le=\"+Inf\",method=\"200\"} 109.0\nx_count{method=\"200\"} 109.0\nx_sum{method=\"200\"} 422.6503\n# EOF\n") {
        show(got2, "# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"1e-05\",method=\"x\\ny\"} 23.0\nx_bucket{le=\"0.1\",method=\"x\\ny\"} 28.0\nx_bucket{le=\"0.3\",method=\"x\\ny\"} 70.0\nx_bucket{le=\"10.0\",method=\"x\\ny\"} 96.0\nx_bucket{le=\"+Inf\",method=\"x\\ny\"} 108.0\nx_count{method=\"x\\ny\"} 108.0\nx_sum{method=\"x\\ny\"} 388.7\nx_bucket{le=\"1e-05\",method=\"/a\\\"b\"} 7.0\nx_bucket{le=\"0.1\",method=\"/a\\\"b\"} 22.0\nx_bucket{le=\"0.3\",method=\"/a\\\"b\"} 56.0\nx_bucket{le=\"10.0\",method=\"/a\\\"b\"} 88.0\nx_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 135.0\nx_count{method=\"/a\\\"b\"} 135.0\nx_sum{method=\"/a\\\"b\"} 82.0\nx_bucket{le=\"1e-05\",method=\"200\"} 6.0\nx_bucket{le=\"0.1\",method=\"200\"} 8.0\nx_bucket{le=\"0.3\",method=\"200\"} 58.0\nx_bucket{le=\"10.0\",method=\"200\"} 77.0\nx_bucket{le=\"+Inf\",method=\"200\"} 109.0\nx_count{method=\"200\"} 109.0\nx_sum{method=\"200\"} 422.6503\n# EOF\n")
        ret false
    }
    ret true
}

fn case_49(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "/a\"b" }, x.Label{ name: "z", value: "200" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4679471872352452608u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp1[0usize..0usize], value: mem.bitcast[f64](13872878616449751450u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total Total requests\n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"/a\\\"b\",z=\"200\"} 68910.0\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total -715.7\n") {
        show(got, "# HELP http_requests_total Total requests\n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"/a\\\"b\",z=\"200\"} 68910.0\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total -715.7\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests Total requests\n# TYPE http_requests counter\nhttp_requests_total{le_not=\"/a\\\"b\",z=\"200\"} 68910.0\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total -715.7\n# EOF\n") {
        show(got2, "# HELP http_requests Total requests\n# TYPE http_requests counter\nhttp_requests_total{le_not=\"/a\\\"b\",z=\"200\"} 68910.0\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total -715.7\n# EOF\n")
        ret false
    }
    ret true
}

fn case_50(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "200" } }
    let bndp0: [2]f64 = [2]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump0: [3]u64 = [3]u64{ 29u64, 64u64, 101u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "x\ny" } }
    let bndp1: [2]f64 = [2]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump1: [3]u64 = [3]u64{ 40u64, 43u64, 76u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "GET" }, x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "le_not", value: "/a\"b" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "x\ny" }, x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "le_not", value: "200" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp4: [3]f64 = [3]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64) }
    let cump4: [4]u64 = [4]u64{ 40u64, 55u64, 70u64, 106u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..2usize], buckets: cump0[0usize..3usize], sum: mem.bitcast[f64](4645682425377012580u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..2usize], buckets: cump1[0usize..3usize], sum: mem.bitcast[f64](4636244710145392640u64) }
    samples[2] = x.Sample{ name: "x", help: "", kind: x.Kind.Counter, labels: labp2[0usize..3usize], value: mem.bitcast[f64](4677165096957378560u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "x", help: "", kind: x.Kind.Counter, labels: labp3[0usize..3usize], value: mem.bitcast[f64](13870818447421446537u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp4[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..3usize], buckets: cump4[0usize..4usize], sum: mem.bitcast[f64](4614388178203810202u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"0.5\",z=\"200\"} 29.0\njobs_total_bucket{le=\"100000.0\",z=\"200\"} 64.0\njobs_total_bucket{le=\"+Inf\",z=\"200\"} 101.0\njobs_total_count{z=\"200\"} 101.0\njobs_total_sum{z=\"200\"} 396.472\njobs_total_bucket{le=\"0.5\",z=\"x\\ny\"} 40.0\njobs_total_bucket{le=\"100000.0\",z=\"x\\ny\"} 43.0\njobs_total_bucket{le=\"+Inf\",z=\"x\\ny\"} 76.0\njobs_total_count{z=\"x\\ny\"} 76.0\njobs_total_sum{z=\"x\\ny\"} 93.0\n# HELP x_total \n# TYPE x_total counter\nx_total{code=\"GET\",le_not=\"/a\\\"b\",path=\"/a\\\"b\"} 50439.0\nx_total{code=\"x\\ny\",le_not=\"200\",path=\"/a\\\"b\"} -496.742949\n# HELP temp_c A \"quoted\" help\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.005\"} 40.0\ntemp_c_bucket{le=\"0.25\"} 55.0\ntemp_c_bucket{le=\"0.5\"} 70.0\ntemp_c_bucket{le=\"+Inf\"} 106.0\ntemp_c_count 106.0\ntemp_c_sum 3.2\n") {
        show(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"0.5\",z=\"200\"} 29.0\njobs_total_bucket{le=\"100000.0\",z=\"200\"} 64.0\njobs_total_bucket{le=\"+Inf\",z=\"200\"} 101.0\njobs_total_count{z=\"200\"} 101.0\njobs_total_sum{z=\"200\"} 396.472\njobs_total_bucket{le=\"0.5\",z=\"x\\ny\"} 40.0\njobs_total_bucket{le=\"100000.0\",z=\"x\\ny\"} 43.0\njobs_total_bucket{le=\"+Inf\",z=\"x\\ny\"} 76.0\njobs_total_count{z=\"x\\ny\"} 76.0\njobs_total_sum{z=\"x\\ny\"} 93.0\n# HELP x_total \n# TYPE x_total counter\nx_total{code=\"GET\",le_not=\"/a\\\"b\",path=\"/a\\\"b\"} 50439.0\nx_total{code=\"x\\ny\",le_not=\"200\",path=\"/a\\\"b\"} -496.742949\n# HELP temp_c A \"quoted\" help\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.005\"} 40.0\ntemp_c_bucket{le=\"0.25\"} 55.0\ntemp_c_bucket{le=\"0.5\"} 70.0\ntemp_c_bucket{le=\"+Inf\"} 106.0\ntemp_c_count 106.0\ntemp_c_sum 3.2\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"0.5\",z=\"200\"} 29.0\njobs_total_bucket{le=\"100000.0\",z=\"200\"} 64.0\njobs_total_bucket{le=\"+Inf\",z=\"200\"} 101.0\njobs_total_count{z=\"200\"} 101.0\njobs_total_sum{z=\"200\"} 396.472\njobs_total_bucket{le=\"0.5\",z=\"x\\ny\"} 40.0\njobs_total_bucket{le=\"100000.0\",z=\"x\\ny\"} 43.0\njobs_total_bucket{le=\"+Inf\",z=\"x\\ny\"} 76.0\njobs_total_count{z=\"x\\ny\"} 76.0\njobs_total_sum{z=\"x\\ny\"} 93.0\n# HELP x \n# TYPE x counter\nx_total{code=\"GET\",le_not=\"/a\\\"b\",path=\"/a\\\"b\"} 50439.0\nx_total{code=\"x\\ny\",le_not=\"200\",path=\"/a\\\"b\"} -496.742949\n# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.005\"} 40.0\ntemp_c_bucket{le=\"0.25\"} 55.0\ntemp_c_bucket{le=\"0.5\"} 70.0\ntemp_c_bucket{le=\"+Inf\"} 106.0\ntemp_c_count 106.0\ntemp_c_sum 3.2\n# EOF\n") {
        show(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"0.5\",z=\"200\"} 29.0\njobs_total_bucket{le=\"100000.0\",z=\"200\"} 64.0\njobs_total_bucket{le=\"+Inf\",z=\"200\"} 101.0\njobs_total_count{z=\"200\"} 101.0\njobs_total_sum{z=\"200\"} 396.472\njobs_total_bucket{le=\"0.5\",z=\"x\\ny\"} 40.0\njobs_total_bucket{le=\"100000.0\",z=\"x\\ny\"} 43.0\njobs_total_bucket{le=\"+Inf\",z=\"x\\ny\"} 76.0\njobs_total_count{z=\"x\\ny\"} 76.0\njobs_total_sum{z=\"x\\ny\"} 93.0\n# HELP x \n# TYPE x counter\nx_total{code=\"GET\",le_not=\"/a\\\"b\",path=\"/a\\\"b\"} 50439.0\nx_total{code=\"x\\ny\",le_not=\"200\",path=\"/a\\\"b\"} -496.742949\n# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.005\"} 40.0\ntemp_c_bucket{le=\"0.25\"} 55.0\ntemp_c_bucket{le=\"0.5\"} 70.0\ntemp_c_bucket{le=\"+Inf\"} 106.0\ntemp_c_count 106.0\ntemp_c_sum 3.2\n# EOF\n")
        ret false
    }
    ret true
}

fn case_51(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "x\ny" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 11u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "code", value: "plain value" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 37u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "code", value: "x\ny" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 42u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 41u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labp0[0usize..1usize], value: mem.bitcast[f64](4649869858236792832u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..1usize], sum: mem.bitcast[f64](4644311431134199153u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..1usize], sum: mem.bitcast[f64](4630176968146189864u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..1usize], sum: mem.bitcast[f64](4644005995600096002u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp4[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..1usize], sum: mem.bitcast[f64](4642926679801898992u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP x A \"quoted\" help\n# TYPE x gauge\nx{method=\"x\\ny\"} 757.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"plain value\"} 11.0\njobs_total_count{code=\"caf\xc3\xa9\",z=\"plain value\"} 11.0\njobs_total_sum{code=\"caf\xc3\xa9\",z=\"plain value\"} 318.54\njobs_total_bucket{code=\"plain value\",le=\"+Inf\",z=\"back\\\\slash\"} 37.0\njobs_total_count{code=\"plain value\",z=\"back\\\\slash\"} 37.0\njobs_total_sum{code=\"plain value\",z=\"back\\\\slash\"} 35.3861\njobs_total_bucket{code=\"x\\ny\",le=\"+Inf\",z=\"200\"} 42.0\njobs_total_count{code=\"x\\ny\",z=\"200\"} 42.0\njobs_total_sum{code=\"x\\ny\",z=\"200\"} 301.178\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"+Inf\"} 41.0\ntemp_c_count 41.0\ntemp_c_sum 247.913\n") {
        show(got, "# HELP x A \"quoted\" help\n# TYPE x gauge\nx{method=\"x\\ny\"} 757.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"plain value\"} 11.0\njobs_total_count{code=\"caf\xc3\xa9\",z=\"plain value\"} 11.0\njobs_total_sum{code=\"caf\xc3\xa9\",z=\"plain value\"} 318.54\njobs_total_bucket{code=\"plain value\",le=\"+Inf\",z=\"back\\\\slash\"} 37.0\njobs_total_count{code=\"plain value\",z=\"back\\\\slash\"} 37.0\njobs_total_sum{code=\"plain value\",z=\"back\\\\slash\"} 35.3861\njobs_total_bucket{code=\"x\\ny\",le=\"+Inf\",z=\"200\"} 42.0\njobs_total_count{code=\"x\\ny\",z=\"200\"} 42.0\njobs_total_sum{code=\"x\\ny\",z=\"200\"} 301.178\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"+Inf\"} 41.0\ntemp_c_count 41.0\ntemp_c_sum 247.913\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x gauge\nx{method=\"x\\ny\"} 757.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"plain value\"} 11.0\njobs_total_count{code=\"caf\xc3\xa9\",z=\"plain value\"} 11.0\njobs_total_sum{code=\"caf\xc3\xa9\",z=\"plain value\"} 318.54\njobs_total_bucket{code=\"plain value\",le=\"+Inf\",z=\"back\\\\slash\"} 37.0\njobs_total_count{code=\"plain value\",z=\"back\\\\slash\"} 37.0\njobs_total_sum{code=\"plain value\",z=\"back\\\\slash\"} 35.3861\njobs_total_bucket{code=\"x\\ny\",le=\"+Inf\",z=\"200\"} 42.0\njobs_total_count{code=\"x\\ny\",z=\"200\"} 42.0\njobs_total_sum{code=\"x\\ny\",z=\"200\"} 301.178\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"+Inf\"} 41.0\ntemp_c_count 41.0\ntemp_c_sum 247.913\n# EOF\n") {
        show(got2, "# HELP x A \\\"quoted\\\" help\n# TYPE x gauge\nx{method=\"x\\ny\"} 757.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",z=\"plain value\"} 11.0\njobs_total_count{code=\"caf\xc3\xa9\",z=\"plain value\"} 11.0\njobs_total_sum{code=\"caf\xc3\xa9\",z=\"plain value\"} 318.54\njobs_total_bucket{code=\"plain value\",le=\"+Inf\",z=\"back\\\\slash\"} 37.0\njobs_total_count{code=\"plain value\",z=\"back\\\\slash\"} 37.0\njobs_total_sum{code=\"plain value\",z=\"back\\\\slash\"} 35.3861\njobs_total_bucket{code=\"x\\ny\",le=\"+Inf\",z=\"200\"} 42.0\njobs_total_count{code=\"x\\ny\",z=\"200\"} 42.0\njobs_total_sum{code=\"x\\ny\",z=\"200\"} 301.178\n# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"+Inf\"} 41.0\ntemp_c_count 41.0\ntemp_c_sum 247.913\n# EOF\n")
        ret false
    }
    ret true
}

fn case_52(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4621599004157183787u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP x \n# TYPE x gauge\nx 9.609\n") {
        show(got, "# HELP x \n# TYPE x gauge\nx 9.609\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x \n# TYPE x gauge\nx 9.609\n# EOF\n") {
        show(got2, "# HELP x \n# TYPE x gauge\nx 9.609\n# EOF\n")
        ret false
    }
    ret true
}

fn case_53(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "a", value: "x\ny" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4612811918334230528u64) }
    let cump1: [5]u64 = [5]u64{ 39u64, 77u64, 102u64, 103u64, 140u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4667149782978920448u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4634309428943018525u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total \n# TYPE temp_c_total counter\ntemp_c_total 10776.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.005\"} 39.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.1\"} 77.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.25\"} 102.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"2.5\"} 103.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"+Inf\"} 140.0\njobs_total_count{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 140.0\njobs_total_sum{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 65.498\n") {
        show(got, "# HELP temp_c_total \n# TYPE temp_c_total counter\ntemp_c_total 10776.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.005\"} 39.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.1\"} 77.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.25\"} 102.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"2.5\"} 103.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"+Inf\"} 140.0\njobs_total_count{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 140.0\njobs_total_sum{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 65.498\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c \n# TYPE temp_c counter\ntemp_c_total 10776.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.005\"} 39.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.1\"} 77.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.25\"} 102.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"2.5\"} 103.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"+Inf\"} 140.0\njobs_total_count{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 140.0\njobs_total_sum{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 65.498\n# EOF\n") {
        show(got2, "# HELP temp_c \n# TYPE temp_c counter\ntemp_c_total 10776.0\n# HELP jobs_total tab\there\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.005\"} 39.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.1\"} 77.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"0.25\"} 102.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"2.5\"} 103.0\njobs_total_bucket{a=\"x\\ny\",code=\"caf\xc3\xa9\",le=\"+Inf\"} 140.0\njobs_total_count{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 140.0\njobs_total_sum{a=\"x\\ny\",code=\"caf\xc3\xa9\"} 65.498\n# EOF\n")
        ret false
    }
    ret true
}

fn case_54(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp3: [4]f64 = [4]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump3: [5]u64 = [5]u64{ 35u64, 40u64, 85u64, 126u64, 167u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp0[0usize..1usize], value: mem.bitcast[f64](4639385798482060326u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](4605398993347578692u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](13867605529854907966u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labp3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..4usize], buckets: cump3[0usize..5usize], sum: mem.bitcast[f64](4633266704891793900u64) }
    samples[4] = x.Sample{ name: "temp_c_30", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labp4[0usize..1usize], value: mem.bitcast[f64](4667137688351014912u64), bounds: bndp4[0usize..0usize], buckets: cump4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{le_not=\"\"} 147.2751\ntemp_c_total{le_not=\"plain value\"} 0.802\ntemp_c_total{le_not=\"back\\\\slash\"} -314.10973\n# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"0.1\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 35.0\nx_bucket{le=\"0.3\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 40.0\nx_bucket{le=\"1.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 85.0\nx_bucket{le=\"100000.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 126.0\nx_bucket{le=\"+Inf\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_count{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_sum{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 57.34\n# HELP temp_c_30 A \"quoted\" help\n# TYPE temp_c_30 gauge\ntemp_c_30{code=\"200\"} 10754.0\n") {
        show(got, "# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{le_not=\"\"} 147.2751\ntemp_c_total{le_not=\"plain value\"} 0.802\ntemp_c_total{le_not=\"back\\\\slash\"} -314.10973\n# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"0.1\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 35.0\nx_bucket{le=\"0.3\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 40.0\nx_bucket{le=\"1.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 85.0\nx_bucket{le=\"100000.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 126.0\nx_bucket{le=\"+Inf\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_count{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_sum{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 57.34\n# HELP temp_c_30 A \"quoted\" help\n# TYPE temp_c_30 gauge\ntemp_c_30{code=\"200\"} 10754.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{le_not=\"\"} 147.2751\ntemp_c_total{le_not=\"plain value\"} 0.802\ntemp_c_total{le_not=\"back\\\\slash\"} -314.10973\n# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"0.1\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 35.0\nx_bucket{le=\"0.3\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 40.0\nx_bucket{le=\"1.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 85.0\nx_bucket{le=\"100000.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 126.0\nx_bucket{le=\"+Inf\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_count{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_sum{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 57.34\n# HELP temp_c_30 A \\\"quoted\\\" help\n# TYPE temp_c_30 gauge\ntemp_c_30{code=\"200\"} 10754.0\n# EOF\n") {
        show(got2, "# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{le_not=\"\"} 147.2751\ntemp_c_total{le_not=\"plain value\"} 0.802\ntemp_c_total{le_not=\"back\\\\slash\"} -314.10973\n# HELP x Total requests\n# TYPE x histogram\nx_bucket{le=\"0.1\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 35.0\nx_bucket{le=\"0.3\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 40.0\nx_bucket{le=\"1.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 85.0\nx_bucket{le=\"100000.0\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 126.0\nx_bucket{le=\"+Inf\",method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_count{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 167.0\nx_sum{method=\"caf\xc3\xa9\",z=\"caf\xc3\xa9\"} 57.34\n# HELP temp_c_30 A \\\"quoted\\\" help\n# TYPE temp_c_30 gauge\ntemp_c_30{code=\"200\"} 10754.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_55(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "le_not", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "le_not", value: "GET" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "le_not", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "200" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndp3: [4]f64 = [4]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [5]u64 = [5]u64{ 26u64, 61u64, 98u64, 124u64, 156u64 }
    let labp4: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "le_not", value: "x\ny" } }
    let bndp4: [4]f64 = [4]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4636737291354636288u64) }
    let cump4: [5]u64 = [5]u64{ 18u64, 27u64, 57u64, 59u64, 67u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](13867744034367088676u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Counter, labels: labp2[0usize..2usize], value: mem.bitcast[f64](4667764409978847232u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Histogram, labels: labp3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..4usize], buckets: cump3[0usize..5usize], sum: mem.bitcast[f64](4638959888139487805u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Histogram, labels: labp4[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..4usize], buckets: cump4[0usize..5usize], sum: mem.bitcast[f64](4645169226125724877u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests_total tab\there\n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"plain value\",z=\"GET\"} -321.9828\nhttp_requests_total{le_not=\"GET\",z=\"back\\\\slash\"} 0.30000000000000004\nhttp_requests_total{le_not=\"\",z=\"/a\\\"b\"} 11894.0\n# HELP temp_c \n# TYPE temp_c histogram\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",le_not=\"caf\xc3\xa9\",path=\"200\"} 26.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.25\",le_not=\"caf\xc3\xa9\",path=\"200\"} 61.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.5\",le_not=\"caf\xc3\xa9\",path=\"200\"} 98.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"100.0\",le_not=\"caf\xc3\xa9\",path=\"200\"} 124.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_count{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_sum{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 135.17\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.1\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 18.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.25\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 27.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.5\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 57.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"100.0\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 59.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"+Inf\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_count{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_sum{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 367.3\n") {
        show(got, "# HELP http_requests_total tab\there\n# TYPE http_requests_total counter\nhttp_requests_total{le_not=\"plain value\",z=\"GET\"} -321.9828\nhttp_requests_total{le_not=\"GET\",z=\"back\\\\slash\"} 0.30000000000000004\nhttp_requests_total{le_not=\"\",z=\"/a\\\"b\"} 11894.0\n# HELP temp_c \n# TYPE temp_c histogram\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",le_not=\"caf\xc3\xa9\",path=\"200\"} 26.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.25\",le_not=\"caf\xc3\xa9\",path=\"200\"} 61.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.5\",le_not=\"caf\xc3\xa9\",path=\"200\"} 98.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"100.0\",le_not=\"caf\xc3\xa9\",path=\"200\"} 124.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_count{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_sum{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 135.17\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.1\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 18.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.25\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 27.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.5\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 57.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"100.0\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 59.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"+Inf\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_count{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_sum{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 367.3\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests tab\there\n# TYPE http_requests counter\nhttp_requests_total{le_not=\"plain value\",z=\"GET\"} -321.9828\nhttp_requests_total{le_not=\"GET\",z=\"back\\\\slash\"} 0.30000000000000004\nhttp_requests_total{le_not=\"\",z=\"/a\\\"b\"} 11894.0\n# HELP temp_c \n# TYPE temp_c histogram\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",le_not=\"caf\xc3\xa9\",path=\"200\"} 26.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.25\",le_not=\"caf\xc3\xa9\",path=\"200\"} 61.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.5\",le_not=\"caf\xc3\xa9\",path=\"200\"} 98.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"100.0\",le_not=\"caf\xc3\xa9\",path=\"200\"} 124.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_count{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_sum{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 135.17\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.1\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 18.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.25\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 27.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.5\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 57.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"100.0\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 59.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"+Inf\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_count{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_sum{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 367.3\n# EOF\n") {
        show(got2, "# HELP http_requests tab\there\n# TYPE http_requests counter\nhttp_requests_total{le_not=\"plain value\",z=\"GET\"} -321.9828\nhttp_requests_total{le_not=\"GET\",z=\"back\\\\slash\"} 0.30000000000000004\nhttp_requests_total{le_not=\"\",z=\"/a\\\"b\"} 11894.0\n# HELP temp_c \n# TYPE temp_c histogram\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.1\",le_not=\"caf\xc3\xa9\",path=\"200\"} 26.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.25\",le_not=\"caf\xc3\xa9\",path=\"200\"} 61.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"0.5\",le_not=\"caf\xc3\xa9\",path=\"200\"} 98.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"100.0\",le_not=\"caf\xc3\xa9\",path=\"200\"} 124.0\ntemp_c_bucket{code=\"caf\xc3\xa9\",le=\"+Inf\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_count{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 156.0\ntemp_c_sum{code=\"caf\xc3\xa9\",le_not=\"caf\xc3\xa9\",path=\"200\"} 135.17\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.1\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 18.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.25\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 27.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"0.5\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 57.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"100.0\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 59.0\ntemp_c_bucket{code=\"/a\\\"b\",le=\"+Inf\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_count{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 67.0\ntemp_c_sum{code=\"/a\\\"b\",le_not=\"x\\ny\",path=\"caf\xc3\xa9\"} 367.3\n# EOF\n")
        ret false
    }
    ret true
}

fn case_56(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp0: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump0: [5]u64 = [5]u64{ 45u64, 65u64, 96u64, 116u64, 136u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "path", value: "GET" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump1: [5]u64 = [5]u64{ 2u64, 6u64, 16u64, 55u64, 92u64 }
    let labp2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp2: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump2: [5]u64 = [5]u64{ 44u64, 69u64, 86u64, 128u64, 147u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..4usize], buckets: cump0[0usize..5usize], sum: mem.bitcast[f64](4640591387473246945u64) }
    samples[1] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4643431610725745820u64) }
    samples[2] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..4usize], buckets: cump2[0usize..5usize], sum: mem.bitcast[f64](4640257463153063467u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP x back\\\\slash and\\nnewline\n# TYPE x histogram\nx_bucket{a=\"/a\\\"b\",le=\"0.005\",path=\"back\\\\slash\"} 45.0\nx_bucket{a=\"/a\\\"b\",le=\"0.25\",path=\"back\\\\slash\"} 65.0\nx_bucket{a=\"/a\\\"b\",le=\"5.0\",path=\"back\\\\slash\"} 96.0\nx_bucket{a=\"/a\\\"b\",le=\"100000.0\",path=\"back\\\\slash\"} 116.0\nx_bucket{a=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\"} 136.0\nx_count{a=\"/a\\\"b\",path=\"back\\\\slash\"} 136.0\nx_sum{a=\"/a\\\"b\",path=\"back\\\\slash\"} 181.54\nx_bucket{a=\"\",le=\"0.005\",path=\"GET\"} 2.0\nx_bucket{a=\"\",le=\"0.25\",path=\"GET\"} 6.0\nx_bucket{a=\"\",le=\"5.0\",path=\"GET\"} 16.0\nx_bucket{a=\"\",le=\"100000.0\",path=\"GET\"} 55.0\nx_bucket{a=\"\",le=\"+Inf\",path=\"GET\"} 92.0\nx_count{a=\"\",path=\"GET\"} 92.0\nx_sum{a=\"\",path=\"GET\"} 268.528\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.005\",path=\"back\\\\slash\"} 44.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.25\",path=\"back\\\\slash\"} 69.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"5.0\",path=\"back\\\\slash\"} 86.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"100000.0\",path=\"back\\\\slash\"} 128.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",path=\"back\\\\slash\"} 147.0\nx_count{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 147.0\nx_sum{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 172.0493\n") {
        show(got, "# HELP x back\\\\slash and\\nnewline\n# TYPE x histogram\nx_bucket{a=\"/a\\\"b\",le=\"0.005\",path=\"back\\\\slash\"} 45.0\nx_bucket{a=\"/a\\\"b\",le=\"0.25\",path=\"back\\\\slash\"} 65.0\nx_bucket{a=\"/a\\\"b\",le=\"5.0\",path=\"back\\\\slash\"} 96.0\nx_bucket{a=\"/a\\\"b\",le=\"100000.0\",path=\"back\\\\slash\"} 116.0\nx_bucket{a=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\"} 136.0\nx_count{a=\"/a\\\"b\",path=\"back\\\\slash\"} 136.0\nx_sum{a=\"/a\\\"b\",path=\"back\\\\slash\"} 181.54\nx_bucket{a=\"\",le=\"0.005\",path=\"GET\"} 2.0\nx_bucket{a=\"\",le=\"0.25\",path=\"GET\"} 6.0\nx_bucket{a=\"\",le=\"5.0\",path=\"GET\"} 16.0\nx_bucket{a=\"\",le=\"100000.0\",path=\"GET\"} 55.0\nx_bucket{a=\"\",le=\"+Inf\",path=\"GET\"} 92.0\nx_count{a=\"\",path=\"GET\"} 92.0\nx_sum{a=\"\",path=\"GET\"} 268.528\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.005\",path=\"back\\\\slash\"} 44.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.25\",path=\"back\\\\slash\"} 69.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"5.0\",path=\"back\\\\slash\"} 86.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"100000.0\",path=\"back\\\\slash\"} 128.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",path=\"back\\\\slash\"} 147.0\nx_count{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 147.0\nx_sum{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 172.0493\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x back\\\\slash and\\nnewline\n# TYPE x histogram\nx_bucket{a=\"/a\\\"b\",le=\"0.005\",path=\"back\\\\slash\"} 45.0\nx_bucket{a=\"/a\\\"b\",le=\"0.25\",path=\"back\\\\slash\"} 65.0\nx_bucket{a=\"/a\\\"b\",le=\"5.0\",path=\"back\\\\slash\"} 96.0\nx_bucket{a=\"/a\\\"b\",le=\"100000.0\",path=\"back\\\\slash\"} 116.0\nx_bucket{a=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\"} 136.0\nx_count{a=\"/a\\\"b\",path=\"back\\\\slash\"} 136.0\nx_sum{a=\"/a\\\"b\",path=\"back\\\\slash\"} 181.54\nx_bucket{a=\"\",le=\"0.005\",path=\"GET\"} 2.0\nx_bucket{a=\"\",le=\"0.25\",path=\"GET\"} 6.0\nx_bucket{a=\"\",le=\"5.0\",path=\"GET\"} 16.0\nx_bucket{a=\"\",le=\"100000.0\",path=\"GET\"} 55.0\nx_bucket{a=\"\",le=\"+Inf\",path=\"GET\"} 92.0\nx_count{a=\"\",path=\"GET\"} 92.0\nx_sum{a=\"\",path=\"GET\"} 268.528\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.005\",path=\"back\\\\slash\"} 44.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.25\",path=\"back\\\\slash\"} 69.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"5.0\",path=\"back\\\\slash\"} 86.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"100000.0\",path=\"back\\\\slash\"} 128.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",path=\"back\\\\slash\"} 147.0\nx_count{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 147.0\nx_sum{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 172.0493\n# EOF\n") {
        show(got2, "# HELP x back\\\\slash and\\nnewline\n# TYPE x histogram\nx_bucket{a=\"/a\\\"b\",le=\"0.005\",path=\"back\\\\slash\"} 45.0\nx_bucket{a=\"/a\\\"b\",le=\"0.25\",path=\"back\\\\slash\"} 65.0\nx_bucket{a=\"/a\\\"b\",le=\"5.0\",path=\"back\\\\slash\"} 96.0\nx_bucket{a=\"/a\\\"b\",le=\"100000.0\",path=\"back\\\\slash\"} 116.0\nx_bucket{a=\"/a\\\"b\",le=\"+Inf\",path=\"back\\\\slash\"} 136.0\nx_count{a=\"/a\\\"b\",path=\"back\\\\slash\"} 136.0\nx_sum{a=\"/a\\\"b\",path=\"back\\\\slash\"} 181.54\nx_bucket{a=\"\",le=\"0.005\",path=\"GET\"} 2.0\nx_bucket{a=\"\",le=\"0.25\",path=\"GET\"} 6.0\nx_bucket{a=\"\",le=\"5.0\",path=\"GET\"} 16.0\nx_bucket{a=\"\",le=\"100000.0\",path=\"GET\"} 55.0\nx_bucket{a=\"\",le=\"+Inf\",path=\"GET\"} 92.0\nx_count{a=\"\",path=\"GET\"} 92.0\nx_sum{a=\"\",path=\"GET\"} 268.528\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.005\",path=\"back\\\\slash\"} 44.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"0.25\",path=\"back\\\\slash\"} 69.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"5.0\",path=\"back\\\\slash\"} 86.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"100000.0\",path=\"back\\\\slash\"} 128.0\nx_bucket{a=\"caf\xc3\xa9\",le=\"+Inf\",path=\"back\\\\slash\"} 147.0\nx_count{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 147.0\nx_sum{a=\"caf\xc3\xa9\",path=\"back\\\\slash\"} 172.0493\n# EOF\n")
        ret false
    }
    ret true
}

fn case_57(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4612811918334230528u64) }
    let cump0: [2]u64 = [2]u64{ 42u64, 59u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4612811918334230528u64) }
    let cump1: [2]u64 = [2]u64{ 26u64, 32u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4641276075354095616u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4643826942330535936u64) }
    samples[2] = x.Sample{ name: "temp_c_94", help: "", kind: x.Kind.Counter, labels: labp2[0usize..0usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp3[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"2.5\",z=\"caf\xc3\xa9\"} 42.0\ntemp_c_bucket{le=\"+Inf\",z=\"caf\xc3\xa9\"} 59.0\ntemp_c_count{z=\"caf\xc3\xa9\"} 59.0\ntemp_c_sum{z=\"caf\xc3\xa9\"} 201.0\ntemp_c_bucket{le=\"2.5\",z=\"back\\\\slash\"} 26.0\ntemp_c_bucket{le=\"+Inf\",z=\"back\\\\slash\"} 32.0\ntemp_c_count{z=\"back\\\\slash\"} 32.0\ntemp_c_sum{z=\"back\\\\slash\"} 291.0\n# HELP temp_c_94_total \n# TYPE temp_c_94_total counter\ntemp_c_94_total 0.30000000000000004\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx{method=\"\"} 0.30000000000000004\n") {
        show(got, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"2.5\",z=\"caf\xc3\xa9\"} 42.0\ntemp_c_bucket{le=\"+Inf\",z=\"caf\xc3\xa9\"} 59.0\ntemp_c_count{z=\"caf\xc3\xa9\"} 59.0\ntemp_c_sum{z=\"caf\xc3\xa9\"} 201.0\ntemp_c_bucket{le=\"2.5\",z=\"back\\\\slash\"} 26.0\ntemp_c_bucket{le=\"+Inf\",z=\"back\\\\slash\"} 32.0\ntemp_c_count{z=\"back\\\\slash\"} 32.0\ntemp_c_sum{z=\"back\\\\slash\"} 291.0\n# HELP temp_c_94_total \n# TYPE temp_c_94_total counter\ntemp_c_94_total 0.30000000000000004\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx{method=\"\"} 0.30000000000000004\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"2.5\",z=\"caf\xc3\xa9\"} 42.0\ntemp_c_bucket{le=\"+Inf\",z=\"caf\xc3\xa9\"} 59.0\ntemp_c_count{z=\"caf\xc3\xa9\"} 59.0\ntemp_c_sum{z=\"caf\xc3\xa9\"} 201.0\ntemp_c_bucket{le=\"2.5\",z=\"back\\\\slash\"} 26.0\ntemp_c_bucket{le=\"+Inf\",z=\"back\\\\slash\"} 32.0\ntemp_c_count{z=\"back\\\\slash\"} 32.0\ntemp_c_sum{z=\"back\\\\slash\"} 291.0\n# HELP temp_c_94 \n# TYPE temp_c_94 counter\ntemp_c_94_total 0.30000000000000004\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx{method=\"\"} 0.30000000000000004\n# EOF\n") {
        show(got2, "# HELP temp_c tab\there\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"2.5\",z=\"caf\xc3\xa9\"} 42.0\ntemp_c_bucket{le=\"+Inf\",z=\"caf\xc3\xa9\"} 59.0\ntemp_c_count{z=\"caf\xc3\xa9\"} 59.0\ntemp_c_sum{z=\"caf\xc3\xa9\"} 201.0\ntemp_c_bucket{le=\"2.5\",z=\"back\\\\slash\"} 26.0\ntemp_c_bucket{le=\"+Inf\",z=\"back\\\\slash\"} 32.0\ntemp_c_count{z=\"back\\\\slash\"} 32.0\ntemp_c_sum{z=\"back\\\\slash\"} 291.0\n# HELP temp_c_94 \n# TYPE temp_c_94 counter\ntemp_c_94_total 0.30000000000000004\n# HELP x caf\xc3\xa9 au lait\n# TYPE x gauge\nx{method=\"\"} 0.30000000000000004\n# EOF\n")
        ret false
    }
    ret true
}

fn case_58(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "x_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..0usize], value: mem.bitcast[f64](4680879796991819776u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total 89398.0\n") {
        show(got, "# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total 89398.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total 89398.0\n# EOF\n") {
        show(got2, "# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total 89398.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_59(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "x\ny" } }
    let bndp0: [5]f64 = [5]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [6]u64 = [6]u64{ 28u64, 67u64, 98u64, 137u64, 152u64, 173u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "200" } }
    let bndp1: [5]f64 = [5]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump1: [6]u64 = [6]u64{ 40u64, 63u64, 74u64, 85u64, 135u64, 176u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "x\ny" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "Total requests", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..5usize], buckets: cump0[0usize..6usize], sum: mem.bitcast[f64](4647028720190619648u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "Total requests", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..5usize], buckets: cump1[0usize..6usize], sum: mem.bitcast[f64](4645660927725666304u64) }
    samples[2] = x.Sample{ name: "temp_c_82", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labp2[0usize..0usize], value: mem.bitcast[f64](4548686525128629352u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labp3[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.1\",path=\"x\\ny\"} 28.0\ntemp_c_bucket{le=\"0.3\",path=\"x\\ny\"} 67.0\ntemp_c_bucket{le=\"0.5\",path=\"x\\ny\"} 98.0\ntemp_c_bucket{le=\"2.5\",path=\"x\\ny\"} 137.0\ntemp_c_bucket{le=\"10.0\",path=\"x\\ny\"} 152.0\ntemp_c_bucket{le=\"+Inf\",path=\"x\\ny\"} 173.0\ntemp_c_count{path=\"x\\ny\"} 173.0\ntemp_c_sum{path=\"x\\ny\"} 473.0\ntemp_c_bucket{le=\"0.1\",path=\"200\"} 40.0\ntemp_c_bucket{le=\"0.3\",path=\"200\"} 63.0\ntemp_c_bucket{le=\"0.5\",path=\"200\"} 74.0\ntemp_c_bucket{le=\"2.5\",path=\"200\"} 85.0\ntemp_c_bucket{le=\"10.0\",path=\"200\"} 135.0\ntemp_c_bucket{le=\"+Inf\",path=\"200\"} 176.0\ntemp_c_count{path=\"200\"} 176.0\ntemp_c_sum{path=\"200\"} 395.25\n# HELP temp_c_82 A \"quoted\" help\n# TYPE temp_c_82 gauge\ntemp_c_82 0.00012345\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{method=\"x\\ny\"} 0.30000000000000004\n") {
        show(got, "# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.1\",path=\"x\\ny\"} 28.0\ntemp_c_bucket{le=\"0.3\",path=\"x\\ny\"} 67.0\ntemp_c_bucket{le=\"0.5\",path=\"x\\ny\"} 98.0\ntemp_c_bucket{le=\"2.5\",path=\"x\\ny\"} 137.0\ntemp_c_bucket{le=\"10.0\",path=\"x\\ny\"} 152.0\ntemp_c_bucket{le=\"+Inf\",path=\"x\\ny\"} 173.0\ntemp_c_count{path=\"x\\ny\"} 173.0\ntemp_c_sum{path=\"x\\ny\"} 473.0\ntemp_c_bucket{le=\"0.1\",path=\"200\"} 40.0\ntemp_c_bucket{le=\"0.3\",path=\"200\"} 63.0\ntemp_c_bucket{le=\"0.5\",path=\"200\"} 74.0\ntemp_c_bucket{le=\"2.5\",path=\"200\"} 85.0\ntemp_c_bucket{le=\"10.0\",path=\"200\"} 135.0\ntemp_c_bucket{le=\"+Inf\",path=\"200\"} 176.0\ntemp_c_count{path=\"200\"} 176.0\ntemp_c_sum{path=\"200\"} 395.25\n# HELP temp_c_82 A \"quoted\" help\n# TYPE temp_c_82 gauge\ntemp_c_82 0.00012345\n# HELP jobs_total Total requests\n# TYPE jobs_total counter\njobs_total{method=\"x\\ny\"} 0.30000000000000004\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.1\",path=\"x\\ny\"} 28.0\ntemp_c_bucket{le=\"0.3\",path=\"x\\ny\"} 67.0\ntemp_c_bucket{le=\"0.5\",path=\"x\\ny\"} 98.0\ntemp_c_bucket{le=\"2.5\",path=\"x\\ny\"} 137.0\ntemp_c_bucket{le=\"10.0\",path=\"x\\ny\"} 152.0\ntemp_c_bucket{le=\"+Inf\",path=\"x\\ny\"} 173.0\ntemp_c_count{path=\"x\\ny\"} 173.0\ntemp_c_sum{path=\"x\\ny\"} 473.0\ntemp_c_bucket{le=\"0.1\",path=\"200\"} 40.0\ntemp_c_bucket{le=\"0.3\",path=\"200\"} 63.0\ntemp_c_bucket{le=\"0.5\",path=\"200\"} 74.0\ntemp_c_bucket{le=\"2.5\",path=\"200\"} 85.0\ntemp_c_bucket{le=\"10.0\",path=\"200\"} 135.0\ntemp_c_bucket{le=\"+Inf\",path=\"200\"} 176.0\ntemp_c_count{path=\"200\"} 176.0\ntemp_c_sum{path=\"200\"} 395.25\n# HELP temp_c_82 A \\\"quoted\\\" help\n# TYPE temp_c_82 gauge\ntemp_c_82 0.00012345\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{method=\"x\\ny\"} 0.30000000000000004\n# EOF\n") {
        show(got2, "# HELP temp_c Total requests\n# TYPE temp_c histogram\ntemp_c_bucket{le=\"0.1\",path=\"x\\ny\"} 28.0\ntemp_c_bucket{le=\"0.3\",path=\"x\\ny\"} 67.0\ntemp_c_bucket{le=\"0.5\",path=\"x\\ny\"} 98.0\ntemp_c_bucket{le=\"2.5\",path=\"x\\ny\"} 137.0\ntemp_c_bucket{le=\"10.0\",path=\"x\\ny\"} 152.0\ntemp_c_bucket{le=\"+Inf\",path=\"x\\ny\"} 173.0\ntemp_c_count{path=\"x\\ny\"} 173.0\ntemp_c_sum{path=\"x\\ny\"} 473.0\ntemp_c_bucket{le=\"0.1\",path=\"200\"} 40.0\ntemp_c_bucket{le=\"0.3\",path=\"200\"} 63.0\ntemp_c_bucket{le=\"0.5\",path=\"200\"} 74.0\ntemp_c_bucket{le=\"2.5\",path=\"200\"} 85.0\ntemp_c_bucket{le=\"10.0\",path=\"200\"} 135.0\ntemp_c_bucket{le=\"+Inf\",path=\"200\"} 176.0\ntemp_c_count{path=\"200\"} 176.0\ntemp_c_sum{path=\"200\"} 395.25\n# HELP temp_c_82 A \\\"quoted\\\" help\n# TYPE temp_c_82 gauge\ntemp_c_82 0.00012345\n# HELP jobs Total requests\n# TYPE jobs counter\njobs_total{method=\"x\\ny\"} 0.30000000000000004\n# EOF\n")
        ret false
    }
    ret true
}

fn case_60(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "200" }, x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "method", value: "GET" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4572414629676717179u64) }
    let cump0: [2]u64 = [2]u64{ 36u64, 64u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "" }, x.Label{ name: "path", value: "plain value" }, x.Label{ name: "method", value: "/a\"b" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](4572414629676717179u64) }
    let cump1: [2]u64 = [2]u64{ 37u64, 47u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4634560293516011897u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..1usize], buckets: cump1[0usize..2usize], sum: mem.bitcast[f64](4628855992006737920u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.005\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 36.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_count{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_sum{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 69.063\nlatency_seconds_bucket{le=\"0.005\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 37.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_count{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_sum{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 29.0\n") {
        show(got, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.005\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 36.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_count{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_sum{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 69.063\nlatency_seconds_bucket{le=\"0.005\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 37.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_count{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_sum{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 29.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.005\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 36.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_count{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_sum{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 69.063\nlatency_seconds_bucket{le=\"0.005\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 37.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_count{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_sum{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 29.0\n# EOF\n") {
        show(got2, "# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"0.005\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 36.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_count{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 64.0\nlatency_seconds_sum{le_not=\"200\",method=\"GET\",path=\"back\\\\slash\"} 69.063\nlatency_seconds_bucket{le=\"0.005\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 37.0\nlatency_seconds_bucket{le=\"+Inf\",le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_count{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 47.0\nlatency_seconds_sum{le_not=\"\",method=\"/a\\\"b\",path=\"plain value\"} 29.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_61(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "" } }
    let bndp0: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump0: [5]u64 = [5]u64{ 28u64, 49u64, 96u64, 116u64, 165u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "plain value" } }
    let bndp1: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump1: [5]u64 = [5]u64{ 27u64, 41u64, 72u64, 122u64, 153u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "back\\slash" } }
    let bndp2: [4]f64 = [4]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64) }
    let cump2: [5]u64 = [5]u64{ 11u64, 31u64, 59u64, 106u64, 114u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "GET" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](4636737291354636288u64) }
    let cump3: [2]u64 = [2]u64{ 21u64, 28u64 }
    let labp4: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "/a\"b" } }
    let bndp4: [1]f64 = [1]f64{ mem.bitcast[f64](4636737291354636288u64) }
    let cump4: [2]u64 = [2]u64{ 42u64, 88u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..4usize], buckets: cump0[0usize..5usize], sum: mem.bitcast[f64](4644529116844312756u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..4usize], buckets: cump1[0usize..5usize], sum: mem.bitcast[f64](4643222747496933491u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp2[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..4usize], buckets: cump2[0usize..5usize], sum: mem.bitcast[f64](4644039807781673370u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp3[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..1usize], buckets: cump3[0usize..2usize], sum: mem.bitcast[f64](4646696227874380186u64) }
    samples[4] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labp4[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..1usize], buckets: cump4[0usize..2usize], sum: mem.bitcast[f64](4643449238096162324u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{code=\"\",le=\"0.005\"} 28.0\nhttp_requests_bucket{code=\"\",le=\"0.1\"} 49.0\nhttp_requests_bucket{code=\"\",le=\"0.25\"} 96.0\nhttp_requests_bucket{code=\"\",le=\"5.0\"} 116.0\nhttp_requests_bucket{code=\"\",le=\"+Inf\"} 165.0\nhttp_requests_count{code=\"\"} 165.0\nhttp_requests_sum{code=\"\"} 330.914\nhttp_requests_bucket{code=\"plain value\",le=\"0.005\"} 27.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.1\"} 41.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.25\"} 72.0\nhttp_requests_bucket{code=\"plain value\",le=\"5.0\"} 122.0\nhttp_requests_bucket{code=\"plain value\",le=\"+Inf\"} 153.0\nhttp_requests_count{code=\"plain value\"} 153.0\nhttp_requests_sum{code=\"plain value\"} 256.6555\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.005\"} 11.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.1\"} 31.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.25\"} 59.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"5.0\"} 106.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"+Inf\"} 114.0\nhttp_requests_count{code=\"back\\\\slash\"} 114.0\nhttp_requests_sum{code=\"back\\\\slash\"} 303.1\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"100.0\",method=\"GET\"} 21.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"GET\"} 28.0\nlatency_seconds_count{method=\"GET\"} 28.0\nlatency_seconds_sum{method=\"GET\"} 454.1\nlatency_seconds_bucket{le=\"100.0\",method=\"/a\\\"b\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 88.0\nlatency_seconds_count{method=\"/a\\\"b\"} 88.0\nlatency_seconds_sum{method=\"/a\\\"b\"} 269.53\n") {
        show(got, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{code=\"\",le=\"0.005\"} 28.0\nhttp_requests_bucket{code=\"\",le=\"0.1\"} 49.0\nhttp_requests_bucket{code=\"\",le=\"0.25\"} 96.0\nhttp_requests_bucket{code=\"\",le=\"5.0\"} 116.0\nhttp_requests_bucket{code=\"\",le=\"+Inf\"} 165.0\nhttp_requests_count{code=\"\"} 165.0\nhttp_requests_sum{code=\"\"} 330.914\nhttp_requests_bucket{code=\"plain value\",le=\"0.005\"} 27.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.1\"} 41.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.25\"} 72.0\nhttp_requests_bucket{code=\"plain value\",le=\"5.0\"} 122.0\nhttp_requests_bucket{code=\"plain value\",le=\"+Inf\"} 153.0\nhttp_requests_count{code=\"plain value\"} 153.0\nhttp_requests_sum{code=\"plain value\"} 256.6555\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.005\"} 11.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.1\"} 31.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.25\"} 59.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"5.0\"} 106.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"+Inf\"} 114.0\nhttp_requests_count{code=\"back\\\\slash\"} 114.0\nhttp_requests_sum{code=\"back\\\\slash\"} 303.1\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"100.0\",method=\"GET\"} 21.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"GET\"} 28.0\nlatency_seconds_count{method=\"GET\"} 28.0\nlatency_seconds_sum{method=\"GET\"} 454.1\nlatency_seconds_bucket{le=\"100.0\",method=\"/a\\\"b\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 88.0\nlatency_seconds_count{method=\"/a\\\"b\"} 88.0\nlatency_seconds_sum{method=\"/a\\\"b\"} 269.53\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{code=\"\",le=\"0.005\"} 28.0\nhttp_requests_bucket{code=\"\",le=\"0.1\"} 49.0\nhttp_requests_bucket{code=\"\",le=\"0.25\"} 96.0\nhttp_requests_bucket{code=\"\",le=\"5.0\"} 116.0\nhttp_requests_bucket{code=\"\",le=\"+Inf\"} 165.0\nhttp_requests_count{code=\"\"} 165.0\nhttp_requests_sum{code=\"\"} 330.914\nhttp_requests_bucket{code=\"plain value\",le=\"0.005\"} 27.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.1\"} 41.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.25\"} 72.0\nhttp_requests_bucket{code=\"plain value\",le=\"5.0\"} 122.0\nhttp_requests_bucket{code=\"plain value\",le=\"+Inf\"} 153.0\nhttp_requests_count{code=\"plain value\"} 153.0\nhttp_requests_sum{code=\"plain value\"} 256.6555\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.005\"} 11.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.1\"} 31.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.25\"} 59.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"5.0\"} 106.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"+Inf\"} 114.0\nhttp_requests_count{code=\"back\\\\slash\"} 114.0\nhttp_requests_sum{code=\"back\\\\slash\"} 303.1\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"100.0\",method=\"GET\"} 21.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"GET\"} 28.0\nlatency_seconds_count{method=\"GET\"} 28.0\nlatency_seconds_sum{method=\"GET\"} 454.1\nlatency_seconds_bucket{le=\"100.0\",method=\"/a\\\"b\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 88.0\nlatency_seconds_count{method=\"/a\\\"b\"} 88.0\nlatency_seconds_sum{method=\"/a\\\"b\"} 269.53\n# EOF\n") {
        show(got2, "# HELP http_requests back\\\\slash and\\nnewline\n# TYPE http_requests histogram\nhttp_requests_bucket{code=\"\",le=\"0.005\"} 28.0\nhttp_requests_bucket{code=\"\",le=\"0.1\"} 49.0\nhttp_requests_bucket{code=\"\",le=\"0.25\"} 96.0\nhttp_requests_bucket{code=\"\",le=\"5.0\"} 116.0\nhttp_requests_bucket{code=\"\",le=\"+Inf\"} 165.0\nhttp_requests_count{code=\"\"} 165.0\nhttp_requests_sum{code=\"\"} 330.914\nhttp_requests_bucket{code=\"plain value\",le=\"0.005\"} 27.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.1\"} 41.0\nhttp_requests_bucket{code=\"plain value\",le=\"0.25\"} 72.0\nhttp_requests_bucket{code=\"plain value\",le=\"5.0\"} 122.0\nhttp_requests_bucket{code=\"plain value\",le=\"+Inf\"} 153.0\nhttp_requests_count{code=\"plain value\"} 153.0\nhttp_requests_sum{code=\"plain value\"} 256.6555\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.005\"} 11.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.1\"} 31.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"0.25\"} 59.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"5.0\"} 106.0\nhttp_requests_bucket{code=\"back\\\\slash\",le=\"+Inf\"} 114.0\nhttp_requests_count{code=\"back\\\\slash\"} 114.0\nhttp_requests_sum{code=\"back\\\\slash\"} 303.1\n# HELP latency_seconds caf\xc3\xa9 au lait\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{le=\"100.0\",method=\"GET\"} 21.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"GET\"} 28.0\nlatency_seconds_count{method=\"GET\"} 28.0\nlatency_seconds_sum{method=\"GET\"} 454.1\nlatency_seconds_bucket{le=\"100.0\",method=\"/a\\\"b\"} 42.0\nlatency_seconds_bucket{le=\"+Inf\",method=\"/a\\\"b\"} 88.0\nlatency_seconds_count{method=\"/a\\\"b\"} 88.0\nlatency_seconds_sum{method=\"/a\\\"b\"} 269.53\n# EOF\n")
        ret false
    }
    ret true
}

fn case_62(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4681608360884174848u64) }
    let cump0: [2]u64 = [2]u64{ 9u64, 43u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "plain value" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "back\\slash" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4643496666629738070u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Gauge, labels: labp1[0usize..1usize], value: mem.bitcast[f64](4610978953285890736u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Gauge, labels: labp2[0usize..1usize], value: mem.bitcast[f64](13871033932190756310u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth A \"quoted\" help\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"100000.0\"} 9.0\nqueue_depth_bucket{le=\"+Inf\"} 43.0\nqueue_depth_count 43.0\nqueue_depth_sum 272.226\n# HELP latency_seconds \n# TYPE latency_seconds gauge\nlatency_seconds{a=\"plain value\"} 1.843\nlatency_seconds{a=\"back\\\\slash\"} -508.99184\n") {
        show(got, "# HELP queue_depth A \"quoted\" help\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"100000.0\"} 9.0\nqueue_depth_bucket{le=\"+Inf\"} 43.0\nqueue_depth_count 43.0\nqueue_depth_sum 272.226\n# HELP latency_seconds \n# TYPE latency_seconds gauge\nlatency_seconds{a=\"plain value\"} 1.843\nlatency_seconds{a=\"back\\\\slash\"} -508.99184\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"100000.0\"} 9.0\nqueue_depth_bucket{le=\"+Inf\"} 43.0\nqueue_depth_count 43.0\nqueue_depth_sum 272.226\n# HELP latency_seconds \n# TYPE latency_seconds gauge\nlatency_seconds{a=\"plain value\"} 1.843\nlatency_seconds{a=\"back\\\\slash\"} -508.99184\n# EOF\n") {
        show(got2, "# HELP queue_depth A \\\"quoted\\\" help\n# TYPE queue_depth histogram\nqueue_depth_bucket{le=\"100000.0\"} 9.0\nqueue_depth_bucket{le=\"+Inf\"} 43.0\nqueue_depth_count 43.0\nqueue_depth_sum 272.226\n# HELP latency_seconds \n# TYPE latency_seconds gauge\nlatency_seconds{a=\"plain value\"} 1.843\nlatency_seconds{a=\"back\\\\slash\"} -508.99184\n# EOF\n")
        ret false
    }
    ret true
}

fn case_63(a: *mem.Arena) -> bool {
    let labp0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "GET" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "plain value" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp0[0usize..2usize], value: mem.bitcast[f64](4636737291354636288u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](13873300828914817434u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4712889646009286656u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..3usize], false)
    if ge != ok || !str.eq(got, "# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total{a=\"/a\\\"b\",path=\"/a\\\"b\"} 100.0\nx_total{a=\"GET\",path=\"back\\\\slash\"} -763.7\n# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total{le_not=\"plain value\"} 1.2345678e+07\n") {
        show(got, "# HELP x_total caf\xc3\xa9 au lait\n# TYPE x_total counter\nx_total{a=\"/a\\\"b\",path=\"/a\\\"b\"} 100.0\nx_total{a=\"GET\",path=\"back\\\\slash\"} -763.7\n# HELP queue_depth_total caf\xc3\xa9 au lait\n# TYPE queue_depth_total counter\nqueue_depth_total{le_not=\"plain value\"} 1.2345678e+07\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..3usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total{a=\"/a\\\"b\",path=\"/a\\\"b\"} 100.0\nx_total{a=\"GET\",path=\"back\\\\slash\"} -763.7\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total{le_not=\"plain value\"} 1.2345678e+07\n# EOF\n") {
        show(got2, "# HELP x caf\xc3\xa9 au lait\n# TYPE x counter\nx_total{a=\"/a\\\"b\",path=\"/a\\\"b\"} 100.0\nx_total{a=\"GET\",path=\"back\\\\slash\"} -763.7\n# HELP queue_depth caf\xc3\xa9 au lait\n# TYPE queue_depth counter\nqueue_depth_total{le_not=\"plain value\"} 1.2345678e+07\n# EOF\n")
        ret false
    }
    ret true
}

fn case_64(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "" }, x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "code", value: "plain value" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](4612811918334230528u64) }
    let cump0: [2]u64 = [2]u64{ 28u64, 48u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..1usize], buckets: cump0[0usize..2usize], sum: mem.bitcast[f64](4627913050834757222u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labp1[0usize..0usize], value: mem.bitcast[f64](13872599780300947456u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP queue_depth \n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\",path=\"/a\\\"b\",z=\"\"} 28.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_count{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_sum{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 25.65\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests -684.0\n") {
        show(got, "# HELP queue_depth \n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\",path=\"/a\\\"b\",z=\"\"} 28.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_count{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_sum{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 25.65\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests -684.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP queue_depth \n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\",path=\"/a\\\"b\",z=\"\"} 28.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_count{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_sum{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 25.65\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests -684.0\n# EOF\n") {
        show(got2, "# HELP queue_depth \n# TYPE queue_depth histogram\nqueue_depth_bucket{code=\"plain value\",le=\"2.5\",path=\"/a\\\"b\",z=\"\"} 28.0\nqueue_depth_bucket{code=\"plain value\",le=\"+Inf\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_count{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 48.0\nqueue_depth_sum{code=\"plain value\",path=\"/a\\\"b\",z=\"\"} 25.65\n# HELP http_requests caf\xc3\xa9 au lait\n# TYPE http_requests gauge\nhttp_requests -684.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_65(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "a", value: "GET" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump0: [4]u64 = [4]u64{ 9u64, 54u64, 84u64, 104u64 }
    let labp1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "GET" }, x.Label{ name: "a", value: "caf\xc3\xa9" } }
    let bndp1: [3]f64 = [3]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump1: [4]u64 = [4]u64{ 44u64, 60u64, 79u64, 87u64 }
    let labp2: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "plain value" }, x.Label{ name: "code", value: "GET" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp2: [3]f64 = [3]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4621819117588971520u64) }
    let cump2: [4]u64 = [4]u64{ 46u64, 70u64, 79u64, 99u64 }
    let labp3: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "GET" }, x.Label{ name: "z", value: "x\ny" } }
    let bndp3: [5]f64 = [5]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump3: [6]u64 = [6]u64{ 43u64, 76u64, 106u64, 113u64, 150u64, 156u64 }
    let labp4: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "" }, x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndp4: [5]f64 = [5]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4636737291354636288u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump4: [6]u64 = [6]u64{ 46u64, 72u64, 117u64, 165u64, 202u64, 249u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4647046593851640775u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp1[0usize..3usize], buckets: cump1[0usize..4usize], sum: mem.bitcast[f64](4640755417015925080u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp2[0usize..3usize], buckets: cump2[0usize..4usize], sum: mem.bitcast[f64](4641332574418795862u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp3[0usize..5usize], buckets: cump3[0usize..6usize], sum: mem.bitcast[f64](4641103671930860339u64) }
    samples[4] = x.Sample{ name: "latency_seconds", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp4[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp4[0usize..5usize], buckets: cump4[0usize..6usize], sum: mem.bitcast[f64](4645343388767564595u64) }
    let (got, ge) = x.render_text(a, samples[0usize..5usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"0.5\",method=\"caf\xc3\xa9\"} 9.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"1.0\",method=\"caf\xc3\xa9\"} 54.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"10.0\",method=\"caf\xc3\xa9\"} 84.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_count{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_sum{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 474.016\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"0.5\",method=\"caf\xc3\xa9\"} 44.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"1.0\",method=\"caf\xc3\xa9\"} 60.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"10.0\",method=\"caf\xc3\xa9\"} 79.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_count{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_sum{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 186.202\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"0.5\",method=\"plain value\"} 46.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"1.0\",method=\"plain value\"} 70.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"10.0\",method=\"plain value\"} 79.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"+Inf\",method=\"plain value\"} 99.0\njobs_total_count{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 99.0\njobs_total_sum{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 202.6058\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"GET\",le=\"0.25\",path=\"back\\\\slash\",z=\"x\\ny\"} 43.0\nlatency_seconds_bucket{a=\"GET\",le=\"0.5\",path=\"back\\\\slash\",z=\"x\\ny\"} 76.0\nlatency_seconds_bucket{a=\"GET\",le=\"1.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 106.0\nlatency_seconds_bucket{a=\"GET\",le=\"100.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 113.0\nlatency_seconds_bucket{a=\"GET\",le=\"100000.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 150.0\nlatency_seconds_bucket{a=\"GET\",le=\"+Inf\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_count{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_sum{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 196.1\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.25\",path=\"\",z=\"/a\\\"b\"} 46.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.5\",path=\"\",z=\"/a\\\"b\"} 72.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"1.0\",path=\"\",z=\"/a\\\"b\"} 117.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100.0\",path=\"\",z=\"/a\\\"b\"} 165.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100000.0\",path=\"\",z=\"/a\\\"b\"} 202.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"+Inf\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_count{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_sum{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 377.2\n") {
        show(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"0.5\",method=\"caf\xc3\xa9\"} 9.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"1.0\",method=\"caf\xc3\xa9\"} 54.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"10.0\",method=\"caf\xc3\xa9\"} 84.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_count{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_sum{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 474.016\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"0.5\",method=\"caf\xc3\xa9\"} 44.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"1.0\",method=\"caf\xc3\xa9\"} 60.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"10.0\",method=\"caf\xc3\xa9\"} 79.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_count{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_sum{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 186.202\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"0.5\",method=\"plain value\"} 46.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"1.0\",method=\"plain value\"} 70.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"10.0\",method=\"plain value\"} 79.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"+Inf\",method=\"plain value\"} 99.0\njobs_total_count{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 99.0\njobs_total_sum{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 202.6058\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"GET\",le=\"0.25\",path=\"back\\\\slash\",z=\"x\\ny\"} 43.0\nlatency_seconds_bucket{a=\"GET\",le=\"0.5\",path=\"back\\\\slash\",z=\"x\\ny\"} 76.0\nlatency_seconds_bucket{a=\"GET\",le=\"1.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 106.0\nlatency_seconds_bucket{a=\"GET\",le=\"100.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 113.0\nlatency_seconds_bucket{a=\"GET\",le=\"100000.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 150.0\nlatency_seconds_bucket{a=\"GET\",le=\"+Inf\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_count{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_sum{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 196.1\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.25\",path=\"\",z=\"/a\\\"b\"} 46.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.5\",path=\"\",z=\"/a\\\"b\"} 72.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"1.0\",path=\"\",z=\"/a\\\"b\"} 117.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100.0\",path=\"\",z=\"/a\\\"b\"} 165.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100000.0\",path=\"\",z=\"/a\\\"b\"} 202.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"+Inf\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_count{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_sum{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 377.2\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..5usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"0.5\",method=\"caf\xc3\xa9\"} 9.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"1.0\",method=\"caf\xc3\xa9\"} 54.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"10.0\",method=\"caf\xc3\xa9\"} 84.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_count{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_sum{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 474.016\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"0.5\",method=\"caf\xc3\xa9\"} 44.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"1.0\",method=\"caf\xc3\xa9\"} 60.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"10.0\",method=\"caf\xc3\xa9\"} 79.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_count{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_sum{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 186.202\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"0.5\",method=\"plain value\"} 46.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"1.0\",method=\"plain value\"} 70.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"10.0\",method=\"plain value\"} 79.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"+Inf\",method=\"plain value\"} 99.0\njobs_total_count{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 99.0\njobs_total_sum{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 202.6058\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"GET\",le=\"0.25\",path=\"back\\\\slash\",z=\"x\\ny\"} 43.0\nlatency_seconds_bucket{a=\"GET\",le=\"0.5\",path=\"back\\\\slash\",z=\"x\\ny\"} 76.0\nlatency_seconds_bucket{a=\"GET\",le=\"1.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 106.0\nlatency_seconds_bucket{a=\"GET\",le=\"100.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 113.0\nlatency_seconds_bucket{a=\"GET\",le=\"100000.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 150.0\nlatency_seconds_bucket{a=\"GET\",le=\"+Inf\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_count{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_sum{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 196.1\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.25\",path=\"\",z=\"/a\\\"b\"} 46.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.5\",path=\"\",z=\"/a\\\"b\"} 72.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"1.0\",path=\"\",z=\"/a\\\"b\"} 117.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100.0\",path=\"\",z=\"/a\\\"b\"} 165.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100000.0\",path=\"\",z=\"/a\\\"b\"} 202.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"+Inf\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_count{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_sum{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 377.2\n# EOF\n") {
        show(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"0.5\",method=\"caf\xc3\xa9\"} 9.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"1.0\",method=\"caf\xc3\xa9\"} 54.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"10.0\",method=\"caf\xc3\xa9\"} 84.0\njobs_total_bucket{a=\"GET\",code=\"/a\\\"b\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_count{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 104.0\njobs_total_sum{a=\"GET\",code=\"/a\\\"b\",method=\"caf\xc3\xa9\"} 474.016\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"0.5\",method=\"caf\xc3\xa9\"} 44.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"1.0\",method=\"caf\xc3\xa9\"} 60.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"10.0\",method=\"caf\xc3\xa9\"} 79.0\njobs_total_bucket{a=\"caf\xc3\xa9\",code=\"GET\",le=\"+Inf\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_count{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 87.0\njobs_total_sum{a=\"caf\xc3\xa9\",code=\"GET\",method=\"caf\xc3\xa9\"} 186.202\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"0.5\",method=\"plain value\"} 46.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"1.0\",method=\"plain value\"} 70.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"10.0\",method=\"plain value\"} 79.0\njobs_total_bucket{a=\"/a\\\"b\",code=\"GET\",le=\"+Inf\",method=\"plain value\"} 99.0\njobs_total_count{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 99.0\njobs_total_sum{a=\"/a\\\"b\",code=\"GET\",method=\"plain value\"} 202.6058\n# HELP latency_seconds back\\\\slash and\\nnewline\n# TYPE latency_seconds histogram\nlatency_seconds_bucket{a=\"GET\",le=\"0.25\",path=\"back\\\\slash\",z=\"x\\ny\"} 43.0\nlatency_seconds_bucket{a=\"GET\",le=\"0.5\",path=\"back\\\\slash\",z=\"x\\ny\"} 76.0\nlatency_seconds_bucket{a=\"GET\",le=\"1.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 106.0\nlatency_seconds_bucket{a=\"GET\",le=\"100.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 113.0\nlatency_seconds_bucket{a=\"GET\",le=\"100000.0\",path=\"back\\\\slash\",z=\"x\\ny\"} 150.0\nlatency_seconds_bucket{a=\"GET\",le=\"+Inf\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_count{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 156.0\nlatency_seconds_sum{a=\"GET\",path=\"back\\\\slash\",z=\"x\\ny\"} 196.1\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.25\",path=\"\",z=\"/a\\\"b\"} 46.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"0.5\",path=\"\",z=\"/a\\\"b\"} 72.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"1.0\",path=\"\",z=\"/a\\\"b\"} 117.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100.0\",path=\"\",z=\"/a\\\"b\"} 165.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"100000.0\",path=\"\",z=\"/a\\\"b\"} 202.0\nlatency_seconds_bucket{a=\"back\\\\slash\",le=\"+Inf\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_count{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 249.0\nlatency_seconds_sum{a=\"back\\\\slash\",path=\"\",z=\"/a\\\"b\"} 377.2\n# EOF\n")
        ret false
    }
    ret true
}

fn case_66(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "plain value" }, x.Label{ name: "z", value: "GET" } }
    let bndp0: [2]f64 = [2]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4681608360884174848u64) }
    let cump0: [3]u64 = [3]u64{ 23u64, 52u64, 100u64 }
    let labp1: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "method", value: "GET" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "tab\there", kind: x.Kind.Histogram, labels: labp0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..2usize], buckets: cump0[0usize..3usize], sum: mem.bitcast[f64](4647222234237108224u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..2usize], value: mem.bitcast[f64](4662758333537583104u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP http_requests tab\there\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 23.0\nhttp_requests_bucket{le=\"100000.0\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 52.0\nhttp_requests_bucket{le=\"+Inf\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_count{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_sum{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 484.0\n# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{method=\"GET\",path=\"back\\\\slash\"} 5490.0\n") {
        show(got, "# HELP http_requests tab\there\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 23.0\nhttp_requests_bucket{le=\"100000.0\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 52.0\nhttp_requests_bucket{le=\"+Inf\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_count{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_sum{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 484.0\n# HELP temp_c_total A \"quoted\" help\n# TYPE temp_c_total counter\ntemp_c_total{method=\"GET\",path=\"back\\\\slash\"} 5490.0\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP http_requests tab\there\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 23.0\nhttp_requests_bucket{le=\"100000.0\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 52.0\nhttp_requests_bucket{le=\"+Inf\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_count{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_sum{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 484.0\n# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{method=\"GET\",path=\"back\\\\slash\"} 5490.0\n# EOF\n") {
        show(got2, "# HELP http_requests tab\there\n# TYPE http_requests histogram\nhttp_requests_bucket{le=\"0.1\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 23.0\nhttp_requests_bucket{le=\"100000.0\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 52.0\nhttp_requests_bucket{le=\"+Inf\",method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_count{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 100.0\nhttp_requests_sum{method=\"plain value\",path=\"caf\xc3\xa9\",z=\"GET\"} 484.0\n# HELP temp_c A \\\"quoted\\\" help\n# TYPE temp_c counter\ntemp_c_total{method=\"GET\",path=\"back\\\\slash\"} 5490.0\n# EOF\n")
        ret false
    }
    ret true
}

fn case_67(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "plain value" }, x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "back\\slash" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    let labp2: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "x\ny" } }
    let bndp2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump2: [1]u64 = [1]u64{ 0u64 }
    let labp3: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "" } }
    let bndp3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4651611484655190016u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total_20", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp1[0usize..1usize], value: mem.bitcast[f64](4681161821724344320u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "jobs_total_20", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp2[0usize..1usize], value: mem.bitcast[f64](4681007340340641792u64), bounds: bndp2[0usize..0usize], buckets: cump2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total_20", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labp3[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndp3[0usize..0usize], buckets: cump3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..4usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total tab\there\n# TYPE jobs_total counter\njobs_total{a=\"/a\\\"b\",method=\"/a\\\"b\",path=\"plain value\"} 955.0\n# HELP jobs_total_20_total back\\\\slash and\\nnewline\n# TYPE jobs_total_20_total counter\njobs_total_20_total{path=\"back\\\\slash\"} 93502.0\njobs_total_20_total{path=\"x\\ny\"} 91254.0\njobs_total_20_total{path=\"\"} 0.30000000000000004\n") {
        show(got, "# HELP jobs_total tab\there\n# TYPE jobs_total counter\njobs_total{a=\"/a\\\"b\",method=\"/a\\\"b\",path=\"plain value\"} 955.0\n# HELP jobs_total_20_total back\\\\slash and\\nnewline\n# TYPE jobs_total_20_total counter\njobs_total_20_total{path=\"back\\\\slash\"} 93502.0\njobs_total_20_total{path=\"x\\ny\"} 91254.0\njobs_total_20_total{path=\"\"} 0.30000000000000004\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..4usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs tab\there\n# TYPE jobs counter\njobs_total{a=\"/a\\\"b\",method=\"/a\\\"b\",path=\"plain value\"} 955.0\n# HELP jobs_total_20 back\\\\slash and\\nnewline\n# TYPE jobs_total_20 counter\njobs_total_20_total{path=\"back\\\\slash\"} 93502.0\njobs_total_20_total{path=\"x\\ny\"} 91254.0\njobs_total_20_total{path=\"\"} 0.30000000000000004\n# EOF\n") {
        show(got2, "# HELP jobs tab\there\n# TYPE jobs counter\njobs_total{a=\"/a\\\"b\",method=\"/a\\\"b\",path=\"plain value\"} 955.0\n# HELP jobs_total_20 back\\\\slash and\\nnewline\n# TYPE jobs_total_20 counter\njobs_total_20_total{path=\"back\\\\slash\"} 93502.0\njobs_total_20_total{path=\"x\\ny\"} 91254.0\njobs_total_20_total{path=\"\"} 0.30000000000000004\n# EOF\n")
        ret false
    }
    ret true
}

fn case_68(a: *mem.Arena) -> bool {
    let labp0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp0: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4607182418800017408u64) }
    let cump0: [4]u64 = [4]u64{ 22u64, 53u64, 70u64, 102u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labp0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndp0[0usize..3usize], buckets: cump0[0usize..4usize], sum: mem.bitcast[f64](4646081205050267402u64) }
    let (got, ge) = x.render_text(a, samples[0usize..1usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 22.0\njobs_total_bucket{le=\"0.005\"} 53.0\njobs_total_bucket{le=\"1.0\"} 70.0\njobs_total_bucket{le=\"+Inf\"} 102.0\njobs_total_count 102.0\njobs_total_sum 419.14\n") {
        show(got, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 22.0\njobs_total_bucket{le=\"0.005\"} 53.0\njobs_total_bucket{le=\"1.0\"} 70.0\njobs_total_bucket{le=\"+Inf\"} 102.0\njobs_total_count 102.0\njobs_total_sum 419.14\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..1usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 22.0\njobs_total_bucket{le=\"0.005\"} 53.0\njobs_total_bucket{le=\"1.0\"} 70.0\njobs_total_bucket{le=\"+Inf\"} 102.0\njobs_total_count 102.0\njobs_total_sum 419.14\n# EOF\n") {
        show(got2, "# HELP jobs_total back\\\\slash and\\nnewline\n# TYPE jobs_total histogram\njobs_total_bucket{le=\"1e-05\"} 22.0\njobs_total_bucket{le=\"0.005\"} 53.0\njobs_total_bucket{le=\"1.0\"} 70.0\njobs_total_bucket{le=\"+Inf\"} 102.0\njobs_total_count 102.0\njobs_total_sum 419.14\n# EOF\n")
        ret false
    }
    ret true
}

fn case_69(a: *mem.Arena) -> bool {
    let labp0: [3]x.Label = [3]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "z", value: "" } }
    let bndp0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump0: [1]u64 = [1]u64{ 0u64 }
    let labp1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndp1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cump1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Counter, labels: labp0[0usize..3usize], value: mem.bitcast[f64](4634274385308418048u64), bounds: bndp0[0usize..0usize], buckets: cump0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labp1[0usize..0usize], value: mem.bitcast[f64](4548686525128629352u64), bounds: bndp1[0usize..0usize], buckets: cump1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let (got, ge) = x.render_text(a, samples[0usize..2usize], false)
    if ge != ok || !str.eq(got, "# HELP jobs_total \n# TYPE jobs_total counter\njobs_total{a=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",z=\"\"} 65.0\n# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total 0.00012345\n") {
        show(got, "# HELP jobs_total \n# TYPE jobs_total counter\njobs_total{a=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",z=\"\"} 65.0\n# HELP x_total A \"quoted\" help\n# TYPE x_total counter\nx_total 0.00012345\n")
        ret false
    }
    let (got2, ge2) = x.render_text(a, samples[0usize..2usize], true)
    if ge2 != ok || !str.eq(got2, "# HELP jobs \n# TYPE jobs counter\njobs_total{a=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",z=\"\"} 65.0\n# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total 0.00012345\n# EOF\n") {
        show(got2, "# HELP jobs \n# TYPE jobs counter\njobs_total{a=\"caf\xc3\xa9\",le_not=\"back\\\\slash\",z=\"\"} 65.0\n# HELP x A \\\"quoted\\\" help\n# TYPE x counter\nx_total 0.00012345\n# EOF\n")
        ret false
    }
    ret true
}

fn case_70(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "z", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "plain value" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "le_not", value: "200" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "GET" }, x.Label{ name: "le_not", value: "x\ny" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "le_not", value: "back\\slash" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4672294397885284352u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4696837155274620928u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Counter, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4649623567632171008u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Counter, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4648235190928559093u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Counter, labels: labo4[0usize..2usize], value: mem.bitcast[f64](4609605355399542735u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "temp_c_total", help: "", kind: x.Kind.Counter, labels: labo5[0usize..2usize], value: mem.bitcast[f64](4651563673315645944u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "my.lib", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":23884.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000001.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":729.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":571.159843,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1.538,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"temp_c_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":949.56448,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":23884.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000001.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":729.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":571.159843,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1.538,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"temp_c_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":949.56448,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_71(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "x\ny" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "plain value" }, x.Label{ name: "path", value: "GET" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "x\ny" }, x.Label{ name: "path", value: "x\ny" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "200" }, x.Label{ name: "path", value: "200" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4670513463926194176u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4667264681944023040u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo2[0usize..2usize], value: mem.bitcast[f64](13925995157322203136u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4680855607736008704u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "Total requests", kind: x.Kind.Counter, labels: labo4[0usize..0usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..5usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":17405.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"http_requests\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":10985.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-2500000.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":89046.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}]}},{\"name\":\"temp_c\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":17405.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"http_requests\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":10985.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-2500000.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":89046.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}]}},{\"name\":\"temp_c\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_72(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "" } }
    let bndo0: [2]f64 = [2]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo0: [3]u64 = [3]u64{ 39u64, 53u64, 101u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "plain value" } }
    let bndo1: [2]f64 = [2]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo1: [3]u64 = [3]u64{ 28u64, 76u64, 94u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "back\\slash" }, x.Label{ name: "le_not", value: "" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndo3: [2]f64 = [2]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo3: [3]u64 = [3]u64{ 38u64, 77u64, 90u64 }
    let labo4: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "200" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndo4: [2]f64 = [2]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo4: [3]u64 = [3]u64{ 18u64, 38u64, 57u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "", kind: x.Kind.Histogram, labels: labo0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..2usize], buckets: cumo0[0usize..3usize], sum: mem.bitcast[f64](4635006220247865754u64) }
    samples[1] = x.Sample{ name: "queue_depth", help: "", kind: x.Kind.Histogram, labels: labo1[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..2usize], buckets: cumo1[0usize..3usize], sum: mem.bitcast[f64](4634989331749263114u64) }
    samples[2] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Gauge, labels: labo2[0usize..3usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Histogram, labels: labo3[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..2usize], buckets: cumo3[0usize..3usize], sum: mem.bitcast[f64](4622392200641554416u64) }
    samples[4] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Histogram, labels: labo4[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo4[0usize..2usize], buckets: cumo4[0usize..3usize], sum: mem.bitcast[f64](4629283833971338117u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "lib\\v1", samples[0usize..5usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"101\",\"sum\":75.4,\"bucketCounts\":[\"39\",\"14\",\"48\"],\"explicitBounds\":[1e-05,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"94\",\"sum\":75.16,\"bucketCounts\":[\"28\",\"48\",\"18\"],\"explicitBounds\":[1e-05,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"http_requests\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"jobs_total\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"90\",\"sum\":11.018,\"bucketCounts\":[\"38\",\"39\",\"13\"],\"explicitBounds\":[0.005,2.5],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"57\",\"sum\":30.52,\"bucketCounts\":[\"18\",\"20\",\"19\"],\"explicitBounds\":[0.005,2.5],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"101\",\"sum\":75.4,\"bucketCounts\":[\"39\",\"14\",\"48\"],\"explicitBounds\":[1e-05,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"94\",\"sum\":75.16,\"bucketCounts\":[\"28\",\"48\",\"18\"],\"explicitBounds\":[1e-05,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"http_requests\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"jobs_total\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"90\",\"sum\":11.018,\"bucketCounts\":[\"38\",\"39\",\"13\"],\"explicitBounds\":[0.005,2.5],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"57\",\"sum\":30.52,\"bucketCounts\":[\"18\",\"20\",\"19\"],\"explicitBounds\":[0.005,2.5],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_73(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo1: [5]f64 = [5]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo1: [6]u64 = [6]u64{ 37u64, 40u64, 88u64, 120u64, 135u64, 146u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labo0[0usize..0usize], value: mem.bitcast[f64](13872837274812547072u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "x", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo1[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..5usize], buckets: cumo1[0usize..6usize], sum: mem.bitcast[f64](4643315009716643430u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "my.lib", samples[0usize..2usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-711.0}]}},{\"name\":\"x\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"146\",\"sum\":261.9,\"bucketCounts\":[\"37\",\"3\",\"48\",\"32\",\"15\",\"11\"],\"explicitBounds\":[0.005,0.25,1.0,2.5,100000.0]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-711.0}]}},{\"name\":\"x\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"146\",\"sum\":261.9,\"bucketCounts\":[\"37\",\"3\",\"48\",\"32\",\"15\",\"11\"],\"explicitBounds\":[0.005,0.25,1.0,2.5,100000.0]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_74(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Counter, labels: labo0[0usize..0usize], value: mem.bitcast[f64](4681291838974328832u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "my.lib", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":95394.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":95394.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_75(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "x\ny" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "200" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "GET" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "plain value" }, x.Label{ name: "code", value: "x\ny" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "" }, x.Label{ name: "code", value: "back\\slash" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    let labo6: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "200" } }
    let bndo6: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo6: [1]u64 = [1]u64{ 0u64 }
    let labo7: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "code", value: "plain value" } }
    let bndo7: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo7: [1]u64 = [1]u64{ 0u64 }
    var samples: [8]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo0[0usize..1usize], value: mem.bitcast[f64](13858333221106367857u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo1[0usize..1usize], value: mem.bitcast[f64](4681213636209803264u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo2[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Gauge, labels: labo3[0usize..3usize], value: mem.bitcast[f64](4658562597165989888u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Gauge, labels: labo4[0usize..3usize], value: mem.bitcast[f64](4618157691091919307u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "http_requests", help: "Total requests", kind: x.Kind.Gauge, labels: labo5[0usize..3usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[6] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Gauge, labels: labo6[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo6[0usize..0usize], buckets: cumo6[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[7] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Gauge, labels: labo7[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo7[0usize..0usize], buckets: cumo7[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..8usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-74.76,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":94256.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}}]}]}},{\"name\":\"http_requests\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":2885.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":5.748,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}]}},{\"name\":\"jobs_total\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-74.76,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":94256.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}}]}]}},{\"name\":\"http_requests\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":2885.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":5.748,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}]}},{\"name\":\"jobs_total\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_76(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "/a\"b" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "back\\slash" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "x\ny" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "code", value: "" }, x.Label{ name: "le_not", value: "" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Counter, labels: labo0[0usize..1usize], value: mem.bitcast[f64](4679289834458578944u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Counter, labels: labo1[0usize..1usize], value: mem.bitcast[f64](4696837146684686336u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Counter, labels: labo2[0usize..1usize], value: mem.bitcast[f64](4648381067595835297u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds_total", help: "Total requests", kind: x.Kind.Counter, labels: labo3[0usize..3usize], value: mem.bitcast[f64](4671809513257435136u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "my.lib", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":66261.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":587.7441,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds_total\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":22120.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":66261.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":587.7441,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds_total\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":22120.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_77(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "le_not", value: "200" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "path", value: "" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "le_not", value: "200" }, x.Label{ name: "path", value: "200" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo0[0usize..3usize], value: mem.bitcast[f64](4674855847661142016u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo1[0usize..3usize], value: mem.bitcast[f64](4642953314371570237u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo2[0usize..3usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "lib\\v1", samples[0usize..3usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":33637.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":248.67,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":33637.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":248.67,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_78(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "code", value: "200" }, x.Label{ name: "path", value: "plain value" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "plain value" }, x.Label{ name: "code", value: "plain value" }, x.Label{ name: "path", value: "" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "x\ny" } }
    let bndo4: [5]f64 = [5]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo4: [6]u64 = [6]u64{ 49u64, 51u64, 78u64, 115u64, 161u64, 161u64 }
    let labo5: [1]x.Label = [1]x.Label{ x.Label{ name: "method", value: "/a\"b" } }
    let bndo5: [5]f64 = [5]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo5: [6]u64 = [6]u64{ 16u64, 46u64, 75u64, 78u64, 92u64, 110u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labo0[0usize..3usize], value: mem.bitcast[f64](4616413672136220082u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labo1[0usize..3usize], value: mem.bitcast[f64](4618080003998347166u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labo2[0usize..3usize], value: mem.bitcast[f64](4594067936685114524u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds_11", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo3[0usize..0usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labo4[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo4[0usize..5usize], buckets: cumo4[0usize..6usize], sum: mem.bitcast[f64](4621882730933708128u64) }
    samples[5] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labo5[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo5[0usize..5usize], buckets: cumo5[0usize..6usize], sum: mem.bitcast[f64](4643828349705419489u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "my.lib", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.199,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":5.679,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.136,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"latency_seconds_11\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07}]}},{\"name\":\"queue_depth\",\"description\":\"back\\\\slash and\\nnewline\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"161\",\"sum\":10.113,\"bucketCounts\":[\"49\",\"2\",\"27\",\"37\",\"46\",\"0\"],\"explicitBounds\":[0.005,0.1,0.25,10.0,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"110\",\"sum\":291.08,\"bucketCounts\":[\"16\",\"30\",\"29\",\"3\",\"14\",\"18\"],\"explicitBounds\":[0.005,0.1,0.25,10.0,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.199,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":5.679,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.136,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"latency_seconds_11\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07}]}},{\"name\":\"queue_depth\",\"description\":\"back\\\\slash and\\nnewline\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"161\",\"sum\":10.113,\"bucketCounts\":[\"49\",\"2\",\"27\",\"37\",\"46\",\"0\"],\"explicitBounds\":[0.005,0.1,0.25,10.0,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"110\",\"sum\":291.08,\"bucketCounts\":[\"16\",\"30\",\"29\",\"3\",\"14\",\"18\"],\"explicitBounds\":[0.005,0.1,0.25,10.0,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_79(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "plain value" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo0[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_80(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "x\ny" } }
    let bndo0: [2]f64 = [2]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64) }
    let cumo0: [3]u64 = [3]u64{ 23u64, 71u64, 119u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 4u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "path", value: "x\ny" } }
    let bndo2: [2]f64 = [2]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo2: [3]u64 = [3]u64{ 32u64, 44u64, 88u64 }
    let labo3: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "x\ny" }, x.Label{ name: "method", value: "x\ny" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndo3: [2]f64 = [2]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo3: [3]u64 = [3]u64{ 39u64, 82u64, 119u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labo0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..2usize], buckets: cumo0[0usize..3usize], sum: mem.bitcast[f64](4639502783000818483u64) }
    samples[1] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Histogram, labels: labo1[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..1usize], sum: mem.bitcast[f64](4645322278144311296u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..2usize], buckets: cumo2[0usize..3usize], sum: mem.bitcast[f64](4642974305367958435u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..2usize], buckets: cumo3[0usize..3usize], sum: mem.bitcast[f64](4641934023112156774u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "lib\\v1", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"x\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"119\",\"sum\":150.6,\"bucketCounts\":[\"23\",\"48\",\"48\"],\"explicitBounds\":[0.25,5.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"queue_depth\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"4\",\"sum\":376.0,\"bucketCounts\":[\"4\"]}],\"aggregationTemporality\":2}},{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"88\",\"sum\":249.2666,\"bucketCounts\":[\"32\",\"12\",\"44\"],\"explicitBounds\":[0.1,10.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"119\",\"sum\":219.7,\"bucketCounts\":[\"39\",\"43\",\"37\"],\"explicitBounds\":[0.1,10.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"x\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"119\",\"sum\":150.6,\"bucketCounts\":[\"23\",\"48\",\"48\"],\"explicitBounds\":[0.25,5.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"queue_depth\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"4\",\"sum\":376.0,\"bucketCounts\":[\"4\"]}],\"aggregationTemporality\":2}},{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"88\",\"sum\":249.2666,\"bucketCounts\":[\"32\",\"12\",\"44\"],\"explicitBounds\":[0.1,10.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"119\",\"sum\":219.7,\"bucketCounts\":[\"39\",\"43\",\"37\"],\"explicitBounds\":[0.1,10.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_81(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "" }, x.Label{ name: "method", value: "200" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](4617315517961601024u64) }
    let cumo0: [2]u64 = [2]u64{ 40u64, 47u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "x\ny" }, x.Label{ name: "code", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "" } }
    let bndo1: [5]f64 = [5]f64{ mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo1: [6]u64 = [6]u64{ 0u64, 15u64, 28u64, 63u64, 63u64, 110u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..1usize], buckets: cumo0[0usize..2usize], sum: mem.bitcast[f64](4644134805586313216u64) }
    samples[1] = x.Sample{ name: "latency_seconds_89", help: "Total requests", kind: x.Kind.Histogram, labels: labo1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..5usize], buckets: cumo1[0usize..6usize], sum: mem.bitcast[f64](4645371536265235661u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..2usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"47\",\"sum\":308.5,\"bucketCounts\":[\"40\",\"7\"],\"explicitBounds\":[5.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds_89\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"110\",\"sum\":378.8,\"bucketCounts\":[\"0\",\"15\",\"13\",\"35\",\"0\",\"47\"],\"explicitBounds\":[1.0,2.5,5.0,10.0,100000.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"47\",\"sum\":308.5,\"bucketCounts\":[\"40\",\"7\"],\"explicitBounds\":[5.0],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds_89\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"110\",\"sum\":378.8,\"bucketCounts\":[\"0\",\"15\",\"13\",\"35\",\"0\",\"47\"],\"explicitBounds\":[1.0,2.5,5.0,10.0,100000.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_82(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "a", value: "x\ny" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "200" }, x.Label{ name: "le_not", value: "back\\slash" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "le_not", value: "back\\slash" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo0[0usize..0usize], value: mem.bitcast[f64](4674481326512930816u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "queue_depth_66", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4676446153791766528u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4678104492204359680u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4635763325307035100u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":31840.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"queue_depth_66\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":45208.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}}]}]}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":57274.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":86.15911,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":31840.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"queue_depth_66\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":45208.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}}]}]}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":57274.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":86.15911,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_83(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "code", value: "x\ny" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "200" }, x.Label{ name: "code", value: "GET" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "plain value" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "x\ny" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "method", value: "plain value" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "queue_depth", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4547007122018943789u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo2[0usize..1usize], value: mem.bitcast[f64](4732664617111650304u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo3[0usize..1usize], value: mem.bitcast[f64](13868009978961959322u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "latency_seconds_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo4[0usize..1usize], value: mem.bitcast[f64](4678764886375792640u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo5[0usize..3usize], value: mem.bitcast[f64](4673998640908337152u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "lib\\v1", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.0001,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":250000000.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-337.1,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":62079.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":30084.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.0001,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":250000000.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-337.1,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":62079.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":30084.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_84(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "le_not", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "x\ny" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "x\ny" }, x.Label{ name: "path", value: "" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4670752057949421568u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Counter, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4831355200913801216u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Counter, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "", kind: x.Kind.Counter, labels: labo3[0usize..2usize], value: mem.bitcast[f64](13872277215228904578u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "lib\\v1", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":18273.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"jobs_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000000000000.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-647.328597,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":18273.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"jobs_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000000000000.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-647.328597,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_85(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "" } }
    let bndo0: [4]f64 = [4]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo0: [5]u64 = [5]u64{ 34u64, 46u64, 77u64, 94u64, 117u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "code", value: "/a\"b" } }
    let bndo1: [4]f64 = [4]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo1: [5]u64 = [5]u64{ 36u64, 37u64, 63u64, 89u64, 93u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "" }, x.Label{ name: "code", value: "plain value" } }
    let bndo2: [4]f64 = [4]f64{ mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo2: [5]u64 = [5]u64{ 50u64, 77u64, 79u64, 106u64, 108u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "z", value: "200" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "caf\xc3\xa9" }, x.Label{ name: "z", value: "/a\"b" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..4usize], buckets: cumo0[0usize..5usize], sum: mem.bitcast[f64](4643450100113278501u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labo1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..4usize], buckets: cumo1[0usize..5usize], sum: mem.bitcast[f64](4634422159671191142u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "tab\there", kind: x.Kind.Histogram, labels: labo2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..4usize], buckets: cumo2[0usize..5usize], sum: mem.bitcast[f64](4635045626744605245u64) }
    samples[3] = x.Sample{ name: "jobs_total_54", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4650204109771636736u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "jobs_total_54", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo4[0usize..2usize], value: mem.bitcast[f64](4681376226491760640u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "jobs_total_54", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo5[0usize..2usize], value: mem.bitcast[f64](4621673876500988822u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "my.lib", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"117\",\"sum\":269.579,\"bucketCounts\":[\"34\",\"12\",\"31\",\"17\",\"23\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"93\",\"sum\":67.1,\"bucketCounts\":[\"36\",\"1\",\"26\",\"26\",\"4\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"108\",\"sum\":75.96,\"bucketCounts\":[\"50\",\"27\",\"2\",\"27\",\"2\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"jobs_total_54\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":795.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":96622.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":9.742,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"117\",\"sum\":269.579,\"bucketCounts\":[\"34\",\"12\",\"31\",\"17\",\"23\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"93\",\"sum\":67.1,\"bucketCounts\":[\"36\",\"1\",\"26\",\"26\",\"4\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"108\",\"sum\":75.96,\"bucketCounts\":[\"50\",\"27\",\"2\",\"27\",\"2\"],\"explicitBounds\":[0.5,2.5,10.0,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"jobs_total_54\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":795.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":96622.0,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":9.742,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_86(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "plain value" }, x.Label{ name: "method", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "method", value: "caf\xc3\xa9" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo3: [5]f64 = [5]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo3: [6]u64 = [6]u64{ 45u64, 66u64, 108u64, 149u64, 192u64, 201u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Gauge, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4642115117075297993u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Gauge, labels: labo1[0usize..2usize], value: mem.bitcast[f64](13862544086757959270u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds_92_total", help: "", kind: x.Kind.Counter, labels: labo2[0usize..0usize], value: mem.bitcast[f64](4705844345939427328u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Histogram, labels: labo3[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..5usize], buckets: cumo3[0usize..6usize], sum: mem.bitcast[f64](4640407373207222354u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":224.847,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-141.2,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}]}},{\"name\":\"latency_seconds_92_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4000000.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"201\",\"sum\":176.31,\"bucketCounts\":[\"45\",\"21\",\"42\",\"41\",\"43\",\"9\"],\"explicitBounds\":[0.005,0.25,0.3,1.0,10.0]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":224.847,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-141.2,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}]}},{\"name\":\"latency_seconds_92_total\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4000000.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"201\",\"sum\":176.31,\"bucketCounts\":[\"45\",\"21\",\"42\",\"41\",\"43\",\"9\"],\"explicitBounds\":[0.005,0.25,0.3,1.0,10.0]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_87(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "200" }, x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndo0: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo0: [4]u64 = [4]u64{ 37u64, 67u64, 82u64, 115u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "" }, x.Label{ name: "a", value: "" }, x.Label{ name: "code", value: "plain value" } }
    let bndo1: [3]f64 = [3]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo1: [4]u64 = [4]u64{ 34u64, 62u64, 80u64, 89u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "path", value: "back\\slash" } }
    let bndo3: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo3: [4]u64 = [4]u64{ 6u64, 22u64, 47u64, 81u64 }
    let labo4: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "back\\slash" }, x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "path", value: "" } }
    let bndo4: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4612811918334230528u64) }
    let cumo4: [4]u64 = [4]u64{ 44u64, 58u64, 60u64, 81u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Histogram, labels: labo0[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..3usize], buckets: cumo0[0usize..4usize], sum: mem.bitcast[f64](4645568568748933120u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Histogram, labels: labo1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..3usize], buckets: cumo1[0usize..4usize], sum: mem.bitcast[f64](4643492690795692032u64) }
    samples[2] = x.Sample{ name: "latency_seconds_60", help: "back\\slash and\nnewline", kind: x.Kind.Gauge, labels: labo2[0usize..0usize], value: mem.bitcast[f64](13871705217640588902u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Histogram, labels: labo3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..3usize], buckets: cumo3[0usize..4usize], sum: mem.bitcast[f64](4643940329247248010u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Histogram, labels: labo4[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo4[0usize..3usize], buckets: cumo4[0usize..4usize], sum: mem.bitcast[f64](4636174341401214976u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "lib\\v1", samples[0usize..5usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"115\",\"sum\":390.0,\"bucketCounts\":[\"37\",\"30\",\"15\",\"33\"],\"explicitBounds\":[1e-05,2.5,10.0],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"89\",\"sum\":272.0,\"bucketCounts\":[\"34\",\"28\",\"18\",\"9\"],\"explicitBounds\":[1e-05,2.5,10.0],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds_60\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-582.3}]}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"81\",\"sum\":297.4453,\"bucketCounts\":[\"6\",\"16\",\"25\",\"34\"],\"explicitBounds\":[0.25,0.3,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"81\",\"sum\":92.0,\"bucketCounts\":[\"44\",\"14\",\"2\",\"21\"],\"explicitBounds\":[0.25,0.3,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"115\",\"sum\":390.0,\"bucketCounts\":[\"37\",\"30\",\"15\",\"33\"],\"explicitBounds\":[1e-05,2.5,10.0],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"89\",\"sum\":272.0,\"bucketCounts\":[\"34\",\"28\",\"18\",\"9\"],\"explicitBounds\":[1e-05,2.5,10.0],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds_60\",\"description\":\"back\\\\slash and\\nnewline\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-582.3}]}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"81\",\"sum\":297.4453,\"bucketCounts\":[\"6\",\"16\",\"25\",\"34\"],\"explicitBounds\":[0.25,0.3,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"81\",\"sum\":92.0,\"bucketCounts\":[\"44\",\"14\",\"2\",\"21\"],\"explicitBounds\":[0.25,0.3,2.5],\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_88(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "plain value" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo0[0usize..1usize], value: mem.bitcast[f64](4620249613118832902u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "lib\\v1", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":7.606,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":7.606,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_89(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "back\\slash" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 40u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "/a\"b" }, x.Label{ name: "z", value: "" }, x.Label{ name: "path", value: "plain value" } }
    let bndo1: [2]f64 = [2]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4607182418800017408u64) }
    let cumo1: [3]u64 = [3]u64{ 28u64, 55u64, 96u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "code", value: "back\\slash" }, x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndo2: [2]f64 = [2]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4607182418800017408u64) }
    let cumo2: [3]u64 = [3]u64{ 32u64, 81u64, 118u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo3: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo3: [5]u64 = [5]u64{ 4u64, 35u64, 59u64, 86u64, 101u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "back\\slash and\nnewline", kind: x.Kind.Histogram, labels: labo0[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..1usize], sum: mem.bitcast[f64](4644261821169553900u64) }
    samples[1] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labo1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..2usize], buckets: cumo1[0usize..3usize], sum: mem.bitcast[f64](4643823934066722341u64) }
    samples[2] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Histogram, labels: labo2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..2usize], buckets: cumo2[0usize..3usize], sum: mem.bitcast[f64](4639293038403485329u64) }
    samples[3] = x.Sample{ name: "temp_c_94", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labo3[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..4usize], buckets: cumo3[0usize..5usize], sum: mem.bitcast[f64](4644564054925796966u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"temp_c\",\"description\":\"back\\\\slash and\\nnewline\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"40\",\"sum\":315.72,\"bucketCounts\":[\"40\"],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"96\",\"sum\":290.829,\"bucketCounts\":[\"28\",\"27\",\"41\"],\"explicitBounds\":[1e-05,1.0],\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"118\",\"sum\":144.6387,\"bucketCounts\":[\"32\",\"49\",\"37\"],\"explicitBounds\":[1e-05,1.0],\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"temp_c_94\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"101\",\"sum\":332.9,\"bucketCounts\":[\"4\",\"31\",\"24\",\"27\",\"15\"],\"explicitBounds\":[1e-05,0.005,0.5,100000.0]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"temp_c\",\"description\":\"back\\\\slash and\\nnewline\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"40\",\"sum\":315.72,\"bucketCounts\":[\"40\"],\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"96\",\"sum\":290.829,\"bucketCounts\":[\"28\",\"27\",\"41\"],\"explicitBounds\":[1e-05,1.0],\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"118\",\"sum\":144.6387,\"bucketCounts\":[\"32\",\"49\",\"37\"],\"explicitBounds\":[1e-05,1.0],\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"temp_c_94\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"101\",\"sum\":332.9,\"bucketCounts\":[\"4\",\"31\",\"24\",\"27\",\"15\"],\"explicitBounds\":[1e-05,0.005,0.5,100000.0]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_90(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "200" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "back\\slash" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](4621819117588971520u64) }
    let cumo2: [2]u64 = [2]u64{ 18u64, 49u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](4621819117588971520u64) }
    let cumo3: [2]u64 = [2]u64{ 17u64, 17u64 }
    let labo4: [1]x.Label = [1]x.Label{ x.Label{ name: "a", value: "200" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](4621819117588971520u64) }
    let cumo4: [2]u64 = [2]u64{ 40u64, 46u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo0[0usize..1usize], value: mem.bitcast[f64](4741671816358002688u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo1[0usize..1usize], value: mem.bitcast[f64](13863815298121528771u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "", kind: x.Kind.Histogram, labels: labo2[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..1usize], buckets: cumo2[0usize..2usize], sum: mem.bitcast[f64](4641133684200252113u64) }
    samples[3] = x.Sample{ name: "x", help: "", kind: x.Kind.Histogram, labels: labo3[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..1usize], buckets: cumo3[0usize..2usize], sum: mem.bitcast[f64](4643420439687607615u64) }
    samples[4] = x.Sample{ name: "x", help: "", kind: x.Kind.Histogram, labels: labo4[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo4[0usize..1usize], buckets: cumo4[0usize..2usize], sum: mem.bitcast[f64](4644096071111080621u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "lib\\v1", samples[0usize..5usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":999999999.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-177.33,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"49\",\"sum\":196.953,\"bucketCounts\":[\"18\",\"31\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"17\",\"sum\":267.893,\"bucketCounts\":[\"17\",\"0\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"46\",\"sum\":306.2982,\"bucketCounts\":[\"40\",\"6\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"temp_c\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":999999999.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-177.33,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"49\",\"sum\":196.953,\"bucketCounts\":[\"18\",\"31\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"17\",\"sum\":267.893,\"bucketCounts\":[\"17\",\"0\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"46\",\"sum\":306.2982,\"bucketCounts\":[\"40\",\"6\"],\"explicitBounds\":[10.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_91(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "200" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](4599075939470750515u64) }
    let cumo0: [2]u64 = [2]u64{ 48u64, 97u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "plain value" }, x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "caf\xc3\xa9" } }
    let bndo1: [4]f64 = [4]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo1: [5]u64 = [5]u64{ 50u64, 61u64, 106u64, 127u64, 142u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "path", value: "GET" }, x.Label{ name: "a", value: "plain value" } }
    let bndo2: [4]f64 = [4]f64{ mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo2: [5]u64 = [5]u64{ 19u64, 20u64, 54u64, 71u64, 99u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "z", value: "/a\"b" } }
    let bndo3: [3]f64 = [3]f64{ mem.bitcast[f64](4598175219545276416u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo3: [4]u64 = [4]u64{ 30u64, 54u64, 84u64, 85u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "http_requests", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..1usize], buckets: cumo0[0usize..2usize], sum: mem.bitcast[f64](4639960595013563947u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Histogram, labels: labo1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..4usize], buckets: cumo1[0usize..5usize], sum: mem.bitcast[f64](4646698965218528697u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "", kind: x.Kind.Histogram, labels: labo2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..4usize], buckets: cumo2[0usize..5usize], sum: mem.bitcast[f64](4641098042431326126u64) }
    samples[3] = x.Sample{ name: "x", help: "A \"quoted\" help", kind: x.Kind.Histogram, labels: labo3[0usize..1usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..3usize], buckets: cumo3[0usize..4usize], sum: mem.bitcast[f64](4634255878328699322u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "lib\\v1", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"http_requests\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"97\",\"sum\":163.6118,\"bucketCounts\":[\"48\",\"49\"],\"explicitBounds\":[0.3],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"142\",\"sum\":454.2556,\"bucketCounts\":[\"50\",\"11\",\"45\",\"21\",\"15\"],\"explicitBounds\":[0.1,1.0,2.5,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"99\",\"sum\":195.94,\"bucketCounts\":[\"19\",\"1\",\"34\",\"17\",\"28\"],\"explicitBounds\":[0.1,1.0,2.5,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"85\",\"sum\":64.737,\"bucketCounts\":[\"30\",\"24\",\"30\",\"1\"],\"explicitBounds\":[0.25,5.0,100.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"http_requests\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"97\",\"sum\":163.6118,\"bucketCounts\":[\"48\",\"49\"],\"explicitBounds\":[0.3],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"142\",\"sum\":454.2556,\"bucketCounts\":[\"50\",\"11\",\"45\",\"21\",\"15\"],\"explicitBounds\":[0.1,1.0,2.5,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"99\",\"sum\":195.94,\"bucketCounts\":[\"19\",\"1\",\"34\",\"17\",\"28\"],\"explicitBounds\":[0.1,1.0,2.5,100.0],\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"description\":\"A \\\"quoted\\\" help\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"85\",\"sum\":64.737,\"bucketCounts\":[\"30\",\"24\",\"30\",\"1\"],\"explicitBounds\":[0.25,5.0,100.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_92(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "GET" }, x.Label{ name: "method", value: "caf\xc3\xa9" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "" }, x.Label{ name: "method", value: "200" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "code", value: "plain value" }, x.Label{ name: "method", value: "plain value" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo0[0usize..3usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo1[0usize..3usize], value: mem.bitcast[f64](4698053238757261312u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "x", help: "Total requests", kind: x.Kind.Counter, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4680633781265104896u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "lib\\v1", samples[0usize..3usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds_total\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1234567.5,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":85818.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds_total\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1234567.5,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"x\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":85818.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_93(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [2]f64 = [2]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4607182418800017408u64) }
    let cumo0: [3]u64 = [3]u64{ 19u64, 30u64, 73u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "/a\"b" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "path", value: "plain value" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Histogram, labels: labo0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..2usize], buckets: cumo0[0usize..3usize], sum: mem.bitcast[f64](4634236034342841221u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labo1[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Counter, labels: labo2[0usize..1usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "jobs_total", help: "A \"quoted\" help", kind: x.Kind.Gauge, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "lib\\v1", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"73\",\"sum\":64.455,\"bucketCounts\":[\"19\",\"11\",\"43\"],\"explicitBounds\":[0.005,1.0]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"73\",\"sum\":64.455,\"bucketCounts\":[\"19\",\"11\",\"43\"],\"explicitBounds\":[0.005,1.0]}],\"aggregationTemporality\":2}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"jobs_total\",\"description\":\"A \\\"quoted\\\" help\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_94(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "GET" }, x.Label{ name: "z", value: "GET" } }
    let bndo0: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo0: [5]u64 = [5]u64{ 37u64, 74u64, 79u64, 93u64, 113u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "x\ny" }, x.Label{ name: "z", value: "200" } }
    let bndo1: [4]f64 = [4]f64{ mem.bitcast[f64](4532020583610935537u64), mem.bitcast[f64](4591870180066957722u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4681608360884174848u64) }
    let cumo1: [5]u64 = [5]u64{ 32u64, 66u64, 74u64, 74u64, 93u64 }
    let labo2: [1]x.Label = [1]x.Label{ x.Label{ name: "code", value: "200" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    var samples: [3]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..4usize], buckets: cumo0[0usize..5usize], sum: mem.bitcast[f64](4635672612255228232u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..4usize], buckets: cumo1[0usize..5usize], sum: mem.bitcast[f64](4647499434312610087u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "Total requests", kind: x.Kind.Gauge, labels: labo2[0usize..1usize], value: mem.bitcast[f64](4677935029974728704u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "my.lib", samples[0usize..3usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"113\",\"sum\":84.87,\"bucketCounts\":[\"37\",\"37\",\"5\",\"14\",\"20\"],\"explicitBounds\":[1e-05,0.1,2.5,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"93\",\"sum\":499.757,\"bucketCounts\":[\"32\",\"34\",\"8\",\"0\",\"19\"],\"explicitBounds\":[1e-05,0.1,2.5,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"temp_c\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":56041.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"113\",\"sum\":84.87,\"bucketCounts\":[\"37\",\"37\",\"5\",\"14\",\"20\"],\"explicitBounds\":[1e-05,0.1,2.5,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"93\",\"sum\":499.757,\"bucketCounts\":[\"32\",\"34\",\"8\",\"0\",\"19\"],\"explicitBounds\":[1e-05,0.1,2.5,100000.0],\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"temp_c\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":56041.0,\"attributes\":[{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_95(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "z", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "plain value" }, x.Label{ name: "method", value: "back\\slash" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "path", value: "/a\"b" }, x.Label{ name: "method", value: "/a\"b" }, x.Label{ name: "z", value: "back\\slash" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "200" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [2]x.Label = [2]x.Label{ x.Label{ name: "path", value: "GET" }, x.Label{ name: "le_not", value: "caf\xc3\xa9" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labo0[0usize..3usize], value: mem.bitcast[f64](4465333615686632963u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labo1[0usize..3usize], value: mem.bitcast[f64](4673094017716584448u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "jobs_total", help: "Total requests", kind: x.Kind.Counter, labels: labo2[0usize..3usize], value: mem.bitcast[f64](13867111801318474873u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Gauge, labels: labo3[0usize..0usize], value: mem.bitcast[f64](4732664617111650304u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo4[0usize..2usize], value: mem.bitcast[f64](4617174780473245696u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "x", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo5[0usize..2usize], value: mem.bitcast[f64](4649177077950363730u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":3.5e-10,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":26793.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-286.044512,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":250000000.0}]}},{\"name\":\"x\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.875,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":678.24,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":3.5e-10,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":26793.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-286.044512,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":250000000.0}]}},{\"name\":\"x\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.875,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":678.24,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"le_not\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_96(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "queue_depth", help: "Total requests", kind: x.Kind.Counter, labels: labo0[0usize..0usize], value: mem.bitcast[f64](4831355200913801216u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "my.lib", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000000000000.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"queue_depth\",\"description\":\"Total requests\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1000000000000000.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_97(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "method", value: "caf\xc3\xa9" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" }, x.Label{ name: "method", value: "plain value" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    var samples: [2]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4615277639130215875u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "my.lib", samples[0usize..2usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":3.595,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":3.595,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"method\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_98(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "code", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "200" }, x.Label{ name: "code", value: "200" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "x\ny" }, x.Label{ name: "code", value: "x\ny" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [1]x.Label = [1]x.Label{ x.Label{ name: "le_not", value: "" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "GET" }, x.Label{ name: "code", value: "" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    let labo6: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "200" }, x.Label{ name: "code", value: "/a\"b" } }
    let bndo6: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo6: [1]u64 = [1]u64{ 0u64 }
    let labo7: [2]x.Label = [2]x.Label{ x.Label{ name: "method", value: "caf\xc3\xa9" }, x.Label{ name: "code", value: "" } }
    let bndo7: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo7: [1]u64 = [1]u64{ 0u64 }
    var samples: [8]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Gauge, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4644231562609557504u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Gauge, labels: labo1[0usize..2usize], value: mem.bitcast[f64](4548686525128629352u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "", kind: x.Kind.Gauge, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labo3[0usize..1usize], value: mem.bitcast[f64](13849294496654235271u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Gauge, labels: labo4[0usize..1usize], value: mem.bitcast[f64](4674864231437303808u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "temp_c_54_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo5[0usize..2usize], value: mem.bitcast[f64](4679662775058825216u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[6] = x.Sample{ name: "temp_c_54_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo6[0usize..2usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo6[0usize..0usize], buckets: cumo6[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[7] = x.Sample{ name: "temp_c_54_total", help: "A \"quoted\" help", kind: x.Kind.Counter, labels: labo7[0usize..2usize], value: mem.bitcast[f64](4502148214488346440u64), bounds: bndo7[0usize..0usize], buckets: cumo7[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "my.lib", samples[0usize..8usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":314.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.00012345,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]}]}},{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-18.578,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":33698.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"temp_c_54_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":71688.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"temp_c\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":314.0,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.00012345,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"x\\ny\"}}]}]}},{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-18.578,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":33698.0,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"\"}}]}]}},{\"name\":\"temp_c_54_total\",\"description\":\"A \\\"quoted\\\" help\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":71688.0,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1e-07,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_99(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "caf\xc3\xa9" }, x.Label{ name: "path", value: "caf\xc3\xa9" } }
    let bndo0: [5]f64 = [5]f64{ mem.bitcast[f64](4572414629676717179u64), mem.bitcast[f64](4602678819172646912u64), mem.bitcast[f64](4607182418800017408u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo0: [6]u64 = [6]u64{ 30u64, 33u64, 37u64, 57u64, 75u64, 114u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "tab\there", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..5usize], buckets: cumo0[0usize..6usize], sum: mem.bitcast[f64](4641768656563339264u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "lib\\v1", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"114\",\"sum\":215.0,\"bucketCounts\":[\"30\",\"3\",\"4\",\"20\",\"18\",\"39\"],\"explicitBounds\":[0.005,0.5,1.0,5.0,100.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"114\",\"sum\":215.0,\"bucketCounts\":[\"30\",\"3\",\"4\",\"20\",\"18\",\"39\"],\"explicitBounds\":[0.005,0.5,1.0,5.0,100.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_100(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "jobs_total", help: "caf\xc3\xa9 au lait", kind: x.Kind.Gauge, labels: labo0[0usize..0usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004}]}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"metrics\":[{\"name\":\"jobs_total\",\"description\":\"caf\xc3\xa9 au lait\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004}]}}]}]}]}")
        ret false
    }
    ret true
}

fn case_101(a: *mem.Arena) -> bool {
    let labo0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo0: [4]f64 = [4]f64{ mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4617315517961601024u64), mem.bitcast[f64](4621819117588971520u64), mem.bitcast[f64](4636737291354636288u64) }
    let cumo0: [5]u64 = [5]u64{ 41u64, 91u64, 113u64, 134u64, 161u64 }
    var samples: [1]x.Sample = zero
    samples[0] = x.Sample{ name: "latency_seconds", help: "caf\xc3\xa9 au lait", kind: x.Kind.Histogram, labels: labo0[0usize..0usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..4usize], buckets: cumo0[0usize..5usize], sum: mem.bitcast[f64](4645256360223202869u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "checkout" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..1usize], "lib\\v1", samples[0usize..1usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"161\",\"sum\":372.253,\"bucketCounts\":[\"41\",\"50\",\"22\",\"21\",\"27\"],\"explicitBounds\":[2.5,5.0,10.0,100.0]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"latency_seconds\",\"description\":\"caf\xc3\xa9 au lait\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"161\",\"sum\":372.253,\"bucketCounts\":[\"41\",\"50\",\"22\",\"21\",\"27\"],\"explicitBounds\":[2.5,5.0,10.0,100.0]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_102(a: *mem.Arena) -> bool {
    let labo0: [3]x.Label = [3]x.Label{ x.Label{ name: "method", value: "GET" }, x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "z", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo1: [1]u64 = [1]u64{ 0u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "back\\slash" }, x.Label{ name: "path", value: "200" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo2: [1]u64 = [1]u64{ 0u64 }
    let labo3: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "path", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "path", value: "x\ny" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    var samples: [5]x.Sample = zero
    samples[0] = x.Sample{ name: "x_total", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo0[0usize..3usize], value: mem.bitcast[f64](4599075939470750516u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "http_requests", help: "back\\slash and\nnewline", kind: x.Kind.Counter, labels: labo1[0usize..0usize], value: mem.bitcast[f64](4680621755356676096u64), bounds: bndo1[0usize..0usize], buckets: cumo1[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo2[0usize..2usize], value: mem.bitcast[f64](4609389182617428951u64), bounds: bndo2[0usize..0usize], buckets: cumo2[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[3] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo3[0usize..2usize], value: mem.bitcast[f64](4598409406725899682u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "temp_c", help: "caf\xc3\xa9 au lait", kind: x.Kind.Counter, labels: labo4[0usize..2usize], value: mem.bitcast[f64](13864010782141010600u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [2]x.Label = [2]x.Label{ x.Label{ name: "service.name", value: "cart \"x\"" }, x.Label{ name: "host", value: "caf\xc3\xa9" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..2usize], "lib\\v1", samples[0usize..5usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"x_total\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"http_requests\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":85643.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"temp_c\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1.49,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.263,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-182.88599,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cart \\\"x\\\"\"}},{\"key\":\"host\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"lib\\\\v1\"},\"metrics\":[{\"name\":\"x_total\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.30000000000000004,\"attributes\":[{\"key\":\"method\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"http_requests\",\"description\":\"back\\\\slash and\\nnewline\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":85643.0}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"temp_c\",\"description\":\"caf\xc3\xa9 au lait\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":1.49,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"200\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.263,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":-182.88599,\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_103(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "code", value: "GET" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](4572414629676717179u64) }
    let cumo0: [2]u64 = [2]u64{ 11u64, 41u64 }
    let labo1: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "/a\"b" }, x.Label{ name: "code", value: "plain value" } }
    let bndo1: [1]f64 = [1]f64{ mem.bitcast[f64](4572414629676717179u64) }
    let cumo1: [2]u64 = [2]u64{ 50u64, 85u64 }
    let labo2: [2]x.Label = [2]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "code", value: "plain value" } }
    let bndo2: [1]f64 = [1]f64{ mem.bitcast[f64](4572414629676717179u64) }
    let cumo2: [2]u64 = [2]u64{ 9u64, 30u64 }
    let labo3: [1]x.Label = [1]x.Label{ x.Label{ name: "path", value: "/a\"b" } }
    let bndo3: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo3: [1]u64 = [1]u64{ 0u64 }
    let labo4: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "x\ny" }, x.Label{ name: "a", value: "GET" }, x.Label{ name: "z", value: "caf\xc3\xa9" } }
    let bndo4: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo4: [1]u64 = [1]u64{ 0u64 }
    let labo5: [3]x.Label = [3]x.Label{ x.Label{ name: "le_not", value: "GET" }, x.Label{ name: "a", value: "/a\"b" }, x.Label{ name: "z", value: "x\ny" } }
    let bndo5: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo5: [1]u64 = [1]u64{ 0u64 }
    var samples: [6]x.Sample = zero
    samples[0] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labo0[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo0[0usize..1usize], buckets: cumo0[0usize..2usize], sum: mem.bitcast[f64](4643624632191025152u64) }
    samples[1] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labo1[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..1usize], buckets: cumo1[0usize..2usize], sum: mem.bitcast[f64](4627408112874035977u64) }
    samples[2] = x.Sample{ name: "temp_c", help: "tab\there", kind: x.Kind.Histogram, labels: labo2[0usize..2usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..1usize], buckets: cumo2[0usize..2usize], sum: mem.bitcast[f64](4647190216458507387u64) }
    samples[3] = x.Sample{ name: "x", help: "", kind: x.Kind.Gauge, labels: labo3[0usize..1usize], value: mem.bitcast[f64](4680185936435216384u64), bounds: bndo3[0usize..0usize], buckets: cumo3[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[4] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Counter, labels: labo4[0usize..3usize], value: mem.bitcast[f64](4619553806976404161u64), bounds: bndo4[0usize..0usize], buckets: cumo4[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[5] = x.Sample{ name: "queue_depth", help: "tab\there", kind: x.Kind.Counter, labels: labo5[0usize..3usize], value: mem.bitcast[f64](4547007122018943789u64), bounds: bndo5[0usize..0usize], buckets: cumo5[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "", samples[0usize..6usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"temp_c\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"41\",\"sum\":279.5,\"bucketCounts\":[\"11\",\"30\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"85\",\"sum\":23.8561,\"bucketCounts\":[\"50\",\"35\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"30\",\"sum\":482.18,\"bucketCounts\":[\"9\",\"21\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":79301.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}]}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":6.988,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.0001,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"metrics\":[{\"name\":\"temp_c\",\"description\":\"tab\\there\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"41\",\"sum\":279.5,\"bucketCounts\":[\"11\",\"30\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"GET\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"85\",\"sum\":23.8561,\"bucketCounts\":[\"50\",\"35\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"30\",\"sum\":482.18,\"bucketCounts\":[\"9\",\"21\"],\"explicitBounds\":[0.005],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"plain value\"}}]}],\"aggregationTemporality\":2}},{\"name\":\"x\",\"gauge\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":79301.0,\"attributes\":[{\"key\":\"path\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}]}},{\"name\":\"queue_depth\",\"description\":\"tab\\there\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":6.988,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":0.0001,\"attributes\":[{\"key\":\"le_not\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"z\",\"value\":{\"stringValue\":\"x\\ny\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}}]}]}]}")
        ret false
    }
    ret true
}

fn case_104(a: *mem.Arena) -> bool {
    let labo0: [2]x.Label = [2]x.Label{ x.Label{ name: "a", value: "200" }, x.Label{ name: "code", value: "caf\xc3\xa9" } }
    let bndo0: [1]f64 = [1]f64{ mem.bitcast[f64](0u64) }
    let cumo0: [1]u64 = [1]u64{ 0u64 }
    let labo1: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "plain value" }, x.Label{ name: "path", value: "plain value" }, x.Label{ name: "a", value: "" } }
    let bndo1: [3]f64 = [3]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo1: [4]u64 = [4]u64{ 42u64, 81u64, 127u64, 156u64 }
    let labo2: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "path", value: "" }, x.Label{ name: "a", value: "" } }
    let bndo2: [3]f64 = [3]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo2: [4]u64 = [4]u64{ 1u64, 43u64, 68u64, 91u64 }
    let labo3: [3]x.Label = [3]x.Label{ x.Label{ name: "z", value: "GET" }, x.Label{ name: "path", value: "back\\slash" }, x.Label{ name: "a", value: "/a\"b" } }
    let bndo3: [3]f64 = [3]f64{ mem.bitcast[f64](4599075939470750515u64), mem.bitcast[f64](4612811918334230528u64), mem.bitcast[f64](4621819117588971520u64) }
    let cumo3: [4]u64 = [4]u64{ 10u64, 45u64, 94u64, 106u64 }
    var samples: [4]x.Sample = zero
    samples[0] = x.Sample{ name: "x", help: "", kind: x.Kind.Counter, labels: labo0[0usize..2usize], value: mem.bitcast[f64](4616829129201845010u64), bounds: bndo0[0usize..0usize], buckets: cumo0[0usize..0usize], sum: mem.bitcast[f64](0u64) }
    samples[1] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Histogram, labels: labo1[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo1[0usize..3usize], buckets: cumo1[0usize..4usize], sum: mem.bitcast[f64](4646821969783351253u64) }
    samples[2] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Histogram, labels: labo2[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo2[0usize..3usize], buckets: cumo2[0usize..4usize], sum: mem.bitcast[f64](4647484882056314146u64) }
    samples[3] = x.Sample{ name: "latency_seconds", help: "Total requests", kind: x.Kind.Histogram, labels: labo3[0usize..3usize], value: mem.bitcast[f64](0u64), bounds: bndo3[0usize..3usize], buckets: cumo3[0usize..4usize], sum: mem.bitcast[f64](4643864237764950098u64) }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_metrics(a, res[0usize..0usize], "my.lib", samples[0usize..4usize], 1700000000000000000u64, 1700000060123456789u64)
    if ge != ok || !str.eq(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"x\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.568,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"156\",\"sum\":461.2476,\"bucketCounts\":[\"42\",\"39\",\"46\",\"29\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"91\",\"sum\":498.9298,\"bucketCounts\":[\"1\",\"42\",\"25\",\"23\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"106\",\"sum\":293.12,\"bucketCounts\":[\"10\",\"35\",\"49\",\"12\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}") {
        show(got, "{\"resourceMetrics\":[{\"scopeMetrics\":[{\"scope\":{\"name\":\"my.lib\"},\"metrics\":[{\"name\":\"x\",\"sum\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"asDouble\":4.568,\"attributes\":[{\"key\":\"a\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"code\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}]}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"latency_seconds\",\"description\":\"Total requests\",\"histogram\":{\"dataPoints\":[{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"156\",\"sum\":461.2476,\"bucketCounts\":[\"42\",\"39\",\"46\",\"29\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"91\",\"sum\":498.9298,\"bucketCounts\":[\"1\",\"42\",\"25\",\"23\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"\"}}]},{\"startTimeUnixNano\":\"1700000000000000000\",\"timeUnixNano\":\"1700000060123456789\",\"count\":\"106\",\"sum\":293.12,\"bucketCounts\":[\"10\",\"35\",\"49\",\"12\"],\"explicitBounds\":[0.3,2.5,10.0],\"attributes\":[{\"key\":\"z\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"path\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}],\"aggregationTemporality\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_105(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "GET" }, x.Label{ name: "peer1", value: "x\ny" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 204, 80, 108, 84, 112, 33, 209, 87, 221, 6, 65, 19, 71, 79, 118, 188 }, span_id: [8]u8{ 109, 29, 238, 12, 48, 128, 131, 216 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 2u8, start_ns: 3202362266388762745u64, end_ns: 1867550389081196588u64, attributes: sat0[0usize..2usize], status_code: 1u8, status_message: "line\nbreak" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 57, 89, 50, 191, 228, 15, 84, 119, 36, 220, 200, 36, 17, 70, 98, 99 }, span_id: [8]u8{ 84, 130, 184, 205, 123, 21, 77, 135 }, parent_span_id: [8]u8{ 123, 189, 35, 22, 145, 169, 203, 250 }, name: "caf\xc3\xa9", kind: 4u8, start_ns: 503064595383594689u64, end_ns: 4142319503410466539u64, attributes: sat1[0usize..0usize], status_code: 2u8, status_message: "line\nbreak" }
    let sat2: [2]x.Label = [2]x.Label{ x.Label{ name: "http.method0", value: "200" }, x.Label{ name: "k1", value: "plain value" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 123, 120, 149, 213, 215, 222, 53, 19, 228, 67, 47, 67, 236, 174, 186, 102 }, span_id: [8]u8{ 157, 225, 225, 70, 13, 230, 177, 28 }, parent_span_id: [8]u8{ 194, 55, 82, 214, 174, 185, 60, 217 }, name: "GET /a", kind: 3u8, start_ns: 1026799869787618515u64, end_ns: 3563885748689203661u64, attributes: sat2[0usize..2usize], status_code: 1u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"cc506c547021d157dd064113474f76bc\",\"spanId\":\"6d1dee0c308083d8\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"3202362266388762745\",\"endTimeUnixNano\":\"1867550389081196588\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"395932bfe40f547724dcc82411466263\",\"spanId\":\"5482b8cd7b154d87\",\"parentSpanId\":\"7bbd231691a9cbfa\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"503064595383594689\",\"endTimeUnixNano\":\"4142319503410466539\",\"status\":{\"message\":\"line\\nbreak\",\"code\":2}},{\"traceId\":\"7b7895d5d7de3513e4432f43ecaeba66\",\"spanId\":\"9de1e1460de6b11c\",\"parentSpanId\":\"c23752d6aeb93cd9\",\"name\":\"GET /a\",\"kind\":3,\"startTimeUnixNano\":\"1026799869787618515\",\"endTimeUnixNano\":\"3563885748689203661\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"cc506c547021d157dd064113474f76bc\",\"spanId\":\"6d1dee0c308083d8\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"3202362266388762745\",\"endTimeUnixNano\":\"1867550389081196588\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"395932bfe40f547724dcc82411466263\",\"spanId\":\"5482b8cd7b154d87\",\"parentSpanId\":\"7bbd231691a9cbfa\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"503064595383594689\",\"endTimeUnixNano\":\"4142319503410466539\",\"status\":{\"message\":\"line\\nbreak\",\"code\":2}},{\"traceId\":\"7b7895d5d7de3513e4432f43ecaeba66\",\"spanId\":\"9de1e1460de6b11c\",\"parentSpanId\":\"c23752d6aeb93cd9\",\"name\":\"GET /a\",\"kind\":3,\"startTimeUnixNano\":\"1026799869787618515\",\"endTimeUnixNano\":\"3563885748689203661\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_106(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "GET" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 245, 200, 100, 72, 177, 25, 43, 47, 120, 54, 124, 132, 91, 113, 137, 175 }, span_id: [8]u8{ 193, 59, 231, 131, 155, 175, 25, 206 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 0u8, start_ns: 1957354242975200410u64, end_ns: 2050108799548355070u64, attributes: sat0[0usize..1usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"f5c86448b1192b2f78367c845b7189af\",\"spanId\":\"c13be7839baf19ce\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1957354242975200410\",\"endTimeUnixNano\":\"2050108799548355070\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"f5c86448b1192b2f78367c845b7189af\",\"spanId\":\"c13be7839baf19ce\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1957354242975200410\",\"endTimeUnixNano\":\"2050108799548355070\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_107(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "k0", value: "back\\slash" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 61, 28, 152, 93, 56, 209, 162, 93, 107, 120, 69, 194, 203, 83, 215, 15 }, span_id: [8]u8{ 150, 97, 134, 9, 133, 122, 195, 202 }, parent_span_id: [8]u8{ 21, 5, 43, 89, 84, 215, 248, 4 }, name: "caf\xc3\xa9", kind: 3u8, start_ns: 869693286413761330u64, end_ns: 839740367748984380u64, attributes: sat0[0usize..1usize], status_code: 2u8, status_message: "line\nbreak" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"3d1c985d38d1a25d6b7845c2cb53d70f\",\"spanId\":\"96618609857ac3ca\",\"parentSpanId\":\"15052b5954d7f804\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"869693286413761330\",\"endTimeUnixNano\":\"839740367748984380\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"3d1c985d38d1a25d6b7845c2cb53d70f\",\"spanId\":\"96618609857ac3ca\",\"parentSpanId\":\"15052b5954d7f804\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"869693286413761330\",\"endTimeUnixNano\":\"839740367748984380\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_108(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "http.method0", value: "200" }, x.Label{ name: "http.method1", value: "caf\xc3\xa9" }, x.Label{ name: "peer2", value: "x\ny" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 238, 254, 45, 93, 123, 99, 237, 115, 250, 168, 102, 156, 193, 205, 188, 9 }, span_id: [8]u8{ 107, 194, 216, 143, 164, 70, 203, 253 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 0u8, start_ns: 4563443558693766614u64, end_ns: 2651006205332996919u64, attributes: sat0[0usize..3usize], status_code: 0u8, status_message: "boom" }
    let sat1: [3]x.Label = [3]x.Label{ x.Label{ name: "http.method0", value: "" }, x.Label{ name: "k1", value: "/a\"b" }, x.Label{ name: "k2", value: "back\\slash" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 190, 247, 115, 194, 88, 69, 93, 197, 250, 205, 52, 74, 85, 216, 143, 173 }, span_id: [8]u8{ 227, 96, 9, 208, 20, 203, 160, 35 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 0u8, start_ns: 1402475683611491397u64, end_ns: 1107805600416435804u64, attributes: sat1[0usize..3usize], status_code: 2u8, status_message: "boom" }
    let sat2: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "back\\slash" }, x.Label{ name: "k1", value: "plain value" }, x.Label{ name: "peer2", value: "GET" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 228, 36, 106, 184, 2, 132, 196, 98, 204, 250, 75, 206, 221, 234, 239, 90 }, span_id: [8]u8{ 234, 106, 99, 61, 167, 169, 127, 239 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 3u8, start_ns: 797773096091183734u64, end_ns: 3971208659800317548u64, attributes: sat2[0usize..3usize], status_code: 2u8, status_message: "line\nbreak" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"eefe2d5d7b63ed73faa8669cc1cdbc09\",\"spanId\":\"6bc2d88fa446cbfd\",\"name\":\"x\",\"startTimeUnixNano\":\"4563443558693766614\",\"endTimeUnixNano\":\"2651006205332996919\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"boom\"}},{\"traceId\":\"bef773c258455dc5facd344a55d88fad\",\"spanId\":\"e36009d014cba023\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1402475683611491397\",\"endTimeUnixNano\":\"1107805600416435804\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"e4246ab80284c462ccfa4bceddeaef5a\",\"spanId\":\"ea6a633da7a97fef\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"797773096091183734\",\"endTimeUnixNano\":\"3971208659800317548\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"eefe2d5d7b63ed73faa8669cc1cdbc09\",\"spanId\":\"6bc2d88fa446cbfd\",\"name\":\"x\",\"startTimeUnixNano\":\"4563443558693766614\",\"endTimeUnixNano\":\"2651006205332996919\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"boom\"}},{\"traceId\":\"bef773c258455dc5facd344a55d88fad\",\"spanId\":\"e36009d014cba023\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1402475683611491397\",\"endTimeUnixNano\":\"1107805600416435804\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"e4246ab80284c462ccfa4bceddeaef5a\",\"spanId\":\"ea6a633da7a97fef\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"797773096091183734\",\"endTimeUnixNano\":\"3971208659800317548\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_109(a: *mem.Arena) -> bool {
    var spans: [2]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "http.method0", value: "" }, x.Label{ name: "http.method1", value: "back\\slash" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 226, 28, 8, 159, 63, 188, 17, 52, 92, 237, 162, 103, 64, 224, 164, 53 }, span_id: [8]u8{ 122, 175, 131, 59, 92, 114, 201, 132 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 1u8, start_ns: 1847885930190295814u64, end_ns: 4269774804436444900u64, attributes: sat0[0usize..2usize], status_code: 2u8, status_message: "boom" }
    let sat1: [3]x.Label = [3]x.Label{ x.Label{ name: "k0", value: "caf\xc3\xa9" }, x.Label{ name: "peer1", value: "plain value" }, x.Label{ name: "peer2", value: "/a\"b" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 81, 52, 95, 19, 108, 130, 59, 25, 120, 37, 186, 123, 211, 244, 169, 238 }, span_id: [8]u8{ 230, 199, 80, 197, 134, 2, 206, 184 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 1u8, start_ns: 4404289966534449962u64, end_ns: 1334011510526019522u64, attributes: sat1[0usize..3usize], status_code: 0u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..2usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"e21c089f3fbc11345ceda26740e0a435\",\"spanId\":\"7aaf833b5c72c984\",\"name\":\"caf\xc3\xa9\",\"kind\":1,\"startTimeUnixNano\":\"1847885930190295814\",\"endTimeUnixNano\":\"4269774804436444900\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"51345f136c823b197825ba7bd3f4a9ee\",\"spanId\":\"e6c750c58602ceb8\",\"name\":\"caf\xc3\xa9\",\"kind\":1,\"startTimeUnixNano\":\"4404289966534449962\",\"endTimeUnixNano\":\"1334011510526019522\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"e21c089f3fbc11345ceda26740e0a435\",\"spanId\":\"7aaf833b5c72c984\",\"name\":\"caf\xc3\xa9\",\"kind\":1,\"startTimeUnixNano\":\"1847885930190295814\",\"endTimeUnixNano\":\"4269774804436444900\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"51345f136c823b197825ba7bd3f4a9ee\",\"spanId\":\"e6c750c58602ceb8\",\"name\":\"caf\xc3\xa9\",\"kind\":1,\"startTimeUnixNano\":\"4404289966534449962\",\"endTimeUnixNano\":\"1334011510526019522\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]}]}]}]}")
        ret false
    }
    ret true
}

fn case_110(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "peer0", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 97, 119, 34, 38, 148, 137, 18, 202, 78, 230, 158, 80, 150, 73, 249, 245 }, span_id: [8]u8{ 187, 49, 12, 10, 150, 32, 241, 172 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "db \"query\"", kind: 2u8, start_ns: 2224144220936229016u64, end_ns: 1656162790060882716u64, attributes: sat0[0usize..1usize], status_code: 1u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"61772226948912ca4ee69e509649f9f5\",\"spanId\":\"bb310c0a9620f1ac\",\"name\":\"db \\\"query\\\"\",\"kind\":2,\"startTimeUnixNano\":\"2224144220936229016\",\"endTimeUnixNano\":\"1656162790060882716\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}}],\"status\":{\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"61772226948912ca4ee69e509649f9f5\",\"spanId\":\"bb310c0a9620f1ac\",\"name\":\"db \\\"query\\\"\",\"kind\":2,\"startTimeUnixNano\":\"2224144220936229016\",\"endTimeUnixNano\":\"1656162790060882716\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}}],\"status\":{\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_111(a: *mem.Arena) -> bool {
    var spans: [2]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 242, 205, 82, 118, 8, 21, 88, 193, 114, 67, 191, 10, 9, 61, 234, 67 }, span_id: [8]u8{ 33, 137, 189, 93, 69, 188, 206, 221 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 2u8, start_ns: 3811117304451846850u64, end_ns: 4543137651892876908u64, attributes: sat0[0usize..1usize], status_code: 0u8, status_message: "line\nbreak" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 154, 85, 148, 15, 159, 247, 204, 172, 56, 16, 224, 61, 204, 72, 9, 38 }, span_id: [8]u8{ 68, 110, 24, 105, 84, 66, 78, 155 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 0u8, start_ns: 245134925015570617u64, end_ns: 3557093924954589476u64, attributes: sat1[0usize..0usize], status_code: 2u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..2usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"f2cd5276081558c17243bf0a093dea43\",\"spanId\":\"2189bd5d45bccedd\",\"name\":\"x\",\"kind\":2,\"startTimeUnixNano\":\"3811117304451846850\",\"endTimeUnixNano\":\"4543137651892876908\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"9a55940f9ff7ccac3810e03dcc480926\",\"spanId\":\"446e186954424e9b\",\"name\":\"x\",\"startTimeUnixNano\":\"245134925015570617\",\"endTimeUnixNano\":\"3557093924954589476\",\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"f2cd5276081558c17243bf0a093dea43\",\"spanId\":\"2189bd5d45bccedd\",\"name\":\"x\",\"kind\":2,\"startTimeUnixNano\":\"3811117304451846850\",\"endTimeUnixNano\":\"4543137651892876908\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"9a55940f9ff7ccac3810e03dcc480926\",\"spanId\":\"446e186954424e9b\",\"name\":\"x\",\"startTimeUnixNano\":\"245134925015570617\",\"endTimeUnixNano\":\"3557093924954589476\",\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_112(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "/a\"b" }, x.Label{ name: "k1", value: "caf\xc3\xa9" }, x.Label{ name: "peer2", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 204, 206, 250, 136, 120, 122, 10, 92, 51, 182, 167, 228, 88, 153, 49, 145 }, span_id: [8]u8{ 183, 228, 48, 178, 145, 83, 35, 201 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 3u8, start_ns: 4324514330376157541u64, end_ns: 1275660316337836013u64, attributes: sat0[0usize..3usize], status_code: 1u8, status_message: "line\nbreak" }
    let sat1: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "x\ny" }, x.Label{ name: "k1", value: "x\ny" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 166, 255, 205, 125, 223, 30, 240, 64, 63, 114, 232, 114, 97, 217, 66, 209 }, span_id: [8]u8{ 124, 175, 252, 57, 115, 129, 225, 38 }, parent_span_id: [8]u8{ 178, 241, 29, 213, 152, 167, 124, 140 }, name: "x", kind: 3u8, start_ns: 1056041492679694679u64, end_ns: 262740881911150738u64, attributes: sat1[0usize..2usize], status_code: 1u8, status_message: "boom" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "x\ny" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 46, 189, 32, 222, 73, 68, 73, 84, 159, 217, 99, 185, 169, 109, 225, 245 }, span_id: [8]u8{ 46, 113, 0, 138, 120, 183, 142, 133 }, parent_span_id: [8]u8{ 56, 227, 40, 228, 83, 68, 213, 232 }, name: "x", kind: 3u8, start_ns: 2506322337874575524u64, end_ns: 2526862357972086710u64, attributes: sat2[0usize..1usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"cccefa88787a0a5c33b6a7e458993191\",\"spanId\":\"b7e430b2915323c9\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"4324514330376157541\",\"endTimeUnixNano\":\"1275660316337836013\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"a6ffcd7ddf1ef0403f72e87261d942d1\",\"spanId\":\"7caffc397381e126\",\"parentSpanId\":\"b2f11dd598a77c8c\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"1056041492679694679\",\"endTimeUnixNano\":\"262740881911150738\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"boom\",\"code\":1}},{\"traceId\":\"2ebd20de494449549fd963b9a96de1f5\",\"spanId\":\"2e71008a78b78e85\",\"parentSpanId\":\"38e328e45344d5e8\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"2506322337874575524\",\"endTimeUnixNano\":\"2526862357972086710\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"cccefa88787a0a5c33b6a7e458993191\",\"spanId\":\"b7e430b2915323c9\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"4324514330376157541\",\"endTimeUnixNano\":\"1275660316337836013\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"a6ffcd7ddf1ef0403f72e87261d942d1\",\"spanId\":\"7caffc397381e126\",\"parentSpanId\":\"b2f11dd598a77c8c\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"1056041492679694679\",\"endTimeUnixNano\":\"262740881911150738\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"boom\",\"code\":1}},{\"traceId\":\"2ebd20de494449549fd963b9a96de1f5\",\"spanId\":\"2e71008a78b78e85\",\"parentSpanId\":\"38e328e45344d5e8\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"2506322337874575524\",\"endTimeUnixNano\":\"2526862357972086710\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_113(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "GET" }, x.Label{ name: "k1", value: "GET" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 145, 249, 154, 140, 199, 120, 89, 188, 37, 111, 37, 153, 140, 167, 56, 17 }, span_id: [8]u8{ 140, 212, 62, 170, 156, 17, 113, 163 }, parent_span_id: [8]u8{ 253, 111, 110, 35, 169, 182, 208, 94 }, name: "x", kind: 4u8, start_ns: 4289327239925424595u64, end_ns: 1674935863076488583u64, attributes: sat0[0usize..2usize], status_code: 0u8, status_message: "boom" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 69, 7, 248, 240, 149, 55, 65, 217, 238, 101, 137, 232, 154, 82, 25, 83 }, span_id: [8]u8{ 159, 167, 180, 75, 159, 37, 176, 92 }, parent_span_id: [8]u8{ 0, 238, 18, 253, 48, 193, 46, 10 }, name: "GET /a", kind: 1u8, start_ns: 1820733037976561606u64, end_ns: 991131554474092732u64, attributes: sat1[0usize..0usize], status_code: 0u8, status_message: "boom" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 72, 217, 141, 109, 12, 141, 141, 115, 29, 150, 227, 99, 105, 7, 212, 48 }, span_id: [8]u8{ 32, 87, 38, 192, 2, 219, 223, 141 }, parent_span_id: [8]u8{ 194, 243, 11, 10, 81, 25, 160, 145 }, name: "GET /a", kind: 0u8, start_ns: 2272877807634109026u64, end_ns: 3111214282126115373u64, attributes: sat2[0usize..0usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"91f99a8cc77859bc256f25998ca73811\",\"spanId\":\"8cd43eaa9c1171a3\",\"parentSpanId\":\"fd6f6e23a9b6d05e\",\"name\":\"x\",\"kind\":4,\"startTimeUnixNano\":\"4289327239925424595\",\"endTimeUnixNano\":\"1674935863076488583\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"boom\"}},{\"traceId\":\"4507f8f0953741d9ee6589e89a521953\",\"spanId\":\"9fa7b44b9f25b05c\",\"parentSpanId\":\"00ee12fd30c12e0a\",\"name\":\"GET /a\",\"kind\":1,\"startTimeUnixNano\":\"1820733037976561606\",\"endTimeUnixNano\":\"991131554474092732\",\"status\":{\"message\":\"boom\"}},{\"traceId\":\"48d98d6d0c8d8d731d96e3636907d430\",\"spanId\":\"205726c002dbdf8d\",\"parentSpanId\":\"c2f30b0a5119a091\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"2272877807634109026\",\"endTimeUnixNano\":\"3111214282126115373\",\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"91f99a8cc77859bc256f25998ca73811\",\"spanId\":\"8cd43eaa9c1171a3\",\"parentSpanId\":\"fd6f6e23a9b6d05e\",\"name\":\"x\",\"kind\":4,\"startTimeUnixNano\":\"4289327239925424595\",\"endTimeUnixNano\":\"1674935863076488583\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"boom\"}},{\"traceId\":\"4507f8f0953741d9ee6589e89a521953\",\"spanId\":\"9fa7b44b9f25b05c\",\"parentSpanId\":\"00ee12fd30c12e0a\",\"name\":\"GET /a\",\"kind\":1,\"startTimeUnixNano\":\"1820733037976561606\",\"endTimeUnixNano\":\"991131554474092732\",\"status\":{\"message\":\"boom\"}},{\"traceId\":\"48d98d6d0c8d8d731d96e3636907d430\",\"spanId\":\"205726c002dbdf8d\",\"parentSpanId\":\"c2f30b0a5119a091\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"2272877807634109026\",\"endTimeUnixNano\":\"3111214282126115373\",\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_114(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 62, 133, 18, 4, 119, 155, 209, 43, 50, 192, 83, 243, 153, 204, 232, 23 }, span_id: [8]u8{ 237, 76, 120, 80, 200, 49, 111, 6 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 0u8, start_ns: 3501628256748528187u64, end_ns: 2042372079252760385u64, attributes: sat0[0usize..0usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"3e851204779bd12b32c053f399cce817\",\"spanId\":\"ed4c7850c8316f06\",\"name\":\"caf\xc3\xa9\",\"startTimeUnixNano\":\"3501628256748528187\",\"endTimeUnixNano\":\"2042372079252760385\",\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"3e851204779bd12b32c053f399cce817\",\"spanId\":\"ed4c7850c8316f06\",\"name\":\"caf\xc3\xa9\",\"startTimeUnixNano\":\"3501628256748528187\",\"endTimeUnixNano\":\"2042372079252760385\",\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_115(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 165, 236, 91, 16, 241, 203, 18, 133, 25, 155, 117, 213, 38, 132, 131, 33 }, span_id: [8]u8{ 250, 217, 139, 88, 77, 190, 50, 139 }, parent_span_id: [8]u8{ 181, 133, 3, 6, 165, 108, 53, 159 }, name: "caf\xc3\xa9", kind: 0u8, start_ns: 2930463010699208312u64, end_ns: 1661697585706601324u64, attributes: sat0[0usize..0usize], status_code: 1u8, status_message: "" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "peer0", value: "GET" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 89, 220, 14, 240, 28, 249, 230, 88, 208, 159, 22, 206, 211, 32, 115, 58 }, span_id: [8]u8{ 51, 4, 242, 120, 86, 21, 90, 46 }, parent_span_id: [8]u8{ 104, 61, 165, 252, 69, 206, 111, 12 }, name: "caf\xc3\xa9", kind: 4u8, start_ns: 693090911081845215u64, end_ns: 2217786018084759019u64, attributes: sat1[0usize..1usize], status_code: 1u8, status_message: "line\nbreak" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "back\\slash" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 8, 91, 51, 108, 17, 107, 218, 91, 99, 83, 15, 176, 2, 120, 18, 192 }, span_id: [8]u8{ 7, 228, 141, 89, 111, 222, 223, 200 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 3u8, start_ns: 3171322747389908819u64, end_ns: 3109760240261730905u64, attributes: sat2[0usize..1usize], status_code: 1u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"a5ec5b10f1cb1285199b75d526848321\",\"spanId\":\"fad98b584dbe328b\",\"parentSpanId\":\"b5850306a56c359f\",\"name\":\"caf\xc3\xa9\",\"startTimeUnixNano\":\"2930463010699208312\",\"endTimeUnixNano\":\"1661697585706601324\",\"status\":{\"code\":1}},{\"traceId\":\"59dc0ef01cf9e658d09f16ced320733a\",\"spanId\":\"3304f27856155a2e\",\"parentSpanId\":\"683da5fc45ce6f0c\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"693090911081845215\",\"endTimeUnixNano\":\"2217786018084759019\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"085b336c116bda5b63530fb0027812c0\",\"spanId\":\"07e48d596fdedfc8\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"3171322747389908819\",\"endTimeUnixNano\":\"3109760240261730905\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"a5ec5b10f1cb1285199b75d526848321\",\"spanId\":\"fad98b584dbe328b\",\"parentSpanId\":\"b5850306a56c359f\",\"name\":\"caf\xc3\xa9\",\"startTimeUnixNano\":\"2930463010699208312\",\"endTimeUnixNano\":\"1661697585706601324\",\"status\":{\"code\":1}},{\"traceId\":\"59dc0ef01cf9e658d09f16ced320733a\",\"spanId\":\"3304f27856155a2e\",\"parentSpanId\":\"683da5fc45ce6f0c\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"693090911081845215\",\"endTimeUnixNano\":\"2217786018084759019\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"085b336c116bda5b63530fb0027812c0\",\"spanId\":\"07e48d596fdedfc8\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"3171322747389908819\",\"endTimeUnixNano\":\"3109760240261730905\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_116(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "GET" }, x.Label{ name: "peer1", value: "x\ny" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 169, 70, 54, 161, 229, 114, 1, 194, 255, 150, 23, 139, 101, 128, 68, 201 }, span_id: [8]u8{ 48, 194, 51, 1, 182, 166, 15, 18 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 3u8, start_ns: 2711869209913731494u64, end_ns: 402770622380316076u64, attributes: sat0[0usize..2usize], status_code: 1u8, status_message: "" }
    let sat1: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "" }, x.Label{ name: "k1", value: "caf\xc3\xa9" }, x.Label{ name: "k2", value: "back\\slash" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 166, 146, 18, 199, 105, 58, 50, 55, 138, 249, 98, 40, 25, 161, 103, 5 }, span_id: [8]u8{ 31, 90, 50, 138, 153, 3, 108, 208 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 5u8, start_ns: 958150769068375497u64, end_ns: 3283128034790297126u64, attributes: sat1[0usize..3usize], status_code: 0u8, status_message: "line\nbreak" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "peer0", value: "GET" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 249, 111, 0, 89, 181, 175, 193, 56, 133, 134, 105, 217, 151, 171, 224, 167 }, span_id: [8]u8{ 9, 250, 167, 176, 57, 65, 75, 159 }, parent_span_id: [8]u8{ 232, 243, 11, 212, 92, 21, 248, 101 }, name: "db \"query\"", kind: 1u8, start_ns: 2437057754152541274u64, end_ns: 184020250878486973u64, attributes: sat2[0usize..1usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"a94636a1e57201c2ff96178b658044c9\",\"spanId\":\"30c23301b6a60f12\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"2711869209913731494\",\"endTimeUnixNano\":\"402770622380316076\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"code\":1}},{\"traceId\":\"a69212c7693a32378af9622819a16705\",\"spanId\":\"1f5a328a99036cd0\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"958150769068375497\",\"endTimeUnixNano\":\"3283128034790297126\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"f96f0059b5afc138858669d997abe0a7\",\"spanId\":\"09faa7b039414b9f\",\"parentSpanId\":\"e8f30bd45c15f865\",\"name\":\"db \\\"query\\\"\",\"kind\":1,\"startTimeUnixNano\":\"2437057754152541274\",\"endTimeUnixNano\":\"184020250878486973\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"a94636a1e57201c2ff96178b658044c9\",\"spanId\":\"30c23301b6a60f12\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"2711869209913731494\",\"endTimeUnixNano\":\"402770622380316076\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"code\":1}},{\"traceId\":\"a69212c7693a32378af9622819a16705\",\"spanId\":\"1f5a328a99036cd0\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"958150769068375497\",\"endTimeUnixNano\":\"3283128034790297126\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"f96f0059b5afc138858669d997abe0a7\",\"spanId\":\"09faa7b039414b9f\",\"parentSpanId\":\"e8f30bd45c15f865\",\"name\":\"db \\\"query\\\"\",\"kind\":1,\"startTimeUnixNano\":\"2437057754152541274\",\"endTimeUnixNano\":\"184020250878486973\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_117(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 82, 233, 54, 155, 101, 84, 236, 200, 231, 2, 200, 195, 116, 64, 133, 4 }, span_id: [8]u8{ 22, 61, 177, 233, 75, 37, 168, 33 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 5u8, start_ns: 265481808267327515u64, end_ns: 1966384624970545094u64, attributes: sat0[0usize..0usize], status_code: 0u8, status_message: "line\nbreak" }
    let sat1: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "caf\xc3\xa9" }, x.Label{ name: "k1", value: "x\ny" }, x.Label{ name: "peer2", value: "x\ny" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 16, 1, 70, 116, 95, 79, 68, 138, 224, 112, 123, 250, 109, 247, 93, 100 }, span_id: [8]u8{ 36, 16, 133, 235, 100, 5, 245, 191 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 2u8, start_ns: 2659266285646496444u64, end_ns: 583580072658717636u64, attributes: sat1[0usize..3usize], status_code: 0u8, status_message: "line\nbreak" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 178, 85, 201, 209, 103, 131, 220, 25, 150, 245, 109, 9, 131, 114, 129, 218 }, span_id: [8]u8{ 78, 166, 19, 162, 221, 201, 228, 29 }, parent_span_id: [8]u8{ 253, 59, 38, 101, 21, 54, 229, 126 }, name: "GET /a", kind: 0u8, start_ns: 1101793500584311540u64, end_ns: 791917968675897857u64, attributes: sat2[0usize..0usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"52e9369b6554ecc8e702c8c374408504\",\"spanId\":\"163db1e94b25a821\",\"name\":\"x\",\"kind\":5,\"startTimeUnixNano\":\"265481808267327515\",\"endTimeUnixNano\":\"1966384624970545094\",\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"100146745f4f448ae0707bfa6df75d64\",\"spanId\":\"241085eb6405f5bf\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"2659266285646496444\",\"endTimeUnixNano\":\"583580072658717636\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"b255c9d16783dc1996f56d09837281da\",\"spanId\":\"4ea613a2ddc9e41d\",\"parentSpanId\":\"fd3b26651536e57e\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1101793500584311540\",\"endTimeUnixNano\":\"791917968675897857\",\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"52e9369b6554ecc8e702c8c374408504\",\"spanId\":\"163db1e94b25a821\",\"name\":\"x\",\"kind\":5,\"startTimeUnixNano\":\"265481808267327515\",\"endTimeUnixNano\":\"1966384624970545094\",\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"100146745f4f448ae0707bfa6df75d64\",\"spanId\":\"241085eb6405f5bf\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"2659266285646496444\",\"endTimeUnixNano\":\"583580072658717636\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"b255c9d16783dc1996f56d09837281da\",\"spanId\":\"4ea613a2ddc9e41d\",\"parentSpanId\":\"fd3b26651536e57e\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1101793500584311540\",\"endTimeUnixNano\":\"791917968675897857\",\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_118(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 145, 245, 11, 163, 204, 76, 5, 44, 2, 95, 9, 99, 205, 19, 101, 84 }, span_id: [8]u8{ 114, 4, 247, 239, 20, 139, 95, 194 }, parent_span_id: [8]u8{ 122, 95, 216, 227, 163, 143, 180, 160 }, name: "GET /a", kind: 5u8, start_ns: 4144619012096026948u64, end_ns: 1436709711989049023u64, attributes: sat0[0usize..0usize], status_code: 2u8, status_message: "boom" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 219, 212, 142, 233, 34, 114, 196, 129, 137, 92, 134, 49, 140, 18, 112, 104 }, span_id: [8]u8{ 164, 82, 228, 64, 104, 39, 219, 137 }, parent_span_id: [8]u8{ 29, 2, 119, 246, 133, 224, 45, 119 }, name: "GET /a", kind: 5u8, start_ns: 1307025465847179963u64, end_ns: 4017236916940266387u64, attributes: sat1[0usize..0usize], status_code: 0u8, status_message: "" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 169, 148, 210, 32, 127, 122, 28, 161, 160, 199, 62, 204, 45, 145, 17, 240 }, span_id: [8]u8{ 97, 247, 210, 206, 101, 26, 22, 167 }, parent_span_id: [8]u8{ 165, 112, 203, 6, 211, 125, 190, 49 }, name: "caf\xc3\xa9", kind: 2u8, start_ns: 3346833228573260497u64, end_ns: 296317433993598006u64, attributes: sat2[0usize..0usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"91f50ba3cc4c052c025f0963cd136554\",\"spanId\":\"7204f7ef148b5fc2\",\"parentSpanId\":\"7a5fd8e3a38fb4a0\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"4144619012096026948\",\"endTimeUnixNano\":\"1436709711989049023\",\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"dbd48ee92272c481895c86318c127068\",\"spanId\":\"a452e4406827db89\",\"parentSpanId\":\"1d0277f685e02d77\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"1307025465847179963\",\"endTimeUnixNano\":\"4017236916940266387\"},{\"traceId\":\"a994d2207f7a1ca1a0c73ecc2d9111f0\",\"spanId\":\"61f7d2ce651a16a7\",\"parentSpanId\":\"a570cb06d37dbe31\",\"name\":\"caf\xc3\xa9\",\"kind\":2,\"startTimeUnixNano\":\"3346833228573260497\",\"endTimeUnixNano\":\"296317433993598006\",\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"91f50ba3cc4c052c025f0963cd136554\",\"spanId\":\"7204f7ef148b5fc2\",\"parentSpanId\":\"7a5fd8e3a38fb4a0\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"4144619012096026948\",\"endTimeUnixNano\":\"1436709711989049023\",\"status\":{\"message\":\"boom\",\"code\":2}},{\"traceId\":\"dbd48ee92272c481895c86318c127068\",\"spanId\":\"a452e4406827db89\",\"parentSpanId\":\"1d0277f685e02d77\",\"name\":\"GET /a\",\"kind\":5,\"startTimeUnixNano\":\"1307025465847179963\",\"endTimeUnixNano\":\"4017236916940266387\"},{\"traceId\":\"a994d2207f7a1ca1a0c73ecc2d9111f0\",\"spanId\":\"61f7d2ce651a16a7\",\"parentSpanId\":\"a570cb06d37dbe31\",\"name\":\"caf\xc3\xa9\",\"kind\":2,\"startTimeUnixNano\":\"3346833228573260497\",\"endTimeUnixNano\":\"296317433993598006\",\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_119(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 214, 94, 220, 26, 23, 112, 119, 16, 94, 153, 125, 232, 239, 60, 224, 128 }, span_id: [8]u8{ 84, 49, 76, 220, 185, 62, 180, 86 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 1u8, start_ns: 3766890448072531677u64, end_ns: 1203283798159240527u64, attributes: sat0[0usize..0usize], status_code: 0u8, status_message: "" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 115, 63, 64, 220, 202, 110, 170, 124, 146, 220, 111, 200, 241, 87, 205, 125 }, span_id: [8]u8{ 185, 241, 159, 247, 95, 149, 124, 164 }, parent_span_id: [8]u8{ 66, 218, 229, 14, 221, 32, 188, 122 }, name: "caf\xc3\xa9", kind: 3u8, start_ns: 2473451526162941002u64, end_ns: 1524350311969746105u64, attributes: sat1[0usize..0usize], status_code: 0u8, status_message: "boom" }
    let sat2: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "plain value" }, x.Label{ name: "peer1", value: "x\ny" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 251, 109, 168, 197, 54, 33, 138, 121, 110, 76, 147, 165, 18, 204, 50, 134 }, span_id: [8]u8{ 158, 136, 136, 176, 154, 191, 211, 19 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 2u8, start_ns: 861588271955004279u64, end_ns: 703950221345041064u64, attributes: sat2[0usize..2usize], status_code: 2u8, status_message: "line\nbreak" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"d65edc1a177077105e997de8ef3ce080\",\"spanId\":\"54314cdcb93eb456\",\"name\":\"x\",\"kind\":1,\"startTimeUnixNano\":\"3766890448072531677\",\"endTimeUnixNano\":\"1203283798159240527\"},{\"traceId\":\"733f40dcca6eaa7c92dc6fc8f157cd7d\",\"spanId\":\"b9f19ff75f957ca4\",\"parentSpanId\":\"42dae50edd20bc7a\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"2473451526162941002\",\"endTimeUnixNano\":\"1524350311969746105\",\"status\":{\"message\":\"boom\"}},{\"traceId\":\"fb6da8c536218a796e4c93a512cc3286\",\"spanId\":\"9e8888b09abfd313\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"861588271955004279\",\"endTimeUnixNano\":\"703950221345041064\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"d65edc1a177077105e997de8ef3ce080\",\"spanId\":\"54314cdcb93eb456\",\"name\":\"x\",\"kind\":1,\"startTimeUnixNano\":\"3766890448072531677\",\"endTimeUnixNano\":\"1203283798159240527\"},{\"traceId\":\"733f40dcca6eaa7c92dc6fc8f157cd7d\",\"spanId\":\"b9f19ff75f957ca4\",\"parentSpanId\":\"42dae50edd20bc7a\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"2473451526162941002\",\"endTimeUnixNano\":\"1524350311969746105\",\"status\":{\"message\":\"boom\"}},{\"traceId\":\"fb6da8c536218a796e4c93a512cc3286\",\"spanId\":\"9e8888b09abfd313\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"861588271955004279\",\"endTimeUnixNano\":\"703950221345041064\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_120(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "peer0", value: "plain value" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 152, 242, 166, 124, 185, 114, 127, 61, 112, 105, 174, 135, 77, 203, 47, 24 }, span_id: [8]u8{ 82, 196, 41, 192, 214, 48, 72, 193 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "db \"query\"", kind: 2u8, start_ns: 488057328492916319u64, end_ns: 1369017243621461995u64, attributes: sat0[0usize..1usize], status_code: 1u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"98f2a67cb9727f3d7069ae874dcb2f18\",\"spanId\":\"52c429c0d63048c1\",\"name\":\"db \\\"query\\\"\",\"kind\":2,\"startTimeUnixNano\":\"488057328492916319\",\"endTimeUnixNano\":\"1369017243621461995\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"98f2a67cb9727f3d7069ae874dcb2f18\",\"spanId\":\"52c429c0d63048c1\",\"name\":\"db \\\"query\\\"\",\"kind\":2,\"startTimeUnixNano\":\"488057328492916319\",\"endTimeUnixNano\":\"1369017243621461995\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_121(a: *mem.Arena) -> bool {
    var spans: [2]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "k0", value: "plain value" }, x.Label{ name: "k1", value: "back\\slash" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 28, 108, 18, 203, 20, 86, 23, 166, 161, 123, 200, 111, 122, 28, 188, 47 }, span_id: [8]u8{ 101, 131, 73, 142, 151, 243, 150, 155 }, parent_span_id: [8]u8{ 167, 182, 70, 48, 156, 1, 226, 255 }, name: "db \"query\"", kind: 3u8, start_ns: 3562111173006670858u64, end_ns: 1340310548009037460u64, attributes: sat0[0usize..2usize], status_code: 1u8, status_message: "" }
    let sat1: [2]x.Label = [2]x.Label{ x.Label{ name: "peer0", value: "caf\xc3\xa9" }, x.Label{ name: "peer1", value: "caf\xc3\xa9" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 131, 213, 89, 121, 181, 54, 250, 140, 73, 177, 42, 138, 117, 92, 139, 211 }, span_id: [8]u8{ 102, 160, 249, 82, 58, 107, 128, 127 }, parent_span_id: [8]u8{ 142, 84, 129, 19, 6, 60, 219, 199 }, name: "GET /a", kind: 0u8, start_ns: 2651106705888573332u64, end_ns: 571087096620657101u64, attributes: sat1[0usize..2usize], status_code: 1u8, status_message: "line\nbreak" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..2usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"1c6c12cb145617a6a17bc86f7a1cbc2f\",\"spanId\":\"6583498e97f3969b\",\"parentSpanId\":\"a7b646309c01e2ff\",\"name\":\"db \\\"query\\\"\",\"kind\":3,\"startTimeUnixNano\":\"3562111173006670858\",\"endTimeUnixNano\":\"1340310548009037460\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"code\":1}},{\"traceId\":\"83d55979b536fa8c49b12a8a755c8bd3\",\"spanId\":\"66a0f9523a6b807f\",\"parentSpanId\":\"8e548113063cdbc7\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"2651106705888573332\",\"endTimeUnixNano\":\"571087096620657101\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"1c6c12cb145617a6a17bc86f7a1cbc2f\",\"spanId\":\"6583498e97f3969b\",\"parentSpanId\":\"a7b646309c01e2ff\",\"name\":\"db \\\"query\\\"\",\"kind\":3,\"startTimeUnixNano\":\"3562111173006670858\",\"endTimeUnixNano\":\"1340310548009037460\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"back\\\\slash\"}}],\"status\":{\"code\":1}},{\"traceId\":\"83d55979b536fa8c49b12a8a755c8bd3\",\"spanId\":\"66a0f9523a6b807f\",\"parentSpanId\":\"8e548113063cdbc7\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"2651106705888573332\",\"endTimeUnixNano\":\"571087096620657101\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_122(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "k0", value: "x\ny" }, x.Label{ name: "peer1", value: "" }, x.Label{ name: "peer2", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 225, 241, 127, 228, 216, 34, 230, 152, 56, 173, 83, 165, 68, 200, 38, 43 }, span_id: [8]u8{ 151, 210, 141, 0, 90, 137, 209, 65 }, parent_span_id: [8]u8{ 40, 211, 51, 71, 143, 56, 233, 102 }, name: "db \"query\"", kind: 3u8, start_ns: 179632319668232391u64, end_ns: 792572726373140729u64, attributes: sat0[0usize..3usize], status_code: 2u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"e1f17fe4d822e69838ad53a544c8262b\",\"spanId\":\"97d28d005a89d141\",\"parentSpanId\":\"28d333478f38e966\",\"name\":\"db \\\"query\\\"\",\"kind\":3,\"startTimeUnixNano\":\"179632319668232391\",\"endTimeUnixNano\":\"792572726373140729\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"e1f17fe4d822e69838ad53a544c8262b\",\"spanId\":\"97d28d005a89d141\",\"parentSpanId\":\"28d333478f38e966\",\"name\":\"db \\\"query\\\"\",\"kind\":3,\"startTimeUnixNano\":\"179632319668232391\",\"endTimeUnixNano\":\"792572726373140729\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_123(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "k0", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 78, 128, 46, 216, 151, 37, 53, 107, 236, 38, 163, 190, 11, 241, 187, 46 }, span_id: [8]u8{ 202, 2, 152, 133, 210, 212, 24, 202 }, parent_span_id: [8]u8{ 1, 4, 148, 65, 150, 197, 33, 160 }, name: "GET /a", kind: 2u8, start_ns: 2599106354653751379u64, end_ns: 4011564301811617358u64, attributes: sat0[0usize..1usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"4e802ed89725356bec26a3be0bf1bb2e\",\"spanId\":\"ca029885d2d418ca\",\"parentSpanId\":\"0104944196c521a0\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"2599106354653751379\",\"endTimeUnixNano\":\"4011564301811617358\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"spans\":[{\"traceId\":\"4e802ed89725356bec26a3be0bf1bb2e\",\"spanId\":\"ca029885d2d418ca\",\"parentSpanId\":\"0104944196c521a0\",\"name\":\"GET /a\",\"kind\":2,\"startTimeUnixNano\":\"2599106354653751379\",\"endTimeUnixNano\":\"4011564301811617358\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_124(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "http.method0", value: "200" }, x.Label{ name: "peer1", value: "200" }, x.Label{ name: "k2", value: "200" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 45, 95, 187, 158, 55, 88, 3, 72, 192, 121, 39, 47, 255, 8, 2, 26 }, span_id: [8]u8{ 226, 173, 42, 79, 29, 184, 119, 151 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 5u8, start_ns: 3764845057656348591u64, end_ns: 1818095309237168818u64, attributes: sat0[0usize..3usize], status_code: 2u8, status_message: "line\nbreak" }
    let sat1: [2]x.Label = [2]x.Label{ x.Label{ name: "peer0", value: "back\\slash" }, x.Label{ name: "peer1", value: "x\ny" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 23, 89, 230, 186, 169, 153, 112, 103, 120, 238, 138, 241, 212, 116, 161, 107 }, span_id: [8]u8{ 92, 242, 112, 85, 198, 236, 86, 64 }, parent_span_id: [8]u8{ 44, 205, 221, 126, 62, 59, 10, 161 }, name: "caf\xc3\xa9", kind: 2u8, start_ns: 1559069172929907136u64, end_ns: 2820364098216122221u64, attributes: sat1[0usize..2usize], status_code: 1u8, status_message: "line\nbreak" }
    let sat2: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "plain value" }, x.Label{ name: "k1", value: "plain value" }, x.Label{ name: "peer2", value: "GET" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 97, 166, 226, 124, 41, 195, 2, 124, 50, 177, 71, 108, 208, 100, 75, 220 }, span_id: [8]u8{ 180, 15, 245, 164, 140, 102, 46, 70 }, parent_span_id: [8]u8{ 149, 170, 58, 111, 136, 35, 197, 77 }, name: "db \"query\"", kind: 5u8, start_ns: 1515203977864576680u64, end_ns: 2144265043720775423u64, attributes: sat2[0usize..3usize], status_code: 1u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"2d5fbb9e37580348c079272fff08021a\",\"spanId\":\"e2ad2a4f1db87797\",\"name\":\"caf\xc3\xa9\",\"kind\":5,\"startTimeUnixNano\":\"3764845057656348591\",\"endTimeUnixNano\":\"1818095309237168818\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"200\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}},{\"traceId\":\"1759e6baa999706778ee8af1d474a16b\",\"spanId\":\"5cf27055c6ec5640\",\"parentSpanId\":\"2ccddd7e3e3b0aa1\",\"name\":\"caf\xc3\xa9\",\"kind\":2,\"startTimeUnixNano\":\"1559069172929907136\",\"endTimeUnixNano\":\"2820364098216122221\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"61a6e27c29c3027c32b1476cd0644bdc\",\"spanId\":\"b40ff5a48c662e46\",\"parentSpanId\":\"95aa3a6f8823c54d\",\"name\":\"db \\\"query\\\"\",\"kind\":5,\"startTimeUnixNano\":\"1515203977864576680\",\"endTimeUnixNano\":\"2144265043720775423\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"2d5fbb9e37580348c079272fff08021a\",\"spanId\":\"e2ad2a4f1db87797\",\"name\":\"caf\xc3\xa9\",\"kind\":5,\"startTimeUnixNano\":\"3764845057656348591\",\"endTimeUnixNano\":\"1818095309237168818\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"200\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":2}},{\"traceId\":\"1759e6baa999706778ee8af1d474a16b\",\"spanId\":\"5cf27055c6ec5640\",\"parentSpanId\":\"2ccddd7e3e3b0aa1\",\"name\":\"caf\xc3\xa9\",\"kind\":2,\"startTimeUnixNano\":\"1559069172929907136\",\"endTimeUnixNano\":\"2820364098216122221\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"back\\\\slash\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"x\\ny\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"61a6e27c29c3027c32b1476cd0644bdc\",\"spanId\":\"b40ff5a48c662e46\",\"parentSpanId\":\"95aa3a6f8823c54d\",\"name\":\"db \\\"query\\\"\",\"kind\":5,\"startTimeUnixNano\":\"1515203977864576680\",\"endTimeUnixNano\":\"2144265043720775423\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"GET\"}}],\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_125(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 158, 140, 114, 184, 250, 11, 193, 175, 123, 180, 66, 72, 191, 138, 184, 205 }, span_id: [8]u8{ 249, 229, 61, 143, 168, 218, 108, 130 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 3u8, start_ns: 2284116017905501293u64, end_ns: 3660846741687089878u64, attributes: sat0[0usize..1usize], status_code: 2u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"9e8c72b8fa0bc1af7bb44248bf8ab8cd\",\"spanId\":\"f9e53d8fa8da6c82\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"2284116017905501293\",\"endTimeUnixNano\":\"3660846741687089878\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"9e8c72b8fa0bc1af7bb44248bf8ab8cd\",\"spanId\":\"f9e53d8fa8da6c82\",\"name\":\"caf\xc3\xa9\",\"kind\":3,\"startTimeUnixNano\":\"2284116017905501293\",\"endTimeUnixNano\":\"3660846741687089878\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_126(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [2]x.Label = [2]x.Label{ x.Label{ name: "http.method0", value: "200" }, x.Label{ name: "peer1", value: "caf\xc3\xa9" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 208, 128, 244, 79, 196, 227, 140, 100, 39, 178, 147, 113, 251, 186, 100, 28 }, span_id: [8]u8{ 54, 95, 72, 111, 75, 123, 115, 89 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 5u8, start_ns: 3106534140421707046u64, end_ns: 3454667283438790530u64, attributes: sat0[0usize..2usize], status_code: 2u8, status_message: "" }
    let sat1: [2]x.Label = [2]x.Label{ x.Label{ name: "peer0", value: "" }, x.Label{ name: "peer1", value: "/a\"b" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 13, 116, 15, 103, 79, 244, 185, 148, 0, 24, 70, 76, 51, 168, 118, 35 }, span_id: [8]u8{ 239, 155, 34, 85, 87, 42, 98, 212 }, parent_span_id: [8]u8{ 245, 81, 16, 238, 15, 205, 221, 250 }, name: "GET /a", kind: 4u8, start_ns: 3649820922141897341u64, end_ns: 2009726478177834377u64, attributes: sat1[0usize..2usize], status_code: 1u8, status_message: "" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "http.method0", value: "plain value" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 186, 210, 195, 24, 208, 129, 10, 171, 181, 248, 242, 247, 3, 174, 250, 67 }, span_id: [8]u8{ 149, 173, 61, 165, 94, 223, 208, 247 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 1u8, start_ns: 3497418811922179105u64, end_ns: 3681806643365953425u64, attributes: sat2[0usize..1usize], status_code: 1u8, status_message: "line\nbreak" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"d080f44fc4e38c6427b29371fbba641c\",\"spanId\":\"365f486f4b7b7359\",\"name\":\"x\",\"kind\":5,\"startTimeUnixNano\":\"3106534140421707046\",\"endTimeUnixNano\":\"3454667283438790530\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}],\"status\":{\"code\":2}},{\"traceId\":\"0d740f674ff4b9940018464c33a87623\",\"spanId\":\"ef9b2255572a62d4\",\"parentSpanId\":\"f55110ee0fcdddfa\",\"name\":\"GET /a\",\"kind\":4,\"startTimeUnixNano\":\"3649820922141897341\",\"endTimeUnixNano\":\"2009726478177834377\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":1}},{\"traceId\":\"bad2c318d0810aabb5f8f2f703aefa43\",\"spanId\":\"95ad3da55edfd0f7\",\"name\":\"GET /a\",\"kind\":1,\"startTimeUnixNano\":\"3497418811922179105\",\"endTimeUnixNano\":\"3681806643365953425\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"d080f44fc4e38c6427b29371fbba641c\",\"spanId\":\"365f486f4b7b7359\",\"name\":\"x\",\"kind\":5,\"startTimeUnixNano\":\"3106534140421707046\",\"endTimeUnixNano\":\"3454667283438790530\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"200\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"caf\xc3\xa9\"}}],\"status\":{\"code\":2}},{\"traceId\":\"0d740f674ff4b9940018464c33a87623\",\"spanId\":\"ef9b2255572a62d4\",\"parentSpanId\":\"f55110ee0fcdddfa\",\"name\":\"GET /a\",\"kind\":4,\"startTimeUnixNano\":\"3649820922141897341\",\"endTimeUnixNano\":\"2009726478177834377\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"code\":1}},{\"traceId\":\"bad2c318d0810aabb5f8f2f703aefa43\",\"spanId\":\"95ad3da55edfd0f7\",\"name\":\"GET /a\",\"kind\":1,\"startTimeUnixNano\":\"3497418811922179105\",\"endTimeUnixNano\":\"3681806643365953425\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn case_127(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [1]x.Label = [1]x.Label{ x.Label{ name: "peer0", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 86, 27, 110, 115, 166, 87, 114, 242, 90, 21, 121, 94, 219, 158, 87, 151 }, span_id: [8]u8{ 87, 183, 29, 58, 246, 133, 101, 205 }, parent_span_id: [8]u8{ 150, 255, 148, 253, 24, 175, 195, 114 }, name: "x", kind: 4u8, start_ns: 2974172388755806004u64, end_ns: 4077995499165331080u64, attributes: sat0[0usize..1usize], status_code: 1u8, status_message: "line\nbreak" }
    let sat1: [3]x.Label = [3]x.Label{ x.Label{ name: "http.method0", value: "x\ny" }, x.Label{ name: "peer1", value: "" }, x.Label{ name: "peer2", value: "plain value" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 164, 173, 81, 73, 254, 167, 18, 223, 54, 81, 80, 146, 21, 249, 206, 233 }, span_id: [8]u8{ 206, 90, 129, 111, 182, 186, 87, 115 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 0u8, start_ns: 1898931870088063726u64, end_ns: 2144577079277530593u64, attributes: sat1[0usize..3usize], status_code: 1u8, status_message: "" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 93, 76, 76, 57, 7, 49, 37, 180, 9, 232, 17, 65, 25, 24, 36, 147 }, span_id: [8]u8{ 232, 48, 39, 181, 99, 125, 60, 85 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "GET /a", kind: 4u8, start_ns: 3372912654132118486u64, end_ns: 2775359693553976674u64, attributes: sat2[0usize..0usize], status_code: 2u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..0usize], "tracer", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"561b6e73a65772f25a15795edb9e5797\",\"spanId\":\"57b71d3af68565cd\",\"parentSpanId\":\"96ff94fd18afc372\",\"name\":\"x\",\"kind\":4,\"startTimeUnixNano\":\"2974172388755806004\",\"endTimeUnixNano\":\"4077995499165331080\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"a4ad5149fea712df3651509215f9cee9\",\"spanId\":\"ce5a816fb6ba5773\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1898931870088063726\",\"endTimeUnixNano\":\"2144577079277530593\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"code\":1}},{\"traceId\":\"5d4c4c39073125b409e8114119182493\",\"spanId\":\"e83027b5637d3c55\",\"name\":\"GET /a\",\"kind\":4,\"startTimeUnixNano\":\"3372912654132118486\",\"endTimeUnixNano\":\"2775359693553976674\",\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"561b6e73a65772f25a15795edb9e5797\",\"spanId\":\"57b71d3af68565cd\",\"parentSpanId\":\"96ff94fd18afc372\",\"name\":\"x\",\"kind\":4,\"startTimeUnixNano\":\"2974172388755806004\",\"endTimeUnixNano\":\"4077995499165331080\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"/a\\\"b\"}}],\"status\":{\"message\":\"line\\nbreak\",\"code\":1}},{\"traceId\":\"a4ad5149fea712df3651509215f9cee9\",\"spanId\":\"ce5a816fb6ba5773\",\"name\":\"GET /a\",\"startTimeUnixNano\":\"1898931870088063726\",\"endTimeUnixNano\":\"2144577079277530593\",\"attributes\":[{\"key\":\"http.method0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"plain value\"}}],\"status\":{\"code\":1}},{\"traceId\":\"5d4c4c39073125b409e8114119182493\",\"spanId\":\"e83027b5637d3c55\",\"name\":\"GET /a\",\"kind\":4,\"startTimeUnixNano\":\"3372912654132118486\",\"endTimeUnixNano\":\"2775359693553976674\",\"status\":{\"message\":\"boom\",\"code\":2}}]}]}]}")
        ret false
    }
    ret true
}

fn case_128(a: *mem.Arena) -> bool {
    var spans: [1]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "k0", value: "x\ny" }, x.Label{ name: "http.method1", value: "/a\"b" }, x.Label{ name: "peer2", value: "200" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 69, 3, 49, 159, 83, 221, 192, 226, 204, 207, 133, 211, 93, 167, 180, 90 }, span_id: [8]u8{ 21, 169, 121, 137, 199, 68, 93, 104 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "caf\xc3\xa9", kind: 4u8, start_ns: 4155410469356298825u64, end_ns: 915712604384579088u64, attributes: sat0[0usize..3usize], status_code: 0u8, status_message: "" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "tracer", spans[0usize..1usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"4503319f53ddc0e2cccf85d35da7b45a\",\"spanId\":\"15a97989c7445d68\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"4155410469356298825\",\"endTimeUnixNano\":\"915712604384579088\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"200\"}}]}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"tracer\"},\"spans\":[{\"traceId\":\"4503319f53ddc0e2cccf85d35da7b45a\",\"spanId\":\"15a97989c7445d68\",\"name\":\"caf\xc3\xa9\",\"kind\":4,\"startTimeUnixNano\":\"4155410469356298825\",\"endTimeUnixNano\":\"915712604384579088\",\"attributes\":[{\"key\":\"k0\",\"value\":{\"stringValue\":\"x\\ny\"}},{\"key\":\"http.method1\",\"value\":{\"stringValue\":\"/a\\\"b\"}},{\"key\":\"peer2\",\"value\":{\"stringValue\":\"200\"}}]}]}]}]}")
        ret false
    }
    ret true
}

fn case_129(a: *mem.Arena) -> bool {
    var spans: [3]x.Span = zero
    let sat0: [3]x.Label = [3]x.Label{ x.Label{ name: "peer0", value: "plain value" }, x.Label{ name: "peer1", value: "plain value" }, x.Label{ name: "k2", value: "/a\"b" } }
    spans[0] = x.Span{ trace_id: [16]u8{ 148, 94, 170, 178, 30, 116, 159, 36, 117, 150, 84, 77, 255, 18, 139, 188 }, span_id: [8]u8{ 193, 169, 188, 128, 34, 76, 29, 145 }, parent_span_id: [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, name: "x", kind: 3u8, start_ns: 201377784928770460u64, end_ns: 2263425771430922027u64, attributes: sat0[0usize..3usize], status_code: 0u8, status_message: "" }
    let sat1: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[1] = x.Span{ trace_id: [16]u8{ 95, 179, 166, 227, 18, 251, 55, 253, 229, 106, 226, 32, 80, 233, 226, 240 }, span_id: [8]u8{ 61, 22, 161, 222, 95, 19, 152, 159 }, parent_span_id: [8]u8{ 95, 127, 227, 29, 51, 50, 134, 123 }, name: "GET /a", kind: 3u8, start_ns: 695734189098512753u64, end_ns: 1835923783613748057u64, attributes: sat1[0usize..0usize], status_code: 0u8, status_message: "line\nbreak" }
    let sat2: [1]x.Label = [1]x.Label{ x.Label{ name: "", value: "" } }
    spans[2] = x.Span{ trace_id: [16]u8{ 85, 131, 23, 218, 148, 165, 221, 132, 229, 34, 50, 240, 71, 138, 96, 109 }, span_id: [8]u8{ 145, 17, 91, 174, 66, 41, 47, 50 }, parent_span_id: [8]u8{ 143, 173, 78, 153, 213, 241, 166, 4 }, name: "db \"query\"", kind: 0u8, start_ns: 4198211310227579310u64, end_ns: 3660602472696851352u64, attributes: sat2[0usize..0usize], status_code: 1u8, status_message: "boom" }
    let res: [1]x.Label = [1]x.Label{ x.Label{ name: "service.name", value: "api" } }
    let (got, ge) = x.render_otlp_spans(a, res[0usize..1usize], "", spans[0usize..3usize])
    if ge != ok || !str.eq(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"945eaab21e749f247596544dff128bbc\",\"spanId\":\"c1a9bc80224c1d91\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"201377784928770460\",\"endTimeUnixNano\":\"2263425771430922027\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"traceId\":\"5fb3a6e312fb37fde56ae22050e9e2f0\",\"spanId\":\"3d16a1de5f13989f\",\"parentSpanId\":\"5f7fe31d3332867b\",\"name\":\"GET /a\",\"kind\":3,\"startTimeUnixNano\":\"695734189098512753\",\"endTimeUnixNano\":\"1835923783613748057\",\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"558317da94a5dd84e52232f0478a606d\",\"spanId\":\"91115bae42292f32\",\"parentSpanId\":\"8fad4e99d5f1a604\",\"name\":\"db \\\"query\\\"\",\"startTimeUnixNano\":\"4198211310227579310\",\"endTimeUnixNano\":\"3660602472696851352\",\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}") {
        show(got, "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"945eaab21e749f247596544dff128bbc\",\"spanId\":\"c1a9bc80224c1d91\",\"name\":\"x\",\"kind\":3,\"startTimeUnixNano\":\"201377784928770460\",\"endTimeUnixNano\":\"2263425771430922027\",\"attributes\":[{\"key\":\"peer0\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"peer1\",\"value\":{\"stringValue\":\"plain value\"}},{\"key\":\"k2\",\"value\":{\"stringValue\":\"/a\\\"b\"}}]},{\"traceId\":\"5fb3a6e312fb37fde56ae22050e9e2f0\",\"spanId\":\"3d16a1de5f13989f\",\"parentSpanId\":\"5f7fe31d3332867b\",\"name\":\"GET /a\",\"kind\":3,\"startTimeUnixNano\":\"695734189098512753\",\"endTimeUnixNano\":\"1835923783613748057\",\"status\":{\"message\":\"line\\nbreak\"}},{\"traceId\":\"558317da94a5dd84e52232f0478a606d\",\"spanId\":\"91115bae42292f32\",\"parentSpanId\":\"8fad4e99d5f1a604\",\"name\":\"db \\\"query\\\"\",\"startTimeUnixNano\":\"4198211310227579310\",\"endTimeUnixNano\":\"3660602472696851352\",\"status\":{\"message\":\"boom\",\"code\":1}}]}]}]}")
        ret false
    }
    ret true
}

fn static_checks(a: *mem.Arena) -> u32 {
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
    let want = "# HELP jobs_total Jobs\n# TYPE jobs_total counter\njobs_total 42.0\n# HELP depth Depth\n# TYPE depth gauge\ndepth -7.0\n# HELP lat Latency\n# TYPE lat histogram\nlat_bucket{le=\"0.5\"} 1.0\nlat_bucket{le=\"1.0\"} 2.0\nlat_bucket{le=\"+Inf\"} 3.0\nlat_count 3.0\nlat_sum 8.0\n"
    if te != ok || !str.eq(text, want) {
        show(text, want)
        ret 3u32
    }
    // negotiation
    let (s1, e1) = x.scrape(a, samples[0usize..1usize], "text/plain")
    if e1 != ok || !str.eq(s1.content_type, "text/plain; version=0.0.4; charset=utf-8") { ret 4u32 }
    let (s2, e2) = x.scrape(a, samples[0usize..1usize], "application/openmetrics-text; version=1.0.0,text/plain;q=0.5")
    if e2 != ok || !str.eq(s2.content_type, "application/openmetrics-text; version=1.0.0; charset=utf-8") { ret 5u32 }
    if !str.eq(s2.body, "# HELP jobs Jobs\n# TYPE jobs counter\njobs_total 42.0\n# EOF\n") { ret 6u32 }
    // non-finite values and a histogram whose buckets disagree with its bounds
    var nf: [3]x.Sample = zero
    nf[0] = x.Sample{ name: "g", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](9218868437227405312u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    nf[1] = x.Sample{ name: "n", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](9221120237041090560u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    nf[2] = x.Sample{ name: "m", help: "", kind: x.Kind.Gauge, labels: none[0usize..0usize], value: mem.bitcast[f64](18442240474082181120u64), bounds: none2(), buckets: nones(), sum: 0.0 }
    let (t2, e3) = x.render_text(a, nf[0usize..3usize], false)
    let want2 = "# HELP g \n# TYPE g gauge\ng +Inf\n# HELP n \n# TYPE n gauge\nn NaN\n# HELP m \n# TYPE m gauge\nm -Inf\n"
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
    let wire = "POST /v1/metrics HTTP/1.1\r\nHost: collector:4318\r\nContent-Type: application/json\r\nAccept: application/json\r\nContent-Length: 2\r\n\r\n{}"
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
    if !case_0(a) { os.exit(1i32) }
    if !case_1(a) { os.exit(2i32) }
    if !case_2(a) { os.exit(3i32) }
    if !case_3(a) { os.exit(4i32) }
    if !case_4(a) { os.exit(5i32) }
    if !case_5(a) { os.exit(6i32) }
    if !case_6(a) { os.exit(7i32) }
    if !case_7(a) { os.exit(8i32) }
    if !case_8(a) { os.exit(9i32) }
    if !case_9(a) { os.exit(10i32) }
    if !case_10(a) { os.exit(11i32) }
    if !case_11(a) { os.exit(12i32) }
    if !case_12(a) { os.exit(13i32) }
    if !case_13(a) { os.exit(14i32) }
    if !case_14(a) { os.exit(15i32) }
    if !case_15(a) { os.exit(16i32) }
    if !case_16(a) { os.exit(17i32) }
    if !case_17(a) { os.exit(18i32) }
    if !case_18(a) { os.exit(19i32) }
    if !case_19(a) { os.exit(20i32) }
    if !case_20(a) { os.exit(21i32) }
    if !case_21(a) { os.exit(22i32) }
    if !case_22(a) { os.exit(23i32) }
    if !case_23(a) { os.exit(24i32) }
    if !case_24(a) { os.exit(25i32) }
    if !case_25(a) { os.exit(26i32) }
    if !case_26(a) { os.exit(27i32) }
    if !case_27(a) { os.exit(28i32) }
    if !case_28(a) { os.exit(29i32) }
    if !case_29(a) { os.exit(30i32) }
    if !case_30(a) { os.exit(31i32) }
    if !case_31(a) { os.exit(32i32) }
    if !case_32(a) { os.exit(33i32) }
    if !case_33(a) { os.exit(34i32) }
    if !case_34(a) { os.exit(35i32) }
    if !case_35(a) { os.exit(36i32) }
    if !case_36(a) { os.exit(37i32) }
    if !case_37(a) { os.exit(38i32) }
    if !case_38(a) { os.exit(39i32) }
    if !case_39(a) { os.exit(40i32) }
    if !case_40(a) { os.exit(41i32) }
    if !case_41(a) { os.exit(42i32) }
    if !case_42(a) { os.exit(43i32) }
    if !case_43(a) { os.exit(44i32) }
    if !case_44(a) { os.exit(45i32) }
    if !case_45(a) { os.exit(46i32) }
    if !case_46(a) { os.exit(47i32) }
    if !case_47(a) { os.exit(48i32) }
    if !case_48(a) { os.exit(49i32) }
    if !case_49(a) { os.exit(50i32) }
    if !case_50(a) { os.exit(51i32) }
    if !case_51(a) { os.exit(52i32) }
    if !case_52(a) { os.exit(53i32) }
    if !case_53(a) { os.exit(54i32) }
    if !case_54(a) { os.exit(55i32) }
    if !case_55(a) { os.exit(56i32) }
    if !case_56(a) { os.exit(57i32) }
    if !case_57(a) { os.exit(58i32) }
    if !case_58(a) { os.exit(59i32) }
    if !case_59(a) { os.exit(60i32) }
    if !case_60(a) { os.exit(61i32) }
    if !case_61(a) { os.exit(62i32) }
    if !case_62(a) { os.exit(63i32) }
    if !case_63(a) { os.exit(64i32) }
    if !case_64(a) { os.exit(65i32) }
    if !case_65(a) { os.exit(66i32) }
    if !case_66(a) { os.exit(67i32) }
    if !case_67(a) { os.exit(68i32) }
    if !case_68(a) { os.exit(69i32) }
    if !case_69(a) { os.exit(70i32) }
    if !case_70(a) { os.exit(71i32) }
    if !case_71(a) { os.exit(72i32) }
    if !case_72(a) { os.exit(73i32) }
    if !case_73(a) { os.exit(74i32) }
    if !case_74(a) { os.exit(75i32) }
    if !case_75(a) { os.exit(76i32) }
    if !case_76(a) { os.exit(77i32) }
    if !case_77(a) { os.exit(78i32) }
    if !case_78(a) { os.exit(79i32) }
    if !case_79(a) { os.exit(80i32) }
    if !case_80(a) { os.exit(81i32) }
    if !case_81(a) { os.exit(82i32) }
    if !case_82(a) { os.exit(83i32) }
    if !case_83(a) { os.exit(84i32) }
    if !case_84(a) { os.exit(85i32) }
    if !case_85(a) { os.exit(86i32) }
    if !case_86(a) { os.exit(87i32) }
    if !case_87(a) { os.exit(88i32) }
    if !case_88(a) { os.exit(89i32) }
    if !case_89(a) { os.exit(90i32) }
    if !case_90(a) { os.exit(91i32) }
    if !case_91(a) { os.exit(92i32) }
    if !case_92(a) { os.exit(93i32) }
    if !case_93(a) { os.exit(94i32) }
    if !case_94(a) { os.exit(95i32) }
    if !case_95(a) { os.exit(96i32) }
    if !case_96(a) { os.exit(97i32) }
    if !case_97(a) { os.exit(98i32) }
    if !case_98(a) { os.exit(99i32) }
    if !case_99(a) { os.exit(100i32) }
    if !case_100(a) { os.exit(101i32) }
    if !case_101(a) { os.exit(102i32) }
    if !case_102(a) { os.exit(103i32) }
    if !case_103(a) { os.exit(104i32) }
    if !case_104(a) { os.exit(105i32) }
    if !case_105(a) { os.exit(106i32) }
    if !case_106(a) { os.exit(107i32) }
    if !case_107(a) { os.exit(108i32) }
    if !case_108(a) { os.exit(109i32) }
    if !case_109(a) { os.exit(110i32) }
    if !case_110(a) { os.exit(111i32) }
    if !case_111(a) { os.exit(112i32) }
    if !case_112(a) { os.exit(113i32) }
    if !case_113(a) { os.exit(114i32) }
    if !case_114(a) { os.exit(115i32) }
    if !case_115(a) { os.exit(116i32) }
    if !case_116(a) { os.exit(117i32) }
    if !case_117(a) { os.exit(118i32) }
    if !case_118(a) { os.exit(119i32) }
    if !case_119(a) { os.exit(120i32) }
    if !case_120(a) { os.exit(121i32) }
    if !case_121(a) { os.exit(122i32) }
    if !case_122(a) { os.exit(123i32) }
    if !case_123(a) { os.exit(124i32) }
    if !case_124(a) { os.exit(125i32) }
    if !case_125(a) { os.exit(126i32) }
    if !case_126(a) { os.exit(127i32) }
    if !case_127(a) { os.exit(128i32) }
    if !case_128(a) { os.exit(129i32) }
    if !case_129(a) { os.exit(130i32) }
    let sc = static_checks(a)
    if sc != 0u32 { os.exit(i32(100u32 + sc)) }
    try io.print("metrics export ok")
    ret ok
}
