// `misc_gaps`: the planned names added to a miscellany of modules -- float
// unpack/pack, saturating arithmetic, string padding, intervals, Julian days,
// the observer record, CBC and AES-GCM by name, Certificate Transparency SCTs,
// demangling, grid BFS / rays / Theta*, dither, CIDR and private ranges,
// SameSite / CORS / CSP, PKCE and WebAuthn, constrained decoding, LPA* / D*
// Lite / PRM. Every expected value comes from scripts in the scratchpad
// (ref.py); each check exits with its own code.

use e.algo.rand
use e.audio
use e.control
use e.crypto.aead as aead
use e.crypto.cipher as cipher
use e.crypto.sign as sign
use e.crypto.x509 as x509
use e.debug
use e.game.grid
use e.io
use e.math
use e.math.float
use e.mem
use e.net
use e.net.http as http
use e.net.http.auth as auth
use e.os
use e.parse
use e.robot.plan
use e.str
use e.time
use e.time.calendar as calendar

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// FNV-1a over little-endian i64 words, the fold ref.py mirrors.
fn fnv_step(h: u64, v: i64) -> u64 {
    var acc = h
    let bits = mem.bitcast[u64](v)
    var i = 0u32
    while i < 8u32 {
        acc = acc ^ ((bits >> (8u32 * i)) & 255u64)
        acc = acc *% 1099511628211u64
        i += 1u32
    }
    ret acc
}

fn fnv_start() -> u64 { ret 14695981039346656037u64 }

fn date(y: i32, m: u8, d: u8) -> time.Date {
    var out: time.Date = zero
    out.year = y
    out.month = m
    out.day = d
    ret out
}

// 1: float unpack/pack.
fn check_float() -> i32 {
    let (negative0, exponent0, mantissa0) = float.unpack(mem.bitcast[f64](4607182418800017408u64))
    if negative0 != false || exponent0 != 1023u32 || mantissa0 != 0u64 { ret 1i32 }
    if mem.bitcast[u64](float.pack(negative0, exponent0, mantissa0)) != 4607182418800017408u64 { ret 1i32 }
    let (negative1, exponent1, mantissa1) = float.unpack(mem.bitcast[f64](13836183955189006336u64))
    if negative1 != true || exponent1 != 1024u32 || mantissa1 != 1125899906842624u64 { ret 1i32 }
    if mem.bitcast[u64](float.pack(negative1, exponent1, mantissa1)) != 13836183955189006336u64 { ret 1i32 }
    let (negative2, exponent2, mantissa2) = float.unpack(mem.bitcast[f64](4962930089146241889u64))
    if negative2 != false || exponent2 != 1101u32 || mantissa2 != 4466899411325793u64 { ret 1i32 }
    if mem.bitcast[u64](float.pack(negative2, exponent2, mantissa2)) != 4962930089146241889u64 { ret 1i32 }
    let (negative3, exponent3, mantissa3) = float.unpack(mem.bitcast[f64](1u64))
    if negative3 != false || exponent3 != 0u32 || mantissa3 != 1u64 { ret 1i32 }
    if mem.bitcast[u64](float.pack(negative3, exponent3, mantissa3)) != 1u64 { ret 1i32 }
    let (negative4, exponent4, mantissa4) = float.unpack(mem.bitcast[f64](9223372036854775808u64))
    if negative4 != true || exponent4 != 0u32 || mantissa4 != 0u64 { ret 1i32 }
    if mem.bitcast[u64](float.pack(negative4, exponent4, mantissa4)) != 9223372036854775808u64 { ret 1i32 }
    let f = float.unpack32(1.5f32)
    if f.negative || f.exponent != 127u32 || f.mantissa != 4194304u64 { ret 1i32 }
    ret 0i32
}

// 2: saturating add/sub/mul over i8, u8, i32, u64, i64.
fn check_saturating() -> i32 {
    if math.saturating_add[i8](100i8, 100i8) != 127i8 { ret 2i32 }
    if math.saturating_add[i8](-100i8, -100i8) != (-127i8 - 1i8) { ret 2i32 }
    if math.saturating_add[i8](50i8, -100i8) != -50i8 { ret 2i32 }
    if math.saturating_sub[i8](-100i8, 100i8) != (-127i8 - 1i8) { ret 2i32 }
    if math.saturating_sub[i8](100i8, -100i8) != 127i8 { ret 2i32 }
    if math.saturating_mul[i8](-127i8 - 1i8, -1i8) != 127i8 { ret 2i32 }
    if math.saturating_mul[i8](16i8, 8i8) != 127i8 { ret 2i32 }
    if math.saturating_mul[i8](-16i8, 8i8) != (-127i8 - 1i8) { ret 2i32 }
    if math.saturating_mul[i8](11i8, -12i8) != (-127i8 - 1i8) { ret 2i32 }
    if math.saturating_mul[i8](11i8, -11i8) != -121i8 { ret 2i32 }
    if math.saturating_add[u8](200u8, 100u8) != 255u8 { ret 2i32 }
    if math.saturating_sub[u8](3u8, 5u8) != 0u8 { ret 2i32 }
    if math.saturating_mul[u8](16u8, 16u8) != 255u8 { ret 2i32 }
    if math.saturating_mul[u8](15u8, 17u8) != 255u8 { ret 2i32 }
    if math.saturating_mul[u8](15u8, 16u8) != 240u8 { ret 2i32 }
    if math.saturating_add[i32](2147483000i32, 1000i32) != 2147483647i32 { ret 2i32 }
    if math.saturating_mul[i32](-65536i32, 32768i32) != (-2147483647i32 - 1i32) { ret 2i32 }
    if math.saturating_mul[i32](46341i32, 46341i32) != 2147483647i32 { ret 2i32 }
    if math.saturating_add[u64](18446744073709551615u64, 1u64) != 18446744073709551615u64 { ret 2i32 }
    if math.saturating_mul[u64](4294967296u64, 4294967296u64) != 18446744073709551615u64 { ret 2i32 }
    if math.saturating_mul[u64](4294967295u64, 4294967297u64) != 18446744073709551615u64 { ret 2i32 }
    if math.saturating_add[i64](-9223372036854775807i64 - 1i64, -1i64) != (-9223372036854775807i64 - 1i64) { ret 2i32 }
    if math.saturating_sub[i64](-9223372036854775807i64 - 1i64, 1i64) != (-9223372036854775807i64 - 1i64) { ret 2i32 }
    if math.saturating_mul[i64](-4611686018427387904i64, 4i64) != (-9223372036854775807i64 - 1i64) { ret 2i32 }
    if math.saturating_mul[i64](3037000500i64, 3037000500i64) != 9223372036854775807i64 { ret 2i32 }
    if math.saturating_mul[i64](3037000499i64, 3037000499i64) != 9223372030926249001i64 { ret 2i32 }
    ret 0i32
}

// 3: padding counted in code points.
fn check_pad(a: *mem.Arena) -> i32 {
    let (out0, e0) = str.pad(a, "\xc3\xa9", 4usize, .Left, "*")
    if e0 != ok || !str.eq(out0, "***\xc3\xa9") { ret 3i32 }
    let (out1, e1) = str.pad(a, "ab", 7usize, .Center, "-")
    if e1 != ok || !str.eq(out1, "--ab---") { ret 3i32 }
    let (out2, e2) = str.pad(a, "abc", 6usize, .Right, "\xe2\x86\x92")
    if e2 != ok || !str.eq(out2, "abc\xe2\x86\x92\xe2\x86\x92\xe2\x86\x92") { ret 3i32 }
    let (out3, e3) = str.pad(a, "hello", 3usize, .Left, "x")
    if e3 != ok || !str.eq(out3, "hello") { ret 3i32 }
    let (out4, e4) = str.pad(a, "\xe6\x97\xa5\xe6\x9c\xac", 5usize, .Center, "\xe2\x86\x92")
    if e4 != ok || !str.eq(out4, "\xe2\x86\x92\xe6\x97\xa5\xe6\x9c\xac\xe2\x86\x92\xe2\x86\x92") { ret 3i32 }
    let (left, left_error) = str.pad_left(a, "ab", 4usize, "0")
    if left_error != ok || !str.eq(left, "00ab") { ret 3i32 }
    let (right, right_error) = str.pad_right(a, "ab", 4usize, "0")
    if right_error != ok || !str.eq(right, "ab00") { ret 3i32 }
    let (centre, centre_error) = str.pad_center(a, "ab", 5usize, "0")
    if centre_error != ok || !str.eq(centre, "0ab00") { ret 3i32 }
    let (_, empty_error) = str.pad(a, "ab", 5usize, .Left, "")
    if empty_error != str.InvalidSeparator { ret 3i32 }
    ret 0i32
}

