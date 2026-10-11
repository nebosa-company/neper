// The Earth's magnetic field (C131): the World Magnetic Model WMM2025 (NOAA and the British Geological Survey, valid
// 2025.0 to 2030.0) evaluated at a place and a date -- declination, inclination, horizontal and total intensity and
// the north, east and down components -- and a compass heading from magnetometer and accelerometer readings.
//
// `field` is the spherical-harmonic synthesis of the model (degree and order 12, secular variation applied from the
// 2025.0 epoch) as NOAA's reference code does it: the geodetic position is moved to geocentric spherical
// coordinates on the WGS84 ellipsoid, the associated Legendre functions are built by the Gauss-normalised
// recurrences and converted to Schmidt quasi-normalisation, and the components are rotated back to geodetic axes.
// Angles are in degrees, intensities in nanotesla, heights in kilometres above the ellipsoid.
//
// `heading` is the tilt-compensated heading of a device from its magnetometer and accelerometer vectors (any
// consistent units; x forward, y right, z down), and `calibrate_hard_iron` the offset that centres a set of
// magnetometer samples taken while turning the device through every direction.
use e.math

type Field = struct { declination: f64, inclination: f64, horizontal: f64, total: f64, north: f64, east: f64, down: f64 }

fn epoch() -> f64 { ret 2025.0f64 }
const DEGREE: usize = 12usize

fn deg_to_rad(d: f64) -> f64 { ret d * 3.141592653589793f64 / 180.0f64 }
fn rad_to_deg(r: f64) -> f64 { ret r * 180.0f64 / 3.141592653589793f64 }

// The Gauss coefficients by index n(n+1)/2 + m - 1 (n 1 to 12, m 0 to n): g, h and their yearly changes.
fn coefficient_g(i: usize) -> f64 {
    let t: [90]f64 = [90]f64{ -29351.8f64, -1410.8f64, -2556.6f64, 2951.1f64, 1649.3f64, 1361.0f64, -2404.1f64, 1243.8f64, 453.6f64, 895.0f64, 799.5f64, 55.7f64, -281.1f64, 12.1f64, -233.2f64, 368.9f64, 187.2f64, -138.7f64, -142.0f64, 20.9f64, 64.4f64, 63.8f64, 76.9f64, -115.7f64, -40.9f64, 14.9f64, -60.7f64, 79.5f64, -77.0f64, -8.8f64, 59.3f64, 15.8f64, 2.5f64, -11.1f64, 14.2f64, 23.2f64, 10.8f64, -17.5f64, 2.0f64, -21.7f64, 16.9f64, 15.0f64, -16.8f64, 0.9f64, 4.6f64, 7.8f64, 3.0f64, -0.2f64, -2.5f64, -13.1f64, 2.4f64, 8.6f64, -8.7f64, -12.9f64, -1.3f64, -6.4f64, 0.2f64, 2.0f64, -1.0f64, -0.6f64, -0.9f64, 1.5f64, 0.9f64, -2.7f64, -3.9f64, 2.9f64, -1.5f64, -2.5f64, 2.4f64, -0.6f64, -0.1f64, -0.6f64, -0.1f64, 1.1f64, -1.0f64, -0.2f64, 2.6f64, -2.0f64, -0.2f64, 0.3f64, 1.2f64, -1.3f64, 0.6f64, 0.6f64, 0.5f64, -0.1f64, -0.4f64, -0.2f64, -1.3f64, -0.7f64 }
    ret t[i]
}

