// R pbivnorm: the bivariate normal distribution function P(X <= x, Y <= y) at correlation rho, by Genz
// and Ge's modification of Drezner and Wesolowsky (MVBVU), with 6, 12 or 20 point Gauss-Legendre rules
// by the size of rho, and Schonfelder's normal distribution function (MVPHI), as pbivnorm calls them.
//
// Not here: the bivariate Student t (mvbvt) and the other limits flags of MVBVN.

use e.math

fn mvphi(z: f64) -> f64 {
    var a: [25]f64 = zero
    a[0usize] = 0.610143081923200417926465815756f64
    a[1usize] = 0.0f64 - 0.434841272712577471828182820888f64
    a[2usize] = 0.176351193643605501125840298123f64
    a[3usize] = 0.0f64 - 0.060710795609249414860051215825f64
    a[4usize] = 0.017712068995694114486147141191f64
    a[5usize] = 0.0f64 - 0.004321119385567293818599864968f64
    a[6usize] = 0.000854216676887098678819832055f64
    a[7usize] = 0.0f64 - 0.000127155090609162742628893940f64
    a[8usize] = 0.000011248167243671189468847072f64
    a[9usize] = 3.13063885421820972630152e-7f64
    a[10usize] = 0.0f64 - 2.70988068537762022009086e-7f64
    a[11usize] = 3.0737622701407688440959e-8f64
    a[12usize] = 2.515620384817622937314e-9f64
    a[13usize] = 0.0f64 - 1.028929921320319127590e-9f64
    a[14usize] = 2.9944052119949939363e-11f64
    a[15usize] = 2.6051789687266936290e-11f64
    a[16usize] = 0.0f64 - 2.634839924171969386e-12f64
    a[17usize] = 0.0f64 - 6.43404509890636443e-13f64
    a[18usize] = 1.12457401801663447e-13f64
    a[19usize] = 1.7281533389986098e-14f64
    a[20usize] = 0.0f64 - 4.264101694942375e-15f64
    a[21usize] = 0.0f64 - 5.45371977880191e-16f64
    a[22usize] = 1.58697607761671e-16f64
    a[23usize] = 2.0899837844334e-17f64
    a[24usize] = 0.0f64 - 5.900526869409e-18f64
    var za = z
    if za < 0.0f64 { za = 0.0f64 - za }
    let xa = za / 1.414213562373095048801688724209f64
    var p = 0.0f64
    if !(xa > 100.0f64) {
        let t = (8.0f64 * xa - 30.0f64) / (4.0f64 * xa + 15.0f64)
        var bm = 0.0f64
        var b = 0.0f64
        var bp = 0.0f64
        var i = 24i64
        while i >= 0i64 {
            bp = b
            b = bm
            bm = t * b - bp + a[usize(i)]
            i -= 1i64
        }
        p = math.exp[f64](0.0f64 - xa * xa) * (bm - bp) / 4.0f64
    }
    if z > 0.0f64 { p = 1.0f64 - p }
    ret p
}

// the Gauss-Legendre half rules: weights and (negative) nodes for 6, 12 and 20 points
fn rule(ng: usize, w: []f64, x: []f64) {
    if ng == 0usize {
        w[0usize] = 0.1713244923791705f64
        x[0usize] = 0.0f64 - 0.9324695142031522f64
        w[1usize] = 0.3607615730481384f64
        x[1usize] = 0.0f64 - 0.6612093864662647f64
        w[2usize] = 0.4679139345726904f64
        x[2usize] = 0.0f64 - 0.2386191860831970f64
    } else if ng == 1usize {
        w[0usize] = 0.04717533638651177f64
        x[0usize] = 0.0f64 - 0.9815606342467191f64
        w[1usize] = 0.1069393259953183f64
        x[1usize] = 0.0f64 - 0.9041172563704750f64
        w[2usize] = 0.1600783285433464f64
        x[2usize] = 0.0f64 - 0.7699026741943050f64
        w[3usize] = 0.2031674267230659f64
        x[3usize] = 0.0f64 - 0.5873179542866171f64
        w[4usize] = 0.2334925365383547f64
        x[4usize] = 0.0f64 - 0.3678314989981802f64
        w[5usize] = 0.2491470458134029f64
        x[5usize] = 0.0f64 - 0.1252334085114692f64
    } else {
        w[0usize] = 0.01761400713915212f64
        x[0usize] = 0.0f64 - 0.9931285991850949f64
        w[1usize] = 0.04060142980038694f64
        x[1usize] = 0.0f64 - 0.9639719272779138f64
        w[2usize] = 0.06267204833410906f64
        x[2usize] = 0.0f64 - 0.9122344282513259f64
        w[3usize] = 0.08327674157670475f64
        x[3usize] = 0.0f64 - 0.8391169718222188f64
        w[4usize] = 0.1019301198172404f64
        x[4usize] = 0.0f64 - 0.7463319064601508f64
        w[5usize] = 0.1181945319615184f64
        x[5usize] = 0.0f64 - 0.6360536807265150f64
        w[6usize] = 0.1316886384491766f64
        x[6usize] = 0.0f64 - 0.5108670019508271f64
        w[7usize] = 0.1420961093183821f64
        x[7usize] = 0.0f64 - 0.3737060887154196f64
        w[8usize] = 0.1491729864726037f64
        x[8usize] = 0.0f64 - 0.2277858511416451f64
        w[9usize] = 0.1527533871307259f64
        x[9usize] = 0.0f64 - 0.07652652113349733f64
    }
}

