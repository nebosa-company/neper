// The settings server (C126): a process that holds the system's settings (the 40 values the Settings app
// shows, settings.e's numbering), answers reads from any process that was granted its endpoints, takes
// changes, keeps them in /settings through the filesystem server, and works out the system word
// (theme.e) that the shell and the apps follow. The kernel starts it in the lunar boot (archive entry 6,
// the wallpaper loader's slot in the older boot) and grants it: slot 2 requests in, slot 3 replies out,
// and, when the machine has a disk, slot 4 filesystem requests out and slot 5 filesystem replies in.
// Without a disk the settings live for the boot only.
use e.mem
use e.os
use fsproto
use sysettings
use theme
use sensor_sim

const REQ: usize = 2usize
const REP: usize = 3usize
const FS_REQ: usize = 4usize
const FS_REP: usize = 5usize
const REFUSED: usize = 18446744073709551615usize
const COUNT: usize = 40usize
// The status service's endpoints, granted when it runs: requests out (slot 6), replies in (slot 7).
// The network server's endpoints (its clients' ends: 8 requests, 9 replies), granted when the machine has a network
// device, for telling it whether the radios may carry traffic.
const NET_REQ: usize = 8usize
const NET_REP: usize = 9usize
const STATUS_REQ: usize = 6usize
const STATUS_REP: usize = 7usize

type Store = struct { v: [48]u8 }

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// The values from /settings, when the file is there and is a settings file (theme.stored_word's rule).
fn load(store: *Store) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, "/settings")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [48]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 48usize)
    if result != fsproto.RESULT_OK || theme.stored_word(raw[0usize..count]) == 0usize { ret false }
    var i = 0usize
    while i < COUNT {
        store.v[i] = raw[i]
        i += 1usize
    }
    ret true
}

fn save(store: *Store) {
    let sent = os.send(FS_REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/settings")
    fsproto.send_bytes(FS_REQ, mem.address_of(&store.v[0usize]), COUNT)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
}

// The uninstalled apps, from /hidden (four bytes, little end first), or none.
fn load_hidden() -> usize {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret 0usize }
    fsproto.send_str(FS_REQ, "/hidden")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [8]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 8usize)
    if result != fsproto.RESULT_OK || count < 4usize { ret 0usize }
    ret usize(raw[0usize]) + usize(raw[1usize]) * 256usize + usize(raw[2usize]) * 65536usize + usize(raw[3usize]) * 16777216usize
}