fn coefficient_h(i: usize) -> f64 {
    let t: [90]f64 = [90]f64{ 0.0f64, 4545.4f64, 0.0f64, -3133.6f64, -815.1f64, 0.0f64, -56.6f64, 237.5f64, -549.5f64, 0.0f64, 278.6f64, -133.9f64, 212.0f64, -375.6f64, 0.0f64, 45.4f64, 220.2f64, -122.9f64, 43.0f64, 106.1f64, 0.0f64, -18.4f64, 16.8f64, 48.8f64, -59.8f64, 10.9f64, 72.7f64, 0.0f64, -48.9f64, -14.4f64, -1.0f64, 23.4f64, -7.4f64, -25.1f64, -2.3f64, 0.0f64, 7.1f64, -12.6f64, 11.4f64, -9.7f64, 12.7f64, 0.7f64, -5.2f64, 3.9f64, 0.0f64, -24.8f64, 12.2f64, 8.3f64, -3.3f64, -5.2f64, 7.2f64, -0.6f64, 0.8f64, 10.0f64, 0.0f64, 3.3f64, 0.0f64, 2.4f64, 5.3f64, -9.1f64, 0.4f64, -4.2f64, -3.8f64, 0.9f64, -9.1f64, 0.0f64, 0.0f64, 2.9f64, -0.6f64, 0.2f64, 0.5f64, -0.3f64, -1.2f64, -1.7f64, -2.9f64, -1.8f64, -2.3f64, 0.0f64, -1.3f64, 0.7f64, 1.0f64, -1.4f64, -0.0f64, 0.6f64, -0.1f64, 0.8f64, 0.1f64, -1.0f64, 0.1f64, 0.2f64 }
    ret t[i]
}

fn coefficient_g_dot(i: usize) -> f64 {
    let t: [90]f64 = [90]f64{ 12.0f64, 9.7f64, -11.6f64, -5.2f64, -8.0f64, -1.3f64, -4.2f64, 0.4f64, -15.6f64, -1.6f64, -2.4f64, -6.0f64, 5.6f64, -7.0f64, 0.6f64, 1.4f64, 0.0f64, 0.6f64, 2.2f64, 0.9f64, -0.2f64, -0.4f64, 0.9f64, 1.2f64, -0.9f64, 0.3f64, 0.9f64, -0.0f64, -0.1f64, -0.1f64, 0.5f64, -0.1f64, -0.8f64, -0.8f64, 0.8f64, -0.1f64, 0.2f64, 0.0f64, 0.5f64, -0.1f64, 0.3f64, 0.2f64, -0.0f64, 0.2f64, -0.0f64, -0.1f64, 0.1f64, 0.3f64, -0.3f64, 0.0f64, 0.3f64, -0.1f64, 0.1f64, -0.1f64, 0.1f64, 0.0f64, 0.1f64, 0.1f64, -0.0f64, -0.3f64, 0.0f64, -0.1f64, -0.1f64, -0.0f64, -0.0f64, 0.0f64, -0.0f64, 0.0f64, 0.0f64, 0.0f64, -0.1f64, 0.0f64, -0.0f64, -0.1f64, -0.1f64, -0.1f64, -0.1f64, 0.0f64, 0.0f64, -0.0f64, -0.0f64, -0.0f64, -0.0f64, 0.1f64, -0.0f64, 0.0f64, 0.0f64, -0.1f64, -0.0f64, -0.1f64 }
    ret t[i]
}

fn coefficient_h_dot(i: usize) -> f64 {
    let t: [90]f64 = [90]f64{ 0.0f64, -21.5f64, 0.0f64, -27.7f64, -12.1f64, 0.0f64, 4.0f64, -0.3f64, -4.1f64, 0.0f64, -1.1f64, 4.1f64, 1.6f64, -4.4f64, 0.0f64, -0.5f64, 2.2f64, 0.4f64, 1.7f64, 1.9f64, 0.0f64, 0.3f64, -1.6f64, -0.4f64, 0.9f64, 0.7f64, 0.9f64, 0.0f64, 0.6f64, 0.5f64, -0.8f64, 0.0f64, -1.0f64, 0.6f64, -0.2f64, 0.0f64, -0.2f64, 0.5f64, -0.4f64, 0.4f64, -0.5f64, -0.6f64, 0.3f64, 0.2f64, 0.0f64, -0.3f64, 0.3f64, -0.3f64, 0.3f64, 0.2f64, -0.1f64, -0.2f64, 0.4f64, 0.1f64, 0.0f64, 0.0f64, -0.0f64, -0.2f64, 0.1f64, -0.1f64, 0.1f64, 0.0f64, -0.1f64, 0.2f64, -0.0f64, 0.0f64, -0.0f64, 0.1f64, -0.0f64, 0.1f64, -0.0f64, -0.0f64, 0.1f64, -0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, -0.0f64, 0.0f64, -0.1f64, 0.1f64, -0.0f64, -0.0f64, -0.0f64, 0.0f64, -0.0f64, -0.0f64, 0.0f64, -0.1f64 }
    ret t[i]
}

