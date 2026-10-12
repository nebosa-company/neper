// Secure (D2235): the app behind the Secure icon, one vault for passwords and one-time codes (C116) --
// a lock screen (the master password typed on the on-screen keyboard), the logins (site, user name, a
// password that stays hidden until you reveal it, how strong it is, copy, delete, and Generate for a new
// one), and the codes: real time-based one-time passwords (RFC 6238, HMAC-SHA-1 over the clock, six
// digits) with the seconds left in each 30-second window, so the code matches the one an authenticator app
// shows for the same secret. Dark ground, cream cards and amber, like the other apps (appkit.e, taps from
// the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: the vault is SAMPLE data in this process and is NOT encrypted or stored: the master password
// is the sample "neper" (the hint is on the lock screen), the logins are made up, the passwords are
// plain bytes in memory, and a copy only says it copied (there is no clipboard). The TOTP maths is real
// (it is checked against the RFC 6238 vector at start); the encrypted store under a key from the master
// password (PBKDF2 or Argon2 and an AEAD from e.crypto), the clipboard, autofill and biometric unlock are
// queued as C116's remainder.
use e.mem
use e.os
use e.time
use e.crypto.mac as mac
use e.crypto.otp as otp
use e.crypto.hash as hash
use e.barcode
use httpc
use vault
use vaultfs
use sysettings
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui

const NONE: usize = 99usize
const MAX_LOGINS: usize = 10usize
const MAX_CODES: usize = 6usize
const LOCK_SCREEN: usize = 0usize
const LIST_SCREEN: usize = 1usize
const DETAIL_SCREEN: usize = 2usize
const ADD_SCREEN: usize = 3usize
const SEARCH_SCREEN: usize = 4usize
const CODE_SCREEN: usize = 5usize
const QR_SCREEN: usize = 6usize
// (C170) The vault locks itself after this many seconds without a tap.
const AUTO_LOCK_SECONDS: usize = 60usize
// Where the vault lives: nowhere (the sample vault, nothing saved), a vault still to be created, or one on disk.
const STORAGE_NONE: usize = 0usize
const STORAGE_NEW: usize = 1usize
const STORAGE_DISK: usize = 2usize
// The PBKDF2 rounds a new vault stores: low enough that the key comes in a few seconds on the emulated core the
// tests run on, far below what a real phone should use; a vault keeps its own count, so raising this only
// affects the vaults created afterwards.
const ITERATIONS: u32 = 20000u32
const JOB_NONE: usize = 0usize
const JOB_CREATE: usize = 1usize
const JOB_UNLOCK: usize = 2usize

type Login = struct { site: [20]u8, site_len: usize, user: [24]u8, user_len: usize, pass: [24]u8, pass_len: usize, used: bool }

// `algo` 0 SHA-1, 1 SHA-256, 2 SHA-512; `digits` and `period` 0 mean the defaults, 6 and 30 (C140).
type Code = struct { issuer: [16]u8, issuer_len: usize, account: [24]u8, account_len: usize, secret: [32]u8, secret_len: usize, used: bool, algo: usize, digits: usize, period: usize, hotp: bool, counter: usize }

type State = struct {
    logins: [10]Login,
    codes: [6]Code,
    screen: usize,
    tab: usize,
    open: usize,
    reveal: bool,
    master: ui.Field,
    wrong: bool,
    // The add form: three fields, which, and the field in focus.
    add_kind: usize,
    f0: ui.Field,
    f1: ui.Field,
    f2: ui.Field,
    focus: usize,
    seed: usize,
    now: usize,
    hits: ui.Hits,
    storage: usize,
    key: [32]u8,
    keyed: bool,
    // Creating a vault: the password is asked twice; `stage` 1 is the second time and `first` holds the first.
    stage: usize,
    first: ui.Field,
    search: ui.Field,
    job: usize,
    // The entry the add form is editing, or NONE for a new one.
    edit: usize,
    message: [48]u8,
    message_len: usize,
    // (C170) The wall-clock second of the last tap (auto-lock), the generator's length (0 means 16) and whether it
    // may use symbols, and the result line of the last breach check or export.
    last_active: usize,
    gen_len: usize,
    gen_symbols: bool,
    note: [48]u8,
    note_len: usize,
}

// ----------------------------------------------------------------------------------------------
// One-time passwords.

// The value of a base32 letter (A-Z, 2-7), or 99.
fn b32(c: u8) -> usize {
    if c >= 65u8 && c <= 90u8 { ret usize(c) - 65usize }
    if c >= 97u8 && c <= 122u8 { ret usize(c) - 97usize }
    if c >= 50u8 && c <= 55u8 { ret usize(c) - 50usize + 26usize }
    ret 99usize
}

// The bytes of a base32 secret into `out`; how many.
fn decode_secret(text_in: str, out: []u8) -> usize {
    var bits = 0usize
    var have = 0usize
    var n = 0usize
    var i = 0usize
    while i < text_in.len {
        let v = b32(text_in[i])
        if v != 99usize {
            bits = (bits << 5usize) | v
            have += 5usize
            if have >= 8usize {
                have -= 8usize
                if n < out.len {
                    out[n] = u8((bits >> have) & 255usize)
                    n += 1usize
                }
                bits = bits & ((1usize << have) - 1usize)
            }
        }
        i += 1usize
    }
    ret n
}

// The one-time password of `secret` (base32) at `unix_seconds`, `digits` long: RFC 4226 over the 30-second
// counter of RFC 6238.
fn totp(secret: str, unix_seconds: usize, digits: usize) -> usize {
    var key: [40]u8 = zero
    let n = decode_secret(secret, key[0usize..40usize])
    let counter = unix_seconds / 30usize
    var message: [8]u8 = zero
    var i = 0usize
    while i < 8usize {
        message[7usize - i] = u8((counter >> (i * 8usize)) & 255usize)
        i += 1usize
    }
    let h = mac.legacy_hmac_sha1(key[0usize..n], message[0usize..8usize])
    let o = usize(h[19usize] & 15u8)
    let binary = ((usize(h[o] & 127u8)) << 24usize) | (usize(h[o + 1usize]) << 16usize) | (usize(h[o + 2usize]) << 8usize) | usize(h[o + 3usize])
    var modulus = 1usize
    var d = 0usize
    while d < digits {
        modulus = modulus * 10usize
        d += 1usize
    }
    ret binary % modulus
}

fn entry_period(s: *State, i: usize) -> usize {
    if s.codes[i].period == 0usize { ret 30usize }
    ret s.codes[i].period
}

fn entry_digits(s: *State, i: usize) -> usize {
    if s.codes[i].digits == 0usize { ret 6usize }
    ret s.codes[i].digits
}

// The code of entry `i` now: its algorithm, digit count and period (otp.totp); 0 when the secret is not base32.
fn entry_code(a: *mem.Arena, s: *State, i: usize) -> usize {
    var key: [40]u8 = zero
    let n = decode_secret(secret_of(a, s, i), key[0usize..40usize])
    if n == 0usize { ret 0usize }
    var algorithm = otp.Algorithm.Sha1
    if s.codes[i].algo == 1usize { algorithm = .Sha256 }
    if s.codes[i].algo == 2usize { algorithm = .Sha512 }
    if s.codes[i].hotp {
        // A counter-based code (RFC 4226): the next button moves the counter, the code is the one at the counter.
        let (counted, counted_error) = otp.hotp(algorithm, key[0usize..n], u64(s.codes[i].counter), u32(entry_digits(s, i)))
        if counted_error != ok { ret 0usize }
        ret usize(counted)
    }
    let (value, value_error) = otp.totp(algorithm, key[0usize..n], u64(s.now), 0u64, u32(entry_period(s, i)), u32(entry_digits(s, i)))
    if value_error != ok { ret 0usize }
    ret usize(value)
}