// 4: half-open intervals.
fn check_intervals() -> i32 {
    if time.intervals_overlap(time.Interval { start: 1i64, end: 3i64 }, time.Interval { start: 3i64, end: 5i64 }) != false { ret 4i32 }
    if time.intervals_overlap(time.Interval { start: 1i64, end: 4i64 }, time.Interval { start: 3i64, end: 5i64 }) != true { ret 4i32 }
    if time.intervals_overlap(time.Interval { start: 5i64, end: 6i64 }, time.Interval { start: 1i64, end: 5i64 }) != false { ret 4i32 }
    if time.intervals_overlap(time.Interval { start: 0i64, end: 10i64 }, time.Interval { start: 2i64, end: 3i64 }) != true { ret 4i32 }
    var xs: [8]time.Interval = zero
    xs[0usize] = time.Interval { start: 1i64, end: 3i64 }
    xs[1usize] = time.Interval { start: 2i64, end: 5i64 }
    xs[2usize] = time.Interval { start: 5i64, end: 7i64 }
    xs[3usize] = time.Interval { start: 8i64, end: 9i64 }
    xs[4usize] = time.Interval { start: 8i64, end: 12i64 }
    xs[5usize] = time.Interval { start: 13i64, end: 14i64 }
    xs[6usize] = time.Interval { start: 20i64, end: 25i64 }
    xs[7usize] = time.Interval { start: 21i64, end: 22i64 }
    let kept = time.intervals_merge(xs[..])
    if kept != 4usize { ret 4i32 }
    if xs[0usize].start != 1i64 || xs[0usize].end != 7i64 { ret 4i32 }
    if xs[1usize].start != 8i64 || xs[1usize].end != 12i64 { ret 4i32 }
    if xs[2usize].start != 13i64 || xs[2usize].end != 14i64 { ret 4i32 }
    if xs[3usize].start != 20i64 || xs[3usize].end != 25i64 { ret 4i32 }
    if time.intervals_merge(xs[..0usize]) != 0usize { ret 4i32 }
    ret 0i32
}

// 5: Julian day numbers.
fn check_julian() -> i32 {
    let (jd0, e0) = calendar.julian_day(date(2000i32, 1u8, 1u8))
    if e0 != ok || jd0 != 2451545i64 { ret 5i32 }
    let back0 = calendar.julian_day_to_date(2451545i64)
    if back0.year != 2000i32 || back0.month != 1u8 || back0.day != 1u8 { ret 5i32 }
    let (jd1, e1) = calendar.julian_day(date(1582i32, 10u8, 15u8))
    if e1 != ok || jd1 != 2299161i64 { ret 5i32 }
    let back1 = calendar.julian_day_to_date(2299161i64)
    if back1.year != 1582i32 || back1.month != 10u8 || back1.day != 15u8 { ret 5i32 }
    let (jd2, e2) = calendar.julian_day(date(1970i32, 1u8, 1u8))
    if e2 != ok || jd2 != 2440588i64 { ret 5i32 }
    let back2 = calendar.julian_day_to_date(2440588i64)
    if back2.year != 1970i32 || back2.month != 1u8 || back2.day != 1u8 { ret 5i32 }
    let (jd3, e3) = calendar.julian_day(date(2026i32, 9u8, 22u8))
    if e3 != ok || jd3 != 2461306i64 { ret 5i32 }
    let back3 = calendar.julian_day_to_date(2461306i64)
    if back3.year != 2026i32 || back3.month != 9u8 || back3.day != 22u8 { ret 5i32 }
    let (jd4, e4) = calendar.julian_day(date(-4713i32, 11u8, 24u8))
    if e4 != ok || jd4 != 0i64 { ret 5i32 }
    let back4 = calendar.julian_day_to_date(0i64)
    if back4.year != -4713i32 || back4.month != 11u8 || back4.day != 24u8 { ret 5i32 }
    let (jd5, e5) = calendar.julian_day(date(1i32, 1u8, 1u8))
    if e5 != ok || jd5 != 1721426i64 { ret 5i32 }
    let back5 = calendar.julian_day_to_date(1721426i64)
    if back5.year != 1i32 || back5.month != 1u8 || back5.day != 1u8 { ret 5i32 }
    let (_, bad) = calendar.julian_day(date(2001i32, 2u8, 29u8))
    if bad != calendar.Invalid { ret 5i32 }
    ret 0i32
}

// 6: the observer record, 20 steps against numpy.
fn check_observer() -> i32 {
    let a = [4]f64{ 1.0, 0.1, -0.2, 0.95 }
    let b = [2]f64{ 0.0, 0.1 }
    let c = [2]f64{ 1.0, 0.0 }
    let l = [2]f64{ 0.5, 0.3 }
    var x = [2]f64{ 1.0, -0.5 }
    var x_hat: [2]f64 = zero
    var scratch: [8]f64 = zero
    var o = control.observer(a[0..], b[0..], c[0..], l[0..], 2usize, 1usize, 1usize, x_hat[0..])
    var k = 0usize
    while k < 20usize {
        let u = [1]f64{ math.sin[f64](0.3f64 * f64(k)) }
        let y = [1]f64{ x[0usize] }
        if control.observer_update(&o, u[0..], y[0..], scratch[0..]) != ok { ret 6i32 }
        let x0 = a[0usize] * x[0usize] + a[1usize] * x[1usize] + b[0usize] * u[0usize]
        let x1 = a[2usize] * x[0usize] + a[3usize] * x[1usize] + b[1usize] * u[0usize]
        x[0usize] = x0
        x[1usize] = x1
        k += 1usize
    }
    if math.abs[f64](x_hat[0usize] - (-0.5822983188889211f64)) > 1.0e-9f64 { ret 6i32 }
    if math.abs[f64](x_hat[1usize] - (-0.649037062374743f64)) > 1.0e-9f64 { ret 6i32 }
    ret 0i32
}

// 7: CBC by name, against cryptography.
fn check_cbc() -> i32 {
    let key = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    let iv = [16]u8{ 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115 }
    var data = [32]u8{ 3, 10, 17, 24, 31, 38, 45, 52, 59, 66, 73, 80, 87, 94, 101, 108, 115, 122, 129, 136, 143, 150, 157, 164, 171, 178, 185, 192, 199, 206, 213, 220 }
    let expected = [32]u8{ 249, 35, 38, 181, 44, 75, 118, 125, 32, 44, 226, 214, 0, 139, 8, 63, 77, 250, 191, 153, 75, 207, 132, 203, 9, 137, 211, 3, 30, 42, 251, 2 }
    let (k, key_error) = cipher.aes_key(key[0..])
    if key_error != ok { ret 7i32 }
    if cipher.cbc(&k, iv, data[0..], true) != ok || !same(data[0..], expected[0..]) { ret 7i32 }
    let original = [32]u8{ 3, 10, 17, 24, 31, 38, 45, 52, 59, 66, 73, 80, 87, 94, 101, 108, 115, 122, 129, 136, 143, 150, 157, 164, 171, 178, 185, 192, 199, 206, 213, 220 }
    if cipher.cbc(&k, iv, data[0..], false) != ok || !same(data[0..], original[0..]) { ret 7i32 }
    if cipher.cbc(&k, iv, data[..20usize], true) != cipher.Invalid { ret 7i32 }
    ret 0i32
}