// The field at geodetic latitude and longitude (degrees), height in km and decimal year.
fn field(latitude: f64, longitude: f64, height: f64, year: f64) -> Field {
    // WGS84 to geocentric spherical.
    let a = 6378.137f64
    let f = 1.0f64 / 298.257223563f64
    let eps2 = f * (2.0f64 - f)
    let lat = deg_to_rad(latitude)
    let lon = deg_to_rad(longitude)
    let sin_lat = math.sin[f64](lat)
    let cos_lat = math.cos[f64](lat)
    let rc = a / math.sqrt[f64](1.0f64 - eps2 * sin_lat * sin_lat)
    let xp = (rc + height) * cos_lat
    let zp = (rc * (1.0f64 - eps2) + height) * sin_lat
    let r = math.sqrt[f64](xp * xp + zp * zp)
    let phi = math.asin[f64](zp / r)
    let x = math.sin[f64](phi)
    let z = math.sqrt[f64]((1.0f64 - x) * (1.0f64 + x))
    // Legendre functions P(n, m) and dP, Gauss-normalised, in (n, m) order with a leading (0, 0).
    var p: [91]f64 = zero
    var dp: [91]f64 = zero
    p[0usize] = 1.0f64
    var n = 1usize
    while n <= DEGREE {
        var m = 0usize
        while m <= n {
            let index = n * (n + 1usize) / 2usize + m
            if n == m {
                let i1 = (n - 1usize) * n / 2usize + m - 1usize
                p[index] = z * p[i1]
                dp[index] = z * dp[i1] + x * p[i1]
            } else if n == 1usize && m == 0usize {
                let i1 = (n - 1usize) * n / 2usize + m
                p[index] = x * p[i1]
                dp[index] = x * dp[i1] - z * p[i1]
            } else {
                let i1 = (n - 2usize) * (n - 1usize) / 2usize + m
                let i2 = (n - 1usize) * n / 2usize + m
                if m > n - 2usize {
                    p[index] = x * p[i2]
                    dp[index] = x * dp[i2] - z * p[i2]
                } else {
                    let k = (f64((n - 1usize) * (n - 1usize)) - f64(m * m)) / (f64(2usize * n - 1usize) * f64(2usize * n - 3usize))
                    p[index] = x * p[i2] - k * p[i1]
                    dp[index] = x * dp[i2] - z * p[i2] - k * dp[i1]
                }
            }
            m += 1usize
        }
        n += 1usize
    }
    // Schmidt quasi-normalisation.
    var schmidt: [91]f64 = zero
    schmidt[0usize] = 1.0f64
    n = 1usize
    while n <= DEGREE {
        let index = n * (n + 1usize) / 2usize
        let i1 = (n - 1usize) * n / 2usize
        schmidt[index] = schmidt[i1] * f64(2usize * n - 1usize) / f64(n)
        var m = 1usize
        while m <= n {
            let j = n * (n + 1usize) / 2usize + m
            let j1 = n * (n + 1usize) / 2usize + m - 1usize
            var two = 1.0f64
            if m == 1usize { two = 2.0f64 }
            schmidt[j] = schmidt[j1] * math.sqrt[f64](f64(n - m + 1usize) * two / f64(n + m))
            m += 1usize
        }
        n += 1usize
    }
    n = 1usize
    while n <= DEGREE {
        var m = 0usize
        while m <= n {
            let index = n * (n + 1usize) / 2usize + m
            p[index] = p[index] * schmidt[index]
            dp[index] = 0.0f64 - dp[index] * schmidt[index]
            m += 1usize
        }
        n += 1usize
    }
    // The synthesis.
    let dt = year - epoch()
    var bx = 0.0f64
    var by = 0.0f64
    var bz = 0.0f64
    n = 1usize
    while n <= DEGREE {
        // (6371.2 km, the geomagnetic reference radius, / r)^(n + 2)
        let ratio = 6371.2f64 / r
        var radius_power = ratio * ratio
        var q = 1usize
        while q <= n {
            radius_power = radius_power * ratio
            q += 1usize
        }
        var m = 0usize
        while m <= n {
            let c = n * (n + 1usize) / 2usize + m - 1usize
            let gnm = coefficient_g(c) + dt * coefficient_g_dot(c)
            let hnm = coefficient_h(c) + dt * coefficient_h_dot(c)
            let cos_m = math.cos[f64](f64(m) * lon)
            let sin_m = math.sin[f64](f64(m) * lon)
            let index = n * (n + 1usize) / 2usize + m
            bz = bz - radius_power * (gnm * cos_m + hnm * sin_m) * f64(n + 1usize) * p[index]
            by = by + radius_power * (gnm * sin_m - hnm * cos_m) * f64(m) * p[index]
            bx = bx - radius_power * (gnm * cos_m + hnm * sin_m) * dp[index]
            m += 1usize
        }
        n += 1usize
    }
    let cos_phi = math.cos[f64](phi)
    if cos_phi > 0.000000001f64 || cos_phi < 0.0f64 - 0.000000001f64 { by = by / cos_phi }
    // Back to geodetic axes.
    let psi = phi - lat
    let north = bx * math.cos[f64](psi) - bz * math.sin[f64](psi)
    let down = bx * math.sin[f64](psi) + bz * math.cos[f64](psi)
    let east = by
    let horizontal = math.sqrt[f64](north * north + east * east)
    let total = math.sqrt[f64](horizontal * horizontal + down * down)
    ret Field { declination: rad_to_deg(math.atan2[f64](east, north)), inclination: rad_to_deg(math.atan2[f64](down, horizontal)), horizontal: horizontal, total: total, north: north, east: east, down: down }
}