// A code as plain digits, zero-padded: "123456", "12345678" (what a paste needs).
fn code_digits(a: *mem.Arena, code: usize, digits: usize) -> str {
    let (out, out_error) = mem.alloc[u8](a, 12usize)
    if out_error != ok { ret "" }
    var rest = code
    var i = digits
    while i > 0usize {
        i -= 1usize
        out[i] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    ret out[0usize..digits]
}

// A code with its digits zero-padded and a space in the middle: "123 456", "1234 5678".
fn code_text_n(a: *mem.Arena, code: usize, digits: usize) -> str {
    let (out, out_error) = mem.alloc[u8](a, 12usize)
    if out_error != ok { ret "" }
    let half = (digits + 1usize) / 2usize
    var rest = code
    var i = digits
    while i > 0usize {
        i -= 1usize
        var at = i
        if i >= half { at = i + 1usize }
        out[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    out[half] = 32u8
    ret out[0usize..digits + 1usize]
}

// Read the first otpauth URI of /otpauth.txt and add it as a code: the index, or NONE.
// The `line`-th line (from 0) of /otpauth.txt as an entry: its index, or NONE when there is no such line or it is not
// an otpauth URI.
fn import_uri(a: *mem.Arena, s: *State, line: usize) -> usize {
    var buf: [640]u8 = zero
    let (n, found) = vaultfs.read("/otpauth.txt", mem.address_of(&buf[0usize]), 640usize)
    if !found || n == 0usize { ret NONE }
    var start = 0usize
    var skipped = 0usize
    while skipped < line && start < n {
        while start < n && buf[start] != 10u8 { start += 1usize }
        start += 1usize
        skipped += 1usize
    }
    while start < n && (buf[start] == 10u8 || buf[start] == 13u8) { start += 1usize }
    if start >= n { ret NONE }
    var end = start
    while end < n && buf[end] != 10u8 && buf[end] != 13u8 { end += 1usize }
    let (p, parse_error) = otp.parse_uri(ui.text_of(a, buf[start..], end - start))
    if parse_error != ok { ret NONE }
    // The label is "Issuer:account" or "account", percent-encoded; the issuer parameter wins.
    var label: [64]u8 = zero
    let (label_len, label_error) = otp.percent_decode(p.label, label[0usize..64usize])
    if label_error != ok { ret NONE }
    var colon = label_len
    var k = 0usize
    while k < label_len {
        if label[k] == 58u8 && colon == label_len { colon = k }
        k += 1usize
    }
    var account = ui.text_of(a, label[0usize..], label_len)
    var issuer = ""
    if colon < label_len {
        issuer = ui.text_of(a, label[0usize..], colon)
        account = ui.text_of(a, label[colon + 1usize..], label_len - colon - 1usize)
    }
    if p.issuer.len > 0usize {
        var issuer_bytes: [32]u8 = zero
        let (issuer_len, issuer_error) = otp.percent_decode(p.issuer, issuer_bytes[0usize..32usize])
        if issuer_error == ok { issuer = ui.text_of(a, issuer_bytes[0usize..], issuer_len) }
    }
    let index = add_code(s, issuer, account, p.secret)
    if index == NONE { ret NONE }
    if p.algorithm == .Sha256 { s.codes[index].algo = 1usize }
    if p.algorithm == .Sha512 { s.codes[index].algo = 2usize }
    s.codes[index].digits = usize(p.digits)
    s.codes[index].period = usize(p.period)
    if !p.totp {
        s.codes[index].hotp = true
        s.codes[index].counter = usize(p.counter)
    }
    ret index
}

fn code_text(a: *mem.Arena, code: usize) -> str {
    ret ui.join(a, ui.join(a, ui.two(a, code / 10000usize), ui.number(a, (code / 1000usize) % 10usize), ""), " ", ui.join(a, ui.number(a, (code / 100usize) % 10usize), ui.number(a, (code / 10usize) % 10usize), ui.number(a, code % 10usize)))
}

// ----------------------------------------------------------------------------------------------
// The vault.

fn add_login(s: *State, site: str, user: str, pass: str) -> usize {
    var i = 0usize
    while i < MAX_LOGINS {
        if !s.logins[i].used {
            var l: Login = zero
            var k = 0usize
            while k < site.len && k < 20usize {
                l.site[k] = site[k]
                k += 1usize
            }
            l.site_len = k
            k = 0usize
            while k < user.len && k < 24usize {
                l.user[k] = user[k]
                k += 1usize
            }
            l.user_len = k
            k = 0usize
            while k < pass.len && k < 24usize {
                l.pass[k] = pass[k]
                k += 1usize
            }
            l.pass_len = k
            l.used = true
            s.logins[i] = l
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn add_code(s: *State, issuer: str, account: str, secret: str) -> usize {
    var i = 0usize
    while i < MAX_CODES {
        if !s.codes[i].used {
            var c: Code = zero
            var k = 0usize
            while k < issuer.len && k < 16usize {
                c.issuer[k] = issuer[k]
                k += 1usize
            }
            c.issuer_len = k
            k = 0usize
            while k < account.len && k < 24usize {
                c.account[k] = account[k]
                k += 1usize
            }
            c.account_len = k
            k = 0usize
            while k < secret.len && k < 32usize {
                c.secret[k] = secret[k]
                k += 1usize
            }
            c.secret_len = k
            c.used = true
            s.codes[i] = c
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn site_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.logins[i].site[0usize..], s.logins[i].site_len)
}

fn user_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.logins[i].user[0usize..], s.logins[i].user_len)
}

fn pass_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.logins[i].pass[0usize..], s.logins[i].pass_len)
}

fn issuer_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.codes[i].issuer[0usize..], s.codes[i].issuer_len)
}

fn account_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.codes[i].account[0usize..], s.codes[i].account_len)
}

fn secret_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.codes[i].secret[0usize..], s.codes[i].secret_len)
}

// How strong a password is: 0 weak .. 3 strong, by length and kinds of characters.
fn strength(pass: str) -> usize {
    var lower = false
    var upper = false
    var digit = false
    var other = false
    var i = 0usize
    while i < pass.len {
        let c = pass[i]
        if c >= 97u8 && c <= 122u8 { lower = true } else if c >= 65u8 && c <= 90u8 { upper = true } else if c >= 48u8 && c <= 57u8 { digit = true } else { other = true }
        i += 1usize
    }
    var kinds = 0usize
    if lower { kinds += 1usize }
    if upper { kinds += 1usize }
    if digit { kinds += 1usize }
    if other { kinds += 1usize }
    if pass.len < 8usize { ret 0usize }
    if pass.len >= 14usize && kinds >= 3usize { ret 3usize }
    if pass.len >= 10usize && kinds >= 2usize { ret 2usize }
    ret 1usize
}

fn generator_length(s: *State) -> usize {
    if s.gen_len == 0usize { ret 16usize }
    ret s.gen_len
}