// 8: AES-GCM dispatching on the key length.
fn check_gcm() -> i32 {
    let key24 = [24]u8{ 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46, 49, 52, 55, 58, 61, 64, 67, 70 }
    let key16 = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    let nonce = [12]u8{ 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61 }
    let expected24 = [35]u8{ 6, 130, 145, 143, 185, 232, 111, 138, 198, 39, 236, 90, 18, 141, 202, 253, 75, 80, 6, 129, 125, 181, 246, 226, 140, 111, 169, 0, 191, 110, 203, 245, 213, 172, 223 }
    let expected16 = [35]u8{ 197, 86, 106, 234, 205, 135, 43, 9, 66, 44, 243, 120, 167, 112, 114, 88, 166, 108, 198, 166, 188, 51, 48, 211, 180, 120, 240, 190, 156, 153, 166, 73, 211, 124, 255 }
    var sealed: [64]u8 = zero
    var opened: [64]u8 = zero
    let (n24, seal24) = aead.aes_gcm_seal(sealed[0..], key24[0..], nonce, "header", "the quick brown fox")
    if seal24 != ok || n24 != 35usize || !same(sealed[..n24], expected24[0..]) { ret 8i32 }
    let (m24, open24) = aead.aes_gcm_open(opened[0..], key24[0..], nonce, "header", sealed[..n24])
    if open24 != ok || m24 != 19usize || !same(opened[..m24], "the quick brown fox") { ret 8i32 }
    let (n16, seal16) = aead.aes_gcm_seal(sealed[0..], key16[0..], nonce, "header", "the quick brown fox")
    if seal16 != ok || !same(sealed[..n16], expected16[0..]) { ret 8i32 }
    sealed[3usize] = sealed[3usize] ^ 1u8
    let (_, tampered) = aead.aes_gcm_open(opened[0..], key16[0..], nonce, "header", sealed[..n16])
    if tampered != aead.Authentication { ret 8i32 }
    let (_, short_key) = aead.aes_gcm_seal(sealed[0..], key24[..20usize], nonce, "header", "x")
    if short_key != aead.InvalidKey { ret 8i32 }
    ret 0i32
}

// 9: Certificate Transparency SCTs signed in Python (P-256 over an X.509
// entry, Ed25519 over a precert entry).
fn check_ct() -> i32 {
    let cert = [70]u8{ 5, 18, 31, 44, 57, 70, 83, 96, 109, 122, 135, 148, 161, 174, 187, 200, 213, 226, 239, 252, 9, 22, 35, 48, 61, 74, 87, 100, 113, 126, 139, 152, 165, 178, 191, 204, 217, 230, 243, 0, 13, 26, 39, 52, 65, 78, 91, 104, 117, 130, 143, 156, 169, 182, 195, 208, 221, 234, 247, 4, 17, 30, 43, 56, 69, 82, 95, 108, 121, 134 }
    let sct_ec = [118]u8{ 0, 131, 111, 241, 132, 231, 180, 27, 30, 19, 203, 95, 216, 159, 161, 222, 152, 219, 186, 185, 158, 157, 41, 24, 145, 63, 244, 59, 134, 165, 199, 194, 19, 0, 0, 1, 139, 207, 229, 104, 123, 0, 0, 4, 3, 0, 71, 48, 69, 2, 32, 92, 137, 83, 37, 99, 245, 77, 22, 149, 232, 254, 40, 164, 120, 41, 125, 85, 157, 36, 134, 137, 162, 103, 30, 176, 18, 246, 63, 50, 218, 237, 227, 2, 33, 0, 227, 114, 79, 111, 57, 37, 192, 233, 231, 6, 90, 219, 141, 70, 67, 60, 166, 66, 73, 155, 105, 89, 137, 211, 113, 63, 72, 170, 243, 237, 36, 55 }
    let sct_ed = [111]u8{ 0, 131, 111, 241, 132, 231, 180, 27, 30, 19, 203, 95, 216, 159, 161, 222, 152, 219, 186, 185, 158, 157, 41, 24, 145, 63, 244, 59, 134, 165, 199, 194, 19, 0, 0, 1, 139, 207, 229, 104, 123, 0, 0, 8, 7, 0, 64, 30, 200, 4, 163, 12, 12, 217, 237, 121, 197, 29, 82, 34, 76, 43, 238, 224, 42, 234, 251, 37, 75, 24, 19, 25, 152, 3, 178, 235, 13, 100, 188, 231, 43, 239, 95, 197, 189, 114, 64, 53, 36, 127, 9, 107, 41, 220, 166, 189, 81, 42, 253, 151, 73, 173, 129, 146, 102, 118, 26, 219, 134, 44, 7 }
    let issuer_hash = [32]u8{ 83, 92, 111, 142, 181, 17, 245, 217, 102, 161, 176, 114, 93, 249, 46, 191, 39, 81, 79, 171, 169, 69, 203, 189, 105, 142, 35, 172, 114, 196, 23, 87 }
    var ec_key: sign.P256PublicKey = zero
    ec_key.bytes = [65]u8{ 4, 71, 28, 62, 117, 140, 73, 4, 40, 91, 186, 126, 83, 17, 142, 208, 245, 36, 173, 235, 7, 87, 210, 91, 210, 248, 231, 176, 215, 109, 250, 113, 76, 221, 82, 15, 122, 202, 138, 139, 145, 122, 204, 55, 245, 29, 232, 240, 201, 187, 227, 173, 133, 131, 130, 231, 2, 220, 37, 161, 45, 9, 247, 168, 88 }
    var ed_key: sign.Ed25519PublicKey = zero
    ed_key.bytes = [32]u8{ 3, 161, 7, 191, 243, 206, 16, 190, 29, 112, 221, 24, 231, 75, 192, 153, 103, 228, 214, 48, 155, 165, 13, 95, 29, 220, 134, 100, 18, 85, 49, 184 }
    var scratch: [256]u8 = zero
    let (s, e) = x509.ct_verify(sct_ec[0..], x509.PublicKey{ P256: ec_key }, cert[0..], scratch[..0usize], scratch[0..])
    if e != ok || s.timestamp != 1700000000123u64 || s.version != 0u8 || s.extensions.len != 0usize || s.hash_algorithm != 4u8 || s.signature_algorithm != 3u8 { ret 9i32 }
    let log_id = [32]u8{ 131, 111, 241, 132, 231, 180, 27, 30, 19, 203, 95, 216, 159, 161, 222, 152, 219, 186, 185, 158, 157, 41, 24, 145, 63, 244, 59, 134, 165, 199, 194, 19 }
    if !same(s.log_id[0..], log_id[0..]) { ret 9i32 }
    let (_, precert) = x509.ct_verify(sct_ed[0..], x509.PublicKey{ Ed25519: ed_key }, cert[..40usize], issuer_hash[0..], scratch[0..])
    if precert != ok { ret 9i32 }
    // The wrong entry, the wrong key kind and a flipped signature byte all fail.
    let (_, wrong_entry) = x509.ct_verify(sct_ec[0..], x509.PublicKey{ P256: ec_key }, cert[..69usize], scratch[..0usize], scratch[0..])
    if wrong_entry != x509.BadSctSignature { ret 9i32 }
    let (_, wrong_kind) = x509.ct_verify(sct_ec[0..], x509.PublicKey{ Ed25519: ed_key }, cert[0..], scratch[..0usize], scratch[0..])
    if wrong_kind != x509.InvalidSct { ret 9i32 }
    var flipped = sct_ed
    flipped[110usize] = flipped[110usize] ^ 1u8
    let (_, bad) = x509.ct_verify(flipped[0..], x509.PublicKey{ Ed25519: ed_key }, cert[..40usize], issuer_hash[0..], scratch[0..])
    if bad != x509.BadSctSignature { ret 9i32 }
    let (_, truncated) = x509.ct_parse(sct_ec[..46usize])
    if truncated != x509.InvalidSct { ret 9i32 }
    ret 0i32
}