// The offset of a magnetometer: the centre of the box around `count` samples (x, y, z each as a separate slice).
fn calibrate_hard_iron(xs: []const f64, ys: []const f64, zs: []const f64, count: usize) -> (f64, f64, f64) {
    if count == 0usize { ret (0.0f64, 0.0f64, 0.0f64) }
    var min_x = xs[0usize]
    var max_x = xs[0usize]
    var min_y = ys[0usize]
    var max_y = ys[0usize]
    var min_z = zs[0usize]
    var max_z = zs[0usize]
    var i = 1usize
    while i < count {
        if xs[i] < min_x { min_x = xs[i] }
        if xs[i] > max_x { max_x = xs[i] }
        if ys[i] < min_y { min_y = ys[i] }
        if ys[i] > max_y { max_y = ys[i] }
        if zs[i] < min_z { min_z = zs[i] }
        if zs[i] > max_z { max_z = zs[i] }
        i += 1usize
    }
    ret ((min_x + max_x) / 2.0f64, (min_y + max_y) / 2.0f64, (min_z + max_z) / 2.0f64)
}

// The heading in degrees (0 to 360, clockwise from magnetic north) of a device with magnetometer (mx, my, mz)
// and accelerometer (ax, ay, az) readings, tilt-compensated: roll and pitch come from gravity, the magnetic
// vector is rotated to the horizontal plane and the heading is taken from its components there.
fn heading(mx: f64, my: f64, mz: f64, ax: f64, ay: f64, az: f64) -> f64 {
    // With x forward, y right and z down, at rest the accelerometer reads gravity along +z (az > 0).
    let roll = math.atan2[f64](ay, az)
    let pitch = math.atan2[f64](0.0f64 - ax, math.sqrt[f64](ay * ay + az * az))
    let cos_roll = math.cos[f64](roll)
    let sin_roll = math.sin[f64](roll)
    let cos_pitch = math.cos[f64](pitch)
    let sin_pitch = math.sin[f64](pitch)
    let hx = mx * cos_pitch + my * sin_roll * sin_pitch + mz * cos_roll * sin_pitch
    let hy = my * cos_roll - mz * sin_roll
    var degrees = rad_to_deg(math.atan2[f64](0.0f64 - hy, hx))
    while degrees < 0.0f64 { degrees = degrees + 360.0f64 }
    while degrees >= 360.0f64 { degrees = degrees - 360.0f64 }
    ret degrees
}