// (C170) A new password of the chosen length (12, 16 or 24) from the letters and digits that cannot be mistaken for
// each other, plus symbols when asked. The bytes come from the random server, taken only when they fall below the
// largest multiple of the alphabet's size (no modulo bias); a machine without the server falls back on a small LCG.
fn generate(a: *mem.Arena, s: *State) -> str {
    var alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    if s.gen_symbols { alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_!@#$%&*?" }
    let length = generator_length(s)
    let (buffer, buffer_error) = mem.alloc[u8](a, 24usize)
    if buffer_error != ok { ret "" }
    var random: [64]u8 = zero
    let drawn = vaultfs.random(mem.address_of(&random[0usize]), 8usize)
    let limit = (256usize / alphabet.len) * alphabet.len
    var i = 0usize
    var at = 0usize
    while i < length {
        var picked = false
        while drawn && !picked && at < 64usize {
            let v = usize(random[at])
            at += 1usize
            if v < limit {
                buffer[i] = alphabet[v % alphabet.len]
                picked = true
            }
        }
        if !picked {
            s.seed = (s.seed * 1103515245usize + 12345usize) & 2147483647usize
            buffer[i] = alphabet[(s.seed >> 8usize) % alphabet.len]
        }
        i += 1usize
    }
    ret buffer[0usize..length]
}

// ----------------------------------------------------------------------------------------------
// The vault on disk (D2252): /vmeta holds the salt, the iteration count and a sealed phrase; each login
// is a record /v/l0 .. /v/l9 and each code /v/c0 .. /v/c5, sealed under the key the master password makes.

fn say_message(s: *State, line: str) {
    var n = 0usize
    while n < line.len && n < 48usize {
        s.message[n] = line[n]
        n += 1usize
    }
    s.message_len = n
}

// A length byte and the bytes, at `at`; the new offset.
fn put_field(out: []u8, at: usize, bytes: []const u8, len: usize) -> usize {
    out[at] = u8(len)
    var i = 0usize
    while i < len {
        out[at + 1usize + i] = bytes[i]
        i += 1usize
    }
    ret at + 1usize + len
}

fn pack_login(s: *State, i: usize, out: []u8) -> usize {
    out[0] = 1u8
    var n = put_field(out, 1usize, s.logins[i].site[0usize..], s.logins[i].site_len)
    n = put_field(out, n, s.logins[i].user[0usize..], s.logins[i].user_len)
    ret put_field(out, n, s.logins[i].pass[0usize..], s.logins[i].pass_len)
}

fn pack_code(s: *State, i: usize, out: []u8) -> usize {
    out[0] = 2u8
    var n = put_field(out, 1usize, s.codes[i].issuer[0usize..], s.codes[i].issuer_len)
    n = put_field(out, n, s.codes[i].account[0usize..], s.codes[i].account_len)
    n = put_field(out, n, s.codes[i].secret[0usize..], s.codes[i].secret_len)
    // Then algorithm, digits and period, one byte each (records written before had none).
    out[n] = u8(s.codes[i].algo)
    out[n + 1usize] = u8(s.codes[i].digits)
    out[n + 2usize] = u8(s.codes[i].period)
    // Then whether it counts (HOTP) and its counter, four bytes little end.
    var kind = 0u8
    if s.codes[i].hotp { kind = 1u8 }
    out[n + 3usize] = kind
    var b = 0usize
    while b < 4usize {
        out[n + 4usize + b] = u8((s.codes[i].counter >> (8usize * b)) & 255usize)
        b += 1usize
    }
    ret n + 8usize
}

// The field at `at` into `dst` (at most `cap` bytes): the offset after it (0 when malformed) and its length.
fn take_field(plain: []const u8, at: usize, dst: []u8, cap: usize) -> (usize, usize) {
    if at >= plain.len { ret (0usize, 0usize) }
    let len = usize(plain[at])
    if len > cap || at + 1usize + len > plain.len { ret (0usize, 0usize) }
    var i = 0usize
    while i < len {
        dst[i] = plain[at + 1usize + i]
        i += 1usize
    }
    ret (at + 1usize + len, len)
}

fn unpack_login(s: *State, i: usize, plain: []const u8) -> bool {
    if plain.len < 4usize || plain[0] != 1u8 { ret false }
    var l: Login = zero
    let (a1, n1) = take_field(plain, 1usize, l.site[0usize..], 20usize)
    if a1 == 0usize { ret false }
    let (a2, n2) = take_field(plain, a1, l.user[0usize..], 24usize)
    if a2 == 0usize { ret false }
    let (a3, n3) = take_field(plain, a2, l.pass[0usize..], 24usize)
    if a3 == 0usize { ret false }
    l.site_len = n1
    l.user_len = n2
    l.pass_len = n3
    l.used = true
    s.logins[i] = l
    ret true
}

fn unpack_code(s: *State, i: usize, plain: []const u8) -> bool {
    if plain.len < 4usize || plain[0] != 2u8 { ret false }
    var c: Code = zero
    let (a1, n1) = take_field(plain, 1usize, c.issuer[0usize..], 16usize)
    if a1 == 0usize { ret false }
    let (a2, n2) = take_field(plain, a1, c.account[0usize..], 24usize)
    if a2 == 0usize { ret false }
    let (a3, n3) = take_field(plain, a2, c.secret[0usize..], 32usize)
    if a3 == 0usize { ret false }
    c.issuer_len = n1
    c.account_len = n2
    c.secret_len = n3
    if plain.len >= a3 + 3usize {
        c.algo = usize(plain[a3])
        c.digits = usize(plain[a3 + 1usize])
        c.period = usize(plain[a3 + 2usize])
    }
    if plain.len >= a3 + 8usize {
        c.hotp = plain[a3 + 3usize] == 1u8
        var counter = 0usize
        var b = 0usize
        while b < 4usize {
            counter = counter | (usize(plain[a3 + 4usize + b]) << (8usize * b))
            b += 1usize
        }
        c.counter = counter
    }
    c.used = true
    s.codes[i] = c
    ret true
}

// "l3" or "c1": a record's name, which is also its additional data.
fn entry_name(a: *mem.Arena, code: bool, i: usize) -> str {
    var kind = "l"
    if code { kind = "c" }
    ret ui.join(a, kind, ui.number(a, i), "")
}

// Seal entry `i` under the vault key and write it; a no-op unless the vault is on disk and unlocked.
fn save_record(a: *mem.Arena, s: *State, code: bool, i: usize) {
    if s.storage != STORAGE_DISK || !s.keyed { ret }
    var plain: [96]u8 = zero
    var n = 0usize
    if code { n = pack_code(s, i, plain[0usize..]) } else { n = pack_login(s, i, plain[0usize..]) }
    var nonce: [16]u8 = zero
    if !vaultfs.random(mem.address_of(&nonce[0usize]), 2usize) {
        ui.say("secure save failed: no random source\n")
        ret
    }
    var record: [128]u8 = zero
    let name = entry_name(a, code, i)
    let (length, seal_error) = vault.seal(s.key, nonce[0usize..], name, plain[0usize..n], record[0usize..])
    if seal_error != ok {
        ui.say("secure save failed\n")
        ret
    }
    if vaultfs.write(ui.join(a, "/v/", name, ""), mem.address_of(&record[0usize]), length) {
        ui.say("secure saved ")
        ui.say_text(name)
        ui.say("\n")
    } else {
        ui.say("secure save failed\n")
    }
}

fn forget_record(a: *mem.Arena, s: *State, code: bool, i: usize) {
    if s.storage != STORAGE_DISK { ret }
    if vaultfs.remove(ui.join(a, "/v/", entry_name(a, code, i), "")) { ui.say("secure removed record\n") }
}

// Read and open every record; how many entries came back.
fn load_records(a: *mem.Arena, s: *State) -> usize {
    var loaded = 0usize
    var record: [128]u8 = zero
    var plain: [96]u8 = zero
    var pass = 0usize
    while pass < 2usize {
        let code = pass == 1usize
        var limit = MAX_LOGINS
        if code { limit = MAX_CODES }
        var i = 0usize
        while i < limit {
            let name = entry_name(a, code, i)
            let (count, found) = vaultfs.read(ui.join(a, "/v/", name, ""), mem.address_of(&record[0usize]), 128usize)
            if found {
                let (n, open_error) = vault.open(s.key, name, record[0usize..count], plain[0usize..])
                if open_error == ok {
                    var good = false
                    if code { good = unpack_code(s, i, plain[0usize..n]) } else { good = unpack_login(s, i, plain[0usize..n]) }
                    if good { loaded += 1usize }
                }
            }
            i += 1usize
        }
        pass += 1usize
    }
    ret loaded
}

// A new vault: salt and nonce from the random server, the key from the password typed twice, the meta file
// written; false (with a message) when something is missing.
fn create_vault(a: *mem.Arena, s: *State) -> bool {
    var random: [32]u8 = zero
    if !vaultfs.random(mem.address_of(&random[0usize]), 4usize) {
        say_message(s, "No random source on this machine")
        ret false
    }
    let (key, derive_error) = vault.derive(ui.field_text(a, &s.master), random[0usize..16usize], ITERATIONS)
    if derive_error != ok {
        say_message(s, "Could not make the key")
        ret false
    }
    var meta: [80]u8 = zero
    let (length, meta_error) = vault.meta_make(key, random[0usize..16usize], ITERATIONS, random[16usize..28usize], meta[0usize..])
    if meta_error != ok {
        say_message(s, "Could not seal the vault")
        ret false
    }
    let made = vaultfs.mkdir("/v")
    if !vaultfs.write("/vmeta", mem.address_of(&meta[0usize]), length) {
        say_message(s, "The disk would not take the vault")
        ret false
    }
    s.key = key
    s.keyed = true
    ret true
}

// Open the vault with the typed password: 0 opened, 1 wrong password, 2 unreadable.
fn unlock_vault(a: *mem.Arena, s: *State) -> usize {
    var meta: [80]u8 = zero
    let (count, found) = vaultfs.read("/vmeta", mem.address_of(&meta[0usize]), 80usize)
    if !found { ret 2usize }
    let (key, unlock_error) = vault.meta_unlock(meta[0usize..count], ui.field_text(a, &s.master))
    if unlock_error == vault.WrongPassword { ret 1usize }
    if unlock_error != ok { ret 2usize }
    s.key = key
    s.keyed = true
    ret 0usize
}

// ----------------------------------------------------------------------------------------------
// (C170) Export, the QR symbol of an entry, the breach check and locking.

fn set_note(s: *State, line: str) {
    var n = 0usize
    while n < line.len && n < 48usize {
        s.note[n] = line[n]
        n += 1usize
    }
    s.note_len = n
}

fn hex_upper(v: usize) -> u8 {
    if v < 10usize { ret u8(48usize + v) }
    ret u8(55usize + v)
}

// `piece` as a part of an otpauth label or parameter: letters, digits and - _ . ~ stay, every other byte is %XX.
fn put_encoded(out: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n + 3usize <= out.len {
        let c = piece[i]
        let plain = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 95u8 || c == 46u8 || c == 126u8
        if plain {
            out[n] = c
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = hex_upper(usize(c) >> 4usize)
            out[n + 2usize] = hex_upper(usize(c) & 15usize)
            n += 3usize
        }
        i += 1usize
    }
    ret n
}

// The Key URI Format of the entry `i`: otpauth://totp/Issuer:account?secret=...&issuer=...&algorithm=...&digits=...
// &period=... (a counter-based one is hotp with &counter=...), what an authenticator reads from a QR symbol.
fn uri_of(a: *mem.Arena, s: *State, i: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 360usize)
    if buffer_error != ok { ret "" }
    let issuer = issuer_of(a, s, i)
    var n = 0usize
    if s.codes[i].hotp { n = httpc.put(buffer, n, "otpauth://hotp/") } else { n = httpc.put(buffer, n, "otpauth://totp/") }
    if issuer.len > 0usize {
        n = put_encoded(buffer, n, issuer)
        n = httpc.put(buffer, n, ":")
    }
    n = put_encoded(buffer, n, account_of(a, s, i))
    n = httpc.put(buffer, n, "?secret=")
    n = httpc.put(buffer, n, secret_of(a, s, i))
    if issuer.len > 0usize {
        n = httpc.put(buffer, n, "&issuer=")
        n = put_encoded(buffer, n, issuer)
    }
    var algorithm = "SHA1"
    if s.codes[i].algo == 1usize { algorithm = "SHA256" }
    if s.codes[i].algo == 2usize { algorithm = "SHA512" }
    n = httpc.put(buffer, n, "&algorithm=")
    n = httpc.put(buffer, n, algorithm)
    n = httpc.put(buffer, n, "&digits=")
    n = httpc.put_number(buffer, n, entry_digits(s, i))
    if s.codes[i].hotp {
        n = httpc.put(buffer, n, "&counter=")
        n = httpc.put_number(buffer, n, s.codes[i].counter)
    } else {
        n = httpc.put(buffer, n, "&period=")
        n = httpc.put_number(buffer, n, entry_period(s, i))
    }
    ret buffer[0usize..n]
}