// 10: demangling.
fn check_demangle() -> i32 {
    let (s, e) = debug.demangle_neper("e.data.treap.insert")
    if e != ok || !str.eq(s.module, "e.data.treap") || !str.eq(s.function, "insert") { ret 10i32 }
    let (s2, second_error) = debug.demangle_neper("main.main")
    if second_error != ok || !str.eq(s2.module, "main") || !str.eq(s2.function, "main") { ret 10i32 }
    let (_, third_error) = debug.demangle_neper("nodot")
    if third_error != debug.Malformed { ret 10i32 }
    var dst: [200]u8 = zero
    let (text0, e0) = debug.demangle("_Z3fooi", dst[0..])
    if e0 != ok || !str.eq(text0, "foo(int)") { ret 10i32 }
    let (text1, e1) = debug.demangle("_Z1fv", dst[0..])
    if e1 != ok || !str.eq(text1, "f()") { ret 10i32 }
    let (text2, e2) = debug.demangle("_ZN3foo3barEv", dst[0..])
    if e2 != ok || !str.eq(text2, "foo::bar()") { ret 10i32 }
    let (text3, e3) = debug.demangle("_Z3addPKci", dst[0..])
    if e3 != ok || !str.eq(text3, "add(char const*, int)") { ret 10i32 }
    let (text4, e4) = debug.demangle("_ZN2ns5ClassC1Ev", dst[0..])
    if e4 != ok || !str.eq(text4, "ns::Class::Class()") { ret 10i32 }
    let (text5, e5) = debug.demangle("_ZN2ns5ClassD1Ev", dst[0..])
    if e5 != ok || !str.eq(text5, "ns::Class::~Class()") { ret 10i32 }
    let (_, e6) = debug.demangle("_Z4swapRiS_", dst[0..])
    if e6 != debug.Unsupported { ret 10i32 }
    let (text7, e7) = debug.demangle("_ZN2ns3sumEPKdm", dst[0..])
    if e7 != ok || !str.eq(text7, "ns::sum(double const*, unsigned long)") { ret 10i32 }
    let (text8, e8) = debug.demangle("_Z5printPKcz", dst[0..])
    if e8 != ok || !str.eq(text8, "print(char const*, ...)") { ret 10i32 }
    let (text9, e9) = debug.demangle("_ZSt4cout", dst[0..])
    if e9 != ok || !str.eq(text9, "std::cout") { ret 10i32 }
    let (_, e10) = debug.demangle("_Z6handleRK3FooOS_", dst[0..])
    if e10 != debug.Unsupported { ret 10i32 }
    let (_, e11) = debug.demangle("_Z3maxIiET_S0_S0_", dst[0..])
    if e11 != debug.Unsupported { ret 10i32 }
    let (text12, e12) = debug.demangle("_Z1gbhstjlmxyfdew", dst[0..])
    if e12 != ok || !str.eq(text12, "g(bool, unsigned char, short, unsigned short, unsigned int, long, unsigned long, long long, unsigned long long, float, double, long double, wchar_t)") { ret 10i32 }
    let (text13, e13) = debug.demangle("_ZN1a1b1cEPN1d1eE", dst[0..])
    if e13 != ok || !str.eq(text13, "a::b::c(d::e*)") { ret 10i32 }
    let (plain, plain_error) = debug.demangle("e.io.print", dst[0..])
    if plain_error != ok || !str.eq(plain, "e.io.print") { ret 10i32 }
    let (_, short_error) = debug.demangle("_Z3fooi", dst[..5usize])
    if short_error != debug.TooSmall { ret 10i32 }
    ret 0i32
}

// 11: grid BFS, rays and Theta* over a walled 12 x 9 grid.
type Walls = struct { w: usize, h: usize, cells: []const u8 }

fn wall_free(ctx: *Walls, c: grid.Coord) -> bool {
    if c.q < 0i32 || c.r < 0i32 || usize(c.q) >= ctx.w || usize(c.r) >= ctx.h { ret false }
    ret ctx.cells[usize(c.r) * ctx.w + usize(c.q)] == 0u8
}

fn coord_fnv(cells: []const grid.Coord, n: usize) -> u64 {
    var h = fnv_start()
    var i = 0usize
    while i < n {
        h = fnv_step(h, i64(cells[i].q) * 100i64 + i64(cells[i].r))
        i += 1usize
    }
    ret h
}

fn check_grid() -> i32 {
    var cells: [108]u8 = zero
    cells[16usize] = 1u8
    cells[28usize] = 1u8
    cells[40usize] = 1u8
    cells[52usize] = 1u8
    cells[64usize] = 1u8
    cells[76usize] = 1u8
    cells[54usize] = 1u8
    cells[55usize] = 1u8
    cells[44usize] = 1u8
    cells[56usize] = 1u8
    cells[68usize] = 1u8
    cells[80usize] = 1u8
    cells[92usize] = 1u8
    cells[104usize] = 1u8
    var walls = Walls { w: 12usize, h: 9usize, cells: cells[0..] }
    var parent: [108]u32 = zero
    var queue: [108]u32 = zero
    var out: [108]grid.Coord = zero
    let (n, e) = grid.path_bfs[Walls](12usize, 9usize, &walls, wall_free, grid.coord(0i32, 0i32), grid.coord(11i32, 8i32), parent[0..], queue[0..], out[0..])
    if e != ok || n != 20usize || coord_fnv(out[0..], n) != 10194694847075118795u64 { ret 11i32 }
    let (blocked, blocked_error) = grid.path_bfs[Walls](12usize, 9usize, &walls, wall_free, grid.coord(0i32, 0i32), grid.coord(4i32, 3i32), parent[0..], queue[0..], out[0..])
    if blocked_error != ok || blocked != 0usize { ret 11i32 }
    let (_, short) = grid.path_bfs[Walls](12usize, 9usize, &walls, wall_free, grid.coord(0i32, 0i32), grid.coord(11i32, 8i32), parent[0..], queue[0..], out[..3usize])
    if short != grid.Bounds { ret 11i32 }
    let (ray0, ray_error0) = grid.ray_cells(grid.coord(0i32, 0i32), grid.coord(5i32, 2i32), out[0..])
    if ray_error0 != ok || ray0 != 8usize || coord_fnv(out[0..], ray0) != 4295675604095810181u64 { ret 11i32 }
    let (ray1, ray_error1) = grid.ray_cells(grid.coord(3i32, 4i32), grid.coord(0i32, 0i32), out[0..])
    if ray_error1 != ok || ray1 != 8usize || coord_fnv(out[0..], ray1) != 7317054877972677209u64 { ret 11i32 }
    let (ray2, ray_error2) = grid.ray_cells(grid.coord(2i32, 2i32), grid.coord(2i32, 6i32), out[0..])
    if ray_error2 != ok || ray2 != 5usize || coord_fnv(out[0..], ray2) != 16417072628174841675u64 { ret 11i32 }
    let (ray3, ray_error3) = grid.ray_cells(grid.coord(1i32, 1i32), grid.coord(4i32, 4i32), out[0..])
    if ray_error3 != ok || ray3 != 7usize || coord_fnv(out[0..], ray3) != 3894580453576809671u64 { ret 11i32 }
    let (ray4, ray_error4) = grid.ray_cells(grid.coord(0i32, 3i32), grid.coord(7i32, 0i32), out[0..])
    if ray_error4 != ok || ray4 != 11usize || coord_fnv(out[0..], ray4) != 2719571510104552109u64 { ret 11i32 }
    var g: [108]f64 = zero
    var closed: [108]u8 = zero
    var heap_key: [1024]f64 = zero
    var heap_node: [1024]u32 = zero
    var scratch: [32]grid.Coord = zero
    let (theta0, length0, theta_error0) = grid.path_theta_star[Walls](12usize, 9usize, &walls, wall_free, grid.coord(0i32, 0i32), grid.coord(11i32, 8i32), g[0..], parent[0..], closed[0..], heap_key[0..], heap_node[0..], scratch[0..], out[0..])
    if theta_error0 != ok || theta0 != 5usize || coord_fnv(out[0..], theta0) != 5203070464365190363u64 { ret 12i32 }
    if mem.bitcast[u64](length0) != 4624786716332412616u64 { ret 12i32 }
    let (theta1, length1, theta_error1) = grid.path_theta_star[Walls](12usize, 9usize, &walls, wall_free, grid.coord(1i32, 8i32), grid.coord(11i32, 0i32), g[0..], parent[0..], closed[0..], heap_key[0..], heap_node[0..], scratch[0..], out[0..])
    if theta_error1 != ok || theta1 != 6usize || coord_fnv(out[0..], theta1) != 14822287016635279870u64 { ret 12i32 }
    if mem.bitcast[u64](length1) != 4623970519038834585u64 { ret 12i32 }
    let (none, _, none_error) = grid.path_theta_star[Walls](12usize, 9usize, &walls, wall_free, grid.coord(0i32, 0i32), grid.coord(4i32, 3i32), g[0..], parent[0..], closed[0..], heap_key[0..], heap_node[0..], scratch[0..], out[0..])
    if none_error != ok || none != 0usize { ret 12i32 }
    ret 0i32
}

