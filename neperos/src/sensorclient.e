// The client side of the sensor server (C161, D4003): what an app holds to read the magnetometer, the accelerometer
// and the gyroscope as streams at a rate of its own, and the location service. The kernel grants a launched app the
// server's two endpoints in slots 11 (requests out) and 12 (replies in); a process it did not grant them to gets the
// kernel's refusal on the first send, which is how a caller learns there is no server (an old archive, a single-app
// boot). The kernel stamps the sender's app number in the top byte of the request word, so the server's permission
// for an app cannot be claimed by another.
//
// A request is ONE word (bits 0-3 op, 4-7 kind, 8-15 and 16-23 two arguments), so two apps' requests never
// interleave; the server answers one request completely before it takes the next. Replies:
//   OPEN kind rate source -> one word, status | granted rate << 8
//   READ kind max         -> a count word (DENIED when not permitted or not open), the stream index of the first
//                            reading, then `count` readings of one word each (three 18-bit signed fields)
//   CLOSE kind            -> 1
//   FIX precise           -> latitude, longitude (micro-degrees + 2^31), then status | accuracy m << 8 | source << 32
//   PERMIT_GET app kind   -> 0 or 1
//   PERMIT_SET app kind v -> 1 when taken (only the Settings app is believed)
// Units of a reading: nT for the magnetometer, mm/s^2 for the accelerometer, mrad/s for the gyroscope.
use e.os

const REQ: usize = 11usize
const REP: usize = 12usize
const NO_SLOT: usize = 99usize
const REFUSED: usize = 18446744073709551615usize

const OP_OPEN: usize = 1usize
const OP_READ: usize = 2usize
const OP_CLOSE: usize = 3usize
const OP_FIX: usize = 4usize
const OP_PERMIT_GET: usize = 5usize
const OP_PERMIT_SET: usize = 6usize
const OP_STEPS: usize = 7usize
// (C176) The recorded fingerprint sensor: only the shell (the lock screen) may ask; the answer is BIOMETRIC_MATCH, the
// Fingerprint switch of Settings being off (BIOMETRIC_OFF), or BIOMETRIC_NO (a finger that is not the enrolled one).
const OP_BIOMETRIC: usize = 8usize
const BIOMETRIC_MATCH: usize = 0usize
const BIOMETRIC_OFF: usize = 1usize
const BIOMETRIC_NO: usize = 2usize
const BIOMETRIC_DENIED: usize = 3usize
const APP_SHELL: usize = 1usize

const KIND_MAGNETOMETER: usize = 0usize
const KIND_ACCELEROMETER: usize = 1usize
const KIND_GYROSCOPE: usize = 2usize
const KIND_LOCATION: usize = 3usize
// The hub's step counter (C168): cumulative steps and the present cadence, counted in the hub whether or not an app
// is running (STEPS -> count, then cadence in hundredths of a step a second); never opened as a stream.
const KIND_STEPS: usize = 4usize
// The permissions that are not streams, the same one-bit-a-kind: the fine (satellite) location, the camera and storage.
const KIND_FINE: usize = 5usize
const KIND_CAMERA: usize = 6usize
const KIND_STORAGE: usize = 7usize
const KINDS: usize = 8usize

// A stream's source (OPEN's second argument): the live (scripted, under QEMU) sensor; the same phone lying flat and
// still on a table, with a bias and a noise of its own (Level's self-test); a recorded session of lifting and
// standing the phone (Level's Replay, and the fixtures' ground truth).
const SOURCE_LIVE: usize = 0usize
const SOURCE_FLAT: usize = 1usize
const SOURCE_REPLAY: usize = 2usize
// A recorded walk: the accelerometer of a phone in the pocket of someone walking at 1.9 steps a second (the magnitude in
// z), played at the speed it is read; the ground truth of the step detector's fixture.
const SOURCE_WALK: usize = 3usize
// The compass's recordings: the phone turned to north, east, south and west two seconds each (the heading is the yaw), and
// the figure eight of the calibration (the field along every axis and corner, eight samples each).
const SOURCE_COMPASS: usize = 4usize
const SOURCE_FIGURE_EIGHT: usize = 5usize

const BIAS: i64 = 2147483648i64
const FIELD_BIAS: i64 = 131072i64
const FIELD_MASK: usize = 262143usize
// The most readings one READ returns, and the highest rate a client may open a stream at.
const MAX_BATCH: usize = 32usize
const MAX_RATE: usize = 100usize
// The count a READ answers with when the app holds no permission for the sensor, or has not opened it.
const DENIED: usize = 1000usize

const STATUS_OK: usize = 0usize
const STATUS_DENIED: usize = 1usize
const STATUS_NO_SERVER: usize = 2usize

// A location's source: the satellite fix, or the network's coarse one.
const SOURCE_GPS: usize = 0usize
const SOURCE_NETWORK: usize = 1usize

// The apps' archive entries the server knows by default (the order of neperos-apps.txt, from 13).
const APP_WEATHER: usize = 18usize
const APP_SETTINGS: usize = 24usize
const APP_MAPS: usize = 28usize
const APP_COMPASS: usize = 29usize
const APP_LEVEL: usize = 30usize
const APP_STEPS: usize = 36usize

type Reading = struct { x: i64, y: i64, z: i64 }