// Every code as one otpauth URI per line (what Aegis, 2FAS and Google Authenticator's transfer read): the text, in
// the arena. Empty when there is nothing to export.
fn export_text(a: *mem.Arena, s: *State) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 2048usize)
    if buffer_error != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < MAX_CODES {
        if s.codes[i].used {
            n = httpc.put(buffer, n, uri_of(a, s, i))
            n = httpc.put(buffer, n, "\n")
        }
        i += 1usize
    }
    ret buffer[0usize..n]
}

// (C170) Export the codes. The file /export.sealed is the list sealed under the vault key (the way each record is,
// named "export"); with `plain` the list is also written as /otpauth-export.txt, readable by any authenticator and
// by anyone who finds the disk, so it is asked for on its own. Each URI is parsed back and its secret compared
// before anything is said to have worked.
fn export_codes(a: *mem.Arena, s: *State, plain: bool) -> bool {
    let body = export_text(a, s)
    if body.len == 0usize {
        set_note(s, "No codes to export")
        ret false
    }
    var lines = 0usize
    var start = 0usize
    var checked = 0usize
    while start < body.len {
        var end = start
        while end < body.len && body[end] != 10u8 { end += 1usize }
        let (p, parse_error) = otp.parse_uri(ui.text_of(a, body[start..], end - start))
        if parse_error == ok {
            var found = false
            var k = 0usize
            while k < MAX_CODES {
                if s.codes[k].used && ui.same(p.secret, secret_of(a, s, k)) { found = true }
                k += 1usize
            }
            if found { checked += 1usize }
        }
        lines += 1usize
        start = end + 1usize
    }
    if checked != lines {
        set_note(s, "Export check failed")
        ui.say("secure export check failed\n")
        ret false
    }
    if plain {
        if !vaultfs.write_big("/otpauth-export.txt", mem.address_of(&body[0usize]), body.len) {
            set_note(s, "The disk would not take the file")
            ret false
        }
        ui.say("secure exported plain ")
        ui.say_num(lines)
        ui.say(" ")
        ui.say_num(body.len)
        ui.say("\n")
        set_note(s, ui.join(a, ui.join(a, "Wrote ", ui.number(a, lines), " codes, readable by anyone"), "", ""))
        ret true
    }
    if s.storage != STORAGE_DISK || !s.keyed {
        set_note(s, "Nothing is stored on this machine")
        ret false
    }
    var nonce: [16]u8 = zero
    if !vaultfs.random(mem.address_of(&nonce[0usize]), 2usize) {
        set_note(s, "No random source on this machine")
        ret false
    }
    let (sealed, sealed_error) = mem.alloc[u8](a, body.len + 64usize)
    if sealed_error != ok { ret false }
    let (length, seal_error) = vault.seal(s.key, nonce[0usize..], "export", body, sealed)
    if seal_error != ok {
        set_note(s, "Could not seal the export")
        ret false
    }
    if !vaultfs.write_big("/export.sealed", mem.address_of(&sealed[0usize]), length) {
        set_note(s, "The disk would not take the file")
        ret false
    }
    // Read it back and open it: the file is only a backup if it opens.
    let (back, back_error) = mem.alloc[u8](a, length + 16usize)
    if back_error != ok { ret false }
    let (got, found) = vaultfs.read_big("/export.sealed", mem.address_of(&back[0usize]), length + 16usize)
    let (opened, open_error) = mem.alloc[u8](a, body.len + 16usize)
    if open_error != ok { ret false }
    let (plain_len, unseal_error) = vault.open(s.key, "export", back[0usize..got], opened)
    if !found || unseal_error != ok || plain_len != body.len {
        set_note(s, "Export check failed")
        ui.say("secure export check failed\n")
        ret false
    }
    ui.say("secure exported sealed ")
    ui.say_num(lines)
    ui.say(" ")
    ui.say_num(length)
    ui.say("\n")
    var shown = 0usize
    start = 0usize
    while start < body.len && shown < 2usize {
        var end = start
        while end < body.len && body[end] != 10u8 { end += 1usize }
        // `say_text` writes at most 40 bytes (and copies them where the console can read them): the line goes out in
        // pieces of 32.
        ui.say("secure uri ")
        var piece_at = start
        while piece_at < end {
            var piece_end = piece_at + 32usize
            if piece_end > end { piece_end = end }
            ui.say_text(ui.text_of(a, body[piece_at..], piece_end - piece_at))
            piece_at = piece_end
        }
        ui.say("\n")
        shown += 1usize
        start = end + 1usize
    }
    set_note(s, ui.join(a, ui.join(a, "Sealed ", ui.number(a, lines), " codes in /export.sealed"), "", ""))
    ret true
}

// A QR symbol of `payload` (error correction M) as an svg, one square per dark module; empty when it does not fit.
// The symbol is decoded again and compared before it is returned, so what is drawn is what a scanner reads.
fn qr_svg(a: *mem.Arena, payload: str) -> str {
    let (symbol, symbol_error) = barcode.qr_encode(a, payload, 1usize)
    if symbol_error != ok { ret "" }
    let (back, back_error) = barcode.qr_decode(a, symbol)
    if back_error != ok || !ui.same(back, payload) { ret "" }
    ui.say("secure qr ok ")
    ui.say_num(symbol.size)
    ui.say("\n")
    let (buffer, buffer_error) = mem.alloc[u8](a, symbol.size * symbol.size * 16usize + 96usize)
    if buffer_error != ok { ret "" }
    var n = 0usize
    n = httpc.put(buffer, n, "<svg viewBox='0 0 ")
    n = httpc.put_number(buffer, n, symbol.size)
    n = httpc.put(buffer, n, " ")
    n = httpc.put_number(buffer, n, symbol.size)
    n = httpc.put(buffer, n, "'><path d='")
    var y = 0usize
    while y < symbol.size {
        var x = 0usize
        while x < symbol.size {
            if symbol.modules[y * symbol.size + x] == 1u8 {
                n = httpc.put(buffer, n, "M")
                n = httpc.put_number(buffer, n, x)
                n = httpc.put(buffer, n, " ")
                n = httpc.put_number(buffer, n, y)
                n = httpc.put(buffer, n, "h1v1h-1z")
            }
            x += 1usize
        }
        y += 1usize
    }
    n = httpc.put(buffer, n, "' fill='currentColor'/></svg>")
    ret buffer[0usize..n]
}

// The host of the breach service: /breachhost on the disk when there is one (a machine that runs its own mirror, or
// the test boot), else Have I Been Pwned's range API.
fn breach_host(a: *mem.Arena) -> str {
    var buf: [64]u8 = zero
    let (n, found) = vaultfs.read("/breachhost", mem.address_of(&buf[0usize]), 64usize)
    if !found || n == 0usize { ret "api.pwnedpasswords.com" }
    var end = n
    while end > 0usize && (buf[end - 1usize] == 10u8 || buf[end - 1usize] == 13u8 || buf[end - 1usize] == 32u8) { end -= 1usize }
    if end == 0usize { ret "api.pwnedpasswords.com" }
    ret ui.text_of(a, buf[0usize..], end)
}

// How many breaches `password` has been seen in, by hash prefix (k-anonymity): only the first five hex digits of its
// SHA-1 leave the device, the service answers every suffix under them with a count, and the match is made here.
// The outcome: 0 answered, 1 no network, 2 the service failed.
fn breach_check(a: *mem.Arena, password: str) -> (usize, usize) {
    let digest = hash.legacy_sha1(password)
    var hex: [40]u8 = zero
    var i = 0usize
    while i < 20usize {
        hex[i * 2usize] = hex_upper(usize(digest[i]) >> 4usize)
        hex[i * 2usize + 1usize] = hex_upper(usize(digest[i]) & 15usize)
        i += 1usize
    }
    let path = ui.join(a, "/range/", ui.text_of(a, hex[0usize..], 5usize), "")
    let (reply, request_error) = httpc.get(a, breach_host(a), path, "")
    if request_error == httpc.NoNetwork { ret (0usize, 1usize) }
    if request_error != ok || reply.status != 200usize { ret (0usize, 2usize) }
    var start = 0usize
    while start < reply.body.len {
        var end = start
        while end < reply.body.len && reply.body[end] != 10u8 { end += 1usize }
        // SUFFIX:COUNT, the suffix 35 hex digits.
        if end - start > 36usize && reply.body[start + 35usize] == 58u8 {
            var same = true
            var k = 0usize
            while k < 35usize {
                var c = reply.body[start + k]
                if c >= 97u8 && c <= 102u8 { c -= 32u8 }
                if c != hex[5usize + k] { same = false }
                k += 1usize
            }
            if same {
                var count = 0usize
                var d = start + 36usize
                while d < end && reply.body[d] >= 48u8 && reply.body[d] <= 57u8 {
                    count = count * 10usize + usize(reply.body[d] - 48u8)
                    d += 1usize
                }
                ret (count, 0usize)
            }
        }
        start = end + 1usize
    }
    ret (0usize, 0usize)
}