// P(X > sh, Y > sk)
fn mvbvu(sh: f64, sk: f64, r: f64) -> f64 {
    let twopi = 6.283185307179586f64
    var w: [10]f64 = zero
    var x: [10]f64 = zero
    var ng = 2usize
    var lg = 10usize
    var ar = r
    if ar < 0.0f64 { ar = 0.0f64 - ar }
    if ar < 0.3f64 {
        ng = 0usize
        lg = 3usize
    } else if ar < 0.75f64 {
        ng = 1usize
        lg = 6usize
    }
    rule(ng, w[0usize..10usize], x[0usize..10usize])
    let h = sh
    var k = sk
    var hk = h * k
    var bvn = 0.0f64
    if ar < 0.925f64 {
        let hs = (h * h + k * k) / 2.0f64
        let asr = math.asin[f64](r)
        var i = 0usize
        while i < lg {
            var sn = math.sin[f64](asr * (x[i] + 1.0f64) / 2.0f64)
            bvn += w[i] * math.exp[f64]((sn * hk - hs) / (1.0f64 - sn * sn))
            sn = math.sin[f64](asr * (0.0f64 - x[i] + 1.0f64) / 2.0f64)
            bvn += w[i] * math.exp[f64]((sn * hk - hs) / (1.0f64 - sn * sn))
            i += 1usize
        }
        bvn = bvn * asr / (2.0f64 * twopi) + mvphi(0.0f64 - h) * mvphi(0.0f64 - k)
    } else {
        if r < 0.0f64 {
            k = 0.0f64 - k
            hk = 0.0f64 - hk
        }
        if ar < 1.0f64 {
            let as2 = (1.0f64 - r) * (1.0f64 + r)
            var a = math.sqrt[f64](as2)
            let bs = (h - k) * (h - k)
            let c = (4.0f64 - hk) / 8.0f64
            let d = (12.0f64 - hk) / 16.0f64
            bvn = a * math.exp[f64](0.0f64 - (bs / as2 + hk) / 2.0f64) * (1.0f64 - c * (bs - as2) * (1.0f64 - d * bs / 5.0f64) / 3.0f64 + c * d * as2 * as2 / 5.0f64)
            if hk > 0.0f64 - 160.0f64 {
                let b = math.sqrt[f64](bs)
                bvn = bvn - math.exp[f64](0.0f64 - hk / 2.0f64) * math.sqrt[f64](twopi) * mvphi(0.0f64 - b / a) * b * (1.0f64 - c * bs * (1.0f64 - d * bs / 5.0f64) / 3.0f64)
            }
            a = a / 2.0f64
            var i = 0usize
            while i < lg {
                var xs = (a * (x[i] + 1.0f64)) * (a * (x[i] + 1.0f64))
                var rs = math.sqrt[f64](1.0f64 - xs)
                bvn = bvn + a * w[i] * (math.exp[f64](0.0f64 - bs / (2.0f64 * xs) - hk / (1.0f64 + rs)) / rs - math.exp[f64](0.0f64 - (bs / xs + hk) / 2.0f64) * (1.0f64 + c * xs * (1.0f64 + d * xs)))
                xs = as2 * (0.0f64 - x[i] + 1.0f64) * (0.0f64 - x[i] + 1.0f64) / 4.0f64
                rs = math.sqrt[f64](1.0f64 - xs)
                bvn = bvn + a * w[i] * math.exp[f64](0.0f64 - (bs / xs + hk) / 2.0f64) * (math.exp[f64](0.0f64 - hk * (1.0f64 - rs) / (2.0f64 * (1.0f64 + rs))) / rs - (1.0f64 + c * xs * (1.0f64 + d * xs)))
                i += 1usize
            }
            bvn = 0.0f64 - bvn / twopi
        }
        if r > 0.0f64 {
            var mx = h
            if k > mx { mx = k }
            bvn = bvn + mvphi(0.0f64 - mx)
        }
        if r < 0.0f64 {
            var df = mvphi(0.0f64 - h) - mvphi(0.0f64 - k)
            if df < 0.0f64 { df = 0.0f64 }
            bvn = 0.0f64 - bvn + df
        }
    }
    ret bvn
}

// pbivnorm(x, y, rho): P(X <= x, Y <= y); infinite arguments are the largest double
fn pbivnorm(x: f64, y: f64, rho: f64) -> f64 { ret mvbvu(0.0f64 - x, 0.0f64 - y, rho) }
