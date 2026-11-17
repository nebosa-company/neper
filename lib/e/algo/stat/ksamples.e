// R kSamples: the Anderson-Darling k-sample statistic of Scholz and Stephens, both versions ad.test reports (version 1 with every tie counted as one block,
// version 2 with the mid-rank adjustment), and the standardised T.AD = (AD - (k - 1)) / sigma_N.
//
// ad.pval gives the asymptotic p value of the standardised statistic (the package tables smoothed by smooth.spline, see e.algo.stat.smspline).
//
// Not here: the exact and simulated p-values, qn.test, contingency2xt and the distribution functions behind them.

use e.math
use e.math.dist as mdist
use e.math.nmath as nm
use e.mem
use e.algo.stat.smspline as sm

fn sorted_pool(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// the scale sigma_N of the statistic's null distribution
fn sigma_n(sizes: []const usize) -> f64 {
    let k = f64(sizes.len)
    var nn = 0usize
    var hh = 0.0f64
    var i = 0usize
    while i < sizes.len {
        nn += sizes[i]
        hh += 1.0f64 / f64(sizes[i])
        i += 1usize
    }
    let n = f64(nn)
    var h = 0.0f64
    i = 1usize
    while i < nn {
        h += 1.0f64 / f64(i)
        i += 1usize
    }
    var g = 0.0f64
    i = 1usize
    while i + 1usize < nn {
        var j = i + 1usize
        while j < nn {
            g += 1.0f64 / (f64(nn - i) * f64(j))
            j += 1usize
        }
        i += 1usize
    }
    let a = (4.0f64 * g - 6.0f64) * (k - 1.0f64) + (10.0f64 - 6.0f64 * g) * hh
    let b = (2.0f64 * g - 4.0f64) * k * k + 8.0f64 * h * k + (2.0f64 * g - 14.0f64 * h - 4.0f64) * hh - 8.0f64 * h + 4.0f64 * g - 6.0f64
    let c = (6.0f64 * h + 2.0f64 * g - 2.0f64) * k * k + (4.0f64 * h - 4.0f64 * g + 6.0f64) * k + (2.0f64 * h - 6.0f64) * hh + 4.0f64 * h
    let d = (2.0f64 * h + 6.0f64) * k * k - 4.0f64 * h * k
    ret math.sqrt[f64]((a * n * n * n + b * n * n + c * n + d) / ((n - 1.0f64) * (n - 2.0f64) * (n - 3.0f64)))
}

// ad.test over k samples stored back to back in x with their sizes: version 1 or 2; part 0 the AD statistic, 1 the standardised T.AD
fn ad_test(a: *mem.Arena, x: []const f64, sizes: []const usize, version: usize, part: usize) -> f64 {
    let k = sizes.len
    let nn = x.len
    let n = f64(nn)
    let (z, e) = sorted_pool(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var total = 0.0f64
    var si = 0usize
    var off = 0usize
    while si < k {
        let ni = f64(sizes[si])
        var sub = 0.0f64
        var lo = 0usize
        // walk the distinct pooled values; B counts the pooled values up to and including this block
        while lo < nn {
            var hi = lo
            while hi < nn && z[hi] == z[lo] { hi += 1usize }
            let l = f64(hi - lo)
            let b = f64(hi)
            var fi = 0.0f64
            var le = 0.0f64
            var q = 0usize
            while q < sizes[si] {
                let v = x[off + q]
                if v == z[lo] { fi += 1.0f64 }
                if v <= z[lo] { le += 1.0f64 }
                q += 1usize
            }
            if version == 1usize {
                if hi < nn {
                    let d = n * le - ni * b
                    sub += l * d * d / (b * (n - b))
                }
            } else {
                let ba = b - l / 2.0f64
                let m = le - fi / 2.0f64
                let d = n * m - ni * ba
                sub += l * d * d / (ba * (n - ba) - n * l / 4.0f64)
            }
            lo = hi
        }
        total += sub / ni
        off += sizes[si]
        si += 1usize
    }
    var ad = 0.0f64
    if version == 1usize { ad = total / n } else { ad = (n - 1.0f64) / (n * n) * total }
    if part == 0usize { ret ad }
    ret (ad - f64(k - 1usize)) / sigma_n(sizes)
}

// ---- ad.pval: the asymptotic p value of the standardised Anderson-Darling statistic (kSamples table 1 smoothed by smooth.spline) ----

fn adk_q(i: usize) -> f64 {
    if i == 0usize { ret 0.00001f64 }
    if i == 1usize { ret 0.00005f64 }
    if i == 2usize { ret 0.0001f64 }
    if i == 3usize { ret 0.0005f64 }
    if i == 4usize { ret 0.001f64 }
    if i == 5usize { ret 0.005f64 }
    if i == 6usize { ret 0.01f64 }
    if i == 7usize { ret 0.025f64 }
    if i == 8usize { ret 0.05f64 }
    if i == 9usize { ret 0.075f64 }
    if i == 10usize { ret 0.1f64 }
    if i == 11usize { ret 0.2f64 }
    if i == 12usize { ret 0.3f64 }
    if i == 13usize { ret 0.4f64 }
    if i == 14usize { ret 0.5f64 }
    if i == 15usize { ret 0.6f64 }
    if i == 16usize { ret 0.7f64 }
    if i == 17usize { ret 0.8f64 }
    if i == 18usize { ret 0.9f64 }
    if i == 19usize { ret 0.925f64 }
    if i == 20usize { ret 0.95f64 }
    if i == 21usize { ret 0.975f64 }
    if i == 22usize { ret 0.99f64 }
    if i == 23usize { ret 0.9925f64 }
    if i == 24usize { ret 0.995f64 }
    if i == 25usize { ret 0.9975f64 }
    if i == 26usize { ret 0.999f64 }
    if i == 27usize { ret 0.99925f64 }
    if i == 28usize { ret 0.9995f64 }
    if i == 29usize { ret 0.99975f64 }
    if i == 30usize { ret 0.9999f64 }
    if i == 31usize { ret 0.999925f64 }
    if i == 32usize { ret 0.99995f64 }
    if i == 33usize { ret 0.999975f64 }
    if i == 34usize { ret 0.99999f64 }
    ret 0.0f64
}

fn adk1_row0(o: []f64) {
    o[0usize] = 1.0f64
    o[1usize] = (0.0f64 - 1.1954f64)
    o[2usize] = (0.0f64 - 1.1786f64)
    o[3usize] = (0.0f64 - 1.166f64)
    o[4usize] = (0.0f64 - 1.1407f64)
    o[5usize] = (0.0f64 - 1.1253f64)
    o[6usize] = (0.0f64 - 1.0777f64)
    o[7usize] = (0.0f64 - 1.0489f64)
    o[8usize] = (0.0f64 - 0.9978f64)
    o[9usize] = (0.0f64 - 0.9417f64)
    o[10usize] = (0.0f64 - 0.8981f64)
    o[11usize] = (0.0f64 - 0.8598f64)
    o[12usize] = (0.0f64 - 0.7258f64)
    o[13usize] = (0.0f64 - 0.5966f64)
    o[14usize] = (0.0f64 - 0.4572f64)
    o[15usize] = (0.0f64 - 0.2966f64)
    o[16usize] = (0.0f64 - 0.1009f64)
    o[17usize] = 0.1571f64
    o[18usize] = 0.5357f64
    o[19usize] = 1.2255f64
    o[20usize] = 1.5262f64
    o[21usize] = 1.9633f64
    o[22usize] = 2.7314f64
    o[23usize] = 3.7825f64
    o[24usize] = 4.1241f64
    o[25usize] = 4.6044f64
    o[26usize] = 5.409f64
    o[27usize] = 6.4954f64
    o[28usize] = 6.8279f64
    o[29usize] = 7.2755f64
    o[30usize] = 8.1885f64
    o[31usize] = 9.3061f64
    o[32usize] = 9.6132f64
    o[33usize] = 10.0989f64
    o[34usize] = 10.8825f64
    o[35usize] = 11.8537f64
}

fn adk1_row1(o: []f64) {
    o[0usize] = 2.0f64
    o[1usize] = (0.0f64 - 1.5806f64)
    o[2usize] = (0.0f64 - 1.5394f64)
    o[3usize] = (0.0f64 - 1.5193f64)
    o[4usize] = (0.0f64 - 1.4659f64)
    o[5usize] = (0.0f64 - 1.4371f64)
    o[6usize] = (0.0f64 - 1.3503f64)
    o[7usize] = (0.0f64 - 1.2984f64)
    o[8usize] = (0.0f64 - 1.2098f64)
    o[9usize] = (0.0f64 - 1.1187f64)
    o[10usize] = (0.0f64 - 1.0491f64)
    o[11usize] = (0.0f64 - 0.9904f64)
    o[12usize] = (0.0f64 - 0.7938f64)
    o[13usize] = (0.0f64 - 0.617f64)
    o[14usize] = (0.0f64 - 0.4383f64)
    o[15usize] = (0.0f64 - 0.2428f64)
    o[16usize] = (0.0f64 - 0.0169f64)
    o[17usize] = 0.2635f64
    o[18usize] = 0.6496f64
    o[19usize] = 1.2989f64
    o[20usize] = 1.5677f64
    o[21usize] = 1.943f64
    o[22usize] = 2.5899f64
    o[23usize] = 3.4425f64
    o[24usize] = 3.716f64
    o[25usize] = 4.0847f64
    o[26usize] = 4.7223f64
    o[27usize] = 5.5823f64
    o[28usize] = 5.8282f64
    o[29usize] = 6.197f64
    o[30usize] = 6.8537f64
    o[31usize] = 7.6592f64
    o[32usize] = 7.9234f64
    o[33usize] = 8.2395f64
    o[34usize] = 8.8994f64
    o[35usize] = 9.5482f64
}

fn adk1_row2(o: []f64) {
    o[0usize] = 3.0f64
    o[1usize] = (0.0f64 - 1.8172f64)
    o[2usize] = (0.0f64 - 1.7728f64)
    o[3usize] = (0.0f64 - 1.7462f64)
    o[4usize] = (0.0f64 - 1.671f64)
    o[5usize] = (0.0f64 - 1.6314f64)
    o[6usize] = (0.0f64 - 1.5102f64)
    o[7usize] = (0.0f64 - 1.4415f64)
    o[8usize] = (0.0f64 - 1.3251f64)
    o[9usize] = (0.0f64 - 1.209f64)
    o[10usize] = (0.0f64 - 1.1235f64)
    o[11usize] = (0.0f64 - 1.0513f64)
    o[12usize] = (0.0f64 - 0.8188f64)
    o[13usize] = (0.0f64 - 0.6177f64)
    o[14usize] = (0.0f64 - 0.419f64)
    o[15usize] = (0.0f64 - 0.2078f64)
    o[16usize] = 0.0304f64
    o[17usize] = 0.3169f64
    o[18usize] = 0.6992f64
    o[19usize] = 1.3202f64
    o[20usize] = 1.5709f64
    o[21usize] = 1.919f64
    o[22usize] = 2.5f64
    o[23usize] = 3.2582f64
    o[24usize] = 3.4984f64
    o[25usize] = 3.8348f64
    o[26usize] = 4.4022f64
    o[27usize] = 5.1456f64
    o[28usize] = 5.3658f64
    o[29usize] = 5.6715f64
    o[30usize] = 6.2077f64
    o[31usize] = 6.85f64
    o[32usize] = 7.1025f64
    o[33usize] = 7.4326f64
    o[34usize] = 7.8934f64
    o[35usize] = 8.5568f64
}

fn adk1_row3(o: []f64) {
    o[0usize] = 4.0f64
    o[1usize] = (0.0f64 - 2.0032f64)
    o[2usize] = (0.0f64 - 1.9426f64)
    o[3usize] = (0.0f64 - 1.9067f64)
    o[4usize] = (0.0f64 - 1.8105f64)
    o[5usize] = (0.0f64 - 1.7619f64)
    o[6usize] = (0.0f64 - 1.6177f64)
    o[7usize] = (0.0f64 - 1.5355f64)
    o[8usize] = (0.0f64 - 1.4007f64)
    o[9usize] = (0.0f64 - 1.2671f64)
    o[10usize] = (0.0f64 - 1.1692f64)
    o[11usize] = (0.0f64 - 1.0879f64)
    o[12usize] = (0.0f64 - 0.8312f64)
    o[13usize] = (0.0f64 - 0.6139f64)
    o[14usize] = (0.0f64 - 0.4033f64)
    o[15usize] = (0.0f64 - 0.1844f64)
    o[16usize] = 0.0596f64
    o[17usize] = 0.348f64
    o[18usize] = 0.7246f64
    o[19usize] = 1.3254f64
    o[20usize] = 1.5663f64
    o[21usize] = 1.8975f64
    o[22usize] = 2.4451f64
    o[23usize] = 3.1423f64
    o[24usize] = 3.3651f64
    o[25usize] = 3.6714f64
    o[26usize] = 4.1791f64
    o[27usize] = 4.8657f64
    o[28usize] = 5.0749f64
    o[29usize] = 5.3642f64
    o[30usize] = 5.8499f64
    o[31usize] = 6.4806f64
    o[32usize] = 6.6731f64
    o[33usize] = 6.9567f64
    o[34usize] = 7.4501f64
    o[35usize] = 8.0283f64
}

fn adk1_row4(o: []f64) {
    o[0usize] = 6.0f64
    o[1usize] = (0.0f64 - 2.2526f64)
    o[2usize] = (0.0f64 - 2.1685f64)
    o[3usize] = (0.0f64 - 2.126f64)
    o[4usize] = (0.0f64 - 2.0048f64)
    o[5usize] = (0.0f64 - 1.9396f64)
    o[6usize] = (0.0f64 - 1.761f64)
    o[7usize] = (0.0f64 - 1.6625f64)
    o[8usize] = (0.0f64 - 1.4977f64)
    o[9usize] = (0.0f64 - 1.3382f64)
    o[10usize] = (0.0f64 - 1.2249f64)
    o[11usize] = (0.0f64 - 1.1317f64)
    o[12usize] = (0.0f64 - 0.8435f64)
    o[13usize] = (0.0f64 - 0.6073f64)
    o[14usize] = (0.0f64 - 0.3834f64)
    o[15usize] = (0.0f64 - 0.1548f64)
    o[16usize] = 0.0933f64
    o[17usize] = 0.3823f64
    o[18usize] = 0.7528f64
    o[19usize] = 1.3305f64
    o[20usize] = 1.5561f64
    o[21usize] = 1.8641f64
    o[22usize] = 2.3664f64
    o[23usize] = 3.0036f64
    o[24usize] = 3.2003f64
    o[25usize] = 3.4721f64
    o[26usize] = 3.9357f64
    o[27usize] = 4.5506f64
    o[28usize] = 4.7318f64
    o[29usize] = 4.9991f64
    o[30usize] = 5.4246f64
    o[31usize] = 5.9919f64
    o[32usize] = 6.1549f64
    o[33usize] = 6.3908f64
    o[34usize] = 6.9009f64
    o[35usize] = 7.4418f64
}

fn adk1_row5(o: []f64) {
    o[0usize] = 8.0f64
    o[1usize] = (0.0f64 - 2.4204f64)
    o[2usize] = (0.0f64 - 2.3288f64)
    o[3usize] = (0.0f64 - 2.2818f64)
    o[4usize] = (0.0f64 - 2.1356f64)
    o[5usize] = (0.0f64 - 2.0637f64)
    o[6usize] = (0.0f64 - 1.8537f64)
    o[7usize] = (0.0f64 - 1.738f64)
    o[8usize] = (0.0f64 - 1.5555f64)
    o[9usize] = (0.0f64 - 1.379f64)
    o[10usize] = (0.0f64 - 1.2552f64)
    o[11usize] = (0.0f64 - 1.155f64)
    o[12usize] = (0.0f64 - 0.8471f64)
    o[13usize] = (0.0f64 - 0.5987f64)
    o[14usize] = (0.0f64 - 0.3676f64)
    o[15usize] = (0.0f64 - 0.1346f64)
    o[16usize] = 0.1156f64
    o[17usize] = 0.4038f64
    o[18usize] = 0.7683f64
    o[19usize] = 1.3286f64
    o[20usize] = 1.5449f64
    o[21usize] = 1.8389f64
    o[22usize] = 2.3155f64
    o[23usize] = 2.9101f64
    o[24usize] = 3.0928f64
    o[25usize] = 3.3453f64
    o[26usize] = 3.7809f64
    o[27usize] = 4.3275f64
    o[28usize] = 4.4923f64
    o[29usize] = 4.7135f64
    o[30usize] = 5.1137f64
    o[31usize] = 5.6122f64
    o[32usize] = 5.8217f64
    o[33usize] = 6.011f64
    o[34usize] = 6.4538f64
    o[35usize] = 6.9524f64
}

fn adk1_row6(o: []f64) {
    o[0usize] = 10.0f64
    o[1usize] = (0.0f64 - 2.5283f64)
    o[2usize] = (0.0f64 - 2.4374f64)
    o[3usize] = (0.0f64 - 2.3926f64)
    o[4usize] = (0.0f64 - 2.2348f64)
    o[5usize] = (0.0f64 - 2.1521f64)
    o[6usize] = (0.0f64 - 1.9178f64)
    o[7usize] = (0.0f64 - 1.7936f64)
    o[8usize] = (0.0f64 - 1.5941f64)
    o[9usize] = (0.0f64 - 1.405f64)
    o[10usize] = (0.0f64 - 1.2755f64)
    o[11usize] = (0.0f64 - 1.1694f64)
    o[12usize] = (0.0f64 - 0.8496f64)
    o[13usize] = (0.0f64 - 0.5941f64)
    o[14usize] = (0.0f64 - 0.3587f64)
    o[15usize] = (0.0f64 - 0.1224f64)
    o[16usize] = 0.1294f64
    o[17usize] = 0.4166f64
    o[18usize] = 0.7771f64
    o[19usize] = 1.3257f64
    o[20usize] = 1.5356f64
    o[21usize] = 1.8212f64
    o[22usize] = 2.2823f64
    o[23usize] = 2.8579f64
    o[24usize] = 3.0311f64
    o[25usize] = 3.2777f64
    o[26usize] = 3.6963f64
    o[27usize] = 4.2228f64
    o[28usize] = 4.3642f64
    o[29usize] = 4.5945f64
    o[30usize] = 4.9555f64
    o[31usize] = 5.5136f64
    o[32usize] = 5.7345f64
    o[33usize] = 5.9566f64
    o[34usize] = 6.2705f64
    o[35usize] = 6.6195f64
}

fn adk1_row7(o: []f64) {
    o[0usize] = (1.0f64 / 0.0f64)
    o[1usize] = (0.0f64 - 4.2649f64)
    o[2usize] = (0.0f64 - 3.8906f64)
    o[3usize] = (0.0f64 - 3.719f64)
    o[4usize] = (0.0f64 - 3.2905f64)
    o[5usize] = (0.0f64 - 3.0902f64)
    o[6usize] = (0.0f64 - 2.5758f64)
    o[7usize] = (0.0f64 - 2.3263f64)
    o[8usize] = (0.0f64 - 1.96f64)
    o[9usize] = (0.0f64 - 1.6449f64)
    o[10usize] = (0.0f64 - 1.4395f64)
    o[11usize] = (0.0f64 - 1.2816f64)
    o[12usize] = (0.0f64 - 0.8416f64)
    o[13usize] = (0.0f64 - 0.5244f64)
    o[14usize] = (0.0f64 - 0.2533f64)
    o[15usize] = 0.0f64
    o[16usize] = 0.2533f64
    o[17usize] = 0.5244f64
    o[18usize] = 0.8416f64
    o[19usize] = 1.2816f64
    o[20usize] = 1.4395f64
    o[21usize] = 1.6449f64
    o[22usize] = 1.96f64
    o[23usize] = 2.3263f64
    o[24usize] = 2.4324f64
    o[25usize] = 2.5758f64
    o[26usize] = 2.807f64
    o[27usize] = 3.0902f64
    o[28usize] = 3.1747f64
    o[29usize] = 3.2905f64
    o[30usize] = 3.4808f64
    o[31usize] = 3.719f64
    o[32usize] = 3.7911f64
    o[33usize] = 3.8906f64
    o[34usize] = 4.0556f64
    o[35usize] = 4.2649f64
}

fn adk1_fill(o: []f64) {
    adk1_row0(o[0usize..36usize])
    adk1_row1(o[36usize..72usize])
    adk1_row2(o[72usize..108usize])
    adk1_row3(o[108usize..144usize])
    adk1_row4(o[144usize..180usize])
    adk1_row5(o[180usize..216usize])
    adk1_row6(o[216usize..252usize])
    adk1_row7(o[252usize..288usize])
}

fn adk2_row0(o: []f64) {
    o[0usize] = 1.0f64
    o[1usize] = (0.0f64 - 1.1976f64)
    o[2usize] = (0.0f64 - 1.1806f64)
    o[3usize] = (0.0f64 - 1.1681f64)
    o[4usize] = (0.0f64 - 1.1427f64)
    o[5usize] = (0.0f64 - 1.1272f64)
    o[6usize] = (0.0f64 - 1.0794f64)
    o[7usize] = (0.0f64 - 1.0504f64)
    o[8usize] = (0.0f64 - 0.999f64)
    o[9usize] = (0.0f64 - 0.9428f64)
    o[10usize] = (0.0f64 - 0.8991f64)
    o[11usize] = (0.0f64 - 0.8607f64)
    o[12usize] = (0.0f64 - 0.7264f64)
    o[13usize] = (0.0f64 - 0.597f64)
    o[14usize] = (0.0f64 - 0.4574f64)
    o[15usize] = (0.0f64 - 0.2966f64)
    o[16usize] = (0.0f64 - 0.1007f64)
    o[17usize] = 0.1573f64
    o[18usize] = 0.5363f64
    o[19usize] = 1.2263f64
    o[20usize] = 1.5274f64
    o[21usize] = 1.9644f64
    o[22usize] = 2.7334f64
    o[23usize] = 3.7851f64
    o[24usize] = 4.1255f64
    o[25usize] = 4.6067f64
    o[26usize] = 5.4121f64
    o[27usize] = 6.5f64
    o[28usize] = 6.8324f64
    o[29usize] = 7.278f64
    o[30usize] = 8.1926f64
    o[31usize] = 9.3096f64
    o[32usize] = 9.6207f64
    o[33usize] = 10.1076f64
    o[34usize] = 10.8874f64
    o[35usize] = 11.8602f64
}

fn adk2_row1(o: []f64) {
    o[0usize] = 2.0f64
    o[1usize] = (0.0f64 - 1.5824f64)
    o[2usize] = (0.0f64 - 1.5416f64)
    o[3usize] = (0.0f64 - 1.5212f64)
    o[4usize] = (0.0f64 - 1.4677f64)
    o[5usize] = (0.0f64 - 1.4387f64)
    o[6usize] = (0.0f64 - 1.3518f64)
    o[7usize] = (0.0f64 - 1.2997f64)
    o[8usize] = (0.0f64 - 1.2109f64)
    o[9usize] = (0.0f64 - 1.1196f64)
    o[10usize] = (0.0f64 - 1.05f64)
    o[11usize] = (0.0f64 - 0.9911f64)
    o[12usize] = (0.0f64 - 0.7944f64)
    o[13usize] = (0.0f64 - 0.6173f64)
    o[14usize] = (0.0f64 - 0.4385f64)
    o[15usize] = (0.0f64 - 0.2427f64)
    o[16usize] = (0.0f64 - 0.0168f64)
    o[17usize] = 0.2638f64
    o[18usize] = 0.6501f64
    o[19usize] = 1.2997f64
    o[20usize] = 1.5686f64
    o[21usize] = 1.944f64
    o[22usize] = 2.5915f64
    o[23usize] = 3.4443f64
    o[24usize] = 3.7175f64
    o[25usize] = 4.0869f64
    o[26usize] = 4.7248f64
    o[27usize] = 5.5856f64
    o[28usize] = 5.8302f64
    o[29usize] = 6.1999f64
    o[30usize] = 6.8586f64
    o[31usize] = 7.6673f64
    o[32usize] = 7.929f64
    o[33usize] = 8.2437f64
    o[34usize] = 8.9034f64
    o[35usize] = 9.5499f64
}

fn adk2_row2(o: []f64) {
    o[0usize] = 3.0f64
    o[1usize] = (0.0f64 - 1.8195f64)
    o[2usize] = (0.0f64 - 1.7747f64)
    o[3usize] = (0.0f64 - 1.7479f64)
    o[4usize] = (0.0f64 - 1.6724f64)
    o[5usize] = (0.0f64 - 1.6325f64)
    o[6usize] = (0.0f64 - 1.5112f64)
    o[7usize] = (0.0f64 - 1.4425f64)
    o[8usize] = (0.0f64 - 1.3259f64)
    o[9usize] = (0.0f64 - 1.2098f64)
    o[10usize] = (0.0f64 - 1.1241f64)
    o[11usize] = (0.0f64 - 1.0518f64)
    o[12usize] = (0.0f64 - 0.8192f64)
    o[13usize] = (0.0f64 - 0.6179f64)
    o[14usize] = (0.0f64 - 0.4191f64)
    o[15usize] = (0.0f64 - 0.2078f64)
    o[16usize] = 0.0305f64
    o[17usize] = 0.3171f64
    o[18usize] = 0.6996f64
    o[19usize] = 1.3209f64
    o[20usize] = 1.5716f64
    o[21usize] = 1.92f64
    o[22usize] = 2.5013f64
    o[23usize] = 3.2595f64
    o[24usize] = 3.4997f64
    o[25usize] = 3.8363f64
    o[26usize] = 4.4032f64
    o[27usize] = 5.1469f64
    o[28usize] = 5.3678f64
    o[29usize] = 5.674f64
    o[30usize] = 6.2082f64
    o[31usize] = 6.8522f64
    o[32usize] = 7.1051f64
    o[33usize] = 7.4349f64
    o[34usize] = 7.8991f64
    o[35usize] = 8.5596f64
}

fn adk2_row3(o: []f64) {
    o[0usize] = 4.0f64
    o[1usize] = (0.0f64 - 2.005f64)
    o[2usize] = (0.0f64 - 1.9434f64)
    o[3usize] = (0.0f64 - 1.9078f64)
    o[4usize] = (0.0f64 - 1.8115f64)
    o[5usize] = (0.0f64 - 1.7629f64)
    o[6usize] = (0.0f64 - 1.6187f64)
    o[7usize] = (0.0f64 - 1.5362f64)
    o[8usize] = (0.0f64 - 1.4014f64)
    o[9usize] = (0.0f64 - 1.2677f64)
    o[10usize] = (0.0f64 - 1.1697f64)
    o[11usize] = (0.0f64 - 1.0883f64)
    o[12usize] = (0.0f64 - 0.8315f64)
    o[13usize] = (0.0f64 - 0.6141f64)
    o[14usize] = (0.0f64 - 0.4034f64)
    o[15usize] = (0.0f64 - 0.1844f64)
    o[16usize] = 0.0596f64
    o[17usize] = 0.3482f64
    o[18usize] = 0.7249f64
    o[19usize] = 1.3258f64
    o[20usize] = 1.5667f64
    o[21usize] = 1.8983f64
    o[22usize] = 2.4457f64
    o[23usize] = 3.1436f64
    o[24usize] = 3.3661f64
    o[25usize] = 3.6724f64
    o[26usize] = 4.1812f64
    o[27usize] = 4.8683f64
    o[28usize] = 5.0769f64
    o[29usize] = 5.3661f64
    o[30usize] = 5.8524f64
    o[31usize] = 6.4825f64
    o[32usize] = 6.6763f64
    o[33usize] = 6.9593f64
    o[34usize] = 7.4543f64
    o[35usize] = 8.0315f64
}

fn adk2_row4(o: []f64) {
    o[0usize] = 6.0f64
    o[1usize] = (0.0f64 - 2.2546f64)
    o[2usize] = (0.0f64 - 2.1687f64)
    o[3usize] = (0.0f64 - 2.1268f64)
    o[4usize] = (0.0f64 - 2.0059f64)
    o[5usize] = (0.0f64 - 1.9405f64)
    o[6usize] = (0.0f64 - 1.7617f64)
    o[7usize] = (0.0f64 - 1.6632f64)
    o[8usize] = (0.0f64 - 1.4981f64)
    o[9usize] = (0.0f64 - 1.3386f64)
    o[10usize] = (0.0f64 - 1.2253f64)
    o[11usize] = (0.0f64 - 1.1321f64)
    o[12usize] = (0.0f64 - 0.8437f64)
    o[13usize] = (0.0f64 - 0.6074f64)
    o[14usize] = (0.0f64 - 0.3835f64)
    o[15usize] = (0.0f64 - 0.1548f64)
    o[16usize] = 0.0934f64
    o[17usize] = 0.3825f64
    o[18usize] = 0.753f64
    o[19usize] = 1.3309f64
    o[20usize] = 1.5565f64
    o[21usize] = 1.8647f64
    o[22usize] = 2.3671f64
    o[23usize] = 3.0046f64
    o[24usize] = 3.2011f64
    o[25usize] = 3.4729f64
    o[26usize] = 3.9369f64
    o[27usize] = 4.552f64
    o[28usize] = 4.7332f64
    o[29usize] = 5.0001f64
    o[30usize] = 5.4265f64
    o[31usize] = 5.9934f64
    o[32usize] = 6.1548f64
    o[33usize] = 6.3923f64
    o[34usize] = 6.9017f64
    o[35usize] = 7.4425f64
}

fn adk2_row5(o: []f64) {
    o[0usize] = 8.0f64
    o[1usize] = (0.0f64 - 2.422f64)
    o[2usize] = (0.0f64 - 2.3301f64)
    o[3usize] = (0.0f64 - 2.2827f64)
    o[4usize] = (0.0f64 - 2.1363f64)
    o[5usize] = (0.0f64 - 2.0649f64)
    o[6usize] = (0.0f64 - 1.8545f64)
    o[7usize] = (0.0f64 - 1.7387f64)
    o[8usize] = (0.0f64 - 1.5561f64)
    o[9usize] = (0.0f64 - 1.3795f64)
    o[10usize] = (0.0f64 - 1.2557f64)
    o[11usize] = (0.0f64 - 1.1555f64)
    o[12usize] = (0.0f64 - 0.8473f64)
    o[13usize] = (0.0f64 - 0.5989f64)
    o[14usize] = (0.0f64 - 0.3677f64)
    o[15usize] = (0.0f64 - 0.1347f64)
    o[16usize] = 0.1157f64
    o[17usize] = 0.404f64
    o[18usize] = 0.7685f64
    o[19usize] = 1.329f64
    o[20usize] = 1.5453f64
    o[21usize] = 1.8396f64
    o[22usize] = 2.3162f64
    o[23usize] = 2.9111f64
    o[24usize] = 3.0939f64
    o[25usize] = 3.3463f64
    o[26usize] = 3.7819f64
    o[27usize] = 4.3284f64
    o[28usize] = 4.4933f64
    o[29usize] = 4.7147f64
    o[30usize] = 5.115f64
    o[31usize] = 5.6135f64
    o[32usize] = 5.8229f64
    o[33usize] = 6.0136f64
    o[34usize] = 6.4568f64
    o[35usize] = 6.9537f64
}

fn adk2_row6(o: []f64) {
    o[0usize] = 10.0f64
    o[1usize] = (0.0f64 - 2.5292f64)
    o[2usize] = (0.0f64 - 2.438f64)
    o[3usize] = (0.0f64 - 2.3937f64)
    o[4usize] = (0.0f64 - 2.2359f64)
    o[5usize] = (0.0f64 - 2.1527f64)
    o[6usize] = (0.0f64 - 1.9182f64)
    o[7usize] = (0.0f64 - 1.7943f64)
    o[8usize] = (0.0f64 - 1.5945f64)
    o[9usize] = (0.0f64 - 1.4054f64)
    o[10usize] = (0.0f64 - 1.2758f64)
    o[11usize] = (0.0f64 - 1.1698f64)
    o[12usize] = (0.0f64 - 0.8498f64)
    o[13usize] = (0.0f64 - 0.5942f64)
    o[14usize] = (0.0f64 - 0.3588f64)
    o[15usize] = (0.0f64 - 0.1224f64)
    o[16usize] = 0.1295f64
    o[17usize] = 0.4168f64
    o[18usize] = 0.7773f64
    o[19usize] = 1.326f64
    o[20usize] = 1.536f64
    o[21usize] = 1.8216f64
    o[22usize] = 2.2827f64
    o[23usize] = 2.8585f64
    o[24usize] = 3.0318f64
    o[25usize] = 3.278f64
    o[26usize] = 3.6977f64
    o[27usize] = 4.2229f64
    o[28usize] = 4.3654f64
    o[29usize] = 4.5956f64
    o[30usize] = 4.9571f64
    o[31usize] = 5.5147f64
    o[32usize] = 5.7358f64
    o[33usize] = 5.9573f64
    o[34usize] = 6.2723f64
    o[35usize] = 6.6213f64
}

fn adk2_row7(o: []f64) {
    o[0usize] = (1.0f64 / 0.0f64)
    o[1usize] = (0.0f64 - 4.2649f64)
    o[2usize] = (0.0f64 - 3.8906f64)
    o[3usize] = (0.0f64 - 3.719f64)
    o[4usize] = (0.0f64 - 3.2905f64)
    o[5usize] = (0.0f64 - 3.0902f64)
    o[6usize] = (0.0f64 - 2.5758f64)
    o[7usize] = (0.0f64 - 2.3263f64)
    o[8usize] = (0.0f64 - 1.96f64)
    o[9usize] = (0.0f64 - 1.6449f64)
    o[10usize] = (0.0f64 - 1.4395f64)
    o[11usize] = (0.0f64 - 1.2816f64)
    o[12usize] = (0.0f64 - 0.8416f64)
    o[13usize] = (0.0f64 - 0.5244f64)
    o[14usize] = (0.0f64 - 0.2533f64)
    o[15usize] = 0.0f64
    o[16usize] = 0.2533f64
    o[17usize] = 0.5244f64
    o[18usize] = 0.8416f64
    o[19usize] = 1.2816f64
    o[20usize] = 1.4395f64
    o[21usize] = 1.6449f64
    o[22usize] = 1.96f64
    o[23usize] = 2.3263f64
    o[24usize] = 2.4324f64
    o[25usize] = 2.5758f64
    o[26usize] = 2.807f64
    o[27usize] = 3.0902f64
    o[28usize] = 3.1747f64
    o[29usize] = 3.2905f64
    o[30usize] = 3.4808f64
    o[31usize] = 3.719f64
    o[32usize] = 3.7911f64
    o[33usize] = 3.8906f64
    o[34usize] = 4.0556f64
    o[35usize] = 4.2649f64
}

fn adk2_fill(o: []f64) {
    adk2_row0(o[0usize..36usize])
    adk2_row1(o[36usize..72usize])
    adk2_row2(o[72usize..108usize])
    adk2_row3(o[108usize..144usize])
    adk2_row4(o[144usize..180usize])
    adk2_row5(o[180usize..216usize])
    adk2_row6(o[216usize..252usize])
    adk2_row7(o[252usize..288usize])
}


// ad.pval(tx, m, version) of kSamples
fn ad_pval(a: *mem.Arena, tx: f64, m: f64, version: usize) -> f64 {
    let (tab, e1) = mem.alloc[f64](a, 8usize * 36usize)
    let (xs, e2) = mem.alloc[f64](a, 8usize)
    let (ys, e3) = mem.alloc[f64](a, 8usize)
    let (ws, e4) = mem.alloc[f64](a, 8usize)
    let (tm, e5) = mem.alloc[f64](a, 35usize)
    let (lp, e6) = mem.alloc[f64](a, 35usize)
    let (w2, e7) = mem.alloc[f64](a, 35usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret 0.0f64 / 0.0f64 }
    if version == 1usize { adk1_fill(tab) } else { adk2_fill(tab) }
    // the table is column-major in R; here row r holds the 36 values of row r
    var i = 0usize
    while i < 8usize {
        // ascending in x = 1 / sqrt(m): the rows run from m = 1 to Inf, so reverse them
        let src = 7usize - i
        xs[i] = 1.0f64 / math.sqrt[f64](tab[src * 36usize])
        ws[i] = 1.0f64
        i += 1usize
    }
    let sqm0 = 1.0f64 / math.sqrt[f64](m)
    var q = 0usize
    while q < 35usize {
        i = 0usize
        while i < 8usize {
            ys[i] = tab[(7usize - i) * 36usize + 1usize + q]
            i += 1usize
        }
        var f: sm.SmSpline = zero
        if sm.fit(a, xs, ys, ws, 0.4f64, &f) != ok { ret 0.0f64 / 0.0f64 }
        tm[q] = sm.predict(a, &f, sqm0)
        let p = 1.0f64 - adk_q(q)
        lp[q] = math.log[f64](p / (1.0f64 - p))
        w2[q] = 1.0f64
        q += 1usize
    }
    // sort (tm, lp) by tm
    i = 1usize
    while i < 35usize {
        let kt = tm[i]
        let kl = lp[i]
        var j = i
        while j > 0usize && tm[j - 1usize] > kt {
            tm[j] = tm[j - 1usize]
            lp[j] = lp[j - 1usize]
            j -= 1usize
        }
        tm[j] = kt
        lp[j] = kl
        i += 1usize
    }
    var f2: sm.SmSpline = zero
    if sm.fit(a, tm, lp, w2, 0.25f64, &f2) != ok { ret 0.0f64 / 0.0f64 }
    let l0 = sm.predict(a, &f2, tx)
    ret math.exp[f64](l0) / (1.0f64 + math.exp[f64](l0))
}

// ---- qn.test (Kruskal-Wallis and van der Waerden scores): the standardised statistic and its chi-square p value ----

// the scores of every observation, tied observations averaging the scores of the positions they cover; test 0 KW (1..n), 1 vdW (qnorm(i / (n + 1)))
fn qn_scores(a: *mem.Arena, x: []const f64, test: usize, out: []f64) -> err {
    let n = x.len
    let (sc, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        if test == 0usize { sc[i] = f64(i + 1usize) } else { sc[i] = mdist.qnorm(f64(i + 1usize) / (f64(n) + 1.0f64), 0.0f64, 1.0f64, true, false) }
        i += 1usize
    }
    i = 0usize
    while i < n {
        // the tied group of x[i]: positions among the sorted values
        var below = 0usize
        var equal = 0usize
        var j = 0usize
        while j < n {
            if x[j] < x[i] { below += 1usize }
            if x[j] == x[i] { equal += 1usize }
            j += 1usize
        }
        var s = 0.0f64
        var t = 0usize
        while t < equal {
            s += sc[below + t]
            t += 1usize
        }
        out[i] = s / f64(equal)
        i += 1usize
    }
    ret ok
}

// qn.test(..., test = "KW" or "vdW", method = "asymptotic"): the statistic (sum of S_i^2 / n_i - n mean^2) / var, and the chi-square p value on k - 1 degrees of freedom; part 0 the statistic, 1 the p value
fn qn_test(a: *mem.Arena, x: []const f64, sizes: []const usize, test: usize, part: usize) -> f64 {
    let n = x.len
    let k = sizes.len
    let (rx, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if qn_scores(a, x, test, rx) != ok { ret 0.0f64 / 0.0f64 }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += rx[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (rx[i] - mean) * (rx[i] - mean)
        i += 1usize
    }
    let svar = ss / f64(n - 1usize)
    var q = 0.0f64
    var at = 0usize
    var g = 0usize
    while g < k {
        var s = 0.0f64
        var j = 0usize
        while j < sizes[g] {
            s += rx[at + j]
            j += 1usize
        }
        q += s * s / f64(sizes[g])
        at += sizes[g]
        g += 1usize
    }
    // the package rounds the sum of squared sample score totals to eight decimals before standardising
    q = math.floor[f64](q * 1.0e8f64 + 0.5f64) / 1.0e8f64
    let stat = (q - f64(n) * mean * mean) / svar
    if part == 0usize { ret stat }
    ret 1.0f64 - nm.pchisq(stat, f64(k - 1usize), true, false)
}

// ---- contingency2xt: the Kruskal-Wallis type statistic of a 2 by t table of counts (rows Avec and Bvec) ----

// the observed statistic (N (N - 1) / (m n)) (sum A_i^2 / d_i - m^2 / N) and its chi-square p value on t - 1 degrees of freedom; part 0 the statistic, 1 the asymptotic p value
fn contingency2xt(avec: []const f64, bvec: []const f64, part: usize) -> f64 {
    var m = 0.0f64
    var n = 0.0f64
    var s = 0.0f64
    var i = 0usize
    while i < avec.len {
        m += avec[i]
        n += bvec[i]
        i += 1usize
    }
    let nn = m + n
    i = 0usize
    while i < avec.len {
        s += avec[i] * avec[i] / (avec[i] + bvec[i])
        i += 1usize
    }
    let kw = nn * (nn - 1.0f64) / (m * n) * (s - m * m / nn)
    if part == 0usize { ret kw }
    ret 1.0f64 - nm.pchisq(kw, f64(avec.len - 1usize), true, false)
}

type C2Ctx = struct { d: []const f64, t: usize, m: f64, nn: f64, lc: f64, obs: f64, pval: f64, cur: []f64 }

fn lchoose_f(n: f64, k: f64) -> f64 { ret nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64) }

fn c2_walk(c: *C2Ctx, pos: usize, rem: f64) {
    if pos + 1usize == c.t {
        if rem > c.d[pos] { ret }
        c.cur[pos] = rem
        var s = 0.0f64
        var lp = 0.0f64 - c.lc
        var i = 0usize
        while i < c.t {
            s += c.cur[i] * c.cur[i] / c.d[i]
            lp += lchoose_f(c.d[i], c.cur[i])
            i += 1usize
        }
        if s >= c.obs { c.pval += math.exp[f64](lp) }
        ret
    }
    var v = 0.0f64
    while v <= c.d[pos] && v <= rem {
        c.cur[pos] = v
        c2_walk(c, pos + 1usize, rem - v)
        v += 1.0f64
    }
}

// the exact p value: the multivariate hypergeometric probability of the first-row vectors whose sum A_i^2 / d_i is at least the observed
fn contingency2xt_exact(a: *mem.Arena, avec: []const f64, bvec: []const f64) -> f64 {
    let t = avec.len
    let (d, e1) = mem.alloc[f64](a, t)
    let (cur, e2) = mem.alloc[f64](a, t)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var m = 0.0f64
    var nn = 0.0f64
    var obs = 0.0f64
    var i = 0usize
    while i < t {
        d[i] = avec[i] + bvec[i]
        m += avec[i]
        nn += d[i]
        obs += avec[i] * avec[i] / d[i]
        i += 1usize
    }
    var ctx = C2Ctx{ d: d, t: t, m: m, nn: nn, lc: lchoose_f(nn, m), obs: obs, pval: 0.0f64, cur: cur }
    c2_walk(&ctx, 0usize, m)
    ret ctx.pval
}

// ---- ad.test exact p value: every assignment of the pooled observations to the samples ----

type AdxCtx = struct { x: []const f64, sizes: []const usize, version: usize, n: usize, k: usize, left: []usize, grp: []usize, xp: []f64, obs: f64, tol: f64, hit: f64, total: f64, arena: *mem.Arena }

fn adx_walk(c: *AdxCtx, pos: usize) {
    if pos == c.n {
        // lay the observations out sample by sample
        var off = 0usize
        var g = 0usize
        while g < c.k {
            var j = 0usize
            var q = 0usize
            while q < c.n {
                if c.grp[q] == g {
                    c.xp[off + j] = c.x[q]
                    j += 1usize
                }
                q += 1usize
            }
            off += c.sizes[g]
            g += 1usize
        }
        let start = mem.mark(c.arena)
        let st = ad_test(c.arena, c.xp, c.sizes, c.version, 0usize)
        mem.reset(c.arena, start)
        c.total += 1.0f64
        if st >= c.obs - c.tol { c.hit += 1.0f64 }
        ret
    }
    var g = 0usize
    while g < c.k {
        if c.left[g] > 0usize {
            c.left[g] -= 1usize
            c.grp[pos] = g
            adx_walk(c, pos + 1usize)
            c.left[g] += 1usize
        }
        g += 1usize
    }
}

// ad.test(method = "exact") p value of the AD statistic (version 1 or 2) for the samples stored back to back in x
fn ad_exact_p(a: *mem.Arena, x: []const f64, sizes: []const usize, version: usize, tol: f64) -> f64 {
    let n = x.len
    let k = sizes.len
    let (left, e1) = mem.alloc[usize](a, k)
    let (grp, e2) = mem.alloc[usize](a, n)
    let (xp, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var g = 0usize
    while g < k {
        left[g] = sizes[g]
        g += 1usize
    }
    let obs = ad_test(a, x, sizes, version, 0usize)
    var ctx = AdxCtx{ x: x, sizes: sizes, version: version, n: n, k: k, left: left, grp: grp, xp: xp, obs: obs, tol: tol, hit: 0.0f64, total: 0.0f64, arena: a }
    adx_walk(&ctx, 0usize)
    ret ctx.hit / ctx.total
}
