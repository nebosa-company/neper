// SSH (D2215): the app behind the SSH icon, after Termius -- a list of hosts (a round terminal glyph, the
// alias, user@address, a dot for the ones used before), a form to add, edit or delete a host (alias,
// address, user, port, password or key) with an on-screen keyboard, and a terminal screen with a prompt,
// the output above it, a command history on the arrow keys, Ctrl-C and Clear, and the keyboard with a
// row of extra keys. Dark ground, cream rows and amber, like the other apps (appkit.e, taps from the
// compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: there is NO network yet (queue item C117), so Connect opens a LOCAL DEMO session, said so on
// screen: a small shell of sample commands (help, ls, pwd, whoami, hostname, date, uname, uptime, echo,
// clear, exit) that never leaves the process. The real client (key exchange, authentication, channels,
// keys kept in Secure, SFTP, port forwarding) is queued as C120. The hosts live in the process too.
// (C155) Beyond that: the Keys screen keeps ed25519 keys sealed in the Secure vault (a record /v/s<slot> next to
// Secure's own, opened with the master password), makes new ones or imports a seed from /ssh/import, and shows each
// one's public line; a host set to sign in with a key asks for the master password, takes its slot's key out of the
// vault and authenticates with it. Files on a host row opens an SFTP session (the `sftp` subsystem of a connection
// of its own, e.net.sftp): browse, download into /Downloads, upload a file of the device. The terminal has an Esc,
// Tab, Ctrl and arrow row and a symbol row, and PgUp/PgDn walk the scrollback the terminal keeps (200 lines).
use e.mem
use e.os
use e.time
use e.bytes as codec
use e.crypto.sign as sign
use e.net.sftp as sftp
use vault
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.net.ssh as sshc
use e.text.terminal as term
use appkit
use text
use lunar
use netclient
use netproto
use vaultfs

const NONE: usize = 99usize
const MAX_HOSTS: usize = 8usize
const MAX_LINES: usize = 64usize
const VISIBLE: usize = 16usize
const MAX_HITS: usize = 96usize
const HOSTS_SCREEN: usize = 0usize
const FORM_SCREEN: usize = 1usize
const TERMINAL_SCREEN: usize = 2usize
const KEYS_SCREEN: usize = 3usize
const SFTP_SCREEN: usize = 4usize
// How many keys the Keys screen holds, and how many entries and local files the SFTP screen lists.
const MAX_KEYS: usize = 3usize
const MAX_ENTRIES: usize = 10usize
const MAX_PICKS: usize = 5usize
// A live session's phases: the password, the host key question, running, over.
const PHASE_PASSWORD: usize = 1usize
const PHASE_HOST_KEY: usize = 2usize
const PHASE_RUNNING: usize = 3usize
const PHASE_OVER: usize = 4usize
const TERM_COLS: usize = 46usize
const TERM_ROWS: usize = 18usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn say_text(value: str) {
    var buffer: [40]u8 = zero
    var n = 0usize
    while n < value.len && n < 40usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn number(a: *mem.Arena, value: usize) -> str {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, 20usize - at)
    if buffer_error != ok { ret "0" }
    var i = 0usize
    while at + i < 20usize {
        buffer[i] = digits[at + i]
        i += 1usize
    }
    ret buffer[0usize..20usize - at]
}

fn join(a: *mem.Arena, first: str, second: str, third: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + third.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < third.len {
        buffer[n] = third[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

fn text_of(a: *mem.Arena, bytes: []const u8, length: usize) -> str {
    let (copy, copy_error) = mem.alloc[u8](a, length + 1usize)
    if copy_error != ok { ret "" }
    var i = 0usize
    while i < length {
        copy[i] = bytes[i]
        i += 1usize
    }
    ret copy[0usize..length]
}

fn weekday_short(day: usize) -> str {
    if day == 0usize { ret "Mon" }
    if day == 1usize { ret "Tue" }
    if day == 2usize { ret "Wed" }
    if day == 3usize { ret "Thu" }
    if day == 4usize { ret "Fri" }
    if day == 5usize { ret "Sat" }
    ret "Sun"
}

fn month_short(month: usize) -> str {
    if month == 0usize { ret "Jan" }
    if month == 1usize { ret "Feb" }
    if month == 2usize { ret "Mar" }
    if month == 3usize { ret "Apr" }
    if month == 4usize { ret "May" }
    if month == 5usize { ret "Jun" }
    if month == 6usize { ret "Jul" }
    if month == 7usize { ret "Aug" }
    if month == 8usize { ret "Sep" }
    if month == 9usize { ret "Oct" }
    if month == 10usize { ret "Nov" }
    ret "Dec"
}

// "Thu Oct 8 22:23 UTC" from the wall clock.
fn date_text(a: *mem.Arena) -> str {
    let (wall, wall_error) = time.now()
    if wall_error != ok { ret "date: no clock" }
    let seconds = usize(wall.nanos / 1000000000i64)
    let (month, date) = lunar.month_day(seconds)
    let weekday = (seconds / 86400usize + 3usize) % 7usize
    let minutes = (seconds % 86400usize) / 60usize
    var tens = ""
    if minutes % 60usize < 10usize { tens = "0" }
    ret join(a, join(a, weekday_short(weekday), " ", month_short(month)), " ", join(a, join(a, number(a, date), " ", number(a, minutes / 60usize)), ":", join(a, tens, number(a, minutes % 60usize), " UTC")))
}

// ----------------------------------------------------------------------------------------------
// State.

// `key_slot` is the Keys-screen key (0 to 2) a host signs in with when `key_auth` is set.
type Host = struct { alias: [16]u8, alias_len: usize, addr: [24]u8, addr_len: usize, user: [12]u8, user_len: usize, port: usize, key_auth: bool, seen: bool, used: bool, key_slot: usize }

type Line = struct { body: [48]u8, length: usize, kind: usize }

// (C155) A key of the Keys screen: its public key (the private seed stays sealed in the vault).
type KeyRec = struct { used: bool, pubkey: [32]u8 }

// (C155) One line of an SFTP directory listing, and one local file that can be uploaded.
type Entry = struct { name: [28]u8, name_len: usize, dir: bool, size: usize }

type Pick = struct { path: [40]u8, path_len: usize }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    hosts: [8]Host,
    screen: usize,
    // The host being connected to or edited, and the draft of the form.
    current: usize,
    editing: usize,
    draft: Host,
    focus: usize,
    // The terminal: the lines above the prompt, the command being typed and the last few commands.
    lines: [64]Line,
    line_total: usize,
    cmd: [40]u8,
    cmd_len: usize,
    history: [160]u8,
    history_len: [4]usize,
    history_total: usize,
    history_at: usize,
    // (C120) A live session over the network: its phase (0 is the local demo), the password being typed, the SSH
    // session and the terminal it draws, the host key's fingerprint shown to the user, and what is kept of the
    // keys accepted this run.
    live_arena: mem.Arena,
    live: bool,
    phase: usize,
    password: [64]u8,
    pw_len: usize,
    session: sshc.Session,
    tm: term.Terminal,
    net_buf: [2048]u8,
    announced: bool,
    known_keys: [256]u8,
    known: [8]bool,
    hits: [96]Hit,
    hit_total: usize,
    // (C155) The terminal's Ctrl modifier (the next letter goes as its control byte) and how many lines it is
    // scrolled back into its history.
    ctrl: bool,
    scroll: usize,
    // (C155) The Secure vault: whether it is open here, its key, and the master password being typed (on the Keys
    // screen, or on the terminal's prompt for a host that signs in with a key). `want_master` says the password
    // prompt of the terminal is the master password, not the host's.
    vault_open: bool,
    vault_key: [32]u8,
    master: [64]u8,
    master_len: usize,
    want_master: bool,
    keys: [3]KeyRec,
    key_note: [48]u8,
    key_note_len: usize,
    // The key a key-auth session signs with, between the unlock and the session's start.
    seed: [32]u8,
    have_seed: bool,
    // (C155) SFTP: the session is a subsystem's (no terminal), the reply bytes not yet decoded, the request id, the
    // folder shown and its entries, the local files offered for an upload, and the last result.
    sftp_mode: bool,
    sftp_started: bool,
    sftp_acc: [8192]u8,
    sftp_len: usize,
    sftp_drop: usize,
    sftp_id: u32,
    cwd: [64]u8,
    cwd_len: usize,
    entries: [10]Entry,
    entry_total: usize,
    picking: bool,
    picks: [5]Pick,
    pick_total: usize,
    sftp_note: [64]u8,
    sftp_note_len: usize,
}

fn make_host(alias: str, addr: str, user: str, port: usize, key_auth: bool, seen: bool) -> Host {
    var h: Host = zero
    var i = 0usize
    while i < alias.len && i < 16usize {
        h.alias[i] = alias[i]
        i += 1usize
    }
    h.alias_len = i
    i = 0usize
    while i < addr.len && i < 24usize {
        h.addr[i] = addr[i]
        i += 1usize
    }
    h.addr_len = i
    i = 0usize
    while i < user.len && i < 12usize {
        h.user[i] = user[i]
        i += 1usize
    }
    h.user_len = i
    h.port = port
    h.key_auth = key_auth
    h.seen = seen
    h.used = true
    ret h
}

fn add_host(s: *State, host: Host) -> bool {
    var i = 0usize
    while i < MAX_HOSTS {
        if !s.hosts[i].used {
            s.hosts[i] = host
            ret true
        }
        i += 1usize
    }
    ret false
}

fn count_hosts(s: *State) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        if s.hosts[i].used { n += 1usize }
        i += 1usize
    }
    ret n
}

// ----------------------------------------------------------------------------------------------
// (C155) The saved hosts and the host keys trusted before live on the disk when there is one: /ssh/hosts holds the
// eight slots (used, alias, address, user, port, flags), /ssh/known the trusted flags and the 32-byte Ed25519 keys by
// slot. A host whose address or port is edited loses its trusted key; a key that differs from the one trusted is
// refused (live_settle).

fn put_field(out: []u8, at: usize, bytes: []const u8, length: usize, cap: usize) -> usize {
    out[at] = u8(length)
    var i = 0usize
    while i < cap {
        out[at + 1usize + i] = 0u8
        if i < length { out[at + 1usize + i] = bytes[i] }
        i += 1usize
    }
    ret at + 1usize + cap
}

fn save_hosts(s: *State) {
    var buf: [480]u8 = zero
    var at = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        let h = s.hosts[i]
        if h.used { buf[at] = 1u8 } else { buf[at] = 0u8 }
        at += 1usize
        at = put_field(buf[0usize..], at, h.alias[0usize..], h.alias_len, 16usize)
        at = put_field(buf[0usize..], at, h.addr[0usize..], h.addr_len, 24usize)
        at = put_field(buf[0usize..], at, h.user[0usize..], h.user_len, 12usize)
        buf[at] = u8(h.port & 255usize)
        buf[at + 1usize] = u8(h.port >> 8usize)
        var flags = 0u8
        if h.key_auth { flags = flags | 1u8 }
        if h.seen { flags = flags | 2u8 }
        // (C155) Bits 2 and 3: the key a host signs in with.
        flags = flags | u8((h.key_slot & 3usize) << 2usize)
        buf[at + 2usize] = flags
        at += 3usize
        i += 1usize
    }
    let made = vaultfs.mkdir("/ssh")
    if vaultfs.write("/ssh/hosts", mem.address_of(&buf[0usize]), at) { say("ssh hosts kept\n") }
}

