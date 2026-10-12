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

// (C161) Every function below has a time form: `tau` is the time in half seconds, a real number, so a 50 Hz stream
// samples the same trace the half-second ticks always saw. The usize forms keep their callers.

// The yaw of the device at tau (half-second steps), in degrees from magnetic north.
fn swing_yaw_at(tau: f64) -> f64 {
    let t = tau * 0.35f64
    ret 40.0f64 + 28.0f64 * math.sin[f64](t) + 9.0f64 * math.sin[f64](t * 2.7f64)
}

fn swing_yaw(ticks: usize) -> f64 {
    ret swing_yaw_at(f64(ticks))
}

// The accelerometer magnitude (m/s^2) of a phone in the pocket of someone walking, at time `t` seconds, sample `n`
// (the noise is an integer hash of n, so the same sample is the same everywhere): gravity, a stride oscillation at
// 1.9 steps a second with its second harmonic, a slow sway and a little noise.
fn walk_at(n: usize, t: f64) -> f64 {
    var h = (n * 2654435761usize + 12345usize) % 4294967296usize
    h = (h ^ (h >> 13usize)) * 1274126177usize % 4294967296usize
    let noise = (f64(h % 1000usize) / 1000.0f64 - 0.5f64) * 0.6f64
    let stride = 3.0f64 * math.sin[f64](2.0f64 * 3.141592653589793f64 * 1.9f64 * t)
    let harmonic = 1.05f64 * math.sin[f64](2.0f64 * 3.141592653589793f64 * 3.8f64 * t + 0.7f64)
    let sway = 0.6f64 * math.sin[f64](2.0f64 * 3.141592653589793f64 * 0.3f64 * t)
    ret 9.81f64 + stride + harmonic + sway + noise
}

// Sample `n` of a 25 Hz stream.
fn walk_magnitude(n: usize) -> f64 {
    ret walk_at(n, f64(n) / 25.0f64)
}

// The gyroscope: the device's angular rates (p about the forward axis, q about the right axis, r about the down
// axis) in rad/s at tau: the derivatives of the roll, pitch and yaw the other sensors follow.
fn gyro_at(tau: f64) -> (f64, f64, f64) {
    let t = tau * 0.5f64
    let roll_rate = 0.0f64 - 0.07f64 * 0.8f64 * math.sin[f64](0.8f64 * t)
    let pitch_rate = 0.10f64 * math.cos[f64](t)
    // The yaw swing is a function of tau (0.35 a step); its rate per second is twice the change per step.
    let per_tick = 28.0f64 * 0.35f64 * math.cos[f64](0.35f64 * tau) + 9.0f64 * 0.35f64 * 2.7f64 * math.cos[f64](0.35f64 * 2.7f64 * tau)
    let yaw_rate = per_tick * 2.0f64 * 3.141592653589793f64 / 180.0f64
    ret (roll_rate, pitch_rate, yaw_rate)
}

fn gyro(ticks: usize) -> (f64, f64, f64) {
    let (p, q, r) = gyro_at(f64(ticks))
    ret (p, q, r)
}

// The accelerometer alone (m/s^2) at tau: gravity rotated by the pitch and roll of the hand.
fn accel_at(tau: f64) -> (f64, f64, f64) {
    let t = tau * 0.5f64
    let pitch = 0.10f64 * math.sin[f64](t)
    let roll = 0.07f64 * math.cos[f64](t * 0.8f64)
    let cp = math.cos[f64](pitch)
    let sp = math.sin[f64](pitch)
    let cr = math.cos[f64](roll)
    let sr = math.sin[f64](roll)
    ret (0.0f64 - sp * 9.81f64, sr * cp * 9.81f64, cr * cp * 9.81f64)
}

// The same phone lying flat and still on a table: gravity straight down with a small fixed bias on each axis and
// noise of a few hundredths from an integer hash of the sample number (the self-test's input: bias and noise are what it
// reports).
fn flat_at(n: usize) -> (f64, f64, f64) {
    var h = (n * 2246822519usize + 3266489917usize) % 4294967296usize
    h = (h ^ (h >> 15usize)) * 2654435761usize % 4294967296usize
    let nx = (f64(h % 1000usize) / 1000.0f64 - 0.5f64) * 0.08f64
    let ny = (f64((h / 1000usize) % 1000usize) / 1000.0f64 - 0.5f64) * 0.08f64
    let nz = (f64((h / 1000000usize) % 1000usize) / 1000.0f64 - 0.5f64) * 0.08f64
    ret (0.03f64 + nx, 0.0f64 - 0.02f64 + ny, 9.81f64 + 0.05f64 + nz)
}