// Forget what is on the screen and in memory: with a vault on disk the entries and the key are wiped and come back
// only by unlocking (the records are read again); the sample vault only returns to its lock screen.
fn lock_now(s: *State) {
    if s.storage == STORAGE_DISK {
        var no_login: Login = zero
        var no_code: Code = zero
        var no_key: [32]u8 = zero
        var k = 0usize
        while k < MAX_LOGINS {
            s.logins[k] = no_login
            k += 1usize
        }
        k = 0usize
        while k < MAX_CODES {
            s.codes[k] = no_code
            k += 1usize
        }
        s.key = no_key
        s.keyed = false
    }
    s.screen = LOCK_SCREEN
    s.master.len = 0usize
    s.message_len = 0usize
    s.note_len = 0usize
    s.reveal = false
    s.open = NONE
    s.edit = NONE
    s.f0.len = 0usize
    s.f1.len = 0usize
    s.f2.len = 0usize
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn lock_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><rect x='5' y='11' width='14' height='10' rx='2' fill='currentColor'/><path d='M8 11V8a4 4 0 0 1 8 0v3' fill='none' stroke='currentColor' stroke-width='2'/></svg>"
}

fn search_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><circle cx='10' cy='10' r='6.5' fill='none' stroke='currentColor' stroke-width='2.4'/><path d='M15 15l6 6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round'/></svg>"
}

fn eye_icon(open: bool) -> str {
    if open { ret "<svg viewBox='0 0 24 24'><path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z' fill='none' stroke='currentColor' stroke-width='2'/><circle cx='12' cy='12' r='3' fill='currentColor'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z M3 3l18 18' fill='none' stroke='currentColor' stroke-width='2'/></svg>"
}

fn masked(a: *mem.Arena, count: usize) -> str {
    var out = ""
    var i = 0usize
    while i < count && i < 24usize {
        out = ui.join(a, out, "*", "")
        i += 1usize
    }
    ret out
}

fn draw_lock(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.disc(a, builder, 206.0, 150.0, 48.0, ui.amber())
    try svg.draw(a, builder, lock_icon(), geometry.rect(182.0, 126.0, 48.0, 48.0), ui.ink())
    try ui.centred(a, builder, faces.jost_bold, 28.0, "Secure", 206.0, 222.0, ui.light())
    var prompt = "Enter your master password"
    var button = "Unlock"
    var note = ""
    if s.storage == STORAGE_NONE { note = "Sample vault, nothing is saved: the password is neper" }
    if s.storage == STORAGE_NEW {
        if s.stage == 0usize {
            prompt = "Create a master password"
            button = "Next"
            note = "It cannot be recovered if you forget it"
        } else {
            prompt = "Repeat the password"
            button = "Create"
        }
    }
    if s.job != JOB_NONE {
        prompt = "Working on the key..."
        note = ""
    }
    try ui.centred(a, builder, faces.jost, 16.0, prompt, 206.0, 266.0, ui.light_muted())
    try ui.card(a, builder, 14.0, 310.0, 384.0, 56.0, 18.0, ui.amber())
    try ui.card(a, builder, 16.0, 312.0, 380.0, 52.0, 16.0, ui.cream())
    try ui.put(a, builder, faces.jost, 22.0, masked(a, s.master.len), 32.0, 324.0, ui.ink())
    if s.message_len > 0usize {
        try ui.centred(a, builder, faces.jost, 15.0, s.message[0usize..s.message_len], 206.0, 382.0, ui.loss())
    } else if note.len > 0usize {
        try ui.centred(a, builder, faces.grotesk, 12.0, note, 206.0, 384.0, ui.light_muted())
    }
    try ui.keyboard(a, builder, &s.hits, faces, button)
    ret ok
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Secure", 20.0, 16.0, ui.light())
    try svg.draw(a, builder, lock_icon(), geometry.rect(364.0, 22.0, 24.0, 24.0), ui.light_muted())
    ui.hit(&s.hits, 150usize, 350.0, 10.0, 56.0, 50.0)
    try svg.draw(a, builder, search_icon(), geometry.rect(318.0, 22.0, 24.0, 24.0), ui.light_muted())
    ui.hit(&s.hits, 160usize, 298.0, 10.0, 52.0, 50.0)
    var tab = 0usize
    while tab < 2usize {
        var label = "Passwords"
        if tab == 1usize { label = "Codes" }
        var fill = ui.soft()
        if tab == s.tab { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + tab, 16.0 + f32(tab) * 130.0, 70.0, 120.0, 38.0, label, fill, 16.0)
        tab += 1usize
    }
    if s.tab == 0usize {
        var row = 0usize
        var i = 0usize
        while i < MAX_LOGINS {
            if s.logins[i].used {
                let y: f32 = 120.0 + f32(row) * 72.0
                try ui.card(a, builder, 16.0, y + 2.0, 380.0, 66.0, 18.0, ui.cream())
                try ui.disc(a, builder, 50.0, y + 35.0, 20.0, ui.tint(i))
                let site = site_of(a, s, i)
                try ui.centred(a, builder, faces.jost_bold, 18.0, site[0usize..1usize], 50.0, y + 24.0, ui.ink())
                try ui.put(a, builder, faces.jost, 18.0, site, 84.0, y + 10.0, ui.ink())
                try ui.put(a, builder, faces.grotesk, 12.0, user_of(a, s, i), 84.0, y + 38.0, ui.muted())
                ui.hit(&s.hits, 200usize + i, 16.0, y + 2.0, 380.0, 66.0)
                row += 1usize
            }
            i += 1usize
        }
    } else {
        // The one-time codes: six digits, the seconds left in this window and a ring that empties.
        var row = 0usize
        var i = 0usize
        while i < MAX_CODES {
            if s.codes[i].used {
                var left = entry_period(s, i) - s.now % entry_period(s, i)
                if s.codes[i].hotp { left = s.codes[i].counter % 100usize }
                let y: f32 = 120.0 + f32(row) * 100.0
                try ui.card(a, builder, 16.0, y + 2.0, 380.0, 92.0, 18.0, ui.cream())
                try ui.put(a, builder, faces.jost, 16.0, issuer_of(a, s, i), 32.0, y + 10.0, ui.ink())
                try ui.put(a, builder, faces.grotesk, 12.0, account_of(a, s, i), 32.0, y + 34.0, ui.muted())
                var tone = ui.amber_dark()
                if left <= 5usize { tone = ui.loss() }
                try ui.put(a, builder, faces.jost_bold, 32.0, code_text_n(a, entry_code(a, s, i), entry_digits(s, i)), 32.0, y + 48.0, tone)
                // The ring: an arc of 30 segments, as many as there are seconds left.
                let cx: f32 = 354.0
                let cy: f32 = y + 48.0
                try ui.disc(a, builder, cx, cy, 20.0, ui.soft())
                try ui.disc(a, builder, cx, cy, 15.0, ui.cream())
                try ui.centred(a, builder, faces.jost_bold, 15.0, ui.number(a, left), cx, cy - 9.0, tone)
                ui.hit(&s.hits, 300usize + i, 16.0, y + 2.0, 380.0, 92.0)
                row += 1usize
            }
            i += 1usize
        }
    }
    try ui.card(a, builder, 252.0, 820.0, 144.0, 56.0, 28.0, ui.amber())
    try ui.card(a, builder, 274.0 - 9.0, 848.0 - 1.5, 18.0, 3.0, 1.5, ui.ink())
    try ui.card(a, builder, 274.0 - 1.5, 848.0 - 9.0, 3.0, 18.0, 1.5, ui.ink())
    try ui.put(a, builder, faces.jost, 17.0, "Add", 300.0, 837.0, ui.ink())
    ui.hit(&s.hits, 400usize, 252.0, 820.0, 144.0, 56.0)
    if s.tab == 1usize {
        try ui.pill(a, builder, &s.hits, faces, 410usize, 16.0, 820.0, 76.0, 56.0, "Import", ui.soft(), 14.0)
        try ui.pill(a, builder, &s.hits, faces, 411usize, 96.0, 820.0, 76.0, 56.0, "Export", ui.soft(), 14.0)
        try ui.pill(a, builder, &s.hits, faces, 412usize, 176.0, 820.0, 70.0, 56.0, "Plain", ui.soft(), 14.0)
    }
    if s.note_len > 0usize { try ui.put(a, builder, faces.grotesk, 12.0, s.note[0usize..s.note_len], 20.0, 796.0, ui.light_muted()) }
    ret ok
}

fn draw_detail(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, site_of(a, s, s.open), 62.0, 20.0, ui.light())
    try ui.card(a, builder, 16.0, 84.0, 380.0, 230.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "User name", 32.0, 98.0, ui.muted())
    try ui.put(a, builder, faces.jost, 19.0, user_of(a, s, s.open), 32.0, 116.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Password", 32.0, 160.0, ui.muted())
    var shown = masked(a, s.logins[s.open].pass_len)
    if s.reveal { shown = pass_of(a, s, s.open) }
    try ui.put(a, builder, faces.jost, 19.0, shown, 32.0, 178.0, ui.ink())
    try svg.draw(a, builder, eye_icon(s.reveal), geometry.rect(354.0, 174.0, 28.0, 28.0), ui.muted())
    ui.hit(&s.hits, 510usize, 330.0, 160.0, 66.0, 56.0)
    // The strength: four bars.
    let st = strength(pass_of(a, s, s.open))
    try ui.put(a, builder, faces.grotesk, 12.0, "Strength", 32.0, 232.0, ui.muted())
    var bar = 0usize
    while bar < 4usize {
        var fill = ui.soft()
        if bar <= st { fill = ui.amber() }
        if st == 0usize && bar == 0usize { fill = ui.loss() }
        try ui.card(a, builder, 32.0 + f32(bar) * 88.0, 254.0, 80.0, 10.0, 5.0, fill)
        bar += 1usize
    }
    var verdict = "Weak"
    if st == 1usize { verdict = "Fair" }
    if st == 2usize { verdict = "Good" }
    if st == 3usize { verdict = "Strong" }
    try ui.put(a, builder, faces.jost, 15.0, verdict, 32.0, 274.0, ui.muted())
    try ui.pill(a, builder, &s.hits, faces, 520usize, 16.0, 340.0, 120.0, 46.0, "Copy", ui.amber(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 521usize, 146.0, 340.0, 120.0, 46.0, "Generate", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 522usize, 276.0, 340.0, 120.0, 46.0, "Delete", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 523usize, 16.0, 396.0, 120.0, 46.0, "Edit", ui.soft(), 16.0)
    // (C170) The breach check, and the generator's options: its length and whether it uses symbols.
    try ui.pill(a, builder, &s.hits, faces, 528usize, 146.0, 396.0, 120.0, 46.0, "Breach", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 529usize, 276.0, 396.0, 120.0, 46.0, ui.join(a, "Length ", ui.number(a, generator_length(s)), ""), ui.soft(), 14.0)
    var symbols = "No symbols"
    if s.gen_symbols { symbols = "Symbols" }
    try ui.pill(a, builder, &s.hits, faces, 530usize, 16.0, 452.0, 160.0, 46.0, symbols, ui.soft(), 14.0)
    if s.note_len > 0usize { try ui.put(a, builder, faces.jost, 15.0, s.note[0usize..s.note_len], 20.0, 516.0, ui.light()) }
    ret ok
}

// One code: the issuer and account, the six digits large, the seconds left, Edit and Delete.
fn draw_code(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, issuer_of(a, s, s.open), 62.0, 20.0, ui.light())
    let left = entry_period(s, s.open) - s.now % entry_period(s, s.open)
    var tone = ui.amber_dark()
    if left <= 5usize && !s.codes[s.open].hotp { tone = ui.loss() }
    try ui.card(a, builder, 16.0, 84.0, 380.0, 190.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "Account", 32.0, 98.0, ui.muted())
    try ui.put(a, builder, faces.jost, 19.0, account_of(a, s, s.open), 32.0, 116.0, ui.ink())
    try ui.put(a, builder, faces.jost_bold, 52.0, code_text_n(a, entry_code(a, s, s.open), entry_digits(s, s.open)), 32.0, 160.0, tone)
    if s.codes[s.open].hotp {
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Counter ", ui.number(a, s.codes[s.open].counter), ""), 32.0, 238.0, ui.muted())
        try ui.pill(a, builder, &s.hits, faces, 526usize, 276.0, 232.0, 100.0, 36.0, "Next", ui.amber(), 14.0)
    } else {
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.join(a, "Changes in ", ui.number(a, left), " s"), "", ""), 32.0, 238.0, ui.muted())
    }
    try ui.pill(a, builder, &s.hits, faces, 524usize, 16.0, 300.0, 120.0, 46.0, "Edit", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 522usize, 146.0, 300.0, 120.0, 46.0, "Delete", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 525usize, 276.0, 300.0, 120.0, 46.0, "Copy", ui.amber(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 527usize, 16.0, 356.0, 120.0, 46.0, "QR", ui.soft(), 16.0)
    ret ok
}