// 13: dither, plain and noise-shaped, bit-exact against the replica.
fn check_dither() -> i32 {
    var xs: [64]f32 = zero
    var state = 12345u64
    var i = 0usize
    while i < 64usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        xs[i] = f32(f64(i64(state >> 33u32) - 1073741824i64) / 1073741824.0f64)
        i += 1usize
    }
    var r = rand.pcg64(7u64, 11u64)
    var d = audio.dither(&r, false)
    var out: [64]i16 = zero
    if audio.dither_block(&d, xs[0..], out[0..]) != ok { ret 13i32 }
    var h = fnv_start()
    i = 0usize
    while i < 64usize {
        h = fnv_step(h, i64(out[i]))
        i += 1usize
    }
    if h != 8866689896194424685u64 || out[0usize] != -25586i16 || out[1usize] != -15375i16 { ret 13i32 }
    var shaped = audio.dither(&r, true)
    if audio.dither_block(&shaped, xs[0..], out[0..]) != ok { ret 13i32 }
    h = fnv_start()
    i = 0usize
    while i < 64usize {
        h = fnv_step(h, i64(out[i]))
        i += 1usize
    }
    if h != 7012123939212494105u64 || out[1usize] != -15376i16 { ret 13i32 }
    if audio.dither_block(&shaped, xs[0..], out[..10usize]) != audio.Truncated { ret 13i32 }
    ret 0i32
}

fn ip(text: str) -> net.Address {
    let (address, e) = net.parse_ip(text)
    if e != ok { os.exit(14i32) }
    ret address
}

// 14: CIDR and private ranges, against ipaddress.
fn check_cidr() -> i32 {
    let (c1, e1) = net.cidr_parse("10.0.0.0/8")
    if e1 != ok || net.cidr_contains(c1, ip("10.200.3.4")) != true { ret 14i32 }
    let (c2, e2) = net.cidr_parse("10.0.0.0/8")
    if e2 != ok || net.cidr_contains(c2, ip("11.0.0.1")) != false { ret 14i32 }
    let (c3, e3) = net.cidr_parse("192.168.1.0/24")
    if e3 != ok || net.cidr_contains(c3, ip("192.168.1.255")) != true { ret 14i32 }
    let (c4, e4) = net.cidr_parse("192.168.1.0/24")
    if e4 != ok || net.cidr_contains(c4, ip("192.168.2.0")) != false { ret 14i32 }
    let (c5, e5) = net.cidr_parse("172.16.0.0/12")
    if e5 != ok || net.cidr_contains(c5, ip("172.31.255.255")) != true { ret 14i32 }
    let (c6, e6) = net.cidr_parse("172.16.0.0/12")
    if e6 != ok || net.cidr_contains(c6, ip("172.32.0.0")) != false { ret 14i32 }
    let (c7, e7) = net.cidr_parse("2001:db8::/32")
    if e7 != ok || net.cidr_contains(c7, ip("2001:db8:ffff::1")) != true { ret 14i32 }
    let (c8, e8) = net.cidr_parse("2001:db8::/32")
    if e8 != ok || net.cidr_contains(c8, ip("2001:db9::1")) != false { ret 14i32 }
    let (c9, e9) = net.cidr_parse("fe80::/10")
    if e9 != ok || net.cidr_contains(c9, ip("febf::1")) != true { ret 14i32 }
    let (c10, e10) = net.cidr_parse("fe80::/10")
    if e10 != ok || net.cidr_contains(c10, ip("fec0::1")) != false { ret 14i32 }
    let (c11, e11) = net.cidr_parse("1.2.3.4")
    if e11 != ok || net.cidr_contains(c11, ip("1.2.3.4")) != true { ret 14i32 }
    let (c12, e12) = net.cidr_parse("1.2.3.4")
    if e12 != ok || net.cidr_contains(c12, ip("1.2.3.5")) != false { ret 14i32 }
    let (c13, e13) = net.cidr_parse("::/0")
    if e13 != ok || net.cidr_contains(c13, ip("1234::")) != true { ret 14i32 }
    let (c14, e14) = net.cidr_parse("10.0.0.0/8")
    if e14 != ok || net.cidr_contains(c14, ip("::1")) != false { ret 14i32 }
    let (_, bad_prefix) = net.cidr_parse("10.0.0.0/33")
    if bad_prefix != net.Failed { ret 14i32 }
    let (_, bad_text) = net.cidr_parse("10.0.0/8")
    if bad_text != net.Failed { ret 14i32 }
    let (link_local, link_local_error) = net.cidr_parse("fe80::/10")
    if link_local_error != ok || link_local.prefix != 10u8 { ret 14i32 }
    if net.is_private(ip("10.1.2.3")) != true { ret 15i32 }
    if net.is_private(ip("172.16.5.5")) != true { ret 15i32 }
    if net.is_private(ip("172.15.255.255")) != false { ret 15i32 }
    if net.is_private(ip("192.168.0.1")) != true { ret 15i32 }
    if net.is_private(ip("192.169.0.1")) != false { ret 15i32 }
    if net.is_private(ip("127.0.0.1")) != true { ret 15i32 }
    if net.is_private(ip("169.254.169.254")) != true { ret 15i32 }
    if net.is_private(ip("8.8.8.8")) != false { ret 15i32 }
    if net.is_private(ip("::1")) != true { ret 15i32 }
    if net.is_private(ip("fe80::1")) != true { ret 15i32 }
    if net.is_private(ip("fd12::1")) != true { ret 15i32 }
    if net.is_private(ip("fc00::")) != true { ret 15i32 }
    if net.is_private(ip("fbff::1")) != false { ret 15i32 }
    if net.is_private(ip("2001:db8::1")) != false { ret 15i32 }
    if net.is_private(ip("::ffff:10.0.0.1")) != true { ret 15i32 }
    if net.is_private(ip("::ffff:8.8.8.8")) != false { ret 15i32 }
    ret 0i32
}

