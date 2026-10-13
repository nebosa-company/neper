// The sensor server (C161, D4003): a process of its own that holds the magnetometer, the accelerometer, the gyroscope
// and the location service. The kernel starts it in the unified boot (archive entry 44) and grants it slot 2 requests
// in (endpoint 14, which the kernel stamps with the sender's app number), slot 3 replies out, slots 4 and 5 the
// filesystem's ends when the machine has a disk (the permission overrides, /permits) and slots 9 and 10 the settings
// server's (the Location switch). The source under QEMU is the scripted trace of sensor_sim.e; the Pixel's sensor
// hub takes its place behind the same requests.
//
// A client opens a sensor at a rate of its own (clamped to the hub's) and reads the samples that have arrived since
// its last read: sample n of a stream at rate r is the trace at n / r seconds, and the server counts the arrivals
// from its own monotonic clock, so a client that lags is told which sample comes first. Every sensor is behind a
// permission per app: the app's manifest default (default_mask) unless Settings changed it (PERMIT_SET, believed only
// from the Settings app by the kernel's stamp), and the location service is also behind the Location switch.
use e.mem
use e.os
use e.time
use e.math
use fsproto
use sysettings
use sensorclient
use sensor_sim

const REQ: usize = 2usize
const REP: usize = 3usize
const FS_REQ: usize = 4usize
const FS_REP: usize = 5usize
const NO_SLOT: usize = 99usize
const REFUSED: usize = 18446744073709551615usize
// The setting that switches the location service (settings.e's LOCATION).
const LOCATION_SETTING: usize = 15usize

const STREAMS: usize = 16usize
const APPS: usize = 64usize
// The permission mask bits: one per kind, and the fine (satellite) location.
const BIT_FINE: usize = 32usize
const OVERRIDE: u8 = 128u8

// The overrides: two bytes an app, the mask's low byte then OVERRIDE | its high bits (a mask of 15 bits).
type Permits = struct { b: [128]u8 }

type Streams = struct {
    app: [16]usize,
    kind: [16]usize,
    rate: [16]usize,
    start_ms: [16]usize,
    next: [16]usize,
    source: [16]usize,
    live: [16]bool,
}

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var more = true
    while more {
        at -= 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        if rest == 0usize { more = false }
    }
    say(digits[at..20usize])
}

// What an app may read without anyone having said so: its manifest (the order of neperos-apps.txt, from entry 13).
fn default_mask(app: usize) -> usize {
    if app == sensorclient.APP_COMPASS { ret 1usize | 2usize | 4usize | 8usize | BIT_FINE }
    if app == sensorclient.APP_LEVEL { ret 2usize | 4usize | 16usize }
    if app == sensorclient.APP_STEPS { ret 2usize | 16usize }
    // (C168) The shell's home-screen step widget reads the counter, and nothing else of the hub.
    if app == sensorclient.APP_SHELL { ret 16usize }
    // The background services process (kernel-started, app number 2): the step counter's keeper.
    if app == 2usize { ret 16usize }
    if app == sensorclient.APP_MAPS { ret 8usize | BIT_FINE }
    if app == sensorclient.APP_WEATHER { ret 8usize }
    // The camera belongs to the Camera app (entry 21); storage to the apps that were granted the filesystem's ends.
    if app == 21usize { ret 64usize | 128usize }
    if app == 14usize || app == 15usize || app == 18usize || app == 20usize || app == 22usize || app == 23usize || app == 24usize || app == 25usize || app == 27usize || app == 31usize || app == 34usize || app == 37usize || app == 38usize || app == 40usize { ret 128usize }
    ret 0usize
}

// One bit a kind: the three sensors, the location (coarse), the step counter, the fine location, the camera and storage.
fn kind_bit(kind: usize) -> usize {
    if kind >= 8usize { ret 0usize }
    ret 1usize << kind
}

// The overrides, two bytes an app: the low byte, then the high bits with OVERRIDE set. Zero is no override.
fn load_overrides(over: *Permits) {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/permits")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [128]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 128usize)
    if result != fsproto.RESULT_OK || count != 128usize { ret }
    var i = 0usize
    while i < 128usize {
        over.b[i] = raw[i]
        i += 1usize
    }
    say("sensor permits loaded\n")
}

