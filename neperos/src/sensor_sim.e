// The simulated sensor source (C131): what the magnetometer and the accelerometer of a phone held in a hand report,
// as a function of time. The device's yaw swings slowly around 40 degrees from magnetic north, it is pitched and
// rolled a little, the field is the World Magnetic Model's at Seattle in 2026.8, and the phone's own magnets add
// a hard-iron offset to every magnetometer reading (nT). The settings server serves it to apps (sysettings.sensor);
// an app without the server computes the same trace itself.
use e.math
use e.algo.magnetic as magnetic

fn place_latitude() -> f64 { ret 47.6062f64 }
fn place_longitude() -> f64 { ret 0.0f64 - 122.3321f64 }
fn model_year() -> f64 { ret 2026.8f64 }
fn iron_x() -> f64 { ret 3000.0f64 }
fn iron_y() -> f64 { ret 0.0f64 - 2000.0f64 }
fn iron_z() -> f64 { ret 1500.0f64 }

// The yaw of the device at tick `ticks` (half-second steps), in degrees from magnetic north.
fn swing_yaw(ticks: usize) -> f64 {
    let t = f64(ticks) * 0.35f64
    ret 40.0f64 + 28.0f64 * math.sin[f64](t) + 9.0f64 * math.sin[f64](t * 2.7f64)
}

// The gyroscope: the device's angular rates (p about the forward axis, q about the right axis, r about the down
// axis) in rad/s at tick `ticks`: the derivatives of the roll, pitch and yaw the other sensors follow.
fn gyro(ticks: usize) -> (f64, f64, f64) {
    let t = f64(ticks) * 0.5f64
    let roll_rate = 0.0f64 - 0.07f64 * 0.8f64 * math.sin[f64](0.8f64 * t)
    let pitch_rate = 0.10f64 * math.cos[f64](t)
    // The yaw swing is a function of the tick (0.35 a tick); its rate per second is twice the change per tick.
    let k = f64(ticks)
    let per_tick = 28.0f64 * 0.35f64 * math.cos[f64](0.35f64 * k) + 9.0f64 * 0.35f64 * 2.7f64 * math.cos[f64](0.35f64 * 2.7f64 * k)
    let yaw_rate = per_tick * 2.0f64 * 3.141592653589793f64 / 180.0f64
    ret (roll_rate, pitch_rate, yaw_rate)
}

// Magnetometer (nT) and accelerometer (m/s^2) readings in the device frame (x forward, y right, z down), the
// magnetometer with the hard-iron offset: (mx, my, mz, ax, ay, az).
fn sensors(ticks: usize) -> (f64, f64, f64, f64, f64, f64) {
    let yaw = swing_yaw(ticks) * 3.141592653589793f64 / 180.0f64
    let t = f64(ticks) * 0.5f64
    let pitch = 0.10f64 * math.sin[f64](t)
    let roll = 0.07f64 * math.cos[f64](t * 0.8f64)
    let f = magnetic.field(place_latitude(), place_longitude(), 0.056f64, model_year())
    // The field in the frame whose x axis is magnetic north: horizontal along x, vertical down.
    let nx = f.horizontal
    let nz = f.down
    // Rotate by yaw about z, then pitch about y, then roll about x (the aerospace 3-2-1 order).
    let cy = math.cos[f64](yaw)
    let sy = math.sin[f64](yaw)
    let cp = math.cos[f64](pitch)
    let sp = math.sin[f64](pitch)
    let cr = math.cos[f64](roll)
    let sr = math.sin[f64](roll)
    let v1x = cy * nx
    let v1y = 0.0f64 - sy * nx
    let v1z = nz
    let v2x = cp * v1x - sp * v1z
    let v2y = v1y
    let v2z = sp * v1x + cp * v1z
    let mx = v2x
    let my = cr * v2y + sr * v2z
    let mz = 0.0f64 - sr * v2y + cr * v2z
    // Gravity: (0, 0, g) rotated the same way (yaw leaves it alone).
    let ax = 0.0f64 - sp * 9.81f64
    let ay = sr * cp * 9.81f64
    let az = cr * cp * 9.81f64
    ret (mx + iron_x(), my + iron_y(), mz + iron_z(), ax, ay, az)
}
