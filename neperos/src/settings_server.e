// The settings server (C126): a process that holds the system's settings (the 40 values the Settings app
// shows, settings.e's numbering), answers reads from any process that was granted its endpoints, takes
// changes, keeps them in /settings through the filesystem server, and works out the system word
// (theme.e) that the shell and the apps follow. The kernel starts it in the lunar boot (archive entry 6,
// the wallpaper loader's slot in the older boot) and grants it: slot 2 requests in, slot 3 replies out,
// and, when the machine has a disk, slot 4 filesystem requests out and slot 5 filesystem replies in.
// Without a disk the settings live for the boot only.
use e.mem
use e.os
use e.time
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

// (D4000) What a receive with a deadline returns when the deadline passes first.
const TIMED_OUT: usize = 18446744073709551614usize

fn now_ms() -> usize {
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret 0usize }
    ret usize(now.nanos / 1000000i64)
}

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

// (C176) The links beside the uplink, gated like the radios by Airplane mode: bit 0 Bluetooth (setting 24), bit 1 Hotspot
// (setting 3). The network server starts with Bluetooth up and the Hotspot down, which is the settings' default (1), so
// nothing is sent at start unless the stored values differ.
const LINKS_DEFAULT: usize = 1usize

fn links_mask(store: *Store) -> usize {
    if store.v[2usize] != 0u8 { ret 0usize }
    var mask = 0usize
    if store.v[24usize] != 0u8 { mask = mask | 1usize }
    if store.v[3usize] != 0u8 { mask = mask | 2usize }
    ret mask
}

fn push_links(mask: usize) {
    let sent = os.send(NET_REQ, 10usize, sysettings.NO_SLOT)
    if sent == REFUSED { ret }
    let mask_sent = os.send(NET_REQ, mask, sysettings.NO_SLOT)
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

// (D4007) The background services process's request end (slot 11): the volumes and Vibrate as one word, whenever one
// changes and at start (the words are the process's bgclient.OP_VOLUMES: op 7, then media, ring and alarm volumes and
// Vibrate from bit 8); and the Clock's /clock in eleven words of six bytes (op 5, the chunk in bits 4-7), read once at
// start so the alarms ring after a restart without the Clock being opened.
const SERVICES_REQ: usize = 11usize

fn push_volumes(store: *Store) {
    let payload = usize(store.v[9usize]) | (usize(store.v[10usize]) << 8usize) | (usize(store.v[11usize]) << 16usize) | (usize(store.v[13usize]) << 24usize)
    let sent = os.send(SERVICES_REQ, 7usize | (payload << 8usize), sysettings.NO_SLOT)
}

fn push_clock() {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret }
    fsproto.send_str(FS_REQ, "/clock")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [64]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 64usize)
    if result != fsproto.RESULT_OK || count < 59usize { ret }
    var chunk = 0usize
    while chunk < 11usize {
        var payload = 0usize
        var k = 0usize
        while k < 6usize {
            let at = chunk * 6usize + k
            if at < 64usize { payload = payload | (usize(raw[at]) << (8usize * k)) }
            k += 1usize
        }
        let sent_chunk = os.send(SERVICES_REQ, 5usize | (chunk << 4usize) | (payload << 8usize), sysettings.NO_SLOT)
        chunk += 1usize
    }
}

fn system_word(store: *Store) -> usize {
    ret theme.stored_word(store.v[0usize..COUNT])
}