fn save_overrides(over: *Permits) {
    let sent = os.send(FS_REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/permits")
    fsproto.send_bytes(FS_REQ, mem.address_of(&over.b[0usize]), 128usize)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
}

fn mask_of(over: *Permits, app: usize) -> usize {
    if app >= APPS { ret 0usize }
    if (over.b[app * 2usize + 1usize] & OVERRIDE) != 0u8 { ret usize(over.b[app * 2usize]) | (usize(over.b[app * 2usize + 1usize] & 127u8) << 8usize) }
    ret default_mask(app)
}

fn find_stream(s: *Streams, app: usize, kind: usize) -> usize {
    var i = 0usize
    while i < STREAMS {
        if s.live[i] && s.app[i] == app && s.kind[i] == kind { ret i }
        i += 1usize
    }
    ret STREAMS
}

fn now_ms() -> usize {
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret 0usize }
    ret usize(now.nanos / 1000000i64)
}

// The packed reading of `kind` from `source` for sample `n` of a stream at `rate`.
fn sample(kind: usize, source: usize, n: usize, rate: usize, nx: f64, nz: f64) -> usize {
    let tau = 2.0f64 * f64(n) / f64(rate)
    if source == sensorclient.SOURCE_FLAT {
        // The phone lying still: the accelerometer reads gravity with its bias and noise, the gyroscope its own.
        let (fx, fy, fz) = sensor_sim.flat_at(n)
        if kind == sensorclient.KIND_ACCELEROMETER {
            ret sensorclient.pack(i64(fx * 1000.0f64), i64(fy * 1000.0f64), i64(fz * 1000.0f64))
        }
        ret sensorclient.pack(0i64, 0i64, 0i64)
    }
    if source == sensorclient.SOURCE_COMPASS {
        let (cx, cy, cz, cax, cay, caz) = sensor_sim.compass_session(f64(n) / f64(rate), nx, nz)
        if kind == sensorclient.KIND_MAGNETOMETER { ret sensorclient.pack(i64(cx), i64(cy), i64(cz)) }
        if kind == sensorclient.KIND_ACCELEROMETER { ret sensorclient.pack(i64(cax * 1000.0f64), i64(cay * 1000.0f64), i64(caz * 1000.0f64)) }
        ret sensorclient.pack(0i64, 0i64, 0i64)
    }
    if source == sensorclient.SOURCE_FIGURE_EIGHT {
        let total = math.sqrt[f64](nx * nx + nz * nz)
        let (fx, fy, fz) = sensor_sim.calibration_pose(n, total)
        if kind == sensorclient.KIND_MAGNETOMETER { ret sensorclient.pack(i64(fx), i64(fy), i64(fz)) }
        if kind == sensorclient.KIND_ACCELEROMETER { ret sensorclient.pack(0i64, 0i64, 9810i64) }
        ret sensorclient.pack(0i64, 0i64, 0i64)
    }
    if source == sensorclient.SOURCE_WALK {
        // The magnitude of a walk at the stream's rate: gravity, the stride and its harmonic, the sway and a little noise.
        let magnitude = sensor_sim.walk_at(n, f64(n) / f64(rate))
        if kind == sensorclient.KIND_ACCELEROMETER { ret sensorclient.pack(0i64, 0i64, i64(magnitude * 1000.0f64)) }
        ret sensorclient.pack(0i64, 0i64, 0i64)
    }
    if source == sensorclient.SOURCE_REPLAY {
        let t = f64(n) / f64(rate)
        if kind == sensorclient.KIND_ACCELEROMETER {
            let (sx, sy, sz) = sensor_sim.session_accel(t)
            ret sensorclient.pack(i64(sx * 1000.0f64), i64(sy * 1000.0f64), i64(sz * 1000.0f64))
        }
        let (sp, sq, sr) = sensor_sim.session_gyro(t)
        ret sensorclient.pack(i64(sp * 1000.0f64), i64(sq * 1000.0f64), i64(sr * 1000.0f64))
    }
    if kind == sensorclient.KIND_GYROSCOPE {
        let (p, q, r) = sensor_sim.gyro_at(tau)
        ret sensorclient.pack(i64(p * 1000.0f64), i64(q * 1000.0f64), i64(r * 1000.0f64))
    }
    let (mx, my, mz, ax, ay, az) = sensor_sim.sensors_with(tau, nx, nz)
    if kind == sensorclient.KIND_ACCELEROMETER {
        ret sensorclient.pack(i64(ax * 1000.0f64), i64(ay * 1000.0f64), i64(az * 1000.0f64))
    }
    ret sensorclient.pack(i64(mx), i64(my), i64(mz))
}

// The hub's highest rate for a kind.
fn rate_cap(kind: usize) -> usize {
    if kind == sensorclient.KIND_MAGNETOMETER { ret 50usize }
    ret sensorclient.MAX_RATE
}