// 16: SameSite, CORS and CSP.
fn check_http() -> i32 {
    if http.cookie_same_site(.Strict, true, true, .Post, false) != true { ret 16i32 }
    if http.cookie_same_site(.Strict, true, false, .Get, true) != false { ret 16i32 }
    if http.cookie_same_site(.Lax, true, false, .Get, true) != true { ret 16i32 }
    if http.cookie_same_site(.Lax, true, false, .Post, true) != false { ret 16i32 }
    if http.cookie_same_site(.Lax, true, false, .Get, false) != false { ret 16i32 }
    if http.cookie_same_site(.None, true, false, .Post, false) != true { ret 16i32 }
    if http.cookie_same_site(.None, false, false, .Get, true) != false { ret 16i32 }
    if http.cookie_same_site(.Default, true, false, .Get, true) != true { ret 16i32 }
    if http.cookie_same_site(.Default, true, false, .Delete, true) != false { ret 16i32 }
    if http.cookie_same_site_parse("strict") != .Strict || http.cookie_same_site_parse("LAX") != .Lax || http.cookie_same_site_parse("none") != .None || http.cookie_same_site_parse("other") != .Default { ret 16i32 }
    if !str.eq(http.cookie_same_site_text(.Lax), "SameSite=Lax") || !str.eq(http.cookie_same_site_text(.Default), "") { ret 16i32 }
    let origins = [2]str{ "https://app.example", "https://admin.example" }
    let methods = [3]str{ "GET", "POST", "DELETE" }
    let headers = [2]str{ "Content-Type", "X-Token" }
    let policy = http.CorsPolicy { origins: origins[0..], methods: methods[0..], headers: headers[0..], credentials: true }
    var out: [8]http.Header = zero
    let (n, e) = http.cors_preflight(&policy, "https://app.example", "POST", "content-type, x-token", out[0..])
    if e != ok || n != 5usize { ret 17i32 }
    if !str.eq(out[0usize].name, "Access-Control-Allow-Origin") || !str.eq(out[0usize].value, "https://app.example") { ret 17i32 }
    if !str.eq(out[1usize].name, "Access-Control-Allow-Methods") || !str.eq(out[1usize].value, "POST") { ret 17i32 }
    if !str.eq(out[2usize].name, "Access-Control-Allow-Headers") || !str.eq(out[2usize].value, "content-type, x-token") { ret 17i32 }
    if !str.eq(out[3usize].name, "Access-Control-Allow-Credentials") || !str.eq(out[3usize].value, "true") { ret 17i32 }
    if !str.eq(out[4usize].name, "Vary") || !str.eq(out[4usize].value, "Origin") { ret 17i32 }
    let (_, bad_origin) = http.cors_preflight(&policy, "https://evil.example", "POST", "", out[0..])
    if bad_origin != http.Denied { ret 17i32 }
    let (_, bad_method) = http.cors_preflight(&policy, "https://app.example", "PUT", "", out[0..])
    if bad_method != http.Denied { ret 17i32 }
    let (_, bad_header) = http.cors_preflight(&policy, "https://app.example", "GET", "X-Token, Authorization", out[0..])
    if bad_header != http.Denied { ret 17i32 }
    let star = [1]str{ "*" }
    let open = http.CorsPolicy { origins: star[0..], methods: methods[0..], headers: star[0..], credentials: false }
    let (m, open_error) = http.cors_preflight(&open, "https://anyone.example", "GET", "Authorization", out[0..])
    if open_error != ok || m != 4usize || !str.eq(out[0usize].value, "*") || !str.eq(out[3usize].name, "Vary") { ret 17i32 }
    var r = rand.pcg64(99u64, 5u64)
    var nonce_dst: [32]u8 = zero
    let (nonce, nonce_error) = http.csp_nonce(&r, nonce_dst[0..])
    if nonce_error != ok || !str.eq(nonce, "k1Vs4IUlOZ2s2U02+z6yTQ==") { ret 18i32 }
    var csp = http.CspPolicy { default_src: "'self'", script_src: "'self'", style_src: "", img_src: "'self' data:", connect_src: "", frame_ancestors: "'none'", nonce: nonce, strict_dynamic: true }
    var header_dst: [256]u8 = zero
    let (header, header_error) = http.csp_header(&csp, header_dst[0..])
    if header_error != ok || !str.eq(header, "default-src 'self'; script-src 'self' 'nonce-k1Vs4IUlOZ2s2U02+z6yTQ==' 'strict-dynamic'; img-src 'self' data:; frame-ancestors 'none'") { ret 18i32 }
    let (_, tight) = http.csp_header(&csp, header_dst[..20usize])
    if tight != http.TooLarge { ret 18i32 }
    ret 0i32
}

