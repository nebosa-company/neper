// `e.test.bench`: the statistics and both report renderings for 14 sample sets against
// scripts/bench_vectors.py (Python's `statistics`, a numerically integrated Student t), the
// comparison verdicts, the sort and quantile building blocks, and a real `run` over two bodies of
// very different cost whose report must have the right shape and order (never a timing value).
use e.io
use e.mem
use e.os
use e.str
use e.test.bench as bench

fn vectors() -> str {
    ret "set~100,100~{\"name\": \"bench_0\", \"iters\": 1, \"samples\": 2, \"kept\": 2, \"mean\": 100.000, \"median\": 100.000, \"stddev\": 0.000, \"min\": 100.000, \"max\": 100.000, \"q1\": 100.000, \"q3\": 100.000, \"mad\": 0.000, \"ci_low\": 100.000, \"ci_high\": 100.000, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_0@N@  time:   [100.000 ns 100.000 ns 100.000 ns]@N@  median: 100.000 ns (mad 0.000)@N@  stddev: 0.000 ns over 2 of 2 samples, 1 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~100,110.5,120.25~{\"name\": \"bench_1\", \"iters\": 38, \"samples\": 3, \"kept\": 3, \"mean\": 110.250, \"median\": 110.500, \"stddev\": 10.127, \"min\": 100.000, \"max\": 120.250, \"q1\": 105.250, \"q3\": 115.375, \"mad\": 9.750, \"ci_low\": 85.090, \"ci_high\": 135.410, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_1@N@  time:   [85.090 ns 110.250 ns 135.410 ns]@N@  median: 110.500 ns (mad 9.750)@N@  stddev: 10.127 ns over 3 of 3 samples, 38 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~5,5,5,5,5,5,5,5,5,5,5,5~{\"name\": \"bench_2\", \"iters\": 75, \"samples\": 12, \"kept\": 12, \"mean\": 5.000, \"median\": 5.000, \"stddev\": 0.000, \"min\": 5.000, \"max\": 5.000, \"q1\": 5.000, \"q3\": 5.000, \"mad\": 0.000, \"ci_low\": 5.000, \"ci_high\": 5.000, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_2@N@  time:   [5.000 ns 5.000 ns 5.000 ns]@N@  median: 5.000 ns (mad 0.000)@N@  stddev: 0.000 ns over 12 of 12 samples, 75 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~940.25,964,988.75,1082.25,1076.25,935.75,975.75,973.75~{\"name\": \"bench_3\", \"iters\": 112, \"samples\": 8, \"kept\": 8, \"mean\": 992.094, \"median\": 974.750, \"stddev\": 56.666, \"min\": 935.750, \"max\": 1082.250, \"q1\": 958.062, \"q3\": 1010.625, \"mad\": 24.250, \"ci_low\": 944.713, \"ci_high\": 1039.475, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_3@N@  time:   [944.713 ns 992.094 ns 1039.475 ns]@N@  median: 974.750 ns (mad 24.250)@N@  stddev: 56.666 ns over 8 of 8 samples, 112 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~1007.25,984.5,982,994.25,1010.5,956,1003.75,981.25,992.25,938.25,1011,1012.25,1024,1012.75,998,984.75,1033.5,985.25,1001.25,1021.75~{\"name\": \"bench_4\", \"iters\": 149, \"samples\": 20, \"kept\": 19, \"mean\": 999.803, \"median\": 1001.250, \"stddev\": 18.532, \"min\": 956.000, \"max\": 1033.500, \"q1\": 984.688, \"q3\": 1011.312, \"mad\": 11.500, \"ci_low\": 990.870, \"ci_high\": 1008.735, \"outliers\": {\"low_severe\": 0, \"low_mild\": 1, \"high_mild\": 0, \"high_severe\": 0}}~bench_4@N@  time:   [990.870 ns 999.803 ns 1008.735 ns]@N@  median: 1001.250 ns (mad 11.500)@N@  stddev: 18.532 ns over 19 of 20 samples, 149 iterations each@N@  outliers: 1 (0 low severe, 1 low mild, 0 high mild, 0 high severe)@N@\nset~261.25,258,265.75,255.5,246.75,256,233.5,252,253.25,245.5,243.25,249.75,256,246.25,234,255.75,249.75,239,259,242.75,259.25,244.5,239.25,264.25,238.25,248.5,240.75,232.25,257,250.25~{\"name\": \"bench_5\", \"iters\": 186, \"samples\": 30, \"kept\": 30, \"mean\": 249.242, \"median\": 249.750, \"stddev\": 9.227, \"min\": 232.250, \"max\": 265.750, \"q1\": 242.875, \"q3\": 256.000, \"mad\": 6.750, \"ci_low\": 245.797, \"ci_high\": 252.687, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_5@N@  time:   [245.797 ns 249.242 ns 252.687 ns]@N@  median: 249.750 ns (mad 6.750)@N@  stddev: 9.227 ns over 30 of 30 samples, 186 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~247,276.75,245,248.75,245,245,259.5,276.25,245,255.75,258.75,261.5,239.25,245.5,249.25,261.75,256.5,242,251,258,261.5,251.5,234.25,240.75,254.75,262.25,262,243.5,251.5,255.75,257.75~{\"name\": \"bench_6\", \"iters\": 223, \"samples\": 31, \"kept\": 31, \"mean\": 253.000, \"median\": 251.500, \"stddev\": 9.893, \"min\": 234.250, \"max\": 276.750, \"q1\": 245.000, \"q3\": 259.125, \"mad\": 6.500, \"ci_low\": 249.372, \"ci_high\": 256.628, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_6@N@  time:   [249.372 ns 253.000 ns 256.628 ns]@N@  median: 251.500 ns (mad 6.500)@N@  stddev: 9.893 ns over 31 of 31 samples, 223 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~4607.5,5326.75,5294,5246.25,5209.5,4701.25,4870,4891,4955.5,5167.5,5151.25,4910.5,4700.75,4851,4606.25,4864,4363,4731.75,4912,4993,5436.5,5311,5657.25,5401.5,4814.5,5360,4908.75,5436.25,4964.5,4754.5,4905,5297,4924,5063,5268.5,5369.5,5040,5127,5104.5,5332.5,5075.75,4691.75,5253.25,5870.75,5061,5464.25,5095.25,5422.75,4582.5,4611.25,4768.75,5232.75,4867.25,4780.25,5310.25,4963.75,5128.75,5222,4867.75,5062.25~{\"name\": \"bench_7\", \"iters\": 260, \"samples\": 60, \"kept\": 60, \"mean\": 5052.679, \"median\": 5061.625, \"stddev\": 291.355, \"min\": 4363.000, \"max\": 5870.750, \"q1\": 4866.438, \"q3\": 5274.875, \"mad\": 202.250, \"ci_low\": 4978.956, \"ci_high\": 5126.402, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_7@N@  time:   [4978.956 ns 5052.679 ns 5126.402 ns]@N@  median: 5061.625 ns (mad 202.250)@N@  stddev: 291.355 ns over 60 of 60 samples, 260 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~86,80.75,86.5,86,84.25,92,86.75,91.25,93.5,89.75,90.75,87.5,94.75,88,88.25,86,88.75,89.25,89.5,92.5,88.5,95,89.75,93.75,91.25,86,97.5,92.5,92.25,93,84,97.25,92.25,89.75,95.75,91.75,91,92,84,94,88.75,93,87,91.5,85~{\"name\": \"bench_8\", \"iters\": 297, \"samples\": 45, \"kept\": 45, \"mean\": 89.967, \"median\": 89.750, \"stddev\": 3.758, \"min\": 80.750, \"max\": 97.500, \"q1\": 87.000, \"q3\": 92.500, \"mad\": 2.750, \"ci_low\": 88.869, \"ci_high\": 91.065, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_8@N@  time:   [88.869 ns 89.967 ns 91.065 ns]@N@  median: 89.750 ns (mad 2.750)@N@  stddev: 3.758 ns over 45 of 45 samples, 297 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~1007.5,1018.5,1025,992,1012,971.5,984,1002.25,1008.25,1022.75,1014.5,1004.75,995,1000.75,973.5,1005,986.25,995.75,978,1001.25,1012.25,988.5,1006.5,980.5,1030.5,977,991,996.25,979.25,1041,997.25,1006.5,1032.75,1022.5,994.25,1025.75,987,1015.75,1009.5,974.75,2000,2500.25,3~{\"name\": \"bench_9\", \"iters\": 334, \"samples\": 43, \"kept\": 40, \"mean\": 1001.681, \"median\": 1001.750, \"stddev\": 17.756, \"min\": 971.500, \"max\": 1041.000, \"q1\": 987.750, \"q3\": 1015.125, \"mad\": 13.000, \"ci_low\": 996.179, \"ci_high\": 1007.184, \"outliers\": {\"low_severe\": 1, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 2}}~bench_9@N@  time:   [996.179 ns 1001.681 ns 1007.184 ns]@N@  median: 1001.750 ns (mad 13.000)@N@  stddev: 17.756 ns over 40 of 43 samples, 334 iterations each@N@  outliers: 3 (1 low severe, 0 low mild, 0 high mild, 2 high severe)@N@\nset~499.25,491.25,493.25,514.75,494.25,501.5,492.5,480.75,504.5,505.5,513.5,509.5,510.25,514.75,497.25,494.75,493.5,487.5,489,491,491.5,509.25,502.5,507,496.25,1500,40~{\"name\": \"bench_10\", \"iters\": 371, \"samples\": 27, \"kept\": 25, \"mean\": 499.400, \"median\": 497.250, \"stddev\": 9.358, \"min\": 480.750, \"max\": 514.750, \"q1\": 492.000, \"q3\": 508.125, \"mad\": 6.250, \"ci_low\": 495.537, \"ci_high\": 503.263, \"outliers\": {\"low_severe\": 1, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 1}}~bench_10@N@  time:   [495.537 ns 499.400 ns 503.263 ns]@N@  median: 497.250 ns (mad 6.250)@N@  stddev: 9.358 ns over 25 of 27 samples, 371 iterations each@N@  outliers: 2 (1 low severe, 0 low mild, 0 high mild, 1 high severe)@N@\nset~996.75,1021.5,985.75,955.75,998,1035,997,994.75,1024.25,990.25,981.5,932.75,1007,1019.75,1021.25,1024.75,1014.5,1017,1039.25,974.75,1017.25,949.5,1054.75,955.5,1015.5,994.75,997.75,977.25,1010.5,973.25~{\"name\": \"bench_11\", \"iters\": 408, \"samples\": 30, \"kept\": 30, \"mean\": 999.250, \"median\": 997.875, \"stddev\": 28.195, \"min\": 932.750, \"max\": 1054.750, \"q1\": 982.562, \"q3\": 1019.125, \"mad\": 20.000, \"ci_low\": 988.723, \"ci_high\": 1009.777, \"outliers\": {\"low_severe\": 0, \"low_mild\": 0, \"high_mild\": 0, \"high_severe\": 0}}~bench_11@N@  time:   [988.723 ns 999.250 ns 1009.777 ns]@N@  median: 997.875 ns (mad 20.000)@N@  stddev: 28.195 ns over 30 of 30 samples, 408 iterations each@N@  outliers: 0 (0 low severe, 0 low mild, 0 high mild, 0 high severe)@N@\nset~1075.5,1118,1103.25,1103.5,1118.75,1113,1075.5,1048.5,1099.25,1132.75,1110.5,1099.25,1095.25,1063.25,1081.25,1117,1090.25,1091.25,1092,1095.25,1127.25,1127.75,1071.25,1093.75,1099.5,1069.5,1094,1105,1123.5,1120.75~{\"name\": \"bench_12\", \"iters\": 445, \"samples\": 30, \"kept\": 29, \"mean\": 1100.241, \"median\": 1099.250, \"stddev\": 18.779, \"min\": 1063.250, \"max\": 1132.750, \"q1\": 1090.500, \"q3\": 1116.000, \"mad\": 13.750, \"ci_low\": 1093.100, \"ci_high\": 1107.383, \"outliers\": {\"low_severe\": 0, \"low_mild\": 1, \"high_mild\": 0, \"high_severe\": 0}}~bench_12@N@  time:   [1093.100 ns 1100.241 ns 1107.383 ns]@N@  median: 1099.250 ns (mad 13.750)@N@  stddev: 18.779 ns over 29 of 30 samples, 445 iterations each@N@  outliers: 1 (0 low severe, 1 low mild, 0 high mild, 0 high severe)@N@\nset~1024,978.25,1029.75,968.25,988.25,1007.75,990.75,994.75,986.5,1039.25,938,961,979.25,1037.25,996.75,1012.5,986.75,992,958,991.5,981.5,998.5,974.25,1013.25,997.75,986.75,972.75,998.25,1024.5,995.75~{\"name\": \"bench_13\", \"iters\": 482, \"samples\": 30, \"kept\": 29, \"mean\": 995.371, \"median\": 992.000, \"stddev\": 21.267, \"min\": 958.000, \"max\": 1039.250, \"q1\": 979.812, \"q3\": 1005.438, \"mad\": 12.750, \"ci_low\": 987.283, \"ci_high\": 1003.459, \"outliers\": {\"low_severe\": 0, \"low_mild\": 1, \"high_mild\": 0, \"high_severe\": 0}}~bench_13@N@  time:   [987.283 ns 995.371 ns 1003.459 ns]@N@  median: 992.000 ns (mad 12.750)@N@  stddev: 21.267 ns over 29 of 30 samples, 482 iterations each@N@  outliers: 1 (0 low severe, 1 low mild, 0 high mild, 0 high severe)@N@\ncmp~11~12~1~bench_12: regressed (10.11%, t = 16.24)\ncmp~12~11~1~bench_11: improved (-9.18%, t = -16.24)\ncmp~11~13~1~bench_13: no change (-0.39%, t = -0.60)\ncmp~11~12~20~bench_12: no change (10.11%, t = 16.24)\ncmp~3~4~5~bench_4: no change (0.78%, t = 0.38)\ncmp~0~1~0~bench_1: no change (10.25%, t = 1.75)\ncmp~2~2~0~bench_2: no change (0.00%, t = 0.00)\ncmp~6~7~0~bench_7: regressed (1897.11%, t = 127.46)"
}