// Read /ssh/hosts into the slots; false when there is no such file (the sample hosts stay).
fn load_hosts(s: *State) -> bool {
    var buf: [480]u8 = zero
    let (n, found) = vaultfs.read("/ssh/hosts", mem.address_of(&buf[0usize]), 480usize)
    if !found || n < 59usize * MAX_HOSTS { ret false }
    var at = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        var h: Host = zero
        h.used = buf[at] == 1u8
        at += 1usize
        h.alias_len = usize(buf[at])
        if h.alias_len > 16usize { h.alias_len = 16usize }
        var k = 0usize
        while k < 16usize {
            h.alias[k] = buf[at + 1usize + k]
            k += 1usize
        }
        at += 17usize
        h.addr_len = usize(buf[at])
        if h.addr_len > 24usize { h.addr_len = 24usize }
        k = 0usize
        while k < 24usize {
            h.addr[k] = buf[at + 1usize + k]
            k += 1usize
        }
        at += 25usize
        h.user_len = usize(buf[at])
        if h.user_len > 12usize { h.user_len = 12usize }
        k = 0usize
        while k < 12usize {
            h.user[k] = buf[at + 1usize + k]
            k += 1usize
        }
        at += 13usize
        h.port = usize(buf[at]) | (usize(buf[at + 1usize]) << 8usize)
        h.key_auth = (buf[at + 2usize] & 1u8) != 0u8
        h.seen = (buf[at + 2usize] & 2u8) != 0u8
        h.key_slot = usize((buf[at + 2usize] >> 2u8) & 3u8)
        if h.key_slot >= MAX_KEYS { h.key_slot = 0usize }
        at += 3usize
        s.hosts[i] = h
        i += 1usize
    }
    ret true
}

fn save_known(s: *State) {
    var buf: [264]u8 = zero
    var i = 0usize
    while i < MAX_HOSTS {
        if s.known[i] { buf[i] = 1u8 }
        i += 1usize
    }
    i = 0usize
    while i < 256usize {
        buf[8usize + i] = s.known_keys[i]
        i += 1usize
    }
    let made = vaultfs.mkdir("/ssh")
    if vaultfs.write("/ssh/known", mem.address_of(&buf[0usize]), 264usize) { say("ssh known hosts kept\n") }
}

fn load_known(s: *State) -> bool {
    var buf: [264]u8 = zero
    let (n, found) = vaultfs.read("/ssh/known", mem.address_of(&buf[0usize]), 264usize)
    if !found || n < 264usize { ret false }
    var i = 0usize
    while i < MAX_HOSTS {
        s.known[i] = buf[i] == 1u8
        i += 1usize
    }
    i = 0usize
    while i < 256usize {
        s.known_keys[i] = buf[8usize + i]
        i += 1usize
    }
    ret true
}

// ----------------------------------------------------------------------------------------------
// (C155) Keys sealed in the Secure vault: the seed of key N is the record /v/s<N> (a tag byte 5 and the 32-byte
// ed25519 seed), under the key the master password derives; the public keys are derived when the vault opens.

fn say_long(value: str) {
    var buffer: [128]u8 = zero
    var n = 0usize
    while n < value.len && n < 128usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

fn key_name(a: *mem.Arena, slot: usize) -> str {
    ret join(a, "s", number(a, slot), "")
}

fn set_key_note(s: *State, line: str) {
    var n = 0usize
    while n < line.len && n < 48usize {
        s.key_note[n] = line[n]
        n += 1usize
    }
    s.key_note_len = n
}

// The vault's key from the master password in s.master: 0 opened, 1 wrong password, 2 no vault on this disk.
fn unlock_vault(a: *mem.Arena, s: *State) -> usize {
    var meta: [80]u8 = zero
    let (count, found) = vaultfs.read("/vmeta", mem.address_of(&meta[0usize]), 80usize)
    if !found { ret 2usize }
    let (key, unlock_error) = vault.meta_unlock(meta[0usize..count], s.master[0usize..s.master_len])
    if unlock_error == vault.WrongPassword { ret 1usize }
    if unlock_error != ok { ret 2usize }
    s.vault_key = key
    s.vault_open = true
    ret 0usize
}

// The seed of the key in `slot`, and whether there is one.
fn read_seed(a: *mem.Arena, s: *State, slot: usize) -> ([32]u8, bool) {
    var seed: [32]u8 = zero
    if !s.vault_open { ret (seed, false) }
    var record: [96]u8 = zero
    var plain: [48]u8 = zero
    let name = key_name(a, slot)
    let (count, found) = vaultfs.read(join(a, "/v/", name, ""), mem.address_of(&record[0usize]), 96usize)
    if !found { ret (seed, false) }
    let (n, open_error) = vault.open(s.vault_key, name, record[0usize..count], plain[0usize..])
    if open_error != ok || n != 33usize || plain[0usize] != 5u8 { ret (seed, false) }
    var i = 0usize
    while i < 32usize {
        seed[i] = plain[1usize + i]
        i += 1usize
    }
    ret (seed, true)
}

// Seal `seed` as the record of `slot`; whether the disk took it.
fn store_seed(a: *mem.Arena, s: *State, slot: usize, seed: [32]u8) -> bool {
    if !s.vault_open { ret false }
    var plain: [48]u8 = zero
    plain[0usize] = 5u8
    var i = 0usize
    while i < 32usize {
        plain[1usize + i] = seed[i]
        i += 1usize
    }
    var nonce: [16]u8 = zero
    if !vaultfs.random(mem.address_of(&nonce[0usize]), 2usize) { ret false }
    var record: [96]u8 = zero
    let name = key_name(a, slot)
    let (length, seal_error) = vault.seal(s.vault_key, nonce[0usize..], name, plain[0usize..33usize], record[0usize..])
    if seal_error != ok { ret false }
    let made = vaultfs.mkdir("/v")
    ret vaultfs.write(join(a, "/v/", name, ""), mem.address_of(&record[0usize]), length)
}

fn public_of(seed: [32]u8) -> ([32]u8, bool) {
    var none: [32]u8 = zero
    let (pubkey, public_error) = sign.ed25519_public_from_secret(sign.Ed25519SecretKey { bytes: seed })
    if public_error != ok { ret (none, false) }
    ret (pubkey.bytes, true)
}

// An authorized_keys line for a public key: ssh-ed25519 and the base64 of its wire blob.
fn public_line(a: *mem.Arena, pubkey: [32]u8) -> str {
    var blob: [51]u8 = zero
    blob[3usize] = 11u8
    let kind = "ssh-ed25519"
    var i = 0usize
    while i < 11usize {
        blob[4usize + i] = kind[i]
        i += 1usize
    }
    blob[18usize] = 32u8
    i = 0usize
    while i < 32usize {
        blob[19usize + i] = pubkey[i]
        i += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, 96usize)
    if out_error != ok { ret "ssh-ed25519" }
    let (encoded, encode_error) = codec.base64_encode(out[0usize..], blob[0usize..51usize], .Standard, true)
    if encode_error != ok { ret "ssh-ed25519" }
    ret join(a, "ssh-ed25519 ", encoded, "")
}

// The public keys of the slots that hold a key.
fn refresh_keys(a: *mem.Arena, s: *State) {
    var slot = 0usize
    while slot < MAX_KEYS {
        s.keys[slot].used = false
        let (seed, have) = read_seed(a, s, slot)
        if have {
            let (pubkey, derived) = public_of(seed)
            if derived {
                s.keys[slot].used = true
                s.keys[slot].pubkey = pubkey
            }
        }
        slot += 1usize
    }
}

fn free_key_slot(s: *State) -> usize {
    var slot = 0usize
    while slot < MAX_KEYS {
        if !s.keys[slot].used { ret slot }
        slot += 1usize
    }
    ret NONE
}

// A key from `seed` into a free slot; its slot or NONE.
fn add_key(a: *mem.Arena, s: *State, seed: [32]u8) -> usize {
    let slot = free_key_slot(s)
    if slot == NONE {
        set_key_note(s, "The keychain is full")
        ret NONE
    }
    if !store_seed(a, s, slot, seed) {
        set_key_note(s, "The disk would not take the key")
        ret NONE
    }
    refresh_keys(a, s)
    ret slot
}

fn hex_digit(c: u8) -> usize {
    if c >= 48u8 && c <= 57u8 { ret usize(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret usize(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret usize(c - 55u8) }
    ret 99usize
}

// A new key from random bytes.
fn new_key(a: *mem.Arena, s: *State) -> usize {
    var seed: [32]u8 = zero
    if !vaultfs.random(mem.address_of(&seed[0usize]), 4usize) {
        set_key_note(s, "No random source")
        ret NONE
    }
    ret add_key(a, s, seed)
}

// A key from /ssh/import: 64 hex digits (the seed of an ed25519 key).
fn import_key(a: *mem.Arena, s: *State) -> usize {
    var text_in: [96]u8 = zero
    let (n, found) = vaultfs.read("/ssh/import", mem.address_of(&text_in[0usize]), 96usize)
    if !found || n < 64usize {
        set_key_note(s, "Put 64 hex digits in /ssh/import")
        ret NONE
    }
    var seed: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        let hi = hex_digit(text_in[2usize * i])
        let lo = hex_digit(text_in[2usize * i + 1usize])
        if hi == 99usize || lo == 99usize {
            set_key_note(s, "That is not hex")
            ret NONE
        }
        seed[i] = u8(hi * 16usize + lo)
        i += 1usize
    }
    ret add_key(a, s, seed)
}

fn alias_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.alias[0usize..], h.alias_len)
}

fn user_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.user[0usize..], h.user_len)
}

fn addr_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.addr[0usize..], h.addr_len)
}

// ----------------------------------------------------------------------------------------------
// The demo shell.

fn push_line(s: *State, body: str, kind: usize) {
    if s.line_total == MAX_LINES {
        var k = 1usize
        while k < MAX_LINES {
            s.lines[k - 1usize] = s.lines[k]
            k += 1usize
        }
        s.line_total -= 1usize
    }
    var line: Line = zero
    var i = 0usize
    while i < body.len && i < 48usize {
        line.body[i] = body[i]
        i += 1usize
    }
    line.length = i
    line.kind = kind
    s.lines[s.line_total] = line
    s.line_total += 1usize
}

fn prompt_text(a: *mem.Arena, s: *State) -> str {
    let h = s.hosts[s.current]
    ret join(a, join(a, user_of(a, h), "@", alias_of(a, h)), ":~$ ", "")
}