// The magnetic field in the frame whose x axis is magnetic north (horizontal along x, vertical down), nT: cached by a
// server that answers many samples (the model's evaluation is the expensive part).
fn field_north() -> (f64, f64) {
    let f = magnetic.field(place_latitude(), place_longitude(), 0.056f64, model_year())
    ret (f.horizontal, f.down)
}

// Magnetometer (nT) and accelerometer (m/s^2) readings in the device frame (x forward, y right, z down), the
// magnetometer with the hard-iron offset: (mx, my, mz, ax, ay, az), at tau, from a field already computed.
fn sensors_with(tau: f64, nx: f64, nz: f64) -> (f64, f64, f64, f64, f64, f64) {
    let yaw = swing_yaw_at(tau) * 3.141592653589793f64 / 180.0f64
    let t = tau * 0.5f64
    let pitch = 0.10f64 * math.sin[f64](t)
    let roll = 0.07f64 * math.cos[f64](t * 0.8f64)
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

fn sensors(ticks: usize) -> (f64, f64, f64, f64, f64, f64) {
    let (nx, nz) = field_north()
    let (mx, my, mz, ax, ay, az) = sensors_with(f64(ticks), nx, nz)
    ret (mx, my, mz, ax, ay, az)
}

// The place's position at time `t` seconds as a walk: a few metres of drift a minute around the place (micro-degrees
// of latitude and longitude), what a provider reports when someone stands nearly still.
fn drift_latitude(t: f64) -> f64 {
    ret place_latitude() + 0.00001f64 * math.sin[f64](t * 0.05f64)
}

fn drift_longitude(t: f64) -> f64 {
    ret place_longitude() + 0.00001f64 * math.cos[f64](t * 0.05f64)
}

// (C162) A recorded session of a phone on a table: still and flat to 4 s, the right side lifted to 15 degrees of roll
// by 8 s and kept to 12 s, back flat by 14 s, the front raised to 30 degrees of pitch by 18 s and kept to 22 s, stood
// up on its edge (90 degrees) by 26 s and kept to 30 s, and laid back flat by 34 s. The angles are the ground truth
// the fixture checks the filter against; the accelerometer and gyroscope follow them exactly.
fn session_length() -> f64 { ret 34.0f64 }

// `a` to `b` linearly between t0 and t1, held outside.
fn session_ramp(t: f64, t0: f64, t1: f64, a: f64, b: f64) -> f64 {
    if t <= t0 { ret a }
    if t >= t1 { ret b }
    ret a + (b - a) * (t - t0) / (t1 - t0)
}

fn session_roll(t: f64) -> f64 {
    if t < 12.0f64 { ret session_ramp(t, 4.0f64, 8.0f64, 0.0f64, 15.0f64) }
    ret session_ramp(t, 12.0f64, 14.0f64, 15.0f64, 0.0f64)
}

fn session_pitch(t: f64) -> f64 {
    if t < 22.0f64 { ret session_ramp(t, 14.0f64, 18.0f64, 0.0f64, 30.0f64) }
    if t < 30.0f64 { ret session_ramp(t, 22.0f64, 26.0f64, 30.0f64, 90.0f64) }
    ret session_ramp(t, 30.0f64, 34.0f64, 90.0f64, 0.0f64)
}

// The rates in degrees per second: the slopes of the ramps.
fn session_roll_rate(t: f64) -> f64 {
    if t >= 4.0f64 && t < 8.0f64 { ret 15.0f64 / 4.0f64 }
    if t >= 12.0f64 && t < 14.0f64 { ret 0.0f64 - 15.0f64 / 2.0f64 }
    ret 0.0f64
}

fn session_pitch_rate(t: f64) -> f64 {
    if t >= 14.0f64 && t < 18.0f64 { ret 30.0f64 / 4.0f64 }
    if t >= 22.0f64 && t < 26.0f64 { ret 60.0f64 / 4.0f64 }
    if t >= 30.0f64 && t < 34.0f64 { ret 0.0f64 - 90.0f64 / 4.0f64 }
    ret 0.0f64
}

// The accelerometer (m/s^2) of the session at `t` seconds: gravity rotated by the roll and the pitch.
fn session_accel(t: f64) -> (f64, f64, f64) {
    let d = 3.141592653589793f64 / 180.0f64
    let roll = session_roll(t) * d
    let pitch = session_pitch(t) * d
    let cp = math.cos[f64](pitch)
    let sp = math.sin[f64](pitch)
    ret (0.0f64 - sp * 9.81f64, math.sin[f64](roll) * cp * 9.81f64, math.cos[f64](roll) * cp * 9.81f64)
}

// The gyroscope (rad/s) of the session at `t`.
fn session_gyro(t: f64) -> (f64, f64, f64) {
    let d = 3.141592653589793f64 / 180.0f64
    ret (session_roll_rate(t) * d, session_pitch_rate(t) * d, 0.0f64)
}