fn save_hidden(mask: usize) {
    var raw: [8]u8 = zero
    raw[0usize] = u8(mask & 255usize)
    raw[1usize] = u8((mask >> 8usize) & 255usize)
    raw[2usize] = u8((mask >> 16usize) & 255usize)
    raw[3usize] = u8((mask >> 24usize) & 255usize)
    let sent = os.send(FS_REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/hidden")
    fsproto.send_bytes(FS_REQ, mem.address_of(&raw[0usize]), 4usize)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
}

// The dynamic apps' registry, from /dyn (six entries of four words, little end first), or empty.
type Registry = struct { w: [24]usize }

fn load_registry(r: *Registry) {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/dyn")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [192]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 192usize)
    if result != fsproto.RESULT_OK || count != 192usize { ret }
    var i = 0usize
    while i < 24usize {
        var word = 0usize
        var j = 0usize
        while j < 8usize {
            word = word | (usize(raw[i * 8usize + j]) << (j * 8usize))
            j += 1usize
        }
        r.w[i] = word
        i += 1usize
    }
}

fn save_registry(r: *Registry) {
    var raw: [192]u8 = zero
    var i = 0usize
    while i < 24usize {
        var j = 0usize
        while j < 8usize {
            raw[i * 8usize + j] = u8((r.w[i] >> (j * 8usize)) & 255usize)
            j += 1usize
        }
        i += 1usize
    }
    let sent = os.send(FS_REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/dyn")
    fsproto.send_bytes(FS_REQ, mem.address_of(&raw[0usize]), 192usize)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
}

fn defaults(store: *Store) {
    var i = 0usize
    while i < COUNT {
        store.v[i] = u8(theme.default_value(i))
        i += 1usize
    }
}

// Airplane mode off and Wi-Fi or Mobile on: the radios may carry traffic.
fn radios_allowed(store: *Store) -> bool {
    ret store.v[2usize] == 0u8 && (store.v[0usize] != 0u8 || store.v[1usize] != 0u8)
}

// Tell the network server, when the answer changed; false when it has no network server.
fn push_radio(allowed: bool) {
    var flag = 0usize
    if allowed { flag = 1usize }
    let sent = os.send(NET_REQ, 8usize, sysettings.NO_SLOT)
    if sent == REFUSED { ret }
    let flag_sent = os.send(NET_REQ, flag, sysettings.NO_SLOT)
    let result = os.recv(NET_REP, sysettings.NO_SLOT)
}

// (C149) The notification switches (settings 26 to 33, the order of Settings' notification list) as a mask, one bit
// per app, sent to the status service, which counts a notification only from an app whose bit is set.
fn push_notify_mask(store: *Store) {
    var mask = 0usize
    var n = 0usize
    while n < 8usize {
        if store.v[26usize + n] != 0u8 { mask = mask | (1usize << n) }
        n += 1usize
    }
    let sent = os.send(STATUS_REQ, 5usize, sysettings.NO_SLOT)
    if sent == REFUSED { ret }
    let mask_sent = os.send(STATUS_REQ, mask, sysettings.NO_SLOT)
}

fn system_word(store: *Store) -> usize {
    ret theme.stored_word(store.v[0usize..COUNT])
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

fn main(a: *mem.Arena, args: []str) -> err {
    var store: Store = zero
    defaults(&store)
    if load(&store) { say("settings server loaded\n") }
    var hidden = load_hidden()
    var registry: Registry = zero
    load_registry(&registry)
    var torch_level = 0usize
    // (C148) The clipboard: the text as four words, its length, owner and the second it was put.
    var clip: [4]usize = zero
    var clip_len = 0usize
    var clip_owner = 0usize
    var clip_stamp = 0usize
    var radios = radios_allowed(&store)
    if !radios { push_radio(false) }
    push_notify_mask(&store)
    say("settings server up\n")
    var running = true
    while running {
        let op = os.recv(REQ, sysettings.NO_SLOT)
        if op == sysettings.OP_QUIT {
            running = false
        } else if op == sysettings.OP_GET_WORD {
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        } else if op == sysettings.OP_GET {
            let index = os.recv(REQ, sysettings.NO_SLOT)
            var value = 0usize
            if index < COUNT { value = usize(store.v[index]) }
            let sent = os.send(REP, value, sysettings.NO_SLOT)
        } else if op == sysettings.OP_SET {
            let index = os.recv(REQ, sysettings.NO_SLOT)
            let value = os.recv(REQ, sysettings.NO_SLOT)
            if index < COUNT && value <= 10usize {
                store.v[index] = u8(value)
                save(&store)
                if index < 3usize && radios_allowed(&store) != radios {
                    radios = radios_allowed(&store)
                    push_radio(radios)
                }
                if index >= 26usize && index < 34usize { push_notify_mask(&store) }
            }
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        } else if op == sysettings.OP_GET_BATTERY {
            var battery = 0usize
            let asked = os.send(STATUS_REQ, 1usize, sysettings.NO_SLOT)
            if asked != REFUSED {
                battery = os.recv(STATUS_REP, sysettings.NO_SLOT)
                // wifi, cellular, clock, notifications: not needed here, but drained so the service stays in step.
                var drained = 0usize
                while drained < 4usize {
                    let word = os.recv(STATUS_REP, sysettings.NO_SLOT)
                    drained += 1usize
                }
            }
            let sent = os.send(REP, battery, sysettings.NO_SLOT)
        } else if op == sysettings.OP_DYN_GET {
            let index = os.recv(REQ, sysettings.NO_SLOT)
            var k = 0usize
            while k < 4usize {
                var word = 0usize
                if index < 6usize { word = registry.w[index * 4usize + k] }
                let sent = os.send(REP, word, sysettings.NO_SLOT)
                k += 1usize
            }
        } else if op == sysettings.OP_DYN_SET {
            let index = os.recv(REQ, sysettings.NO_SLOT)
            var k = 0usize
            while k < 4usize {
                let word = os.recv(REQ, sysettings.NO_SLOT)
                if index < 6usize { registry.w[index * 4usize + k] = word }
                k += 1usize
            }
            if index < 6usize { save_registry(&registry) }
            let sent = os.send(REP, 0usize, sysettings.NO_SLOT)
        } else if op == sysettings.OP_SENSOR {
            let kind = os.recv(REQ, sysettings.NO_SLOT)
            let tick = os.recv(REQ, sysettings.NO_SLOT)
            let (mx, my, mz, ax, ay, az) = sensor_sim.sensors(tick)
            var x = mx
            var y = my
            var z = mz
            if kind == sysettings.SENSOR_ACCELEROMETER {
                x = ax
                y = ay
                z = az
            }
            if kind == sysettings.SENSOR_WALK {
                x = sensor_sim.walk_magnitude(tick)
                y = 0.0f64
                z = 0.0f64
            }
            if kind == sysettings.SENSOR_GYROSCOPE {
                let (gp, gq, gr) = sensor_sim.gyro(tick)
                x = gp
                y = gq
                z = gr
            }
            // Milli-units, biased so the words are unsigned.
            let bx = i64(x * 1000.0f64) + sysettings.SENSOR_BIAS
            let by = i64(y * 1000.0f64) + sysettings.SENSOR_BIAS
            let bz = i64(z * 1000.0f64) + sysettings.SENSOR_BIAS
            let sent_x = os.send(REP, usize(bx), sysettings.NO_SLOT)
            let sent_y = os.send(REP, usize(by), sysettings.NO_SLOT)
            let sent_z = os.send(REP, usize(bz), sysettings.NO_SLOT)
        } else if op == sysettings.OP_TORCH {
            let level = os.recv(REQ, sysettings.NO_SLOT)
            if level <= 5usize && level != torch_level {
                torch_level = level
                say("torch level ")
                say_num(level)
                say("\n")
            }
            let sent = os.send(REP, torch_level, sysettings.NO_SLOT)
        } else if op == sysettings.OP_CLIP_SET {
            clip_owner = os.recv(REQ, sysettings.NO_SLOT)
            clip_stamp = os.recv(REQ, sysettings.NO_SLOT)
            clip_len = os.recv(REQ, sysettings.NO_SLOT)
            if clip_len > sysettings.CLIP_BYTES { clip_len = sysettings.CLIP_BYTES }
            var cw = 0usize
            while cw < 4usize {
                clip[cw] = os.recv(REQ, sysettings.NO_SLOT)
                cw += 1usize
            }
            // Only the length and owner are said, never the text.
            say("clipboard set by ")
            say_num(clip_owner)
            say(" length ")
            say_num(clip_len)
            say("\n")
            let sent = os.send(REP, 1usize, sysettings.NO_SLOT)
        } else if op == sysettings.OP_CLIP_GET {
            let asked_at = os.recv(REQ, sysettings.NO_SLOT)
            if clip_len > 0usize && asked_at >= clip_stamp && asked_at - clip_stamp > sysettings.CLIP_SECONDS {
                clip_len = 0usize
                clip[0usize] = 0usize
                clip[1usize] = 0usize
                clip[2usize] = 0usize
                clip[3usize] = 0usize
                say("clipboard cleared\n")
            }
            let sent_length = os.send(REP, clip_len, sysettings.NO_SLOT)
            let sent_owner = os.send(REP, clip_owner, sysettings.NO_SLOT)
            var gw = 0usize
            while gw < 4usize {
                let sent_word = os.send(REP, clip[gw], sysettings.NO_SLOT)
                gw += 1usize
            }
        } else if op == sysettings.OP_GET_HIDDEN {
            let sent = os.send(REP, hidden, sysettings.NO_SLOT)
        } else if op == sysettings.OP_SET_HIDDEN {
            let index = os.recv(REQ, sysettings.NO_SLOT)
            let flag = os.recv(REQ, sysettings.NO_SLOT)
            if index < 29usize {
                if flag != 0usize { hidden = hidden | (1usize << index) } else { hidden = hidden & ~(1usize << index) }
                save_hidden(hidden)
            }
            let sent = os.send(REP, hidden, sysettings.NO_SLOT)
        } else if op == sysettings.OP_RESET {
            defaults(&store)
            save(&store)
            if radios_allowed(&store) != radios {
                radios = radios_allowed(&store)
                push_radio(radios)
            }
            push_notify_mask(&store)
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        }
    }
    say("settings server done\n")
    ret ok
}