fn command_is(s: *State, word: str) -> bool {
    if s.cmd_len != word.len { ret false }
    var i = 0usize
    while i < word.len {
        if s.cmd[i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

fn command_starts(s: *State, word: str) -> bool {
    if s.cmd_len < word.len { ret false }
    var i = 0usize
    while i < word.len {
        if s.cmd[i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

fn remember(s: *State) {
    if s.cmd_len == 0usize { ret }
    // The newest command goes in slot 0 of four; the others move down.
    var slot = 3usize
    while slot > 0usize {
        var i = 0usize
        while i < 40usize {
            s.history[slot * 40usize + i] = s.history[(slot - 1usize) * 40usize + i]
            i += 1usize
        }
        s.history_len[slot] = s.history_len[slot - 1usize]
        slot -= 1usize
    }
    var j = 0usize
    while j < s.cmd_len {
        s.history[j] = s.cmd[j]
        j += 1usize
    }
    s.history_len[0usize] = s.cmd_len
    if s.history_total < 4usize { s.history_total += 1usize }
}

// Run the command typed: echo it with its prompt, print the output, start a new line.
fn run_command(a: *mem.Arena, s: *State) {
    let typed = text_of(a, s.cmd[0usize..], s.cmd_len)
    push_line(s, join(a, prompt_text(a, s), typed, ""), 1usize)
    remember(s)
    s.history_at = 0usize
    if s.cmd_len > 0usize {
        say("ssh command ")
        say_text(typed)
        say("\n")
    }
    let h = s.hosts[s.current]
    if s.cmd_len == 0usize {
    } else if command_is(s, "help") {
        push_line(s, "help ls pwd whoami hostname date uname", 0usize)
        push_line(s, "uptime echo clear exit", 0usize)
    } else if command_is(s, "ls") {
        push_line(s, "bin  docs  logs  notes.txt  projects", 0usize)
    } else if command_is(s, "pwd") {
        push_line(s, join(a, "/home/", user_of(a, h), ""), 0usize)
    } else if command_is(s, "whoami") {
        push_line(s, user_of(a, h), 0usize)
    } else if command_is(s, "hostname") {
        push_line(s, alias_of(a, h), 0usize)
    } else if command_is(s, "date") {
        push_line(s, date_text(a), 0usize)
    } else if command_is(s, "uname") {
        push_line(s, join(a, "Linux ", alias_of(a, h), " 6.8.0 aarch64"), 0usize)
    } else if command_is(s, "uptime") {
        push_line(s, "up 12 days, 3:41, load 0.12 0.09 0.05", 0usize)
    } else if command_starts(s, "echo ") {
        push_line(s, text_of(a, s.cmd[5usize..], s.cmd_len - 5usize), 0usize)
    } else if command_is(s, "clear") {
        s.line_total = 0usize
    } else if command_is(s, "exit") {
        s.screen = HOSTS_SCREEN
        say("ssh closed\n")
    } else {
        push_line(s, join(a, "sh: ", typed, ": command not found"), 0usize)
    }
    s.cmd_len = 0usize
}

// ----------------------------------------------------------------------------------------------
// A live session.

// Send what the SSH session has queued; false when the network refused it.
fn live_flush(s: *State) -> bool {
    if s.session.out_len == 0usize { ret true }
    let r = netclient.send(mem.address_of(&s.session.outbuf[0usize]), s.session.out_len)
    if r != netproto.R_OK { ret false }
    sshc.sent(&s.session, s.session.out_len)
    ret true
}

fn live_end(s: *State, why: str) {
    if s.phase == PHASE_OVER { ret }
    s.phase = PHASE_OVER
    push_line(s, why, 2usize)
    say("ssh live over\n")
}

// What the session's state means for the screen: the host key to confirm, the shell ready, the output to draw.
fn live_settle(a: *mem.Arena, s: *State) {
    let status = sshc.status(&s.session)
    if status == sshc.HOST_KEY_PENDING && s.phase == PHASE_PASSWORD {
        var fp: [64]u8 = zero
        let n = sshc.host_fingerprint(&s.session, fp[0usize..64usize])
        // A key accepted before in this run is trusted again; a different one for the same host is refused.
        let key = sshc.host_key(&s.session)
        if s.known[s.current] {
            var same = true
            var i = 0usize
            while i < 32usize {
                if s.known_keys[s.current * 32usize + i] != key[i] { same = false }
                i += 1usize
            }
            if same {
                sshc.trust(&s.session)
                s.phase = PHASE_RUNNING
                say("ssh live known host\n")
            } else {
                live_end(s, "HOST KEY CHANGED: connection refused")
                say("ssh live host key changed\n")
                ret
            }
        } else {
            push_line(s, "The authenticity of this host", 2usize)
            push_line(s, "is unknown. Its key is:", 2usize)
            push_line(s, text_of(a, fp[0usize..], n), 0usize)
            push_line(s, "Trust it? Type yes and Enter.", 2usize)
            s.phase = PHASE_HOST_KEY
            s.cmd_len = 0usize
            say("ssh live host key ")
            say_text(text_of(a, fp[0usize..], n))
            say("\n")
        }
    }
    if status == sshc.READY && !s.announced {
        s.announced = true
        s.phase = PHASE_RUNNING
        say("ssh live ready\n")
        if s.sftp_mode {
            // The subsystem is open: the SFTP screen takes over, and the protocol starts (sftp_begin).
            s.screen = SFTP_SCREEN
            s.sftp_len = 0usize
            s.sftp_drop = 0usize
        }
    }
    if status == sshc.FAILED {
        if s.session.failure == sshc.FAIL_AUTH {
            if s.want_master {
                live_end(s, "Permission denied (the key was not accepted)")
            } else {
                live_end(s, "Permission denied (wrong password)")
            }
        } else {
            live_end(s, "The session failed")
        }
    }
    if status == sshc.CLOSED {
        live_end(s, "Connection closed")
        if s.session.has_exit_status {
            say("ssh live exit ")
            say_text(number(a, usize(s.session.exit_status)))
            say("\n")
        }
    }
    // The program's output goes to the terminal.
    var chunk: [512]u8 = zero
    var more = true
    while more {
        let n = sshc.read(&s.session, chunk[0usize..512usize])
        if n == 0usize {
            more = false
        } else if s.sftp_mode {
            // (C155) An SFTP session's bytes are the server's packets.
            var k = 0usize
            while k < n && s.sftp_len < 8192usize {
                s.sftp_acc[s.sftp_len] = chunk[k]
                s.sftp_len += 1usize
                k += 1usize
            }
        } else {
            term.feed(&s.tm, chunk[0usize..n])
        }
    }
}

// Receive what the server has sent (waiting a moment) and settle; `tries` polls at most.
fn live_poll(a: *mem.Arena, s: *State, tries: usize) {
    var t = 0usize
    while t < tries && s.phase != PHASE_OVER {
        let (n, r) = netclient.poll(mem.address_of(&s.net_buf[0usize]), 2048usize)
        if r == netproto.R_EMPTY {
            t = tries
        } else if r != netproto.R_OK {
            live_end(s, "Network error")
            ret
        } else if n == 0usize {
            live_end(s, "Connection closed by the host")
            ret
        } else {
            let fed = sshc.feed(&s.session, s.net_buf[0usize..n])
            if !live_flush(s) {
                live_end(s, "Network error")
                ret
            }
            live_settle(a, s)
            t += 1usize
        }
    }
}

// Start the session once the password is typed: random bytes, then the version exchange.
fn live_start(a: *mem.Arena, s: *State) {
    var random: [64]u8 = zero
    if !vaultfs.random(mem.address_of(&random[0usize]), 8usize) {
        live_end(s, "No random source")
        ret
    }
    let h = s.hosts[s.current]
    // (C155) A host that signs in with a key sends no password: the seed the vault gave is the credential.
    var secret = text_of(a, s.password[0usize..], s.pw_len)
    if s.have_seed { secret = "" }
    let (opened, open_error) = sshc.open(&s.live_arena, random[0usize..64usize], user_of(a, h), secret, u32(TERM_COLS), u32(TERM_ROWS))
    if open_error != ok {
        live_end(s, "Could not start the session")
        ret
    }
    s.session = opened
    if s.have_seed {
        sshc.use_key(&s.session, s.seed)
        var wipe = 0usize
        while wipe < 32usize {
            s.seed[wipe] = 0u8
            wipe += 1usize
        }
        s.have_seed = false
    }
    if s.sftp_mode { sshc.set_subsystem(&s.session, "sftp") }
    s.pw_len = 0usize
    s.announced = false
    if !live_flush(s) {
        live_end(s, "Network error")
        ret
    }
    // The handshake: poll until it settles at the host key question, the shell, or a failure.
    var rounds = 0usize
    while rounds < 40usize && s.phase == PHASE_PASSWORD {
        live_poll(a, s, 1usize)
        rounds += 1usize
        if sshc.status(&s.session) == sshc.FAILED { rounds = 40usize }
    }
}

// Keys to the remote program.
fn live_send(a: *mem.Arena, s: *State, bytes: []const u8) {
    if s.phase != PHASE_RUNNING { ret }
    let taken = sshc.write(&s.session, bytes)
    if !live_flush(s) {
        live_end(s, "Network error")
        ret
    }
    live_poll(a, s, 4usize)
}

fn live_close(s: *State) {
    if !s.live { ret }
    if s.phase != PHASE_OVER {
        sshc.close(&s.session)
        let flushed = live_flush(s)
    }
    let closed = netclient.close()
    s.live = false
    s.phase = 0usize
}

fn connect(a: *mem.Arena, s: *State, index: usize, sftp_session: bool) {
    s.current = index
    s.hosts[index].seen = true
    s.screen = TERMINAL_SCREEN
    s.line_total = 0usize
    s.cmd_len = 0usize
    s.history_at = 0usize
    s.live = false
    s.phase = 0usize
    s.sftp_mode = sftp_session
    s.sftp_started = false
    s.ctrl = false
    s.scroll = 0usize
    s.have_seed = false
    s.picking = false
    s.sftp_note_len = 0usize
    let h = s.hosts[index]
    s.want_master = h.key_auth
    let r = netclient.connect(addr_of(a, h), u16(h.port), false)
    if r == netproto.R_OK {
        // The session and the terminal live outside the per-frame arena: their memory is reserved at start.
        s.live_arena.off = 0usize
        let (t, t_error) = term.open(&s.live_arena, TERM_COLS, TERM_ROWS, 200usize)
        if t_error == ok {
            s.tm = t
            s.live = true
            s.phase = PHASE_PASSWORD
            s.pw_len = 0usize
            push_line(s, join(a, "Connected to ", addr_of(a, h), ""), 2usize)
            if h.key_auth {
                push_line(s, join(a, join(a, "Key ", number(a, h.key_slot + 1usize), " of the keychain."), "", ""), 2usize)
                push_line(s, "Master password (Secure):", 2usize)
            } else {
                push_line(s, join(a, user_of(a, h), "'s password:", ""), 2usize)
            }
            say("ssh connected ")
            say_text(alias_of(a, h))
            say("\n")
            say("ssh live connected\n")
            ret
        }
        let closed = netclient.close()
    }
    push_line(s, "Local demo session: no network yet.", 2usize)
    push_line(s, join(a, join(a, "Connected to ", alias_of(a, h), " ("), join(a, user_of(a, h), "@", join(a, addr_of(a, h), ":", join(a, number(a, h.port), ")", ""))), ""), 2usize)
    push_line(s, "Type help for commands.", 2usize)
    say("ssh connected ")
    say_text(alias_of(a, h))
    say("\n")
}

// ----------------------------------------------------------------------------------------------
// (C155) SFTP: version 3 packets (e.net.sftp) over the subsystem channel of a connection of its own. Each call waits
// for its reply (polling the network a moment at a time, bounded), so a listing, a download or an upload is done when
// the call returns.

fn set_sftp_note(s: *State, line: str) {
    var n = 0usize
    while n < line.len && n < 64usize {
        s.sftp_note[n] = line[n]
        n += 1usize
    }
    s.sftp_note_len = n
}

// An SFTP packet onto the channel (the window may take it in pieces).
fn sftp_send(a: *mem.Arena, s: *State, packet: []const u8) -> bool {
    var at = 0usize
    var tries = 0usize
    while at < packet.len && tries < 100usize {
        let taken = sshc.write(&s.session, packet[at..])
        at += taken
        tries += 1usize
        if !live_flush(s) { ret false }
        if at < packet.len { live_poll(a, s, 2usize) }
    }
    ret at == packet.len
}

// The next whole reply (its slices point into the receive buffer and hold until the next call).
fn sftp_reply(a: *mem.Arena, s: *State, names: []sftp.Name) -> (sftp.Response, bool) {
    var none: sftp.Response = zero
    if s.sftp_drop > 0usize {
        var k = s.sftp_drop
        while k < s.sftp_len {
            s.sftp_acc[k - s.sftp_drop] = s.sftp_acc[k]
            k += 1usize
        }
        s.sftp_len -= s.sftp_drop
        s.sftp_drop = 0usize
    }
    var rounds = 0usize
    while rounds < 150usize && s.phase != PHASE_OVER {
        if s.sftp_len > 0usize {
            let (used, response, decode_error) = sftp.decode(s.sftp_acc[0usize..s.sftp_len], names)
            if decode_error == ok {
                s.sftp_drop = used
                ret (response, true)
            }
            if decode_error != sftp.Incomplete { ret (none, false) }
        }
        live_poll(a, s, 2usize)
        rounds += 1usize
    }
    ret (none, false)
}

fn sftp_next_id(s: *State) -> u32 {
    s.sftp_id += 1u32
    ret s.sftp_id
}

// The folder path and `name` as one path.
fn sftp_join(a: *mem.Arena, s: *State, name: str) -> str {
    let folder = text_of(a, s.cwd[0usize..], s.cwd_len)
    if folder.len == 1usize { ret join(a, "/", name, "") }
    ret join(a, folder, "/", name)
}

// The protocol's start: INIT and VERSION, then the folder the server calls ".".
fn sftp_begin(a: *mem.Arena, s: *State) -> bool {
    var req: [256]u8 = zero
    var names: [4]sftp.Name = zero
    let (n0, e0) = sftp.encode_init(req[0usize..256usize], 3u32)
    if e0 != ok || !sftp_send(a, s, req[0usize..n0]) { ret false }
    let (r0, ok0) = sftp_reply(a, s, names[0usize..4usize])
    if !ok0 || r0.kind != sftp.FXP_VERSION || r0.version != 3u32 { ret false }
    let (n1, e1) = sftp.encode_path(req[0usize..256usize], sftp.FXP_REALPATH, sftp_next_id(s), ".")
    if e1 != ok || !sftp_send(a, s, req[0usize..n1]) { ret false }
    let (r1, ok1) = sftp_reply(a, s, names[0usize..4usize])
    if !ok1 || r1.kind != sftp.FXP_NAME || r1.count < 1usize { ret false }
    var k = 0usize
    while k < names[0].filename.len && k < 64usize {
        s.cwd[k] = names[0].filename[k]
        k += 1usize
    }
    s.cwd_len = k
    say("ssh sftp ready ")
    say_text(text_of(a, s.cwd[0usize..], s.cwd_len))
    say("\n")
    ret true
}

// The folder in s.cwd as entries.
fn sftp_list(a: *mem.Arena, s: *State) -> bool {
    var req: [512]u8 = zero
    var names: [16]sftp.Name = zero
    s.entry_total = 0usize
    let (n0, e0) = sftp.encode_path(req[0usize..512usize], sftp.FXP_OPENDIR, sftp_next_id(s), text_of(a, s.cwd[0usize..], s.cwd_len))
    if e0 != ok || !sftp_send(a, s, req[0usize..n0]) { ret false }
    let (r0, ok0) = sftp_reply(a, s, names[0usize..16usize])
    if !ok0 || r0.kind != sftp.FXP_HANDLE || r0.handle.len > 64usize {
        set_sftp_note(s, "The folder cannot be opened")
        ret false
    }
    var handle: [64]u8 = zero
    let handle_len = r0.handle.len
    var h = 0usize
    while h < handle_len {
        handle[h] = r0.handle[h]
        h += 1usize
    }
    var rounds = 0usize
    var more = true
    while more && rounds < 4usize {
        rounds += 1usize
        let (n1, e1) = sftp.encode_handle(req[0usize..512usize], sftp.FXP_READDIR, sftp_next_id(s), handle[0usize..handle_len])
        if e1 != ok || !sftp_send(a, s, req[0usize..n1]) { ret false }
        let (r1, ok1) = sftp_reply(a, s, names[0usize..16usize])
        if !ok1 { ret false }
        if r1.kind != sftp.FXP_NAME {
            more = false
        } else {
            var i = 0usize
            while i < r1.count {
                let name = names[i].filename
                let skip = name.len == 0usize || (name.len == 1usize && name[0usize] == 46u8) || (name.len == 2usize && name[0usize] == 46u8 && name[1usize] == 46u8)
                if !skip && s.entry_total < MAX_ENTRIES {
                    var e: Entry = zero
                    var c = 0usize
                    while c < name.len && c < 28usize {
                        e.name[c] = name[c]
                        c += 1usize
                    }
                    e.name_len = c
                    let a_flags = names[i].attrs.flags
                    if (a_flags & sftp.ATTR_PERMISSIONS) != 0u32 && (names[i].attrs.permissions & 61440u32) == 16384u32 { e.dir = true }
                    if (a_flags & sftp.ATTR_SIZE) != 0u32 { e.size = usize(names[i].attrs.size) }
                    s.entries[s.entry_total] = e
                    s.entry_total += 1usize
                }
                i += 1usize
            }
        }
    }
    let (n2, e2) = sftp.encode_handle(req[0usize..512usize], sftp.FXP_CLOSE, sftp_next_id(s), handle[0usize..handle_len])
    if e2 == ok && sftp_send(a, s, req[0usize..n2]) {
        let (r2, ok2) = sftp_reply(a, s, names[0usize..16usize])
    }
    say("ssh sftp listed ")
    say_text(number(a, s.entry_total))
    say("\n")
    ret true
}

// The entry's file into /Downloads (up to 24 KB).
fn sftp_download(a: *mem.Arena, s: *State, index: usize) -> bool {
    if index >= s.entry_total || s.entries[index].dir { ret false }
    var req: [512]u8 = zero
    var names: [4]sftp.Name = zero
    let name = text_of(a, s.entries[index].name[0usize..], s.entries[index].name_len)
    let path = sftp_join(a, s, name)
    let (n0, e0) = sftp.encode_open(req[0usize..512usize], sftp_next_id(s), path, sftp.OPEN_READ, sftp.no_attrs())
    if e0 != ok || !sftp_send(a, s, req[0usize..n0]) { ret false }
    let (r0, ok0) = sftp_reply(a, s, names[0usize..4usize])
    if !ok0 || r0.kind != sftp.FXP_HANDLE || r0.handle.len > 64usize {
        set_sftp_note(s, "The file cannot be opened")
        ret false
    }
    var handle: [64]u8 = zero
    let handle_len = r0.handle.len
    var h = 0usize
    while h < handle_len {
        handle[h] = r0.handle[h]
        h += 1usize
    }
    let (store, store_error) = mem.alloc[u8](a, 24576usize)
    if store_error != ok { ret false }
    var total = 0usize
    var reading = true
    while reading && total < 24576usize {
        var want = 24576usize - total
        if want > 2048usize { want = 2048usize }
        let (n1, e1) = sftp.encode_read(req[0usize..512usize], sftp_next_id(s), handle[0usize..handle_len], u64(total), u32(want))
        if e1 != ok || !sftp_send(a, s, req[0usize..n1]) { ret false }
        let (r1, ok1) = sftp_reply(a, s, names[0usize..4usize])
        if !ok1 { ret false }
        if r1.kind != sftp.FXP_DATA {
            reading = false
        } else {
            var c = 0usize
            while c < r1.data.len && total + c < 24576usize {
                store[total + c] = r1.data[c]
                c += 1usize
            }
            total += c
            if r1.data.len == 0usize { reading = false }
        }
    }
    let (n2, e2) = sftp.encode_handle(req[0usize..512usize], sftp.FXP_CLOSE, sftp_next_id(s), handle[0usize..handle_len])
    if e2 == ok && sftp_send(a, s, req[0usize..n2]) {
        let (r2, ok2) = sftp_reply(a, s, names[0usize..4usize])
    }
    let made = vaultfs.mkdir("/Downloads")
    if !vaultfs.write_big(join(a, "/Downloads/", name, ""), mem.address_of(&store[0usize]), total) {
        set_sftp_note(s, "The device would not take the file")
        ret false
    }
    say("ssh sftp downloaded ")
    say_text(name)
    say(" ")
    say_text(number(a, total))
    say("\n")
    set_sftp_note(s, join(a, "Saved in Downloads: ", name, ""))
    ret true
}

// The local file at `path` into the folder shown, as `name` (up to 8 KB).
fn sftp_upload(a: *mem.Arena, s: *State, path: str, name: str) -> bool {
    let (size, kind, day, found) = vaultfs.stat(path)
    if !found || size == 0usize || size > 8192usize { ret false }
    let (data, data_error) = mem.alloc[u8](a, size)
    if data_error != ok { ret false }
    let (got, read_ok) = vaultfs.read_big(path, mem.address_of(&data[0usize]), size)
    if !read_ok || got != size { ret false }
    var req: [3072]u8 = zero
    var names: [4]sftp.Name = zero
    let remote = sftp_join(a, s, name)
    let (n0, e0) = sftp.encode_open(req[0usize..3072usize], sftp_next_id(s), remote, sftp.OPEN_WRITE | sftp.OPEN_CREAT | sftp.OPEN_TRUNC, sftp.no_attrs())
    if e0 != ok || !sftp_send(a, s, req[0usize..n0]) { ret false }
    let (r0, ok0) = sftp_reply(a, s, names[0usize..4usize])
    if !ok0 || r0.kind != sftp.FXP_HANDLE || r0.handle.len > 64usize {
        set_sftp_note(s, "The file cannot be created")
        ret false
    }
    var handle: [64]u8 = zero
    let handle_len = r0.handle.len
    var h = 0usize
    while h < handle_len {
        handle[h] = r0.handle[h]
        h += 1usize
    }
    var at = 0usize
    var good = true
    while at < size && good {
        var piece = size - at
        if piece > 2048usize { piece = 2048usize }
        let (n1, e1) = sftp.encode_write(req[0usize..3072usize], sftp_next_id(s), handle[0usize..handle_len], u64(at), data[at..at + piece])
        if e1 != ok || !sftp_send(a, s, req[0usize..n1]) { ret false }
        let (r1, ok1) = sftp_reply(a, s, names[0usize..4usize])
        if !ok1 || r1.kind != sftp.FXP_STATUS || r1.status != sftp.FX_OK { good = false }
        at += piece
    }
    let (n2, e2) = sftp.encode_handle(req[0usize..3072usize], sftp.FXP_CLOSE, sftp_next_id(s), handle[0usize..handle_len])
    if e2 == ok && sftp_send(a, s, req[0usize..n2]) {
        let (r2, ok2) = sftp_reply(a, s, names[0usize..4usize])
    }
    if !good {
        set_sftp_note(s, "The upload failed")
        ret false
    }
    say("ssh sftp uploaded ")
    say_text(name)
    say(" ")
    say_text(number(a, size))
    say("\n")
    set_sftp_note(s, join(a, "Uploaded: ", name, ""))
    ret true
}

// One more local file to offer for an upload: `dir`/`name`.
fn add_pick(s: *State, dir: str, names: []const u8, from: usize, to: usize) {
    if s.pick_total >= MAX_PICKS || dir.len + (to - from) > 39usize { ret }
    var p: Pick = zero
    var n = 0usize
    while n < dir.len {
        p.path[n] = dir[n]
        n += 1usize
    }
    var i = from
    while i < to {
        p.path[n] = names[i]
        n += 1usize
        i += 1usize
    }
    p.path_len = n
    s.picks[s.pick_total] = p
    s.pick_total += 1usize
}

// The files of /Downloads and of the root folder (names with a dot), for Upload.
fn list_picks(a: *mem.Arena, s: *State) {
    s.pick_total = 0usize
    var names: [512]u8 = zero
    let (dl_bytes, dl_listed) = vaultfs.list("/Downloads", mem.address_of(&names[0usize]), 512usize)
    if dl_listed {
        var start = 0usize
        var pos = 0usize
        while pos < dl_bytes {
            if names[pos] == 10u8 {
                if pos > start { add_pick(s, "/Downloads/", names[0usize..], start, pos) }
                start = pos + 1usize
            }
            pos += 1usize
        }
    }
    var root: [512]u8 = zero
    let (root_bytes, root_listed) = vaultfs.list("/", mem.address_of(&root[0usize]), 512usize)
    if root_listed {
        var start = 0usize
        var pos = 0usize
        while pos < root_bytes {
            if root[pos] == 10u8 {
                var dotted = false
                var d = start
                while d < pos {
                    if root[d] == 46u8 { dotted = true }
                    d += 1usize
                }
                if dotted { add_pick(s, "/", root[0usize..], start, pos) }
                start = pos + 1usize
            }
            pos += 1usize
        }
    }
}

// The SFTP screen's first fill once the subsystem is open: the protocol's start and the first folder.
fn sftp_enter(a: *mem.Arena, s: *State) {
    s.sftp_started = true
    if !sftp_begin(a, s) {
        set_sftp_note(s, "The server did not start SFTP")
        say("ssh sftp failed to start\n")
        ret
    }
    let listed = sftp_list(a, s)
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream() -> paint.Color {
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn muted() -> paint.Color {
    ret appkit.muted()
}

fn light() -> paint.Color {
    ret appkit.light()
}

fn light_muted() -> paint.Color {
    ret appkit.light_muted()
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn tint_of(index: usize) -> paint.Color {
    let n = index % 6usize
    if n == 0usize { ret paint.Color { red: 0.85, green: 0.60, blue: 0.45, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.55, green: 0.72, blue: 0.62, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.60, green: 0.66, blue: 0.85, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.82, green: 0.62, blue: 0.75, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.88, green: 0.76, blue: 0.45, alpha: 1.0 } }
    ret paint.Color { red: 0.62, green: 0.78, blue: 0.80, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn disc(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.ellipse_path(a, cx, cy, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn hit(s: *State, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if s.hit_total < MAX_HITS {
        s.hits[s.hit_total] = Hit { id: id, x: x, y: y, w: w, h: h }
        s.hit_total += 1usize
    }
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn prompt_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M4 7l6 5-6 5' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/><path d='M12 18h8' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round'/></svg>"
}

// ---- the keyboard: digits, three rows of letters, a row with - / space . and Enter.

fn number_label(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    if n == 7usize { ret "7" }
    if n == 8usize { ret "8" }
    ret "9"
}

fn letter_row(row: usize) -> str {
    if row == 0usize { ret "qwertyuiop" }
    if row == 1usize { ret "asdfghjkl" }
    ret "zxcvbnm"
}

fn key_cap(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 2.0, w, 48.0, 10.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.35 })
    try card(a, builder, x, y, w, 48.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 20.0, label, x + w / 2.0, y + 24.0 - 12.0, ink())
    hit(s, id, x, y, w, 48.0)
    ret ok
}

fn draw_keyboard(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var d = 0usize
    while d < 10usize {
        try key_cap(a, builder, s, faces, 1100usize + d, 18.0 + f32(d) * 38.0, 500.0, 34.0, number_label((d + 1usize) % 10usize), soft())
        d += 1usize
    }
    var row = 0usize
    while row < 3usize {
        let letters = letter_row(row)
        var x0: f32 = 18.0
        if row == 1usize { x0 = 37.0 }
        if row == 2usize { x0 = 18.0 + 52.0 }
        var k = 0usize
        while k < letters.len {
            let ch = usize(letters[k])
            let (one, one_error) = mem.alloc[u8](a, 1usize)
            if one_error != ok { ret one_error }
            one[0usize] = letters[k]
            try key_cap(a, builder, s, faces, 1000usize + ch - 97usize, x0 + f32(k) * 38.0, 558.0 + f32(row) * 58.0, 34.0, one[0usize..1usize], cream())
            k += 1usize
        }
        row += 1usize
    }
    try key_cap(a, builder, s, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, s, faces, 1203usize, 18.0, 732.0, 44.0, "-", soft())
    try key_cap(a, builder, s, faces, 1204usize, 68.0, 732.0, 44.0, "/", soft())
    try key_cap(a, builder, s, faces, 1200usize, 118.0, 732.0, 130.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 254.0, 732.0, 44.0, ".", soft())
    try key_cap(a, builder, s, faces, 1205usize, 304.0, 732.0, 90.0, "Enter", amber())
    ret ok
}

// ---- the hosts.

fn draw_hosts(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 34.0, "Hosts", 24.0, 40.0, light())
    try pill(a, builder, s, faces, 160usize, 300.0, 44.0, 96.0, 38.0, "Keys", soft(), 15.0)
    try put(a, builder, faces.grotesk, 12.0, "Saved hosts: a live SSH session, or a local demo", 24.0, 86.0, light_muted())
    var row = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        if s.hosts[i].used {
            let h = s.hosts[i]
            let y: f32 = 112.0 + f32(row) * 80.0
            try card(a, builder, 16.0, y, 380.0, 68.0, 20.0, cream())
            try disc(a, builder, 50.0, y + 34.0, 22.0, tint_of(i))
            try svg.draw(a, builder, prompt_icon(), geometry.rect(38.0, y + 22.0, 24.0, 24.0), ink())
            try clipped(a, builder, faces.jost_bold, 18.0, alias_of(a, h), 86.0, y + 12.0, 230.0, ink())
            try clipped(a, builder, faces.grotesk, 13.0, join(a, join(a, user_of(a, h), "@", addr_of(a, h)), "", ""), 86.0, y + 40.0, 230.0, muted())
            var dot = soft()
            if h.seen { dot = paint.Color { red: 0.13, green: 0.52, blue: 0.28, alpha: 1.0 } }
            try disc(a, builder, 370.0, y + 22.0, 5.0, dot)
            try put(a, builder, faces.grotesk, 11.0, "edit", 356.0 - 8.0, y + 44.0, muted())
            // (C155) Files opens an SFTP session on the host.
            try put(a, builder, faces.grotesk, 11.0, "files", 270.0, y + 44.0, muted())
            hit(s, 100usize + i, 16.0, y, 240.0, 68.0)
            hit(s, 400usize + i, 256.0, y, 60.0, 68.0)
            hit(s, 300usize + i, 316.0, y, 80.0, 68.0)
            row += 1usize
        }
        i += 1usize
    }
    try card(a, builder, 252.0, 780.0, 144.0, 56.0, 28.0, amber())
    try card(a, builder, 274.0 - 9.0, 808.0 - 1.5, 18.0, 3.0, 1.5, ink())
    try card(a, builder, 274.0 - 1.5, 808.0 - 9.0, 3.0, 18.0, 1.5, ink())
    try put(a, builder, faces.jost, 17.0, "New host", 298.0, 797.0, ink())
    hit(s, 150usize, 252.0, 780.0, 144.0, 56.0)
    ret ok
}

// ---- the form.

fn field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, which: usize, label: str, value: str, y: f32) -> err {
    try put(a, builder, faces.grotesk, 12.0, label, 20.0, y - 16.0, light_muted())
    if s.focus == which { try card(a, builder, 14.0, y - 2.0, 384.0, 52.0, 18.0, amber()) }
    try card(a, builder, 16.0, y, 380.0, 48.0, 16.0, cream())
    try clipped(a, builder, faces.jost, 19.0, value, 32.0, y + 12.0, 340.0, ink())
    if s.focus == which {
        var caret_x: f32 = 32.0
        if value.len > 0usize { caret_x = 32.0 + text.measure(a, faces.jost, 19.0, value) + 2.0 }
        if caret_x > 372.0 { caret_x = 372.0 }
        try card(a, builder, caret_x, y + 11.0, 2.0, 26.0, 1.0, amber())
    }
    hit(s, 1500usize + which, 16.0, y, 380.0, 48.0)
    ret ok
}

fn draw_form(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "New host"
    if s.editing != NONE { heading = "Edit host" }
    try put(a, builder, faces.jost_bold, 30.0, heading, 24.0, 28.0, light())
    try field(a, builder, s, faces, 0usize, "Alias", alias_of(a, s.draft), 90.0)
    try field(a, builder, s, faces, 1usize, "Address", addr_of(a, s.draft), 160.0)
    try field(a, builder, s, faces, 2usize, "User", user_of(a, s.draft), 230.0)
    // The port and the sign-in.
    var port_22 = soft()
    var port_2222 = soft()
    if s.draft.port == 22usize { port_22 = amber() } else { port_2222 = amber() }
    try put(a, builder, faces.grotesk, 12.0, "Port", 20.0, 284.0, light_muted())
    try pill(a, builder, s, faces, 1320usize, 16.0, 304.0, 60.0, 36.0, "22", port_22, 15.0)
    try pill(a, builder, s, faces, 1321usize, 72.0, 304.0, 76.0, 36.0, "2222", port_2222, 15.0)
    var password_fill = soft()
    var key_fill = soft()
    if s.draft.key_auth { key_fill = amber() } else { password_fill = amber() }
    try put(a, builder, faces.grotesk, 12.0, "Sign in with", 180.0, 284.0, light_muted())
    try pill(a, builder, s, faces, 1330usize, 180.0, 304.0, 120.0, 36.0, "Password", password_fill, 15.0)
    // (C155) A second tap on Key moves to the next key of the keychain.
    try pill(a, builder, s, faces, 1331usize, 308.0, 304.0, 88.0, 36.0, join(a, "Key ", number(a, s.draft.key_slot + 1usize), ""), key_fill, 15.0)
    // Save, Connect and Cancel or Delete.
    try pill(a, builder, s, faces, 1300usize, 16.0, 366.0, 120.0, 48.0, "Save", amber(), 17.0)
    try pill(a, builder, s, faces, 1303usize, 146.0, 366.0, 120.0, 48.0, "Connect", soft(), 17.0)
    if s.editing != NONE {
        try pill(a, builder, s, faces, 1301usize, 276.0, 366.0, 120.0, 48.0, "Delete", soft(), 17.0)
    } else {
        try pill(a, builder, s, faces, 1302usize, 276.0, 366.0, 120.0, 48.0, "Cancel", soft(), 17.0)
    }
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

// ---- (C155) the keys and the files.

fn draw_keys(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), light())
    hit(s, 800usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 28.0, "Keys", 64.0, 18.0, light())
    try put(a, builder, faces.grotesk, 12.0, "ed25519 keys, sealed in the Secure vault", 24.0, 66.0, light_muted())
    if !s.vault_open {
        try put(a, builder, faces.grotesk, 12.0, "Master password of the Secure vault", 20.0, 100.0, light_muted())
        try card(a, builder, 14.0, 118.0, 384.0, 52.0, 18.0, amber())
        try card(a, builder, 16.0, 120.0, 380.0, 48.0, 16.0, cream())
        var dots: [64]u8 = zero
        var d = 0usize
        while d < s.master_len && d < 64usize {
            dots[d] = 42u8
            d += 1usize
        }
        try put(a, builder, faces.jost, 19.0, text_of(a, dots[0usize..], s.master_len), 32.0, 132.0, ink())
        if s.key_note_len > 0usize { try put(a, builder, faces.jost, 14.0, text_of(a, s.key_note[0usize..], s.key_note_len), 20.0, 184.0, light()) }
        try draw_keyboard(a, builder, s, faces)
        ret ok
    }
    var slot = 0usize
    while slot < MAX_KEYS {
        let y: f32 = 100.0 + f32(slot) * 84.0
        try card(a, builder, 16.0, y, 380.0, 76.0, 18.0, cream())
        if s.keys[slot].used {
            let line = public_line(a, s.keys[slot].pubkey)
            try put(a, builder, faces.jost_bold, 17.0, join(a, "Key ", number(a, slot + 1usize), ""), 32.0, y + 10.0, ink())
            try clipped(a, builder, faces.grotesk, 11.0, line, 32.0, y + 40.0, 250.0, muted())
            try pill(a, builder, s, faces, 810usize + slot, 316.0, y + 18.0, 64.0, 40.0, "Del", soft(), 14.0)
        } else {
            try put(a, builder, faces.jost, 17.0, join(a, "Slot ", number(a, slot + 1usize), " is empty"), 32.0, y + 26.0, muted())
        }
        slot += 1usize
    }
    try pill(a, builder, s, faces, 820usize, 16.0, 366.0, 180.0, 48.0, "New key", amber(), 17.0)
    try pill(a, builder, s, faces, 821usize, 216.0, 366.0, 180.0, 48.0, "Import", soft(), 17.0)
    try put(a, builder, faces.grotesk, 12.0, "Import reads 64 hex digits from /ssh/import.", 20.0, 428.0, light_muted())
    if s.key_note_len > 0usize { try put(a, builder, faces.jost, 14.0, text_of(a, s.key_note[0usize..], s.key_note_len), 20.0, 452.0, light()) }
    ret ok
}

fn draw_sftp(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let h = s.hosts[s.current]
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 22.0, alias_of(a, h), 64.0, 14.0, light())
    try clipped(a, builder, faces.grotesk, 12.0, join(a, "files  ", text_of(a, s.cwd[0usize..], s.cwd_len), ""), 64.0, 46.0, 330.0, light_muted())
    if s.picking {
        try put(a, builder, faces.jost, 17.0, "Upload which file?", 24.0, 84.0, light())
        var i = 0usize
        while i < s.pick_total {
            let y: f32 = 120.0 + f32(i) * 52.0
            try card(a, builder, 16.0, y, 380.0, 44.0, 14.0, cream())
            try clipped(a, builder, faces.jost, 16.0, text_of(a, s.picks[i].path[0usize..], s.picks[i].path_len), 30.0, y + 12.0, 350.0, ink())
            hit(s, 700usize + i, 16.0, y, 380.0, 44.0)
            i += 1usize
        }
        if s.pick_total == 0usize { try put(a, builder, faces.jost, 16.0, "No files on this device to upload", 24.0, 130.0, light_muted()) }
        try pill(a, builder, s, faces, 710usize, 16.0, 420.0, 120.0, 44.0, "Cancel", soft(), 16.0)
        ret ok
    }
    var i = 0usize
    while i < s.entry_total {
        let y: f32 = 84.0 + f32(i) * 46.0
        try card(a, builder, 16.0, y, 380.0, 40.0, 12.0, cream())
        var label = text_of(a, s.entries[i].name[0usize..], s.entries[i].name_len)
        if s.entries[i].dir { label = join(a, label, "/", "") }
        try clipped(a, builder, faces.jost, 16.0, label, 30.0, y + 10.0, 250.0, ink())
        if !s.entries[i].dir {
            try put(a, builder, faces.grotesk, 12.0, join(a, number(a, s.entries[i].size), " B", ""), 310.0, y + 12.0, muted())
        }
        hit(s, 600usize + i, 16.0, y, 380.0, 40.0)
        i += 1usize
    }
    if s.entry_total == 0usize { try put(a, builder, faces.jost, 16.0, "This folder is empty", 24.0, 100.0, light_muted()) }
    try pill(a, builder, s, faces, 630usize, 16.0, 560.0, 112.0, 46.0, "Up", soft(), 16.0)
    try pill(a, builder, s, faces, 631usize, 150.0, 560.0, 112.0, 46.0, "Upload", amber(), 16.0)
    try pill(a, builder, s, faces, 632usize, 284.0, 560.0, 112.0, 46.0, "Refresh", soft(), 16.0)
    if s.sftp_note_len > 0usize { try put(a, builder, faces.jost, 14.0, text_of(a, s.sftp_note[0usize..], s.sftp_note_len), 20.0, 624.0, light()) }
    if s.phase == PHASE_OVER { try put(a, builder, faces.grotesk, 12.0, "The connection is closed", 20.0, 654.0, light_muted()) }
    ret ok
}

// ---- the terminal.

fn line_color(kind: usize) -> paint.Color {
    if kind == 1usize { ret paint.Color { red: 0.55, green: 0.82, blue: 0.62, alpha: 1.0 } }
    if kind == 2usize { ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
    ret paint.Color { red: 0.86, green: 0.88, blue: 0.86, alpha: 1.0 }
}

fn extra_key(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y, w, 36.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 13.0, label, x + w / 2.0, y + 18.0 - 9.0, ink())
    hit(s, id, x, y, w, 36.0)
    ret ok
}

fn draw_terminal(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let h = s.hosts[s.current]
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 14.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 22.0, alias_of(a, h), 64.0, 16.0, light())
    try disc(a, builder, 72.0, 56.0, 4.0, paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 })
    var mode_label = "demo session"
    if s.live { mode_label = "live session" }
    try put(a, builder, faces.grotesk, 12.0, mode_label, 82.0, 49.0, light_muted())
    try card(a, builder, 16.0, 80.0, 380.0, 322.0, 16.0, paint.Color { red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0 })
    if s.scroll > 0usize {
        try put(a, builder, faces.grotesk, 12.0, join(a, "scrollback ", number(a, s.scroll), " lines up"), 250.0, 56.0, amber())
    }
    if s.live && (s.phase == PHASE_RUNNING || (s.phase == PHASE_OVER && s.announced)) {
        try draw_grid(a, builder, s, faces)
        try draw_extra_keys(a, builder, s, faces)
        ret ok
    }
    var first = 0usize
    if s.line_total > VISIBLE { first = s.line_total - VISIBLE }
    var row = 0usize
    while first + row < s.line_total {
        let line = s.lines[first + row]
        try clipped(a, builder, faces.grotesk, 13.0, text_of(a, line.body[0usize..], line.length), 28.0, 92.0 + f32(row) * 18.0, 356.0, line_color(line.kind))
        row += 1usize
    }
    // The prompt with what is typed and a block cursor.
    var prompt = join(a, prompt_text(a, s), text_of(a, s.cmd[0usize..], s.cmd_len), "")
    if s.live && s.phase == PHASE_PASSWORD {
        // The password is never shown: a dot for each character.
        var dots: [64]u8 = zero
        var d = 0usize
        while d < s.pw_len && d < 64usize {
            dots[d] = 42u8
            d += 1usize
        }
        prompt = text_of(a, dots[0usize..], s.pw_len)
    }
    if s.live && s.phase == PHASE_HOST_KEY { prompt = join(a, "> ", text_of(a, s.cmd[0usize..], s.cmd_len), "") }
    let y: f32 = 92.0 + f32(row) * 18.0
    try clipped(a, builder, faces.grotesk, 13.0, prompt, 28.0, y, 356.0, line_color(1usize))
    var cursor_x = 28.0 + text.measure(a, faces.grotesk, 13.0, prompt) + 1.0
    if cursor_x > 380.0 { cursor_x = 380.0 }
    try card(a, builder, cursor_x, y + 1.0, 7.0, 15.0, 1.0, amber())
    try draw_extra_keys(a, builder, s, faces)
    ret ok
}

// (C155) Two rows above the keyboard: the control keys (Esc, Tab, Ctrl as a modifier for the next letter, the four
// arrows, Clear) and the symbols a phone keyboard buries, with PgUp and PgDn for the scrollback.
fn draw_extra_keys(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var ctrl_fill = soft()
    if s.ctrl { ctrl_fill = amber() }
    try extra_key(a, builder, s, faces, 1216usize, 16.0, 408.0, 44.0, "Esc", soft())
    try extra_key(a, builder, s, faces, 1217usize, 64.0, 408.0, 44.0, "Tab", soft())
    try extra_key(a, builder, s, faces, 1218usize, 112.0, 408.0, 44.0, "Ctrl", ctrl_fill)
    try extra_key(a, builder, s, faces, 1219usize, 160.0, 408.0, 44.0, "Left", soft())
    try extra_key(a, builder, s, faces, 1213usize, 208.0, 408.0, 44.0, "Down", soft())
    try extra_key(a, builder, s, faces, 1212usize, 256.0, 408.0, 44.0, "Up", soft())
    try extra_key(a, builder, s, faces, 1220usize, 304.0, 408.0, 44.0, "Right", soft())
    try extra_key(a, builder, s, faces, 1215usize, 352.0, 408.0, 44.0, "Clr", soft())
    try extra_key(a, builder, s, faces, 1211usize, 16.0, 452.0, 44.0, "~", soft())
    try extra_key(a, builder, s, faces, 1230usize, 64.0, 452.0, 44.0, "|", soft())
    try extra_key(a, builder, s, faces, 1231usize, 112.0, 452.0, 44.0, "_", soft())
    try extra_key(a, builder, s, faces, 1232usize, 160.0, 452.0, 44.0, ":", soft())
    try extra_key(a, builder, s, faces, 1233usize, 208.0, 452.0, 44.0, ";", soft())
    try extra_key(a, builder, s, faces, 1234usize, 256.0, 452.0, 44.0, "\\", soft())
    try extra_key(a, builder, s, faces, 1221usize, 304.0, 452.0, 44.0, "PgUp", soft())
    try extra_key(a, builder, s, faces, 1222usize, 352.0, 452.0, 44.0, "PgDn", soft())
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

// A terminal colour code (see e.text.terminal) as a paint colour; `fallback` for the default.
fn term_colour(code: u32, fallback: paint.Color) -> paint.Color {
    if code == 0u32 { ret fallback }
    if code >= 16777216u32 {
        ret paint.Color { red: f32((code >> 16u32) & 255u32) / 255.0, green: f32((code >> 8u32) & 255u32) / 255.0, blue: f32(code & 255u32) / 255.0, alpha: 1.0 }
    }
    var index = 0u32
    if code >= 256u32 { index = code & 255u32 } else { index = code - 1u32 }
    if index < 16u32 {
        var bright: f32 = 0.0
        var base = index
        if index >= 8u32 {
            bright = 0.25
            base = index - 8u32
        }
        // black, red, green, yellow, blue, magenta, cyan, white
        let r: f32 = f32(base & 1u32) * 0.62 + bright
        let g: f32 = f32((base >> 1u32) & 1u32) * 0.62 + bright
        let b: f32 = f32((base >> 2u32) & 1u32) * 0.62 + bright
        if base == 0u32 { ret paint.Color { red: 0.1 + bright, green: 0.1 + bright, blue: 0.1 + bright, alpha: 1.0 } }
        if base == 7u32 { ret paint.Color { red: 0.78 + bright * 0.8, green: 0.78 + bright * 0.8, blue: 0.78 + bright * 0.8, alpha: 1.0 } }
        ret paint.Color { red: r, green: g, blue: b, alpha: 1.0 }
    }
    if index >= 232u32 {
        let v: f32 = (8.0 + f32(index - 232u32) * 10.0) / 255.0
        ret paint.Color { red: v, green: v, blue: v, alpha: 1.0 }
    }
    // The 6 x 6 x 6 cube.
    let c = index - 16u32
    let steps = "\x00\x5f\x87\xaf\xd7\xff"
    let r2 = f32(u32(steps[usize(c / 36u32)])) / 255.0
    let g2 = f32(u32(steps[usize((c / 6u32) % 6u32)])) / 255.0
    let b2 = f32(u32(steps[usize(c % 6u32)])) / 255.0
    ret paint.Color { red: r2, green: g2, blue: b2, alpha: 1.0 }
}

// A code point as UTF-8 in the arena (a question mark for what is out of range).
fn char_text(a: *mem.Arena, cp: u32) -> str {
    let (out, out_error) = mem.alloc[u8](a, 4usize)
    if out_error != ok { ret "?" }
    if cp < 128u32 {
        out[0usize] = u8(cp)
        ret out[0usize..1usize]
    }
    if cp < 2048u32 {
        out[0usize] = u8(192u32 | (cp >> 6u32))
        out[1usize] = u8(128u32 | (cp & 63u32))
        ret out[0usize..2usize]
    }
    if cp < 65536u32 {
        out[0usize] = u8(224u32 | (cp >> 12u32))
        out[1usize] = u8(128u32 | ((cp >> 6u32) & 63u32))
        out[2usize] = u8(128u32 | (cp & 63u32))
        ret out[0usize..3usize]
    }
    ret "?"
}

// The terminal's cells, one at a time on a fixed grid, with its cursor.
fn draw_grid(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let cell_w: f32 = 7.7
    let cell_h: f32 = 17.0
    var y = 0usize
    while y < s.tm.rows {
        var x = 0usize
        while x < s.tm.cols {
            // (C155) Scrolled back by `scroll` lines: the rows above the screen come from the history (line 0 the
            // newest), the rest of the screen moves down.
            var c = term.blank_cell()
            if y >= s.scroll {
                c = term.cell(&s.tm, x, y - s.scroll)
            } else {
                c = term.history_cell(&s.tm, s.scroll - y - 1usize, x)
            }
            var fg = term_colour(c.fg, paint.Color { red: 0.86, green: 0.88, blue: 0.86, alpha: 1.0 })
            var bg = term_colour(c.bg, paint.Color { red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0 })
            if (c.attrs & term.REVERSE) != 0u32 {
                let swap = fg
                fg = bg
                bg = swap
            }
            let px: f32 = 26.0 + f32(x) * cell_w
            let py: f32 = 88.0 + f32(y) * cell_h
            if c.bg != 0u32 || (c.attrs & term.REVERSE) != 0u32 {
                try card(a, builder, px, py, cell_w + 0.5, cell_h, 0.0, bg)
            }
            if c.ch > 32u32 {
                try put(a, builder, faces.grotesk, 13.0, char_text(a, c.ch), px, py + 1.0, fg)
            }
            x += 1usize
        }
        y += 1usize
    }
    if s.tm.cursor_visible && s.phase == PHASE_RUNNING && s.scroll == 0usize {
        try card(a, builder, 26.0 + f32(s.tm.cx) * cell_w, 88.0 + f32(s.tm.cy) * cell_h + 13.0, cell_w, 3.0, 1.0, amber())
    }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: appkit.ground_color(0.08, 0.09, 0.11, 1.0 - f32(kit.frame % 2usize) * 0.002) } } })
    if s.screen == HOSTS_SCREEN {
        try draw_hosts(a, builder, s, faces)
    } else if s.screen == FORM_SCREEN {
        try draw_form(a, builder, s, faces)
    } else if s.screen == KEYS_SCREEN {
        try draw_keys(a, builder, s, faces)
    } else if s.screen == SFTP_SCREEN {
        try draw_sftp(a, builder, s, faces)
    } else {
        try draw_terminal(a, builder, s, faces)
    }
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    let draw_error = draw(a, &builder, kit, s)
    if draw_error != ok {
        say("ssh draw failed\n")
        ret false
    }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

// A character from the keyboard goes to the command in the terminal, or to the field in focus.
fn type_byte(s: *State, byte: u8) {
    // (C155) The Keys screen's only field is the vault's master password.
    if s.screen == KEYS_SCREEN {
        if s.master_len < 64usize {
            s.master[s.master_len] = byte
            s.master_len += 1usize
        }
        ret
    }
    if s.screen == TERMINAL_SCREEN && s.live {
        if s.phase == PHASE_PASSWORD && s.pw_len < 64usize {
            s.password[s.pw_len] = byte
            s.pw_len += 1usize
        } else if s.phase == PHASE_HOST_KEY && s.cmd_len < 40usize {
            s.cmd[s.cmd_len] = byte
            s.cmd_len += 1usize
        }
        ret
    }
    if s.screen == TERMINAL_SCREEN {
        if s.cmd_len < 40usize {
            s.cmd[s.cmd_len] = byte
            s.cmd_len += 1usize
        }
        ret
    }
    if s.focus == 0usize && s.draft.alias_len < 16usize {
        s.draft.alias[s.draft.alias_len] = byte
        s.draft.alias_len += 1usize
    }
    if s.focus == 1usize && s.draft.addr_len < 24usize {
        s.draft.addr[s.draft.addr_len] = byte
        s.draft.addr_len += 1usize
    }
    if s.focus == 2usize && s.draft.user_len < 12usize {
        s.draft.user[s.draft.user_len] = byte
        s.draft.user_len += 1usize
    }
}

fn backspace(s: *State) {
    if s.screen == KEYS_SCREEN {
        if s.master_len > 0usize { s.master_len -= 1usize }
        ret
    }
    if s.screen == TERMINAL_SCREEN && s.live {
        if s.phase == PHASE_PASSWORD && s.pw_len > 0usize { s.pw_len -= 1usize }
        if s.phase == PHASE_HOST_KEY && s.cmd_len > 0usize { s.cmd_len -= 1usize }
        ret
    }
    if s.screen == TERMINAL_SCREEN {
        if s.cmd_len > 0usize { s.cmd_len -= 1usize }
        ret
    }
    if s.focus == 0usize && s.draft.alias_len > 0usize { s.draft.alias_len -= 1usize }
    if s.focus == 1usize && s.draft.addr_len > 0usize { s.draft.addr_len -= 1usize }
    if s.focus == 2usize && s.draft.user_len > 0usize { s.draft.user_len -= 1usize }
}

fn open_form(s: *State, index: usize) {
    s.screen = FORM_SCREEN
    s.editing = index
    s.focus = 0usize
    if index == NONE {
        s.draft = make_host("", "", "", 22usize, false, false)
        s.draft.alias_len = 0usize
    } else {
        s.draft = s.hosts[index]
    }
}

// Keep the draft: a new host or the edited one. False when a field is empty.
fn save_draft(s: *State) -> bool {
    if s.draft.alias_len == 0usize || s.draft.addr_len == 0usize || s.draft.user_len == 0usize { ret false }
    if s.editing == NONE {
        if !add_host(s, s.draft) { ret false }
    } else {
        // A key trusted for an address is not trusted for another.
        let before = s.hosts[s.editing]
        var moved = before.port != s.draft.port || before.addr_len != s.draft.addr_len
        var k = 0usize
        while k < before.addr_len && k < s.draft.addr_len {
            if before.addr[k] != s.draft.addr[k] { moved = true }
            k += 1usize
        }
        if moved && s.known[s.editing] {
            s.known[s.editing] = false
            save_known(s)
        }
        s.hosts[s.editing] = s.draft
    }
    say("ssh saved\n")
    save_hosts(s)
    ret true
}

// Put history entry `at` (0 = newest) on the command line.
fn recall(s: *State, at: usize) {
    var i = 0usize
    while i < s.history_len[at] {
        s.cmd[i] = s.history[at * 40usize + i]
        i += 1usize
    }
    s.cmd_len = s.history_len[at]
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == HOSTS_SCREEN {
        if id >= 100usize && id < 108usize {
            if s.hosts[id - 100usize].used {
                connect(a, s, id - 100usize, false)
                ret true
            }
            ret false
        }
        // (C155) Files: an SFTP session on the host.
        if id >= 400usize && id < 408usize {
            if s.hosts[id - 400usize].used {
                connect(a, s, id - 400usize, true)
                ret true
            }
            ret false
        }
        if id >= 300usize && id < 308usize {
            open_form(s, id - 300usize)
            ret true
        }
        if id == 150usize {
            if count_hosts(s) < MAX_HOSTS { open_form(s, NONE) }
            ret true
        }
        // (C155) Keys.
        if id == 160usize {
            s.screen = KEYS_SCREEN
            s.key_note_len = 0usize
            s.master_len = 0usize
            if s.vault_open { refresh_keys(a, s) }
            say("ssh keys shown\n")
            ret true
        }
        ret false
    }
    // (C155) The Keys screen: the master password opens the vault, then keys are made, imported and deleted.
    if s.screen == KEYS_SCREEN {
        if id == 800usize {
            s.screen = HOSTS_SCREEN
            ret true
        }
        if !s.vault_open {
            if id == 1205usize {
                let opened = unlock_vault(a, s)
                s.master_len = 0usize
                if opened == 0usize {
                    s.key_note_len = 0usize
                    refresh_keys(a, s)
                    say("ssh keys unlocked\n")
                } else if opened == 1usize {
                    set_key_note(s, "Wrong master password")
                    say("ssh keys wrong password\n")
                } else {
                    set_key_note(s, "No vault: make one in Secure first")
                    say("ssh keys no vault\n")
                }
                ret true
            }
            if id == 1201usize {
                backspace(s)
                ret true
            }
            if id >= 1000usize && id < 1026usize {
                type_byte(s, u8(97usize + id - 1000usize))
                ret true
            }
            if id >= 1100usize && id < 1110usize {
                type_byte(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
                ret true
            }
            if id == 1200usize {
                type_byte(s, 32u8)
                ret true
            }
            if id == 1202usize {
                type_byte(s, 46u8)
                ret true
            }
            if id == 1203usize {
                type_byte(s, 45u8)
                ret true
            }
            if id == 1204usize {
                type_byte(s, 47u8)
                ret true
            }
            ret false
        }
        if id == 820usize || id == 821usize {
            var slot = NONE
            if id == 820usize { slot = new_key(a, s) } else { slot = import_key(a, s) }
            if slot != NONE {
                set_key_note(s, join(a, "Key ", number(a, slot + 1usize), " added"))
                say("ssh key created slot ")
                say_text(number(a, slot))
                say("\n")
                say("ssh key public ")
                say_long(public_line(a, s.keys[slot].pubkey))
                say("\n")
            }
            ret true
        }
        if id >= 810usize && id < 810usize + MAX_KEYS {
            let gone = vaultfs.remove(join(a, "/v/", key_name(a, id - 810usize), ""))
            refresh_keys(a, s)
            set_key_note(s, "Key deleted")
            say("ssh key deleted slot ")
            say_text(number(a, id - 810usize))
            say("\n")
            ret true
        }
        ret false
    }
    // The back arrow.
    if id == 500usize {
        s.screen = HOSTS_SCREEN
        if s.live {
            live_close(s)
            say("ssh live closed\n")
        }
        s.sftp_mode = false
        if s.line_total > 0usize || s.cmd_len > 0usize { say("ssh closed\n") }
        ret true
    }
    // (C155) The SFTP screen: a folder's entries (a tap opens a folder or downloads a file), Up, Upload, Refresh.
    if s.screen == SFTP_SCREEN {
        if s.picking {
            if id == 710usize {
                s.picking = false
                ret true
            }
            if id >= 700usize && id < 700usize + MAX_PICKS {
                let index = id - 700usize
                s.picking = false
                if index < s.pick_total {
                    let path = text_of(a, s.picks[index].path[0usize..], s.picks[index].path_len)
                    var leaf = 0usize
                    var k = 0usize
                    while k < s.picks[index].path_len {
                        if s.picks[index].path[k] == 47u8 { leaf = k + 1usize }
                        k += 1usize
                    }
                    let name = text_of(a, s.picks[index].path[leaf..], s.picks[index].path_len - leaf)
                    if sftp_upload(a, s, path, name) { let relisted = sftp_list(a, s) }
                }
                ret true
            }
            ret false
        }
        if id >= 600usize && id < 600usize + MAX_ENTRIES {
            let index = id - 600usize
            if index >= s.entry_total { ret false }
            if s.entries[index].dir {
                let subfolder = sftp_join(a, s, text_of(a, s.entries[index].name[0usize..], s.entries[index].name_len))
                var n = 0usize
                while n < subfolder.len && n < 64usize {
                    s.cwd[n] = subfolder[n]
                    n += 1usize
                }
                s.cwd_len = n
                let listed = sftp_list(a, s)
            } else {
                let got = sftp_download(a, s, index)
            }
            ret true
        }
        if id == 630usize {
            // Up: the folder above, `/` at the top.
            var n = s.cwd_len
            while n > 1usize && s.cwd[n - 1usize] != 47u8 { n -= 1usize }
            if n > 1usize { n -= 1usize }
            s.cwd_len = n
            let listed = sftp_list(a, s)
            ret true
        }
        if id == 631usize {
            list_picks(a, s)
            s.picking = true
            ret true
        }
        if id == 632usize {
            let listed = sftp_list(a, s)
            ret true
        }
        ret false
    }
    // (C155) Esc, Tab, Ctrl, PgUp and PgDn, which no program but a live session answers to.
    if s.screen == TERMINAL_SCREEN && id == 1218usize {
        s.ctrl = !s.ctrl
        ret true
    }
    if s.screen == TERMINAL_SCREEN && (id == 1221usize || id == 1222usize) {
        if s.live {
            let history = term.history_lines(&s.tm)
            if id == 1221usize {
                s.scroll += 9usize
                if s.scroll > history { s.scroll = history }
            } else if s.scroll >= 9usize {
                s.scroll -= 9usize
            } else {
                s.scroll = 0usize
            }
            say("ssh scrollback ")
            say_text(number(a, s.scroll))
            say("\n")
        }
        ret true
    }
    // A live session sends its keys to the host as they are tapped.
    if s.screen == TERMINAL_SCREEN && s.live && s.phase == PHASE_RUNNING && !s.sftp_mode {
        var one: [3]u8 = zero
        var n = 0usize
        if id >= 1000usize && id < 1026usize {
            one[0usize] = u8(97usize + id - 1000usize)
            n = 1usize
            // Ctrl then a letter is the control byte (Ctrl-C is 3).
            if s.ctrl {
                one[0usize] = u8(1usize + id - 1000usize)
                s.ctrl = false
            }
        } else if id >= 1100usize && id < 1110usize {
            one[0usize] = u8(48usize + (id - 1100usize + 1usize) % 10usize)
            n = 1usize
        } else if id == 1200usize {
            one[0usize] = 32u8
            n = 1usize
        } else if id == 1201usize {
            one[0usize] = 127u8
            n = 1usize
        } else if id == 1202usize {
            one[0usize] = 46u8
            n = 1usize
        } else if id == 1203usize {
            one[0usize] = 45u8
            n = 1usize
        } else if id == 1204usize {
            one[0usize] = 47u8
            n = 1usize
        } else if id == 1205usize {
            one[0usize] = 13u8
            n = 1usize
        } else if id == 1211usize {
            one[0usize] = 126u8
            n = 1usize
        } else if id == 1212usize {
            one[0usize] = 27u8
            one[1usize] = 91u8
            one[2usize] = 65u8
            n = 3usize
        } else if id == 1213usize {
            one[0usize] = 27u8
            one[1usize] = 91u8
            one[2usize] = 66u8
            n = 3usize
        } else if id == 1214usize {
            one[0usize] = 3u8
            n = 1usize
        } else if id == 1215usize {
            one[0usize] = 12u8
            n = 1usize
        } else if id == 1216usize {
            one[0usize] = 27u8
            n = 1usize
        } else if id == 1217usize {
            one[0usize] = 9u8
            n = 1usize
        } else if id == 1219usize {
            one[0usize] = 27u8
            one[1usize] = 91u8
            one[2usize] = 68u8
            n = 3usize
        } else if id == 1220usize {
            one[0usize] = 27u8
            one[1usize] = 91u8
            one[2usize] = 67u8
            n = 3usize
        } else if id >= 1230usize && id <= 1234usize {
            // | _ : ; and the backslash.
            let symbols = "|_:;\\"
            one[0usize] = symbols[id - 1230usize]
            n = 1usize
        }
        if n > 0usize {
            s.scroll = 0usize
            live_send(a, s, one[0usize..n])
            if id == 1205usize { live_say_above(a, s) }
            ret true
        }
        ret false
    }
    if s.screen == TERMINAL_SCREEN && s.live && id == 1205usize {
        if s.phase == PHASE_PASSWORD {
            if s.want_master {
                // (C155) The prompt is the vault's master password; the host never sees it. The key of the slot
                // the host is set to comes out of the vault and signs the login.
                var i = 0usize
                s.master_len = s.pw_len
                while i < s.pw_len {
                    s.master[i] = s.password[i]
                    i += 1usize
                }
                s.pw_len = 0usize
                let opened = unlock_vault(a, s)
                s.master_len = 0usize
                if opened != 0usize {
                    if opened == 1usize {
                        push_line(s, "Wrong master password. Try again.", 2usize)
                        say("ssh key wrong password\n")
                    } else {
                        live_end(s, "No vault on this device: make one in Secure")
                        say("ssh key no vault\n")
                    }
                    ret true
                }
                let (seed, have) = read_seed(a, s, s.hosts[s.current].key_slot)
                if !have {
                    live_end(s, join(a, "There is no key in slot ", number(a, s.hosts[s.current].key_slot + 1usize), ""))
                    say("ssh key missing\n")
                    ret true
                }
                s.seed = seed
                s.have_seed = true
                say("ssh key from secure\n")
            }
            live_start(a, s)
            ret true
        }
        if s.phase == PHASE_HOST_KEY {
            if s.cmd_len == 3usize && s.cmd[0usize] == 121u8 && s.cmd[1usize] == 101u8 && s.cmd[2usize] == 115u8 {
                var i = 0usize
                let key = sshc.host_key(&s.session)
                while i < 32usize {
                    s.known_keys[s.current * 32usize + i] = key[i]
                    i += 1usize
                }
                s.known[s.current] = true
                save_known(s)
                sshc.trust(&s.session)
                s.phase = PHASE_RUNNING
                s.cmd_len = 0usize
                if !live_flush(s) { live_end(s, "Network error") }
                // Authentication and the shell come next.
                var rounds = 0usize
                while rounds < 40usize && !s.announced && s.phase == PHASE_RUNNING {
                    live_poll(a, s, 1usize)
                    rounds += 1usize
                }
            } else {
                sshc.close(&s.session)
                let flushed = live_flush(s)
                live_end(s, "Host key not trusted")
            }
            ret true
        }
        ret true
    }
    if id >= 1000usize && id < 1026usize {
        if s.screen == TERMINAL_SCREEN && s.ctrl {
            // The demo shell: Ctrl-C abandons the line, Ctrl-L clears the screen.
            s.ctrl = false
            if id == 1002usize {
                push_line(s, join(a, prompt_text(a, s), text_of(a, s.cmd[0usize..], s.cmd_len), "^C"), 1usize)
                s.cmd_len = 0usize
            }
            if id == 1011usize { s.line_total = 0usize }
            ret true
        }
        type_byte(s, u8(97usize + id - 1000usize))
        ret true
    }
    if s.screen == TERMINAL_SCREEN && id >= 1230usize && id <= 1234usize {
        let symbols = "|_:;\\"
        type_byte(s, symbols[id - 1230usize])
        ret true
    }
    if id >= 1100usize && id < 1110usize {
        type_byte(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
        ret true
    }
    if id == 1200usize {
        type_byte(s, 32u8)
        ret true
    }
    if id == 1201usize {
        backspace(s)
        ret true
    }
    if id == 1202usize {
        type_byte(s, 46u8)
        ret true
    }
    if id == 1203usize {
        type_byte(s, 45u8)
        ret true
    }
    if id == 1204usize {
        type_byte(s, 47u8)
        ret true
    }
    if id == 1205usize {
        if s.screen == TERMINAL_SCREEN {
            run_command(a, s)
        } else if s.focus < 2usize {
            s.focus += 1usize
        }
        ret true
    }
    if s.screen == TERMINAL_SCREEN {
        if id == 1211usize {
            type_byte(s, 126u8)
            ret true
        }
        if id == 1212usize {
            if s.history_at < s.history_total {
                recall(s, s.history_at)
                s.history_at += 1usize
            }
            ret true
        }
        if id == 1213usize {
            if s.history_at > 1usize {
                s.history_at -= 1usize
                recall(s, s.history_at - 1usize)
            } else {
                s.history_at = 0usize
                s.cmd_len = 0usize
            }
            ret true
        }
        if id == 1214usize {
            push_line(s, join(a, prompt_text(a, s), text_of(a, s.cmd[0usize..], s.cmd_len), "^C"), 1usize)
            s.cmd_len = 0usize
            ret true
        }
        if id == 1215usize {
            s.line_total = 0usize
            ret true
        }
        ret false
    }
    // The form.
    if id >= 1500usize && id < 1503usize {
        s.focus = id - 1500usize
        ret true
    }
    if id == 1320usize {
        s.draft.port = 22usize
        ret true
    }
    if id == 1321usize {
        s.draft.port = 2222usize
        ret true
    }
    if id == 1330usize {
        s.draft.key_auth = false
        ret true
    }
    if id == 1331usize {
        if s.draft.key_auth { s.draft.key_slot = (s.draft.key_slot + 1usize) % MAX_KEYS }
        s.draft.key_auth = true
        ret true
    }
    if id == 1300usize {
        if save_draft(s) { s.screen = HOSTS_SCREEN }
        ret true
    }
    if id == 1303usize {
        if save_draft(s) {
            var index = s.editing
            if index == NONE {
                index = 0usize
                while index < MAX_HOSTS && !(s.hosts[index].used && s.hosts[index].alias_len == s.draft.alias_len && s.hosts[index].addr_len == s.draft.addr_len) { index += 1usize }
            }
            if index < MAX_HOSTS { connect(a, s, index, false) } else { s.screen = HOSTS_SCREEN }
        }
        ret true
    }
    if id == 1301usize {
        if s.editing != NONE {
            s.hosts[s.editing].used = false
            if s.known[s.editing] {
                s.known[s.editing] = false
                save_known(s)
            }
            save_hosts(s)
        }
        s.screen = HOSTS_SCREEN
        say("ssh deleted\n")
        ret true
    }
    if id == 1302usize {
        s.screen = HOSTS_SCREEN
        ret true
    }
    ret false
}

// The terminal line above the cursor, for the test boot's log: what a command just printed.
fn live_say_above(a: *mem.Arena, s: *State) {
    if s.tm.cy == 0usize { ret }
    var line: [64]u8 = zero
    var n = 0usize
    var x = 0usize
    while x < s.tm.cols && n < 63usize {
        let c = term.cell(&s.tm, x, s.tm.cy - 1usize)
        var ch = 63u8
        if c.ch >= 32u32 && c.ch < 127u32 { ch = u8(c.ch) }
        line[n] = ch
        n += 1usize
        x += 1usize
    }
    while n > 0usize && line[n - 1usize] == 32u8 { n -= 1usize }
    say("ssh live above ")
    say_text(text_of(a, line[0usize..], n))
    say("\n")
}

fn hit_at(s: *State, x: f32, y: f32) -> usize {
    var i = s.hit_total
    while i > 0usize {
        i -= 1usize
        let h = s.hits[i]
        if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h { ret h.id }
    }
    ret NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    // (C120) A live session's buffers (the SSH session's 160 KB, the terminal's screens and 200 lines of history)
    // are taken before the app's per-frame arena mark, so a frame does not take them back.
    let (persist, persist_error) = mem.alloc[u8](a, 524288usize)
    if persist_error != ok {
        say("ssh no memory\n")
        ret ok
    }
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "ssh")
    if kit_error != ok {
        say("ssh open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("ssh fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.live_arena = mem.arena_from(persist)
    s.editing = NONE
    let h1 = add_host(&s, make_host("web-01", "10.0.1.21", "deploy", 22usize, true, true))
    let h2 = add_host(&s, make_host("db-primary", "10.0.2.5", "postgres", 22usize, true, false))
    let h3 = add_host(&s, make_host("lab-pi", "192.168.1.40", "pi", 22usize, false, true))
    let h4 = add_host(&s, make_host("build-runner", "ci.example.com", "runner", 2222usize, true, false))
    let h5 = add_host(&s, make_host("backup-nas", "nas.local", "admin", 22usize, false, false))
    // (C120) The test boot's own SSH server, at the host the guest's DNS answers for neper.test.
    let h6 = add_host(&s, make_host("neper-test", "neper.test", "neper", 8022usize, false, false))
    // (C155) With a disk the hosts saved before replace the sample ones, and the keys trusted come back with them.
    if load_hosts(&s) { say("ssh hosts loaded\n") }
    if load_known(&s) { say("ssh known hosts loaded\n") }
    if !show(a, &kit, &s) {
        say("ssh present failed\n")
        ret ok
    }
    say("ssh shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // A live shell's output arrives when the host sends it.
            if s.live && s.phase == PHASE_RUNNING && s.screen == TERMINAL_SCREEN {
                live_poll(a, &s, 2usize)
                if s.sftp_mode && s.screen == SFTP_SCREEN && !s.sftp_started { sftp_enter(a, &s) }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            say("ssh home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(a, &s, id) {
                if s.sftp_mode && s.screen == SFTP_SCREEN && !s.sftp_started && s.live { sftp_enter(a, &s) }
                if !show(a, &kit, &s) {
                    say("ssh present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