// (C170) The entry as a QR symbol another authenticator can scan, with what it says on it.
fn draw_qr(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, issuer_of(a, s, s.open), 62.0, 20.0, ui.light())
    try ui.card(a, builder, 16.0, 84.0, 380.0, 380.0, 20.0, ui.cream())
    let picture = qr_svg(a, uri_of(a, s, s.open))
    if picture.len > 0usize {
        try svg.draw(a, builder, picture, geometry.rect(46.0, 114.0, 320.0, 320.0), ui.ink())
    } else {
        try ui.centred(a, builder, faces.jost, 16.0, "This code does not fit a QR symbol", 206.0, 260.0, ui.ink())
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Scan it with another authenticator. Anyone who sees it can make your codes.", 20.0, 480.0, ui.light_muted())
    ret ok
}

// Whether `needle` is in `hay`, ignoring case.
fn has_text(hay: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    var at = 0usize
    while at + needle.len <= hay.len {
        var same = true
        var k = 0usize
        while k < needle.len {
            var x = hay[at + k]
            var y = needle[k]
            if x >= 65u8 && x <= 90u8 { x = x + 32u8 }
            if y >= 65u8 && y <= 90u8 { y = y + 32u8 }
            if x != y { same = false }
            k += 1usize
        }
        if same { ret true }
        at += 1usize
    }
    ret false
}

// The search screen: the query on the keyboard, the matching logins and codes above it.
fn draw_search(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 20.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 6.0, 66.0, 56.0)
    try ui.card(a, builder, 60.0, 12.0, 336.0, 44.0, 16.0, ui.cream())
    var query = ui.field_text(a, &s.search)
    if query.len == 0usize {
        try ui.put(a, builder, faces.jost, 18.0, "Search", 74.0, 22.0, ui.muted())
    } else {
        try ui.put(a, builder, faces.jost, 18.0, query, 74.0, 22.0, ui.ink())
    }
    var row = 0usize
    var i = 0usize
    while i < MAX_LOGINS && row < 5usize {
        if s.logins[i].used && (has_text(site_of(a, s, i), query) || has_text(user_of(a, s, i), query)) {
            let y: f32 = 72.0 + f32(row) * 84.0
            try ui.card(a, builder, 16.0, y, 380.0, 76.0, 18.0, ui.cream())
            try ui.put(a, builder, faces.jost, 18.0, site_of(a, s, i), 32.0, y + 12.0, ui.ink())
            try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Password  ", user_of(a, s, i), ""), 32.0, y + 44.0, ui.muted())
            ui.hit(&s.hits, 200usize + i, 16.0, y, 380.0, 76.0)
            row += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < MAX_CODES && row < 5usize {
        if s.codes[i].used && (has_text(issuer_of(a, s, i), query) || has_text(account_of(a, s, i), query)) {
            let y: f32 = 72.0 + f32(row) * 84.0
            try ui.card(a, builder, 16.0, y, 380.0, 76.0, 18.0, ui.cream())
            try ui.put(a, builder, faces.jost, 18.0, issuer_of(a, s, i), 32.0, y + 12.0, ui.ink())
            try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Code  ", account_of(a, s, i), ""), 32.0, y + 44.0, ui.muted())
            ui.hit(&s.hits, 300usize + i, 16.0, y, 380.0, 76.0)
            row += 1usize
        }
        i += 1usize
    }
    if row == 0usize { try ui.centred(a, builder, faces.jost, 16.0, "Nothing matches", 206.0, 200.0, ui.light_muted()) }
    try ui.keyboard(a, builder, &s.hits, faces, "Done")
    ret ok
}

fn field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, which: usize, label: str, value: str, y: f32) -> err {
    try ui.put(a, builder, faces.grotesk, 12.0, label, 20.0, y - 15.0, ui.light_muted())
    if s.focus == which { try ui.card(a, builder, 14.0, y - 2.0, 384.0, 44.0, 16.0, ui.amber()) }
    try ui.card(a, builder, 16.0, y, 380.0, 40.0, 14.0, ui.cream())
    try ui.clipped(a, builder, faces.jost, 17.0, value, 32.0, y + 9.0, 340.0, ui.ink())
    ui.hit(&s.hits, 1500usize + which, 16.0, y, 380.0, 40.0)
    ret ok
}