// How long a copy stays on the clipboard, in seconds, by Settings' choice (setting 35): 30 s, a minute, five minutes, fifteen.
fn clip_lifetime(choice: usize) -> usize {
    if choice == 1usize { ret 60usize }
    if choice == 2usize { ret 300usize }
    if choice == 3usize { ret 900usize }
    ret 30usize
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
    // (C163) The torch policy: the level last used (the toggle's on), and the monotonic millisecond at which the server
    // turns it off by itself (0 while it is off).
    var torch_last = 5usize
    var torch_until = 0usize
    // (C148) The clipboard: the text as four words, its length, owner and the second it was put.
    var clip: [4]usize = zero
    var clip_len = 0usize
    var clip_owner = 0usize
    var clip_stamp = 0usize
    var radios = radios_allowed(&store)
    if !radios { push_radio(false) }
    var links = links_mask(&store)
    if links != LINKS_DEFAULT { push_links(links) }
    push_notify_mask(&store)
    push_volumes(&store)
    push_clock()
    say("settings server up\n")
    var running = true
    while running {
        // (C163) While the torch is on under a limit the server wakes every half second to see whether it has passed.
        var wait_slot = sysettings.NO_SLOT
        if torch_until != 0usize { wait_slot = 1500usize }
        let op = os.recv(REQ, wait_slot)
        // The limit is checked at every request too, not only when the wait ran out: an app that polls the torch
        // would otherwise keep the server from ever timing out.
        if torch_until != 0usize && now_ms() >= torch_until {
            torch_level = 0usize
            torch_until = 0usize
            say("torch level 0 timeout\n")
        }
        if op == TIMED_OUT {
            running = true
        } else if op == sysettings.OP_QUIT {
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
                if (index == 2usize || index == 3usize || index == 24usize) && links_mask(&store) != links {
                    links = links_mask(&store)
                    push_links(links)
                }
                if index >= 26usize && index < 34usize { push_notify_mask(&store) }
                if index == 9usize || index == 10usize || index == 11usize || index == 13usize { push_volumes(&store) }
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
                if level != 0usize {
                    torch_last = level
                    torch_until = now_ms() + sysettings.TORCH_MAX_SECONDS * 1000usize
                } else {
                    torch_until = 0usize
                }
                say("torch level ")
                say_num(level)
                say("\n")
            }
            let sent = os.send(REP, torch_level, sysettings.NO_SLOT)
        } else if op == sysettings.OP_TORCH_FOR {
            let level = os.recv(REQ, sysettings.NO_SLOT)
            var seconds = os.recv(REQ, sysettings.NO_SLOT)
            if seconds == 0usize || seconds > sysettings.TORCH_MAX_SECONDS { seconds = sysettings.TORCH_MAX_SECONDS }
            if level <= 5usize {
                if level != 0usize {
                    torch_last = level
                    torch_until = now_ms() + seconds * 1000usize
                } else {
                    torch_until = 0usize
                }
                if level != torch_level {
                    torch_level = level
                    say("torch level ")
                    say_num(level)
                    say("\n")
                }
            }
            let sent = os.send(REP, torch_level, sysettings.NO_SLOT)
        } else if op == sysettings.OP_TORCH_TOGGLE {
            if torch_level == 0usize {
                torch_level = torch_last
                torch_until = now_ms() + sysettings.TORCH_MAX_SECONDS * 1000usize
            } else {
                torch_last = torch_level
                torch_level = 0usize
                torch_until = 0usize
            }
            say("torch level ")
            say_num(torch_level)
            say(" toggle\n")
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
            if clip_len > 0usize && asked_at >= clip_stamp && asked_at - clip_stamp > clip_lifetime(usize(store.v[sysettings.CLIP_LIFETIME_SETTING])) {
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
        } else if op == sysettings.OP_CLIP_CLEAR {
            let owner = os.recv(REQ, sysettings.NO_SLOT)
            var cleared = 0usize
            if clip_len > 0usize && clip_owner == owner {
                clip_len = 0usize
                clip[0usize] = 0usize
                clip[1usize] = 0usize
                clip[2usize] = 0usize
                clip[3usize] = 0usize
                cleared = 1usize
                say("clipboard cleared by owner ")
                say_num(owner)
                say("\n")
            }
            let sent = os.send(REP, cleared, sysettings.NO_SLOT)
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
            if links_mask(&store) != links {
                links = links_mask(&store)
                push_links(links)
            }
            push_notify_mask(&store)
            push_volumes(&store)
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        }
    }
    say("settings server done\n")
    ret ok
}
