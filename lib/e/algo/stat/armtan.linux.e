// tan as R computes it on Linux: libm's own. See armtan.e.

@import("libm.so.6", "tan")
extern fn raw_tan(x: f64) -> f64

fn tan_c(x: f64) -> f64 { ret raw_tan(x) }



@import("libm.so.6", "atan")
extern fn raw_atan(x: f64) -> f64

fn atan_c(x: f64) -> f64 { ret raw_atan(x) }

// pcauchy(x), lower tail, no log, with the atan R calls
fn pcauchy_c(x: f64) -> f64 {
    if x != x { ret x }
    var ax = x
    if x < 0.0f64 { ax = 0.0f64 - x }
    if ax > 1.0f64 {
        let y = atan_c(1.0f64 / x) / 3.141592653589793238462643383280f64
        if x > 0.0f64 { ret (0.5f64 - y) + 0.5f64 }
        ret 0.0f64 - y
    }
    ret 0.5f64 + atan_c(x) / 3.141592653589793238462643383280f64
}