fn draw_add(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "New login"
    var l0 = "Site"
    var l1 = "User name"
    var l2 = "Password"
    if s.add_kind == 1usize {
        heading = "New code"
        l0 = "Issuer"
        l1 = "Account"
        l2 = "Secret (base32)"
    }
    if s.edit != NONE {
        heading = "Edit login"
        if s.add_kind == 1usize { heading = "Edit code" }
    }
    try ui.put(a, builder, faces.jost_bold, 28.0, heading, 24.0, 14.0, ui.light())
    try field(a, builder, s, faces, 0usize, l0, ui.field_text(a, &s.f0), 80.0)
    try field(a, builder, s, faces, 1usize, l1, ui.field_text(a, &s.f1), 146.0)
    try field(a, builder, s, faces, 2usize, l2, ui.field_text(a, &s.f2), 212.0)
    try ui.pill(a, builder, &s.hits, faces, 1300usize, 16.0, 272.0, 186.0, 46.0, "Save", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 1302usize, 210.0, 272.0, 186.0, 46.0, "Cancel", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LOCK_SCREEN { try draw_lock(a, builder, s, faces) }
    if s.screen == LIST_SCREEN { try draw_list(a, builder, s, faces) }
    if s.screen == DETAIL_SCREEN { try draw_detail(a, builder, s, faces) }
    if s.screen == ADD_SCREEN { try draw_add(a, builder, s, faces) }
    if s.screen == SEARCH_SCREEN { try draw_search(a, builder, s, faces) }
    if s.screen == CODE_SCREEN { try draw_code(a, builder, s, faces) }
    if s.screen == QR_SCREEN { try draw_qr(a, builder, s, faces) }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn focused(s: *State) -> *ui.Field {
    if s.focus == 0usize { ret &s.f0 }
    if s.focus == 1usize { ret &s.f1 }
    ret &s.f2
}

fn clock_now() -> usize {
    let (wall, wall_error) = time.now()
    if wall_error != ok { ret 0usize }
    ret usize(wall.nanos / 1000000000i64)
}

// Fill the add form from entry `i` (a login, or a code when `code`) for editing.
fn fill_form(a: *mem.Arena, s: *State, code: bool, i: usize) {
    s.f0.len = 0usize
    s.f1.len = 0usize
    s.f2.len = 0usize
    var k = 0usize
    if code {
        while k < s.codes[i].issuer_len {
            ui.field_type(&s.f0, s.codes[i].issuer[k], false)
            k += 1usize
        }
        k = 0usize
        while k < s.codes[i].account_len {
            ui.field_type(&s.f1, s.codes[i].account[k], false)
            k += 1usize
        }
        k = 0usize
        while k < s.codes[i].secret_len {
            ui.field_type(&s.f2, s.codes[i].secret[k], false)
            k += 1usize
        }
    } else {
        while k < s.logins[i].site_len {
            ui.field_type(&s.f0, s.logins[i].site[k], false)
            k += 1usize
        }
        k = 0usize
        while k < s.logins[i].user_len {
            ui.field_type(&s.f1, s.logins[i].user[k], false)
            k += 1usize
        }
        k = 0usize
        while k < s.logins[i].pass_len {
            ui.field_type(&s.f2, s.logins[i].pass[k], false)
            k += 1usize
        }
    }
}

// Store the add form: a new entry, or the one being edited, and write its record.
fn commit_form(a: *mem.Arena, s: *State) {
    let code = s.add_kind == 1usize
    var index = s.edit
    if index == NONE {
        if code { index = add_code(s, ui.field_text(a, &s.f0), ui.field_text(a, &s.f1), ui.field_text(a, &s.f2)) } else { index = add_login(s, ui.field_text(a, &s.f0), ui.field_text(a, &s.f1), ui.field_text(a, &s.f2)) }
        ui.say("secure added\n")
    } else {
        if code { s.codes[index].used = false } else { s.logins[index].used = false }
        var again = NONE
        if code { again = add_code(s, ui.field_text(a, &s.f0), ui.field_text(a, &s.f1), ui.field_text(a, &s.f2)) } else { again = add_login(s, ui.field_text(a, &s.f0), ui.field_text(a, &s.f1), ui.field_text(a, &s.f2)) }
        // The first free slot is the one just emptied (or an earlier one): the record follows the entry.
        if again != index {
            forget_record(a, s, code, index)
            index = again
        }
        ui.say("secure edited\n")
    }
    if index != NONE { save_record(a, s, code, index) }
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.job != JOB_NONE { ret false }
    if s.screen == LOCK_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                s.message_len = 0usize
                if s.storage == STORAGE_NONE {
                    if ui.same(ui.field_text(a, &s.master), "neper") {
                        s.screen = LIST_SCREEN
                        s.wrong = false
                        ui.say("secure unlocked\n")
                    } else {
                        s.wrong = true
                        s.master.len = 0usize
                        ui.say("secure wrong password\n")
                    }
                    ret true
                }
                if s.master.len == 0usize { ret true }
                if s.storage == STORAGE_NEW {
                    if s.stage == 0usize {
                        if s.master.len < 4usize {
                            say_message(s, "At least 4 characters")
                            ret true
                        }
                        s.first.len = 0usize
                        var k = 0usize
                        while k < s.master.len {
                            ui.field_type(&s.first, s.master.bytes[k], false)
                            k += 1usize
                        }
                        s.master.len = 0usize
                        s.stage = 1usize
                        ret true
                    }
                    if ui.same(ui.field_text(a, &s.first), ui.field_text(a, &s.master)) {
                        s.job = JOB_CREATE
                        ui.say("secure creating the vault\n")
                    } else {
                        say_message(s, "They differ. Start again.")
                        s.stage = 0usize
                        s.master.len = 0usize
                        s.first.len = 0usize
                    }
                    ret true
                }
                s.job = JOB_UNLOCK
                ui.say("secure unlocking\n")
                ret true
            }
            s.message_len = 0usize
            ret ui.field_key(&s.master, id, false)
        }
        ret false
    }
    if s.screen == SEARCH_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                s.screen = LIST_SCREEN
                ret true
            }
            ret ui.field_key(&s.search, id, false)
        }
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        // A result opens like a row of the list does; fall through to the list's handling.
        if id >= 200usize && id < 200usize + MAX_LOGINS {
            s.open = id - 200usize
            s.screen = DETAIL_SCREEN
            s.reveal = false
            ui.say("secure opened ")
            ui.say_text(site_of(a, s, s.open))
            ui.say("\n")
            ret true
        }
        if id >= 300usize && id < 300usize + MAX_CODES {
            s.open = id - 300usize
            s.now = clock_now()
            s.screen = CODE_SCREEN
            ui.say("secure opened code\n")
            ret true
        }
        ret false
    }
    if s.screen == ADD_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.focus < 2usize { s.focus += 1usize }
                ret true
            }
            ret ui.field_key(focused(s), id, false)
        }
        if id >= 1500usize && id < 1503usize {
            s.focus = id - 1500usize
            ret true
        }
        if id == 1300usize {
            if s.f0.len > 0usize { commit_form(a, s) }
            s.screen = LIST_SCREEN
            s.edit = NONE
            ret true
        }
        if id == 1302usize {
            s.screen = LIST_SCREEN
            s.edit = NONE
            ret true
        }
        ret false
    }
    if s.screen == QR_SCREEN {
        if id == 500usize {
            s.screen = CODE_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == CODE_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 527usize {
            s.screen = QR_SCREEN
            ui.say("secure qr shown\n")
            ret true
        }
        if id == 526usize && s.codes[s.open].hotp {
            // Next: the counter moves on, and the entry is sealed again with it.
            s.codes[s.open].counter += 1usize
            save_record(a, s, true, s.open)
            ui.say("secure counter ")
            ui.say_num(s.codes[s.open].counter)
            ui.say("\n")
            ret true
        }
        if id == 525usize {
            // Copy the code as plain digits; the clipboard clears itself after ninety seconds.
            let digits = code_digits(a, entry_code(a, s, s.open), entry_digits(s, s.open))
            let taken = sysettings.clip_set(1usize, clock_now(), digits)
            ui.say("secure copied code ")
            ui.say_num(digits.len)
            ui.say(" digits\n")
            ret true
        }
        if id == 524usize {
            s.edit = s.open
            s.add_kind = 1usize
            fill_form(a, s, true, s.open)
            s.focus = 0usize
            s.screen = ADD_SCREEN
            ret true
        }
        if id == 522usize {
            s.codes[s.open].used = false
            s.screen = LIST_SCREEN
            ui.say("secure deleted\n")
            forget_record(a, s, true, s.open)
            ret true
        }
        ret false
    }
    if s.screen == DETAIL_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            s.reveal = false
            s.note_len = 0usize
            ret true
        }
        if id == 528usize {
            // (C170) The breach check: only the SHA-1 prefix leaves the device.
            let (seen, outcome) = breach_check(a, pass_of(a, s, s.open))
            if outcome == 1usize {
                set_note(s, "No network: could not check")
                ui.say("secure breach no network\n")
            } else if outcome == 2usize {
                set_note(s, "The breach service did not answer")
                ui.say("secure breach failed\n")
            } else if seen == 0usize {
                set_note(s, "Not found in known breaches")
                ui.say("secure breach none\n")
            } else {
                set_note(s, ui.join(a, ui.join(a, "Seen in ", ui.number(a, seen), " breaches"), "", ""))
                ui.say("secure breach seen ")
                ui.say_num(seen)
                ui.say("\n")
            }
            ret true
        }
        if id == 529usize {
            var next = 16usize
            if generator_length(s) == 16usize { next = 24usize }
            if generator_length(s) == 24usize { next = 12usize }
            s.gen_len = next
            ui.say("secure generator length ")
            ui.say_num(next)
            ui.say("\n")
            ret true
        }
        if id == 530usize {
            s.gen_symbols = !s.gen_symbols
            ret true
        }
        if id == 510usize {
            s.reveal = !s.reveal
            if s.reveal { ui.say("secure revealed\n") }
            ret true
        }
        if id == 520usize {
            let taken = sysettings.clip_set(1usize, clock_now(), pass_of(a, s, s.open))
            ui.say("secure copied\n")
            ret true
        }
        if id == 521usize {
            let made = generate(a, s)
            var k = 0usize
            while k < made.len && k < 24usize {
                s.logins[s.open].pass[k] = made[k]
                k += 1usize
            }
            s.logins[s.open].pass_len = k
            save_record(a, s, false, s.open)
            ui.say("secure generated\n")
            ret true
        }
        if id == 523usize {
            s.edit = s.open
            s.add_kind = 0usize
            fill_form(a, s, false, s.open)
            s.focus = 0usize
            s.screen = ADD_SCREEN
            ret true
        }
        if id == 522usize {
            s.logins[s.open].used = false
            s.screen = LIST_SCREEN
            ui.say("secure deleted\n")
            forget_record(a, s, false, s.open)
            ret true
        }
        ret false
    }
    if id == 150usize {
        lock_now(s)
        ui.say("secure locked\n")
        ret true
    }
    if id == 411usize || id == 412usize {
        // (C170) Export: sealed under the vault key, or (Plain) as otpauth URIs any authenticator reads.
        let wrote = export_codes(a, s, id == 412usize)
        ret true
    }
    if id == 160usize {
        s.screen = SEARCH_SCREEN
        s.search.len = 0usize
        s.now = clock_now()
        ui.say("secure search\n")
        ret true
    }
    if id == 100usize || id == 101usize {
        s.tab = id - 100usize
        if s.tab == 1usize {
            s.now = clock_now()
            ui.say("secure codes shown\n")
        }
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_LOGINS {
        s.open = id - 200usize
        s.screen = DETAIL_SCREEN
        s.reveal = false
        ui.say("secure opened ")
        ui.say_text(site_of(a, s, s.open))
        ui.say("\n")
        ret true
    }
    if id >= 300usize && id < 300usize + MAX_CODES {
        s.open = id - 300usize
        s.now = clock_now()
        s.screen = CODE_SCREEN
        ui.say("secure opened code\n")
        ret true
    }
    if id == 410usize {
        // Every line of the file that is an otpauth URI becomes an entry.
        var line = 0usize
        var imported = 0usize
        while line < 8usize {
            let index = import_uri(a, s, line)
            line += 1usize
            if index != NONE {
                save_record(a, s, true, index)
                imported += 1usize
                ui.say("secure imported ")
                ui.say_text(issuer_of(a, s, index))
                ui.say(" algo ")
                ui.say_num(s.codes[index].algo)
                ui.say(" digits ")
                ui.say_num(entry_digits(s, index))
                if s.codes[index].hotp {
                    ui.say(" counter ")
                    ui.say_num(s.codes[index].counter)
                } else {
                    ui.say(" period ")
                    ui.say_num(entry_period(s, index))
                }
                ui.say("\n")
            }
        }
        s.now = clock_now()
        if imported == 0usize {
            ui.say("secure import failed\n")
            ret false
        }
        ret true
    }
    if id == 400usize {
        s.screen = ADD_SCREEN
        s.add_kind = s.tab
        s.edit = NONE
        s.f0.len = 0usize
        s.f1.len = 0usize
        s.f2.len = 0usize
        s.focus = 0usize
        ret true
    }
    ret false
}

