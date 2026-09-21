// `e.ml.linear`: ordinary least squares, ridge and lasso on a seven-sample
// two-feature set against scikit-learn's coefficients, logistic regression
// by Newton's method against scikit-learn at the same penalty with its
// predicted probabilities, and the singular and storage cases. Each check
// exits with its own code.

use e.io
use e.mem
use e.ml.linear
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [14]f64 = zero
    x[0usize] = 1.0f64
    x[1usize] = 2.0f64
    x[2usize] = 2.0f64
    x[3usize] = 1.0f64
    x[4usize] = 3.0f64
    x[5usize] = 4.0f64
    x[6usize] = 4.0f64
    x[7usize] = 3.0f64
    x[8usize] = 5.0f64
    x[9usize] = 6.0f64
    x[10usize] = 6.0f64
    x[11usize] = 5.0f64
    x[12usize] = 7.0f64
    x[13usize] = 8.0f64
    var y: [7]f64 = zero
    y[0usize] = 3.1f64
    y[1usize] = 3.9f64
    y[2usize] = 7.2f64
    y[3usize] = 8.1f64
    y[4usize] = 10.8f64
    y[5usize] = 12.1f64
    y[6usize] = 15.2f64
    var coefficients: [3]f64 = zero
    var scratch: [32]f64 = zero

    // 1: OLS and ridge.
    if linear.ols(x[..], y[..], 7usize, 2usize, coefficients[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(coefficients[0usize], 1.48988095f64, 0.0000001f64) || !near(coefficients[1usize], 0.52083333f64, 0.0000001f64) || !near(coefficients[2usize], 0.51130952f64, 0.0000001f64) { os.exit(1i32) }
    if !near(linear.predict(x[..], 2usize, 0usize, coefficients[..]), 1.48988095f64 + 2.0f64 * 0.52083333f64 + 0.51130952f64, 0.000001f64) { os.exit(1i32) }
    if linear.ridge(x[..], y[..], 7usize, 2usize, 1.0f64, coefficients[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(coefficients[0usize], 1.33807929f64, 0.0000001f64) || !near(coefficients[1usize], 0.62484645f64, 0.0000001f64) || !near(coefficients[2usize], 0.68760469f64, 0.0000001f64) { os.exit(1i32) }
    // A duplicated feature makes the normal equations singular.
    var dup: [14]f64 = zero
    var i = 0usize
    while i < 7usize {
        dup[2usize * i] = x[2usize * i]
        dup[2usize * i + 1usize] = x[2usize * i]
        i += 1usize
    }
    if linear.ols(dup[..], y[..], 7usize, 2usize, coefficients[..], scratch[..]) != linear.Singular { os.exit(1i32) }
    if linear.ridge(dup[..], y[..], 7usize, 2usize, 0.1f64, coefficients[..], scratch[..]) != ok { os.exit(1i32) }
    if linear.ols(x[..], y[..], 7usize, 2usize, coefficients[..], scratch[..8usize]) != linear.TooSmall { os.exit(1i32) }
    if linear.ridge(x[..], y[..], 7usize, 2usize, 0.0f64 - 1.0f64, coefficients[..], scratch[..]) != linear.Invalid { os.exit(1i32) }

    // 2: lasso.
    if linear.lasso(x[..], y[..], 7usize, 2usize, 0.5f64, 0.000000000001f64, 100000u32, coefficients[..], scratch[..]) != ok { os.exit(2i32) }
    if !near(coefficients[0usize], 1.36488095f64, 0.000001f64) || !near(coefficients[1usize], 0.52083333f64, 0.000001f64) || !near(coefficients[2usize], 1.01130952f64, 0.000001f64) { os.exit(2i32) }
    // A large penalty zeroes the features and leaves the mean.
    if linear.lasso(x[..], y[..], 7usize, 2usize, 100.0f64, 0.000000000001f64, 1000u32, coefficients[..], scratch[..]) != ok { os.exit(2i32) }
    if coefficients[0usize] != 0.0f64 || coefficients[1usize] != 0.0f64 || !near(coefficients[2usize], 8.62857143f64, 0.0000001f64) { os.exit(2i32) }
    if linear.lasso(x[..], y[..], 7usize, 2usize, 0.5f64, 0.001f64, 10u32, coefficients[..], scratch[..3usize]) != linear.TooSmall { os.exit(2i32) }

    // 3: logistic regression.
    var xc: [16]f64 = zero
    xc[2usize] = 1.0f64
    xc[5usize] = 1.0f64
    xc[6usize] = 1.0f64
    xc[7usize] = 1.0f64
    xc[8usize] = 2.0f64
    xc[9usize] = 2.0f64
    xc[10usize] = 3.0f64
    xc[11usize] = 2.0f64
    xc[12usize] = 2.0f64
    xc[13usize] = 3.0f64
    xc[14usize] = 3.0f64
    xc[15usize] = 3.0f64
    var yc: [8]f64 = zero
    yc[4usize] = 1.0f64
    yc[5usize] = 1.0f64
    yc[6usize] = 1.0f64
    yc[7usize] = 1.0f64
    let (iterations, fit_error) = linear.logistic(xc[..], yc[..], 8usize, 2usize, 1.0f64, 0.000000001f64, 100u32, coefficients[..], scratch[..])
    if fit_error != ok || iterations == 0u32 || iterations > 20u32 { os.exit(3i32) }
    if !near(coefficients[0usize], 0.95520996f64, 0.000001f64) || !near(coefficients[1usize], 0.95520996f64, 0.000001f64) || !near(coefficients[2usize], 0.0f64 - 2.86562989f64, 0.000001f64) { os.exit(3i32) }
    var query: [6]f64 = zero
    query[0usize] = 1.5f64
    query[1usize] = 1.5f64
    query[4usize] = 3.0f64
    query[5usize] = 3.0f64
    if !near(linear.predict_probability(query[..], 2usize, 0usize, coefficients[..]), 0.5f64, 0.000001f64) { os.exit(3i32) }
    if !near(linear.predict_probability(query[..], 2usize, 1usize, coefficients[..]), 0.05387899f64, 0.000001f64) { os.exit(3i32) }
    if !near(linear.predict_probability(query[..], 2usize, 2usize, coefficients[..]), 0.94612101f64, 0.000001f64) { os.exit(3i32) }
    // Separable data with no penalty diverges; with a tiny one it converges to a steep boundary.
    let (steep, steep_error) = linear.logistic(xc[..], yc[..], 8usize, 2usize, 0.0001f64, 0.000001f64, 200u32, coefficients[..], scratch[..])
    if steep_error != ok || steep == 200u32 || coefficients[0usize] < 3.0f64 { os.exit(3i32) }
    let (_, invalid) = linear.logistic(xc[..], yc[..], 8usize, 2usize, 0.0f64 - 1.0f64, 0.000001f64, 10u32, coefficients[..], scratch[..])
    if invalid != linear.Invalid { os.exit(3i32) }

    try io.print("ml linear ok\n")
    ret ok
}