fn request(op: usize, kind: usize, arg1: usize, arg2: usize) -> usize {
    ret op | (kind << 4usize) | (arg1 << 8usize) | (arg2 << 16usize)
}

// A reading's three fields into one word (each saturated to 18 bits signed).
fn pack(x: i64, y: i64, z: i64) -> usize {
    ret field(x) | (field(y) << 18usize) | (field(z) << 36usize)
}

fn field(v: i64) -> usize {
    var c = v
    if c > 131071i64 { c = 131071i64 }
    if c < 0i64 - 131071i64 { c = 0i64 - 131071i64 }
    ret usize(c + FIELD_BIAS) & FIELD_MASK
}

fn unfield(w: usize) -> i64 {
    ret i64(w & FIELD_MASK) - FIELD_BIAS
}

// Open `kind` at `rate` Hz from `source` (SOURCE_*); the status and the rate the hub settled on. Opening a stream
// again restarts it at sample 0.
fn open(kind: usize, rate: usize, source: usize) -> (usize, usize) {
    let sent = os.send(REQ, request(OP_OPEN, kind, rate, source), NO_SLOT)
    if sent == REFUSED { ret (STATUS_NO_SERVER, 0usize) }
    let word = os.recv(REP, NO_SLOT)
    ret (word & 255usize, word >> 8usize)
}

// The readings of `kind` since the last read, at most `out.len` (and MAX_BATCH): how many came back, the stream
// index of the first, and whether the app lacks the permission (or has not opened the stream).
fn read(kind: usize, out: []Reading) -> (usize, usize, bool) {
    var want = out.len
    if want > MAX_BATCH { want = MAX_BATCH }
    let sent = os.send(REQ, request(OP_READ, kind, want, 0usize), NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, false) }
    let count = os.recv(REP, NO_SLOT)
    let first = os.recv(REP, NO_SLOT)
    if count == DENIED { ret (0usize, 0usize, true) }
    var i = 0usize
    while i < count {
        let w = os.recv(REP, NO_SLOT)
        if i < out.len { out[i] = Reading { x: unfield(w), y: unfield(w >> 18usize), z: unfield(w >> 36usize) } }
        i += 1usize
    }
    ret (count, first, false)
}

fn close(kind: usize) {
    let sent = os.send(REQ, request(OP_CLOSE, kind, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret }
    let ack = os.recv(REP, NO_SLOT)
}

// A location fix: the status, latitude and longitude in micro-degrees, the accuracy in metres and the source.
// `precise` asks for the satellite fix (an app holding only the coarse permission gets the network's).
fn fix(precise: bool) -> (usize, i64, i64, usize, usize) {
    var flag = 0usize
    if precise { flag = 1usize }
    let sent = os.send(REQ, request(OP_FIX, KIND_LOCATION, flag, 0usize), NO_SLOT)
    if sent == REFUSED { ret (STATUS_NO_SERVER, 0i64, 0i64, 0usize, 0usize) }
    let lat = os.recv(REP, NO_SLOT)
    let lon = os.recv(REP, NO_SLOT)
    let meta = os.recv(REP, NO_SLOT)
    ret (meta & 255usize, i64(lat) - BIAS, i64(lon) - BIAS, (meta >> 8usize) & 16777215usize, meta >> 32usize)
}

// A touch on the fingerprint reader: BIOMETRIC_MATCH when the enrolled finger lay on it and the switch is on.
fn biometric() -> usize {
    let sent = os.send(REQ, request(OP_BIOMETRIC, 0usize, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret BIOMETRIC_DENIED }
    ret os.recv(REP, NO_SLOT)
}

// The hub's step counter: the count since the hub started, the cadence in hundredths of a step a second, and the
// status (STATUS_DENIED without the permission, STATUS_NO_SERVER without a server).
fn steps() -> (usize, usize, usize) {
    let sent = os.send(REQ, request(OP_STEPS, KIND_STEPS, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, STATUS_NO_SERVER) }
    let count = os.recv(REP, NO_SLOT)
    let cadence = os.recv(REP, NO_SLOT)
    let status = os.recv(REP, NO_SLOT)
    ret (count, cadence, status)
}

// Whether `app` may read `kind` (the default of the app's manifest or what Settings set).
fn permitted(app: usize, kind: usize) -> bool {
    let sent = os.send(REQ, request(OP_PERMIT_GET, kind, app, 0usize), NO_SLOT)
    if sent == REFUSED { ret false }
    ret os.recv(REP, NO_SLOT) != 0usize
}

// The same with whether the server answered at all (a machine without it asks nothing of the app).
fn permission(app: usize, kind: usize) -> (bool, bool) {
    let sent = os.send(REQ, request(OP_PERMIT_GET, kind, app, 0usize), NO_SLOT)
    if sent == REFUSED { ret (false, false) }
    ret (os.recv(REP, NO_SLOT) != 0usize, true)
}

// Allow or deny `kind` for `app`; true when the server took it (only the Settings app is believed).
fn set_permit(app: usize, kind: usize, allow: bool) -> bool {
    var value = 0usize
    if allow { value = 1usize }
    let sent = os.send(REQ, request(OP_PERMIT_SET, kind, app, value), NO_SLOT)
    if sent == REFUSED { ret false }
    ret os.recv(REP, NO_SLOT) != 0usize
}