// A code of up to eight digits with its leading zeros, to the console.
fn say_digits8(value: usize) {
    var out: [8]u8 = zero
    var rest = value
    var i = 8usize
    while i > 0usize {
        i -= 1usize
        out[i] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
    }
    ui.say_text(out[0usize..8usize])
}

// The work behind Create and Unlock, done on a tick so the screen can say it is working first.
fn run_job(a: *mem.Arena, s: *State) {
    let job = s.job
    s.job = JOB_NONE
    if job == JOB_CREATE {
        if create_vault(a, s) {
            s.storage = STORAGE_DISK
            s.screen = LIST_SCREEN
            s.master.len = 0usize
            s.first.len = 0usize
            s.message_len = 0usize
            ui.say("secure vault created\n")
        } else {
            s.stage = 0usize
            s.master.len = 0usize
            s.first.len = 0usize
            ui.say("secure vault create failed\n")
        }
        ret
    }
    let opened = unlock_vault(a, s)
    if opened == 0usize {
        s.screen = LIST_SCREEN
        s.master.len = 0usize
        s.message_len = 0usize
        ui.say("secure unlocked\n")
        let loaded = load_records(a, s)
        ui.say("secure loaded ")
        ui.say_num(loaded)
        ui.say("\n")
        // The codes at the RFC 6238 test time (59 s), eight digits: the same on every run, so a test can check them.
        var i = 0usize
        while i < MAX_CODES {
            if s.codes[i].used {
                ui.say("secure code at 59 ")
                say_digits8(totp(secret_of(a, s, i), 59usize, 8usize))
                ui.say("\n")
            }
            i += 1usize
        }
    } else if opened == 1usize {
        s.master.len = 0usize
        say_message(s, "Wrong password. Try again.")
        ui.say("secure wrong password\n")
    } else {
        s.master.len = 0usize
        say_message(s, "The vault could not be read")
        ui.say("secure vault unreadable\n")
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "secure")
    if kit_error != ok {
        ui.say("secure open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("secure fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.seed = 9137usize
    s.now = clock_now()
    s.last_active = s.now
    s.edit = NONE
    // The one-time password maths against RFC 6238: the SHA-1 secret "12345678901234567890" at time 59 gives
    // 94287082 with eight digits ("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" in base32).
    if totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 59usize, 8usize) == 94287082usize { ui.say("secure totp check ok\n") } else { ui.say("secure totp check FAILED\n") }
    // Where the vault lives: with no storage capability the sample vault runs as it always did; with storage,
    // a vault is created on first use and unlocked after.
    let (reachable, has_vault) = vaultfs.probe("/vmeta")
    if !reachable {
        s.storage = STORAGE_NONE
        let _ = add_login(&s, "Neper Bank", "sam.rivera", "correct-horse-battery")
        let _ = add_login(&s, "City Library", "sam.r", "Lib2024!")
        let _ = add_login(&s, "Mail", "sam@example.com", "t7Kq-9mZp2Vx_4Rw")
        let _ = add_login(&s, "Neper Cloud", "sam", "hunter22")
        let _ = add_code(&s, "Neper Bank", "sam.rivera", "JBSWY3DPEHPK3PXP")
        let _ = add_code(&s, "Mail", "sam@example.com", "GEZDGNBVGY3TQOJQ")
        let _ = add_code(&s, "Neper Cloud", "sam", "MFRGGZDFMZTWQ2LK")
        ui.say("secure storage none\n")
    } else if has_vault {
        s.storage = STORAGE_DISK
        ui.say("secure storage disk\n")
    } else {
        s.storage = STORAGE_NEW
        ui.say("secure storage new\n")
    }
    s.open = NONE
    if !show(a, &kit, &s) {
        ui.say("secure present failed\n")
        ret ok
    }
    ui.say("secure shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            if s.job != JOB_NONE {
                run_job(a, &s)
                s.last_active = clock_now()
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else if s.screen != LOCK_SCREEN && clock_now() >= s.last_active + AUTO_LOCK_SECONDS {
                // (C170) Auto-lock: a minute without a tap and the vault is wiped from memory and locked.
                lock_now(&s)
                ui.say("secure auto-locked\n")
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else if (s.screen == LIST_SCREEN && s.tab == 1usize) || s.screen == CODE_SCREEN {
                // On the codes the clock and the countdown follow the ticks, once a second.
                s.now = clock_now()
                if tap.ms % 1000usize < 500usize {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            s.last_active = clock_now()
            ui.say("secure home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            s.last_active = clock_now()
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("secure present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
