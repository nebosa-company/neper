// The client side of the settings server (C126): what an app or the shell holds to read the system
// settings and to change them. The kernel grants a process the two endpoints of the server in slots
// 9 (requests out) and 10 (replies in); a process it did not grant them to gets the kernel's refusal on
// the first send, which is how a caller learns there is no server (a single-app boot, an old archive).
//
// One word per rendezvous. Requests: GET_WORD; GET index; SET index value; RESET. Every reply is one
// word: the system word (theme.e) for GET_WORD, SET and RESET, the value for GET.
use e.os

const REQ: usize = 9usize
const REP: usize = 10usize
const NO_SLOT: usize = 99usize
const REFUSED: usize = 18446744073709551615usize

const OP_QUIT: usize = 0usize
const OP_GET_WORD: usize = 1usize
const OP_GET: usize = 2usize
const OP_SET: usize = 3usize
const OP_RESET: usize = 4usize
// The uninstalled apps, one bit per home-screen icon: GET_HIDDEN -> mask; SET_HIDDEN index flag -> mask.
const OP_GET_HIDDEN: usize = 5usize
const OP_SET_HIDDEN: usize = 6usize
// The battery word of the status service (present bit 31, charging bit 8, level in the low byte; 0 when no
// provider reports one): the server asks the status service for it.
const OP_GET_BATTERY: usize = 7usize
// The registry of dynamic apps (the Dynamic app's, C124's to come): six entries of four words, each entry
// the name (24 bytes, three words, little end first) and a word of name length | template << 8 | version << 16
// | extras << 24 (a name length of 0 is an empty entry). DYN_GET index -> four words; DYN_SET index and
// four words -> an acknowledgement.
const OP_DYN_GET: usize = 8usize
const OP_DYN_SET: usize = 9usize
// The sensors (C131): SENSOR kind tick -> three words, a reading's x, y and z in milli-units plus 2^31 (kind 0 the
// magnetometer in nT, 1 the accelerometer in m/s^2, both in the device frame); the tick is the time in half
// seconds, so the scripted source answers the same to every caller.
const OP_SENSOR: usize = 10usize
const SENSOR_MAGNETOMETER: usize = 0usize
const SENSOR_ACCELEROMETER: usize = 1usize
// Kind 2: the gyroscope's rates (p, q, r) in mrad/s.
const SENSOR_GYROSCOPE: usize = 2usize
// Kind 3: the walking accelerometer's magnitude (x, in m/s^2; y and z zero) at sample `tick` of a 25 Hz stream.
const SENSOR_WALK: usize = 3usize
const SENSOR_BIAS: i64 = 2147483648i64
// The torch (C133): TORCH level (0 off, 1 to 5 the brightness steps) -> the level now set. The server holds the
// device (a simulated LED under QEMU, the camera's flash on the Pixel).
const OP_TORCH: usize = 11usize

// A sensor's reading at `tick` in milli-units (x, y, z) and whether the server answered.
fn sensor(kind: usize, tick: usize) -> (i64, i64, i64, bool) {
    let sent = os.send(REQ, OP_SENSOR, NO_SLOT)
    if sent == REFUSED { ret (0i64, 0i64, 0i64, false) }
    let sent_kind = os.send(REQ, kind, NO_SLOT)
    let sent_tick = os.send(REQ, tick, NO_SLOT)
    let wx = os.recv(REP, NO_SLOT)
    let wy = os.recv(REP, NO_SLOT)
    let wz = os.recv(REP, NO_SLOT)
    ret (i64(wx) - SENSOR_BIAS, i64(wy) - SENSOR_BIAS, i64(wz) - SENSOR_BIAS, true)
}

// Set the torch to `level`; the level the server now holds, and whether it answered.
fn torch(level: usize) -> (usize, bool) {
    let sent = os.send(REQ, OP_TORCH, NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    let sent_level = os.send(REQ, level, NO_SLOT)
    ret (os.recv(REP, NO_SLOT), true)
}

// The system word, or 0 when there is no server.
fn word() -> usize {
    let sent = os.send(REQ, OP_GET_WORD, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// Setting `index`, and whether the server answered.
fn get(index: usize) -> (usize, bool) {
    let sent = os.send(REQ, OP_GET, NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    let sent_index = os.send(REQ, index, NO_SLOT)
    ret (os.recv(REP, NO_SLOT), true)
}

// Change a setting; the system word after it, or 0 when there is no server.
fn set(index: usize, value: usize) -> usize {
    let sent = os.send(REQ, OP_SET, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let sent_value = os.send(REQ, value, NO_SLOT)
    ret os.recv(REP, NO_SLOT)
}

// Registry entry `index`: its four words, and whether the server answered.
fn dyn_get(index: usize) -> (usize, usize, usize, usize, bool) {
    let sent = os.send(REQ, OP_DYN_GET, NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, 0usize, 0usize, false) }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let w0 = os.recv(REP, NO_SLOT)
    let w1 = os.recv(REP, NO_SLOT)
    let w2 = os.recv(REP, NO_SLOT)
    let w3 = os.recv(REP, NO_SLOT)
    ret (w0, w1, w2, w3, true)
}

// Store registry entry `index`; whether the server took it.
fn dyn_set(index: usize, w0: usize, w1: usize, w2: usize, w3: usize) -> bool {
    let sent = os.send(REQ, OP_DYN_SET, NO_SLOT)
    if sent == REFUSED { ret false }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let s0 = os.send(REQ, w0, NO_SLOT)
    let s1 = os.send(REQ, w1, NO_SLOT)
    let s2 = os.send(REQ, w2, NO_SLOT)
    let s3 = os.send(REQ, w3, NO_SLOT)
    let ack = os.recv(REP, NO_SLOT)
    ret true
}

// The status service's battery word through the server, or 0 (no server, or no battery provider).
fn battery() -> usize {
    let sent = os.send(REQ, OP_GET_BATTERY, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// The mask of uninstalled apps (bit n is the icon with index n), or 0 when there is no server.
fn hidden() -> usize {
    let sent = os.send(REQ, OP_GET_HIDDEN, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// Uninstall (flag 1) or reinstall (flag 0) icon `index`; the mask after it, or 0 when there is no server.
fn set_hidden(index: usize, flag: usize) -> usize {
    let sent = os.send(REQ, OP_SET_HIDDEN, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let sent_flag = os.send(REQ, flag, NO_SLOT)
    ret os.recv(REP, NO_SLOT)
}

// Every setting back to its default; the system word after it, or 0 when there is no server.
fn reset() -> usize {
    let sent = os.send(REQ, OP_RESET, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}