type Work = struct { n: u64, sink: u64 }

fn spin(w: *Work) {
    var i = 0u64
    while i < w.n {
        w.sink = w.sink *% 31u64 +% i
        i += 1u64
    }
}

fn parse_samples(csv: str, out: []f64) -> usize {
    var n = 0usize
    var rest = csv
    while rest.len > 0usize {
        let (head, tail, found) = str.split_once(rest, ",")
        var piece = head
        if !found { piece = rest }
        let (v, e) = str.parse_f64(piece)
        if e != ok || n >= out.len { os.exit(90i32) }
        out[n] = v
        n += 1usize
        if !found { break }
        rest = tail
    }
    ret n
}

fn check_vectors(a: *mem.Arena) -> i32 {
    var samples: [128]f64 = zero
    var all: [16]bench.Stats = zero
    var lines = str.lines(vectors())
    var sets = 0usize
    var comparisons = 0i32
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (kind, rest, found) = str.split_once(line, "~")
        if !found { ret 10i32 }
        if str.eq(kind, "set") {
            let (csv, rest2, f2) = str.split_once(rest, "~")
            let (want_json, want_text, f3) = str.split_once(rest2, "~")
            if !f2 || !f3 { ret 11i32 }
            let n = parse_samples(csv, samples[0..])
            let (stats, se) = bench.summarize(samples[0..n], 15u32)
            if se != ok { ret 12i32 }
            all[sets] = stats
            // The name and iteration count the generator used: bench_<i>, 1 + 37 i.
            let (nb, ne) = str.builder(a, 32usize)
            if ne != ok { ret 13i32 }
            var name_builder = nb
            if str.push(&name_builder, "bench_") != ok || str.push_usize(&name_builder, sets) != ok { ret 14i32 }
            let report = bench.Report { name: str.done(&name_builder), iters: u64(1usize + 37usize * sets), stats: stats }
            let (jb, je) = str.builder(a, 1024usize)
            if je != ok { ret 15i32 }
            var json = jb
            if bench.render_json(&json, report) != ok { ret 16i32 }
            if !str.eq(str.done(&json), want_json) { ret 100i32 + i32(sets) }
            let (expected_text, rp) = str.replace(a, want_text, "@N@", "\n")
            if rp != ok { ret 19i32 }
            let (tb, te) = str.builder(a, 1024usize)
            if te != ok { ret 17i32 }
            var text = tb
            if bench.render_text(&text, report) != ok { ret 18i32 }
            if !str.eq(str.done(&text), expected_text) { ret 130i32 + i32(sets) }
            sets += 1usize
        } else if str.eq(kind, "cmp") {
            let (ia, r1, g1) = str.split_once(rest, "~")
            let (ib, r2, g2) = str.split_once(r1, "~")
            let (thr, want, g3) = str.split_once(r2, "~")
            if !g1 || !g2 || !g3 { ret 20i32 }
            let (x, ex) = str.parse_u64(ia)
            let (y, ey) = str.parse_u64(ib)
            let (threshold, et) = str.parse_f64(thr)
            if ex != ok || ey != ok || et != ok { ret 21i32 }
            let c = bench.compare(all[usize(x)], all[usize(y)], threshold)
            let (cb, ce) = str.builder(a, 128usize)
            if ce != ok { ret 22i32 }
            var cmp = cb
            if str.push(&cmp, "bench_") != ok || str.push_u64(&cmp, y) != ok { ret 23i32 }
            let label = str.done(&cmp)
            let (ob, oe) = str.builder(a, 128usize)
            if oe != ok { ret 24i32 }
            var out = ob
            if bench.render_comparison(&out, label, c) != ok { ret 25i32 }
            let (full, rq) = str.replace(a, str.done(&out), "\n", "")
            if rq != ok { ret 26i32 }
            if !str.eq(full, want) { ret 160i32 + comparisons }
            comparisons += 1i32
        }
    }
    if sets != 14usize || comparisons != 8i32 { ret 27i32 }
    ret 0i32
}

fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.0000001f64
}

fn check_parts() -> i32 {
    // The t table: exact to 30, normal beyond, nothing at 0.
    if !near(bench.t_critical(1usize), 12.706f64) || !near(bench.t_critical(11usize), 2.201f64) { ret 40i32 }
    if !near(bench.t_critical(30usize), 2.042f64) || !near(bench.t_critical(31usize), 1.96f64) { ret 41i32 }
    if bench.t_critical(0usize) != 0.0f64 { ret 42i32 }
    // sort and quantile.
    var v: [7]f64 = zero
    v[0] = 5.0f64
    v[1] = 1.0f64
    v[2] = 4.0f64
    v[3] = 2.0f64
    v[4] = 7.0f64
    v[5] = 3.0f64
    v[6] = 6.0f64
    bench.sort(v[0..])
    var i = 0usize
    while i < 7usize {
        if v[i] != f64(i + 1usize) { ret 43i32 }
        i += 1usize
    }
    if !near(bench.quantile(v[0..], 0.0f64), 1.0f64) || !near(bench.quantile(v[0..], 1.0f64), 7.0f64) { ret 44i32 }
    if !near(bench.quantile(v[0..], 0.5f64), 4.0f64) || !near(bench.quantile(v[0..], 0.25f64), 2.5f64) { ret 45i32 }
    if bench.quantile(v[0..0], 0.5f64) != 0.0f64 { ret 46i32 }
    // Under two samples there is nothing to summarize.
    var one: [1]f64 = zero
    let (s1, e1) = bench.summarize(one[0..], 15u32)
    if e1 != bench.TooFew { ret 47i32 }
    // A zero base mean compares as no change rather than dividing.
    var z: bench.Stats = zero
    let c = bench.compare(z, z, 1.0f64)
    if c.verdict != bench.Verdict.NoChange || c.change_pct != 0.0f64 { ret 48i32 }
    ret 0i32
}

