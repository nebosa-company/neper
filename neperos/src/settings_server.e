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

const REQ: usize = 2usize
const REP: usize = 3usize
const FS_REQ: usize = 4usize
const FS_REP: usize = 5usize
const REFUSED: usize = 18446744073709551615usize
const COUNT: usize = 40usize

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

fn defaults(store: *Store) {
    var i = 0usize
    while i < COUNT {
        store.v[i] = u8(theme.default_value(i))
        i += 1usize
    }
}

fn system_word(store: *Store) -> usize {
    ret theme.stored_word(store.v[0usize..COUNT])
}

fn main(a: *mem.Arena, args: []str) -> err {
    var store: Store = zero
    defaults(&store)
    if load(&store) { say("settings server loaded\n") }
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
            }
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        } else if op == sysettings.OP_RESET {
            defaults(&store)
            save(&store)
            let sent = os.send(REP, system_word(&store), sysettings.NO_SLOT)
        }
    }
    say("settings server done\n")
    ret ok
}