// 19: PKCE (RFC 7636 Appendix B, then a generated pair) and WebAuthn
// assertions signed in Python.
fn check_auth() -> i32 {
    var challenge_dst: [43]u8 = zero
    let (b, b_error) = auth.pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", challenge_dst[0..])
    if b_error != ok || !str.eq(b, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM") { ret 19i32 }
    var r = rand.pcg64(3u64, 4u64)
    var verifier_dst: [50]u8 = zero
    let (verifier, verifier_error) = auth.pkce_verifier_seeded(&r, verifier_dst[0..])
    if verifier_error != ok || !str.eq(verifier, "e~EnUqEMNzHWnx1qEREUO.oiFWq97Hihxj-l-36HQQZnqJ1TU1") { ret 19i32 }
    let (challenge, challenge_error) = auth.pkce_challenge(verifier, challenge_dst[0..])
    if challenge_error != ok || !str.eq(challenge, "aYfZ1aGZp5WNSZgSFRTquhgfJr7EYYw-tBfhDv-nWPw") { ret 19i32 }
    let (_, short_error) = auth.pkce_verifier(verifier_dst[..42usize])
    if short_error != auth.Invalid { ret 19i32 }
    var secure_verifier_dst: [43]u8 = zero
    let (secure_verifier, secure_challenge, pkce_error) = auth.pkce(secure_verifier_dst[0..], challenge_dst[0..])
    if pkce_error != ok || secure_verifier.len < 43usize || secure_verifier.len > 128usize || secure_challenge.len != 43usize { ret 19i32 }
    let client = [132]u8{ 123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34, 99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 65, 65, 69, 67, 65, 119, 81, 70, 66, 103, 99, 73, 67, 81, 111, 76, 68, 65, 48, 79, 68, 120, 65, 82, 69, 104, 77, 85, 70, 82, 89, 88, 71, 66, 107, 97, 71, 120, 119, 100, 72, 104, 56, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 115, 58, 47, 47, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103, 105, 110, 34, 58, 102, 97, 108, 115, 101, 125 }
    let bad_client = [129]u8{ 123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34, 99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 65, 65, 69, 67, 65, 119, 81, 70, 66, 103, 99, 73, 67, 81, 111, 76, 68, 65, 48, 79, 68, 120, 65, 82, 69, 104, 77, 85, 70, 82, 89, 88, 71, 66, 107, 97, 71, 120, 119, 100, 72, 104, 56, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 115, 58, 47, 47, 101, 118, 105, 108, 46, 99, 111, 109, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103, 105, 110, 34, 58, 102, 97, 108, 115, 101, 125 }
    let auth_data = [37]u8{ 163, 121, 166, 246, 238, 175, 185, 165, 94, 55, 140, 17, 128, 52, 226, 117, 30, 104, 47, 171, 159, 45, 48, 171, 19, 210, 18, 85, 134, 206, 25, 71, 5, 0, 0, 0, 42 }
    let sig_es = [71]u8{ 48, 69, 2, 33, 0, 212, 193, 35, 134, 107, 219, 202, 148, 17, 151, 0, 208, 4, 64, 10, 84, 115, 225, 182, 24, 203, 128, 111, 27, 130, 156, 196, 149, 86, 137, 60, 75, 2, 32, 78, 239, 10, 73, 132, 142, 91, 8, 168, 102, 160, 126, 92, 55, 185, 233, 131, 194, 193, 38, 181, 17, 113, 194, 191, 147, 191, 77, 158, 184, 115, 39 }
    let sig_ed = [64]u8{ 220, 70, 178, 237, 226, 138, 6, 89, 37, 114, 158, 76, 61, 15, 251, 167, 118, 212, 107, 191, 74, 162, 107, 138, 232, 147, 119, 211, 88, 84, 182, 120, 83, 222, 1, 212, 198, 67, 88, 214, 157, 238, 179, 48, 98, 73, 141, 66, 213, 188, 189, 56, 21, 89, 136, 136, 80, 62, 223, 178, 24, 42, 20, 6 }
    var ec_key: sign.P256PublicKey = zero
    ec_key.bytes = [65]u8{ 4, 71, 28, 62, 117, 140, 73, 4, 40, 91, 186, 126, 83, 17, 142, 208, 245, 36, 173, 235, 7, 87, 210, 91, 210, 248, 231, 176, 215, 109, 250, 113, 76, 221, 82, 15, 122, 202, 138, 139, 145, 122, 204, 55, 245, 29, 232, 240, 201, 187, 227, 173, 133, 131, 130, 231, 2, 220, 37, 161, 45, 9, 247, 168, 88 }
    var ed_key: sign.Ed25519PublicKey = zero
    ed_key.bytes = [32]u8{ 3, 161, 7, 191, 243, 206, 16, 190, 29, 112, 221, 24, 231, 75, 192, 153, 103, 228, 214, 48, 155, 165, 13, 95, 29, 220, 134, 100, 18, 85, 49, 184 }
    var scratch: [128]u8 = zero
    let (a, e) = auth.webauthn_verify(auth_data[0..], client[0..], sig_es[0..], auth.Key{ P256: ec_key }, "example.com", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if e != ok || a.sign_count != 42u32 || !a.user_present || !a.user_verified { ret 20i32 }
    let (_, ed_error) = auth.webauthn_verify(auth_data[0..], client[0..], sig_ed[0..], auth.Key{ Ed25519: ed_key }, "example.com", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if ed_error != ok { ret 20i32 }
    let (_, wrong_origin) = auth.webauthn_verify(auth_data[0..], bad_client[0..], sig_es[0..], auth.Key{ P256: ec_key }, "example.com", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if wrong_origin != auth.BadClientData { ret 20i32 }
    let (_, wrong_rp) = auth.webauthn_verify(auth_data[0..], client[0..], sig_es[0..], auth.Key{ P256: ec_key }, "example.org", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if wrong_rp != auth.BadRpId { ret 20i32 }
    let (_, wrong_challenge) = auth.webauthn_verify(auth_data[0..], client[0..], sig_es[0..], auth.Key{ P256: ec_key }, "example.com", "AAAA", "https://example.com", scratch[0..])
    if wrong_challenge != auth.BadClientData { ret 20i32 }
    let (_, swapped) = auth.webauthn_verify(auth_data[0..], client[0..], sig_ed[0..], auth.Key{ P256: ec_key }, "example.com", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if swapped != auth.BadSignature { ret 20i32 }
    var absent = auth_data
    absent[32usize] = 4u8
    let (_, not_present) = auth.webauthn_verify(absent[0..], client[0..], sig_es[0..], auth.Key{ P256: ec_key }, "example.com", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "https://example.com", scratch[0..])
    if not_present != auth.UserNotPresent { ret 20i32 }
    ret 0i32
}

// 21: constrained decoding over a JSON-like grammar, against brute force.
fn check_constrained() -> i32 {
    let lhs = [12]u32{ 8, 8, 8, 8, 9, 9, 11, 11, 10, 10, 12, 12 }
    let rhs = [26]u32{ 9, 10, 6, 7, 0, 1, 0, 11, 1, 6, 5, 8, 6, 5, 8, 4, 11, 2, 3, 2, 12, 3, 8, 8, 4, 12 }
    let rule_start = [13]usize{ 0, 1, 2, 3, 4, 6, 9, 12, 17, 19, 22, 23, 26 }
    let g = parse.grammar(lhs[0..], rhs[0..], rule_start[0..], 8u32)
    var items: [4096]parse.Item = zero
    var sets: [64]usize = zero
    let vocab = [8]u32{ 0, 1, 2, 3, 4, 5, 6, 7 }
    var allowed: [8]bool = zero
    let (count0, e0) = parse.constrained_decode(&g, 8u32, vocab[..0usize], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e0 != ok || count0 != 4usize { ret 21i32 }
    if allowed[0usize] != true { ret 21i32 }
    if allowed[1usize] != false { ret 21i32 }
    if allowed[2usize] != true { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != false { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != true { ret 21i32 }
    if allowed[7usize] != true { ret 21i32 }
    let prefix1 = [1]u32{ 0 }
    let (count1, e1) = parse.constrained_decode(&g, 8u32, prefix1[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e1 != ok || count1 != 2usize { ret 21i32 }
    if allowed[0usize] != false { ret 21i32 }
    if allowed[1usize] != true { ret 21i32 }
    if allowed[2usize] != false { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != false { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != true { ret 21i32 }
    if allowed[7usize] != false { ret 21i32 }
    let prefix2 = [3]u32{ 0, 6, 5 }
    let (count2, e2) = parse.constrained_decode(&g, 8u32, prefix2[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e2 != ok || count2 != 4usize { ret 21i32 }
    if allowed[0usize] != true { ret 21i32 }
    if allowed[1usize] != false { ret 21i32 }
    if allowed[2usize] != true { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != false { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != true { ret 21i32 }
    if allowed[7usize] != true { ret 21i32 }
    let prefix3 = [2]u32{ 2, 7 }
    let (count3, e3) = parse.constrained_decode(&g, 8u32, prefix3[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e3 != ok || count3 != 2usize { ret 21i32 }
    if allowed[0usize] != false { ret 21i32 }
    if allowed[1usize] != false { ret 21i32 }
    if allowed[2usize] != false { ret 21i32 }
    if allowed[3usize] != true { ret 21i32 }
    if allowed[4usize] != true { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != false { ret 21i32 }
    if allowed[7usize] != false { ret 21i32 }
    let prefix4 = [3]u32{ 2, 7, 4 }
    let (count4, e4) = parse.constrained_decode(&g, 8u32, prefix4[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e4 != ok || count4 != 4usize { ret 21i32 }
    if allowed[0usize] != true { ret 21i32 }
    if allowed[1usize] != false { ret 21i32 }
    if allowed[2usize] != true { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != false { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != true { ret 21i32 }
    if allowed[7usize] != true { ret 21i32 }
    let prefix5 = [5]u32{ 0, 6, 5, 2, 3 }
    let (count5, e5) = parse.constrained_decode(&g, 8u32, prefix5[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e5 != ok || count5 != 2usize { ret 21i32 }
    if allowed[0usize] != false { ret 21i32 }
    if allowed[1usize] != true { ret 21i32 }
    if allowed[2usize] != false { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != true { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != false { ret 21i32 }
    if allowed[7usize] != false { ret 21i32 }
    let prefix6 = [2]u32{ 0, 0 }
    let (count6, e6) = parse.constrained_decode(&g, 8u32, prefix6[0..], vocab[0..], allowed[0..], items[0..], sets[0..])
    if e6 != ok || count6 != 0usize { ret 21i32 }
    if allowed[0usize] != false { ret 21i32 }
    if allowed[1usize] != false { ret 21i32 }
    if allowed[2usize] != false { ret 21i32 }
    if allowed[3usize] != false { ret 21i32 }
    if allowed[4usize] != false { ret 21i32 }
    if allowed[5usize] != false { ret 21i32 }
    if allowed[6usize] != false { ret 21i32 }
    if allowed[7usize] != false { ret 21i32 }
    ret 0i32
}

// 22: LPA* and D* Lite replans against fresh breadth-first costs, then the
// one-call PRM against the replica.
fn check_plan() -> i32 {
    var blocked: [80]u8 = zero
    var g: [80]f64 = zero
    var rhs: [80]f64 = zero
    var k1: [2048]f64 = zero
    var k2: [2048]f64 = zero
    var node: [2048]u32 = zero
    var path: [80]u32 = zero
    blocked[26usize] = 1u8
    blocked[43usize] = 1u8
    blocked[56usize] = 1u8
    blocked[13usize] = 1u8
    blocked[46usize] = 1u8
    blocked[3usize] = 1u8
    blocked[76usize] = 1u8
    blocked[33usize] = 1u8
    blocked[66usize] = 1u8
    blocked[23usize] = 1u8
    blocked[36usize] = 1u8
    blocked[53usize] = 1u8
    let (s0, e0) = plan.lpa_star(10usize, 8usize, blocked[0..], g[0..], rhs[0..], k1[0..], k2[0..], node[0..], 0usize, 79usize)
    if e0 != ok { ret 22i32 }
    var s = s0
    let (c0, ce0) = plan.incremental_compute(&s)
    if ce0 != ok || c0 != 26.0f64 { ret 22i32 }
    let (n0, p0) = plan.incremental_path(&s, path[0..])
    if p0 != ok || n0 != 27usize || path[0usize] != 79u32 || path[n0 - 1usize] != 0u32 { ret 22i32 }
    if plan.incremental_block(&s, 63usize, true) != ok { ret 22i32 }
    let (c1, ce1) = plan.incremental_compute(&s)
    if ce1 != ok || c1 != 28.0f64 { ret 22i32 }
    if plan.incremental_block(&s, 23usize, false) != ok { ret 22i32 }
    let (c2, ce2) = plan.incremental_compute(&s)
    if ce2 != ok || c2 != 18.0f64 { ret 22i32 }
    if plan.incremental_block(&s, 16usize, true) != ok { ret 22i32 }
    let (c3, ce3) = plan.incremental_compute(&s)
    if ce3 != ok || c3 != 20.0f64 { ret 22i32 }
    let (n3, p3) = plan.incremental_path(&s, path[0..])
    if p3 != ok || n3 != 21usize { ret 22i32 }
    // Every step of the path is a unit move between open cells.
    var i = 1usize
    while i < n3 {
        let a = usize(path[i - 1usize])
        let b = usize(path[i])
        var d = 0usize
        if b > a { d = b - a } else { d = a - b }
        if (d != 1usize && d != 10usize) || blocked[a] != 0u8 || blocked[b] != 0u8 { ret 22i32 }
        i += 1usize
    }
    if s.expansions == 0usize || s.expansions > 240usize { ret 22i32 }
    // D* Lite from the robot's side.
    i = 0usize
    while i < 80usize {
        blocked[i] = 0u8
        i += 1usize
    }
    blocked[26usize] = 1u8
    blocked[43usize] = 1u8
    blocked[56usize] = 1u8
    blocked[13usize] = 1u8
    blocked[46usize] = 1u8
    blocked[3usize] = 1u8
    blocked[76usize] = 1u8
    blocked[33usize] = 1u8
    blocked[66usize] = 1u8
    blocked[23usize] = 1u8
    blocked[36usize] = 1u8
    blocked[53usize] = 1u8
    let (d0, de0) = plan.dstar_lite(10usize, 8usize, blocked[0..], g[0..], rhs[0..], k1[0..], k2[0..], node[0..], 0usize, 79usize)
    if de0 != ok { ret 23i32 }
    var d = d0
    let (dc0, dce0) = plan.incremental_compute(&d)
    if dce0 != ok || dc0 != 26.0f64 { ret 23i32 }
    if plan.incremental_move(&d, 30usize) != ok || plan.incremental_block(&d, 16usize, true) != ok { ret 23i32 }
    let (dc1, dce1) = plan.incremental_compute(&d)
    if dce1 != ok || dc1 != 25.0f64 { ret 23i32 }
    let (dn1, dp1) = plan.incremental_path(&d, path[0..])
    if dp1 != ok || dn1 != 26usize || path[0usize] != 30u32 || path[dn1 - 1usize] != 79u32 { ret 23i32 }
    if plan.incremental_move(&d, 63usize) != ok || plan.incremental_block(&d, 6usize, true) != ok { ret 23i32 }
    let (dc2, dce2) = plan.incremental_compute(&d)
    if dce2 != ok || dc2 < 1.0e300f64 { ret 23i32 }
    let (dn2, dp2) = plan.incremental_path(&d, path[0..])
    if dp2 != ok || dn2 != 0usize { ret 23i32 }
    if plan.incremental_block(&d, 46usize, false) != ok { ret 23i32 }
    let (dc3, dce3) = plan.incremental_compute(&d)
    if dce3 != ok || dc3 != 11.0f64 { ret 23i32 }
    let (dn3, dp3) = plan.incremental_path(&d, path[0..])
    if dp3 != ok || dn3 != 12usize { ret 23i32 }
    // PRM in one call.
    var xs: [64]f64 = zero
    var ys: [64]f64 = zero
    var parent: [64]u32 = zero
    var cost: [64]f64 = zero
    var adj: [310]u32 = zero
    var heap_key: [2048]f64 = zero
    var heap_node: [2048]u32 = zero
    var closed: [64]u8 = zero
    var p = plan.pool(xs[0..], ys[0..], parent[0..], cost[0..])
    var obs: [4]plan.Circle = zero
    obs[0usize] = plan.Circle { x: 3.0f64, y: 3.0f64, r: 1.2f64 }
    obs[1usize] = plan.Circle { x: 6.0f64, y: 6.5f64, r: 1.5f64 }
    obs[2usize] = plan.Circle { x: 7.5f64, y: 2.5f64, r: 1.0f64 }
    obs[3usize] = plan.Circle { x: 2.5f64, y: 7.5f64, r: 1.0f64 }
    var cfg: plan.Config = zero
    cfg.min_x = 0.0f64
    cfg.min_y = 0.0f64
    cfg.max_x = 10.0f64
    cfg.max_y = 10.0f64
    var rng = rand.pcg64(2024u64, 9u64)
    let (goal, prm_error) = plan.prm(&cfg, obs[0..], &rng, &p, 60usize, 5usize, adj[0..], 0.5f64, 0.5f64, 9.5f64, 9.5f64, heap_key[0..], heap_node[0..], closed[0..])
    if prm_error != ok || goal != 61u32 || mem.bitcast[u64](p.cost[usize(goal)]) != 4625410246376258232u64 { ret 24i32 }
    var hops = 0usize
    var cur = goal
    while cur != plan.NONE {
        hops += 1usize
        cur = p.parent[usize(cur)]
    }
    if hops != 12usize || p.parent[usize(goal)] != 50u32 { ret 24i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_float()
    if code != 0i32 { os.exit(code) }
    code = check_saturating()
    if code != 0i32 { os.exit(code) }
    code = check_pad(a)
    if code != 0i32 { os.exit(code) }
    code = check_intervals()
    if code != 0i32 { os.exit(code) }
    code = check_julian()
    if code != 0i32 { os.exit(code) }
    code = check_observer()
    if code != 0i32 { os.exit(code) }
    code = check_cbc()
    if code != 0i32 { os.exit(code) }
    code = check_gcm()
    if code != 0i32 { os.exit(code) }
    code = check_ct()
    if code != 0i32 { os.exit(code) }
    code = check_demangle()
    if code != 0i32 { os.exit(code) }
    code = check_grid()
    if code != 0i32 { os.exit(code) }
    code = check_dither()
    if code != 0i32 { os.exit(code) }
    code = check_cidr()
    if code != 0i32 { os.exit(code) }
    code = check_http()
    if code != 0i32 { os.exit(code) }
    code = check_auth()
    if code != 0i32 { os.exit(code) }
    code = check_constrained()
    if code != 0i32 { os.exit(code) }
    code = check_plan()
    if code != 0i32 { os.exit(code) }
    try io.print("misc gaps ok\n")
    ret ok
}