fn check_run() -> i32 {
    var cfg = bench.config_default()
    cfg.warmup_ns = 5000000i64
    cfg.target_sample_ns = 200000i64
    var light_work = Work { n: 50u64, sink: 0u64 }
    var heavy_work = Work { n: 20000u64, sink: 0u64 }
    var light_samples: [30]f64 = zero
    var heavy_samples: [30]f64 = zero
    let (light, le) = bench.run[Work]("light", cfg, &light_work, spin, light_samples[0..])
    if le != ok { ret 50i32 }
    let (heavy, he) = bench.run[Work]("heavy", cfg, &heavy_work, spin, heavy_samples[0..])
    if he != ok { ret 51i32 }
    if light.iters < 1u64 || heavy.iters < 1u64 { ret 52i32 }
    if light.iters < heavy.iters { ret 53i32 }
    if light.stats.count != 30usize || heavy.stats.count != 30usize { ret 54i32 }
    if light.stats.kept < 1usize || light.stats.kept > 30usize || heavy.stats.kept < 1usize { ret 55i32 }
    if !(light.stats.mean > 0.0f64) || !(heavy.stats.mean > light.stats.mean) { ret 56i32 }
    if light.stats.ci_low > light.stats.mean || light.stats.ci_high < light.stats.mean { ret 57i32 }
    if light.stats.min > light.stats.median || light.stats.median > light.stats.max { ret 58i32 }
    if light.stats.q1 > light.stats.q3 { ret 59i32 }
    // 400 times the work is a regression by any threshold the caller could mean.
    let c = bench.compare(light.stats, heavy.stats, 5.0f64)
    if c.verdict != bench.Verdict.Regressed || !c.significant || c.change_pct < 100.0f64 { ret 60i32 }
    let back = bench.compare(heavy.stats, light.stats, 5.0f64)
    if back.verdict != bench.Verdict.Improved { ret 61i32 }
    // The body really ran: the work context advanced.
    if light_work.sink == 0u64 || heavy_work.sink == 0u64 { ret 62i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_vectors(a)
    if code == 0i32 { code = check_parts() }
    if code == 0i32 { code = check_run() }
    if code != 0i32 { os.exit(code) }
    let e = io.print("test bench ok")
    ret ok
}