fn main(a: *mem.Arena, args: []str) -> err {
    var streams: Streams = zero
    var over: Permits = zero
    // The overrides are read at the first request, not at start: the settings server is reading /settings through the
    // same filesystem endpoints in the same moments of the boot, and two processes' multi-word requests must not
    // interleave on them.
    var loaded = false
    var touches = 0usize
    let (nx, nz) = sensor_sim.field_north()
    let born = now_ms()
    say("sensor server up\n")
    var running = true
    while running {
        let word = os.recv(REQ, NO_SLOT)
        if word == REFUSED { running = false } else {
            if !loaded {
                loaded = true
                load_overrides(&over)
            }
            let app = word >> 56usize
            let op = word & 15usize
            let kind = (word >> 4usize) & 15usize
            let arg1 = (word >> 8usize) & 255usize
            let arg2 = (word >> 16usize) & 255usize
            if op == sensorclient.OP_OPEN {
                var status = sensorclient.STATUS_OK
                var granted = 0usize
                if kind > sensorclient.KIND_GYROSCOPE || (mask_of(&over, app) & kind_bit(kind)) == 0usize {
                    status = sensorclient.STATUS_DENIED
                    say("sensor denied app ")
                    say_num(app)
                    say(" kind ")
                    say_num(kind)
                    say("\n")
                } else {
                    granted = arg1
                    if granted < 1usize { granted = 1usize }
                    if granted > rate_cap(kind) { granted = rate_cap(kind) }
                    var at = find_stream(&streams, app, kind)
                    if at == STREAMS {
                        var i = 0usize
                        while i < STREAMS && at == STREAMS {
                            if !streams.live[i] { at = i }
                            i += 1usize
                        }
                    }
                    if at == STREAMS {
                        status = sensorclient.STATUS_DENIED
                        granted = 0usize
                    } else {
                        streams.live[at] = true
                        streams.app[at] = app
                        streams.kind[at] = kind
                        streams.rate[at] = granted
                        streams.start_ms[at] = now_ms()
                        streams.next[at] = 0usize
                        streams.source[at] = arg2
                        if arg2 > sensorclient.SOURCE_FIGURE_EIGHT { streams.source[at] = sensorclient.SOURCE_LIVE }
                        say("sensor open app ")
                        say_num(app)
                        say(" kind ")
                        say_num(kind)
                        say(" rate ")
                        say_num(granted)
                        say(" source ")
                        say_num(streams.source[at])
                        say("\n")
                    }
                }
                let sent = os.send(REP, status | (granted << 8usize), NO_SLOT)
            } else if op == sensorclient.OP_READ {
                let at = find_stream(&streams, app, kind)
                if at == STREAMS || (mask_of(&over, app) & kind_bit(kind)) == 0usize {
                    let sent_count = os.send(REP, sensorclient.DENIED, NO_SLOT)
                    let sent_first = os.send(REP, 0usize, NO_SLOT)
                } else {
                    // The samples that have arrived: (elapsed ms x rate) / 1000, kept in the hub's FIFO of 1000: a client that
                    // reads late still gets every sample in order, and one more than 1000 behind skips ahead (the first
                    // index in the reply says so).
                    let elapsed = now_ms() - streams.start_ms[at]
                    var arrived = elapsed * streams.rate[at] / 1000usize
                    if streams.source[at] == sensorclient.SOURCE_LIVE {
                        if arrived > streams.next[at] + 1000usize { streams.next[at] = arrived - 1000usize }
                    } else {
                        // A recording or a flat-table source plays at the speed it is read: an emulated machine that
                        // cannot keep 50 Hz gets the same samples, only later.
                        arrived = streams.next[at] + sensorclient.MAX_BATCH
                    }
                    var count = 0usize
                    if arrived > streams.next[at] { count = arrived - streams.next[at] }
                    var limit = arg1
                    if limit > sensorclient.MAX_BATCH { limit = sensorclient.MAX_BATCH }
                    if count > limit { count = limit }
                    let first = streams.next[at]
                    let sent_count = os.send(REP, count, NO_SLOT)
                    let sent_first = os.send(REP, first, NO_SLOT)
                    var i = 0usize
                    while i < count {
                        let sent_word = os.send(REP, sample(kind, streams.source[at], first + i, streams.rate[at], nx, nz), NO_SLOT)
                        i += 1usize
                    }
                    streams.next[at] = first + count
                }
            } else if op == sensorclient.OP_CLOSE {
                let at = find_stream(&streams, app, kind)
                if at != STREAMS { streams.live[at] = false }
                let sent = os.send(REP, 1usize, NO_SLOT)
            } else if op == sensorclient.OP_FIX {
                let mask = mask_of(&over, app)
                var status = sensorclient.STATUS_OK
                var lat = 0i64
                var lon = 0i64
                var accuracy = 0usize
                var source = sensorclient.SOURCE_NETWORK
                let (switch_value, switch_served) = sysettings.get(LOCATION_SETTING)
                if (mask & 8usize) == 0usize || (switch_served && switch_value == 0usize) {
                    status = sensorclient.STATUS_DENIED
                    say("sensor fix denied app ")
                    say_num(app)
                    say("\n")
                } else {
                    let t = f64(now_ms() - born) / 1000.0f64
                    let degrees_lat = sensor_sim.drift_latitude(t)
                    let degrees_lon = sensor_sim.drift_longitude(t)
                    if arg1 != 0usize && (mask & BIT_FINE) != 0usize {
                        // The satellite fix: micro-degrees, a few metres.
                        source = sensorclient.SOURCE_GPS
                        accuracy = 5usize
                        lat = i64(degrees_lat * 1000000.0f64)
                        lon = i64(degrees_lon * 1000000.0f64)
                    } else {
                        // The network's: to a hundredth of a degree (about a kilometre), nearer 1500 m.
                        accuracy = 1500usize
                        lat = i64(degrees_lat * 100.0f64) * 10000i64
                        lon = i64(degrees_lon * 100.0f64) * 10000i64
                    }
                    say("sensor fix app ")
                    say_num(app)
                    if source == sensorclient.SOURCE_GPS { say(" gps\n") } else { say(" network\n") }
                }
                let sent_lat = os.send(REP, usize(lat + sensorclient.BIAS), NO_SLOT)
                let sent_lon = os.send(REP, usize(lon + sensorclient.BIAS), NO_SLOT)
                let sent_meta = os.send(REP, status | (accuracy << 8usize) | (source << 32usize), NO_SLOT)
            } else if op == sensorclient.OP_STEPS {
                // The hub's counter: the count and cadence at the time since the hub started.
                var status = sensorclient.STATUS_OK
                var count = 0usize
                var cadence = 0usize
                if (mask_of(&over, app) & 16usize) == 0usize {
                    status = sensorclient.STATUS_DENIED
                } else {
                    let since = now_ms() - born
                    count = sensor_sim.step_count_at(since)
                    cadence = sensor_sim.step_cadence_at(since)
                }
                let sent_count = os.send(REP, count, NO_SLOT)
                let sent_cadence = os.send(REP, cadence, NO_SLOT)
                let sent_status = os.send(REP, status, NO_SLOT)
            } else if op == sensorclient.OP_BIOMETRIC {
                // The recorded fingerprint sensor: the enrolled finger lies on the reader unless it is every fourth try.
                var answer = sensorclient.BIOMETRIC_DENIED
                if app == sensorclient.APP_SHELL {
                    let (switch_value, switch_served) = sysettings.get(18usize)
                    if switch_served && switch_value == 0usize {
                        answer = sensorclient.BIOMETRIC_OFF
                    } else if touches % 4usize == 3usize {
                        answer = sensorclient.BIOMETRIC_NO
                    } else {
                        answer = sensorclient.BIOMETRIC_MATCH
                    }
                    touches += 1usize
                    say("sensor biometric ")
                    say_num(answer)
                    say("\n")
                }
                let sent = os.send(REP, answer, NO_SLOT)
            } else if op == sensorclient.OP_PERMIT_GET {
                var value = 0usize
                if (mask_of(&over, arg1) & kind_bit(kind)) != 0usize { value = 1usize }
                let sent = os.send(REP, value, NO_SLOT)
            } else if op == sensorclient.OP_PERMIT_SET {
                var taken = 0usize
                if app == sensorclient.APP_SETTINGS && arg1 < APPS && kind < 8usize {
                    var mask = mask_of(&over, arg1)
                    if arg2 != 0usize { mask = mask | kind_bit(kind) } else { mask = mask & ~kind_bit(kind) }
                    over.b[arg1 * 2usize] = u8(mask & 255usize)
                    over.b[arg1 * 2usize + 1usize] = OVERRIDE | u8((mask >> 8usize) & 127usize)
                    save_overrides(&over)
                    taken = 1usize
                    say("sensor permit app ")
                    say_num(arg1)
                    say(" kind ")
                    say_num(kind)
                    if arg2 != 0usize { say(" allowed\n") } else { say(" denied\n") }
                } else {
                    say("sensor permit refused from app ")
                    say_num(app)
                    say("\n")
                }
                let sent = os.send(REP, taken, NO_SLOT)
            } else {
                // An unknown request still gets one word, so the caller is not left waiting.
                let sent = os.send(REP, 0usize, NO_SLOT)
            }
        }
    }
    say("sensor server done\n")
    ret ok
}
